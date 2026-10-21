import copy
import subprocess
import hashlib
import hmac
import json
import os
import shutil
from pathlib import Path
import sys
import threading
import tempfile
import unittest
from unittest.mock import patch
import importlib.util
import urllib.request
import urllib.error
from http.server import ThreadingHTTPServer
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'server'))
from archive_backend.bundle import Bundle, build
from archive_backend.service import ArchiveService,ArchiveError

class Database:
    def __init__(self,bundle):
        self.bundle=bundle;self.profiles={};self.ops={};self.lock=threading.RLock();self.lose_reply=False;self.conflict=False
    def profile(self,account):
        if account not in self.profiles:
            self.profiles[account]={'schema_version':1,'account_id':account,'revision':1,'entitlements':{},'achievements':{},'public':{},
                'save':{'archive':{},'gameplay_stats':{r['field_id']:r['default_value'] for r in self.bundle.configs['player_gameplay_stats']['rows']}}}
        return self.profiles[account]
    def resume(self,a,i):
        op=self.ops[(a,i)]
        return copy.deepcopy({'ok':not op.get('error'),'terminal':op['done'],'done':op['done'],'error':op.get('error'),
            'profile':self.profile(a),'command':op['command'],'has_pass':op['pass'],
            'config_hash':op['hash'],'response':op.get('response')})
    def rpc(self,name,p):
        with self.lock:
            a=p.get('p_account',p.get('p_account_id'));i=p.get('p_id')
            if name in ('archive_sync_config','ensure_player_gameplay_stats'):return {'ok':True}
            if name=='get_fishing_profile':return copy.deepcopy(self.profile(a))
            if name=='archive_online_pending':return []
            if name=='archive_pending':return [{'id':i} for (account,i),op in self.ops.items() if account==a and not op['done']]
            if name=='archive_prepare':
                if (a,i) not in self.ops:
                    c=copy.deepcopy(p['p_command']);c.update(today=20000,day_key='20000')
                    self.ops[(a,i)]={'command':c,'done':False,'fingerprint':p['p_fingerprint'],'hash':p['p_hash'],
                        'pass':self.profile(a)['entitlements'].get('archive_pass',{}).get('active',False)}
                op=self.ops[(a,i)]
                if op['fingerprint']!=p['p_fingerprint']:return {'ok':False,'terminal':True,'error':'archive_id_conflict'}
                return self.resume(a,i)
            if name=='archive_resume':return self.resume(a,i) if (a,i) in self.ops else {'ok':False,'terminal':True,'error':'archive_operation_missing'}
            if name in ('archive_commit','archive_commit_lottery'):
                op=self.ops[(a,i)];profile=self.profile(a)
                if op['done']:return self.resume(a,i)
                if self.conflict:
                    self.conflict=False;profile['revision']+=1;profile['save']['gameplay_stats']['initial_wood']+=100
                if p['p_revision']!=profile['revision']:return {'ok':False,'error':'archive_revision_conflict'}
                if not p['p_error']:
                    profile['save']['archive']=copy.deepcopy(p['p_archive'])
                    if name=='archive_commit_lottery':
                        profile['save']['content_inventory']=copy.deepcopy(p['p_inventory'])
                        op['response']=copy.deepcopy(p['p_response'])
                    for key,delta in p['p_deltas'].items():profile['save']['gameplay_stats'][key]+=delta
                    profile['revision']+=1
                op['done']=True;op['error']=p['p_error']
                if self.lose_reply:self.lose_reply=False;raise TimeoutError('reply lost after commit')
                return self.resume(a,i)
            raise AssertionError(name)

class App:
    account_id_pepper='test-only-fixed-pepper-not-a-real-secret'
    def __init__(self,db):self.rpc_client=db
    def _database_account_id(self,a):return hashlib.sha256(a.encode()).hexdigest()
    def _ensure_gameplay_stats(self,a):self.rpc_client.profile(a)
    def authorized(self,header):return header=='Bearer local-test-only'
    def profile(self,payload):return self._public_response({'profile':self.rpc_client.profile(self._database_account_id(payload['account_id']))},'',payload['account_id'])['profile']
    def _public_response(self,r,a,public):
        r=copy.deepcopy(r)
        if r.get('profile'):r['profile']['account_id']=public
        return r

class ArchiveTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.lua=os.environ.get('LUA_EXECUTABLE') or shutil.which('lua5.1') or shutil.which('lua')
        if not cls.lua:
            raise RuntimeError('Set LUA_EXECUTABLE to run archive settlement tests')
        # Test the current sources, without replacing a game's chosen bundle or
        # its generated HTTP hash. A restored deployment pointer can be older.
        cls.bundle_temp=tempfile.TemporaryDirectory(prefix='archive-backend-test-')
        cls.addClassCleanup(cls.bundle_temp.cleanup)
        cls.game_bundle_before=(ROOT/'scripts/vscripts/config/generated/archive_http_bundle.lua').read_bytes()
        cls.current_before=(ROOT/'server/bundles/current.json').read_bytes()
        destination=Path(cls.bundle_temp.name)
        digest=build(ROOT,destination=destination,update_game_config=False)
        cls.bundle=Bundle(destination/digest)
    def setUp(self):
        self.db=Database(self.bundle);self.app=App(self.db)
        self.service=ArchiveService(self.app,self.bundle,self.lua)
        self.account=self.app._database_account_id('100');self.profile=self.db.profile(self.account);self.n=0
    def command(self,kind,**values):
        self.n+=1
        return {'account_id':'100','config_hash':self.bundle.hash,'command':dict(id='testsession:op:'+str(self.n),kind=kind,**values)}
    def send(self,kind,**values):return self.service.command(self.command(kind,**values))
    def test_separate_bundle_build_includes_lottery_without_switching_game(self):
        self.assertIn('lottery_pool_definitions',self.bundle.configs)
        self.assertTrue((self.bundle.directory/'systems/lottery_http_settlement.lua').is_file())
        self.assertTrue((self.bundle.directory/'config/content_id_aliases.lua').is_file())
        self.assertEqual((ROOT/'scripts/vscripts/config/generated/archive_http_bundle.lua').read_bytes(),self.game_bundle_before)
        self.assertEqual((ROOT/'server/bundles/current.json').read_bytes(),self.current_before)
    def test_endless_floor_backfill_is_atomic_and_idempotent(self):
        self.profile['save']['archive']['endless_best_wave']=461
        before=copy.deepcopy(self.profile['save']['gameplay_stats'])
        command=self.command('endless_reconcile')
        self.db.lose_reply=True
        # A transport failure after commit must never double-apply rewards.
        try: self.service.command(command)
        except TimeoutError: pass
        self.db.lose_reply=False
        self.assertTrue(self.service.command(command)['ok'])
        current=self.profile['save']
        self.assertEqual(sum(bool(current['archive']['completed'].get('endless_'+str(i))) for i in range(51,83)),32)
        self.assertFalse(current['archive']['completed'].get('endless_1'))
        self.assertEqual(current['gameplay_stats']['hero_attribute_bonus_pct']-before['hero_attribute_bonus_pct'],52)
        self.assertEqual(current['gameplay_stats']['hero_damage_wood_flat']-before['hero_damage_wood_flat'],2)
        self.assertEqual(current['gameplay_stats']['hero_attributes_per_damage']-before['hero_attributes_per_damage'],13)
        settled=copy.deepcopy(current['gameplay_stats'])
        self.assertTrue(self.send('endless_reconcile')['ok'])
        self.assertEqual(current['gameplay_stats'],settled)

    def test_endless_reconcile_rejects_client_progress(self):
        with self.assertRaises(ArchiveError):
            self.service.command(self.command('endless_reconcile',wave=461))
        self.assertFalse(self.profile['save']['archive'].get('completed'))

    def test_endless_floor_strict_boundary(self):
        self.assertTrue(self.send('endless',wave=10,difficulty=10)['ok'])
        self.assertFalse(self.profile['save']['archive']['completed'].get('endless_51'))
        self.assertTrue(self.send('endless',wave=11,difficulty=10)['ok'])
        self.assertTrue(self.profile['save']['archive']['completed']['endless_51'])

    def test_clear_and_lost_response(self):
        payload=self.command('clear',difficulty_id='n1',count=1)
        self.db.lose_reply=True
        with self.assertRaises(TimeoutError):self.service.command(payload)
        result=self.service.command(payload)
        self.assertTrue(result['ok']);self.assertEqual(self.profile['save']['archive']['clear_counts']['n1'],1)
        self.assertEqual(result['profile']['account_id'],'100')
    def test_building_purchase_and_retry(self):
        self.profile['save']['archive']['buildings']={'faith':4000,'levels':{},'earned_by_day':{}}
        payload=self.command('building_upgrade',item_id='building_01',expected_level=0)
        self.db.lose_reply=True
        with self.assertRaises(TimeoutError): self.service.command(payload)
        self.assertTrue(self.service.command(payload)['ok'])
        self.assertEqual(self.profile['save']['archive']['buildings']['faith'],1000)
        self.assertEqual(self.profile['save']['gameplay_stats']['technology_wood_cost_refund_pct'],5)
        self.assertFalse(self.send('building_upgrade',item_id='building_01',expected_level=0)['ok'])
        self.assertFalse(self.send('building_upgrade',item_id='building_01',expected_level=1)['ok'])
        for values in ({'item_id':'building_01','expected_level':5},
                       {'item_id':'missing','expected_level':0},
                       {'item_id':'building_01','expected_level':1,'cost':0}):
            with self.assertRaises(ArchiveError): self.send('building_upgrade',**values)
    def test_faith_cheat_persists_and_upgrades(self):
        payload=self.command('faith_cheat',amount=15000)
        with self.assertRaises(ArchiveError): self.service.command(payload)
        self.profile['save']['archive']['buildings']={'faith':15000,'levels':{},'earned_by_day':{}}
        for level in range(5):
            self.assertTrue(self.send('building_upgrade',item_id='building_01',expected_level=level)['ok'])
        self.assertEqual(self.profile['save']['archive']['buildings']['faith'],0)
        self.assertEqual(self.profile['save']['gameplay_stats']['technology_wood_cost_refund_pct'],25)
        self.assertEqual(self.profile['save']['archive']['buildings']['earned_by_day'],{})
        for amount in (0,-1,1.5,True,1000000001,'3000'):
            with self.assertRaises(ArchiveError): self.send('faith_cheat',amount=amount)
    def test_faith_daily_cap_no_pass_bonus(self):
        self.profile['entitlements']['archive_pass']={'active':True}
        for n in range(12):
            payload=self.command('clear',difficulty_id='n1',count=1,day_key='99999')
            payload['command']['id']='faithmatch'+str(n)+':clear'
            self.assertTrue(self.service.command(payload)['ok'])
        s=self.profile['save']['archive']['buildings']
        self.assertEqual(s['faith'],3000)
        self.assertEqual(s['earned_by_day'],{'20000':3000})
    def test_conflict_preserves_other_writer(self):
        before=self.profile['save']['gameplay_stats']['initial_wood'];self.db.conflict=True
        self.assertTrue(self.send('clear',difficulty_id='n1',count=1)['ok'])
        # The same atomic clear awards N1's 50 wood and the first-win welfare's
        # 10 wood, while preserving the concurrent writer's 100 wood.
        self.assertEqual(self.profile['save']['gameplay_stats']['initial_wood'],before+100+50+10)
        self.assertTrue(self.profile['save']['archive']['completed']['clear_n1_1'])
        self.assertTrue(self.profile['save']['archive']['completed']['welfare_victory_01'])
    def test_rejects_untrusted_fields_and_config(self):
        for c in (dict(kind='online_checkpoint',actual_seconds=100),dict(kind='social_ticket_cheat'),
            dict(kind='social_draw',pool_id='friend',roll=0),dict(kind='clear',difficulty_id='n1',count=20),
            dict(kind='challenge',challenge_id='hunt_01',kill_sequence=1,difficulty_id='n1')):
            with self.assertRaises(ArchiveError):self.service.command(self.command(**c))
        payload=self.command('boss_kill');payload['config_hash']='0'*64
        self.assertEqual(self.service.command(payload)['error'],'archive_config_mismatch')
    def test_id_conflict(self):
        payload=self.command('clear',difficulty_id='n1',count=1);self.service.command(payload)
        payload['command']['difficulty_id']='n2'
        self.assertEqual(self.service.command(payload)['error'],'archive_id_conflict')
    def test_all_archive_rewards(self):
        self.assertTrue(self.send('boss_kill')['ok'])
        for key in ('shadow_1','hunt_01','cage_1'):
            if key not in self.bundle.tables['archive_challenge_definitions']:
                key=next(k for k,v in self.bundle.tables['archive_challenge_definitions'].items() if v['reward_kind']=='cage')
            self.assertTrue(self.send('challenge',challenge_id=key,kill_sequence=self.n+1,difficulty_id='n10')['ok'],key)
        self.assertTrue(self.send('endless',wave=1,difficulty=1)['ok'])
        self.assertTrue(self.send('daily_init')['ok'])
        self.assertTrue(self.send('daily_claim',target_day=20000)['ok'])
        self.assertFalse(self.send('daily_claim',target_day=20000)['ok'])
        s=self.profile['save']['archive'];s['social_tickets']={'yitie':3,'invitation':3,'blessing_ticket':3}
        for pool in ('friend','ex','beast'):
            self.assertTrue(self.send('social_draw',pool_id=pool)['ok'])
        s=self.profile['save']['archive'];s['online']={'actual_seconds':36000,'map_seconds':36000,'coins':600,'map_level':0,'work_levels':{},'cursors':{}}
        self.assertTrue(self.send('work_upgrade',item_id='work_01',expected_level=0)['ok'])
        self.assertFalse(self.send('work_upgrade',item_id='work_01',expected_level=0)['ok'])
        self.assertFalse(self.send('promotion',fragment_id='fragment_01')['ok'])
    def test_worker_online_and_pass(self):
        result=self.service.settle(copy.deepcopy(self.profile),dict(id='db:online:1',kind='online_checkpoint',session='db:1',actual_seconds=1800,map_seconds=3600),False)
        self.assertTrue(result['ok']);self.assertEqual(result['archive']['online']['map_level'],1)
        self.assertEqual(result['archive']['online']['coins'],30)
    def test_two_players_isolated(self):
        self.send('clear',difficulty_id='n1',count=1)
        self.assertEqual(self.db.profile(self.app._database_account_id('200'))['save']['archive'],{})

    def test_cooperative_challenge_base_drops_and_personal_entitlements(self):
        self.assertTrue(self.service.shared_challenge_roll(self.bundle))
        command = {'id': 'sharedmatch:challenge_kind:shadow_4', 'kind': 'challenge',
                   'challenge_id': 'shadow_4', 'kill_sequence': 7, 'difficulty_id': 'n10'}
        profiles = {}
        # VIP and the archive pass are separate entitlements. The existing
        # pass bonus must never be borrowed from another reward recipient.
        for account, vip, archive_pass in [('100', True, True), ('200', False, False),
                                            ('300', True, False), ('400', False, True)]:
            profile = self.db.profile(self.app._database_account_id(account))
            if vip: profile['entitlements']['vip'] = {'active': True}
            if archive_pass: profile['entitlements']['archive_pass'] = {'active': True}
            profiles[account] = profile
        entitlements = {account: copy.deepcopy(profile['entitlements'])
                        for account, profile in profiles.items()}
        for account in ('100', '200', '300', '400'):
            payload = {'account_id': account, 'config_hash': self.bundle.hash,
                       'command': copy.deepcopy(command)}
            self.assertTrue(self.service.command(payload)['ok'])
            before = copy.deepcopy(profiles[account])
            self.assertTrue(self.service.command(payload)['ok'])
            self.assertEqual(profiles[account], before)
        counts = {account: profile['save']['archive']['shadow_counts']
                  for account, profile in profiles.items()}
        self.assertEqual(counts['200'], counts['300'])
        self.assertEqual(counts['100'], counts['400'])
        self.assertEqual(sum(counts['200'].values()), 2)
        self.assertEqual(sum(counts['100'].values()), 3)
        for item, count in counts['200'].items():
            self.assertGreaterEqual(counts['100'].get(item, 0), count)
        for account, profile in profiles.items():
            self.assertEqual(profile['entitlements'], entitlements[account])

    def test_cooperative_challenge_lost_reply_and_restart_preserve_base_roll(self):
        payload = {'account_id': '100', 'config_hash': self.bundle.hash, 'command': {
            'id': 'lostshared:challenge_kind:shadow_1', 'kind': 'challenge',
            'challenge_id': 'shadow_1', 'kill_sequence': 23, 'difficulty_id': 'n10'}}
        self.db.lose_reply = True
        with self.assertRaises(TimeoutError):
            self.service.command(payload)
        saved = copy.deepcopy(self.profile)
        restarted = ArchiveService(self.app, self.bundle, self.lua)
        self.assertTrue(restarted.command(payload)['ok'])
        self.assertEqual(self.profile, saved)
        teammate = copy.deepcopy(payload)
        teammate['account_id'] = '200'
        self.assertTrue(restarted.command(teammate)['ok'])
        other = self.db.profile(self.app._database_account_id('200'))
        self.assertEqual(other['save']['archive']['shadow_counts'],
                         self.profile['save']['archive']['shadow_counts'])

    def test_shared_challenge_rejects_client_reward_and_entitlement_overrides(self):
        for field, value in [('drops', ['shadow_001']), ('roll', 0), ('has_pass', True),
                             ('vip_level', 12), ('score', 100000), ('seed', 1)]:
            payload = self.command('challenge', challenge_id='shadow_4', kill_sequence=11,
                                   difficulty_id='n10', **{field: value})
            with self.assertRaises(ArchiveError):
                self.service.command(payload)
        self.assertEqual(self.profile['save']['archive'], {})
        self.assertEqual(self.db.ops, {})

    def test_non_challenge_random_seeds_remain_account_specific(self):
        original_run = subprocess.run
        captured = []
        def capture(*args, **kwargs):
            captured.append(json.loads(kwargs['input']))
            return original_run(*args, **kwargs)
        command = {'id': 'same_social_request:draw', 'kind': 'social_draw', 'pool_id': 'friend'}
        with patch('archive_backend.service.subprocess.run', side_effect=capture):
            for account in ('100', '200'):
                profile = self.db.profile(self.app._database_account_id(account))
                profile['save']['archive']['social_tickets'] = {'yitie': 1}
                self.assertTrue(self.service.settle(profile, copy.deepcopy(command), False)['ok'])
        self.assertNotEqual(captured[0]['seed'], captured[1]['seed'])
        for payload in captured:
            scope = payload['profile']['account_id'] + ':' + command['id']
            expected = int.from_bytes(hmac.new(self.app.account_id_pepper.encode(),
                scope.encode(), hashlib.sha256).digest()[:4], 'big') % 2147483646 + 1
            self.assertEqual(payload['seed'], expected)

    def test_upgraded_non_challenge_keeps_existing_bundle_requirements(self):
        bundle = Bundle(self.bundle.directory)
        prior_hash = '1' * 64
        bundle.compatible_config_hashes[prior_hash] = {
            'commands': frozenset({'clear'}), 'upgrade_commands': frozenset({'clear'})}
        self.assertFalse((bundle.directory.parent / prior_hash).exists())
        service = ArchiveService(self.app, bundle, self.lua)
        payload = self.command('clear', difficulty_id='n1', count=1)
        payload['config_hash'] = prior_hash
        self.assertTrue(service.command(payload)['ok'])
        self.assertEqual(self.profile['save']['archive']['clear_counts']['n1'], 1)

    def test_old_prepared_challenge_preserves_seed_even_when_reducer_is_upgraded(self):
        # A distinct immutable version records the previous per-account
        # policy. Its sources stay executable by the actual Lua worker.
        data = json.loads((self.bundle.directory / 'bundle.json').read_bytes())
        rule = next(row for row in data['configs']['archive_cooperative_reward_rules']['rows']
                    if row['rule_id'] == 'default')
        rule['shared_challenge_roll'] = False
        raw = json.dumps(data, ensure_ascii=False, sort_keys=True,
                         separators=(',', ':'), allow_nan=False).encode()
        digest = hashlib.sha256(raw).hexdigest()
        directory = self.bundle.directory.parent / digest
        directory.mkdir(exist_ok=True)
        for name in data['sources']:
            destination = directory / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes((self.bundle.directory / name).read_bytes())
        (directory / 'bundle.json').write_bytes(raw)
        old_bundle = Bundle(directory)
        self.assertFalse(self.service.shared_challenge_roll(old_bundle))
        self.assertFalse(self.service.shared_challenge_roll(type('LegacyBundle', (), {'tables': {}})()))
        for upgraded in (False, True):
            app = App(Database(self.bundle))
            old_service = ArchiveService(app, old_bundle, self.lua)
            payload = {'account_id': '100', 'config_hash': old_bundle.hash, 'command': {
                'id': 'legacyseed' + str(upgraded) + ':challenge_kind:shadow_4', 'kind': 'challenge',
                'challenge_id': 'shadow_4', 'kill_sequence': 35, 'difficulty_id': 'n10'}}
            old_service.settle = lambda *args: (_ for _ in ()).throw(TimeoutError('worker stopped'))
            with self.assertRaises(TimeoutError):
                old_service.command(payload)
            current_bundle = Bundle(self.bundle.directory)
            current_bundle.compatible_config_hashes[old_bundle.hash] = {
                'commands': frozenset({'challenge'}),
                'upgrade_commands': frozenset({'challenge'}) if upgraded else frozenset()}
            resumed_service = ArchiveService(app, current_bundle, self.lua)
            captured = []
            original_run = subprocess.run
            def capture(*args, **kwargs):
                captured.append(json.loads(kwargs['input']))
                return original_run(*args, **kwargs)
            with patch('archive_backend.service.subprocess.run', side_effect=capture):
                self.assertTrue(resumed_service.command(payload)['ok'])
            self.assertEqual(len(captured), 1)
            prepared = captured[0]
            expected_scope = prepared['profile']['account_id'] + ':' + prepared['command']['id']
            expected_seed = int.from_bytes(hmac.new(app.account_id_pepper.encode(),
                expected_scope.encode(), hashlib.sha256).digest()[:4], 'big') % 2147483646 + 1
            self.assertEqual(prepared['seed'], expected_seed)
            profile = copy.deepcopy(app.rpc_client.profile(app._database_account_id('100')))
            self.assertTrue(resumed_service.command(payload)['ok'])
            self.assertEqual(app.rpc_client.profile(app._database_account_id('100')), profile)
    def test_concurrent_same_receipt(self):
        payload=self.command('clear',difficulty_id='n1',count=1);results=[]
        workers=[threading.Thread(target=lambda:results.append(self.service.command(payload))) for _ in range(4)]
        for t in workers:t.start()
        for t in workers:t.join()
        self.assertEqual(len(results),4);self.assertTrue(all(r['ok'] for r in results))
        self.assertEqual(self.profile['save']['archive']['clear_counts']['n1'],1)
    def test_http_auth_and_command(self):
        backend=os.environ.get('FISHING_BACKEND_ROOT')
        if not backend:
            raise RuntimeError('Set FISHING_BACKEND_ROOT to the backend/ directory under test')
        sys.path.insert(0,backend)
        from fishing_api import server as module
        self.app.archive=self.service
        server=ThreadingHTTPServer(('127.0.0.1',0),module.make_handler(self.app))
        thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
        def post(path,payload,auth=True):
            request=urllib.request.Request('http://127.0.0.1:'+str(server.server_port)+path,
                data=json.dumps(payload).encode(),headers={'Authorization':'Bearer local-test-only' if auth else 'bad','Content-Type':'application/json'})
            opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
            with opener.open(request,timeout=10) as response:return json.load(response)
        try:
            with self.assertRaises(urllib.error.HTTPError) as error:post('/v1/archive/config',{},False)
            self.assertEqual(error.exception.code,401)
            error.exception.close()
            self.assertEqual(post('/v1/archive/config',{})['config_hash'],self.bundle.hash)
            payload=self.command('clear',difficulty_id='n1',count=1)
            self.assertTrue(post('/v1/archive/command',payload)['ok'])
            self.assertTrue(post('/v1/archive/command',payload)['ok'])
            self.assertEqual(self.profile['save']['archive']['clear_counts']['n1'],1)
            with self.assertRaises(urllib.error.HTTPError) as invalid:post('/v1/archive/command',self.command('social_draw',pool_id='friend',roll=0))
            self.assertEqual(invalid.exception.code,400)
            invalid.exception.close()
        finally:
            server.shutdown();server.server_close();thread.join()
    def test_restart_recovers_prepared_operation(self):
        self.service.settle=lambda *args: (_ for _ in ()).throw(TimeoutError('worker stopped'))
        payload=self.command('clear',difficulty_id='n1',count=1)
        with self.assertRaises(TimeoutError):self.service.command(payload)
        self.service=ArchiveService(self.app,self.bundle,self.service.lua)
        result=self.service.profile({'account_id':'100'})
        self.assertEqual(result['save']['archive']['clear_counts']['n1'],1)

    def test_lottery_atomic_ten_and_lost_reply(self):
        self.profile['save']['content_inventory']={'lottery_ticket':100}
        payload=self.command('lottery_draw',pool_id='map',count=10,request_id='draw_1')
        self.db.lose_reply=True
        with self.assertRaises(TimeoutError):self.service.command(payload)
        result=self.service.command(payload)
        self.assertTrue(result['ok'],result)
        response=result['response'];self.assertEqual(len(response['results']),10)
        self.assertTrue(response['guarantee_satisfied'])
        revision=self.profile['revision'];inventory=copy.deepcopy(self.profile['save']['content_inventory'])
        self.assertLess(inventory['lottery_ticket'],100)
        again=self.service.command(payload)
        self.assertEqual(again['response'],response)
        self.assertEqual(self.profile['revision'],revision)
        self.assertEqual(self.profile['save']['content_inventory'],inventory)
        self.assertEqual(self.profile['save']['archive']['lottery_state']['pools']['map']['draws'],10)

    def _points_draw_fixture(self, quality='ssr', wanted_item=None):
        # Change only trusted, in-memory draw weights. Real item definitions,
        # effects, conversion amounts, reducer, worker and commit path remain.
        pool_id='dragon_knight' if quality=='ur' else 'map'
        definitions=self.bundle.tables['lottery_item_definitions']
        memberships=self.bundle.configs['lottery_pool_items']['rows']
        candidates=[]
        for member in memberships:
            if member.get('enabled') is False or member['pool_id']!=pool_id:
                continue
            ids=definitions if member['item_id']=='*' else [member['item_id']]
            for item_id in ids:
                item=definitions[item_id]
                if (item.get('enabled') is not False and item.get('quality')==quality
                        and item.get('item_type')=='积分道具'
                        and (wanted_item is None or item_id==wanted_item)
                        and item_id!='lottery_ember_of_legacy'
                        and not {'map_level','starjoy_points'}.intersection(item.get('effect_ids',[]))):
                    candidates.append(item)
        self.assertTrue(candidates,'A real enabled pool item is required for '+quality)
        item=sorted(candidates,key=lambda row:row['item_id'])[0]
        configs=copy.deepcopy(self.bundle.configs)
        for row in configs['lottery_quality_weights']['rows']:
            if row['pool_id']==pool_id:
                row['enabled']=True
                row['weight']=10000 if row['quality']==quality else 0
        for row in configs['lottery_pool_items']['rows']:
            if row['pool_id']==pool_id:
                self.assertNotEqual(row['item_id'],'*','Focused fixture needs explicit real pool memberships')
                row['item_weight']=1 if row['item_id']==item['item_id'] else 0
        ticket=self.bundle.tables['lottery_pool_definitions'][pool_id]['ticket_content_id']
        return item,pool_id,ticket,patch.object(self.bundle,'configs',configs)

    def _seed_points_draw_profile(self, ticket):
        stats={row['field_id']:row['default_value'] for row in self.bundle.configs['player_gameplay_stats']['rows']}
        stats.update(starjoy_points=17,starjoy_points_earned=23,starjoy_reward_level=0)
        self.profile['save']={
            'archive':{'unrelated':{'keep':True},'commerce':{
                'balances':{'u_coin':19,'shop_points':7,'shop_gold':29}}},
            'gameplay_stats':stats,
            'content_inventory':{ticket:100,'daily_growth_gem':9,'material_synthesis_gem':41},
        }
        return copy.deepcopy(stats)

    def _assert_points_draw_balance(self, expected, stats):
        self.assertEqual(self.profile['save']['archive']['commerce']['balances'],
                         {'u_coin':19,'shop_points':expected,'shop_gold':29})
        self.assertEqual(self.profile['save']['archive']['unrelated'],{'keep':True})
        for field in ('starjoy_points','starjoy_points_earned','starjoy_reward_level'):
            self.assertEqual(self.profile['save']['gameplay_stats'][field],stats[field],field)
        inventory=self.profile['save']['content_inventory']
        self.assertEqual(inventory['daily_growth_gem'],9)
        self.assertEqual(inventory['material_synthesis_gem'],41,
                         'Existing daily and separately purchased stackable materials are not normalized')

    def test_lottery_points_catalog_has_unique_permanent_ownership(self):
        rows=[row for row in self.bundle.configs['lottery_item_definitions']['rows']
              if row.get('enabled') is not False and row.get('item_type')=='积分道具']
        self.assertEqual(len(rows),97,'Current complete CSV import must participate in the worker bundle')
        self.assertEqual(len({row['item_id'] for row in rows}),97)
        for row in rows:
            with self.subTest(item=row['item_id']):
                self.assertEqual(row['duration_type'],'permanent')
                self.assertEqual(row['max_owned'],1)
                self.assertIsInstance(row['duplicate_points'],int)
                self.assertGreaterEqual(row['duplicate_points'],0)

    def test_lottery_points_first_and_duplicate_credit_only_configured_shop_points(self):
        for quality in ('n','r','sr','ssr','ur'):
            with self.subTest(quality=quality):
                item,pool,ticket,weights=self._points_draw_fixture(quality)
                original_configs=self.bundle.configs
                initial_stats=self._seed_points_draw_profile(ticket)
                with weights:
                    first=self.send('lottery_draw',pool_id=pool,count=1,request_id='points_first_'+quality)
                    self.assertTrue(first['ok'],first)
                    entry=first['response']['results'][0]
                    self.assertEqual(entry['id'],item['item_id'])
                    self.assertFalse(entry['duplicate'])
                    self.assertEqual(entry['converted_points'],0)
                    self.assertEqual(self.profile['save']['content_inventory'][item['item_id']],1)
                    for field,value in zip(item['effect_ids'],item['effect_values']):
                        self.assertAlmostEqual(self.profile['save']['gameplay_stats'][field],
                                               initial_stats[field]+float(value),msg=field)
                    self._assert_points_draw_balance(7,initial_stats)
                    stats_after_first=copy.deepcopy(self.profile['save']['gameplay_stats'])
                    payload=self.command('lottery_draw',pool_id=pool,count=1,request_id='points_duplicate_'+quality)
                    duplicate=self.service.command(payload)
                    self.assertTrue(duplicate['ok'],duplicate)
                    entry=duplicate['response']['results'][0]
                    self.assertEqual(entry['id'],item['item_id'])
                    self.assertTrue(entry['duplicate'])
                    self.assertEqual(entry['converted_currency'],'shop_points')
                    self.assertEqual(entry['converted_points'],item['duplicate_points'])
                    self.assertEqual(self.profile['save']['content_inventory'][item['item_id']],1)
                    self.assertEqual(self.profile['save']['content_inventory'][ticket],98)
                    self.assertEqual(self.profile['save']['gameplay_stats'],stats_after_first,
                                     'A duplicate never reapplies permanent effects or loyalty progress')
                    self._assert_points_draw_balance(7+item['duplicate_points'],initial_stats)
                    after=copy.deepcopy(self.profile)
                    self.assertEqual(self.service.command(payload)['response'],duplicate['response'])
                    self.assertEqual(self.profile,after,'A receipt replay does not debit or credit again')
                self.assertIs(self.bundle.configs,original_configs,'Focused weights cannot leak to another test')

    def test_lottery_points_same_item_ten_and_lost_reply_remain_atomic(self):
        item,pool,ticket,weights=self._points_draw_fixture('ssr')
        initial_stats=self._seed_points_draw_profile(ticket)
        other=self.db.profile(self.app._database_account_id('200'))
        other_before=copy.deepcopy(other)
        with weights:
            payload=self.command('lottery_draw',pool_id=pool,count=10,request_id='points_same_ten')
            self.db.lose_reply=True
            with self.assertRaises(TimeoutError):
                self.service.command(payload)
            committed=copy.deepcopy(self.profile)
            self.service=ArchiveService(self.app,self.bundle,self.lua)
            result=self.service.command(payload)
            self.assertTrue(result['ok'],result)
            rewards=result['response']['results']
            self.assertEqual(len(rewards),10)
            self.assertEqual({row['id'] for row in rewards},{item['item_id']})
            self.assertEqual([row['duplicate'] for row in rewards],[False]+[True]*9)
            self.assertEqual(sum(row['converted_points'] for row in rewards),9*item['duplicate_points'])
            self.assertTrue(all(row['converted_currency']=='shop_points' for row in rewards[1:]))
            self.assertEqual(self.profile['save']['content_inventory'][item['item_id']],1)
            self.assertEqual(self.profile['save']['content_inventory'][ticket],90)
            for field,value in zip(item['effect_ids'],item['effect_values']):
                self.assertAlmostEqual(self.profile['save']['gameplay_stats'][field],
                                       initial_stats[field]+float(value),msg=field)
            self._assert_points_draw_balance(7+9*item['duplicate_points'],initial_stats)
            self.assertEqual(self.profile,committed,'Recovery must reuse the committed draw instead of settling it again')
            self.assertEqual(self.service.command(payload)['response'],result['response'])
            self.assertEqual(self.profile,committed)
            self.assertEqual(other,other_before,'The other account remains unchanged')

    def test_lottery_points_legacy_alias_ownership_only_converts_duplicates(self):
        for canonical_count in (0,1):
            with self.subTest(canonical_count=canonical_count):
                item,pool,ticket,weights=self._points_draw_fixture('n','lottery_nature_crystal')
                initial_stats=self._seed_points_draw_profile(ticket)
                inventory=self.profile['save']['content_inventory']
                inventory['lottery_flame_crystal']=2
                inventory['material_synthesis_gem']=101
                if canonical_count:
                    inventory[item['item_id']]=canonical_count
                before_inventory=copy.deepcopy(inventory)
                with weights:
                    projection=self.service.lottery_snapshot({'account_id':'100','config_hash':self.bundle.hash})
                    selected=next(row for row in projection['snapshots'] if row['selected_pool_id']==pool)
                    public=next(row for row in selected['items'] if row['id']==item['item_id'])
                    self.assertTrue(public['owned'] and public['at_max_owned'],
                                    'Public ownership recognizes aliases before a draw')
                    self.assertEqual(public['owned_count'],1)
                    self.assertEqual(self.profile['save']['content_inventory'],before_inventory,
                                     'Reading aggregate ownership must not migrate raw inventory')
                    payload=self.command('lottery_draw',pool_id=pool,count=1,
                                         request_id='points_alias_'+str(canonical_count))
                    result=self.service.command(payload)
                    self.assertTrue(result['ok'],result)
                    reward=result['response']['results'][0]
                    self.assertEqual(reward['id'],item['item_id'])
                    self.assertTrue(reward['duplicate'],'A legacy alias already owns its canonical permanent item')
                    self.assertEqual(reward['converted_currency'],'shop_points')
                    self.assertEqual(reward['converted_points'],item['duplicate_points'])
                    expected_inventory=copy.deepcopy(before_inventory)
                    expected_inventory[ticket]-=1
                    expected_inventory.pop('lottery_flame_crystal')
                    expected_inventory[item['item_id']]=1
                    self.assertEqual(self.profile['save']['content_inventory'],expected_inventory,
                                     'Successful settlement canonicalizes historical copies exactly once')
                    self.assertEqual(self.profile['save']['gameplay_stats'],initial_stats,
                                     'An alias-owned duplicate cannot reapply permanent effects')
                    balances=self.profile['save']['archive']['commerce']['balances']
                    self.assertEqual(balances,{'u_coin':19,'shop_points':7+(2+canonical_count)*item['duplicate_points'],'shop_gold':29})
                    self.assertEqual(result['response']['unique_points_reconciliation'],{
                        'changed_items':1,'converted_points':(1+canonical_count)*item['duplicate_points'],
                        'converted_currency':'shop_points'})
                    after=copy.deepcopy(self.profile)
                    self.assertEqual(self.service.command(payload)['response'],result['response'])
                    self.assertEqual(self.profile,after)

    def test_lottery_points_reconciles_all_97_historical_items_without_reapplying_stats(self):
        from archive_backend.unique_points import catalog,preview
        item,pool,ticket,weights=self._points_draw_fixture('ssr')
        initial_stats=self._seed_points_draw_profile(ticket)
        rows=[r for r in self.bundle.configs['lottery_item_definitions']['rows']
              if r.get('enabled') is not False and r.get('item_type')=='积分道具']
        inventory=self.profile['save']['content_inventory']
        for row in rows:inventory[row['item_id']]=3
        inventory['lottery_flame_crystal']=2
        inventory['lottery_burst_crystal']=1
        inventory['daily_growth_gem']=999
        inventory['special_lottery_ticket']=23
        before=copy.deepcopy(self.profile)
        expected=preview(inventory,self.profile['save']['archive'],*catalog(self.bundle))
        with weights:
            payload=self.command('lottery_draw',pool_id=pool,count=1,request_id='points_reconcile_all')
            self.db.lose_reply=True
            with self.assertRaises(TimeoutError):self.service.command(payload)
            committed=copy.deepcopy(self.profile)
            result=self.service.command(payload)
            self.assertTrue(result['ok'],result)
            self.assertEqual(self.profile,committed,'Lost replies replay the same compensation and draw receipt')
            normalized=copy.deepcopy(expected['content_inventory']);normalized[ticket]-=1
            self.assertEqual(self.profile['save']['content_inventory'],normalized)
            self.assertEqual(self.profile['save']['gameplay_stats'],initial_stats)
            self.assertEqual(result['response']['unique_points_reconciliation'],{
                'changed_items':97,'converted_points':expected['converted_points'],'converted_currency':'shop_points'})
            self.assertEqual(self.profile['save']['archive']['commerce']['balances']['shop_points'],
                             7+expected['converted_points']+item['duplicate_points'])
            second=self.send('lottery_draw',pool_id=pool,count=1,request_id='points_reconcile_again')
            self.assertEqual(second['response']['unique_points_reconciliation']['converted_points'],0)
            self.assertEqual(second['response']['unique_points_reconciliation']['changed_items'],0)
            self.assertEqual(self.profile['save']['archive']['commerce']['balances']['shop_points'],
                             7+expected['converted_points']+2*item['duplicate_points'])
            self.assertEqual(self.profile['save']['gameplay_stats'],before['save']['gameplay_stats'])

    def test_lottery_points_exchange_reconciles_other_legacy_items_only_after_validation(self):
        item,pool,ticket,weights=self._points_draw_fixture('ssr')
        self._seed_points_draw_profile(ticket)
        inventory=self.profile['save']['content_inventory']
        inventory['lottery_flame_crystal']=3
        before=copy.deepcopy(self.profile)
        with weights:
            failed=self.send('lottery_exchange',pool_id=pool,item_id=item['item_id'],request_id='reconcile_exchange_poor')
            self.assertFalse(failed['ok']);self.assertEqual(failed['error'],'starjoy_points_insufficient')
            self.assertEqual(self.profile,before,'Rejected transactions cannot compensate or normalize a save')
            self.profile['save']['gameplay_stats']['starjoy_points']=item['exchange_points']+17
            payload=self.command('lottery_exchange',pool_id=pool,item_id=item['item_id'],request_id='reconcile_exchange_ok')
            result=self.service.command(payload)
            self.assertTrue(result['ok'],result)
            inventory=self.profile['save']['content_inventory']
            self.assertNotIn('lottery_flame_crystal',inventory)
            self.assertEqual(inventory['lottery_nature_crystal'],1)
            self.assertEqual(inventory[item['item_id']],1)
            self.assertEqual(self.profile['save']['archive']['commerce']['balances']['shop_points'],17)
            self.assertEqual(self.profile['save']['gameplay_stats']['starjoy_points'],17)
            after=copy.deepcopy(self.profile)
            self.assertEqual(self.service.command(payload)['response'],result['response'])
            self.assertEqual(self.profile,after)

    def test_lottery_points_reconciliation_overflow_preserves_the_whole_account(self):
        item,pool,ticket,weights=self._points_draw_fixture('n')
        self._seed_points_draw_profile(ticket)
        self.profile['save']['content_inventory'][item['item_id']]=3
        self.profile['save']['archive']['commerce']['balances']['shop_points']=9007199254740990
        before=copy.deepcopy(self.profile)
        with weights:
            result=self.send('lottery_draw',pool_id=pool,count=1,request_id='reconcile_overflow')
            self.assertFalse(result['ok']);self.assertEqual(result['error'],'settlement_failed')
        self.assertEqual(self.profile,before,'A failed repair cannot debit tickets, add stats or lose historical copies')

    def test_unique_lottery_unfinished_old_intents_require_refresh_without_loading_old_reducer(self):
        item,pool,ticket,weights=self._points_draw_fixture('n')
        self._seed_points_draw_profile(ticket)
        self.profile['save']['content_inventory'][item['item_id']]=3
        self.profile['save']['gameplay_stats']['starjoy_points']=item['exchange_points']+17
        before=copy.deepcopy(self.profile)
        old_hash='a'*64
        for kind in ('lottery_draw','lottery_exchange'):
            command=self.command(kind,pool_id=pool,request_id='old_unique_'+kind,
                                 **({'count':1} if kind=='lottery_draw' else {'item_id':item['item_id']}))['command']
            prepared=self.db.rpc('archive_prepare',{'p_account':self.account,'p_id':command['id'],
                'p_command':command,'p_hash':old_hash,'p_fingerprint':kind})
            with patch('archive_backend.service.Bundle',side_effect=AssertionError('An old lottery reducer cannot run')):
                result=self.service.finish_prepared(self.account,command['id'],prepared)
            self.assertFalse(result['ok']);self.assertTrue(result['terminal'])
            self.assertEqual(result['error'],'lottery_config_refresh_required')
            self.assertEqual(self.profile,before,'A refresh rejection cannot normalize or award historical copies')
            again=self.service.finish_prepared(self.account,command['id'],self.db.resume(self.account,command['id']))
            self.assertEqual(again,result)

    def test_unique_lottery_completed_old_receipts_are_immutable(self):
        item,pool,ticket,weights=self._points_draw_fixture('n')
        self._seed_points_draw_profile(ticket)
        command=self.command('lottery_draw',pool_id=pool,count=1,request_id='old_completed_unique')['command']
        self.db.rpc('archive_prepare',{'p_account':self.account,'p_id':command['id'],
            'p_command':command,'p_hash':'a'*64,'p_fingerprint':'completed-old'})
        op=self.db.ops[(self.account,command['id'])]
        op.update(done=True,response={'ok':True,'results':[{'id':item['item_id'],'owned_count':44}],
                                      'shop_points':123,'legacy_recorded_rule':'keep'})
        before=copy.deepcopy(self.profile);receipt=self.db.resume(self.account,command['id'])
        self.assertEqual(self.service.finish_prepared(self.account,command['id'],receipt),receipt)
        self.assertEqual(self.profile,before)

    def test_unique_lottery_old_snapshot_clamps_only_current_unique_item_projection(self):
        self.profile['save']['content_inventory']={'lottery_flame_crystal':3,'material_synthesis_gem':91}
        before=copy.deepcopy(self.profile)
        old_hash='a'*64
        projected={'ok':True,'snapshots':[{'selected_pool_id':'map','items':[
            {'id':'lottery_flame_crystal','owned_count':3,'max_owned':9,'owned':True,'at_max_owned':False},
            {'id':'lottery_nature_crystal','owned_count':0,'max_owned':9,'owned':False,'at_max_owned':False},
            {'id':'material_synthesis_gem','owned_count':91,'max_owned':999999}]}]}
        with patch.object(self.bundle,'compatible_config_hashes',{old_hash:{'commands':{'lottery_snapshot'},'upgrade_commands':set()}}), \
                patch('archive_backend.service.Bundle',return_value=self.bundle), \
                patch.object(ArchiveService,'settle',return_value=copy.deepcopy(projected)):
            result=self.service.lottery_snapshot({'account_id':'100','config_hash':old_hash})
        items=result['snapshots'][0]['items']
        self.assertEqual(items[0],{'id':'lottery_flame_crystal','owned_count':1,'max_owned':1,'owned':True,'at_max_owned':True})
        self.assertEqual(items[1],{'id':'lottery_nature_crystal','owned_count':0,'max_owned':1,'owned':False,'at_max_owned':False})
        self.assertEqual(items[2],projected['snapshots'][0]['items'][2])
        self.assertEqual(self.profile,before)
        self.assertEqual(result['config_hash'],old_hash)

    def test_lottery_points_legacy_alias_exchange_rejects_without_debit_or_grant(self):
        item,pool,ticket,weights=self._points_draw_fixture('n','lottery_nature_crystal')
        self._seed_points_draw_profile(ticket)
        self.profile['save']['content_inventory']['lottery_flame_crystal']=1
        self.profile['save']['gameplay_stats']['starjoy_points']=item['exchange_points']+17
        before=copy.deepcopy(self.profile)
        with weights:
            payload=self.command('lottery_exchange',pool_id=pool,item_id=item['item_id'],
                                 request_id='points_alias_exchange')
            result=self.service.command(payload)
            self.assertFalse(result['ok'],result)
            self.assertEqual(result['error'],'lottery_item_owned')
            self.assertEqual(self.profile,before,'A legacy alias prevents a second purchase and any currency debit')
            self.assertFalse(self.service.command(payload)['ok'])
            self.assertEqual(self.profile,before)

    def test_lottery_rejects_without_local_grant(self):
        before=copy.deepcopy(self.profile)
        result=self.send('lottery_draw',pool_id='map',count=10,request_id='empty_1')
        self.assertFalse(result['ok']);self.assertEqual(result['error'],'lottery_ticket_insufficient')
        self.assertEqual(self.profile,before)
        with self.assertRaises(ArchiveError):self.send('lottery_draw',pool_id='map',count=10,request_id='forged_1',results=[])

    def test_lottery_snapshot_and_read_and_exchange(self):
        projection=self.service.lottery_snapshot({'account_id':'100','config_hash':self.bundle.hash})
        self.assertTrue(projection['ok'],projection)
        snapshots=projection['snapshots'];self.assertEqual(len(snapshots),4)
        selected=next(s for s in snapshots if s['selected_pool_id']=='map')
        ranks={'ur':5,'ssr':4,'sr':3,'r':2,'n':1}
        values=[ranks[i['quality']] for i in selected['items']]
        self.assertEqual(values,sorted(values,reverse=True))
        self.assertNotIn('quality_weights',selected['selected_pool'])
        self.assertEqual(selected['tickets'],0)
        self.assertTrue(self.send('lottery_read',pool_id='map',read_action='details',revision=selected['selected_pool']['revision'],request_id='read_1')['ok'])
        after=self.service.lottery_snapshot({'account_id':'100','config_hash':self.bundle.hash})
        self.assertFalse(next(s for s in after['snapshots'] if s['selected_pool_id']=='map')['selected_pool']['update_unread'])
        item=next(i for i in selected['items'] if i['exchange_enabled'] and i['exchange_points']>0)
        self.profile['save']['gameplay_stats']['starjoy_points']=item['exchange_points']
        self.assertTrue(self.send('lottery_exchange',pool_id='map',item_id=item['id'],request_id='exchange_1')['ok'])
        self.assertEqual(self.profile['save']['gameplay_stats']['starjoy_points'],0)
        self.assertEqual(self.profile['save']['content_inventory'][item['id']],1)

    def test_incomplete_recovery_never_returns_stale_profile(self):
        payload=self.command('clear',difficulty_id='n1',count=1)
        self.service.settle=lambda *args: (_ for _ in ()).throw(TimeoutError('worker stopped'))
        with self.assertRaises(TimeoutError):self.service.command(payload)
        self.service=ArchiveService(self.app,self.bundle,self.service.lua)
        self.service.finish_prepared=lambda *args:{'ok':False,'error':'archive_busy_retry'}
        with self.assertRaisesRegex(TimeoutError,'archive_pending_retry'):
            self.service.profile({'account_id':'100'})

    def test_lottery_cultivation_locked_at_99_without_any_debit(self):
        self.profile['save']['content_inventory']={'lottery_ticket':50,'special_lottery_ticket':80}
        self.profile['save']['archive']={'lottery_state':{'pools':{'map':{'draws':99}}}}
        before=copy.deepcopy(self.profile)
        for count in (1,10):
            result=self.send('lottery_draw',pool_id='cultivation',count=count,request_id='locked_'+str(count))
            self.assertFalse(result['ok']);self.assertEqual(result['error'],'lottery_pool_locked')
            self.assertEqual(self.profile,before)
        projection=self.service.lottery_snapshot({'account_id':'100','config_hash':self.bundle.hash})
        selected=next(s for s in projection['snapshots'] if s['selected_pool_id']=='cultivation')['selected_pool']
        self.assertFalse(selected['unlocked']);self.assertEqual(selected['unlock_progress'],99)
        self.assertEqual(selected['unlock_required'],100);self.assertEqual(selected['ticket_content_id'],'special_lottery_ticket')

    def test_lottery_map_ten_unlocks_at_100_and_cultivation_spends_gold(self):
        self.profile['save']['content_inventory']={'lottery_ticket':100,'special_lottery_ticket':17}
        self.profile['save']['archive']={'lottery_state':{'pools':{'map':{'draws':90}}}}
        payload=self.command('lottery_draw',pool_id='map',count=10,request_id='unlock_ten')
        self.assertTrue(self.service.command(payload)['ok']);self.assertTrue(self.service.command(payload)['ok'])
        self.assertEqual(self.profile['save']['archive']['lottery_state']['pools']['map']['draws'],100)
        projection=self.service.lottery_snapshot({'account_id':'100','config_hash':self.bundle.hash})
        selected=next(s for s in projection['snapshots'] if s['selected_pool_id']=='cultivation')['selected_pool']
        self.assertTrue(selected['unlocked'])
        self.assertEqual(selected['ticket_content_id'],'special_lottery_ticket')
        self.assertEqual(selected['ticket_name'],'金色抽奖券')
        self.assertEqual(selected['tickets'],17)
        self.assertTrue(self.send('lottery_draw',pool_id='cultivation',count=1,request_id='gold_one')['ok'])
        self.assertTrue(self.send('lottery_draw',pool_id='cultivation',count=10,request_id='gold_ten')['ok'])
        self.assertEqual(self.profile['save']['content_inventory']['lottery_ticket'],90)
        self.assertEqual(self.profile['save']['content_inventory']['special_lottery_ticket'],6)
        self.assertEqual(self.profile['save']['archive']['lottery_state']['pools']['cultivation']['draws'],11)

    def test_lottery_cultivation_gold_shortage_preserves_normal_tickets(self):
        self.profile['save']['content_inventory']={'lottery_ticket':100,'special_lottery_ticket':9}
        self.profile['save']['archive']={'lottery_state':{'pools':{'map':{'draws':100}}}}
        before=copy.deepcopy(self.profile)
        result=self.send('lottery_draw',pool_id='cultivation',count=10,request_id='gold_ten_shortage')
        self.assertFalse(result['ok']);self.assertEqual(result['error'],'lottery_ticket_insufficient')
        self.assertEqual(self.profile,before)

    def test_lottery_gold_pools_have_no_progress_gate(self):
        self.profile['save']['content_inventory']={'lottery_ticket':17,'special_lottery_ticket':22}
        for pool in ('dragon_knight','summer'):
            self.assertTrue(self.send('lottery_draw',pool_id=pool,count=1,request_id=pool+'_one')['ok'])
            self.assertTrue(self.send('lottery_draw',pool_id=pool,count=10,request_id=pool+'_ten')['ok'])
        self.assertEqual(self.profile['save']['content_inventory']['lottery_ticket'],17)
        self.assertEqual(self.profile['save']['content_inventory']['special_lottery_ticket'],0)
        self.assertNotIn('map',self.profile['save']['archive']['lottery_state']['pools'])

    def test_lottery_ticket_types_cannot_substitute_each_other(self):
        for pool in ('map','cultivation','dragon_knight','summer'):
            normal=pool=='map'
            self.profile['save']['content_inventory']={'lottery_ticket':0 if normal else 99,'special_lottery_ticket':99 if normal else 0}
            self.profile['save']['archive']={'lottery_state':{'pools':{'map':{'draws':100}}}}
            before=copy.deepcopy(self.profile)
            for count in (1,10):
                result=self.send('lottery_draw',pool_id=pool,count=count,request_id='wrong_'+pool+'_'+str(count))
                self.assertFalse(result['ok']);self.assertEqual(result['error'],'lottery_ticket_insufficient')
                self.assertEqual(self.profile,before)

    def test_lottery_pity_tiers_and_forced_ssr_fallback(self):
        # Seed zero selects the lowest available tier; cultivation and dragon_knight have no N in their screenshot pools.
        for pool,expected in [('map','ssr'),('cultivation','ssr'),('dragon_knight','ur'),('summer','ur')]:
            profile=copy.deepcopy(self.profile)
            profile['save']['content_inventory']={'lottery_ticket':100,'special_lottery_ticket':100}
            profile['save']['archive']={'lottery_state':{'pools':{'map':{'draws':100}}}}
            payload={'profile':profile,'configs':self.bundle.configs,'seed':0,'has_pass':False,
                'command':{'kind':'lottery_draw','pool_id':pool,'count':10,'id':'guarantee_test','request_id':'guarantee_test'}}
            completed=subprocess.run([self.lua,'worker.lua'],cwd=self.bundle.directory,input=json.dumps(payload),capture_output=True,text=True,check=True)
            result=json.loads(completed.stdout);self.assertTrue(result['ok'],result)
            response=result['response'];self.assertEqual(response['guarantee_quality'],expected)
            self.assertTrue(response['guarantee_satisfied'])
            natural='r' if pool in ('cultivation','dragon_knight','summer') else 'n'
            self.assertEqual([x['quality'] for x in response['results']],[natural]*9+[expected])
            # A single draw at an existing 100-draw history still has no batch guarantee.
            payload['command']['count']=1
            completed=subprocess.run([self.lua,'worker.lua'],cwd=self.bundle.directory,input=json.dumps(payload),capture_output=True,text=True,check=True)
            single=json.loads(completed.stdout)['response']
            self.assertEqual(single['guarantee_quality'],'');self.assertEqual(single['results'][0]['quality'],natural)
        projection=self.service.lottery_snapshot({'account_id':'100','config_hash':self.bundle.hash})
        for snapshot in projection['snapshots']:
            wanted='ssr' if snapshot['selected_pool_id'] in ('map','cultivation') else 'ur'
            self.assertEqual(snapshot['selected_pool']['pity'][0]['quality'],wanted)

if __name__=='__main__':unittest.main()
