"""Multi-backend limits and PID identity corruption cannot silently pass."""
import copy,unittest
from tools.loadtest_lab.process_runtime import validate_backend_pair,PAIR_PROFILE,_node_cfg,_aggregate_counters
from tools.loadtest_lab.guard import canonical,sha
from tools.loadtest_lab.monitor import _pm_scope
from tools.loadtest_lab.experiments import http_admission_backlog
from tools.loadtest_lab.rpc_process_pool import validate_profile
class BackendPairTests(unittest.TestCase):
 def cfg(self):return dict(backend_process_pool=dict(PAIR_PROFILE),purpose='capacity',process_topology='split-v1',process_observation='pid-v1',backend_db_pool='bounded-v2',db_concurrency=32,http_concurrency=64,web_concurrency=128,database_resource_profile='db32-4cpu-4g-v1',database_pool_limits=dict(connections=32,waiting=64,wait_seconds=2),runtime_experiments=[dict(id='http-admission-v8')],sources={'operator/loadtest_lab/process_runtime.py':'a'*64},run_id='b'*32)
 def test_unselected_old_configs_unchanged(self):
  cfg={'http_concurrency':32};self.assertIs(_node_cfg(cfg),cfg);self.assertIsNone(validate_backend_pair(cfg))
 def test_original_driver_nodes_no_rpc_ipc(self):
  cfg=self.cfg();old=copy.deepcopy(cfg);self.assertIsNone(validate_profile(cfg));node=_node_cfg(cfg)
  self.assertEqual(cfg,old);self.assertEqual((node['http_concurrency'],node['db_concurrency']),(32,16));self.assertEqual(node['database_pool_limits'],dict(connections=16,waiting=32,wait_seconds=2));self.assertIsNone(validate_profile(node))
 def test_pair_cannot_bypass_original_fixed_limits(self):
  for k,v in [('workers',3),('per_worker_http',64),('per_worker_connections',32),('per_worker_waiters',64),('wait_seconds',3),('extra',1)]:
   cfg=self.cfg();cfg['backend_process_pool'][k]=v
   with self.subTest(k=k),self.assertRaises(ValueError):validate_backend_pair(cfg)
 def test_pair_requires_isolated_observed_shared_database_profile(self):
  for k,v in [('purpose','production'),('process_topology','same-v1'),('process_observation',None),('backend_db_pool','baseline'),('db_concurrency',16),('http_concurrency',32),('database_resource_profile','db16-4cpu-4g-v1'),('rpc_process_pool',{'workers':32})]:
   cfg=self.cfg();cfg[k]=v
   with self.subTest(k=k),self.assertRaises(ValueError):validate_backend_pair(cfg)
 def test_sum_counters_is_not_average_or_primary_only(self):
  a=dict(max_size=16,total=3,closed=False,wait_timeout=2);b=dict(max_size=16,total=5,closed=True,wait_timeout=2)
  self.assertEqual(_aggregate_counters([a,b],{'wait_timeout'}),dict(max_size=32,total=8,closed=False,wait_timeout=2))
  with self.assertRaises(ValueError):_aggregate_counters([a,{**b,'wait_timeout':3}],{'wait_timeout'})
  with self.assertRaises(ValueError):_aggregate_counters([a,{**b,'missing':0}],{'wait_timeout'})
 def test_all_kernel_backlogs_accounted(self):
  cfg=self.cfg();self.assertEqual(http_admission_backlog(cfg),256);self.assertEqual(http_admission_backlog(_node_cfg(cfg)),128);self.assertEqual(http_admission_backlog(cfg,layer='frontend'),2048)
 def scope(self,cfg):return dict(schema=1,id='pid-v1',run_id=cfg['run_id'],manifest_sha256=sha(canonical(cfg)),postgres_container_name='survival-loadtest-'+cfg['run_id'][:12],processes=[dict(pid=i+100,starttime_ticks=200+i,boot_id_sha256='c'*64,exe_sha256='d'*64,roles=[role])for i,role in enumerate(('frontend','backend','backend1'))])
 def test_all_three_native_processes_required(self):
  cfg=self.cfg();scope=self.scope(cfg);self.assertEqual(_pm_scope(cfg,scope),scope)
  for corruption in ['missing','duplicate_pid','role_alias','unbound_hash']:
   broken=copy.deepcopy(scope)
   if corruption=='missing':broken['processes'].pop()
   if corruption=='duplicate_pid':broken['processes'][2]['pid']=100
   if corruption=='role_alias':broken['processes'][2]['roles']=['backend']
   if corruption=='unbound_hash':broken['manifest_sha256']='e'*64
   with self.subTest(corruption=corruption),self.assertRaises(ValueError):_pm_scope(cfg,broken)
if __name__=='__main__':unittest.main()
