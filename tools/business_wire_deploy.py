"""Stage a pinned PWA-only wire release; never authenticate, migrate or charge.

plan is a fresh read-only observation plus a local immutable plan. prepare writes
a new inactive release. activate alone may restart the PWA, with parent CAS,
private backups, a persistent pending marker and guarded automatic rollback.
Each invocation is explicit; a failed/unknown activation is never replayed.
"""
from __future__ import annotations

import argparse
import base64
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import secrets
import subprocess
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
OVERLAY = (
    "player_web_auth/http_api.py",
    "player_web_auth/business_wire.py",
    "player_web_auth/business_wire_schema.json",
)
SELF = "tools/business_wire_deploy.py"
TRANSPORT = "tools/archive_caps_20261020/remote_driver.py"
HOSTS = "tools/deploy/goufayu_test_known_hosts"
LEDGER = "tools/release_storage_ledger.py"


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True,
                      separators=(",", ":"), allow_nan=False).encode("utf-8")


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def need(ok, code):
    if not ok:
        raise ValueError(code)


def git(*args):
    run = subprocess.run(["git", "--no-optional-locks", "--no-replace-objects",
                          "-c", "safe.directory=" + ROOT.as_posix(), *args],
                         cwd=ROOT, capture_output=True, timeout=45)
    need(run.returncode == 0, "git_read_failed")
    return run.stdout


def source_binding(revision):
    commit = git("rev-parse", "--verify", revision + "^{commit}").decode().strip()
    need(re.fullmatch("[0-9a-f]{40}", commit), "source_revision_invalid")
    paths = (SELF, TRANSPORT, HOSTS, LEDGER, *("server/" + p for p in OVERLAY))
    sources, hashes = {}, {}
    for name in paths:
        raw = git("show", commit + ":" + name).replace(b"\r\n", b"\n")
        need((ROOT / name).read_bytes().replace(b"\r\n", b"\n") == raw,
             "declared_git_source_dirty")
        sources[name], hashes[name] = raw, sha(raw)
    return commit, hashes, {name: sources["server/" + name] for name in OVERLAY}


def output_directory(value):
    path = Path(value)
    need(path.is_absolute(), "absolute_external_output_required")
    for parent in (path, *path.parents):
        need(not parent.is_symlink() and not getattr(parent, "is_junction", lambda: False)(),
             "output_reparse_point_rejected")
    path = path.resolve()
    allowed = Path("D:/Survival_本地工具").resolve()
    need(path.is_relative_to(allowed / "runs") and path != allowed / "runs",
         "output_must_be_external_runs_child")
    return path


def write_new(path, raw):
    with path.open("xb") as stream:
        stream.write(raw)
        stream.flush()
        os.fsync(stream.fileno())


def record(receipt):
    result = subprocess.run([sys.executable, "-X", "utf8", "-B", str(ROOT / LEDGER), "record",
                             "--receipt", str(receipt)], cwd=ROOT, capture_output=True,
                            timeout=45)
    need(result.returncode == 0, "storage_ledger_registration_failed_receipt_retained")
    return json.loads(result.stdout)


REMOTE = r"""
import base64, fcntl, hashlib, json, os, re, stat, subprocess, time
from pathlib import Path
import urllib.request

BASE = Path('/opt/goufayu-ws4-web/releases')
OPS = Path('/root/survival_business_wire_deploy')
UNIT = Path('/etc/systemd/system/goufayu-ws4-web.service')
SERVICE = 'goufayu-ws4-web.service'
SOURCES = (
 'lobby_backend/__init__.py','lobby_backend/http_api.py','lobby_backend/service.py',
 'player_web_auth/__init__.py','player_web_auth/http_api.py',
 'player_web_auth/run.py','player_web_auth/service.py','player_web_auth/game_diagnostics.py',
)
OVERLAY = ('player_web_auth/http_api.py','player_web_auth/business_wire.py',
           'player_web_auth/business_wire_schema.json')
RETAINED = ('goufayu-ws4.service','goufayu-ws4-db.service','goufayu-ws4-payment.service',
            'goufayu-api.service','goufayu-db.service','goufayu-payment.service','nginx.service')
class GuardError(Exception): pass
def need(ok,code):
 if not ok: raise GuardError(code)
def canonical(value):
 return json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(',',':'),allow_nan=False).encode()
def sha(raw): return hashlib.sha256(raw).hexdigest()
def regular(path,limit=8*1024*1024):
 need(path.is_file() and not path.is_symlink() and path.stat().st_size<=limit,'bounded_regular_file_required')
 for node in (path,*path.parents): need(not node.is_symlink(),'source_symlink_rejected')
 return path.read_bytes()
def new(path,raw,mode=0o600):
 fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,mode)
 os.fchmod(fd,mode)
 with os.fdopen(fd,'wb') as stream:
  stream.write(raw);stream.flush();os.fsync(stream.fileno())
def private(path,create=False):
 if not path.exists() and create: path.mkdir(mode=0o700,parents=False)
 need(path.is_dir() and not path.is_symlink() and path.stat().st_uid==0
      and stat.S_IMODE(path.stat().st_mode)&0o077==0,'private_operator_directory_required')
def ctl(*args,timeout=35):
 result=subprocess.run(['systemctl',*args],stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=timeout)
 need(result.returncode==0,'systemctl_operation_failed')
 return result.stdout.decode().strip()
def props(name,timeout=35):
 result=ctl('show',name,'--property=MainPID,ActiveState,FragmentPath',timeout=timeout)
 return dict(line.split('=',1) for line in result.splitlines() if '=' in line)
def working_directory(raw):
 matches=re.findall(rb'(?m)^[ \t]*WorkingDirectory[ \t]*=[ \t]*([^\r\n]+)\r?$',raw)
 need(len(matches)==1,'unique_working_directory_required')
 value=Path(matches[0].strip().decode('utf-8'))
 need(value.is_absolute() and value.parent==BASE and value.resolve()==value
      and re.fullmatch(r'[A-Za-z0-9_-]+',value.name),'web_parent_directory_invalid')
 return value
def changed_unit(raw,candidate):
 working_directory(raw)
 result,count=re.subn(rb'(?m)^([ \t]*WorkingDirectory[ \t]*=[ \t]*)[^\r\n]+',
                       lambda match:match.group(1)+str(candidate).encode(),raw)
 need(count==1,'working_directory_replace_failed')
 return result
def environment_digest(raw):
 matches=re.findall(rb'(?m)^[ \t]*EnvironmentFile[ \t]*=[ \t]*([^\r\n]+)\r?$',raw)
 need(len(matches)==1,'unique_environment_file_required')
 path=Path(matches[0].strip().decode('utf-8'))
 need(path.is_absolute() and path.parent==Path('/etc/goufayu-ws4-web'),'environment_path_unexpected')
 return sha(regular(path))
def health(timeout=2):
 try:
  class NoRedirect(urllib.request.HTTPRedirectHandler):
   def redirect_request(self,*args,**kwargs): return None
  opener=urllib.request.build_opener(urllib.request.ProxyHandler({}),NoRedirect())
  with opener.open('http://127.0.0.1:18767/health',timeout=timeout) as response:
   raw=response.read(16385)
   return response.status==200 and len(raw)<=16384 and json.loads(raw).get('ok') is True
 except Exception: return False
def healthy():
 for _ in range(16):
  if health(): return
  time.sleep(0.25)
 need(False,'web_health_failed')

def safe_failure(error):
 result={'error_type':type(error).__name__}
 if isinstance(error,GuardError) and re.fullmatch('[a-z_]{1,100}',str(error)):
  result['failure_code']=str(error)
 else: result['failure_code']='unexpected_operator_exception'
 fields={'attempts':int,'active':bool,'pid':int,'cwd_matches':bool,
         'healthy':bool,'identity_stable':bool}
 state=getattr(error,'readiness',None)
 if (result['failure_code']=='web_readiness_timeout' and isinstance(error,GuardError)
     and type(state) is dict and set(state)==set(fields)
     and all(type(state[key]) is expected for key,expected in fields.items())):
  result['readiness']={key:state[key] for key in fields}
 return result

def wait_web_ready(root,excluded_pid=None,timeout=12):
 # Deployment-only bounded polling: at most 49 iterations, O(1) state. Each
 # attempt reads one service and one cwd; only a matching candidate gets one
 # loopback health request and a second identity read. No player/SQL calls.
 deadline=time.monotonic()+timeout
 state={'attempts':0,'active':False,'pid':0,'cwd_matches':False,
        'healthy':False,'identity_stable':False}
 while True:
  remaining=deadline-time.monotonic()
  if remaining<=0: break
  try: web=props(SERVICE,timeout=remaining)
  except subprocess.TimeoutExpired: break
  pid=web.get('MainPID','0')
  state.update(attempts=state['attempts']+1,active=web.get('ActiveState')=='active',
               pid=int(pid),cwd_matches=False,healthy=False,identity_stable=False)
  if state['active'] and int(pid)>0 and pid!=excluded_pid:
   try: state['cwd_matches']=Path(os.readlink('/proc/'+pid+'/cwd'))==root
   except (FileNotFoundError,ProcessLookupError): pass
   if state['cwd_matches']:
    remaining=deadline-time.monotonic()
    if remaining<=0: break
    state['healthy']=health(timeout=min(2,remaining))
    if state['healthy']:
     remaining=deadline-time.monotonic()
     if remaining<=0: break
     try: after=props(SERVICE,timeout=remaining)
     except subprocess.TimeoutExpired: break
     if after==web:
      try: state['identity_stable']=Path(os.readlink('/proc/'+pid+'/cwd'))==root
      except (FileNotFoundError,ProcessLookupError): pass
     if state['identity_stable'] and time.monotonic()<=deadline: return web,state
  remaining=deadline-time.monotonic()
  if remaining<=0: break
  time.sleep(min(0.25,remaining))
 error=GuardError('web_readiness_timeout');error.readiness=state
 raise error
def source_hashes(parent):
 actual={p.relative_to(parent).as_posix() for p in parent.rglob('*.py')}
 need(actual==set(SOURCES),'unclassified_parent_python_source')
 return {name:sha(regular(parent/name)) for name in SOURCES}
def observe():
 raw=regular(UNIT,128*1024)
 need(UNIT.stat().st_uid==0,'unit_owner_invalid')
 parent=working_directory(raw);web=props(SERVICE)
 need(web.get('ActiveState')=='active' and int(web.get('MainPID','0'))>0
      and web.get('FragmentPath')==str(UNIT),'web_service_not_active')
 pid=int(web['MainPID'])
 need(Path(os.readlink('/proc/'+str(pid)+'/cwd'))==parent,'web_process_directory_mismatch')
 result={'working_directory':str(parent),'unit_sha256':sha(raw),
         'environment_sha256':environment_digest(raw),'source_hashes':source_hashes(parent),
         'web':web,'retained':{name:props(name) for name in RETAINED}}
 need(health(),'parent_health_failed')
 return result
def parent_check(expected):
 current=observe()
 need(current==expected,'parent_source_unit_process_or_service_changed')
 return current
def candidate_files(plan):
 result=dict(plan['parent']['source_hashes']);result.update(plan['overlay'])
 return result
def validate_release(plan):
 root=Path(plan['candidate'])
 need(root.parent==BASE and root.name=='business-wire-'+plan['release_digest']
      and root.is_dir() and not root.is_symlink(),'candidate_directory_invalid')
 expected=candidate_files(plan)
 actual={p.relative_to(root).as_posix() for p in root.rglob('*') if p.is_file()}
 need(actual==set(expected)|{'release_manifest.json'},'candidate_file_set_changed')
 for name,digest in expected.items(): need(sha(regular(root/name))==digest,'candidate_source_changed')
 manifest=json.loads(regular(root/'release_manifest.json'))
 need(manifest=={'schema':1,'plan_sha256':sha(canonical(plan)),
                 'source_revision':plan['source_revision'],'files':expected},
      'candidate_manifest_changed')
 return root
def preflight(root,plan):
 # No production environment is inherited. Imports do not construct Service,
 # connect to SQLite/PostgreSQL, request Steam, or run the HTTP server.
 code=("import sys,json,pathlib;sys.path.insert(0,"+repr(str(root))+");"
       "root=pathlib.Path("+repr(str(root))+");"
       "[compile(p.read_bytes(),str(p),'exec') for p in root.rglob('*.py')];"
       "import player_web_auth.http_api,player_web_auth.run,player_web_auth.service,"
       "player_web_auth.game_diagnostics,lobby_backend.http_api,lobby_backend.service;"
       "from player_web_auth.business_wire import SCHEMA,SCHEMA_HASH,canonical,pack_bytes,decode;"
       "sample=dict(SCHEMA['templates'][0]['defaults']);"
       "value={'ok':True,'profile':{'daily_limits':{'rows':[sample]*40}}};"
       "raw=canonical(value);wire=pack_bytes(raw,SCHEMA_HASH);"
       "assert wire!=raw and canonical(decode(json.loads(wire)))==raw;"
       "print(json.dumps({'ok':True,'schema_hash':SCHEMA_HASH,"
       "'legacy_bytes':len(raw),'wire_bytes':len(wire)}))")
 result=subprocess.run(['/usr/bin/python3.11','-I','-B','-c',code],cwd=root,
        env={'PATH':'/usr/bin:/bin','PYTHONDONTWRITEBYTECODE':'1','LANG':'C.UTF-8'},
        stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=25)
 need(result.returncode==0,'inactive_python_import_or_codec_selftest_failed')
 value=json.loads(result.stdout)
 need(value.get('ok') is True and value.get('schema_hash')==plan['schema_hash'],
      'inactive_schema_selftest_mismatch')
 return value
def operator_directory(plan,plan_hash,create=False):
 need(re.fullmatch('[0-9a-f]{64}',plan_hash),'plan_hash_invalid')
 private(OPS,create)
 path=OPS/plan_hash
 private(path,create)
 need(path.is_dir() and not path.is_symlink(),'prepared_operator_directory_missing')
 plan_path=path/'plan.json'
 if not plan_path.exists() and create: new(plan_path,canonical(plan))
 need(regular(plan_path)==canonical(plan),'remote_plan_changed')
 return path
def atomic_unit(raw,attempt):
 temporary=UNIT.with_name(UNIT.name+'.business-wire-'+attempt+'.tmp')
 mode=stat.S_IMODE(UNIT.stat().st_mode)
 new(temporary,raw,mode);os.replace(temporary,UNIT)
 descriptor=os.open(UNIT.parent,os.O_RDONLY|os.O_DIRECTORY)
 try: os.fsync(descriptor)
 finally: os.close(descriptor)
def prepare(plan,plan_hash,payload):
 parent_check(plan['parent'])
 ops=operator_directory(plan,plan_hash,create=True)
 need(not (ops/'activation_pending.json').exists(),'activation_pending_reconcile_required')
 root=Path(plan['candidate']);expected=candidate_files(plan)
 need(set(payload['files'])==set(OVERLAY),'overlay_allowlist_mismatch')
 decoded={}
 for name,encoded in payload['files'].items():
  raw=base64.b64decode(encoded,validate=True)
  need(sha(raw)==plan['overlay'][name],'overlay_digest_mismatch')
  decoded[name]=raw
 backup=ops/'parent_unit.bin'
 if not backup.exists(): new(backup,regular(UNIT,128*1024))
 need(sha(regular(backup))==plan['parent']['unit_sha256'],'parent_unit_backup_mismatch')
 if root.exists():
  validate_release(plan)
  need((ops/'prepared.json').is_file(),'interrupted_prepare_requires_review')
  return {'status':'ALREADY_PREPARED','candidate':str(root),'selftest':preflight(root,plan)}
 need(root.parent==BASE and root.name=='business-wire-'+plan['release_digest'],
      'candidate_name_invalid')
 root.mkdir(mode=0o755);root.chmod(0o755)
 for name in expected:
  target=root/name;target.parent.mkdir(mode=0o755,exist_ok=True);target.parent.chmod(0o755)
  raw=decoded[name] if name in decoded else regular(Path(plan['parent']['working_directory'])/name)
  need(sha(raw)==expected[name],'parent_source_changed_while_copying')
  new(target,raw,0o644)
 manifest={'schema':1,'plan_sha256':plan_hash,'source_revision':plan['source_revision'],'files':expected}
 new(root/'release_manifest.json',canonical(manifest),0o644)
 validate_release(plan)
 proof=preflight(root,plan);parent_check(plan['parent'])
 result={'status':'PREPARED_INACTIVE','candidate':str(root),'selftest':proof,
         'parent_unit_backup_sha256':sha(regular(backup)),'active_services_changed':False}
 new(ops/'prepared.json',canonical(result))
 return result
def verify_active(plan,ops):
 root=validate_release(plan)
 parent_unit=regular(ops/'parent_unit.bin',128*1024)
 need(sha(parent_unit)==plan['parent']['unit_sha256'],'parent_backup_changed')
 expected_unit=changed_unit(parent_unit,root)
 need(regular(UNIT,128*1024)==expected_unit,'active_unit_differs_from_candidate')
 need(environment_digest(expected_unit)==plan['parent']['environment_sha256'],'environment_changed')
 need({name:props(name) for name in RETAINED}==plan['parent']['retained'],'retained_service_changed')
 web,readiness=wait_web_ready(root,plan['parent']['web']['MainPID'])
 need(regular(UNIT,128*1024)==expected_unit,'active_unit_changed_during_readiness')
 need(environment_digest(expected_unit)==plan['parent']['environment_sha256'],'environment_changed')
 need({name:props(name) for name in RETAINED}==plan['parent']['retained'],'retained_service_changed')
 validate_release(plan)
 return {'status':'ACTIVE_VERIFIED','candidate':str(root),'web':web,
         'schema_hash':plan['schema_hash'],'retained_services_unchanged':True,
         'environment_unchanged':True,'authenticated_player_requests':0,'readiness':readiness}
def activate(plan,plan_hash,payload):
 ops=operator_directory(plan,plan_hash)
 need((ops/'prepared.json').is_file(),'prepared_receipt_required')
 need(not (ops/'activation_pending.json').exists(),'activation_pending_reconcile_required')
 root=validate_release(plan);proof=preflight(root,plan)
 parent_check(plan['parent'])
 original=regular(ops/'parent_unit.bin',128*1024)
 need(sha(original)==plan['parent']['unit_sha256'],'parent_backup_changed')
 updated=changed_unit(original,root)
 new(ops/'activation_pending.json',canonical({'plan_sha256':plan_hash,
     'parent_unit_sha256':sha(original),'candidate_unit_sha256':sha(updated),
     'attempt':payload['attempt']}))
 need(regular(UNIT,128*1024)==original,'parent_unit_changed_before_switch')
 switched=False;stage='unit_switch'
 try:
  atomic_unit(updated,payload['attempt']);switched=True
  stage='daemon_reload';ctl('daemon-reload')
  stage='web_restart';ctl('restart',SERVICE)
  stage='candidate_verification'
  result=verify_active(plan,ops)
  result['selftest']=proof
  new(ops/'activated.json',canonical(result))
  return result
 except Exception as error:
  rolled_back=False;rollback_failure=None
  # Never overwrite another operator's post-switch change.
  if switched and regular(UNIT,128*1024)==updated:
   try:
    need(environment_digest(original)==plan['parent']['environment_sha256'],
         'rollback_environment_changed_reconcile_required')
    need(source_hashes(Path(plan['parent']['working_directory']))==plan['parent']['source_hashes'],
         'rollback_parent_source_changed_reconcile_required')
    atomic_unit(original,payload['attempt']+'-rollback')
    ctl('daemon-reload');ctl('restart',SERVICE)
    wait_web_ready(Path(plan['parent']['working_directory']),plan['parent']['web']['MainPID'])
    rolled_back=(regular(UNIT,128*1024)==original
       and environment_digest(original)==plan['parent']['environment_sha256']
       and {name:props(name) for name in RETAINED}==plan['parent']['retained'])
   except Exception as rollback_error: rollback_failure=safe_failure(rollback_error)
  result={'status':'ACTIVATION_FAILED','ok':False,'rolled_back':rolled_back,
          'backup_directory':str(ops),'pending_preserved':True,
          'failure_stage':stage,**safe_failure(error)}
  if rollback_failure: result['rollback_failure']=rollback_failure
  new(ops/'activation_failed.json',canonical(result))
  return result
def execute(payload):
 need(payload['phase'] in ('plan','prepare','activate','verify'),'phase_invalid')
 need(re.fullmatch('[0-9a-f]{16}',payload['attempt']),'attempt_invalid')
 lock=os.open('/run/lock/survival-business-wire-deploy.lock',os.O_RDWR|os.O_CREAT|os.O_NOFOLLOW,0o600)
 try:
  fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
  if payload['phase']=='plan': return {'ok':True,'parent':observe()}
  plan=payload['plan'];plan_hash=payload['plan_sha256']
  need(sha(canonical(plan))==plan_hash and plan['kind']=='BUSINESS_WIRE_WEB_DEPLOY_PLAN',
       'plan_digest_mismatch')
  need(set(plan['overlay'])==set(OVERLAY) and set(plan['parent']['source_hashes'])==set(SOURCES),
       'plan_scope_invalid')
  if payload['phase']=='prepare': result=prepare(plan,plan_hash,payload)
  elif payload['phase']=='activate': result=activate(plan,plan_hash,payload)
  else:
   ops=operator_directory(plan,plan_hash)
   need((ops/'activated.json').is_file(),'successful_activation_receipt_required')
   result=verify_active(plan,ops)
  result.setdefault('ok',True)
  ops=operator_directory(plan,plan_hash)
  receipt=ops/(payload['phase']+'_'+payload['attempt']+'_receipt.json')
  raw=canonical(result);new(receipt,raw)
  result['remote_receipt_path']=str(receipt);result['remote_receipt_sha256']=sha(raw)
  return result
 finally: os.close(lock)
try:
 result=execute(PAYLOAD)
except GuardError as error:
 result={'ok':False,'status':'GUARD_REJECTED','error':error.args[0]}
except Exception as error:
 result={'ok':False,'status':'FAILED','error_type':type(error).__name__}
if result.get('ok') is False and 'remote_receipt_path' not in result and PAYLOAD.get('phase') in ('prepare','activate','verify'):
 try:
  plan=PAYLOAD['plan'];plan_hash=PAYLOAD['plan_sha256']
  need(sha(canonical(plan))==plan_hash,'plan_digest_mismatch')
  ops=operator_directory(plan,plan_hash,create=PAYLOAD['phase']=='prepare')
  receipt=ops/(PAYLOAD['phase']+'_'+PAYLOAD['attempt']+'_failed_receipt.json')
  raw=canonical(result);new(receipt,raw)
  result['remote_receipt_path']=str(receipt);result['remote_receipt_sha256']=sha(raw)
 except Exception: result['remote_receipt_written']=False
print(json.dumps(result,separators=(',',':')))
"""


def remote(payload):
    spec = importlib.util.spec_from_file_location("wire_deploy_pinned_transport", ROOT / TRANSPORT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    packed = base64.b64encode(canonical(payload)).decode("ascii")
    source = "import json,base64\nPAYLOAD=json.loads(base64.b64decode(" + repr(packed) + "))\n" + REMOTE
    return json.loads(module.remote(source, timeout=120))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("phase", choices=("plan", "prepare", "activate", "verify"))
    parser.add_argument("--output", required=True)
    parser.add_argument("--revision", default="HEAD")
    parser.add_argument("--plan-sha256")
    parser.add_argument("--observed-web", type=Path)
    args = parser.parse_args(argv)
    output = output_directory(args.output)
    attempt = secrets.token_hex(8)
    if args.phase == "plan":
        commit, bindings, files = source_binding(args.revision)
        need(not output.exists(), "new_output_directory_required")
        result = remote({"phase": "plan", "attempt": attempt})
        need(result.get("ok") is True, "remote_parent_observation_failed")
        parent = result["parent"]
        if args.observed_web:
            observed = json.loads(args.observed_web.read_bytes())
            need(observed["working_directory"] == parent["working_directory"]
                 and observed["source_hashes"] == parent["source_hashes"]
                 and observed["properties"]["MainPID"] == parent["web"]["MainPID"],
                 "reviewed_web_observation_changed")
        schema = json.loads(files["player_web_auth/business_wire_schema.json"])
        seed = {"parent": parent, "overlay": {k: sha(v) for k, v in files.items()},
                "source_revision": commit, "bindings": bindings, "nonce": attempt}
        digest = sha(canonical(seed))
        plan = dict(seed, kind="BUSINESS_WIRE_WEB_DEPLOY_PLAN", schema=1,
                    schema_hash=sha(canonical(schema)), release_digest=digest,
                    candidate="/opt/goufayu-ws4-web/releases/business-wire-" + digest,
                    artifact_root=str(output),
                    observed_utc=datetime.now(timezone.utc).isoformat())
        output.mkdir(parents=True)
        path = output / "deploy_plan.json"
        raw = canonical(plan)
        write_new(path, raw)
        registration = record(path)
        print(json.dumps({"ok": True, "phase": "PLAN_READY", "plan_sha256": sha(raw),
                          "plan_path": str(path), "storage_record": registration["record_id"]}))
        return 0
    plan_path = output / "deploy_plan.json"
    raw = plan_path.read_bytes()
    need(args.plan_sha256 == sha(raw), "explicit_plan_digest_required")
    plan = json.loads(raw)
    commit, bindings, files = source_binding(plan["source_revision"])
    need(commit == plan["source_revision"] and bindings == plan["bindings"],
         "operator_or_runtime_source_changed")
    need({k: sha(v) for k, v in files.items()} == plan["overlay"], "runtime_overlay_changed")
    payload = {"phase": args.phase, "attempt": attempt,
               "plan": plan, "plan_sha256": sha(canonical(plan))}
    if args.phase == "prepare":
        payload["files"] = {k: base64.b64encode(v).decode("ascii") for k, v in files.items()}
    result = remote(payload)
    receipt = {"kind": "BUSINESS_WIRE_WEB_" + args.phase.upper() + "_RECEIPT",
               "phase": args.phase, "source_revision": commit,
               "plan_sha256": payload["plan_sha256"], "artifact_root": str(output),
               "observed_utc": datetime.now(timezone.utc).isoformat(), "result": result}
    path = output / (args.phase + "_" + attempt + "_receipt.json")
    write_new(path, canonical(receipt))
    try:
        registration = record(path)
    except Exception:
        print(json.dumps({"ok": False, "phase": args.phase, "receipt_path": str(path),
                          "error": "storage_ledger_registration_failed_receipt_retained",
                          "remote_ok": result.get("ok") is True}))
        return 1
    print(json.dumps({"ok": result.get("ok") is True, "phase": args.phase,
                      "status": result.get("status"), "error": result.get("error"),
                      "receipt_path": str(path), "storage_record": registration["record_id"],
                      "rolled_back": result.get("rolled_back")}))
    return 0 if result.get("ok") is True else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        code = str(error) if isinstance(error, ValueError) and re.fullmatch("[a-z_]{1,100}", str(error)) else "deployment_action_failed"
        print(json.dumps({"ok": False, "error": code, "error_type": type(error).__name__}))
        raise SystemExit(1)
