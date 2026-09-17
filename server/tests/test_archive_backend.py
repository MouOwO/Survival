import copy
import hashlib
import json
from pathlib import Path
import sys
import threading
import unittest
import importlib.util
import urllib.request
import urllib.error
from http.server import ThreadingHTTPServer
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'server'))
from archive_backend.bundle import Bundle
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
            'profile':self.profile(a),'command':op['command'],'has_pass':op['pass']})
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
            if name=='archive_commit':
                op=self.ops[(a,i)];profile=self.profile(a)
                if op['done']:return self.resume(a,i)
                if self.conflict:
                    self.conflict=False;profile['revision']+=1;profile['save']['gameplay_stats']['initial_wood']+=100
                if p['p_revision']!=profile['revision']:return {'ok':False,'error':'archive_revision_conflict'}
                if not p['p_error']:
                    profile['save']['archive']=copy.deepcopy(p['p_archive'])
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
        current=json.loads((ROOT/'server/bundles/current.json').read_text())
        cls.bundle=Bundle(ROOT/'server/bundles'/current['hash'])
    def setUp(self):
        self.db=Database(self.bundle);self.app=App(self.db)
        self.service=ArchiveService(self.app,self.bundle,r'C:\Program Files\lua\bin\lua5.1.exe')
        self.account=self.app._database_account_id('100');self.profile=self.db.profile(self.account);self.n=0
    def command(self,kind,**values):
        self.n+=1
        return {'account_id':'100','config_hash':self.bundle.hash,'command':dict(id='testsession:op:'+str(self.n),kind=kind,**values)}
    def send(self,kind,**values):return self.service.command(self.command(kind,**values))
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
        self.db.lose_reply=True
        with self.assertRaises(TimeoutError): self.service.command(payload)
        self.assertTrue(self.service.command(payload)['ok'])
        self.assertEqual(self.profile['save']['archive']['buildings']['faith'],15000)
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
        self.assertEqual(self.profile['save']['gameplay_stats']['initial_wood'],before+100+50)
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
        sys.path.insert(0,r'D:\survival_database\backend')
        spec=importlib.util.spec_from_file_location('fishing_api.archive_staged_server',ROOT/'server/staged/fishing_api/server.py')
        module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
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

if __name__=='__main__':unittest.main()
