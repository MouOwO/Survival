import copy,io,unittest
from contextlib import redirect_stdout
from unittest.mock import patch
from tools.loadtest_lab.rpc_process_pool import validate_profile
class RpcProfileTests(unittest.TestCase):
 def cfg(self):return {'purpose':'capacity','process_topology':'split-v1','process_observation':'pid-v1','db_concurrency':16,'database_pool_limits':{'connections':16,'waiting':32,'wait_seconds':2.0},'rpc_process_pool':{'id':'driver-process3-v1','workers':3,'max_pending':24,'queue_seconds':2},'sources':{'operator/loadtest_lab/rpc_process_pool.py':'a'*64,'runtime/player_web_auth/response_pool.py':'b'*64}}
 def test_default_has_no_rpc_processes(self):self.assertIsNone(validate_profile({}))
 def test_original_total_database_budget_is_retained(self):
  cfg=self.cfg();old=copy.deepcopy(cfg);self.assertEqual(validate_profile(cfg),cfg['rpc_process_pool']);self.assertEqual(cfg,old)
 def test_undeclared_or_unbounded_options_rejected(self):
  for key,value in [('workers',4),('max_pending',25),('queue_seconds',3),('id','unknown'),('extra',1)]:
   cfg=self.cfg();cfg['rpc_process_pool'][key]=value
   with self.assertRaises(ValueError):validate_profile(cfg)
 def test_non_isolated_unobserved_or_different_database_budget_rejected(self):
  for key,value in [('purpose','functional-smoke'),('process_topology','same-v1'),('process_observation',None),('db_concurrency',8),('database_pool_limits',{'connections':16,'waiting':64,'wait_seconds':2})]:
   cfg=self.cfg();cfg[key]=value
   with self.assertRaises(ValueError):validate_profile(cfg)
 def test_required_actual_consumers_cannot_be_omitted(self):
  for key in self.cfg()['sources']:
   cfg=self.cfg();del cfg['sources'][key]
   with self.assertRaises(ValueError):validate_profile(cfg)
 def test_actual_cli_exposes_only_explicit_optin(self):
  from tools.loadtest_lab import cli
  with patch.object(cli,'prepare',return_value={'ok':True})as call,redirect_stdout(io.StringIO()):
   self.assertEqual(cli.main(['prepare','--directory','fixture','--source-receipt','fixture.json','--rpc-processes','driver-process3-v1']),0)
  self.assertEqual(call.call_args.args[0].rpc_processes,'driver-process3-v1')
 def test_fixed_monitor_accepts_exact_three_additional_worker_identities(self):
  from tools.loadtest_lab.guard import canonical,sha
  from tools.loadtest_lab.monitor import _pm_scope
  cfg=self.cfg();cfg['run_id']='a'*32
  scope={'schema':1,'id':'pid-v1','run_id':cfg['run_id'],'manifest_sha256':sha(canonical(cfg)),'postgres_container_name':'survival-loadtest-'+cfg['run_id'][:12],'processes':[{'pid':i+10,'starttime_ticks':100+i,'boot_id_sha256':'b'*64,'exe_sha256':'c'*64,'roles':[role]}for i,role in enumerate(('frontend','backend','rpc0','rpc1','rpc2'))]}
  self.assertEqual(_pm_scope(cfg,scope),scope)
  bad=copy.deepcopy(scope);bad['processes'][4]['roles']=['rpc0']
  with self.assertRaises(ValueError):_pm_scope(cfg,bad)
  bad=copy.deepcopy(scope);bad['processes'].pop()
  with self.assertRaises(ValueError):_pm_scope(cfg,bad)
  del cfg['rpc_process_pool'];scope['manifest_sha256']=sha(canonical(cfg))
  with self.assertRaises(ValueError):_pm_scope(cfg,scope)
 def test_actual_monitor_constructor_indexes_seven_fixed_processes(self):
  from pathlib import Path
  from types import SimpleNamespace
  from tools.loadtest_lab import monitor as m
  from tools.loadtest_lab.guard import canonical,sha
  cfg=self.cfg();cfg['run_id']='a'*32
  roles=('frontend','backend','rpc0','rpc1','rpc2')
  rows=[{'pid':i+10,'starttime_ticks':100+i,'boot_id_sha256':'b'*64,'exe_sha256':'c'*64,'roles':[role]}for i,role in enumerate(roles)]
  scope={'schema':1,'id':'pid-v1','run_id':cfg['run_id'],'manifest_sha256':sha(canonical(cfg)),'postgres_container_name':'survival-loadtest-'+cfg['run_id'][:12],'processes':rows};raw=canonical(scope)
  def identity(pid):return {'pid':pid,'starttime_ticks':100,'boot_id_sha256':'b'*64,'exe_sha256':'c'*64}
  with patch.object(Path,'is_file',return_value=True),patch.object(Path,'is_symlink',return_value=False),patch.object(Path,'stat',return_value=SimpleNamespace(st_size=len(raw))),patch.object(Path,'read_bytes',return_value=raw),patch.object(m,'_pm_boot_hash',return_value='b'*64),patch.object(m.os,'sysconf',return_value=100,create=True),patch.object(m,'_pm_capture',side_effect=[(identity(999),None),(identity(998),None)]),patch.object(m,'_pm_inspect',return_value={'pid':998}),patch.object(m,'_ObservedProcess')as process,patch.object(m,'_ObservedCgroup')as group:
   group.return_value.public={};observer=m._ProcessObservation(Path('rpc-monitor-fixture'),cfg)
  self.assertEqual(process.call_count,7);self.assertEqual(len(observer.header['processes']),7)
  self.assertEqual({r for row in observer.header['processes']for r in row['roles']},set(roles)|{'monitor','postgres_init'})
if __name__=='__main__':unittest.main()
