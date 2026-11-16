import sys,unittest
from pathlib import Path
from http.server import BaseHTTPRequestHandler
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'tools'))
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from loadtest_lab.guard import resolve_database_pool
from loadtest_lab.experiments import http_admission_backlog,http_admission_wait
from loadtest_lab.runtime import checked_http_admission_stats
from fishing_api_overrides.http_admission import BoundedAdmissionMixin
from fishing_api_overrides import http_admission_patch as patch

class BurstAdmissionTests(unittest.TestCase):
 def cfg(self,version):return dict(web_concurrency=128,http_concurrency=32,runtime_experiments=[{'id':'http-admission-v'+str(version)}])
 def test_legacy_backlogs_and_waits_preserved(self):
  for version in range(1,7):
   cfg=self.cfg(version)
   for layer in ['frontend','backend']:
    self.assertEqual(http_admission_backlog(cfg,layer=layer),128 if version>=4 else 64)
    self.assertEqual(http_admission_wait(cfg,layer=layer),0 if layer=='frontend' else 2)
 def test_explicit_burst_queue_only_frontend(self):
  cfg=self.cfg(7);self.assertEqual(http_admission_backlog(cfg,layer='frontend'),2048);self.assertEqual(http_admission_backlog(cfg,layer='backend'),128)
  self.assertEqual(http_admission_wait(cfg,layer='frontend'),2);self.assertEqual(http_admission_wait(cfg,layer='backend'),2)
 def test_unrecognized_layers_rejected(self):
  for layer in [None,'public','',True]:
   for fn in [http_admission_backlog,http_admission_wait]:
    with self.subTest(layer=layer),self.assertRaises(ValueError):fn(self.cfg(7),layer=layer)
 def test_only_exact_burst_configuration_can_expand_native_queue(self):
  obj=BoundedAdmissionMixin();obj._configure_admission(layer='frontend',max_concurrency=128,request_backlog=2048,admission_wait_seconds=2)
  self.assertEqual(obj.admission_stats()['active'],0);self.assertEqual(obj.admission_stats()['max_concurrency'],128)
  baseline=dict(layer='frontend',max_concurrency=128,request_backlog=2048,admission_wait_seconds=2)
  for change in [dict(layer='backend'),dict(max_concurrency=127),dict(max_concurrency=129),dict(request_backlog=4096),dict(request_backlog=2049),dict(request_backlog=True),dict(admission_wait_seconds=0),dict(admission_wait_seconds=3),dict(admission_wait_seconds=float('nan'))]:
   v={**baseline,**change}
   with self.subTest(change=change),self.assertRaises(ValueError):BoundedAdmissionMixin()._configure_admission(**v)
 def test_old_bounded_native_queues_still_valid(self):
  for layer in ['frontend','backend']:
   for size in [128,256]:
    obj=BoundedAdmissionMixin();obj._configure_admission(layer=layer,max_concurrency=32,request_backlog=size);self.assertEqual(obj.admission_stats()['backlog'],size)
 def test_db16_budget_unchanged(self):
  v=dict(http_concurrency=32,db_concurrency=16,web_concurrency=128,pool_max_waiters=32,pool_wait_seconds=2,admission_mode='bounded-v7');_,pool=resolve_database_pool('bounded-v2',**v);self.assertEqual(pool,dict(connections=16,waiting=32,wait_seconds=2))
  for change in [dict(db_concurrency=8),dict(web_concurrency=256),dict(http_concurrency=64),dict(pool_max_waiters=128)]:
   with self.subTest(change=change),self.assertRaises(ValueError):resolve_database_pool('bounded-v2',**{**v,**change})
 def test_actual_frontend_constructor_and_startup_gate(self):
  import threading
  from http.server import ThreadingHTTPServer
  ns=dict(BoundedAdmissionMixin=BoundedAdmissionMixin,ThreadingHTTPServer=ThreadingHTTPServer,threading=threading)
  exec(patch.NEW_FRONT,ns);cfg=self.cfg(7);server=ns['BoundedServer'](('127.0.0.1',0),BaseHTTPRequestHandler,max_concurrency=128,request_backlog=2048,admission_wait_seconds=2)
  try:
   result=checked_http_admission_stats(server,'frontend',cfg);self.assertEqual(result['backlog'],2048);self.assertEqual(result['max_concurrency'],128)
   with self.assertRaises(ValueError):checked_http_admission_stats(server,'frontend',self.cfg(6))
  finally:server.server_close()
 def test_actual_old_frontend_default_wait_is_zero(self):
  import threading
  from http.server import ThreadingHTTPServer
  ns=dict(BoundedAdmissionMixin=BoundedAdmissionMixin,ThreadingHTTPServer=ThreadingHTTPServer,threading=threading);exec(patch.NEW_FRONT,ns);server=ns['BoundedServer'](('127.0.0.1',0),BaseHTTPRequestHandler,max_concurrency=128,request_backlog=128)
  try:self.assertEqual(checked_http_admission_stats(server,'frontend',self.cfg(6))['accept_wait_seconds'],0)
  finally:server.server_close()
 def test_patch_helper_digest_and_native_ast_match(self):
  import hashlib,ast
  raw=Path(patch.__file__).with_name('http_admission.py').read_text(encoding='utf8').replace('\r\n','\n');self.assertEqual(hashlib.sha256(raw.encode()).hexdigest(),patch.HELPER_SHA256);ast.parse(patch.NEW_FRONT)

if __name__=='__main__':unittest.main()
