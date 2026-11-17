import copy,unittest
from tools.loadtest_lab.process_runtime import FOUR_PROFILE,validate_backend_pair,_node_cfg,_aggregate_counters
from tools.loadtest_lab.monitor import _pm_scope
from tools.loadtest_lab.experiments import http_admission_backlog
from tools.loadtest_lab.guard import canonical,sha
from server.tests import test_backend_pair_profile as pair_tests
class BackendFourTests(unittest.TestCase):
 def cfg(self):
  cfg=pair_tests.BackendPairTests().cfg();cfg['backend_process_pool']=dict(FOUR_PROFILE);return cfg
 def test_total_capacity_unchanged_and_nodes_bounded(self):
  cfg=self.cfg();old=copy.deepcopy(cfg);self.assertEqual(validate_backend_pair(cfg),FOUR_PROFILE);node=_node_cfg(cfg)
  self.assertEqual((node['http_concurrency'],node['database_pool_limits']),(16,dict(connections=8,waiting=16,wait_seconds=2)));self.assertEqual(cfg,old)
 def test_explicit_four_profile_cannot_expand_any_allocation(self):
  for k,v in [('workers',3),('per_worker_http',17),('per_worker_connections',9),('per_worker_waiters',17),('wait_seconds',3)]:
   cfg=self.cfg();cfg['backend_process_pool'][k]=v
   with self.subTest(k=k),self.assertRaises(ValueError):validate_backend_pair(cfg)
 def test_third_and_fourth_counters_are_verified(self):
  rows=[dict(max_size=8,total=i,closed=True,wait_timeout=2)for i in range(4)];self.assertEqual(_aggregate_counters(rows,{'wait_timeout'}),dict(max_size=32,total=6,closed=True,wait_timeout=2))
  rows[2]['wait_timeout']=3
  with self.assertRaises(ValueError):_aggregate_counters(rows,{'wait_timeout'})
 def test_any_unclosed_node_keeps_aggregate_open(self):
  rows=[dict(closed=True)for _ in range(4)];rows[3]['closed']=False;self.assertEqual(_aggregate_counters(rows,set()),{'closed':False})
 def test_all_four_listener_queues_reported(self):
  cfg=self.cfg();self.assertEqual(http_admission_backlog(cfg),512);self.assertEqual(http_admission_backlog(_node_cfg(cfg)),128)
 def test_five_native_processes_required_without_role_aliases(self):
  cfg=self.cfg();scope=pair_tests.BackendPairTests().scope(cfg);scope['processes'] += [dict(pid=103+i,starttime_ticks=203+i,boot_id_sha256='c'*64,exe_sha256='d'*64,roles=['backend'+str(i+2)])for i in range(2)];scope['manifest_sha256']=sha(canonical(cfg));self.assertEqual(_pm_scope(cfg,scope),scope)
  for change in ('missing_last','duplicate_last_PID','wrong_last_role'):
   bad=copy.deepcopy(scope)
   if change=='missing_last':bad['processes'].pop()
   if change=='duplicate_last_PID':bad['processes'][-1]['pid']=bad['processes'][1]['pid']
   if change=='wrong_last_role':bad['processes'][-1]['roles']=['backend2']
   with self.subTest(change=change),self.assertRaises(ValueError):_pm_scope(cfg,bad)
if __name__=='__main__':unittest.main()
