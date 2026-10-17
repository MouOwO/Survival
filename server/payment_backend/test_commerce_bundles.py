"""Complete bundle compiler and real Lua settlement tests; no remote services."""
import copy
import json
from pathlib import Path
import sys
import unittest
ROOT=Path(__file__).resolve().parents[2]
sys.path[:0]=[str(ROOT/'server'),str(ROOT/'output/video_shop_20261015/deps'),str(ROOT/'output/python_test_runtime')]
from payment_backend.csv_catalog import build,rows,SOURCES
from payment_backend.commerce_bundles import compile_commerce,csv_text,EMPTY_MEMBERS
from payment_backend.ucoin_catalog import compile_payment_catalog

MEMBER_FIELDS=('member_id','bundle_sku','member_type','target_id','quantity','sort_order','enabled')
class CompilerTests(unittest.TestCase):
 def setUp(self):
  self.package=build(ROOT);self.tables=copy.deepcopy(self.package['commerce_tables'])
  self.reference={name:(ROOT/'data/csv'/name).read_text(encoding='utf-8-sig') for name in SOURCES}
 def add_bundle(self,sku='test_bundle_sword',members=None,enabled='1',price='47680',original='59600'):
  records=rows(self.tables['commerce_products']);p=dict(records[0])
  p.update(sku=sku,display_name=sku,product_type='bundle',category_id='bundles',currency='u_coin',
   price=price,purchase_limit='1',enabled=enabled,sort_order='900',ownership_id=sku+'_owned',
   source_id='TEST',source_current_price=price,source_original_price=original,ownership_quantity='1')
  records.append(p);self.tables['commerce_products']=csv_text(records,list(records[0]))
  values=rows(self.tables.get('commerce_bundle_members',EMPTY_MEMBERS))
  for i,(kind,target,count) in enumerate(members or [('product','video_p012',1),('product','video_p026',1)]):
   values.append(dict(member_id=sku+'_m'+str(i),bundle_sku=sku,member_type=kind,target_id=target,quantity=count,sort_order=i,enabled='1'))
  self.tables['commerce_bundle_members']=csv_text(values,MEMBER_FIELDS)
  return sku
 def compile(self):return {p['sku']:p for p in compile_commerce(self.tables,self.reference,self.package['tables']['payment_categories'])['products']}
 def test_discount_price_complete_rewards_and_component_ownership(self):
  sku=self.add_bundle();p=self.compile();b=p[sku]
  self.assertEqual(b['price'],47680);self.assertEqual(b['original_price'],59600)
  expected={}
  for identity in ('video_p012','video_p026'):
   for field,n in p[identity]['effects'].items():expected[field]=expected.get(field,0)+n
   self.assertEqual(b['grants']['items'][p[identity]['item_id']],1)
  self.assertEqual(b['effects'],expected);self.assertEqual(len(b['grants']['components']),2)
  self.assertEqual([v['id'] for v in b['grants']['lines']],['video_p012','video_p026'])
  self.assertTrue(all(v['icon'] and v['description'] for v in b['grants']['lines']))
  paid={p['sku']:p for p in compile_payment_catalog(self.package['tables'],self.tables,self.reference)['products']}[sku]
  self.assertEqual(paid['amount'],4768);self.assertEqual(paid['grants']['pricing']['original_u_coin_price'],59600)
 def test_nested_bundle_preserves_all_component_markers(self):
  inner=self.add_bundle();outer=self.add_bundle('test_bundle_outer',[('product',inner,1)])
  p=self.compile();self.assertEqual(p[outer]['effects'],p[inner]['effects'])
  self.assertEqual(set(p[outer]['grants']['items']),{'commerce_p012','commerce_p026',inner+'_owned'})
 def test_vip_package_medal_dedup_and_current_source_effects(self):
  sku=self.add_bundle('test_bundle_vip',[('vip_reward','vip_package_05',1),('vip_reward','vip_medal_05',1)],price='17280',original='21600')
  p=self.compile()[sku];self.assertEqual(p['grants']['required_vip_level'],5)
  self.assertEqual(p['grants']['vip_claims'],['vip_package_05','vip_medal_05'])
  self.assertEqual(len(p['grants']['lines']),2)
  source={r['reward_id']:r for r in rows(self.reference['存档系统/archive_vip_rewards.csv'])}
  total={}
  for identity in ('vip_package_05','vip_medal_05'):
   for field,n in zip(source[identity]['effect_ids'].split('|'),source[identity]['effect_values'].split('|')):total[field]=total.get(field,0)+float(n)
  self.assertEqual(p['effects'],total)
  self.assertEqual(float(source['vip_package_05']['effect_values'].split('|')[3]),8)
 def test_pending_preserves_all_members_but_grants_nothing(self):
  sku=self.add_bundle('test_bundle_pending',[('product','video_p012',1),('unavailable','P028',1)],enabled='0')
  p=self.compile()[sku];self.assertFalse(p['enabled']);self.assertTrue(p['bundle_pending'])
  self.assertEqual(p['effects'],{});self.assertEqual(p['grants']['items'],{});self.assertEqual(len(p['grants']['lines']),2)
  self.assertEqual(p['pending_members'],['P028'])
 def test_enabled_cannot_sell_pending_or_skip_missing_members(self):
  self.add_bundle(members=[('unavailable','P028',1)])
  with self.assertRaisesRegex(ValueError,'commerce_bundle_unavailable_member'):self.compile()
  self.setUp();self.add_bundle(members=[('product','no_product_exists',1)])
  with self.assertRaisesRegex(ValueError,'commerce_bundle_product_missing'):self.compile()
 def test_cycle_disabled_child_and_duplicate_claims_rejected(self):
  self.add_bundle(members=[('product','test_bundle_sword',1)])
  with self.assertRaisesRegex(ValueError,'commerce_bundle_cycle'):self.compile()
  self.setUp();self.add_bundle('test_bundle_disabled',enabled='0');self.add_bundle(members=[('product','test_bundle_disabled',1)])
  with self.assertRaisesRegex(ValueError,'commerce_bundle_member_disabled'):self.compile()
  self.setUp();self.add_bundle(members=[('vip_reward','vip_package_01',1),('vip_reward','vip_package_01',1)])
  with self.assertRaisesRegex(ValueError,'commerce_vip_package_duplicated'):self.compile()
 def test_single_price_rule_and_bundle_discount_cannot_be_bypassed(self):
  records=rows(self.tables['commerce_products']);p=next(p for p in records if p['sku']=='video_p012');p['price']='23840'
  self.tables['commerce_products']=csv_text(records,list(records[0]))
  with self.assertRaisesRegex(ValueError,'commerce_reference_price_mismatch'):self.compile()
  self.setUp();self.add_bundle(price='60000',original='59600')
  with self.assertRaisesRegex(ValueError,'commerce_bundle_discount_invalid'):self.compile()

class LuaBundleTests(unittest.TestCase):
 setUp=CompilerTests.setUp
 add_bundle=CompilerTests.add_bundle
 compile=CompilerTests.compile
 @classmethod
 def setUpClass(cls):
  from lupa.lua51 import LuaRuntime
  cls.LuaRuntime=staticmethod(LuaRuntime)
  from archive_backend.bundle import build as build_bundle,Bundle
  from tests.test_archive_backend import Database,App
  from archive_backend.service import ArchiveService,object_maps
  import tempfile
  cls.temp=tempfile.TemporaryDirectory();cls.addClassCleanup(cls.temp.cleanup)
  digest=build_bundle(ROOT,Path(cls.temp.name),False);cls.base_bundle=Bundle(Path(cls.temp.name)/digest)
  class LocalService(ArchiveService):
   def settle(self,profile,command,has_pass):
    lua=LuaRuntime(unpack_returned_tuples=True)
    lua.globals().INPUT=json.dumps(dict(configs=self.bundle.configs,profile=profile,command=command,has_pass=has_pass,seed=1234,server_time=2000000000),ensure_ascii=False)
    lua.execute('io={read=function() return INPUT end,write=function(v) OUTPUT=v end}')
    source=(self.bundle.directory/'worker.lua').read_text(encoding='utf-8').replace('package.path = "./?.lua"','package.path = '+json.dumps(self.bundle.directory.as_posix()+'/?.lua'))
    lua.execute(source);return object_maps(json.loads(lua.globals().OUTPUT))
  cls.Database=staticmethod(Database);cls.App=staticmethod(App);cls.Service=staticmethod(LocalService)
 def prepare(self,vip=False):
  self.sku=self.add_bundle('test_bundle_vip' if vip else 'test_bundle_sword',
   [('vip_reward','vip_package_05',1),('vip_reward','vip_medal_05',1)] if vip else None)
  self.bundle=copy.deepcopy(self.base_bundle);products=list(self.compile().values())
  self.bundle.configs['commerce_catalog']={'key':'sku','rows':products};self.bundle.tables['commerce_catalog']={p['sku']:p for p in products}
  self.db=self.Database(self.bundle);self.app=self.App(self.db);self.service=self.Service(self.app,self.bundle,'local-lupa')
  self.profile=self.db.profile(self.app._database_account_id('100'));self.profile['save']['archive']['commerce']={'balances':{'u_coin':1000000}}
  self.seq=0
 def send(self,kind='commerce_purchase',sku=None,token=None,**extra):
  self.seq+=1;c=dict(id='bundletest:'+str(self.seq),kind=kind,**extra)
  if kind=='commerce_purchase':c.update(sku=sku or self.sku,request_id=token or 'bundletoken_'+str(self.seq))
  return self.service.command(dict(account_id='100',config_hash=self.bundle.hash,command=c))
 def test_lua_complete_atomic_grant_component_limits_and_lost_reply(self):
  self.prepare();before=copy.deepcopy(self.profile);self.db.lose_reply=True
  with self.assertRaises(TimeoutError):self.send(token='bundle_retry_1')
  after=copy.deepcopy(self.profile);self.assertTrue(self.send(token='bundle_retry_1')['ok']);self.assertEqual(after,self.profile)
  direct=self.bundle.tables['commerce_catalog'][self.sku]['effects'];prior=before['save']['gameplay_stats'];actual=self.profile['save']['gameplay_stats']
  # The product's points are earned immediately and cross formal progression
  # tiers in the same transaction; assert their independent configured rewards
  # in addition to every direct item effect, rather than ignoring the extra stats.
  score=max(prior.get('starjoy_points_earned',0),prior.get('starjoy_points',0))+direct.get('starjoy_points',0)
  old_level=prior.get('starjoy_reward_level',0)
  tiers=[r for r in self.bundle.configs['archive_starjoy_levels']['rows'] if r.get('enabled') and r['level']>old_level and score>=r['required_points']]
  expected=dict(direct)
  for tier in tiers:
   for field,n in zip(tier['effect_ids'],tier['effect_values']):expected[field]=expected.get(field,0)+float(n)
  for field,n in expected.items():self.assertAlmostEqual(actual[field],prior.get(field,0)+n,field)
  self.assertEqual(actual['starjoy_points_earned'],score)
  self.assertEqual(actual['starjoy_reward_level'],max([old_level]+[r['level'] for r in tiers]))
  self.assertEqual([r['level'] for r in tiers],[1,2,3],'This real sword+teleporter fixture must exercise all first three point tiers')
  self.assertEqual(self.send(sku='video_p012')['error'],'already_owned')
  self.assertEqual(self.send()['error'],'already_owned');self.assertEqual(after,self.profile)
 def test_lua_prior_single_blocks_bundle_without_charge(self):
  self.prepare();self.assertTrue(self.send(sku='video_p012')['ok']);before=copy.deepcopy(self.profile)
  self.assertEqual(self.send()['error'],'component_already_owned');self.assertEqual(before,self.profile)
 def test_lua_real_vip_level_and_old_new_claim_interop(self):
  self.prepare(True);s=self.profile['save']['gameplay_stats'];s['vip_level']=12
  self.profile['entitlements']['vip']={'active':True};before=copy.deepcopy(self.profile)
  self.assertEqual(self.send()['error'],'vip_level_insufficient');self.assertEqual(before,self.profile)
  level=self.bundle.tables['archive_vip_levels']['vip_level_05'];s['vip_recharge_total_fen']=level['required_recharge_fen']
  self.assertTrue(self.send()['ok']);after=copy.deepcopy(self.profile)
  self.assertTrue(after['save']['archive']['vip_claimed']['vip_package_05']);self.assertTrue(after['save']['archive']['vip_claimed']['vip_medal_05'])
  self.assertTrue(self.send('vip_purchase',reward_id='vip_package_05')['ok']);self.assertEqual(after['save']['gameplay_stats'],self.profile['save']['gameplay_stats'])
 def test_lua_prior_legacy_package_blocks_bundle_and_medal_only_skips_medal(self):
  self.prepare(True);s=self.profile['save']['gameplay_stats'];s['vip_recharge_total_fen']=self.bundle.tables['archive_vip_levels']['vip_level_05']['required_recharge_fen'];s['shop_paid_currency']=1000
  self.assertTrue(self.send('vip_purchase',reward_id='vip_package_05')['ok']);before=copy.deepcopy(self.profile)
  self.assertEqual(self.send()['error'],'already_owned');self.assertEqual(before,self.profile)
  self.setUp();self.prepare(True);s=self.profile['save']['gameplay_stats'];s['vip_recharge_total_fen']=self.bundle.tables['archive_vip_levels']['vip_level_05']['required_recharge_fen']
  self.profile['save']['archive']['vip_claimed']={'vip_medal_05':True};before=copy.deepcopy(s)
  self.assertTrue(self.send()['ok']);p=self.bundle.tables['commerce_catalog'][self.sku]
  for field,n in p['effects'].items():self.assertAlmostEqual(s[field],before[field]+n-p['grants']['vip_claim_effects']['vip_medal_05'].get(field,0))
 def test_lua_old_purchase_rejects_forged_member_tier(self):
  self.prepare(True);self.profile['entitlements']['vip']={'active':True};self.profile['save']['gameplay_stats']['shop_paid_currency']=1000
  before=copy.deepcopy(self.profile);self.assertEqual(self.send('vip_purchase',reward_id='vip_package_05')['error'],'VIP等级不足');self.assertEqual(before,self.profile)
 def test_lua_revision_conflict_keeps_concurrent_rewards(self):
  self.prepare();old=self.profile['save']['gameplay_stats']['initial_wood'];self.db.conflict=True
  self.assertTrue(self.send()['ok']);self.assertEqual(self.profile['save']['gameplay_stats']['initial_wood'],old+100+self.bundle.tables['commerce_catalog'][self.sku]['effects'].get('initial_wood',0))
if __name__=='__main__':unittest.main(verbosity=2)
