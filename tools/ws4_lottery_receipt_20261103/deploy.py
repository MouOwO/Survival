"""Exact WS4 two-file receipt projection rollout, never the legacy test API.

Default is metadata only. No SQL mutation or real draw/redemption is available.
Activation requires immutable operator, parent/unit pins and a real Lua probe.
"""
from pathlib import Path
import argparse,base64,hashlib,importlib.util,json,re,subprocess
ROOT=Path(__file__).resolve().parents[2]
TRANSPORT=ROOT/'tools/archive_release_20261029/server_deploy.py'
TRANSPORT_SHA='66413c174fb6fe27d5ae84dc267ceea07366c6f6a855a9406e5ffdaf388b1cc5'
SOURCE='14812ec239d3dd24634b9b860b81e35a9a9fd721'
OUT=ROOT/'output/ws4_lottery_receipt_20261103'
sha=lambda raw:hashlib.sha256(raw).hexdigest()
REMOTE=r'''
from pathlib import Path,PurePosixPath
import base64,contextlib,copy,fcntl,hashlib,json,os,re,shutil,subprocess,sys,time,urllib.request
sha=lambda raw:hashlib.sha256(raw).hexdigest()
base=Path('/opt/goufayu-ws4/releases')
old=base/'20261101-admission-five-ffd96ff80622'
unit=Path('/etc/systemd/system/goufayu-ws4.service')
expected_manifest='970792238ee146c7dbb247e5fe1e7b320899c4f8273859223d591069a1a3d38e'
expected_service='b75684f5052930b579d5dc3e0df6004e83328ff171c75c650f5564b813998165'
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
raw=safe(old,service).read_bytes();need(sha(raw)==expected_service,'ws4_parent_service_changed')
needle='        result=self.finish_prepared(database_id,command["id"],prepared)\n        return self.app._public_response(result,database_id,account)'
replacement='        result=self.finish_prepared(database_id,command["id"],prepared)\n        reply=self.app._public_response(result,database_id,account)\n        from .lottery_receipt_snapshot import attach\n        return attach(self,reply,command,requested_hash)'
text=raw.decode().replace('\r\n','\n');need(text.count(needle)==1,'ws4_exact_patch_anchor_missing')
helper=base64.b64decode(HELPER,validate=True)
need(sha(helper)=='9192fc746010acd798a06fd551f65d5729e2727f5ed19667d8fbbff17a1c8e38','reviewed_helper_changed')
payloads={service:text.replace(needle,replacement).encode(),'backend/archive_backend/lottery_receipt_snapshot.py':helper}
pins={name:sha(value) for name,value in payloads.items()}
for name,value in payloads.items():compile(value,name,'exec')
new=base/('20261103-ws4-lottery-receipt-'+sha(json.dumps(pins,sort_keys=True).encode())[:12])
records=new/'receipt_operator'
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
 path=records/(name+'.json');need(not path.exists(),'preserve_remote_receipt')
 with path.open('x') as f:json.dump(result,f,sort_keys=True)
 path.chmod(0o600)
def replace_unit(expected,target):
 need(not unit.is_symlink() and sha(unit.read_bytes())==expected,'ws4_unit_changed')
 info=unit.stat();temp=unit.with_name(unit.name+'.lottery-receipt-'+str(os.getpid()))
 need(not temp.exists(),'unit_temporary_exists')
 with temp.open('xb') as f:f.write(target);f.flush();os.fsync(f.fileno())
 os.chmod(temp,info.st_mode&0o777);os.chown(temp,info.st_uid,info.st_gid);os.replace(temp,unit)
with contextlib.ExitStack() as stack:
 if MODE!='audit':
  for name in sorted(('/var/lock/goufayu_admission_five.lock','/var/lock/goufayu_ws4_lottery_receipt.lock')):
   lock=stack.enter_context(open(name,'a'));fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
 validate_files(old,manifest['files'])
 current,pid=active();unit_raw=unit.read_bytes()
 if MODE=='audit':
  need(current==old,'ws4_parent_not_active')
  wd=re.findall(rb'(?m)^\s*WorkingDirectory=([^\r\n]+)',unit_raw)
  need(wd==[str(old/'backend').encode()],'ws4_unit_workdir_anchor_invalid')
  exec_lines=re.findall(rb'(?m)^\s*ExecStart=([^\r\n]+)',unit_raw)
  need(len(exec_lines)==1 and str(old).encode() not in exec_lines[0],'ws4_execstart_requires_separate_review')
  result=dict(ok=True,status='READ_ONLY_ACTUAL_WS4_RECEIPT_AUDIT',parent=old.name,parent_manifest_sha256=expected_manifest,
   unit_sha256=sha(unit_raw),api_pid=pid,payload_sha256=pins,new_release=new.name,retained_services=retained,database_writes=0,unit_or_env_changed=False)
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
   prepared={**manifest,'release':new.name,'files':{**original,**pins},'lottery_receipt_parent_manifest_sha256':expected_manifest,
    'lottery_receipt_source_revision':SOURCE,'lottery_receipt_operator_revision':OPERATOR,'lottery_receipt_changed_files':sorted(pins),
    'lottery_receipt_parent_unit_sha256':UNIT_SHA,'database_changed':False,'addon_root_and_env_unchanged':True}
   (new/'release_manifest.json').write_text(json.dumps(prepared,sort_keys=True,separators=(',',':')))
   records.mkdir(mode=0o700);(records/'unit.original').write_bytes(unit_raw);(records/'unit.original').chmod(0o600)
   result=dict(ok=True,status='WS4_RECEIPT_PREPARED_NOT_ACTIVE',release=new.name,payload_sha256=pins,database_writes=0)
  else:
   need(new.is_dir() and not new.is_symlink(),'prepared_ws4_release_missing')
   prepared=json.loads((new/'release_manifest.json').read_bytes())
   need(prepared['lottery_receipt_source_revision']==SOURCE and prepared['lottery_receipt_operator_revision']==OPERATOR
    and prepared['lottery_receipt_parent_unit_sha256']==UNIT_SHA and prepared['lottery_receipt_changed_files']==sorted(pins),'prepared_source_binding_changed')
   validate_files(new,prepared['files']);need(all(prepared['files'][k]==v for k,v in pins.items()),'payload_pins_changed')
   original_unit=(records/'unit.original').read_bytes();need(sha(original_unit)==UNIT_SHA,'original_unit_backup_changed')
   target_unit,count=re.subn(rb'(?m)^(\s*WorkingDirectory=)[^\r\n]+',lambda m:m[1]+str(new/'backend').encode(),original_unit)
   need(count==1,'unit_workdir_anchor_changed')
   if MODE=='probe':
    need(current==old and sha(unit_raw)==UNIT_SHA,'probe_parent_drift')
    sys.path.insert(0,str(new/'backend'))
    from archive_backend.bundle import Bundle
    from archive_backend.service import ArchiveService
    from archive_backend.lottery_receipt_snapshot import attach
    from types import SimpleNamespace
    bundle=Bundle(old/'addon/server/bundles'/bundle_hash)
    calls=[]
    def forbidden(*args,**kwargs):calls.append(True);raise RuntimeError('probe_forbidden_rpc')
    app=SimpleNamespace(account_id_pepper='synthetic-readonly-probe',rpc_client=SimpleNamespace(rpc=forbidden))
    service_instance=ArchiveService(app,bundle,'/usr/bin/lua')
    profile=dict(schema_version=1,account_id='100',revision=1,entitlements={},achievements={},public={},save=dict(archive={},
     gameplay_stats={r['field_id']:r['default_value'] for r in bundle.configs['player_gameplay_stats']['rows']},content_inventory={'lottery_ticket':37,'special_lottery_ticket':11}))
    before=copy.deepcopy(profile);times=[]
    for index in range(3):
     reply=attach(service_instance,dict(ok=True,done=True,profile=profile),{'id':'synthetic_receipt_probe','kind':'lottery_draw'},bundle_hash)
     snapshots=reply.get('lottery_snapshots',[])
     need(len(snapshots)==4 and next(r['tickets'] for r in snapshots if r['selected_pool_id']=='map')==37,'actual_lua_projection_failed')
     need(profile==before and not calls,'probe_modified_profile_or_called_database');times.append(reply['snapshot_projection_ms'])
    result=dict(ok=True,status='ACTUAL_WS4_PREPARED_LUA_PROJECTION_PASS',pools=4,iterations=3,projection_ms=times,rpc_calls=0,real_player_data_used=False,database_writes=0)
   elif MODE=='activate':
    need(current==old and sha(unit_raw)==UNIT_SHA,'activation_parent_drift')
    probe=json.loads((records/'probe.json').read_bytes());need(probe.get('status')=='ACTUAL_WS4_PREPARED_LUA_PROJECTION_PASS','real_lua_probe_required')
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
    result=dict(ok=True,status='ACTUAL_WS4_RECEIPT_ACTIVE',release=new.name,api_pid=active()[1],unit_sha256=sha(unit.read_bytes()),database_writes=0,env_unchanged=True,original_release_preserved=True)
   elif MODE=='verify':
    need(current==new and sha(unit_raw)==sha(target_unit),'active_ws4_lineage_changed');health()
    result=dict(ok=True,status='ACTUAL_WS4_RECEIPT_ACTIVE_VERIFIED',release=new.name,manifest_sha256=sha((new/'release_manifest.json').read_bytes()),payload_sha256=pins,api_pid=pid,database_writes=0,env_unchanged=True,original_release_preserved=True)
   elif MODE=='rollback':
    need(current==new,'only_own_active_release_can_rollback');replace_unit(sha(target_unit),original_unit);restart();need(active()[0]==old,'rollback_cwd_failed')
    result=dict(ok=True,status='OWN_WS4_RECEIPT_ROLLED_BACK',restored=old.name,prepared_preserved=True,database_writes=0)
   else:raise RuntimeError('invalid_ws4_mode')
  keep_services();result['retained_services_unchanged']=True;save(MODE,result)
 print(json.dumps(result))
'''
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode',nargs='?',default='plan',choices=('plan','audit','prepare','probe','activate','verify','rollback'))
    parser.add_argument('--operator-revision');parser.add_argument('--unit-sha256')
    args=parser.parse_args()
    if args.mode=='plan':print(json.dumps(dict(status='STATIC_ACTUAL_WS4_RECEIPT_PLAN',files=2,database_writes=0,remote_actions=0)));return
    report=OUT/(args.mode+'.json');OUT.mkdir(parents=True,exist_ok=True)
    if report.exists():raise RuntimeError('preserve_existing_local_receipt')
    if args.mode!='audit':
        if not re.fullmatch('[a-f0-9]{40}',args.operator_revision or ''):raise RuntimeError('immutable_operator_required')
        own=subprocess.check_output(['git','show',args.operator_revision+':'+Path(__file__).relative_to(ROOT).as_posix()],cwd=ROOT)
        if own!=Path(__file__).read_bytes().replace(b'\r\n',b'\n'):raise RuntimeError('operator_worktree_drift')
    helper=subprocess.check_output(['git','show',SOURCE+':server/archive_backend/lottery_receipt_snapshot.py'],cwd=ROOT)
    if sha(TRANSPORT.read_bytes())!=TRANSPORT_SHA:raise RuntimeError('pinned_transport_changed')
    spec=importlib.util.spec_from_file_location('ws4_receipt_transport',TRANSPORT);transport=importlib.util.module_from_spec(spec);spec.loader.exec_module(transport)
    context=dict(MODE=args.mode,OPERATOR=args.operator_revision,SOURCE=SOURCE,UNIT_SHA=args.unit_sha256,HELPER=base64.b64encode(helper).decode())
    remote='\n'.join(k+'='+repr(v) for k,v in context.items())+'\n'+REMOTE
    result=transport.remote(remote,timeout=240)
    report.write_text(json.dumps(result,indent=2)+'\n',encoding='utf8');print(json.dumps(result))
if __name__=='__main__':main()
