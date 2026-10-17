"""Exercise the exact deployed Python router and old worker with the minimal overlay."""
import copy,hashlib,importlib.util,json,shutil,sys,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path[:0]=[str(ROOT/'server'),str(ROOT/'output/video_shop_20261015/deps')]
from lupa.lua51 import LuaRuntime
from tests.test_archive_backend import Database,App
BASE='310d3063f3e320b4d541b8715d3e2005b08a68aacfabdf471da9d1c85380fca4'
RELEASE=ROOT/'output/video_shop_20261015/release'
DIFF=json.loads((RELEASE/'archive_overlay_diff.json').read_bytes());OVERLAY=DIFF['overlay']
DEPLOYED=ROOT/'output/video_shop_20261015/deployed_baseline'
manifest=json.loads((DEPLOYED/'release_manifest.json').read_text(encoding='utf-8-sig'))['files']
assert hashlib.sha256((ROOT/'server/archive_backend/config_compatibility.py').read_bytes().replace(b'\r\n',b'\n')).hexdigest()==manifest['backend/archive_backend/config_compatibility.py']
def load(name,file):
 assert hashlib.sha256(file.read_bytes()).hexdigest()==manifest['backend/archive_backend/'+file.name]
 spec=importlib.util.spec_from_file_location(name,file);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module
bundle_module=load('archive_backend._deployed_bundle',DEPLOYED/'backend/archive_backend/bundle.py')
service_module=load('archive_backend._deployed_service',DEPLOYED/'backend/archive_backend/service.py')
service_module.Bundle=bundle_module.Bundle
USED=[]
def runtime(bundle,profile,command,has_pass=False):
 lua=LuaRuntime(unpack_returned_tuples=True)
 lua.globals().INPUT=json.dumps(dict(configs=bundle.configs,profile=profile,command=command,has_pass=has_pass,seed=1234,server_time=2000000000),ensure_ascii=False)
 lua.execute('io={read=function() return INPUT end,write=function(v) OUTPUT=v end}')
 source=(bundle.directory/'worker.lua').read_text(encoding='utf-8').replace('package.path = "./?.lua"','package.path = '+json.dumps(bundle.directory.as_posix()+'/?.lua'))
 lua.execute(source);return service_module.object_maps(json.loads(lua.globals().OUTPUT))
def settle(self,profile,command,has_pass):
 USED.append(self.bundle.hash);return runtime(self.bundle,profile,command,has_pass)
service_module.ArchiveService.settle=settle

class OverlayTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.temp=tempfile.TemporaryDirectory();cls.addClassCleanup(cls.temp.cleanup);folder=Path(cls.temp.name)
  shutil.copytree(ROOT/'server/bundles'/BASE,folder/BASE)
  shutil.copytree(RELEASE/'archive_bundle_overlay'/OVERLAY,folder/OVERLAY)
  cls.old=bundle_module.Bundle(folder/BASE);cls.bundle=bundle_module.Bundle(folder/OVERLAY)
 def setUp(self):
  self.db=Database(self.bundle);self.app=App(self.db);self.service=service_module.ArchiveService(self.app,self.bundle,'embedded-lupa51')
  self.profile=self.db.profile(self.app._database_account_id('100'));self.n=0
  self.profile['save']['archive']['commerce']={'balances':{'u_coin':1000000,'shop_points':1000000,'shop_gold':1000000}}
 def command(self,kind='commerce_purchase',hash=OVERLAY,**extra):
  self.n+=1;c=dict(id='overlaytest:'+str(self.n),kind=kind,**extra)
  if kind=='commerce_purchase':c.setdefault('request_id','overlay_request_'+str(self.n))
  return dict(account_id='100',config_hash=hash,command=c)
 def send(self,kind='commerce_purchase',hash=OVERLAY,**extra):return self.service.command(self.command(kind,hash,**extra))
 def test_all_13_formal_packs_use_exact_deployed_python_and_old_worker(self):
  products=[p for p in self.bundle.configs['commerce_catalog']['rows'] if p['enabled'] and p['sku'].startswith('video_bundle_')]
  self.assertEqual(len(products),13)
  for p in products:
   with self.subTest(sku=p['sku']):
    self.setUp();required=p['grants'].get('required_vip_level',0)
    if required:self.profile['save']['gameplay_stats']['vip_recharge_total_fen']=next(r['required_recharge_fen'] for r in self.bundle.configs['archive_vip_levels']['rows'] if r['level']==required)
    before=copy.deepcopy(self.profile);self.assertTrue(self.send(sku=p['sku'])['ok'])
    for field,n in p['effects'].items():self.assertAlmostEqual(self.profile['save']['gameplay_stats'][field],before['save']['gameplay_stats'][field]+n)
    for identity,n in p['grants']['items'].items():self.assertEqual(self.profile['save']['content_inventory'][identity],n)
    for identity in p['grants'].get('vip_claims',[]):self.assertTrue(self.profile['save']['archive']['vip_claimed'][identity])
    self.assertEqual(self.send(sku=p['sku'])['error'],'already_owned')
 def test_pending_2_packs_refuse_without_partial_effects(self):
  for sku in ('video_bundle_b003','video_bundle_b005'):
   before=copy.deepcopy(self.profile);self.assertEqual(self.send(sku=sku)['error'],'product_unavailable');self.assertEqual(before,self.profile)
 def test_old_client_catalog_reads_new_cash_pack_listing(self):
  result=self.send('commerce_catalog',hash=BASE);self.assertTrue(result['ok'])
  self.assertEqual(len(result['products']),121)
  self.assertIn('video_bundle_b001',{p['sku'] for p in result['products']});self.assertEqual(USED[-1],OVERLAY)
 def test_old_client_wallet_receipt_stays_with_original_310_reducer(self):
  self.assertTrue(self.send(hash=BASE,sku='video_p004')['ok']);self.assertEqual(USED[-1],BASE)
  before=copy.deepcopy(self.profile)
  self.assertEqual(self.send(hash=BASE,sku='video_bundle_b001')['error'],'product_unavailable');self.assertEqual(USED[-1],BASE);self.assertEqual(before,self.profile)
 def test_old_receipt_retry_retains_hash_and_never_regrants(self):
  c=self.command(hash=BASE,sku='video_p004',request_id='overlay_old_retry');self.db.lose_reply=True
  with self.assertRaises(TimeoutError):self.service.command(c)
  after=copy.deepcopy(self.profile);self.assertTrue(self.service.command(c)['ok']);self.assertEqual(after,self.profile)
  op=self.db.ops[(self.app._database_account_id('100'),'commerce:overlay_old_retry')]
  self.assertEqual(op['hash'],BASE)
 def test_existing_unrelated_business_uses_unchanged_lua_and_configs(self):
  commands=[dict(kind='daily_init',today=20000,day_key='20000'),dict(kind='clear',difficulty_id='n1',count=1,day_key='20000'),dict(kind='endless',wave=30,difficulty=1),dict(kind='vip_claim',reward_id='vip_privilege_01'),dict(kind='starjoy_reconcile')]
  profile=copy.deepcopy(self.profile);profile['save']['gameplay_stats']['vip_recharge_total_fen']=5000
  for i,command in enumerate(commands):
   command['id']='unchanged:command:'+str(i)
   self.assertEqual(runtime(self.old,profile,command),runtime(self.bundle,profile,command),command['kind'])
 def test_new_vip_tier_gate_and_medal_dedup(self):
  s=self.profile['save']['gameplay_stats'];s['vip_level']=12;self.profile['entitlements']['vip']={'active':True}
  self.assertEqual(self.send(sku='video_bundle_vip_10')['error'],'vip_level_insufficient')
  s['vip_recharge_total_fen']=self.bundle.tables['archive_vip_levels']['vip_level_10']['required_recharge_fen']
  self.profile['save']['archive']['vip_claimed']={'vip_medal_10':True};before=copy.deepcopy(s)
  self.assertTrue(self.send(sku='video_bundle_vip_10')['ok']);self.assertEqual(s['hero_damage_wood_flat']-before['hero_damage_wood_flat'],10)
  self.assertEqual(s['hero_attribute_bonus_pct']-before['hero_attribute_bonus_pct'],10)
if __name__=='__main__':
 result=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(OverlayTests))
 report=dict(status='PASS' if result.wasSuccessful() else 'FAIL',tests_run=result.testsRun,errors=len(result.errors),failures=len(result.failures),base=BASE,overlay=OVERLAY,actual_deployed_python_source_sha256={name:manifest['backend/archive_backend/'+name] for name in ('bundle.py','service.py','config_compatibility.py')},old_worker_unchanged=True,game_or_server_pointer_modified=False,real_external_requests=0,scope='exact_deployed_python_router_embedded_lua_worker_with_local_database_fixture')
 (RELEASE/'archive_overlay_lua_validation.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
 raise SystemExit(not result.wasSuccessful())
