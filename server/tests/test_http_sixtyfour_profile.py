"""HTTP64 is explicit and cannot borrow a legacy or smaller DB budget."""
from copy import deepcopy
import unittest
from tools.loadtest_lab.guard import resolve_database_pool
from tools.loadtest_lab.experiments import SPECS,validate_experiments,http_admission_backlog,http_admission_wait
from server.fishing_api_overrides.http_admission64_patch import patch_sources
class HTTP64Profile(unittest.TestCase):
 def args(self):return dict(http_concurrency=64,db_concurrency=32,web_concurrency=128,pool_max_waiters=64,pool_wait_seconds=2,admission_mode='bounded-v8')
 def cfg(self):
  operators,inputs,outputs=SPECS['http-admission-v8'];row=dict(id='http-admission-v8',source_revision='a'*40,operator_sources={'operator/runtime_experiments/'+name:'a'*64 for name in operators},parent_runtime_sha256={'runtime/'+name:'c'*64 for name in inputs},runtime_sha256={'runtime/'+name:'b'*64 for name in outputs})
  return dict(purpose='capacity',csv_source_revision='a'*40,backend_db_pool='bounded-v2',database_resource_profile='db32-4cpu-4g-v1',database_cpu_limit=4,database_memory_mib=4096,http_concurrency=64,web_concurrency=128,db_concurrency=32,database_pool_limits={'connections':32,'waiting':64,'wait_seconds':2},runtime_experiments=[row],sources={**row['operator_sources'],**row['runtime_sha256']})
 def test_explicit64_keeps_database_bounded(self):
  args=self.args();old=deepcopy(args);_,limits=resolve_database_pool('bounded-v2',**args);self.assertEqual(limits,dict(connections=32,waiting=64,wait_seconds=2));self.assertEqual(args,old)
 def test_cannot_implicitly_expand_old_modes(self):
  for mode in ['baseline',*[f'bounded-v{i}'for i in range(1,8)]]:
   with self.subTest(mode=mode),self.assertRaises(ValueError):resolve_database_pool('bounded-v2',**{**self.args(),'admission_mode':mode})
 def test_exact_limits_reject_partial_or_excess_budget(self):
  for key,value in [('http_concurrency',32),('http_concurrency',65),('http_concurrency',True),('db_concurrency',16),('db_concurrency',31),('db_concurrency',33),('web_concurrency',127),('web_concurrency',129),('pool_max_waiters',32),('pool_max_waiters',65),('pool_wait_seconds',3)]:
   with self.subTest(key=key,value=value),self.assertRaises(ValueError):resolve_database_pool('bounded-v2',**{**self.args(),key:value})
 def test_overlay_binding_validates_without_mutation(self):
  cfg=self.cfg();old=deepcopy(cfg);self.assertTrue(validate_experiments(cfg));self.assertEqual(cfg,old)
 def test_overlay_cannot_reuse_16_connection_profile(self):
  for key,value in [('http_concurrency',32),('db_concurrency',16),('database_resource_profile','db16-4cpu-4g-v1'),('database_cpu_limit',8),('database_memory_mib',8192)]:
   cfg=self.cfg();cfg[key]=value
   with self.subTest(key=key,value=value),self.assertRaises(ValueError):validate_experiments(cfg)
 def test_original_queue_wait_and_frontend_backlog_unchanged(self):
  for identity in ['http-admission-v7','http-admission-v8']:
   cfg={'runtime_experiments':[{'id':identity}]}
   self.assertEqual(http_admission_backlog(cfg,layer='frontend'),2048);self.assertEqual(http_admission_backlog(cfg,layer='backend'),128)
   self.assertEqual(http_admission_wait(cfg,layer='frontend'),2);self.assertEqual(http_admission_wait(cfg,layer='backend'),2)
 def test_unknown_source_or_wrong_config_never_patches(self):
  with self.assertRaises(ValueError):patch_sources({})
  with self.assertRaisesRegex(ValueError,'exact_config_parent'):patch_sources(dict.fromkeys(['fishing_api/server.py','player_web_auth/http_api.py','fishing_api/config.py'],''))
if __name__=='__main__':unittest.main()
