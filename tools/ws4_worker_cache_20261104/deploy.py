"""Exact WS4 worker-cache rollout. Default plan performs no remote operation.

Only one reviewed settlement method and two backend helpers change. Existing
bundle, SQL, environment, payment/auth services and the parent release remain.
"""
from pathlib import Path
import argparse,base64,hashlib,importlib.util,json,re,subprocess
ROOT=Path(__file__).resolve().parents[2]
TOOL='tools/ws4_worker_cache_20261104/deploy.py'
TRANSPORT=ROOT/'tools/archive_release_20261029/server_deploy.py'
TRANSPORT_SHA='66413c174fb6fe27d5ae84dc267ceea07366c6f6a855a9406e5ffdaf388b1cc5'
OUT=ROOT/'output/ws4_worker_cache_20261104_v02'
RECIPE='normalized-parity-v2'
FILES=('service.py','settlement_runner.py','worker_fast.lua')
SOURCE='5a93e17c3b6e575fae701d2dc99827d273afe139'
SOURCE_PINS={
 'backend/archive_backend/service.py':'bca021af4fe5ae8a50036754f9fe2553724e638f21887fa48d96c1e700d62d5e',
 'backend/archive_backend/settlement_runner.py':'5bbe7508064573bdd25f6474e8c237a27bda01a53bb980a63d16912616503e38',
 'backend/archive_backend/worker_fast.lua':'4a85d79d97599f44bc5026bad154f0f2ffbe35b024151ca327a30625716d20b4',
}
PARENT_RELEASE='20261103-ws4-lottery-receipt-d2c7c2e85920'
PARENT_MANIFEST='75c7fd8fc1e95fc1a5a73e521e1d5f9cd411c271ba99028ccfef779b46e48a11'
PARENT_SERVICE='56e32e2e30e2e46257ae002652b6800bc6b5b864fa6097a8fbd079b4af8df03f'
SOURCE_METHOD='27757154a661835ac0d59e58151106b7dd1a4baad7cb603249b16a8642e7591e'
DERIVED_SERVICE='1e7a132537459c4436066555b1c58f9e7831d6d1e9b2c374f53f4b68c866c6e1'
sha=lambda raw:hashlib.sha256(raw).hexdigest()
REMOTE=r'''

from pathlib import Path,PurePosixPath
import ast,base64,contextlib,copy,fcntl,hashlib,hmac,json,os,re,shutil,subprocess,sys,time,urllib.request
sha=lambda raw:hashlib.sha256(raw).hexdigest()
base=Path('/opt/goufayu-ws4/releases')
old=base/'20261103-ws4-lottery-receipt-d2c7c2e85920'
unit=Path('/etc/systemd/system/goufayu-ws4.service')
expected_manifest='75c7fd8fc1e95fc1a5a73e521e1d5f9cd411c271ba99028ccfef779b46e48a11'
expected_service='56e32e2e30e2e46257ae002652b6800bc6b5b864fa6097a8fbd079b4af8df03f'
bundle_hash='d573588b64d2ea6d1431c856d52e0515b5ed471cfdf6af4456ff618d0f568488'
def need(ok,reason):
 if not ok:raise RuntimeError(reason)
def command(args):
 p=subprocess.run(args,capture_output=True,timeout=60);need(p.returncode==0,'ws4_control_command_failed');return p.stdout.decode().strip()
def state(name):
 rows=dict(line.split('=',1) for line in command(['systemctl','show',name,'--property=MainPID,WorkingDirectory']).splitlines() if '=' in line)
 return dict(pid=int(rows.get('MainPID','0')),cwd=rows.get('WorkingDirectory',''))
def active():
 s=state('goufayu-ws4.service');need(s['pid']>0,'ws4_not_running')
 cwd=Path(s['cwd']).resolve();need(cwd.name=='backend' and cwd.parent.parent==base,'ws4_service_scope_invalid')
 need(Path(os.readlink('/proc/%d/cwd'%s['pid'])).resolve()==cwd,'ws4_process_cwd_mismatch')
 return cwd.parent,s['pid']
def safe(root,name):
 p=PurePosixPath(name);need(not p.is_absolute() and '..' not in p.parts,'manifest_path_invalid')
 target=root/name;need(not target.is_symlink() and target.resolve().is_relative_to(root),'manifest_symlink_invalid');return target

need(old.is_dir() and not old.is_symlink() and sha((old/'release_manifest.json').read_bytes())==expected_manifest,'ws4_parent_manifest_changed')
manifest=json.loads((old/'release_manifest.json').read_bytes())
need(json.loads((old/'addon/server/bundles/current.json').read_bytes())['hash']==bundle_hash,'ws4_bundle_changed')
service='backend/archive_backend/service.py'
parent_raw=safe(old,service).read_bytes();need(sha(parent_raw)==expected_service,'ws4_parent_service_changed')
source_files={name:base64.b64decode(value,validate=True) for name,value in PAYLOADS.items()}
need(set(source_files)=={service,'backend/archive_backend/settlement_runner.py','backend/archive_backend/worker_fast.lua'},'exact_three_worker_cache_inputs_required')
need(SOURCE==EXPECTED_SOURCE and {name:sha(raw) for name,raw in source_files.items()}==SOURCE_PINS,'immutable_worker_cache_source_changed')
def fragments(raw):
 text=raw.decode('utf8');need('\r' not in text,'immutable_lf_service_required')
 tree=ast.parse(text)
 classes=[n for n in tree.body if isinstance(n,ast.ClassDef) and n.name=='ArchiveService']
 need(len(classes)==1,'service_class_anchor_invalid')
 methods=[n for n in classes[0].body if isinstance(n,ast.FunctionDef) and n.name=='settle']
 need(len(methods)==1,'settlement_method_anchor_invalid')
 method=methods[0];lines=text.splitlines(keepends=True)
 return ''.join(lines[:method.lineno-1]),''.join(lines[method.lineno-1:method.end_lineno]),''.join(lines[method.end_lineno:])
def derive_payloads(parent_raw,source_files):
 need(sha(parent_raw)==expected_service,'ws4_parent_service_changed')
 need({name:sha(raw) for name,raw in source_files.items()}==SOURCE_PINS,'immutable_worker_cache_source_changed')
 prefix,parent_method,suffix=fragments(parent_raw)
 _,source_method,_=fragments(source_files[service])
 need(sha(source_method.encode())==SOURCE_METHOD,'reviewed_settlement_method_changed')
 payloads=dict(source_files);payloads[service]=(prefix+source_method+suffix).encode('utf8')
 method_binding=dict(kind='EXACT_IMMUTABLE_METHOD_PATCH_PARENT_OUTSIDE_METHOD_UNCHANGED',
  parent_service_sha256=expected_service,parent_settle_sha256=sha(parent_method.encode()),
  source_service_sha256=sha(source_files[service]),source_settle_sha256=sha(source_method.encode()),
  output_service_sha256=sha(payloads[service]),outside_method_unchanged=True)
 for name,value in payloads.items():
  if name.endswith('.py'):compile(value,name,'exec')
 pins={name:sha(value) for name,value in payloads.items()}
 need(pins[service]==DERIVED_SERVICE,'reviewed_exact_method_patch_changed')
 return payloads,method_binding,pins

payloads,method_binding,pins=derive_payloads(parent_raw,source_files)
need(RECIPE=='normalized-parity-v2','reviewed_worker_cache_recipe_required')
new=base/('20261104-ws4-worker-cache-'+sha(json.dumps(dict(payload_sha256=pins,recipe=RECIPE),sort_keys=True).encode())[:12])
records=new/'worker_cache_operator'
retained_names=('goufayu-api.service','goufayu-payment.service','goufayu-db.service','goufayu-ws4-db.service','goufayu-ws4-web.service','goufayu-ws4-payment.service','nginx.service')
retained={name:state(name)['pid'] for name in retained_names}
def keep_services():need(all(state(n)['pid']==v for n,v in retained.items()),'unrelated_service_pid_changed')
def validate_files(root,entries):
 for name,digest in entries.items():need(sha(safe(root,name).read_bytes())==digest,'release_file_hash_changed')
def health():
 # Reuse WS4's established pinned internal read-only config probe. Never log
 # the token/environment or introduce a public authentication bypass.
 web_pid=state('goufayu-ws4-web.service')['pid']
 values=dict(row.split(b'=',1) for row in Path('/proc/%d/environ'%web_pid).read_bytes().split(b'\0') if b'=' in row)
 token=values[b'PLAYER_WEB_AUTH_UPSTREAM_BEARER'].decode('ascii')
 approved=json.loads(Path('/etc/goufayu-ws4/pins.json').read_bytes())
 need(approved.get('workshop_id')=='3824360109' and sha(token.encode()) in approved.get('sha256',[]),'existing_internal_upstream_pin_invalid')
 request=urllib.request.Request('http://127.0.0.1:18765/v1/archive/config',data=b'{}',headers={'Authorization':'Bearer '+token,'Content-Type':'application/json'})
 with urllib.request.urlopen(request,timeout=5) as response:value=json.load(response)
 need(value.get('ok') is True and value.get('config_hash')==bundle_hash,'ws4_published_config_unhealthy')
def restart():
 command(['systemctl','daemon-reload']);command(['systemctl','restart','goufayu-ws4.service'])
 for i in range(40):
  try:health();return
  except Exception:
   if i==39:raise
   time.sleep(.25)
def save(name,result):
 result['recipe']=RECIPE
 path=records/(name+'.json');need(not path.exists(),'preserve_remote_receipt')
 with path.open('x') as f:json.dump(result,f,sort_keys=True)
 path.chmod(0o600)
def replace_unit(expected,target):
 need(not unit.is_symlink() and sha(unit.read_bytes())==expected,'ws4_unit_changed')
 info=unit.stat();temp=unit.with_name(unit.name+'.worker-cache-'+str(os.getpid()))
 need(not temp.exists(),'unit_temporary_exists')
 with temp.open('xb') as f:f.write(target);f.flush();os.fsync(f.fileno())
 os.chmod(temp,info.st_mode&0o777);os.chown(temp,info.st_uid,info.st_gid);os.replace(temp,unit)
with contextlib.ExitStack() as stack:
 if MODE!='audit':
  for name in sorted(('/var/lock/goufayu_admission_five.lock','/var/lock/goufayu_ws4_worker_cache.lock')):
   lock=stack.enter_context(open(name,'a'));fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
 if MODE!='audit':validate_files(old,manifest['files'])
 current,pid=active();unit_raw=unit.read_bytes()
 if MODE=='audit':
  need(current==old,'ws4_parent_not_active')
  wd=re.findall(rb'(?m)^\s*WorkingDirectory=([^\r\n]+)',unit_raw)
  need(wd==[str(old/'backend').encode()],'ws4_unit_workdir_anchor_invalid')
  exec_lines=re.findall(rb'(?m)^\s*ExecStart=([^\r\n]+)',unit_raw)
  need(len(exec_lines)==1 and str(old).encode() not in exec_lines[0],'ws4_execstart_requires_separate_review')
  result=dict(ok=True,status='READ_ONLY_ACTUAL_WS4_WORKER_CACHE_AUDIT',parent=old.name,parent_manifest_sha256=expected_manifest,
   source_revision=SOURCE,source_sha256=SOURCE_PINS,recipe=RECIPE,parent_full_inventory_verified=False,
   unit_sha256=sha(unit_raw),api_pid=pid,payload_sha256=pins,new_release=new.name,method_binding=method_binding,retained_services=retained,database_writes=0,unit_or_env_changed=False)
 else:
  need(re.fullmatch('[a-f0-9]{64}',UNIT_SHA or '') is not None,'explicit_parent_unit_sha_required')
  if MODE=='prepare':
   need(current==old and sha(unit_raw)==UNIT_SHA and not new.exists(),'prepare_parent_drift_or_existing_candidate')
   health()
   original=dict(manifest['files'])
   for file in (old/'backend').rglob('*.py'):
    if '__pycache__' not in file.parts and not file.is_symlink():original[file.relative_to(old).as_posix()]=sha(file.read_bytes())
   new.mkdir(mode=0o755)
   for name,digest in original.items():
    src=safe(old,name);need(sha(src.read_bytes())==digest,'parent_copy_changed')
    dest=safe(new,name);dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(src,dest);dest.chmod(src.stat().st_mode&0o777)
   need((old/'.venv').exists(),'parent_venv_missing');(new/'.venv').symlink_to(old/'.venv',target_is_directory=True)
   for name,value in payloads.items():
    dest=safe(new,name);dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(value);dest.chmod(0o644)
   prepared={**manifest,'release':new.name,'files':{**original,**pins},'worker_cache_parent_manifest_sha256':expected_manifest,
    'worker_cache_source_revision':SOURCE,'worker_cache_operator_revision':OPERATOR,'worker_cache_changed_files':sorted(pins),'worker_cache_recipe':RECIPE,
    'worker_cache_source_sha256':SOURCE_PINS,
    'worker_cache_parent_unit_sha256':UNIT_SHA,'database_changed':False,'addon_root_and_env_unchanged':True,'worker_cache_method_binding':method_binding}
   (new/'release_manifest.json').write_text(json.dumps(prepared,sort_keys=True,separators=(',',':')))
   records.mkdir(mode=0o700);(records/'unit.original').write_bytes(unit_raw);(records/'unit.original').chmod(0o600)
   result=dict(ok=True,status='WS4_WORKER_CACHE_PREPARED_NOT_ACTIVE',release=new.name,payload_sha256=pins,database_writes=0)
  else:
   need(new.is_dir() and not new.is_symlink(),'prepared_ws4_release_missing')
   prepared=json.loads((new/'release_manifest.json').read_bytes())
   need(prepared['worker_cache_source_revision']==SOURCE and prepared['worker_cache_operator_revision']==OPERATOR and prepared['worker_cache_recipe']==RECIPE
    and prepared['worker_cache_parent_unit_sha256']==UNIT_SHA and prepared['worker_cache_changed_files']==sorted(pins)
    and prepared['worker_cache_source_sha256']==SOURCE_PINS and prepared['worker_cache_method_binding']==method_binding,'prepared_source_binding_changed')
   validate_files(new,prepared['files']);need(all(prepared['files'][k]==v for k,v in pins.items()),'payload_pins_changed')
   original_unit=(records/'unit.original').read_bytes();need(sha(original_unit)==UNIT_SHA,'original_unit_backup_changed')
   target_unit,count=re.subn(rb'(?m)^(\s*WorkingDirectory=)[^\r\n]+',lambda m:m[1]+str(new/'backend').encode(),original_unit)
   need(count==1,'unit_workdir_anchor_changed')
   if MODE=='probe':
    need(current==old and sha(unit_raw)==UNIT_SHA,'probe_parent_drift')
    sys.path.insert(0,str(new/'backend'))
    from archive_backend.bundle import Bundle
    import archive_backend.service as service_module
    from archive_backend.settlement_runner import cache_info,clear_cache
    from types import SimpleNamespace
    bundle=Bundle(old/'addon/server/bundles'/bundle_hash)
    calls=[]
    def forbidden(*args,**kwargs):calls.append(True);raise RuntimeError('probe_forbidden_rpc')
    frozen=1770000000;service_module.time=SimpleNamespace(time=lambda:frozen)
    pepper='synthetic-readonly-worker-cache-probe'
    app=SimpleNamespace(account_id_pepper=pepper,rpc_client=SimpleNamespace(rpc=forbidden))
    instance=service_module.ArchiveService(app,bundle,'/usr/bin/lua')
    profile=dict(schema_version=1,account_id='100',revision=1,entitlements={},achievements={},public={},save=dict(archive={},gameplay_stats={r['field_id']:r['default_value'] for r in bundle.configs['player_gameplay_stats']['rows']},content_inventory={'lottery_ticket':1000,'special_lottery_ticket':1000}))
    def baseline(profile,command):
     seed=int.from_bytes(hmac.new(pepper.encode(),(profile['account_id']+':'+command['id']).encode(),hashlib.sha256).digest()[:4],'big')%2147483646+1
     q=dict(configs=bundle.configs,profile=profile,command=command,has_pass=False,seed=seed,server_time=frozen)
     completed=subprocess.run(['/usr/bin/lua','worker.lua'],cwd=bundle.directory,input=json.dumps(q,ensure_ascii=False,allow_nan=False).encode(),stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=10,check=True)
     # ArchiveService.settle has always normalized Lua empty tables to maps.
     # Compare both sides at that same public return boundary.
     return service_module.object_maps(json.loads(completed.stdout))
    today=(frozen+10800)//86400
    initial=baseline(profile,dict(id='synthetic_init',kind='daily_init',today=today))
    eligible=copy.deepcopy(profile);eligible['save']['archive']=initial['archive'];eligible['save']['gameplay_stats']=initial['gameplay_stats']
    cases=[('snapshot',profile,dict(id='synthetic_snapshot',kind='lottery_snapshot')),
     ('claim',eligible,dict(id='synthetic_claim',kind='daily_claim',today=today,target_day=today)),
     ('draw',profile,dict(id='synthetic_draw',kind='lottery_draw',pool_id='map',count=10))]
    timings=[]
    try:
     for name,source,command_value in cases:
      before=copy.deepcopy(source);start=time.perf_counter();expected=baseline(source,command_value);old_ms=(time.perf_counter()-start)*1000
      start=time.perf_counter();actual=instance.settle(source,command_value,False);fast_ms=(time.perf_counter()-start)*1000
      need(actual==expected and actual.get('ok') is True,'actual_fresh_vm_parity_failed_'+name)
      need(source==before and not calls,'probe_modified_source_or_called_rpc')
      timings.append(dict(kind=name,old_ms=old_ms,fast_ms=fast_ms,equal=True,ok=True))
     info=cache_info()
    finally:clear_cache()
    result=dict(ok=True,status='ACTUAL_WS4_PREPARED_WORKER_PARITY_PASS',cases=timings,cache=info,
     rpc_calls=0,real_player_data_used=False,database_writes=0,source_files_unchanged=True)
   elif MODE=='activate':
    need(current==old and sha(unit_raw)==UNIT_SHA,'activation_parent_drift')
    probe=json.loads((records/'probe.json').read_bytes());need(probe.get('status')=='ACTUAL_WS4_PREPARED_WORKER_PARITY_PASS','real_lua_probe_required')
    import psycopg
    with psycopg.connect(host='127.0.0.1',port=15432,dbname='goufayu_ws4',user='postgres',password=Path('/etc/goufayu-ws4/admin-password').read_text().strip()) as conn:
     conn.execute('SET TRANSACTION READ ONLY');conn.execute("SET LOCAL statement_timeout='10s'")
     need(conn.info.dbname=='goufayu_ws4' and conn.info.port==15432,'wrong_database_rejected')
     need(conn.execute('SELECT count(*) FROM public.archive_operations WHERE NOT done').fetchone()[0]==0,'pending_ws4_operations');conn.rollback()
    replace_unit(UNIT_SHA,target_unit)
    try:
     restart();need(active()[0]==new,'new_ws4_process_cwd_mismatch')
    except Exception:
     replace_unit(sha(target_unit),original_unit);restart();raise
    result=dict(ok=True,status='ACTUAL_WS4_WORKER_CACHE_ACTIVE',release=new.name,api_pid=active()[1],unit_sha256=sha(unit.read_bytes()),database_writes=0,env_unchanged=True,original_release_preserved=True)
   elif MODE=='verify':
    need(current==new and sha(unit_raw)==sha(target_unit),'active_ws4_lineage_changed');health()
    result=dict(ok=True,status='ACTUAL_WS4_WORKER_CACHE_ACTIVE_VERIFIED',release=new.name,manifest_sha256=sha((new/'release_manifest.json').read_bytes()),payload_sha256=pins,api_pid=pid,database_writes=0,env_unchanged=True,original_release_preserved=True)
   elif MODE=='rollback':
    need(current==new,'only_own_active_release_can_rollback');replace_unit(sha(target_unit),original_unit);restart();need(active()[0]==old,'rollback_cwd_failed')
    result=dict(ok=True,status='OWN_WS4_WORKER_CACHE_ROLLED_BACK',restored=old.name,prepared_preserved=True,database_writes=0)
   else:raise RuntimeError('invalid_ws4_mode')
  keep_services();result['retained_services_unchanged']=True;save(MODE,result)
 print(json.dumps(result))

'''

def git_blob(revision,name):
 if not re.fullmatch('[a-f0-9]{40}',revision or ''):raise RuntimeError('immutable_git_revision_required')
 return subprocess.check_output(['git','--no-replace-objects','-c','safe.directory='+ROOT.as_posix(),'-C',str(ROOT),'show',revision+':'+name])

def source_payloads(revision):
 if revision!=SOURCE:raise RuntimeError('reviewed_s10_source_revision_required')
 values={('backend/archive_backend/'+name):git_blob(revision,'server/archive_backend/'+name) for name in FILES}
 if {name:sha(raw) for name,raw in values.items()}!=SOURCE_PINS:raise RuntimeError('immutable_worker_cache_source_changed')
 return {name:base64.b64encode(raw).decode('ascii') for name,raw in values.items()}

def plan():
 pins={**SOURCE_PINS,'backend/archive_backend/service.py':DERIVED_SERVICE}
 return dict(status='STATIC_ACTUAL_WS4_WORKER_CACHE_PLAN',service='goufayu-ws4.service',recipe=RECIPE,
  source_revision=SOURCE,source_sha256=SOURCE_PINS,parent_release=PARENT_RELEASE,
  parent_manifest_sha256=PARENT_MANIFEST,parent_service_sha256=PARENT_SERVICE,
  source_settle_sha256=SOURCE_METHOD,derived_payload_sha256=pins,
  candidate='20261104-ws4-worker-cache-'+sha(json.dumps(dict(payload_sha256=pins,recipe=RECIPE),sort_keys=True).encode())[:12],
  files=3,method_only_service_patch=True,parent_bytes_outside_settle_preserved=True,
  remote_actions=0,database_writes=0,
  modes=dict(audit='Read-only service/release/unit identity; no tokens, player data, SQL, health HTTP, or writes.',
   prepare='Clone exact pinned parent into a fresh candidate; write three derived payloads and evidence; keep parent active.',
   probe='Run frozen synthetic snapshot, valid daily claim and ten-draw through original/new workers; no real account/RPC/SQL.',
   activate='Require recorded parity probe and zero unfinished operations; change only WS4 WorkingDirectory and restart WS4 API.',
   verify='Verify active candidate files, identity and existing authenticated read-only health; preserve unrelated service PIDs.',
   rollback='Restore only this operator\'s active unit to its exact preserved parent; retain candidate/evidence.'))

def main(argv=None):
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument('mode',nargs='?',default='plan',choices=('plan','audit','prepare','probe','activate','verify','rollback'))
 parser.add_argument('--source-revision',default=SOURCE);parser.add_argument('--operator-revision');parser.add_argument('--unit-sha256')
 args=parser.parse_args(argv)
 if args.mode=='plan':
  print(json.dumps(plan(),sort_keys=True));return 0
 report=OUT/(args.mode+'.json')
 if report.exists():raise RuntimeError('preserve_existing_local_receipt')
 payloads=source_payloads(args.source_revision)
 if args.mode!='audit':
  own=git_blob(args.operator_revision,TOOL)
  if own!=Path(__file__).read_bytes().replace(b'\r\n',b'\n'):raise RuntimeError('operator_worktree_drift')
  if not re.fullmatch('[a-f0-9]{64}',args.unit_sha256 or ''):raise RuntimeError('parent_unit_sha256_required')
 if sha(TRANSPORT.read_bytes())!=TRANSPORT_SHA:raise RuntimeError('pinned_transport_changed')
 spec=importlib.util.spec_from_file_location('ws4_worker_cache_transport',TRANSPORT);transport=importlib.util.module_from_spec(spec);spec.loader.exec_module(transport)
 context=dict(MODE=args.mode,SOURCE=args.source_revision,EXPECTED_SOURCE=SOURCE,SOURCE_PINS=SOURCE_PINS,RECIPE=RECIPE,
  SOURCE_METHOD=SOURCE_METHOD,DERIVED_SERVICE=DERIVED_SERVICE,
  OPERATOR=args.operator_revision,UNIT_SHA=args.unit_sha256,PAYLOADS=payloads)
 remote='\n'.join(k+'='+repr(v) for k,v in context.items())+'\n'+REMOTE
 result=transport.remote(remote,timeout=240)
 OUT.mkdir(parents=True,exist_ok=True)
 with report.open('x',encoding='utf8') as stream:json.dump(result,stream,sort_keys=True,indent=2);stream.write('\n')
 print(json.dumps(result));return 0

if __name__=='__main__':raise SystemExit(main())
