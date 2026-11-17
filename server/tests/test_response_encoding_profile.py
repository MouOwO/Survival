import ast,copy,io,sys,unittest
from pathlib import Path
from unittest.mock import patch
from contextlib import redirect_stdout
from tools.loadtest_lab.guard import validate_response_encoding_pool
class ResponseProfileTests(unittest.TestCase):
 def cfg(self,workers=3):return {'purpose':'capacity','process_topology':'split-v1','process_observation':'pid-v1','sources':{'runtime/player_web_auth/response_pool.py':'a'*64},'response_encoding_pool':{'id':'pure-process-v1','workers':workers,'max_pending':workers*8,'wait_seconds':2}}
 def test_baseline_has_no_encoder(self):self.assertIsNone(validate_response_encoding_pool({}))
 def test_two_and_three_are_explicit_bounded_profiles(self):
  for n in (2,3):
   cfg=self.cfg(n);before=copy.deepcopy(cfg);self.assertEqual(validate_response_encoding_pool(cfg),cfg['response_encoding_pool']);self.assertEqual(cfg,before)
 def test_unknown_worker_counts_waiting_or_fields_fail(self):
  for key,value in [('workers',True),('workers',4),('max_pending',25),('max_pending',16),('wait_seconds',0),('wait_seconds',3),('id','unknown')]:
   cfg=self.cfg();cfg['response_encoding_pool'][key]=value
   with self.assertRaises(ValueError):validate_response_encoding_pool(cfg)
  cfg=self.cfg();cfg['response_encoding_pool']['extra']=1
  with self.assertRaises(ValueError):validate_response_encoding_pool(cfg)
 def test_non_capacity_same_process_or_unobserved_fail(self):
  for key,value in [('purpose','functional-smoke'),('process_topology','same-v1'),('process_observation',None)]:
   cfg=self.cfg();cfg[key]=value
   with self.assertRaises(ValueError):validate_response_encoding_pool(cfg)
 def test_missing_or_unbound_helper_fails(self):
  for value in (None,{}, {'runtime/player_web_auth/response_pool.py':'bad'}):
   cfg=self.cfg();cfg['sources']=value or{}
   with self.assertRaises(ValueError):validate_response_encoding_pool(cfg)
 def test_real_cli_accepts_pool3(self):
  from tools.loadtest_lab import cli
  with patch.object(cli,'prepare',return_value={'ok':True})as prepare,redirect_stdout(io.StringIO()):
   self.assertEqual(cli.main(['prepare','--directory','fixture','--source-receipt','fixture.json','--response-encoding','pool3-v1']),0)
  self.assertEqual(prepare.call_args.args[0].response_encoding,'pool3-v1')
 def test_actual_generated_launcher_does_not_run_entry_when_spawn_imports(self):
  root=Path(__file__).resolve().parents[2];tree=ast.parse((root/'tools/loadtest_lab/cli.py').read_text(encoding='utf-8-sig'));prepare=next(n for n in tree.body if isinstance(n,ast.FunctionDef)and n.name=='prepare');assignment=next(n for n in ast.walk(prepare)if isinstance(n,ast.Assign)and any(isinstance(t,ast.Name)and t.id=='runner'for t in n.targets));runner=ast.literal_eval(assignment.value);before=list(sys.path)
  try:
   sys.path.insert(0,str(root/'tools'))
   from loadtest_lab import cli
   with patch.object(cli,'entry',side_effect=AssertionError('spawn_reentered_server'))as entry:
    exec(compile(runner,'fixture-run_lab.py','exec'),{'__name__':'__mp_main__','__file__':str(root/'fixture-run_lab.py')})
    entry.assert_not_called()
  finally:sys.path[:]=before
if __name__=='__main__':unittest.main()
