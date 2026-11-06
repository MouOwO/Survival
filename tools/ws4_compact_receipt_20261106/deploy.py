"""DRAFT WS4 compact receipt rollout. Default plan performs no remote action.

Three exact backend files only; no bundle, SQL, environment, auth or payment
changes. Source/operator and derived pins must be frozen before any remote mode.
"""
from pathlib import Path
import argparse,base64,hashlib,importlib.util,json,re,subprocess
ROOT=Path(__file__).resolve().parents[2]
TOOL='tools/ws4_compact_receipt_20261106/deploy.py'
TRANSPORT=ROOT/'tools/archive_release_20261029/server_deploy.py'
TRANSPORT_SHA='66413c174fb6fe27d5ae84dc267ceea07366c6f6a855a9406e5ffdaf388b1cc5'
OUT=ROOT/'output/ws4_compact_receipt_20261106_v01'
RECIPE='compact-receipt-v1'
FILES=('service.py','lottery_receipt_snapshot.py','command_timing.py')
SOURCE='UNFROZEN_SOURCE_COMMIT'
SOURCE_PINS={'backend/archive_backend/service.py': 'c24442218cbc7cdbe32c163272f3923fe383ad1357582fdc9396a93e2ece9eb7', 'backend/archive_backend/lottery_receipt_snapshot.py': '9f2ae886f7b25faa85b41b49653220f4a0baa1656c78472baf9a959a7fb2eabc', 'backend/archive_backend/command_timing.py': 'cde11e5fcc995bed05a331842f547b3e7bfa718198a219d9a7854431f202274d'}
PARENT_RELEASE='20261104-ws4-worker-cache-3f53908aaea0'
PARENT_MANIFEST='39851557ce5d9c268c2deaa48b4be4697d8e3c04b10a52262566f371882481c2'
PARENT_SERVICE='1e7a132537459c4436066555b1c58f9e7831d6d1e9b2c374f53f4b68c866c6e1'
DERIVED_SERVICE='ec0748b94f3e7581b9271dc23c8ab0eb0f46a0901d796c6fcbca2b434b08c4b3'
sha=lambda raw:hashlib.sha256(raw).hexdigest()
REMOTE=r'''

from pathlib import Path,PurePosixPath
import ast,base64,contextlib,copy,fcntl,hashlib,hmac,json,os,re,shutil,subprocess,sys,time,urllib.request
sha=lambda raw:hashlib.sha256(raw).hexdigest()
base=Path('/opt/goufayu-ws4/releases')
old=base/'20261104-ws4-worker-cache-3f53908aaea0'
unit=Path('/etc/systemd/system/goufayu-ws4.service')
expected_manifest='39851557ce5d9c268c2deaa48b4be4697d8e3c04b10a52262566f371882481c2'
expected_service='1e7a132537459c4436066555b1c58f9e7831d6d1e9b2c374f53f4b68c866c6e1'
bundle_hash='d573588b64d2ea6d1431c856d52e0515b5ed471cfdf6af4456ff618d0f568488'
def need(ok,reason):
 if not ok:raise RuntimeError(reason)
def command(args):
 p=subprocess.run(args,capture_output=True,timeout=60);need(p.returncode==0,'ws4_control_command_failed');return p.stdout.decode().strip()
def state(name):
 rows=dict(line.split('=',1) for line in command(['systemctl','show',name,'--property=MainPID,WorkingDirectory,ActiveState,SubState']).splitlines() if '=' in line)
 return dict(pid=int(rows.get('MainPID','0')),cwd=rows.get('WorkingDirectory',''),active_state=rows.get('ActiveState',''),sub_state=rows.get('SubState',''))

def observed():
 s=state('goufayu-ws4.service')
 cwd=Path(s['cwd']).resolve();need(cwd.name=='backend' and cwd.parent.parent==base,'ws4_service_scope_invalid')
 if s['pid']>0:need(Path(os.readlink('/proc/%d/cwd'%s['pid'])).resolve()==cwd,'ws4_process_cwd_mismatch')
 return cwd.parent,s
def active():
 release,s=observed();need(s['pid']>0,'ws4_not_running')
 return release,s['pid']
def safe(root,name):
 p=PurePosixPath(name);need(not p.is_absolute() and '..' not in p.parts,'manifest_path_invalid')
 target=root/name;need(not target.is_symlink() and target.resolve().is_relative_to(root),'manifest_symlink_invalid');return target

need(old.is_dir() and not old.is_symlink() and sha((old/'release_manifest.json').read_bytes())==expected_manifest,'ws4_parent_manifest_changed')
manifest=json.loads((old/'release_manifest.json').read_bytes())
need(json.loads((old/'addon/server/bundles/current.json').read_bytes())['hash']==bundle_hash,'ws4_bundle_changed')
service='backend/archive_backend/service.py'
parent_raw=safe(old,service).read_bytes();need(sha(parent_raw)==expected_service,'ws4_parent_service_changed')
source_files={name:base64.b64decode(value,validate=True) for name,value in PAYLOADS.items()}
need(set(source_files)=={service,'backend/archive_backend/lottery_receipt_snapshot.py','backend/archive_backend/command_timing.py'},'exact_three_compact_receipt_inputs_required')
need(SOURCE==EXPECTED_SOURCE and {name:sha(raw) for name,raw in source_files.items()}==SOURCE_PINS,'immutable_compact_receipt_source_changed')
def methods(raw):
 text=raw.decode('utf8');need('\r' not in text,'immutable_lf_service_required')
 tree=ast.parse(text);lines=text.splitlines(keepends=True)
 classes=[n for n in tree.body if isinstance(n,ast.ClassDef) and n.name=='ArchiveService']
 need(len(classes)==1,'service_class_anchor_invalid')
 nodes={n.name:n for n in classes[0].body if isinstance(n,ast.FunctionDef)}
 return text,lines,nodes

def derive_payloads(parent_raw,source_files):
 need(sha(parent_raw)==expected_service,'ws4_parent_service_changed')
 need({name:sha(raw) for name,raw in source_files.items()}==SOURCE_PINS,'immutable_compact_source_changed')
 parent_text,parent_lines,parent_nodes=methods(parent_raw)
 source_text,source_lines,source_nodes=methods(source_files[service])
 def fragment(lines,node):return ''.join(lines[node.lineno-1:node.end_lineno])
 def replace(value,old,new):
  need(value.count(old)==1,'reviewed_parent_method_anchor_changed')
  need(desired.count(new)==1,'inserted_fragment_not_bound_to_immutable_source')
  return value.replace(old,new)
 selected={};replacements=[]
 for name in ('settle','command','finish_prepared'):
  need(name in parent_nodes,'parent_method_missing')
  before=fragment(parent_lines,parent_nodes[name]);after=before
  desired=fragment(source_lines,source_nodes['_command' if name=='command' else name])
  if name=='settle':
   after=replace(after,'    def settle(self,profile,command,has_pass,shared_challenge_roll=None):\n','    def settle(self,profile,command,has_pass,shared_challenge_roll=None):\n        from .command_timing import measure\n')
   after=replace(after,'        if not self.slots.acquire(timeout=2): raise TimeoutError("archive_workers_busy")',"        with measure('worker_wait'):\n            if not self.slots.acquire(timeout=2): raise TimeoutError(\"archive_workers_busy\")")
   after=replace(after,'            completed=run(self.bundle,self.lua,payload)',"            with measure('worker'):\n                completed=run(self.bundle,self.lua,payload)")
   after=replace(after,'        result=object_maps(json.loads(completed.stdout))',"        with measure('worker_decode'):\n            result=object_maps(json.loads(completed.stdout))")
   expected=fragment(source_lines,source_nodes[name])
  elif name=='command':
   after=replace(after,'    def command(self,payload):\n','    def _command(self,payload):\n        from .command_timing import measure\n')
   after=replace(after,'        self.app._ensure_gameplay_stats(database_id)',"        with measure('ensure'):\n            self.app._ensure_gameplay_stats(database_id)")
   after=replace(after,'        prepared=self.app.rpc_client.rpc("archive_prepare",{"p_account":database_id,"p_id":command["id"],\n            "p_hash":requested_hash,"p_fingerprint":fingerprint,"p_command":command})\n        result=self.finish_prepared(database_id,command["id"],prepared)\n        reply=self.app._public_response(result,database_id,account)', '        with measure(\'prepare\'):\n            prepared=self.app.rpc_client.rpc("archive_prepare",{"p_account":database_id,"p_id":command["id"],\n                "p_hash":requested_hash,"p_fingerprint":fingerprint,"p_command":command})\n        with measure(\'finish\'):\n            result=self.finish_prepared(database_id,command["id"],prepared)\n        with measure(\'public\'):\n            reply=self.app._public_response(result,database_id,account)')
   after=replace(after,'        return attach(self,reply,command,requested_hash)',"        with measure('snapshot'):\n            return attach(self,reply,command,requested_hash,payload.get('response_capabilities'))")
   after=fragment(source_lines,source_nodes['command'])+'\n'+after
   expected=fragment(source_lines,source_nodes['command'])+'\n'+fragment(source_lines,source_nodes['_command'])
  else:
   after=replace(after,'    def finish_prepared(self,account,operation_id,prepared,clear_mode=None):\n','    def finish_prepared(self,account,operation_id,prepared,clear_mode=None):\n        from .command_timing import measure\n')
   after=replace(after,'            committed=self.app.rpc_client.rpc(rpc,commit_payload)',"            with measure('commit'):\n                committed=self.app.rpc_client.rpc(rpc,commit_payload)")
   after=replace(after,'            prepared=self.app.rpc_client.rpc("archive_resume",{"p_account":account,"p_id":operation_id})',"            with measure('resume'):\n                prepared=self.app.rpc_client.rpc(\"archive_resume\",{\"p_account\":account,\"p_id\":operation_id})")
   expected=fragment(source_lines,source_nodes[name])
  selected[name]={'parent_sha256':sha(before.encode()),'derived_sha256':sha(after.encode()),
   'source_sha256':sha(expected.encode()),'complete_method_equals_source':after==expected,
   'only_reviewed_source_bound_insertions':True}
  node=parent_nodes[name];replacements.append((node.lineno-1,node.end_lineno,after))
 result_lines=list(parent_lines)
 for start,end,after in sorted(replacements,reverse=True):result_lines[start:end]=[after]
 payloads=dict(source_files);payloads[service]=''.join(result_lines).encode()
 for name,value in payloads.items():compile(value,name,'exec')
 pins={name:sha(value) for name,value in payloads.items()}
 need(pins[service]==DERIVED_SERVICE,'reviewed_derived_service_changed')
 binding=dict(kind='EXACT_PARENT_TRANSFORM_WITH_IMMUTABLE_SOURCE_BOUND_INSERTIONS',
  parent_service_sha256=expected_service,source_service_sha256=sha(source_files[service]),
  output_service_sha256=pins[service],methods=selected,outside_methods_unchanged=True,
  retained_parent_only=['onboarding command route'],
  source_context_not_deployed=['public_beta_gift command scope and pending/reward validation'])
 return payloads,binding,pins
payloads,method_binding,pins=derive_payloads(parent_raw,source_files)
need(RECIPE=='compact-receipt-v1','reviewed_compact_receipt_recipe_required')
new=base/('20261106-ws4-compact-receipt-'+sha(json.dumps(dict(payload_sha256=pins,recipe=RECIPE),sort_keys=True).encode())[:12])
control_root=base.parent/'deployment_records'
records=control_root/new.name
retained_names=('goufayu-api.service','goufayu-payment.service','goufayu-db.service','goufayu-ws4-db.service','goufayu-ws4-web.service','goufayu-ws4-payment.service','nginx.service')
retained={name:state(name)['pid'] for name in retained_names}
def keep_services():need(all(state(n)['pid']==v for n,v in retained.items()),'unrelated_service_pid_changed')
def validate_files(root,entries):
 for name,digest in entries.items():need(sha(safe(root,name).read_bytes())==digest,'release_file_hash_changed')
def parent_inventory():
 entries=dict(manifest['files'])
 validate_files(old,entries)
 for file in (old/'backend').rglob('*.py'):
  if '__pycache__' not in file.parts:
   need(not file.is_symlink(),'parent_python_symlink_rejected')
   entries[file.relative_to(old).as_posix()]=sha(safe(old,file.relative_to(old).as_posix()).read_bytes())
 return entries
def canonical(value):return json.dumps(value,sort_keys=True,separators=(',',':')).encode('utf8')
def validate_parent_inventory(original):
 need(re.fullmatch('[a-f0-9]{64}',PARENT_INVENTORY_SHA or '') is not None and sha(canonical(original))==PARENT_INVENTORY_SHA,'audited_parent_inventory_changed')
def candidate_manifest(original):
 return {**manifest,'release':new.name,'files':{**original,**pins},'compact_receipt_parent_manifest_sha256':expected_manifest_digest,
  'compact_receipt_source_revision':SOURCE,'compact_receipt_operator_revision':OPERATOR,'compact_receipt_changed_files':sorted(pins),'compact_receipt_recipe':RECIPE,
  'compact_receipt_source_sha256':SOURCE_PINS,'compact_receipt_parent_inventory_sha256':sha(canonical(original)),
  'compact_receipt_parent_unit_sha256':UNIT_SHA,'database_changed':False,'addon_root_and_env_unchanged':True,'compact_receipt_method_binding':method_binding}
def control_binding(original):
 return dict(kind='EXACT_WS4_COMPACT_RECEIPT_BINDING',parent=old.name,candidate=new.name,
  source_revision=SOURCE,operator_revision=OPERATOR,source_sha256=SOURCE_PINS,payload_sha256=pins,
  parent_manifest_sha256=expected_manifest_digest,parent_inventory_sha256=sha(canonical(original)),
  parent_unit_sha256=UNIT_SHA,prepared_manifest_sha256=sha(canonical(candidate_manifest(original))),recipe=RECIPE)
def unit_pair():
 need(control_root.is_dir() and not control_root.is_symlink() and records.is_dir() and not records.is_symlink(),'independent_control_directory_missing')
 original_unit=safe(records,'unit.original').read_bytes();need(sha(original_unit)==UNIT_SHA,'original_unit_backup_changed')
 working=re.findall(rb'(?m)^\s*WorkingDirectory=([^\r\n]+)',original_unit)
 need(working==[str(old/'backend').encode()],'original_unit_lineage_changed')
 target_unit,count=re.subn(rb'(?m)^(\s*WorkingDirectory=)[^\r\n]+',lambda m:m[1]+str(new/'backend').encode(),original_unit)
 need(count==1,'unit_workdir_anchor_changed')
 return original_unit,target_unit
def validate_controls(original):
 binding=control_binding(original)
 need(json.loads(safe(records,'prepared_binding.json').read_bytes())==binding,'independent_control_binding_changed')
 return binding,unit_pair()
def validate_candidate(original):
 need(new.is_dir() and not new.is_symlink(),'prepared_ws4_release_missing')
 need((new/'.venv').is_symlink() and (new/'.venv').resolve()==(old/'.venv').resolve(),'candidate_venv_lineage_changed')
 prepared=candidate_manifest(original);expected=canonical(prepared)
 need(safe(new,'release_manifest.json').read_bytes()==expected,'exact_candidate_manifest_changed')
 validate_files(new,prepared['files'])
 actual=set()
 for directory,dirs,files in os.walk(new,followlinks=False):
  root=Path(directory)
  for name in list(dirs):
   path=root/name
   if path==new/'.venv':
    need(path.is_symlink() and path.resolve()==(old/'.venv').resolve(),'candidate_venv_lineage_changed');dirs.remove(name)
   else:need(not path.is_symlink(),'candidate_directory_symlink_rejected')
  for name in files:
   path=root/name;relative=path.relative_to(new).as_posix()
   if relative!='release_manifest.json':
    need(not path.is_symlink(),'candidate_file_symlink_rejected');actual.add(relative)
 need(actual==set(prepared['files']),'candidate_runtime_file_set_changed')
 return prepared
def validate_probe(original):
 value=json.loads(safe(records,'probe.json').read_bytes())
 need(value.get('ok') is True and value.get('status')=='ACTUAL_WS4_PREPARED_COMPACT_RECEIPT_PARITY_PASS','exact_candidate_probe_required')
 need(value.get('binding')==control_binding(original),'probe_binding_changed')
 need(value.get('rpc_calls')==0 and value.get('database_writes')==0 and value.get('real_player_data_used') is False,'probe_isolation_changed')
 samples=value.get('samples');need(isinstance(samples,list) and len(samples)==3,'probe_samples_missing')
 for sample in samples:
  need(sample.get('equal') is True,'probe_parity_failed')
  for variant in ('parent','legacy','compact'):
   need(sample.get(variant,{}).get('real_rpc_calls')==0,'probe_real_rpc_rejected')
 return value
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
def start_parent():
 command(['systemctl','daemon-reload']);command(['systemctl','start','goufayu-ws4.service'])
 for i in range(40):
  try:health();return
  except Exception:
   if i==39:raise
   time.sleep(.25)
def save(name,result):
 result['recipe']=RECIPE
 path=records/(name+'.json');need(not path.exists(),'preserve_remote_receipt')
 with path.open('x') as f:json.dump(result,f,sort_keys=True);f.flush();os.fsync(f.fileno())
 path.chmod(0o600)
def replace_unit(expected,target):
 need(not unit.is_symlink() and sha(unit.read_bytes())==expected,'ws4_unit_changed')
 info=unit.stat();temp=unit.with_name(unit.name+'.compact-receipt-'+str(os.getpid()))
 need(not temp.exists(),'unit_temporary_exists')
 with temp.open('xb') as f:f.write(target);f.flush();os.fsync(f.fileno())
 os.chmod(temp,info.st_mode&0o777);os.chown(temp,info.st_uid,info.st_gid);os.replace(temp,unit)
def rollback_parent(original,current,service_state,unit_raw):
 binding,(original_unit,target_unit)=validate_controls(original)
 need(sha(unit_raw) in (UNIT_SHA,sha(target_unit)),'rollback_unrelated_unit_rejected')
 need((sha(unit_raw)==UNIT_SHA and current==old) or (sha(unit_raw)==sha(target_unit) and current==new),'rollback_unit_lineage_mismatch')
 if service_state['pid']>0:
  # A later live rollback needs the same reviewed admission gate as activation.
  # Do not terminate a possibly running transaction merely to recover a file.
  need(current==old and sha(unit_raw)==UNIT_SHA,'live_rollback_requires_reviewed_connection_drain_gate')
  health()
  return dict(ok=True,status='OWN_WS4_COMPACT_RECEIPT_PARENT_ALREADY_ACTIVE',restored=old.name,binding=binding,database_writes=0)
 need(service_state['active_state'] in ('inactive','failed'),'rollback_restart_job_requires_drain_review')
 command(['systemctl','stop','goufayu-ws4.service'])
 stopped,stopped_state=observed()
 need(stopped_state['pid']==0 and stopped==current and sha(unit.read_bytes())==sha(unit_raw),'rollback_stopped_identity_changed')
 if sha(unit_raw)!=UNIT_SHA:replace_unit(sha(target_unit),original_unit)
 try:
  start_parent();need(active()[0]==old,'rollback_cwd_failed')
  return dict(ok=True,status='OWN_WS4_COMPACT_RECEIPT_ROLLED_BACK',restored=old.name,binding=binding,
   candidate_files_not_required=True,database_writes=0)
 except Exception as error:
  return dict(ok=False,status='PARENT_UNIT_RESTORED_START_OR_HEALTH_FAILED',restored_unit=old.name,
   error_type=type(error).__name__,binding=binding,candidate_files_not_required=True,database_writes=0)

def record_recovery(result):
 try:keep_services();result['retained_services_unchanged']=True
 except Exception:
  result['ok']=False;result['retained_services_unchanged']=False
  result['postcheck_error']='unrelated_service_pid_changed'
 try:save('rollback',result);result['receipt_persisted']=True
 except Exception:
  result['ok']=False;result['receipt_persisted']=False
  result['receipt_error']='recovery_receipt_write_failed'
 return result
with contextlib.ExitStack() as stack:
 if MODE!='audit':
  for name in sorted(('/var/lock/goufayu_admission_five.lock','/var/lock/goufayu_ws4_worker_cache.lock')):
   lock=stack.enter_context(open(name,'a'));fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
 # Never infer graceful drain from systemctl stop: the current API uses daemon
 # request threads and has no SIGTERM drain handler. Activation remains blocked
 # until a separately reviewed reversible NEW-connection gate is implemented.
 need(MODE!='activate','activation_requires_reviewed_connection_drain_gate')
 original=parent_inventory()
 expected_manifest_digest=expected_manifest
 current,service_state=observed();pid=service_state['pid'];unit_raw=unit.read_bytes()
 if MODE=='audit':
  need(current==old and pid>0,'ws4_parent_not_active')
  wd=re.findall(rb'(?m)^\s*WorkingDirectory=([^\r\n]+)',unit_raw)
  need(wd==[str(old/'backend').encode()],'ws4_unit_workdir_anchor_invalid')
  exec_lines=re.findall(rb'(?m)^\s*ExecStart=([^\r\n]+)',unit_raw)
  need(len(exec_lines)==1 and str(old).encode() not in exec_lines[0],'ws4_execstart_requires_separate_review')
  result=dict(ok=True,status='READ_ONLY_ACTUAL_WS4_COMPACT_RECEIPT_AUDIT',parent=old.name,parent_manifest_sha256=expected_manifest,
   source_revision=SOURCE,source_sha256=SOURCE_PINS,recipe=RECIPE,parent_full_inventory_verified=True,
   parent_inventory_sha256=sha(canonical(original)),parent_inventory=original,
   unit_sha256=sha(unit_raw),api_pid=pid,payload_sha256=pins,new_release=new.name,method_binding=method_binding,retained_services=retained,database_writes=0,unit_or_env_changed=False)
 else:
  need(re.fullmatch('[a-f0-9]{64}',UNIT_SHA or '') is not None,'explicit_parent_unit_sha_required')
  validate_parent_inventory(original)
  if MODE=='rollback':
   result=record_recovery(rollback_parent(original,current,service_state,unit_raw))
  elif MODE=='prepare':
   need(current==old and pid>0 and sha(unit_raw)==UNIT_SHA and not new.exists() and not records.exists(),'prepare_parent_drift_or_existing_candidate')
   health()
   need(not control_root.is_symlink(),'control_directory_symlink_rejected')
   control_root.mkdir(mode=0o700,exist_ok=True)
   need(control_root.stat().st_uid==os.geteuid() and control_root.stat().st_mode&0o077==0,'control_directory_permissions_invalid')
   records.mkdir(mode=0o700)
   with (records/'unit.original').open('xb') as stream:stream.write(unit_raw);stream.flush();os.fsync(stream.fileno())
   (records/'unit.original').chmod(0o600)
   binding=control_binding(original)
   with (records/'prepared_binding.json').open('xb') as stream:stream.write(canonical(binding));stream.flush();os.fsync(stream.fileno())
   (records/'prepared_binding.json').chmod(0o600)
   new.mkdir(mode=0o755)
   for name,digest in original.items():
    src=safe(old,name);need(sha(src.read_bytes())==digest,'parent_copy_changed')
    dest=safe(new,name);dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(src,dest);dest.chmod(src.stat().st_mode&0o777)
   need((old/'.venv').exists(),'parent_venv_missing');(new/'.venv').symlink_to(old/'.venv',target_is_directory=True)
   for name,value in payloads.items():
    dest=safe(new,name);dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(value);dest.chmod(0o644)
   with (new/'release_manifest.json').open('xb') as stream:stream.write(canonical(candidate_manifest(original)));stream.flush();os.fsync(stream.fileno())
   validate_candidate(original)
   result=dict(ok=True,status='WS4_COMPACT_RECEIPT_PREPARED_NOT_ACTIVE',release=new.name,payload_sha256=pins,binding=binding,database_writes=0)
  else:
   binding,(original_unit,target_unit)=validate_controls(original)
   prepared=validate_candidate(original)
   if MODE=='probe':
    need(current==old and sha(unit_raw)==UNIT_SHA,'probe_parent_drift')
    sys.path.insert(0,str(new/'backend'))
    from archive_backend.bundle import Bundle
    from archive_backend.service import ArchiveService
    from archive_backend.settlement_runner import clear_cache
    import archive_backend.command_timing as timing
    import importlib.util
    spec=importlib.util.spec_from_file_location('archive_backend.parent_probe',old/'backend/archive_backend/service.py')
    parent_module=importlib.util.module_from_spec(spec);spec.loader.exec_module(parent_module)
    bundle=Bundle(old/'addon/server/bundles'/bundle_hash)
    from unittest.mock import patch
    from types import SimpleNamespace
    frozen=1770000000
    synthetic=dict(schema_version=1,account_id='100',revision=1,entitlements={},achievements={},public={},save=dict(archive={},gameplay_stats={r['field_id']:r['default_value'] for r in bundle.configs['player_gameplay_stats']['rows']},content_inventory={'lottery_ticket':1000,'special_lottery_ticket':1000}))
    class MemoryReceipt:
     def __init__(self):self.profile=copy.deepcopy(synthetic);self.calls=[];self.operation=None
     def rpc(self,name,p):
      self.calls.append(name)
      if name=='archive_prepare':
       need(self.operation is None,'probe_duplicate_prepare');self.operation=copy.deepcopy(p['p_command'])
       return dict(ok=True,done=False,profile=copy.deepcopy(self.profile),command=copy.deepcopy(self.operation),has_pass=False,config_hash=bundle_hash)
      need(name=='archive_commit_lottery','probe_unexpected_rpc')
      need(not p['p_error'] and p['p_revision']==self.profile['revision'],'probe_commit_rejected')
      self.profile['save']['archive']=copy.deepcopy(p['p_archive']);self.profile['save']['content_inventory']=copy.deepcopy(p['p_inventory'])
      for key,value in p['p_deltas'].items():self.profile['save']['gameplay_stats'][key]+=value
      self.profile['revision']+=1
      return dict(ok=True,done=True,terminal=True,profile=copy.deepcopy(self.profile),response=copy.deepcopy(p['p_response']))
    samples=[]
    def one(implementation,compact):
     db=MemoryReceipt();app=SimpleNamespace(account_id_pepper='synthetic-readonly-compact-receipt-probe',rpc_client=db,
      _database_account_id=lambda account:account,_ensure_gameplay_stats=lambda account:None,
      _public_response=lambda response,database_account,public_account:copy.deepcopy(response))
     instance=implementation(app,bundle,'/usr/bin/lua')
     request=dict(account_id='100',config_hash=bundle_hash,command=dict(kind='lottery_draw',id='readonly-probe:draw-0001',request_id='readonly-probe-0001',pool_id='map',count=10))
     if compact:request['response_capabilities']={'lottery_committed_profile_v1':True}
     captured=[]
     with patch('archive_backend.service.time.time',return_value=frozen),patch.object(timing,'_emit',side_effect=captured.append):
      started=time.perf_counter();reply=instance.command(request);elapsed=(time.perf_counter()-started)*1000
     need(reply.get('ok') is True and db.calls==['archive_prepare','archive_commit_lottery'],'synthetic_draw_failed')
     core={k:v for k,v in reply.items() if k not in ('lottery_snapshots','snapshot_config_hash','snapshot_projection_ms')}
     return core,db.profile,dict(ms=elapsed,bytes=len(json.dumps(reply,separators=(',',':')).encode()),memory_rpc_calls=len(db.calls),real_rpc_calls=0,
      worker_calls=captured[0]['stages']['worker'][0] if captured else None)
    try:
     for ordinal in range(3):
      prior,prior_state,prior_timing=one(parent_module.ArchiveService,False)
      legacy,legacy_state,legacy_timing=one(ArchiveService,False)
      compact,compact_state,compact_timing=one(ArchiveService,True)
      need(prior==legacy==compact and prior_state==legacy_state==compact_state,'synthetic_receipt_state_or_rng_changed')
      need(legacy_timing['worker_calls']==2 and compact_timing['worker_calls']==1,'compact_worker_call_budget_failed')
      samples.append(dict(ordinal=ordinal,parent=prior_timing,legacy=legacy_timing,compact=compact_timing,equal=True))
    finally:clear_cache()
    # Bind this probe to the entire exact candidate, not merely its status.
    validate_candidate(original)
    result=dict(ok=True,status='ACTUAL_WS4_PREPARED_COMPACT_RECEIPT_PARITY_PASS',samples=samples,binding=binding,
     rpc_calls=0,real_player_data_used=False,database_writes=0,source_files_unchanged=True,
     boundary='Real Linux Lua with isolated in-memory receipts; no PostgreSQL/HTTP/auth/transit latency claim')
   elif MODE=='verify':
    need(current==new and sha(unit_raw)==sha(target_unit),'active_ws4_lineage_changed');health()
    result=dict(ok=True,status='ACTUAL_WS4_COMPACT_RECEIPT_ACTIVE_VERIFIED',release=new.name,manifest_sha256=sha((new/'release_manifest.json').read_bytes()),payload_sha256=pins,api_pid=pid,database_writes=0,env_unchanged=True,original_release_preserved=True)
   else:raise RuntimeError('invalid_ws4_mode')
  if MODE!='rollback':keep_services();result['retained_services_unchanged']=True;save(MODE,result)
 print(json.dumps(result))

'''

def git_blob(revision,name):
 if not re.fullmatch('[a-f0-9]{40}',revision or ''):raise RuntimeError('immutable_git_revision_required')
 return subprocess.check_output(['git','--no-replace-objects','-c','safe.directory='+ROOT.as_posix(),'-C',str(ROOT),'show',revision+':'+name])

def source_payloads(revision):
 if revision!=SOURCE or not re.fullmatch('[a-f0-9]{40}',SOURCE):raise RuntimeError('frozen_compact_receipt_source_revision_required')
 values={('backend/archive_backend/'+name):git_blob(revision,'server/archive_backend/'+name) for name in FILES}
 if {name:sha(raw) for name,raw in values.items()}!=SOURCE_PINS:raise RuntimeError('immutable_compact_receipt_source_changed')
 return {name:base64.b64encode(raw).decode('ascii') for name,raw in values.items()}

def plan():
 return dict(status='DRAFT_COMPACT_RECEIPT_PLAN_NOT_DEPLOYED',source_revision=SOURCE,
  source_sha256=SOURCE_PINS,parent_release=PARENT_RELEASE,parent_manifest_sha256=PARENT_MANIFEST,
  parent_service_sha256=PARENT_SERVICE,derived_service_sha256=DERIVED_SERVICE,
  files=3,remote_actions=0,database_writes=0,
  blockers=['Freeze source commit and operator commit','Review source-bound insertions and verified exact derived digest',
   'Review audit, synthetic probe, unit SHA and full parent inventory before Root executes',
   'Activation and live rollback require a separately reviewed connection drain gate'],
  preserves=['receipt identity and RNG','SQL/permissions','bundle/configs','payment/PWA','parent release'],
  bounds=dict(log_bytes_per_command=2048,extra_db_calls=0,extra_http_calls=0,idle_work=0))

def main(argv=None):
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument('mode',nargs='?',default='plan',choices=('plan','audit','prepare','probe','activate','verify','rollback'))
 parser.add_argument('--source-revision',default=SOURCE);parser.add_argument('--operator-revision');parser.add_argument('--unit-sha256')
 parser.add_argument('--parent-inventory-sha256')
 args=parser.parse_args(argv)
 if args.mode=='plan':
  print(json.dumps(plan(),sort_keys=True));return 0
 if args.mode=='activate':raise RuntimeError('activation_requires_reviewed_connection_drain_gate')
 if not re.fullmatch('[a-f0-9]{40}',SOURCE) or not re.fullmatch('[a-f0-9]{64}',DERIVED_SERVICE):
  raise RuntimeError('draft_source_and_derived_service_not_frozen')
 report=OUT/(args.mode+'.json')
 if report.exists():raise RuntimeError('preserve_existing_local_receipt')
 payloads=source_payloads(args.source_revision)
 if args.mode!='audit':
  own=git_blob(args.operator_revision,TOOL)
  if own!=Path(__file__).read_bytes().replace(b'\r\n',b'\n'):raise RuntimeError('operator_worktree_drift')
  if not re.fullmatch('[a-f0-9]{64}',args.unit_sha256 or ''):raise RuntimeError('parent_unit_sha256_required')
  if not re.fullmatch('[a-f0-9]{64}',args.parent_inventory_sha256 or ''):raise RuntimeError('parent_inventory_sha256_required')
 if sha(TRANSPORT.read_bytes())!=TRANSPORT_SHA:raise RuntimeError('pinned_transport_changed')
 spec=importlib.util.spec_from_file_location('ws4_compact_receipt_transport',TRANSPORT);transport=importlib.util.module_from_spec(spec);spec.loader.exec_module(transport)
 context=dict(MODE=args.mode,SOURCE=args.source_revision,EXPECTED_SOURCE=SOURCE,SOURCE_PINS=SOURCE_PINS,RECIPE=RECIPE,
  DERIVED_SERVICE=DERIVED_SERVICE,
  OPERATOR=args.operator_revision,UNIT_SHA=args.unit_sha256,PARENT_INVENTORY_SHA=args.parent_inventory_sha256,PAYLOADS=payloads)
 remote='\n'.join(k+'='+repr(v) for k,v in context.items())+'\n'+REMOTE
 result=transport.remote(remote,timeout=240)
 OUT.mkdir(parents=True,exist_ok=True)
 with report.open('x',encoding='utf8') as stream:json.dump(result,stream,sort_keys=True,indent=2);stream.write('\n')
 print(json.dumps(result));return 0 if result.get('ok') is True else 2

if __name__=='__main__':raise SystemExit(main())
