from pathlib import Path
import copy,json,sys,tempfile,unittest,importlib.util
ROOT=Path(__file__).resolve().parents[1]
sys.path[:0]=[str(ROOT/'output/python_test_runtime'),str(ROOT/'server')]
from lupa.lua51 import LuaRuntime
from archive_backend.bundle import build,Bundle
from archive_backend.service import ArchiveService,ArchiveError
spec=importlib.util.spec_from_file_location('archive_tests',ROOT/'server/tests/test_archive_backend.py');fixtures=importlib.util.module_from_spec(spec);spec.loader.exec_module(fixtures)
class LocalWorkerService(ArchiveService):
 def settle(self,profile,command,has_pass):
  payload={'configs':self.bundle.configs,'profile':profile,'command':command,'has_pass':has_pass,'seed':1234,'server_time':2000000000}
  lua=LuaRuntime(unpack_returned_tuples=True)
  lua.globals().INPUT=json.dumps(payload,ensure_ascii=False)
  lua.execute('io={read=function() return INPUT end,write=function(text) OUTPUT=text end}')
  source=(self.bundle.directory/'worker.lua').read_text(encoding='utf-8')
  source=source.replace('package.path = "./?.lua"','package.path = '+json.dumps(self.bundle.directory.as_posix()+'/?.lua'))
  lua.execute(source)
  result=json.loads(lua.globals().OUTPUT)
  return fixtures.copy.deepcopy(__import__('archive_backend.service',fromlist=['object_maps']).object_maps(result))
class VIPBackendTest(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.tmp=tempfile.TemporaryDirectory();cls.addClassCleanup(cls.tmp.cleanup)
  digest=build(ROOT,Path(cls.tmp.name),False);cls.bundle=Bundle(Path(cls.tmp.name)/digest)
 def setUp(self):
  self.db=fixtures.Database(self.bundle);self.app=fixtures.App(self.db)
  self.svc=LocalWorkerService(self.app,self.bundle,'unused')
  self.profile=self.db.profile(self.app._database_account_id('100'));self.n=0
 def command(self,kind,reward):
  self.n+=1
  return {'account_id':'100','config_hash':self.bundle.hash,'command':{'id':'viptest:request:'+str(self.n),'kind':kind,'reward_id':reward}}
 def test_client_cannot_supply_membership_prices_or_effects(self):
  for key,value in [('vip_level',12),('price',0),('effects',{'initial_wood':9999}),('balance',1000),('player_id',0)]:
   cmd=self.command('vip_claim','vip_privilege_01')['command'];cmd[key]=value
   with self.assertRaises(ArchiveError):self.svc.validate(cmd)
  for kind,id in [('vip_claim','vip_package_01'),('vip_purchase','vip_medal_01'),('vip_purchase','missing')]:
   with self.assertRaises(ArchiveError):self.svc.validate(self.command(kind,id)['command'])
 def test_lost_reply_and_new_request_cannot_duplicate_purchase(self):
  s=self.profile['save']['gameplay_stats'];s['vip_level']=1;s['vip_recharge_total_fen']=5000;s['shop_paid_currency']=20
  command=self.command('vip_purchase','vip_package_01');self.db.lose_reply=True
  with self.assertRaises(TimeoutError):self.svc.command(command)
  self.db.lose_reply=False;self.assertTrue(self.svc.command(command)['ok'])
  self.assertTrue(self.svc.command(self.command('vip_purchase','vip_package_01'))['ok'])
  self.assertEqual(s['shop_paid_currency'],10);self.assertEqual(s['initial_wood'],60)
  self.assertEqual(s['hero_attribute_bonus_pct'],1)
  self.assertTrue(self.profile['save']['archive']['vip_claimed']['vip_medal_01'])
 def test_insufficient_then_funded_new_attempt_succeeds(self):
  s=self.profile['save']['gameplay_stats'];s['vip_level']=1;s['vip_recharge_total_fen']=5000;s['shop_paid_currency']=9
  self.assertFalse(self.svc.command(self.command('vip_purchase','vip_package_01'))['ok']);self.assertEqual(s['shop_paid_currency'],9)
  s['shop_paid_currency']=10
  self.assertTrue(self.svc.command(self.command('vip_purchase','vip_package_01'))['ok']);self.assertEqual(s['shop_paid_currency'],0)
 def test_changed_profile_retries_without_lost_stats(self):
  s=self.profile['save']['gameplay_stats'];s['vip_level']=1;s['vip_recharge_total_fen']=5000;s['shop_paid_currency']=10;self.db.conflict=True
  self.assertTrue(self.svc.command(self.command('vip_purchase','vip_package_01'))['ok'])
  self.assertEqual(s['initial_wood'],160);self.assertEqual(s['shop_paid_currency'],0)
 def test_levels_and_little_jacket_lifetime_points(self):
  s=self.profile['save']['gameplay_stats'];s['vip_level']=2;s['vip_recharge_total_fen']=10000
  for n in (1,2):self.assertTrue(self.svc.command(self.command('vip_claim',f'vip_privilege_{n:02}'))['ok'])
  self.assertAlmostEqual(s['hero_damage_attack_growth'],2.5)
  self.assertFalse(self.svc.command(self.command('vip_claim','vip_privilege_03'))['ok'])
  s['shop_paid_currency']=19
  self.assertTrue(self.svc.command(self.command('vip_purchase','vip_little_jacket'))['ok'])
  self.assertEqual(s['starjoy_points_earned'],68);self.assertEqual(s['starjoy_reward_level'],1)
  self.assertEqual(s['shop_paid_currency'],0);self.assertEqual(s['wood_per_second'],1)
if __name__=='__main__':
 LuaRuntime(unpack_returned_tuples=True).execute((ROOT/'scripts/vscripts/tests/test_vip_rewards.lua').read_text(encoding='utf-8-sig'))
 unittest.main(verbosity=2)
