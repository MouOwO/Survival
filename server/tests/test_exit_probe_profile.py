import sys,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'tools'))
from loadtest_lab.guard import validate_exit_probe
class ExitProbeTests(unittest.TestCase):
 def cfg(self,**changes):
  c=dict(purpose='capacity',active=2000,client_workload='client-v3',actor_progress={'id':'active-business-v1','ttl_seconds':120},exit_probe_common_seconds=300,exit_smoothing='direct');c.update(changes);return c
 def test_old_default_has_no_probe(self):self.assertIsNone(validate_exit_probe({}))
 def test_large_probe_is_five_minutes(self):self.assertEqual(validate_exit_probe(self.cfg()),dict(common_seconds=300,mode='direct'))
 def test_native_smoke_is_explicit_one_minute(self):self.assertEqual(validate_exit_probe(self.cfg(active=2,exit_probe_common_seconds=60))['common_seconds'],60)
 def test_only_explicit_bounded_modes(self):
  for mode in ['direct','jitter3-v1','queue32-v1','queue64-v1','queue128-v1']:self.assertEqual(validate_exit_probe(self.cfg(exit_smoothing=mode))['mode'],mode)
 def test_reject_ambiguous_or_unbounded_policy(self):
  for change in [dict(exit_smoothing='queue2000-v1'),dict(exit_smoothing='jitter60'),dict(exit_probe_common_seconds=True),dict(exit_probe_common_seconds=0),dict(exit_probe_common_seconds=60),dict(purpose='functional-smoke'),dict(client_workload='legacy-v1'),dict(actor_progress={'id':'active-business-v1','ttl_seconds':121})]:
   with self.subTest(change=change),self.assertRaises(ValueError):validate_exit_probe(self.cfg(**change))
 def test_smoothing_cannot_be_silent_legacy_change(self):
  with self.assertRaises(ValueError):validate_exit_probe({'exit_smoothing':'queue64-v1'})
if __name__=='__main__':unittest.main()
