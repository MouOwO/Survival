import unittest,copy,ast
from pathlib import Path
from tools.loadtest_lab.guard import generator_ports,generator_url,target_url
class TransportTests(unittest.TestCase):
 def cfg(self):return dict(purpose='capacity',client_workload='client-v3',actor_progress={'id':'active-business-v1','ttl_seconds':120},generator_transport={'id':'ssh-quad-v1','loopback_ports':[29567,29568,29569,29570]})
 def test_legacy_fixed_target_stays_fixed(self):
  self.assertEqual(generator_ports({}),(29567,));self.assertEqual(generator_url({},17),'http://127.0.0.1:29567')
  for url in ['http://127.0.0.1:29568','https://127.0.0.1:29567','http://example.com:29567','http://localhost:29567']:
   with self.assertRaises(ValueError):target_url(url)
 def test_explicit_quad_is_exact_and_balanced(self):
  cfg=self.cfg();original=copy.deepcopy(cfg);urls=[generator_url(cfg,i)for i in range(2000)]
  for port in range(29567,29571):self.assertEqual(urls.count('http://127.0.0.1:'+str(port)),500)
  self.assertEqual(cfg,original)
 def test_unknown_duplicate_extra_or_noninteger_ports_rejected(self):
  for ports in [[29567]*4,[29567,29568,29569,443],[29567,29568,29569,29570,29571],[29567,29568,29569,True],['29567',29568,29569,29570],None]:
   cfg=self.cfg();cfg['generator_transport']['loopback_ports']=ports
   with self.assertRaises(ValueError):generator_ports(cfg)
  for value in ['ssh-quad-v1',{'id':'unknown','loopback_ports':[29567,29568,29569,29570]},{**self.cfg()['generator_transport'],'host':'remote'}]:
   cfg=self.cfg();cfg['generator_transport']=value
   with self.assertRaises(ValueError):generator_ports(cfg)
 def test_non_capacity_or_unbound_profiles_rejected(self):
  for k,v in [('purpose','functional-smoke'),('client_workload','legacy-v1'),('actor_progress',None)]:
   cfg=self.cfg();cfg[k]=v
   with self.assertRaises(ValueError):generator_ports(cfg)
 def test_invalid_indices_rejected(self):
  for i in [-1,True,'0',1000001,None]:
   with self.assertRaises(ValueError):generator_url(self.cfg(),i)
 def test_runtime_routes_once_before_player_and_no_request_rewrite(self):
  source=(Path(__file__).resolve().parents[2]/'tools/loadtest_lab/locustfile.py').read_text(encoding='utf8');tree=ast.parse(source);calls=[n for n in ast.walk(tree)if isinstance(n,ast.Call)and isinstance(n.func,ast.Name)and n.func.id=='generator_url'];self.assertEqual(len(calls),1)
  user=next(n for n in tree.body if isinstance(n,ast.ClassDef)and n.name=='SyntheticPlayer');start=next(n for n in user.body if isinstance(n,ast.FunctionDef)and n.name=='on_start');self.assertIn(calls[0],list(ast.walk(start)))
 def test_sixteen_is_fixed_and_balanced_for4000(self):
  cfg=self.cfg();cfg['generator_transport']={'id':'ssh-16-v1','loopback_ports':list(range(29567,29583))};before=copy.deepcopy(cfg);urls=[generator_url(cfg,i)for i in range(4000)]
  for port in range(29567,29583):self.assertEqual(urls.count('http://127.0.0.1:'+str(port)),250)
  self.assertEqual(cfg,before)
 def test_sixteen_cannot_choose_other_ports_or_unbounded_count(self):
  for ports in [list(range(29567,29582)),list(range(29567,29584)),list(reversed(range(29567,29583))),[443]+list(range(29568,29583)),[True]+list(range(29568,29583))]:
   cfg=self.cfg();cfg['generator_transport']={'id':'ssh-16-v1','loopback_ports':ports}
   with self.assertRaises(ValueError):generator_ports(cfg)
 def test_native_loopback_is_explicit_fixed_and_full_actor_safe(self):
  cfg=self.cfg();cfg['generator_transport']={'id':'linux-loopback-v1','loopback_ports':[29567]};before=copy.deepcopy(cfg)
  self.assertEqual(generator_ports(cfg),(29567,))
  for actor in (0,1,3999,1000000):self.assertEqual(generator_url(cfg,actor),'http://127.0.0.1:29567')
  self.assertEqual(cfg,before)
 def test_native_loopback_cannot_redirect_or_create_extra_listeners(self):
  for ports in ([443],[29568],[29567,29568],['29567'],[True],[]):
   cfg=self.cfg();cfg['generator_transport']={'id':'linux-loopback-v1','loopback_ports':ports}
   with self.assertRaises(ValueError):generator_ports(cfg)
 def test_native_gradual_exit_retains_120s_and_requires_explicit_profile(self):
  from tools.loadtest_lab.guard import validate_exit_probe
  cfg=self.cfg();cfg.update(active=4000,exit_probe_common_seconds=3600,exit_smoothing='gradual120-v1',exit_wave_seconds=120,generator_transport={'id':'linux-loopback-v1','loopback_ports':[29567]})
  self.assertEqual(validate_exit_probe(cfg),dict(common_seconds=3600,mode='gradual120-v1',wave_seconds=120))
  for key,value in [('exit_wave_seconds',2),('generator_transport',None),('purpose','functional-smoke')]:
   bad=copy.deepcopy(cfg);bad[key]=value
   with self.assertRaises(ValueError):validate_exit_probe(bad)
 def test_actual_CLI_parses_explicit_native_transport(self):
  from unittest.mock import patch
  from tools.loadtest_lab import cli
  with patch.object(cli,'prepare',return_value={'ok':True})as prepare,patch('builtins.print'):
   self.assertEqual(cli.main(['prepare','--directory','fixture-native-output','--source-receipt','fixture-public-source.json','--generator-transport','linux-loopback-v1']),0)
   self.assertEqual(prepare.call_args.args[0].generator_transport,'linux-loopback-v1')
if __name__=='__main__':unittest.main()
