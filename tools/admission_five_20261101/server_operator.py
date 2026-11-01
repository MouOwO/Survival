"""One-shot five-account admission maintenance; credentials stay on the host.

Preparation creates immutable source trees and private backups only. Activation
is separately reviewed, retains all data, and restores owned code/config on
failure. There is no OAuth approval, user provisioning, payment change or timer.
"""
from pathlib import Path
import base64, copy, hashlib, json, os, re, sqlite3, stat, subprocess, time

OLD_IDS = ('76561198424163156', '76561198845461206', '76561198104787442', '76561198974301984')
ADDED = '76561198296534615'
IDS = (*OLD_IDS, ADDED)
BUNDLE = 'd573588b64d2ea6d1431c856d52e0515b5ed471cfdf6af4456ff618d0f568488'
ROLES = {
 'api': {'unit': '/etc/systemd/system/goufayu-ws4.service', 'env': '/etc/goufayu-ws4/api.env',
         'root': '/opt/goufayu-ws4/releases/20261031-redemption-ws4-23e3ab768478',
         'key': 'SURVIVAL_TEST_STEAM_IDS64', 'cwd_suffix': 'backend'},
 'web': {'unit': '/etc/systemd/system/goufayu-ws4-web.service', 'env': '/etc/goufayu-ws4-web/auth.env',
         'root': '/opt/goufayu-ws4-web/releases/20261031-game-diagnostics-v2',
         'key': 'PLAYER_WEB_AUTH_STEAM_IDS', 'cwd_suffix': ''}}
SOURCE = {
 'server/archive_backend/test_access.py': ('api', 'backend/archive_backend/test_access.py'),
 'server/workshop_test/run_api.py': ('api', 'backend/workshop_test/run_api.py'),
 'server/player_web_auth/service.py': ('web', 'player_web_auth/service.py')}
PROTECTED = ('goufayu-api.service','goufayu-payment.service','goufayu-db.service',
             'goufayu-ws4-db.service','goufayu-ws4-payment.service','nginx.service')
PINS = Path('/etc/goufayu-ws4/pins.json')
SQLITE = Path('/var/lib/goufayu-ws4-web/auth.sqlite3')
MAX_FILE = 16 * 1024 * 1024


def need(value, code):
 if not value: raise RuntimeError(code)


def sha(raw): return hashlib.sha256(raw).hexdigest()
def encoded(value): return (json.dumps(value,sort_keys=True,separators=(',',':'))+'\n').encode()


def regular(path):
 path=Path(path);info=path.lstat()
 need(stat.S_ISREG(info.st_mode) and info.st_size <= MAX_FILE,'regular_bounded_file_required')
 descriptor=os.open(path,os.O_RDONLY|getattr(os,'O_NOFOLLOW',0))
 with os.fdopen(descriptor,'rb') as stream:
  observed=os.fstat(stream.fileno());need(stat.S_ISREG(observed.st_mode) and observed.st_size==info.st_size,'file_identity_changed')
  raw=stream.read(MAX_FILE+1)
 need(len(raw)==info.st_size,'file_size_changed');return raw


def command(argv, *, data=None, env=None, timeout=60, cwd=None):
 result=subprocess.run(argv,input=data,capture_output=True,env=env,timeout=timeout,cwd=cwd)
 need(result.returncode==0,'admission_subprocess_failed');return result.stdout


def write_new(path, raw, *, mode=0o600, uid=0, gid=0):
 path=Path(path);need(not path.exists() and not path.is_symlink(),'new_file_required')
 descriptor=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL|getattr(os,'O_NOFOLLOW',0),mode)
 with os.fdopen(descriptor,'wb') as stream:stream.write(raw);stream.flush();os.fsync(stream.fileno())
 os.chmod(path,mode);os.chown(path,uid,gid)


def parse_env(raw):
 result={}
 for line in raw.decode().splitlines():
  if not line.strip() or line.lstrip().startswith('#'):continue
  key,sep,value=line.partition('=')
  need(sep and re.fullmatch(r'[A-Z][A-Z0-9_]*',key) and key not in result,'invalid_environment_format')
  result[key]=json.loads(value) if value.startswith('"') else value
 return result


def replace_env(raw, key, *, old_root=None, new_root=None):
 before=parse_env(raw);need(before.get(key)==','.join(OLD_IDS),'old_roster_changed')
 keys=[key]
 def replace_value(data,name,value):
  pattern=rb'(?m)^'+name.encode()+rb'=([^\r\n]*)'
  def replacement(match):
   original=match[1];rendered=json.dumps(value).encode() if original.startswith(b'"') else value.encode()
   return name.encode()+b'='+rendered
  changed,count=re.subn(pattern,replacement,data);need(count==1,'unique_env_key_required');return changed
 changed=replace_value(raw,key,','.join(IDS))
 if old_root and new_root and before.get('FISHING_ADDON_ROOT')==old_root+'/addon':
  changed=replace_value(changed,'FISHING_ADDON_ROOT',new_root+'/addon');keys.append('FISHING_ADDON_ROOT')
 after=parse_env(changed)
 need(set(before)==set(after) and all(before[name]==after[name] for name in before if name not in keys),'unrelated_environment_changed')
 need(after[key]==','.join(IDS),'new_roster_invalid')
 return changed


def patch_unit(raw, old_root, new_root, suffix):
 expected=old_root+('/'+suffix if suffix else '')
 working=re.findall(rb'(?m)^WorkingDirectory=([^\r\n]+)',raw)
 need(working==[expected.encode()],'unit_working_directory_changed')
 need(1<=raw.count(old_root.encode())<=4,'unit_root_anchor_changed')
 changed=raw.replace(old_root.encode(),new_root.encode())
 need(changed.replace(new_root.encode(),old_root.encode())==raw,'unit_unrelated_changes')
 return changed


def service(name):
 pid=command(['systemctl','show',name,'--property=MainPID','--value']).decode().strip()
 need(pid.isdigit() and int(pid)>0,'required_service_inactive')
 unit=Path(command(['systemctl','show',name,'--property=FragmentPath','--value']).decode().strip())
 return {'pid':int(pid),'unit_path':str(unit),'unit_sha256':sha(regular(unit)),
         'cwd':str(Path('/proc/'+pid+'/cwd').resolve(strict=True)),
         'working_directory':command(['systemctl','show',name,'--property=WorkingDirectory','--value']).decode().strip()}


def process_env(pid):
 rows=Path('/proc/'+str(pid)+'/environ').read_bytes().split(b'\0')
 return {key.decode():value.decode() for row in rows if b'=' in row for key,value in [row.split(b'=',1)]}


def inventory(root):
 root=Path(root);need(root.is_dir() and not root.is_symlink(),'source_root_invalid')
 files,links,total={},{},0
 for path in root.rglob('*'):
  relative=path.relative_to(root).as_posix()
  if '__pycache__' in path.parts:continue
  if path.is_symlink():
   need(relative=='.venv' and path.resolve()==Path('/opt/goufayu-ws4/.venv'),'unexpected_source_symlink')
   links[relative]=str(path.resolve());continue
  if path.is_dir():continue
  need(path.resolve().is_relative_to(root),'source_path_escape')
  raw=regular(path);total+=len(raw);need(len(files)<4000 and total<=128*1024*1024,'source_inventory_bound')
  files[relative]={'bytes':len(raw),'sha256':sha(raw)}
 return {'files':files,'links':links,'bytes':total}


def live_audit():
 result={'roles':{},'protected':{name:service(name) for name in PROTECTED},'pins_sha256':sha(regular(PINS)),'inventories':{}}
 for role,config in ROLES.items():
  observed=service(Path(config['unit']).name);old=Path(config['root'])
  expected=str(old/config['cwd_suffix']) if config['cwd_suffix'] else str(old)
  need(observed['cwd']==expected and observed['working_directory']==expected,'unexpected_live_source_root')
  raw=regular(config['env']);values=parse_env(raw)
  need(values.get(config['key'])==','.join(OLD_IDS),'existing_roster_changed')
  proc=process_env(observed['pid']);need(proc.get(config['key'])==','.join(OLD_IDS),'disk_process_roster_mismatch')
  if role=='web':
   need(values.get('PLAYER_WEB_AUTH_LOBBY_ENABLED','0')=='0','independent_lobby_must_stay_disabled')
   need(values.get('PLAYER_WEB_AUTH_DATABASE')==str(SQLITE),'auth_database_path_changed')
  result['roles'][role]={**observed,'root':str(old),'env_sha256':sha(raw)}
  result['inventories'][role]=inventory(old)
 return result


def validate_plan(plan):
 need(plan.get('schema')==1 and plan.get('approved_steamids64')==list(IDS) and plan.get('max_players')==4,'plan_roster_scope')
 need(re.fullmatch(r'[a-f0-9]{40}',plan.get('source_revision','')) is not None,'committed_source_required')
 name=plan.get('release','');need(re.fullmatch(r'20261101-admission-five-[a-f0-9]{12}',name) is not None,'release_name_invalid')
 stage=Path(plan.get('stage',''));need(stage.parent==Path('/root/goufayu_upload') and stage.name=='admission-five-'+name,'stage_scope_invalid')
 need(set(plan.get('overlay',{}))==set(SOURCE),'exact_three_source_overlay_required')
 return stage


def target(plan, role):
 validate_plan(plan);old=Path(ROLES[role]['root']);new=old.parent/plan['release']
 need(new.parent==old.parent and new!=old and not new.is_symlink(),'new_release_scope_invalid');return new


def receipt(stage,name,value):
 path=stage/(name+'.json');write_new(path,encoded(value));return {'path':str(path),'sha256':sha(regular(path))}


def verify_before(plan):
 actual=live_audit();need(actual==plan['live'],'live_baseline_changed');return actual


def sqlite_state(path=SQLITE):
 need(Path(path).is_file() and not Path(path).is_symlink(),'auth_database_missing')
 with sqlite3.connect('file:'+str(path)+'?mode=ro',uri=True) as conn:
  schema=list(conn.execute("SELECT type,name,tbl_name,sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY type,name"))
  tables={}
  for (name,) in conn.execute("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name"):
   need(re.fullmatch(r'[a-z_]+',name),'unexpected_sqlite_table')
   values=[json.dumps(list(row),sort_keys=True,separators=(',',':')) for row in conn.execute('SELECT * FROM "'+name+'"')]
   values.sort();tables[name]={'rows':len(values),'sha256':sha(('\n'.join(values)).encode())}
 return {'schema_sha256':sha(encoded(schema)),'tables':tables}


def sqlite_backup(stage,name):
 path=stage/name;need(not path.exists(),'new_auth_backup_required')
 with sqlite3.connect('file:'+str(SQLITE)+'?mode=ro',uri=True) as source:
  with sqlite3.connect(path) as destination:source.backup(destination)
 os.chmod(path,0o600)
 return {'path':str(path),'sha256':sha(regular(path)),'state':sqlite_state(path),'host_private_only':True}


def postgres_state():
 import psycopg
 from psycopg import sql
 with psycopg.connect(host='127.0.0.1',port=15432,dbname='goufayu_ws4',user='postgres',
     password=Path('/etc/goufayu-ws4/admin-password').read_text().strip()) as conn:
  conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY')
  need(conn.execute('SELECT current_database()').fetchone()[0]=='goufayu_ws4','database_scope_invalid')
  need(conn.execute('SELECT count(*) FROM public.archive_operations WHERE NOT done').fetchone()[0]==0,'pending_archive_operations')
  need(conn.execute("SELECT count(*) FROM payments.orders WHERE state IN ('created','pending','paid_review')").fetchone()[0]==0,'unresolved_payment_orders')
  tables={}
  for schema,name in conn.execute("SELECT schemaname,tablename FROM pg_tables WHERE schemaname IN ('public','payments') ORDER BY 1,2").fetchall():
   row=conn.execute(sql.SQL("SELECT count(*),md5(coalesce(string_agg(to_jsonb(t)::text,chr(10) ORDER BY to_jsonb(t)::text),'')) FROM {}.{} t").format(sql.Identifier(schema),sql.Identifier(name))).fetchone()
   tables[schema+'.'+name]=list(row)
  functions=list(conn.execute("SELECT p.oid::regprocedure::text,pg_get_functiondef(p.oid),coalesce(p.proacl::text,'') FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND NOT EXISTS(SELECT 1 FROM pg_depend d WHERE d.classid='pg_proc'::regclass AND d.objid=p.oid AND d.deptype='e') ORDER BY 1"))
 return {'tables':tables,'functions_sha256':sha(encoded(functions)),'read_only':True,'database':'goufayu_ws4'}


def prepare(plan, overlays):
 stage=validate_plan(plan);verify_before(plan)
 need(not stage.exists() and not stage.is_symlink(),'new_private_stage_required')
 need(set(overlays)==set(SOURCE),'overlay_source_scope')
 stage.mkdir(mode=0o700)
 write_new(stage/'plan.json',encoded(plan))
 for role,config in ROLES.items():
  old=Path(config['root']);new=target(plan,role);need(not new.exists(),'new_immutable_root_required')
  new.mkdir(mode=0o755);os.chown(new,old.stat().st_uid,old.stat().st_gid)
  expected=copy.deepcopy(plan['live']['inventories'][role]['files'])
  for name,pin in expected.items():
   raw=regular(old/name);need(len(raw)==pin['bytes'] and sha(raw)==pin['sha256'],'parent_source_changed')
   path=new/name;path.parent.mkdir(parents=True,exist_ok=True,mode=0o755)
   info=(old/name).stat();write_new(path,raw,mode=stat.S_IMODE(info.st_mode),uid=info.st_uid,gid=info.st_gid)
  for name,destination in plan['live']['inventories'][role]['links'].items():(new/name).symlink_to(destination,target_is_directory=True)
  for source,(owner,name) in SOURCE.items():
   if owner!=role:continue
   raw=base64.b64decode(overlays[source],validate=True);need(sha(raw)==plan['overlay'][source]['sha256'],'committed_overlay_changed')
   need(b'\r' not in raw,'committed_lf_sources_required');compile(raw,source,'exec')
   path=new/name;info=path.stat();path.write_bytes(raw);os.chmod(path,stat.S_IMODE(info.st_mode));os.chown(path,info.st_uid,info.st_gid)
   expected[name]={'bytes':len(raw),'sha256':sha(raw)}
  parent_manifest=json.loads(regular(old/'release_manifest.json')) if (old/'release_manifest.json').exists() else {}
  manifest={**parent_manifest,'release':plan['release'],'previous_release':old.name,'files':{name:pin['sha256'] for name,pin in expected.items() if name!='release_manifest.json'},
            'admission':{'source_revision':plan['source_revision'],'approved_accounts':5,'max_players':4,'payment_policy_changed':False}}
  manifest_raw=encoded(manifest);manifest_path=new/'release_manifest.json'
  if manifest_path.exists():manifest_path.write_bytes(manifest_raw)
  else:write_new(manifest_path,manifest_raw,mode=0o644)
  expected['release_manifest.json']={'bytes':len(manifest_raw),'sha256':sha(manifest_raw)}
  need(inventory(new)['files']==expected,'candidate_inventory_changed')
  for label,path in [('env',Path(config['env'])),('unit',Path(config['unit']))]:
   raw=regular(path);write_new(stage/(role+'.'+label+'.before'),raw)
  changed_env=replace_env(regular(config['env']),config['key'],old_root=str(old) if role=='api' else None,new_root=str(new) if role=='api' else None)
  changed_unit=patch_unit(regular(config['unit']),str(old),str(new),config['cwd_suffix'])
  write_new(stage/(role+'.env.after'),changed_env);write_new(stage/(role+'.unit.after'),changed_unit)
 backup=sqlite_backup(stage,'auth.prepare.sqlite3')
 verify_before(plan)
 result={'ok':True,'status':'PREPARED_FIVE_ACCOUNT_ADMISSION_NOT_ACTIVE','plan_sha256':sha(encoded(plan)),
         'roots':{role:str(target(plan,role)) for role in ROLES},'candidate_inventories':{role:inventory(target(plan,role)) for role in ROLES},
         'auth_backup':backup,'live_changed':False,'postgres_writes':0}
 reference=receipt(stage,'prepared',result);return {**result,'receipt':reference}


def owned_replace(path, before, after):
 path=Path(path);need(regular(path)==before,'concurrent_configuration_change')
 info=path.stat();temporary=path.with_name(path.name+'.admission-five-'+os.urandom(6).hex())
 write_new(temporary,after,mode=stat.S_IMODE(info.st_mode),uid=info.st_uid,gid=info.st_gid)
 need(regular(path)==before,'concurrent_configuration_change');os.replace(temporary,path)


def control(action, role):command(['systemctl',action,Path(ROLES[role]['unit']).name],timeout=90)


def wait_http(address, accepted):
 import urllib.request, urllib.error
 deadline=time.monotonic()+12
 while True:
  try:
   with urllib.request.urlopen(address,timeout=2) as response:
    need(response.status in accepted,'startup_status_invalid');return
  except urllib.error.HTTPError as error:
   if error.code in accepted:return
  except (urllib.error.URLError,OSError):pass
  need(time.monotonic()<deadline,'startup_readiness_timeout');time.sleep(.25)


def restore_owned(plan, stage):
 errors=[]
 for role in ('web','api'):
  try:control('stop',role)
  except Exception:errors.append('stop_'+role)
 for role,config in ROLES.items():
  for kind in ('env','unit'):
   try:
    old=regular(stage/(role+'.'+kind+'.before'));new=regular(stage/(role+'.'+kind+'.after'));path=Path(config[kind]);actual=regular(path)
    if actual==new:owned_replace(path,new,old)
    else:need(actual==old,'external_change_preserved')
   except Exception:errors.append('restore_'+role+'_'+kind)
 try:command(['systemctl','daemon-reload'])
 except Exception:errors.append('daemon_reload')
 for role in ('api','web'):
  try:control('start',role)
  except Exception:errors.append('start_'+role)
 try:
  wait_http('http://127.0.0.1:18765/health',{200,401,403})
  wait_http('http://127.0.0.1:18767/health',{200})
  processes={}
  for role,config in ROLES.items():
   current=service(Path(config['unit']).name)
   need(current['cwd']==plan['live']['roles'][role]['cwd'],'rollback_source_not_restored')
   need(process_env(current['pid']).get(config['key'])==','.join(OLD_IDS),'rollback_roster_not_restored')
   processes[role]=current
  health(processes)
  need({name:service(name) for name in PROTECTED}==plan['live']['protected'],'rollback_protected_service_changed')
 except Exception:errors.append('rollback_verification')
 return {'ok':not errors,'errors':errors,'database_restored':False,'backups_preserved':True}


def running(plan):
 result={}
 for role,config in ROLES.items():
  actual=service(Path(config['unit']).name);new=target(plan,role)
  expected=str(new/config['cwd_suffix']) if config['cwd_suffix'] else str(new)
  need(actual['cwd']==expected and actual['working_directory']==expected,'active_source_root_mismatch')
  need(actual['pid']!=plan['live']['roles'][role]['pid'],'fresh_service_pid_required')
  values=process_env(actual['pid']);need(values.get(config['key'])==','.join(IDS),'active_process_roster_mismatch')
  disk=parse_env(regular(config['env']));need(all(values.get(name)==value for name,value in disk.items()),'active_environment_mismatch')
  result[role]=actual
 need({name:service(name) for name in PROTECTED}==plan['live']['protected'],'protected_service_changed')
 need(sha(regular(PINS))==plan['live']['pins_sha256'],'upstream_pins_changed')
 return result


def evaluate_policy(plan, processes):
 reports={}
 for role in ROLES:
  actual=processes[role];env=process_env(actual['pid']);cwd=actual['cwd']
  if role=='api':
   interpreter=str(target(plan,role)/'.venv/bin/python')
   source="from archive_backend.test_access import TestAccountPolicy\nimport os,json\np=TestAccountPolicy.from_environment(os.environ)\nold="+repr([str(int(s)-76561197960265728) for s in IDS])+"\nassert p is not None and all(p.permits(s) for s in old) and not p.permits('336268888')\nprint(json.dumps({'approved_count':len(p.account_ids),'all_expected_permitted':True,'sixth_denied':True}))"
  else:
   interpreter='/usr/bin/python3.11'
   source="from player_web_auth.run import settings_from_environment\nimport os,json\ns=settings_from_environment(os.environ);s.validate()\nassert set(s.steam_ids)==set("+repr(IDS)+") and '336268888' not in s.accounts\nprint(json.dumps({'approved_count':len(s.accounts),'all_expected_permitted':True,'sixth_denied':True,'lobby_disabled':os.environ.get('PLAYER_WEB_AUTH_LOBBY_ENABLED','0')=='0'}))"
  reports[role]=json.loads(command([interpreter,'-B','-c',source],env=env,cwd=cwd))
 return reports


def health(processes):
 import urllib.request
 for path in ('http://127.0.0.1:18767/health','https://pay.xiaofengnet.com/ws4-web/health'):
  with urllib.request.urlopen(path,timeout=10) as response:
   need(response.status==200 and json.load(response).get('ok') is True,'web_health_failed')
 env=process_env(processes['web']['pid']);token=env['PLAYER_WEB_AUTH_UPSTREAM_BEARER']
 pins=json.loads(regular(PINS));need(pins.get('workshop_id')=='3824360109' and sha(token.encode()) in pins.get('sha256',[]),'existing_upstream_pin_required')
 request=urllib.request.Request('http://127.0.0.1:18765/v1/archive/config',data=b'{}',headers={'Authorization':'Bearer '+token,'Content-Type':'application/json'})
 with urllib.request.urlopen(request,timeout=10) as response:body=json.load(response);need(response.status==200 and body.get('config_hash')==BUNDLE,'bundle_health_failed')
 return {'web_loopback':True,'web_public':True,'archive_config_bundle':BUNDLE,'user_auth_minted':False,'payment_calls':0}


def activate(plan):
 stage=validate_plan(plan);need(sha(regular(stage/'plan.json'))==sha(encoded(plan)),'prepared_plan_changed')
 prepared=json.loads(regular(stage/'prepared.json'));need(prepared['status']=='PREPARED_FIVE_ACCOUNT_ADMISSION_NOT_ACTIVE','prepared_receipt_required')
 need(not (stage/'activated.json').exists() and not (stage/'activation_failed.json').exists(),'terminal_attempt_preserved_use_new_stage')
 verify_before(plan)
 for role in ROLES:need(inventory(target(plan,role))==prepared['candidate_inventories'][role],'candidate_source_drift')
 postgres_state() # Read-only pending preflight while both old services still run.
 touched=False
 try:
  touched=True;control('stop','web');control('stop','api')
  before_pg=postgres_state();before_sqlite=sqlite_state();backup=sqlite_backup(stage,'auth.activation.sqlite3')
  need(backup['state']==before_sqlite,'auth_backup_snapshot_changed')
  for role,config in ROLES.items():
   for kind in ('env','unit'):owned_replace(config[kind],regular(stage/(role+'.'+kind+'.before')),regular(stage/(role+'.'+kind+'.after')))
  command(['systemctl','daemon-reload']);control('start','api');wait_http('http://127.0.0.1:18765/health',{200,401,403})
  # No web proxy traffic during the PostgreSQL startup comparison.
  need(postgres_state()==before_pg,'postgres_data_or_schema_changed')
  control('start','web');wait_http('http://127.0.0.1:18767/health',{200})
  need(sqlite_state()==before_sqlite,'auth_data_or_schema_changed_no_database_restore')
  processes=running(plan);policies=evaluate_policy(plan,processes);checked=health(processes)
  need({name:service(name) for name in PROTECTED}==plan['live']['protected'],'protected_service_changed')
  result={'ok':True,'status':'PASS_FIVE_ACCOUNT_ADMISSION_ACTIVE','added_steamid64':ADDED,'approved_steamids64':list(IDS),'max_players':4,
    'web_policy_active':True,'archive_policy_active':True,'original_accounts_preserved':True,'payments_unchanged':True,'bundle_preserved':True,
    'no_real_player_auth_claimed':True,'database_restored':False,'postgres_writes_by_operator':0,'postgres_before':before_pg,
    'sqlite_before':before_sqlite,'private_auth_backup':backup,'processes':processes,'policy_evaluation':policies,'health':checked,
    'plan_sha256':sha(encoded(plan)),'source_revision':plan['source_revision'],'prepared_receipt':{'path':str(stage/'prepared.json'),'sha256':sha(regular(stage/'prepared.json'))}}
  reference=receipt(stage,'activated',result);return {**result,'receipt':reference}
 except Exception as error:
  rollback=restore_owned(plan,stage) if touched else {'ok':True,'database_restored':False}
  receipt(stage,'activation_failed',{'ok':False,'status':'FIVE_ACCOUNT_ACTIVATION_FAILED','error_type':type(error).__name__,'rollback':rollback,'database_restored':False})
  raise RuntimeError('five_account_activation_failed_rollback_'+('ok' if rollback['ok'] else 'incomplete')) from None


def verify(plan):
 stage=validate_plan(plan);active=json.loads(regular(stage/'activated.json'))
 need(active['status']=='PASS_FIVE_ACCOUNT_ADMISSION_ACTIVE','activation_receipt_required')
 prepared=json.loads(regular(stage/'prepared.json'))
 for role in ROLES:
  need(inventory(target(plan,role))==prepared['candidate_inventories'][role],'active_source_drift')
  for kind in ('env','unit'):need(regular(ROLES[role][kind])==regular(stage/(role+'.'+kind+'.after')),'active_launch_changed')
 processes=running(plan);policies=evaluate_policy(plan,processes);checked=health(processes)
 result={key:active[key] for key in ('status','added_steamid64','approved_steamids64','max_players','web_policy_active','archive_policy_active','original_accounts_preserved','payments_unchanged','bundle_preserved','no_real_player_auth_claimed')}
 result.update(ok=True,processes=processes,policy_evaluation=policies,health=checked,activation_receipt={'path':str(stage/'activated.json'),'sha256':sha(regular(stage/'activated.json'))},private_backups_preserved=True)
 reference=receipt(stage,'verified',result);return {**result,'receipt':reference}


def run(action, plan=None, overlays=None):
 if action=='audit':return {'ok':True,'status':'READ_ONLY_ADMISSION_BASELINE','live':live_audit(),'private_values_returned':False}
 import fcntl
 validate_plan(plan)
 with Path('/var/lock/goufayu_admission_five.lock').open('a') as lock:
  fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
  return {'prepare':lambda:prepare(plan,overlays),'activate':lambda:activate(plan),'verify':lambda:verify(plan)}[action]()


if 'OP_ACTION' in globals():
 try:print(json.dumps(run(OP_ACTION,globals().get('OP_PLAN'),globals().get('OP_OVERLAYS')),sort_keys=True))
 except Exception as error:
  print(json.dumps({'ok':False,'status':'ADMISSION_OPERATION_REFUSED','error_type':type(error).__name__,
                    'error':str(error) if isinstance(error,RuntimeError) and re.fullmatch('[a-z0-9_]+',str(error)) else 'operation_failed'}));raise SystemExit(1)
