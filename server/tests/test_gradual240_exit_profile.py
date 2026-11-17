import copy,unittest,ast,types
from pathlib import Path
from tools.loadtest_lab.guard import validate_exit_probe
class Gradual240ProfileTests(unittest.TestCase):
 def cfg(self,active=3500,mode='gradual240-v1'):
  return dict(purpose='capacity',client_workload='client-v3',actor_progress={'id':'active-business-v1','ttl_seconds':120},active=active,exit_probe_common_seconds=60 if active==2 else 3600,exit_smoothing=mode,exit_wave_seconds=2 if active==2 else(240 if mode=='gradual240-v1'else 120),generator_transport={'id':'linux-loopback-v1','loopback_ports':[29567]})
 def test_explicit_240_and_old120_are_distinct(self):
  for mode,seconds in [('gradual120-v1',120),('gradual240-v1',240)]:
   c=self.cfg(mode=mode);old=copy.deepcopy(c);self.assertEqual(validate_exit_probe(c),dict(common_seconds=3600,mode=mode,wave_seconds=seconds));self.assertEqual(c,old)
 def test_native2_stays_2seconds(self):
  for mode in('gradual120-v1','gradual240-v1'):self.assertEqual(validate_exit_probe(self.cfg(2,mode))['wave_seconds'],2)
 def test_forged_windows_types_and_old_name_cannot_select240(self):
  for mode,values in [('gradual240-v1',[120,240.0,True,None,241]),('gradual120-v1',[240,120.0,True])]:
   for value in values:
    c=self.cfg(mode=mode);c['exit_wave_seconds']=value
    with self.subTest(mode=mode,value=value),self.assertRaises(ValueError):validate_exit_probe(c)
 def test_orphan_and_wrong_environment_refused(self):
  for key,value in [('purpose','production'),('client_workload','legacy-v1'),('actor_progress',None),('exit_probe_common_seconds',None),('generator_transport',None)]:
   c=self.cfg();c[key]=value
   with self.subTest(key=key),self.assertRaises((ValueError,TypeError)):validate_exit_probe(c)
 def test_existing_personal_45_budget_remains_literal(self):
  source=(Path(__file__).resolve().parents[2]/'tools/loadtest_lab/locustfile.py').read_text();tree=ast.parse(source);cls=next(x for x in tree.body if isinstance(x,ast.ClassDef)and x.name=='SyntheticPlayer');onstop=next(x for x in cls.body if isinstance(x,ast.FunctionDef)and x.name=='on_stop');self.assertIn('personal+45-time.monotonic()',ast.get_source_segment(source,onstop))
if __name__=='__main__':unittest.main()
