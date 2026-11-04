from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'server'))
from archive_backend import settlement_runner as fast
from archive_backend.bundle import Bundle

LUA=shutil.which('lua5.1') or shutil.which('lua') or 'C:/Program Files/lua/bin/lua5.1.exe'
BUNDLE=ROOT/'server/bundles/d573588b64d2ea6d1431c856d52e0515b5ed471cfdf6af4456ff618d0f568488'


def payload(profile, command, seed=123, stamp=1770000000):
    return dict(profile=deepcopy(profile),command=deepcopy(command),has_pass=False,seed=seed,server_time=stamp)


def original(bundle, request):
    raw=json.dumps(dict(request,configs=bundle.configs),ensure_ascii=False,allow_nan=False).encode()
    result=subprocess.run([LUA,'worker.lua'],cwd=bundle.directory,input=raw,
        stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=10,check=True,
        creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
    return json.loads(result.stdout)


@unittest.skipUnless(Path(LUA).is_file() or shutil.which(LUA),'real Lua interpreter required')
class ActualBundleParity(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.bundle=Bundle(BUNDLE)
        cls.profile=dict(schema_version=1,account_id='100',revision=1,entitlements={},achievements={},public={},save=dict(
            archive={'commerce':{'balances':{'shop_points':1000000,'u_coin':1000000}}},
            gameplay_stats={row['field_id']:row['default_value'] for row in cls.bundle.configs['player_gameplay_stats']['rows']},
            content_inventory={'lottery_ticket':1000,'special_lottery_ticket':1000}))

    @classmethod
    def tearDownClass(cls): fast.clear_cache()

    def test_actual_settlement_actions_preserve_all_results(self):
        bundle=self.bundle
        first=lambda table,key:next(row[key] for row in bundle.configs[table]['rows'] if row.get('enabled',True))
        cases=[
            dict(kind=kind,difficulty_id='n1',count=1,day_key='2026-11-04')
            for kind in ('clear','standard_clear','rich_clear','cold_clear','scourge_clear','mode_clear')]
        cases += [dict(kind='boss_kill'),dict(kind='endless',wave=5,difficulty=1,variant='endless'),
            dict(kind='endless_reconcile'),dict(kind='starjoy_reconcile'),dict(kind='welfare_reconcile'),
            dict(kind='challenge',challenge_id=first('archive_challenge_definitions','challenge_id'),difficulty_id='n1',kill_sequence=1),
            dict(kind='social_draw',pool_id=first('archive_social_rules','pool_id')),
            dict(kind='promotion',fragment_id=first('archive_fragment_definitions','fragment_id')),
            dict(kind='daily_init'),dict(kind='daily_claim',target_day=1),
            dict(kind='benefit_claim',track='public_beta',tier_id='public_beta_login'),
            dict(kind='vip_claim',reward_id=first('archive_vip_rewards','reward_id')),
            dict(kind='vip_purchase',reward_id=first('archive_vip_rewards','reward_id')),
            dict(kind='title_equip',title_id=''),
            dict(kind='work_upgrade',item_id=first('archive_work_items','item_id'),expected_level=0),
            dict(kind='building_upgrade',item_id=first('archive_building_items','item_id'),expected_level=0),
            dict(kind='lottery_snapshot'),dict(kind='lottery_read',pool_id='map',read_action='visit',revision='synthetic'),
            dict(kind='lottery_exchange',pool_id='map',item_id=first('lottery_item_definitions','item_id')),
            dict(kind='commerce_catalog'),dict(kind='commerce_purchase',sku=first('commerce_catalog','sku'))]
        for index,command in enumerate(cases):
            command['id']='synthetic_parity_%d'%index
            request=payload(self.profile,command)
            with self.subTest(kind=command['kind']):
                before=deepcopy(request)
                expected=original(bundle,request)
                actual=json.loads(fast.run(bundle,LUA,request).stdout)
                self.assertEqual(actual,expected)
                self.assertEqual(request,before)

    def test_actual_four_pool_draws_preserve_fixed_random_seeds_and_batches(self):
        for pool in ('map','cultivation','dragon_knight','summer'):
            for count in (1,10):
                for seed in (1,2147483646):
                    command=dict(id='synthetic_draw_%s_%d_%d'%(pool,count,seed),kind='lottery_draw',pool_id=pool,count=count)
                    request=payload(self.profile,command,seed)
                    with self.subTest(pool=pool,count=count,seed=seed):
                        self.assertEqual(json.loads(fast.run(self.bundle,LUA,request).stdout),original(self.bundle,request))

    def test_request_does_not_transport_immutable_configuration(self):
        request=payload(self.profile,dict(id='synthetic_bytes',kind='lottery_snapshot'))
        small=len(json.dumps(request,ensure_ascii=False).encode())
        old=len(json.dumps(dict(request,configs=self.bundle.configs),ensure_ascii=False).encode())
        self.assertLess(small,old/20)
        self.assertNotIn('configs',request)

    def test_actual_daily_reward_success_duplicate_nonce_and_already_claimed_rejection(self):
        today=(1770000000+3*3600)//86400 # trusted prepared command's database day
        initial=payload(self.profile,dict(id='synthetic_daily_init',kind='daily_init',today=today))
        initialized=original(self.bundle,initial)
        active=deepcopy(self.profile)
        active['save']['archive']=initialized['archive']
        active['save']['gameplay_stats']=initialized['gameplay_stats']
        day=active['save']['archive']['daily_rewards']['first_day']
        command=dict(id='synthetic_daily_claim',kind='daily_claim',target_day=day,today=today)
        request=payload(active,command)
        expected=original(self.bundle,request)
        actual=json.loads(fast.run(self.bundle,LUA,request).stdout)
        self.assertEqual(actual,expected);self.assertTrue(actual['ok'])
        self.assertEqual(actual['archive']['daily_rewards']['count'],1)
        active['save']['archive']=deepcopy(actual['archive'])
        active['save']['gameplay_stats']=deepcopy(actual['gameplay_stats'])
        same_nonce=payload(active,command)
        duplicate=json.loads(fast.run(self.bundle,LUA,same_nonce).stdout)
        self.assertEqual(duplicate,original(self.bundle,same_nonce));self.assertTrue(duplicate['duplicate'])
        active['save']['archive'].pop('processed',None) # durable commit stores receipts in SQL
        repeated=payload(active,dict(command,id='synthetic_daily_new_nonce'))
        before=deepcopy(repeated)
        rejected=json.loads(fast.run(self.bundle,LUA,repeated).stdout)
        self.assertEqual(rejected,original(self.bundle,repeated));self.assertFalse(rejected['ok'])
        self.assertEqual(repeated,before)
        self.assertEqual(active['save']['archive']['daily_rewards']['count'],1)


FIXTURE_WORKER='''package.path="./?.lua"
local decoder=require("core/json_decoder")
local encoder=require("core/json_encoder")
local input=decoder.decode(io.read("*a"))
for name,config in pairs(input.configs) do
 local m={rows=config.rows,by_id={}}
 for _,row in ipairs(config.rows) do m.by_id[row[config.key]]=row end
 package.loaded["config/generated/"..name]=m
end
_G.account_state=(_G.account_state or 0)+1
local value=require("config/generated/sample")
io.write(encoder.encode({rows=value.rows,account=input.profile.account_id,counter=_G.account_state,
 unused_loaded=package.loaded["config/generated/unused"]~=nil}))
'''


@unittest.skipUnless(Path(LUA).is_file() or shutil.which(LUA),'real Lua interpreter required')
class CacheBoundaries(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='goufayu_runner_test_')
        self.root=Path(self.temp.name).resolve()
        self.assertEqual(self.root.parent,Path(tempfile.gettempdir()).resolve())
        (self.root/'core').mkdir()
        for name in ('json_decoder.lua','json_encoder.lua'):
            shutil.copyfile(ROOT/'scripts/vscripts/core'/name,self.root/'core'/name)
        (self.root/'worker.lua').write_text(FIXTURE_WORKER,encoding='utf8')
        self.configs={'sample':{'key':'id','rows':[{'id':'one','value':'中文\\\"\n\x00\x19','null':None,'float':-1.25e-8,'yes':True}]},
                      'unused':{'key':'id','rows':[{'id':str(i),'value':i} for i in range(1000)]}}
        fast.clear_cache()

    def tearDown(self):
        fast.clear_cache()
        self.assertEqual(self.root.parent,Path(tempfile.gettempdir()).resolve())
        self.assertTrue(self.root.name.startswith('goufayu_runner_test_'))
        self.temp.cleanup()

    def bundle(self,configs=None,salt=''):
        configs=deepcopy(self.configs if configs is None else configs)
        digest=hashlib.sha256(json.dumps(configs,sort_keys=True).encode()+salt.encode()).hexdigest()
        return SimpleNamespace(configs=configs,hash=digest,directory=self.root)

    def request(self,account='100'):
        return payload({'account_id':account},dict(id='synthetic_cache',kind='lottery_snapshot'))

    def test_only_required_tables_are_loaded_and_unicode_null_roundtrip(self):
        b=self.bundle();q=self.request();actual=json.loads(fast.run(b,LUA,q).stdout)
        expected=original(b,q)
        self.assertFalse(actual.pop('unused_loaded'));expected.pop('unused_loaded')
        self.assertEqual(actual,expected)

    def test_every_request_has_a_fresh_vm_and_no_previous_account_state(self):
        b=self.bundle()
        for account in ('100','200','100'):
            value=json.loads(fast.run(b,LUA,self.request(account)).stdout)
            self.assertEqual((value['account'],value['counter']),(account,1))

    def test_concurrent_requests_share_one_config_build_and_keep_accounts_isolated(self):
        b=self.bundle();before=fast.cache_info()['builds']
        with ThreadPoolExecutor(max_workers=4) as executor:
            values=list(executor.map(lambda account:json.loads(fast.run(b,LUA,self.request(account)).stdout),('100','200','300','400')))
        self.assertEqual(fast.cache_info()['builds']-before,1)
        self.assertEqual([(v['account'],v['counter']) for v in values],[('100',1),('200',1),('300',1),('400',1)])

    def test_warm_account_is_not_blocked_by_another_bundles_cold_compiler(self):
        warm,cold=self.bundle(salt='warm'),self.bundle(salt='cold')
        fast.run(warm,LUA,self.request())
        started,release=threading.Event(),threading.Event()
        actual=fast._Entry
        def delayed(bundle,lua):
            if bundle.hash==cold.hash:
                started.set()
                if not release.wait(5):raise AssertionError('test compiler release missing')
            return actual(bundle,lua)
        with ThreadPoolExecutor(max_workers=2) as executor,patch.object(fast,'_Entry',side_effect=delayed):
            waiting=executor.submit(fast.run,cold,LUA,self.request('200'))
            self.assertTrue(started.wait(2))
            try:
                ready=executor.submit(fast.run,warm,LUA,self.request('100'))
                self.assertEqual(json.loads(ready.result(timeout=2).stdout)['account'],'100')
                self.assertFalse(waiting.done())
            finally:release.set()
            self.assertEqual(json.loads(waiting.result(timeout=3).stdout)['account'],'200')

    def test_config_hash_change_cannot_reuse_previous_module(self):
        b=self.bundle();first=json.loads(fast.run(b,LUA,self.request()).stdout)
        changed=deepcopy(self.configs);changed['sample']['rows'][0]['value']='new config'
        second=json.loads(fast.run(self.bundle(changed),LUA,self.request()).stdout)
        self.assertNotEqual(first['rows'],second['rows'])
        self.assertEqual(second['rows'][0]['value'],'new config')

    def test_worker_uses_the_exact_resolved_executable_that_compiled_the_cache(self):
        with patch.object(fast.shutil,'which',return_value=LUA):
            result=json.loads(fast.run(self.bundle(),'synthetic_unresolvable_alias',self.request()).stdout)
        self.assertEqual(result['account'],'100')

    def test_eviction_never_deletes_a_cache_used_by_an_active_command(self):
        with patch.object(fast,'MAX_CACHES',2):
            with fast._cache(self.bundle(salt='a'),LUA) as first:
                with fast._cache(self.bundle(salt='b'),LUA): pass
                with fast._cache(self.bundle(salt='c'),LUA): pass
                self.assertTrue(first.retired)
                self.assertTrue(first.directory.is_dir())
                self.assertEqual(fast.cache_info()['retained'],2)
            self.assertFalse(first.directory.exists())

    def test_caller_configs_override_is_rejected_before_worker_execution(self):
        with patch.object(fast.subprocess,'run',side_effect=AssertionError('worker must not start')):
            with self.assertRaisesRegex(ValueError,'cannot_override_configs'):
                fast.run(self.bundle(),LUA,dict(self.request(),configs={}))

    def test_cleanup_rechecks_windows_reparse_flag_and_keeps_replaced_directory(self):
        with fast._cache(self.bundle(),LUA) as entry:
            real=entry.directory
            entry.closed=False
            with patch.object(Path,'lstat',return_value=SimpleNamespace(st_file_attributes=0x400)),\
                    patch.object(fast.shutil,'rmtree',side_effect=AssertionError('must not delete reparse target')):
                with self.assertLogs(fast.__name__,level='WARNING'):
                    fast._dispose(entry)
            self.assertTrue(real.is_dir())
            # Restore this unchanged, actually owned path for the real cleanup.
            entry.closed=False

    def test_cleanup_rechecks_current_resolved_path_before_recursive_delete(self):
        with fast._cache(self.bundle(),LUA) as entry:
            with patch.object(Path,'resolve',return_value=self.root),\
                    patch.object(fast.shutil,'rmtree',side_effect=AssertionError('must not delete replacement target')):
                with self.assertLogs(fast.__name__,level='WARNING'):
                    fast._dispose(entry)
            self.assertTrue(entry.directory.is_dir())
            entry.closed=False

    def test_worker_failure_is_not_automatically_replayed(self):
        (self.root/'worker.lua').write_text('error("synthetic failure")',encoding='utf8')
        calls=[];actual=fast.subprocess.run
        def observed(args,*a,**k):
            if len(args)>1 and args[1]==str(fast.RUNNER):calls.append(args)
            return actual(args,*a,**k)
        with patch.object(fast.subprocess,'run',side_effect=observed):
            with self.assertRaises(subprocess.CalledProcessError):fast.run(self.bundle(),LUA,self.request())
        self.assertEqual(len(calls),1)
        self.assertEqual(fast.cache_info()['retained'],0)

    def test_worker_timeout_is_not_automatically_replayed(self):
        calls=[];actual=fast.subprocess.run
        def observed(args,*a,**k):
            if len(args)>1 and args[1]==str(fast.RUNNER):
                calls.append(args);raise subprocess.TimeoutExpired(args,10)
            return actual(args,*a,**k)
        with patch.object(fast.subprocess,'run',side_effect=observed):
            with self.assertRaises(subprocess.TimeoutExpired):fast.run(self.bundle(),LUA,self.request())
        self.assertEqual(len(calls),1)
        self.assertEqual(fast.cache_info()['retained'],0)


if __name__=='__main__':unittest.main()
