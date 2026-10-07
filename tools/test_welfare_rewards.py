from pathlib import Path
import sys,json,tempfile,unittest
ROOT=Path(__file__).resolve().parents[1]
sys.path[:0]=[str(ROOT/'output/python_test_runtime'),str(ROOT/'server'),str(ROOT/'tools')]
from lupa.lua51 import LuaRuntime
from test_vip_rewards import fixtures,LocalWorkerService
from archive_backend.bundle import build,Bundle
from archive_backend.service import ArchiveError
class WelfareBackendTest(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.tmp=tempfile.TemporaryDirectory();cls.addClassCleanup(cls.tmp.cleanup)
  digest=build(ROOT,Path(cls.tmp.name),False);cls.bundle=Bundle(Path(cls.tmp.name)/digest)
 def setUp(self):
  self.db=fixtures.Database(self.bundle);self.app=fixtures.App(self.db)
  self.svc=LocalWorkerService(self.app,self.bundle,'unused')
  self.profile=self.db.profile(self.app._database_account_id('100'))
  self.profile['save']['archive']['clear_counts']={'n1':5,'n2':8}
 def command(self,session='welfare'):
  return {'account_id':'100','config_hash':self.bundle.hash,'command':{'id':session+':welfare_reconcile','kind':'welfare_reconcile'}}
 def test_backfill_lost_reply_and_new_session_no_double_grant(self):
  base=dict(self.profile['save']['gameplay_stats']);self.db.lose_reply=True
  with self.assertRaises(TimeoutError):self.svc.command(self.command())
  self.db.lose_reply=False
  self.assertTrue(self.svc.command(self.command())['ok'])
  self.assertTrue(self.svc.command(self.command('second'))['ok'])
  s=self.profile['save']['gameplay_stats']
  self.assertEqual(s['initial_wood']-base['initial_wood'],560)
  self.assertEqual(s['initial_population_cap']-base['initial_population_cap'],8)
  self.assertEqual(sum(k.startswith('welfare_victory_') for k in self.profile['save']['archive']['completed']),13)
 def test_no_client_progress_or_effects(self):
  for key,value in [('count',13),('wins',13),('effect_ids',['initial_wood']),('reward_id','welfare_victory_13')]:
   c=self.command()['command'];c[key]=value
   with self.assertRaises(ArchiveError):self.svc.validate(c)
 def test_empty_account_cannot_grant(self):
  self.profile['save']['archive']['clear_counts']={}
  self.assertTrue(self.svc.command(self.command())['ok'])
  self.assertFalse(any(k.startswith('welfare_victory_') for k in self.profile['save']['archive']['completed']))
 def test_cooperative_clear_atomic_retry_and_solo_isolation(self):
  a=self.profile['save']['archive'];a['cooperative_clear_count']=4
  cmd=self.command('team-match');cmd['command']={'id':'team-match:clear','kind':'clear','count':1,'difficulty_id':'n2','cooperative_win':1}
  self.db.lose_reply=True
  with self.assertRaises(TimeoutError):self.svc.command(cmd)
  self.db.lose_reply=False
  self.assertTrue(self.svc.command(cmd)['ok'])
  self.assertEqual(self.profile['save']['archive']['cooperative_clear_count'],5)
  self.assertTrue(self.profile['save']['archive']['completed']['welfare_coop_01'])
  stats=dict(self.profile['save']['gameplay_stats'])
  cmd['command']['id']='team-match:different-retry-suffix'
  self.assertTrue(self.svc.command(cmd)['ok'])
  self.assertEqual(self.profile['save']['archive']['cooperative_clear_count'],5)
  self.assertEqual(stats,self.profile['save']['gameplay_stats'])
  for session,flag in [('solo-match',0),('older-server',None)]:
   cmd['command']['id']=session+':clear'
   if flag is None:cmd['command'].pop('cooperative_win',None)
   else:cmd['command']['cooperative_win']=flag
   self.assertTrue(self.svc.command(cmd)['ok'])
   self.assertEqual(self.profile['save']['archive']['cooperative_clear_count'],5)
 def test_cooperative_flag_validation(self):
  for flag in [True,False,-1,2,1.5,'1',None]:
   with self.assertRaises(ArchiveError):self.svc.validate({'id':'validmatch:clear','kind':'clear','count':1,'difficulty_id':'n1','cooperative_win':flag})
 def test_finish_history_backfill_does_not_repeat_old_batches(self):
  archive=self.profile['save']['archive'];archive['clear_counts']={'n1':70,'n2':60};archive['cooperative_clear_count']=50
  archive['completed']={r['achievement_id']:True for r in self.bundle.tables['archive_welfare_rewards'].values() if not r['achievement_id'].startswith('welfare_finish_')}
  base=dict(self.profile['save']['gameplay_stats']);self.db.lose_reply=True
  with self.assertRaises(TimeoutError):self.svc.command(self.command('finish-history'))
  self.db.lose_reply=False
  self.assertTrue(self.svc.command(self.command('finish-history'))['ok'])
  self.assertTrue(self.svc.command(self.command('finish-new-session'))['ok'])
  expected={'hero_attribute_bonus_pct':11,'hero_attack_bonus_pct':17,'hero_attribute_growth':20,'hero_attack_armor_reduction':21,'hero_final_damage_bonus_pct':14,'hero_basic_attack_growth':9}
  for key,value in self.profile['save']['gameplay_stats'].items():self.assertAlmostEqual(value-base[key],expected.get(key,0),msg=key)
  self.assertEqual(sum(k.startswith('welfare_finish_') for k in self.profile['save']['archive']['completed']),13)
if __name__=='__main__':
 lua=LuaRuntime(unpack_returned_tuples=True)
 lua.execute((ROOT/'scripts/vscripts/tests/test_welfare_rewards.lua').read_text(encoding='utf-8-sig'))
 rows=lua.eval("require('systems/archive_welfare_rewards').rows({clear_counts={n1=5}})")
 out=ROOT/'output/welfare_victory_20261003';out.mkdir(exist_ok=True,parents=True)
 (out/'rows.json').write_text(json.dumps([dict(rows[i]) for i in range(1,len(rows)+1)],ensure_ascii=False),encoding='utf-8')
 unittest.main()
