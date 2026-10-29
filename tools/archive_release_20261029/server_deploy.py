"""Pinned test-host transport. Audit is read-only; writes require a sealed stage.

Credentials remain in existing local/remote private configuration. SSH stderr
and remote exception text are never printed. This tool never updates payments.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import importlib.util
import io
import tarfile
import re

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "output/release_archive_20261029/server_plan"
HOST = "root@47.110.238.248"
REMOTE_PYTHON = "/opt/goufayu/payments/current/.venv/bin/python -B -"
CANDIDATE=OUT/'candidate_v3'
OPERATOR=Path(__file__).with_name('server_remote_operator.py')
canonical=lambda value:json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(',',':'),allow_nan=False).encode()
sha=lambda raw:hashlib.sha256(raw).hexdigest()

AUDIT = r'''
from pathlib import Path
import ast,base64,hashlib,json,subprocess,sys,time,urllib.request
sha=lambda raw:hashlib.sha256(raw).hexdigest()
root=Path('/opt/goufayu/releases/current').resolve(strict=True)
assert root.parent==Path('/opt/goufayu/releases')
pay=Path('/opt/goufayu/payments/current').resolve(strict=True)
assert pay.parent==Path('/opt/goufayu/payments')
raw=(root/'release_manifest.json').read_bytes();manifest=json.loads(raw)
for name,digest in manifest['files'].items():
 p=root/name
 assert p.is_file() and not p.is_symlink() and p.resolve().is_relative_to(root) and sha(p.read_bytes())==digest
pointer=json.loads((root/'addon/server/bundles/current.json').read_bytes())
bundle=(root/'addon/server/bundles'/pointer['hash']/'bundle.json').read_bytes();assert sha(bundle)==pointer['hash']
sources={p.relative_to(root).as_posix():p.read_bytes() for p in (root/'backend').rglob('*.py') if not p.is_symlink() and '__pycache__' not in p.parts}
tree=ast.parse(sources['backend/fishing_api/postgres.py'])
values=[n.value for n in tree.body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='RPC_SIGNATURES' for t in n.targets)]
rpcs=[ast.literal_eval(k) for k in values[0].keys]
sys.path.insert(0,str(pay))
from deploy import connection
with connection() as conn:
 conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY')
 assert conn.info.dbname=='goufayu_test'
 version=conn.execute('SHOW server_version').fetchone()[0]
 ledger=dict(conn.execute('SELECT migration_id,sha256 FROM public._goufayu_migrations ORDER BY 1'))
 functions={s:sha(d.encode()) for s,d in conn.execute("SELECT p.oid::regprocedure::text,pg_get_functiondef(p.oid) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' ORDER BY 1")}
 columns=[r[0] for r in conn.execute("SELECT column_name FROM information_schema.columns WHERE table_schema='public' AND table_name='player_gameplay_stats' ORDER BY ordinal_position")]
 pending=[list(r) for r in conn.execute("SELECT config_hash,command->>'kind',count(*) FROM public.archive_operations WHERE NOT done GROUP BY 1,2 ORDER BY 1,2")]
 app_rpcs=[r[0] for r in conn.execute("SELECT p.oid::regprocedure::text FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND has_function_privilege('goufayu_app',p.oid,'EXECUTE') AND NOT EXISTS(SELECT 1 FROM pg_depend d WHERE d.classid='pg_proc'::regclass AND d.objid=p.oid AND d.deptype='e') ORDER BY 1")]
 configs=dict(conn.execute("SELECT config_hash,encode(sha256(convert_to(config::text,'UTF8')),'hex') FROM public.archive_config_sets ORDER BY 1"))
 activity=dict(zip(('online_lease180s','online5m','online30m'),conn.execute("SELECT count(*) FILTER(WHERE last_checkpoint_at>=clock_timestamp()-interval '180 seconds'),count(*) FILTER(WHERE last_checkpoint_at>=clock_timestamp()-interval '5 minutes'),count(*) FILTER(WHERE last_checkpoint_at>=clock_timestamp()-interval '30 minutes') FROM public.online_time_sessions").fetchone()))
 activity['recent_match_sessions30m']=conn.execute("SELECT count(*) FROM public.match_profile_sessions WHERE created_at>=clock_timestamp()-interval '30 minutes'").fetchone()[0]
 activity['recent_online_receipts5m']=conn.execute("SELECT count(*) FROM public.online_time_idempotency WHERE created_at>=clock_timestamp()-interval '5 minutes'").fetchone()[0]
 cash_names=[dict(sku=r[0],title=r[1],amount_fen=r[2]) for r in conn.execute("SELECT sku,title,amount FROM payments.products WHERE sku='video_p001' OR item_id='special_lottery_ticket' ORDER BY sku")]
 conn.rollback()
services={s:{k:subprocess.check_output(['systemctl','show','--property='+k,'--value',s],text=True).strip() for k in ('MainPID','ActiveState')} for s in ('goufayu-api.service','goufayu-payment.service','goufayu-db.service')}
health={}
for port in (8765,8766):
 with urllib.request.urlopen('http://127.0.0.1:'+str(port)+'/health',timeout=5) as response:health[str(port)]=json.load(response).get('ok') is True
result=dict(ok=True,time_utc=time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),release=root.name,manifest_sha256=sha(raw),manifest=manifest,bundle=pointer['hash'],payment_release=pay.name,payment_manifest_sha256=sha((pay/'manifest.json').read_bytes()),services=services,health=health,postgres_version=version,ledger=ledger,functions=functions,configs=configs,backend_source_hashes={name:sha(value) for name,value in sources.items()},rpc_names=rpcs,app_rpcs=app_rpcs,gameplay_stat_columns=columns,pending_by_hash_and_kind=pending,activity=activity,cash_ticket_titles=cash_names,source_files={name:base64.b64encode(value).decode() for name,value in sources.items()},bundle_json=base64.b64encode(bundle).decode(),profile_rows_read=0,remote_mutations=0)
print(json.dumps(result))
'''


def options():
    sys.path.insert(0, str(ROOT / "tools"))
    import aliyun_local_config
    from aliyun_test_connection import verify_known_hosts
    settings = aliyun_local_config.load(ROOT)
    hosts = ROOT / "tools/deploy/goufayu_test_known_hosts"
    verify_known_hosts(hosts)
    if not settings["ssh_key"].is_file():
        raise RuntimeError("ssh_identity_not_readable")
    return ["-F", "none", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes",
            "-o", "UserKnownHostsFile=tools/deploy/goufayu_test_known_hosts", "-o", "GlobalKnownHostsFile=none",
            "-o", "HostKeyAlgorithms=ssh-ed25519", "-o", "IdentitiesOnly=yes",
            "-o", "PreferredAuthentications=publickey", "-o", "PasswordAuthentication=no",
            "-o", "KbdInteractiveAuthentication=no", "-o", "ConnectTimeout=10",
            "-i", str(settings["ssh_key"])]


def remote(source, timeout=90):
    wrapped = "try:\n" + "".join(" " + line + "\n" for line in source.splitlines())
    wrapped += "except Exception as error:\n import json,re\n code=str(error) if type(error) is RuntimeError else ''\n code=code if re.fullmatch(r'[a-z0-9_]{1,100}',code) else 'remote_operator_failed'\n print(json.dumps(dict(ok=False,error=code,error_type=type(error).__name__)))\n raise SystemExit(1)\n"
    result = subprocess.run(["ssh.exe", "-T", *options(), HOST, REMOTE_PYTHON],
        input=wrapped.encode(), capture_output=True, cwd=ROOT, timeout=timeout,
        creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    records = []
    for line in result.stdout.decode("utf-8", "replace").splitlines():
        try:
            value = json.loads(line)
            if isinstance(value, dict): records.append(value)
        except ValueError:
            pass
    if result.returncode or not records or records[-1].get("ok") is not True:
        code = records[-1].get("error", "ssh_action_failed") if records else "ssh_action_failed"
        raise RuntimeError(code if isinstance(code,str) and re.fullmatch(r'[a-z0-9_]{1,100}',code) else "remote_action_failed")
    return records[-1]


def audit():
    result = remote(AUDIT)
    OUT.mkdir(parents=True, exist_ok=True)
    encoded = result.pop("source_files")
    raw_bundle = base64.b64decode(result.pop("bundle_json"), validate=True)
    if hashlib.sha256(raw_bundle).hexdigest() != result["bundle"]:
        raise RuntimeError("baseline_bundle_hash_invalid")
    for name, value in encoded.items():
        relative = Path(name)
        if relative.is_absolute() or ".." in relative.parts or not name.startswith("backend/"):
            raise RuntimeError("baseline_source_path_invalid")
        raw = base64.b64decode(value, validate=True)
        if hashlib.sha256(raw).hexdigest() != result["backend_source_hashes"][name]:
            raise RuntimeError("baseline_source_hash_invalid")
        target = OUT / "baseline" / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(raw)
    (OUT / "parent_bundle.json").write_bytes(raw_bundle)
    (OUT / "live_audit.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return {key: result[key] for key in ("ok", "time_utc", "release", "manifest_sha256", "bundle",
        "payment_release", "services", "health", "postgres_version", "pending_by_hash_and_kind", "activity", "cash_ticket_titles", "remote_mutations")}

def seal():
    plan=json.loads((CANDIDATE/'plan.json').read_bytes())
    files={'plan.json':(CANDIDATE/'plan.json').read_bytes(),'server_remote_operator.py':OPERATOR.read_bytes()}
    for folder in ('overlay','safe_overlay'):
        for name,digest in plan[folder].items():
            raw=(CANDIDATE/folder/name).read_bytes()
            if sha(raw)!=digest:raise RuntimeError('candidate_payload_changed')
            files[folder+'/'+name]=raw
    stream=io.BytesIO()
    with tarfile.open(fileobj=stream,mode='w:gz') as archive:
        for name,raw in sorted(files.items()):
            entry=tarfile.TarInfo(name);entry.size=len(raw);entry.mode=0o600;entry.mtime=0
            archive.addfile(entry,io.BytesIO(raw))
    record=dict(files={name:sha(raw) for name,raw in files.items()},plan_sha256=sha(files['plan.json']))
    record['stage']='/root/goufayu_upload/archive-20261029-'+sha(canonical(record))[:16]
    record['archive_sha256']=sha(stream.getvalue())
    (CANDIDATE/'release.tar.gz').write_bytes(stream.getvalue());(CANDIDATE/'seal.json').write_bytes(canonical(record))
    return dict(ok=True,phase='SEALED_NOT_UPLOADED',release=plan['new_release'],bundle=plan['bundle'],stage=record['stage'],files=len(files))

def source_for(mode,record):
    source='STAGE='+repr(record['stage'])+'\nMODE='+repr(mode)+'\nEXPECTED='+repr(record)+'\n'
    if mode=='prepare':
        raw=(CANDIDATE/'release.tar.gz').read_bytes()
        if sha(raw)!=record['archive_sha256']:raise RuntimeError('sealed_archive_changed')
        source+='PAYLOAD='+repr(base64.b64encode(raw).decode())+'\n'
        source+=r'''
from pathlib import Path,PurePosixPath
import base64,hashlib,io,tarfile
root=Path(STAGE)
assert root.parent==Path('/root/goufayu_upload') and not root.is_symlink()
root.mkdir(mode=0o700,parents=True,exist_ok=True)
raw=base64.b64decode(PAYLOAD,validate=True);assert hashlib.sha256(raw).hexdigest()==EXPECTED['archive_sha256']
with tarfile.open(fileobj=io.BytesIO(raw),mode='r:gz') as archive:
 members=archive.getmembers();assert len(members)==len(EXPECTED['files'])
 for entry in members:
  name=PurePosixPath(entry.name)
  assert entry.isfile() and not name.is_absolute() and '..' not in name.parts and entry.name in EXPECTED['files']
  value=archive.extractfile(entry).read();assert hashlib.sha256(value).hexdigest()==EXPECTED['files'][entry.name]
  target=root/entry.name;assert not target.is_symlink();target.parent.mkdir(mode=0o700,parents=True,exist_ok=True)
  if target.exists():assert target.read_bytes()==value
  else:
   with target.open('xb') as output:output.write(value)
  target.chmod(0o600)
'''
    source+=r'''
from pathlib import Path
import hashlib,importlib.util,json
root=Path(STAGE)
for name,digest in EXPECTED['files'].items():
 p=root/name
 assert not p.is_symlink() and hashlib.sha256(p.read_bytes()).hexdigest()==digest
spec=importlib.util.spec_from_file_location('sealed_archive_operator',root/'server_remote_operator.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
print(json.dumps(module.Operator(root).dispatch(MODE)))
'''
    return source

def protected_backup(record,result):
    source='STAGE='+repr(record['stage'])+'\n'+r'''
from pathlib import Path
import base64,hashlib,json
value=json.loads((Path(STAGE)/'private_backup.json').read_bytes());p=Path(value['path'])
assert p.parent==Path('/var/backups/goufayu-payment') and not p.is_symlink() and p.stat().st_size==value['size']
raw=p.read_bytes();assert len(raw)<128*1024*1024 and hashlib.sha256(raw).hexdigest()==value['sha256']
print(json.dumps(dict(ok=True,backup_b64=base64.b64encode(raw).decode())))
'''
    data=remote(source,timeout=90);raw=base64.b64decode(data['backup_b64'],validate=True)
    if sha(raw)!=result['sha256']:raise RuntimeError('downloaded_private_backup_changed')
    # Reuse only the established, pure Windows DPAPI helper; its remote driver
    # and historical deployment plan are never executed or mutated.
    spec=importlib.util.spec_from_file_location('archive_dpapi_helper',ROOT/'tools/onboarding_release_20261025/deploy.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    encrypted=module.dpapi(raw)
    if sha(module.dpapi(encrypted,decrypt=True))!=result['sha256']:raise RuntimeError('encrypted_backup_roundtrip_failed')
    path=OUT/('database-'+result['sha256'][:16]+'.dump.dpapi')
    if path.exists():raise RuntimeError('encrypted_backup_already_exists')
    path.write_bytes(encrypted)
    ack=dict(ok=True,sha256=result['sha256'],encrypted_sha256=sha(encrypted),encrypted_verified=True,encrypted_size=len(encrypted))
    (OUT/'protected_backup.json').write_bytes(canonical(ack))
    source='STAGE='+repr(record['stage'])+'\nACK='+repr(ack)+'\n'+r'''
from pathlib import Path
import json
root=Path(STAGE);saved=json.loads((root/'private_backup.json').read_bytes())
assert saved['sha256']==ACK['sha256'] and ACK['encrypted_verified'] is True
p=root/'offsite_ack.json';assert not p.is_symlink();p.write_text(json.dumps(ACK,sort_keys=True,separators=(',',':')));p.chmod(0o600)
print(json.dumps(dict(ok=True,phase='ENCRYPTED_OFFSITE_BACKUP_VERIFIED')))
'''
    return remote(source)

def execute(mode):
    record=json.loads((CANDIDATE/'seal.json').read_bytes())
    if sha(OPERATOR.read_bytes())!=record['files']['server_remote_operator.py']:raise RuntimeError('sealed_operator_changed')
    try:
        value=remote(source_for(mode,record),timeout=300 if mode in ('validate-clone','activate','rollback-safe') else 150)
        (CANDIDATE/('remote_'+mode+'.json')).write_bytes(canonical(value))
        if mode=='backup':value['encrypted_backup']=protected_backup(record,value)
        return value
    except Exception:
        if mode=='backup':
            # A failed encrypted transfer cannot strand a functioning parent.
            remote(source_for('resume',record),timeout=90)
        raise

def receipts():
    target=json.loads((CANDIDATE/'plan.json').read_bytes())['bundle']
    source='TARGET='+repr(target)+'\n'+r'''
from pathlib import Path
import json,sys
root=Path('/opt/goufayu/releases/current').resolve(strict=True)
pay=Path('/opt/goufayu/payments/current').resolve(strict=True);sys.path.insert(0,str(pay))
from deploy import connection
with connection() as conn:
 conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY')
 assert conn.info.dbname=='goufayu_test'
 rows=[dict(challenge_id=r[0],receipts=r[1],durable_success=r[2],accepted_units=str(r[3]),skipped=r[4],pending=r[5]) for r in conn.execute("SELECT command->>'challenge_id',count(*),count(*) FILTER(WHERE done AND error IS NULL AND response IS NOT NULL),coalesce(sum(CASE WHEN done AND error IS NULL AND jsonb_typeof(response->'awarded')='number' THEN (response->>'awarded')::numeric ELSE 0 END),0),count(*) FILTER(WHERE done AND error IS NULL AND response ? 'skipped_reason'),count(*) FILTER(WHERE NOT done) FROM public.archive_operations WHERE config_hash=%s AND command->>'kind'='challenge' GROUP BY 1 ORDER BY 1",(TARGET,))]
 conn.rollback()
active=json.loads((root/'addon/server/bundles/current.json').read_bytes())['hash']
print(json.dumps(dict(ok=True,phase='READ_ONLY_DURABLE_RECEIPTS',active_bundle=active,target_bundle=TARGET,active_matches_target=active==TARGET,rows=rows,account_rows_output=0,remote_mutations=0,gameplay_kill_verified=False)))
'''
    result=remote(source)
    (OUT/'durable_receipts_readonly.json').write_bytes(canonical(result))
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("audit","receipts","seal","prepare","backup","validate-clone","activate","verify","resume","rollback-safe"))
    parser.add_argument('--candidate',type=Path,default=CANDIDATE,help='Explicit local sealed candidate; historical stages remain selectable.')
    args = parser.parse_args()
    CANDIDATE=args.candidate.resolve()
    try:
        print(json.dumps(audit() if args.mode=='audit' else receipts() if args.mode=='receipts' else seal() if args.mode=='seal' else execute(args.mode), ensure_ascii=False))
    except Exception as error:
        code=str(error) if type(error) is RuntimeError else ''
        print(json.dumps(dict(ok=False, error=code if re.fullmatch(r'[a-z0-9_]{1,100}',code) else "deployment_driver_failed")))
        raise SystemExit(1)
