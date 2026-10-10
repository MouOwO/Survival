import copy
import subprocess
import hashlib
import json
import os
import shutil
from pathlib import Path
import sys
import threading
import tempfile
import unittest
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
            'profile':self.profile(a),'command':op['command'],'has_pass':op['pass'],'response':op.get('response')})
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
            if name=='archive_resume':return self.resume(a,i)
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
        self.assertEqual(s['faith'],4000)
        self.assertEqual(s['earned_by_day'],{'20000':4000})
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
        self.assertEqual(selected['unlock_required'],100);self.assertEqual(selected['ticket_content_id'],'lottery_ticket')

    def test_lottery_map_ten_unlocks_at_100_and_cultivation_spends_normal(self):
        self.profile['save']['content_inventory']={'lottery_ticket':100,'special_lottery_ticket':17}
        self.profile['save']['archive']={'lottery_state':{'pools':{'map':{'draws':90}}}}
        payload=self.command('lottery_draw',pool_id='map',count=10,request_id='unlock_ten')
        self.assertTrue(self.service.command(payload)['ok']);self.assertTrue(self.service.command(payload)['ok'])
        self.assertEqual(self.profile['save']['archive']['lottery_state']['pools']['map']['draws'],100)
        projection=self.service.lottery_snapshot({'account_id':'100','config_hash':self.bundle.hash})
        selected=next(s for s in projection['snapshots'] if s['selected_pool_id']=='cultivation')['selected_pool']
        self.assertTrue(selected['unlocked'])
        self.assertTrue(self.send('lottery_draw',pool_id='cultivation',count=1,request_id='normal_one')['ok'])
        self.assertTrue(self.send('lottery_draw',pool_id='cultivation',count=10,request_id='normal_ten')['ok'])
        self.assertEqual(self.profile['save']['content_inventory']['lottery_ticket'],79)
        self.assertEqual(self.profile['save']['content_inventory']['special_lottery_ticket'],17)

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
            normal=pool in ('map','cultivation')
            self.profile['save']['content_inventory']={'lottery_ticket':0 if normal else 99,'special_lottery_ticket':99 if normal else 0}
            self.profile['save']['archive']={'lottery_state':{'pools':{'map':{'draws':100}}}}
            before=copy.deepcopy(self.profile)
            result=self.send('lottery_draw',pool_id=pool,count=1,request_id='wrong_'+pool)
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
