from pathlib import Path
import copy,sys,tempfile,unittest
ROOT=Path(__file__).resolve().parents[1]
sys.path[:0]=[str(ROOT/'output/python_test_runtime'),str(ROOT/'server'),str(ROOT/'tools')]
from lupa.lua51 import LuaRuntime
from test_vip_rewards import fixtures,LocalWorkerService
from archive_backend.bundle import build,Bundle
from archive_backend.service import ArchiveError
class TitleBackendTest(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.tmp=tempfile.TemporaryDirectory();cls.addClassCleanup(cls.tmp.cleanup)
  digest=build(ROOT,Path(cls.tmp.name),False);cls.bundle=Bundle(Path(cls.tmp.name)/digest)
 def setUp(self):
  self.db=fixtures.Database(self.bundle);self.app=fixtures.App(self.db)
  self.svc=LocalWorkerService(self.app,self.bundle,'unused')
  self.profile=self.db.profile(self.app._database_account_id('100'));self.n=0
 def command(self,title):
  self.n+=1
  return {'account_id':'100','config_hash':self.bundle.hash,'command':{'id':'titles:request:'+str(self.n),'kind':'title_equip','title_id':title}}
 def test_equip_remove_reload_and_repeated_receipt(self):
  cmd=self.command('peak_perfection')
  original_stats=copy.deepcopy(self.profile['save']['gameplay_stats'])
  self.assertTrue(self.svc.command(cmd)['ok'])
  self.assertEqual(self.profile['save']['archive']['equipped_title'],'peak_perfection')
  stats=copy.deepcopy(self.profile['save']['gameplay_stats'])
  self.assertEqual(stats,original_stats)
  self.assertTrue(self.svc.command(cmd)['ok'])
  fresh=LocalWorkerService(self.app,self.bundle,'unused')
  self.assertEqual(fresh.profile({'account_id':'100'})['save']['archive']['equipped_title'],'peak_perfection')
  self.assertTrue(fresh.command(self.command(''))['ok'])
  self.assertEqual(self.profile['save']['archive']['equipped_title'],'')
  self.assertEqual(self.profile['save']['gameplay_stats'],stats)
 def test_invalid_title_and_injected_ownership(self):
  for value in ['missing',{},None,1,True]:
   with self.assertRaises(ArchiveError):self.svc.validate(self.command(value)['command'])
  for key in ['titles_owned','equipped_title','player_id','effects']:
   c=self.command('peak_perfection')['command'];c[key]={'peak_perfection':True}
   with self.assertRaises(ArchiveError):self.svc.validate(c)
 def test_new_series_stays_locked_in_worker(self):
  before=copy.deepcopy(self.profile['save'])
  for title in ['jinghong','youlong','jian_tianya','tianxia_diyi','cangqiong','sihai','daoyuan','chushen']:
   result=self.svc.command(self.command(title))
   self.assertFalse(result['ok']);self.assertTrue(result['terminal'])
   self.assertEqual(self.profile['save'],before)
 def test_lost_reply_retry_does_not_grant_stats(self):
  c=self.command('peak_perfection');self.db.lose_reply=True
  with self.assertRaises(TimeoutError):self.svc.command(c)
  before=copy.deepcopy(self.profile['save'])
  self.db.lose_reply=False
  self.assertTrue(self.svc.command(c)['ok']);self.assertEqual(self.profile['save'],before)
if __name__=='__main__':
 LuaRuntime(unpack_returned_tuples=True).execute((ROOT/'scripts/vscripts/tests/test_titles.lua').read_text(encoding='utf-8'))
 unittest.main(verbosity=2)
