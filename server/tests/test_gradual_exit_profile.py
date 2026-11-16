import unittest,copy
from tools.loadtest_lab.guard import validate_exit_probe
class GradualProfileTests(unittest.TestCase):
 def cfg(self,active=2000):
  return dict(purpose='capacity',client_workload='client-v3',actor_progress={'id':'active-business-v1','ttl_seconds':120},active=active,exit_probe_common_seconds=60 if active==2 else 300,exit_smoothing='gradual120-v1',exit_wave_seconds=2 if active==2 else 120,generator_transport={'id':'ssh-quad-v1','loopback_ports':[29567,29568,29569,29570]})
 def test_full_wave_exact120(self):self.assertEqual(validate_exit_probe(self.cfg()),{'common_seconds':300,'mode':'gradual120-v1','wave_seconds':120})
 def test_native_wave_only2(self):self.assertEqual(validate_exit_probe(self.cfg(2))['wave_seconds'],2)
 def test_wrong_windows_and_types_refused(self):
  for active,values in [(2,[120,2.0,True,None]),(2000,[2,120.0,True,None,60,121])]:
   for value in values:
    cfg=self.cfg(active);cfg['exit_wave_seconds']=value
    with self.assertRaises(ValueError):validate_exit_probe(cfg)
 def test_quad_binding_is_mandatory(self):
  cfg=self.cfg();cfg.pop('generator_transport')
  with self.assertRaises(ValueError):validate_exit_probe(cfg)
 def test_orphan_wave_refused(self):
  cfg=self.cfg();cfg['exit_smoothing']='direct'
  with self.assertRaises(ValueError):validate_exit_probe(cfg)
  cfg.pop('exit_probe_common_seconds');cfg.pop('exit_smoothing')
  with self.assertRaises(ValueError):validate_exit_probe(cfg)
 def test_legacy_probe_unchanged_and_cfg_not_mutated(self):
  cfg=self.cfg();cfg['exit_smoothing']='direct';cfg.pop('exit_wave_seconds');old=copy.deepcopy(cfg);self.assertEqual(validate_exit_probe(cfg),{'common_seconds':300,'mode':'direct'});self.assertEqual(cfg,old)
if __name__=='__main__':unittest.main()
