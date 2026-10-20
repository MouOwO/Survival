"""Run the reviewed test-host operator using pinned SSH and sealed artifacts."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
PACKAGE = ROOT / "tmp/archive_caps_20261020/release_candidate"
ARCHIVE = PACKAGE / "archive_caps_review_ecf55dd6.tar.gz"
OPERATOR = Path(__file__).with_name("deploy_remote.py")
HOST = "root@47.110.238.248"
OPTIONS = ["-F", "none", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes",
           "-o", "UserKnownHostsFile=tools/deploy/goufayu_test_known_hosts",
           "-o", "GlobalKnownHostsFile=none", "-o", "HostKeyAlgorithms=ssh-ed25519",
           "-o", "IdentitiesOnly=yes", "-o", "ConnectTimeout=10", "-i",
           "C:/Users/Administrator/.ssh/goufayu_ecs_ed25519_v2"]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(arguments, *, source=None, timeout=60):
    result = subprocess.run(arguments, input=source.encode() if source else None,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, cwd=ROOT, timeout=timeout,
        creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    if result.returncode:
        # Operator stdout contains fixed error codes only. SSH stderr and
        # connection environments are never echoed into task output.
        for line in result.stdout.decode("utf-8", "replace").splitlines():
            try:
                record = json.loads(line)
                print(json.dumps(record, ensure_ascii=False))
            except ValueError:
                pass
        raise RuntimeError("reviewed_remote_action_failed")
    return result.stdout.decode("utf-8")


def remote(source, timeout=60):
    source = "try:\n" + "".join(" " + line + "\n" for line in source.splitlines()) + '''except Exception as error:
 import json,traceback
 print(json.dumps({'ok':False,'error':'remote_verification_failed','error_type':type(error).__name__,
                   'line':traceback.extract_tb(error.__traceback__)[-1].lineno}))
 raise SystemExit(1)
'''
    return run(["ssh.exe", "-T", *OPTIONS, HOST,
                "/opt/goufayu/payments/current/.venv/bin/python -B -"],
               source=source, timeout=timeout)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("upload", "check", "prepare", "activate", "verify"))
    args = parser.parse_args()
    seal = json.loads(ARCHIVE.with_suffix(ARCHIVE.suffix + ".seal.json").read_bytes())
    assert sha(ARCHIVE) == seal["archive_sha256"]
    assert sha(PACKAGE / "stage/plan.json") == seal["plan_sha256"]
    operator_hash = sha(OPERATOR)
    remote_directory = "/root/goufayu_upload/archive-caps-" + seal["plan_sha256"][:16]
    if args.mode == "upload":
        remote("from pathlib import Path\nimport os\np=Path(" + repr(remote_directory) + ")\n"
               "assert p.parent==Path('/root/goufayu_upload') and not p.is_symlink()\n"
               "p.mkdir(parents=True,exist_ok=True,mode=0o700)\nassert p.stat().st_uid==0\np.chmod(0o700)\n")
        run(["scp.exe", *OPTIONS, str(ARCHIVE), str(OPERATOR), HOST + ":" + remote_directory + "/"], timeout=60)
        source = "EXPECTED=" + repr(seal) + "\nDIRECTORY=" + repr(remote_directory) + "\nOPERATOR_HASH=" + repr(operator_hash) + "\n"
        source += r'''
from pathlib import Path, PurePosixPath
import hashlib,json,tarfile,os
directory=Path(DIRECTORY)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
archive=directory/EXPECTED['archive']
assert sha(archive)==EXPECTED['archive_sha256']
assert sha(directory/'deploy_remote.py')==OPERATOR_HASH
with tarfile.open(archive,'r:gz') as stream:
 members=stream.getmembers()
 assert len(members)==EXPECTED['file_count']
 for member in members:
  name=PurePosixPath(member.name)
  assert member.isfile() and not name.is_absolute() and '..' not in name.parts and name.parts[0]=='stage'
  relative=name.relative_to('stage').as_posix()
  assert relative in EXPECTED['files']
  raw=stream.extractfile(member).read()
  assert hashlib.sha256(raw).hexdigest()==EXPECTED['files'][relative]
  target=directory.joinpath(*name.parts)
  assert not target.is_symlink()
  target.parent.mkdir(parents=True,exist_ok=True,mode=0o700)
  if target.exists():assert target.read_bytes()==raw
  else:
   with target.open('xb') as output:output.write(raw)
  target.chmod(0o600)
assert sha(directory/'stage/plan.json')==EXPECTED['plan_sha256']
print(json.dumps({'ok':True,'phase':'SEALED_STAGE_UPLOADED','files':len(members)}))
'''
        output = remote(source)
    elif args.mode == "verify":
        source = "DIRECTORY=" + repr(remote_directory) + "\nPLAN_HASH=" + repr(seal["plan_sha256"]) + "\n"
        source += r'''
from pathlib import Path
import hashlib,importlib.util,json,sys,time,urllib.request
directory=Path(DIRECTORY);stage=directory/'stage'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert sha(stage/'plan.json')==PLAN_HASH
plan=json.loads((stage/'plan.json').read_bytes());expected=plan['expected'];candidate=plan['candidate']
release=Path('/opt/goufayu/releases/current').resolve(strict=True)
assert release.name==candidate['release_id']
assert sha(release/'release_manifest.json')==candidate['release_manifest_sha256']
for name,digest in candidate['overlay'].items():assert sha(release/name)==digest
sys.path[:0]=[str(release/'backend'),str(Path('/opt/goufayu/payments/current').resolve())]
from archive_backend.bundle import Bundle
from archive_backend.daily_limits import snapshot
from fishing_api.postgres import Parameter,PostgresRpcClient
bundle=Bundle(release/'addon/server/bundles'/candidate['bundle_hash'])
assert json.loads((release/'addon/server/bundles/current.json').read_bytes())['hash']==bundle.hash
now=time.time();day=str(int((now+28800)//86400))
profile={'save':{'archive':{'daily':{day:{'clear_total':20,'cage_total':60,'fragment_01':20}}}},
         'entitlements':{'archive_pass':{'active':True}}}
quotas=snapshot(profile,bundle,now)['by_key']
for key,limit in {'clear':20,'cage':60,'fragment_01':20,'fishing':80,'coins':8000,'endless':50000,'faith':3000}.items():
 assert quotas[key]['limit']==limit
for key in ('clear','cage','fragment_01'):assert quotas[key]['capped']==1
converter=object.__new__(PostgresRpcClient)
for mode in ('pure','standard','rich','cold','scourge'):assert converter._convert(Parameter('p_mode','text','match_mode'),mode)==mode
from deploy import connection
with connection() as db:
 db.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY')
 assert db.execute('SELECT current_database()').fetchone()[0]=='goufayu_test'
 ledger=dict(db.execute('SELECT migration_id,sha256 FROM public._goufayu_migrations'))
 original={item['id']:item['sha256'] for item in expected['ledger']}
 additions={item['id']:item['sha256'] for item in candidate['migrations']}
 assert ledger=={**original,**additions}
 assert db.execute('SELECT count(*) FROM public.archive_config_sets WHERE config_hash IN (%s,%s)',(bundle.hash,expected['bundle_hash'])).fetchone()[0]==2
 assert not db.execute("SELECT has_function_privilege('goufayu_app','public.grant_out_of_match_reward_before_daily_limits(text,uuid,text,integer,numeric)','EXECUTE')").fetchone()[0]
 assert db.execute("SELECT has_function_privilege('goufayu_app','public.checkpoint_online_time(text,text,text,integer,integer,integer,integer,boolean)','EXECUTE')").fetchone()[0]
 db.rollback()
spec=importlib.util.spec_from_file_location('verified_caps_operator',directory/'deploy_remote.py')
operator=importlib.util.module_from_spec(spec);spec.loader.exec_module(operator)
prepared=json.loads((stage/'prepared.json').read_bytes())
assert operator.Operator(stage,PLAN_HASH).payment_pin()==prepared['payment']
backup=json.loads((stage/'backup.json').read_bytes());backup_directory=Path(backup['directory'])
assert sha(backup_directory/'database.dump')==backup['database_sha256']
assert sha(backup_directory/'parent_sources.tar.gz')==backup['source_sha256']
for port in (8765,8766):
 with urllib.request.urlopen('http://127.0.0.1:'+str(port)+'/health',timeout=5) as response:assert json.load(response)['ok'] is True
print(json.dumps({'ok':True,'phase':'POST_DEPLOY_VERIFIED','release':release.name,'bundle':bundle.hash,
 'ledger_entries':len(ledger),'quota_limits':{key:quotas[key]['limit'] for key in ('clear','cage','fragment_01','fishing','coins','endless','faith')},
 'payment_untouched':True,'private_backup_verified':True,'player_profiles_read':0,'player_updates':0}))
'''
        output = remote(source, timeout=90)
    else:
        source = "DIRECTORY=" + repr(remote_directory) + "\nOPERATOR_HASH=" + repr(operator_hash) + "\nPLAN_HASH=" + repr(seal["plan_sha256"]) + "\nMODE=" + repr(args.mode) + "\n"
        source += r'''
from pathlib import Path
import hashlib,runpy,sys
directory=Path(DIRECTORY)
operator=directory/'deploy_remote.py'
assert hashlib.sha256(operator.read_bytes()).hexdigest()==OPERATOR_HASH
assert hashlib.sha256((directory/'stage/plan.json').read_bytes()).hexdigest()==PLAN_HASH
sys.argv=[str(operator),'--stage',str(directory/'stage'),'--plan-sha256',PLAN_HASH,'--mode',MODE]
runpy.run_path(str(operator),run_name='__main__')
'''
        output = remote(source, timeout=300 if args.mode == "activate" else 90)
    print(output.strip())
    result = PACKAGE / ("remote_" + args.mode + ".jsonl")
    result.write_text(output, encoding="utf-8")


if __name__ == "__main__":
    main()
