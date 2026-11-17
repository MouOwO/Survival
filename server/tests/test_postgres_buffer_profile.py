"""A fixed PG cache option changes only declared startup memory, never SQL semantics."""
import copy,json,unittest
from tools.loadtest_lab.guard import validate_postgres_cache,postgres_command
class PostgresBufferProfileTests(unittest.TestCase):
 def cfg(self):return dict(purpose='capacity',database_memory_mib=4096,database_cpu_limit=4,database_resource_profile='db16-4cpu-4g-v1',postgres_cache=dict(id='buffers1g-v1',shared_buffers_mib=1024))
 def test_default_command_remains_byte_identical(self):
  self.assertEqual(json.dumps(postgres_command({})), '["postgres", "-p", "25432", "-c", "listen_addresses=127.0.0.1"]')
 def test_explicit_profile_adds_one_fixed_setting_only(self):
  cfg=self.cfg();old=copy.deepcopy(cfg);self.assertEqual(postgres_command(cfg),postgres_command({})+['-c','shared_buffers=1024MB']);self.assertEqual(cfg,old)
 def test_fresh_command_lists_cannot_change_next_launch(self):
  first=postgres_command(self.cfg());first.append('bad');self.assertNotIn('bad',postgres_command(self.cfg()))
 def test_other_sizes_types_and_unknown_keys_refused(self):
  for key,value in [('shared_buffers_mib',512),('shared_buffers_mib',2048),('shared_buffers_mib',1024.0),('shared_buffers_mib',True),('id','other'),('extra',1)]:
   cfg=self.cfg();cfg['postgres_cache'][key]=value
   with self.subTest(key=key,value=value),self.assertRaises(ValueError):validate_postgres_cache(cfg)
 def test_wrong_host_or_purpose_cannot_borrow_profile(self):
  for key,value in [('purpose','production'),('database_memory_mib',2048),('database_memory_mib',8192),('database_memory_mib',4096.0),('database_cpu_limit',8),('database_resource_profile','db8-2cpu-2g-v1')]:
   cfg=self.cfg();cfg[key]=value
   with self.subTest(key=key),self.assertRaises(ValueError):postgres_command(cfg)
 def test_both_original_fixed_connection_budgets_supported(self):
  for profile in ['db16-4cpu-4g-v1','db32-4cpu-4g-v1']:
   cfg=self.cfg();cfg['database_resource_profile']=profile;self.assertEqual(validate_postgres_cache(cfg)['shared_buffers_mib'],1024)
 def test_command_fragments_cannot_be_supplied_by_configuration(self):
  cfg=self.cfg();cfg['postgres_cache']['shared_buffers_mib']='1024MB -c other=1'
  with self.assertRaises(ValueError):postgres_command(cfg)
if __name__=='__main__':unittest.main()
