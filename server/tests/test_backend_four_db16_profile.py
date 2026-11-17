"""Reduced DB concurrency must remain explicit, isolated and fully audited."""
import copy,unittest
from tools.loadtest_lab.process_runtime import FOUR_DB16_PROFILE,validate_backend_pair,_node_cfg
from tools.loadtest_lab.guard import resolve_database_pool
from tools.loadtest_lab.experiments import validate_experiments
from server.tests import test_http_sixtyfour_profile as http_tests
class BackendFourDB16Tests(unittest.TestCase):
 def cfg(self):
  cfg=http_tests.HTTP64Profile().cfg();cfg.update(backend_process_pool=dict(FOUR_DB16_PROFILE),process_topology='split-v1',process_observation='pid-v1',db_concurrency=16,database_resource_profile='db16-4cpu-4g-v1',database_pool_limits=dict(connections=16,waiting=64,wait_seconds=2));cfg['sources']['operator/loadtest_lab/process_runtime.py']='d'*64;return cfg
 def test_only_connection_allocation_reduced(self):
  cfg=self.cfg();old=copy.deepcopy(cfg);self.assertEqual(validate_backend_pair(cfg),FOUR_DB16_PROFILE);node=_node_cfg(cfg)
  self.assertEqual((node['http_concurrency'],node['db_concurrency'],node['database_pool_limits']),(16,4,dict(connections=4,waiting=16,wait_seconds=2)));self.assertEqual(cfg,old)
 def test_full_runtime_overlay_validates(self):
  cfg=self.cfg();old=copy.deepcopy(cfg);self.assertTrue(validate_experiments(cfg));self.assertEqual(cfg,old)
 def test_missing_or_forged_node_profile_cannot_admit_smaller_db(self):
  for kind in('missing','workers','node_connections','node_waiters','extra'):
   cfg=self.cfg()
   if kind=='missing':cfg.pop('backend_process_pool')
   else:cfg['backend_process_pool'][{'workers':'workers','node_connections':'per_worker_connections','node_waiters':'per_worker_waiters','extra':'extra'}[kind]]=3
   with self.subTest(kind=kind),self.assertRaises(ValueError):validate_experiments(cfg)
 def test_global_budgets_and_isolation_remain_fixed(self):
  for key,value in [('db_concurrency',32),('http_concurrency',65),('database_resource_profile','db32-4cpu-4g-v1'),('purpose','production'),('process_topology','same-v1'),('rpc_process_pool',{})]:
   cfg=self.cfg();cfg[key]=value
   with self.subTest(key=key),self.assertRaises(ValueError):validate_backend_pair(cfg)
 def test_old_parser_still_rejects_unselected_db16(self):
  args=http_tests.HTTP64Profile().args();args['db_concurrency']=16
  with self.assertRaises(ValueError):resolve_database_pool('bounded-v2',**args)
 def test_requested_effective_audit_keeps_all_other_limits(self):
  args=http_tests.HTTP64Profile().args();args['db_concurrency']=16
  audit,limits=resolve_database_pool('bounded-v2',backend_profile=FOUR_DB16_PROFILE['id'],**args)
  self.assertEqual(limits,dict(connections=16,waiting=64,wait_seconds=2));self.assertEqual(audit['effective'],dict(http_concurrency=64,db_concurrency=16,web_concurrency=128,pool_max_waiters=64,pool_wait_seconds=2))
 def test_parser_rejects_other_budgets_even_with_profile(self):
  args=http_tests.HTTP64Profile().args();args.update(db_concurrency=16,backend_profile=FOUR_DB16_PROFILE['id'])
  for key,value in [('db_concurrency',32),('pool_max_waiters',32),('pool_max_waiters',65),('http_concurrency',32),('admission_mode','bounded-v7'),('backend_profile','other')]:
   with self.subTest(key=key),self.assertRaises(ValueError):resolve_database_pool('bounded-v2',**{**args,key:value})
 def test_unclosed_fourth_node_is_not_hidden(self):
  from tools.loadtest_lab.process_runtime import _aggregate_counters
  rows=[dict(max_size=4,closed=True,wait_timeout=2)for _ in range(4)];rows[-1]['closed']=False
  self.assertEqual(_aggregate_counters(rows,{'wait_timeout'}),dict(max_size=16,closed=False,wait_timeout=2))
if __name__=='__main__':unittest.main()
