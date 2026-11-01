"""Local synthetic files/SQLite/HTTP; no SSH, deployed service or real-player I/O."""
from pathlib import Path
import copy,hashlib,importlib.util,json,os,tempfile,unittest
from unittest.mock import patch

HERE=Path(__file__).resolve().parent
def module(name,path):
 spec=importlib.util.spec_from_file_location(name,path);value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value);return value
op=module('five_admission_operator_test',HERE/'server_operator.py')
driver=module('five_admission_driver_test',HERE/'server_driver.py')


class ScopeTests(unittest.TestCase):
 def plan(self):
  release='20261101-admission-five-0123456789ab'
  return {'schema':1,'source_revision':'a'*40,'release':release,
    'stage':'/root/goufayu_upload/admission-five-'+release,'approved_steamids64':list(op.IDS),
    'max_players':4,'overlay':{name:{'sha256':'b'*64} for name in op.SOURCE}}

 def test_environment_changes_only_roster_and_exact_own_addon_path(self):
  original=('SURVIVAL_TEST_STEAM_IDS64='+json.dumps(','.join(op.OLD_IDS))+'\nFISHING_ADDON_ROOT="/old/addon"\nSECRET="keep=this"\nRELAY=1\n').encode()
  changed=op.replace_env(original,'SURVIVAL_TEST_STEAM_IDS64',old_root='/old',new_root='/new')
  before,after=map(op.parse_env,(original,changed))
  self.assertEqual(after['SURVIVAL_TEST_STEAM_IDS64'],','.join(op.IDS))
  self.assertEqual(after['FISHING_ADDON_ROOT'],'/new/addon')
  self.assertEqual({k:v for k,v in before.items() if k not in ('SURVIVAL_TEST_STEAM_IDS64','FISHING_ADDON_ROOT')},
                   {k:v for k,v in after.items() if k not in ('SURVIVAL_TEST_STEAM_IDS64','FISHING_ADDON_ROOT')})
  self.assertIn(b'SECRET="keep=this"\nRELAY=1\n',changed)

 def test_environment_rejects_duplicate_keys_or_changed_original_accounts(self):
  valid=('PLAYER_WEB_AUTH_STEAM_IDS='+','.join(op.OLD_IDS)+'\n').encode()
  for raw in (valid+valid,valid.replace(op.OLD_IDS[0].encode(),op.ADDED.encode()),b'OTHER=1\n'):
   with self.subTest(raw=raw),self.assertRaises(RuntimeError):op.replace_env(raw,'PLAYER_WEB_AUTH_STEAM_IDS')

 def test_unit_requires_actual_old_working_directory_and_preserves_other_lines(self):
  raw=b'[Service]\nWorkingDirectory=/old/backend\nExecStart=/old/.venv/bin/python -B -m workshop_test.run_api\nEnvironmentFile=/etc/fixed.env\n'
  for prefix in (b'',b' ',b'\t'):
   variant=raw.replace(b'WorkingDirectory=',prefix+b'WorkingDirectory=')
   changed=op.patch_unit(variant,'/old','/new','backend')
   self.assertIn(prefix+b'WorkingDirectory=/new/backend',changed)
   self.assertIn(b'ExecStart=/new/.venv/bin/python',changed)
   self.assertIn(b'EnvironmentFile=/etc/fixed.env\n',changed)
   self.assertEqual(changed.replace(b'/new',b'/old'),variant)
  for bad in (raw.replace(b'/old/backend',b'/another/backend'),raw+b'WorkingDirectory=/old/backend\n',
              raw+b' WorkingDirectory=/old/backend\n',raw+b'\tWorkingDirectory=/old/backend\n'):
   with self.assertRaises(RuntimeError):op.patch_unit(bad,'/old','/new','backend')

 def test_plan_rejects_general_roster_widening_escape_or_room_limit_change(self):
  good=self.plan();op.validate_plan(good)
  for updates in ({'approved_steamids64':list(op.IDS)+['76561198296534616']},{'max_players':5},
                  {'stage':'/etc/new'},{'release':'../../other'},{'overlay':{}},{'source_revision':'dev'}):
   with self.subTest(updates=updates),self.assertRaises(RuntimeError):op.validate_plan({**good,**updates})

 def test_bounded_regular_file_rejects_directory_and_oversize(self):
  with tempfile.TemporaryDirectory() as directory:
   folder=Path(directory)
   with self.assertRaises(RuntimeError):op.regular(folder)
   path=folder/'oversized';path.write_bytes(b'1234')
   with patch.object(op,'MAX_FILE',3),self.assertRaises(RuntimeError):op.regular(path)

 def test_owned_replace_preserves_external_change(self):
  with tempfile.TemporaryDirectory() as directory:
   path=Path(directory)/'env';path.write_bytes(b'concurrent-administrator-edit')
   with self.assertRaises(RuntimeError):op.owned_replace(path,b'our-before',b'our-after')
   self.assertEqual(path.read_bytes(),b'concurrent-administrator-edit')

 def test_rollback_restores_only_owned_files_and_restarts_both_original_services(self):
  self.rollback_case(False)

 def test_rollback_keeps_concurrent_file_but_still_restores_other_files_and_starts_services(self):
  self.rollback_case(True)

 def rollback_case(self,concurrent):
  with tempfile.TemporaryDirectory() as directory:
   base=Path(directory);stage=base/'stage';stage.mkdir();roles={}
   for role in ('api','web'):
    config={'root':'/'+role,'cwd_suffix':'','key':role+'_IDS'}
    for kind in ('env','unit'):
     path=base/(role+'.'+kind);path.write_bytes(b'new-'+role.encode()+kind.encode());config[kind]=str(path)
     (stage/(role+'.'+kind+'.before')).write_bytes(b'old-'+role.encode()+kind.encode())
     (stage/(role+'.'+kind+'.after')).write_bytes(path.read_bytes())
    roles[role]=config
   if concurrent:Path(roles['api']['env']).write_bytes(b'concurrent')
   plan={'live':{'roles':{role:{'cwd':'/'+role} for role in roles},'protected':{}}}
   def fake_service(name):return {'pid':123,'cwd':'/api' if name.startswith('api') else '/web'}
   def fake_replace(path,before,after):
    self.assertEqual(Path(path).read_bytes(),before);Path(path).write_bytes(after)
   with patch.object(op,'ROLES',roles),patch.object(op,'PROTECTED',()),patch.object(op,'owned_replace',side_effect=fake_replace), \
       patch.object(op,'control') as control,patch.object(op,'command'),patch.object(op,'wait_http'), \
       patch.object(op,'service',side_effect=fake_service),patch.object(op,'process_env',return_value={role+'_IDS':','.join(op.OLD_IDS) for role in roles}), \
       patch.object(op,'health'),patch.object(op,'postgres_state') as postgres:
    result=op.restore_owned(plan,stage)
   self.assertEqual(result['ok'],not concurrent)
   self.assertFalse(result['database_restored']);postgres.assert_not_called()
   self.assertEqual(control.call_args_list,[(('stop','web'),),(('stop','api'),),(('start','api'),),(('start','web'),)])
   for role,config in roles.items():
    for kind in ('env','unit'):
     self.assertEqual(Path(config[kind]).read_bytes(),b'concurrent' if concurrent and (role,kind)==('api','env') else b'old-'+role.encode()+kind.encode())

 def test_activation_failure_reaches_owned_rollback_and_retains_failure_receipt(self):
  plan=self.plan();plan['live']={}
  with tempfile.TemporaryDirectory() as directory:
   stage=Path(directory)
   prepared={'status':'PREPARED_FIVE_ACCOUNT_ADMISSION_NOT_ACTIVE','candidate_inventories':{'api':{},'web':{}}}
   def fake_read(path):
    if path.name=='plan.json':return op.encoded(plan)
    if path.name=='prepared.json':return op.encoded(prepared)
    return b'fixture'
   with patch.object(op,'validate_plan',return_value=stage),patch.object(op,'regular',side_effect=fake_read), \
      patch.object(op,'verify_before'),patch.object(op,'inventory',return_value={}),patch.object(op,'target',return_value=Path('/safe/new')), \
      patch.object(op,'postgres_state',return_value={}),patch.object(op,'control'),patch.object(op,'sqlite_state',side_effect=RuntimeError('fixture_failure')), \
      patch.object(op,'restore_owned',return_value={'ok':True,'database_restored':False}) as restore,patch.object(op,'receipt') as saved:
    with self.assertRaisesRegex(RuntimeError,'rollback_ok'):op.activate(plan)
   restore.assert_called_once_with(plan,stage)
   self.assertEqual(saved.call_args.args[1],'activation_failed')
   self.assertFalse(saved.call_args.args[2]['database_restored'])

 def test_bare_tcp_readiness_preserves_sqlite_where_http_health_changes_limits(self):
  import sys,threading,urllib.request
  from types import SimpleNamespace
  sys.path.insert(0,str(HERE.parents[1]/'server'))
  from player_web_auth.service import Service,Settings
  from player_web_auth.http_api import BoundedServer,handler
  with tempfile.TemporaryDirectory() as directory:
   database=Path(directory)/'auth.sqlite3'
   service=Service(Settings(database,'a'*64,'b'*64,op.OLD_IDS))
   completed=threading.Event();base=handler(service)
   class ObservedHandler(base):
    def finish(self):
     try:super().finish()
     finally:completed.set()
   server=BoundedServer(('127.0.0.1',0),ObservedHandler)
   worker=threading.Thread(target=lambda:server.serve_forever(poll_interval=.01),daemon=True);worker.start()
   port=server.server_address[1]
   try:
    before=op.sqlite_state(database)
    with patch.object(op,'STARTUP_PORTS',(port,)):op.wait_socket(port)
    self.assertTrue(completed.wait(2),'the empty TCP request must finish before the SQLite comparison')
    self.assertEqual(op.sqlite_state(database),before)
    with urllib.request.urlopen('http://127.0.0.1:'+str(port)+'/health',timeout=2) as response:
     self.assertEqual(response.status,200);response.read()
    after=op.sqlite_state(database)
    self.assertNotEqual(after['tables']['limits'],before['tables']['limits'])
    self.assertEqual({k:v for k,v in after['tables'].items() if k!='limits'},
                     {k:v for k,v in before['tables'].items() if k!='limits'})
   finally:server.shutdown();server.server_close();worker.join(2);service.close()

 def test_tcp_readiness_rejects_other_ports_before_connecting(self):
  with patch.object(op.socket,'create_connection') as connect:
   with self.assertRaisesRegex(RuntimeError,'startup_port_not_allowed'):op.wait_socket(443)
   connect.assert_not_called()

 def test_full_sqlite_guard_precedes_any_http_health_probe(self):
  result,events,saved=self.activation_order_case(False)
  self.assertTrue(result['preservation_check_before_health'])
  self.assertTrue(result['health_rate_counters_expected'])
  self.assertLess(events.index('tcp:18767'),len(events)-1-events[::-1].index('sqlite'))
  self.assertLess(len(events)-1-events[::-1].index('sqlite'),events.index('health'))

 def test_unsolicited_limits_change_still_refuses_before_health(self):
  result,events,saved=self.activation_order_case(True)
  self.assertNotIn('health',events)
  self.assertEqual(saved.call_args.args[1],'activation_failed')
  self.assertEqual(saved.call_args.args[2]['error'],'auth_data_or_schema_changed_no_database_restore')
  self.assertFalse(saved.call_args.args[2]['database_restored'])

 def activation_order_case(self,changed):
  plan=self.plan();plan['live']={'protected':{}};events=[]
  before={'schema_sha256':'same','tables':{'limits':{'rows':1,'sha256':'before'}}}
  after={**before,'tables':{'limits':{'rows':2,'sha256':'unsolicited'}}} if changed else before
  counter=[0]
  def auth_state():
   events.append('sqlite');counter[0]+=1;return before if counter[0]==1 else after
  def pg_state():events.append('postgres');return {'same':True}
  with tempfile.TemporaryDirectory() as directory:
   stage=Path(directory);prepared={'status':'PREPARED_FIVE_ACCOUNT_ADMISSION_NOT_ACTIVE','candidate_inventories':{'api':{},'web':{}}}
   def fake_read(path):
    if path.name=='plan.json':return op.encoded(plan)
    if path.name=='prepared.json':return op.encoded(prepared)
    return b'fixture'
   with patch.object(op,'validate_plan',return_value=stage),patch.object(op,'regular',side_effect=fake_read), \
       patch.object(op,'verify_before'),patch.object(op,'inventory',return_value={}),patch.object(op,'target',return_value=Path('/safe/new')), \
       patch.object(op,'postgres_state',side_effect=pg_state),patch.object(op,'sqlite_state',side_effect=auth_state), \
       patch.object(op,'sqlite_backup',return_value={'state':before}),patch.object(op,'owned_replace'),patch.object(op,'control'), \
       patch.object(op,'command'),patch.object(op,'wait_socket',side_effect=lambda port:events.append('tcp:'+str(port))), \
       patch.object(op,'wait_http',side_effect=AssertionError('HTTP readiness is forbidden before preservation')), \
       patch.object(op,'running',return_value={}),patch.object(op,'evaluate_policy',return_value={}), \
       patch.object(op,'health',side_effect=lambda processes:events.append('health')),patch.object(op,'PROTECTED',()), \
       patch.object(op,'restore_owned',return_value={'ok':True,'database_restored':False}), \
       patch.object(op,'receipt',return_value={'path':'fixture','sha256':'a'*64}) as saved:
    if changed:
     with self.assertRaisesRegex(RuntimeError,'rollback_ok'):op.activate(plan)
     result=None
    else:result=op.activate(plan)
   return result,events,saved

 def test_failure_code_does_not_return_untrusted_exception_text(self):
  self.assertEqual(op.fixed_error_code(op.AdmissionGuardError('auth_data_or_schema_changed_no_database_restore')),
                   'auth_data_or_schema_changed_no_database_restore')
  for error in (RuntimeError('private_secret_value'),ValueError('https://user:secret@invalid/'),op.AdmissionGuardError('https://secret.invalid/')):
   self.assertEqual(op.fixed_error_code(error),'operation_failed')


class DriverTests(unittest.TestCase):
 def test_live_activation_requires_explicit_apply_and_reviewed_plan(self):
  target=driver.ROOT/'output/admission_five_20261101/test_never_written.json'
  args=['activate','--plan','not-opened.json','--reviewed-plan-sha256','a'*64,'--report',str(target)]
  with self.assertRaises(RuntimeError):driver.arguments(args)
  self.assertTrue(driver.arguments(args+['--apply']).apply)
  with self.assertRaises(RuntimeError):driver.arguments(['plan','--source-revision','a'*40,'--apply','--report',str(target)])

 def test_reviewed_plan_hash_and_exact_five_roster_are_mandatory(self):
  with tempfile.TemporaryDirectory() as directory:
   path=Path(directory)/'plan.json';value={'approved_steamids64':driver.IDS,'max_players':4}
   raw=driver.canonical(value);path.write_bytes(raw)
   self.assertEqual(driver.load_reviewed(path,hashlib.sha256(raw).hexdigest()),value)
   with self.assertRaises(RuntimeError):driver.load_reviewed(path,'a'*64)
   raw=driver.canonical({**value,'max_players':5});path.write_bytes(raw)
   with self.assertRaises(RuntimeError):driver.load_reviewed(path,hashlib.sha256(raw).hexdigest())

 def test_source_commit_cannot_execute_changed_working_operator(self):
  with patch.object(driver.subprocess,'check_output',return_value=('a'*40+'\n').encode()), \
      patch.object(driver,'blob',return_value=b'# unrelated operator\n'):
   with self.assertRaisesRegex(RuntimeError,'operator_changed_since_source_commit'):driver.committed('dev')


if __name__=='__main__':unittest.main()
