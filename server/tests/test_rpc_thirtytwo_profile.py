"""ExplicitDB32 never silently changes the legacy16 connection budgets."""
from copy import deepcopy
import unittest
from tools.loadtest_lab.guard import resolve_database_pool
from tools.loadtest_lab.rpc_process_pool import validate_profile
from tools.loadtest_lab.experiments import resolve_database_resources,DB16_RESOURCE_PROFILES,DB32_RESOURCE_PROFILES
class ThirtyTwoRPCProfile(unittest.TestCase):
 def cfg(self):return {'purpose':'capacity','process_topology':'split-v1','process_observation':'pid-v1','database_resource_profile':'db32-4cpu-4g-v1','db_concurrency':32,'database_pool_limits':{'connections':32,'waiting':64,'wait_seconds':2},'rpc_process_pool':{'id':'driver-process32-v1','workers':32,'max_pending':48,'queue_seconds':2},'sources':{'operator/loadtest_lab/rpc_process_pool.py':'a'*64,'runtime/player_web_auth/response_pool.py':'b'*64}}
 def test_explicit_profile_fixed_allocation(self):
  cfg=self.cfg();old=deepcopy(cfg);self.assertEqual(validate_profile(cfg),cfg['rpc_process_pool']);self.assertEqual(cfg,old)
  self.assertEqual(resolve_database_resources('capacity',profile='db32-4cpu-4g-v1'),(4096,4));self.assertEqual(len(DB16_RESOURCE_PROFILES),1)
 def test_unselected_and_legacy_defaults_unchanged(self):
  self.assertIsNone(validate_profile({}));self.assertEqual(resolve_database_resources('capacity',profile='db16-4cpu-4g-v1'),(4096,4))
 def test_db32_requires_matching_worker_profile(self):
  cfg=self.cfg();cfg.pop('rpc_process_pool')
  with self.assertRaises(ValueError):validate_profile(cfg)
  for key,value in [('workers',16),('workers',33),('max_pending',49),('max_pending',24),('queue_seconds',3),('id','driver-process16-v1')]:
   cfg=self.cfg();cfg['rpc_process_pool'][key]=value
   with self.subTest(key=key,value=value),self.assertRaises(ValueError):validate_profile(cfg)
 def test_cannot_borrow_legacy_connection_or_wait_budget(self):
  for key,value in [('db_concurrency',16),('database_resource_profile','db16-4cpu-4g-v1'),('purpose','functional-smoke'),('process_topology','same-v1')]:
   cfg=self.cfg();cfg[key]=value
   with self.subTest(key=key),self.assertRaises(ValueError):validate_profile(cfg)
  for key,value in [('connections',31),('waiting',32),('wait_seconds',3)]:
   cfg=self.cfg();cfg['database_pool_limits'][key]=value
   with self.subTest(key=key),self.assertRaises(ValueError):validate_profile(cfg)
 def test_fixed_resolution_only_with_explicit32_and_v7(self):
  args=dict(http_concurrency=32,db_concurrency=32,web_concurrency=128,pool_max_waiters=64,pool_wait_seconds=2,admission_mode='bounded-v7')
  _,limits=resolve_database_pool('bounded-v2',**args);self.assertEqual(limits,{'connections':32,'waiting':64,'wait_seconds':2})
  for key,value in [('db_concurrency',31),('pool_max_waiters',32),('pool_max_waiters',65),('pool_wait_seconds',3),('admission_mode','bounded-v6'),('web_concurrency',127)]:
   bad={**args,key:value}
   with self.subTest(key=key,value=value),self.assertRaises(ValueError):resolve_database_pool('bounded-v2',**bad)
 def test_matching_legacy_profile_does_not_accept_new_flag(self):
  cfg=self.cfg();cfg.update(db_concurrency=16,database_pool_limits={'connections':16,'waiting':32,'wait_seconds':2});cfg['rpc_process_pool']={'id':'driver-process16-v1','workers':16,'max_pending':24,'queue_seconds':2}
  with self.assertRaises(ValueError):validate_profile(cfg)
class OriginalBootstrapRetirement(unittest.TestCase):
 def test_a_real_startup_connection_is_closed_before_testing_zero(self):
  from tools.loadtest_lab.process_runtime import _retire_original_pool
  class Original:
   closed=False
   def close(self):self.closed=True
   def pool_stats(self):return dict(closed=self.closed,total=0 if self.closed else 1,waiting=0,in_use=0,connecting=0,closing=0,quarantined=0)
  client=Original();result=_retire_original_pool(client);self.assertTrue(client.closed);self.assertEqual(result['total'],0)
 def test_deferred_or_quarantined_closure_cannot_start_the_new_pool(self):
  from tools.loadtest_lab.process_runtime import _retire_original_pool
  class Original:
   def __init__(self,key):self.key=key
   def close(self):pass
   def pool_stats(self):
    value=dict(closed=True,total=0,waiting=0,in_use=0,connecting=0,closing=0,quarantined=0);value[self.key]=False if self.key=='closed'else 1;return value
  for key in ['closed','total','waiting','in_use','connecting','closing','quarantined']:
   with self.subTest(key=key),self.assertRaises(ValueError):_retire_original_pool(Original(key))
if __name__=='__main__':unittest.main()
