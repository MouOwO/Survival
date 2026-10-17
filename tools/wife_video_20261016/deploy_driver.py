"""Explicit SSH transport for the user-requested reviewed wife collection sync.

OpenSSH reads the existing local identity; no credential or player data is read
by this process. Upload is immutable. No operation runs on module import.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import aliyun_local_config
from aliyun_test_connection import ECS_HOST, verify_known_hosts


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def release(candidate):
    if not re.fullmatch(r"[0-9a-f]{64}", candidate):
        raise ValueError("candidate_hash_invalid")
    directory = ROOT / "output/wife_video_20261016/release" / candidate
    plan = json.loads((directory / "release_plan.json").read_bytes())
    if plan["candidate"] != candidate:
        raise ValueError("candidate_plan_mismatch")
    return directory


def stage(candidate):
    return "/tmp/survival-wife-20261016-" + candidate[:12]


def remote(candidate, action, source, timeout=240):
    directory = release(candidate)
    report = directory / "deployment"
    report.mkdir(exist_ok=True)
    config = aliyun_local_config.load(ROOT)
    verify_known_hosts(config["known_hosts"])
    args = ["ssh.exe", "-T", "-F", "none", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes",
        "-o", 'UserKnownHostsFile="' + config["known_hosts"].as_posix() + '"', "-o", "GlobalKnownHostsFile=none",
        "-o", "HostKeyAlgorithms=ssh-ed25519", "-o", "IdentitiesOnly=yes", "-o", "ConnectTimeout=10",
        "-i", str(config["ssh_key"]), "root@" + ECS_HOST,
        "/opt/goufayu/payments/current/.venv/bin/python -B -"]
    result = subprocess.run(args, input=source.encode("utf-8"), capture_output=True,
        timeout=timeout, cwd=ROOT, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    (report / (action + ".stdout.txt")).write_bytes(result.stdout)
    (report / (action + ".stderr.txt")).write_bytes(result.stderr)
    if result.returncode:
        raise RuntimeError("remote_" + action + "_failed; diagnostics saved in " + str(report))
    lines = result.stdout.decode("utf-8").splitlines()
    parsed = json.loads(next(line for line in reversed(lines) if line.startswith("{")))
    (report / (action + ".json")).write_text(json.dumps(parsed, ensure_ascii=False, indent=2) + "\n", "utf-8")
    return parsed


def upload(candidate):
    directory = release(candidate)
    result = json.loads((directory / "build_result.json").read_bytes())
    archive = directory / "wife_patch.tar.gz"
    if sha(archive.read_bytes()) != result["tar_sha256"]:
        raise ValueError("candidate_tar_checksum_changed")
    files = {"wife_patch.tar.gz": archive, "release_plan.json": directory / "release_plan.json",
             "deploy_remote.py": Path(__file__).with_name("deploy_remote.py"),
             "social_source_patch.py": Path(__file__).with_name("social_source_patch.py"),
             "smoke.py": Path(__file__).with_name("smoke.py")}
    records = {name: {"sha256": sha(path.read_bytes()), "data": base64.b64encode(path.read_bytes()).decode("ascii")}
               for name, path in files.items()}
    source = """from pathlib import Path
import base64,hashlib,json,os
os.umask(0o077)
root=Path(STAGE)
if root.is_symlink():raise RuntimeError('stage_symlink_refused')
root.mkdir(mode=0o700,exist_ok=True)
records=RECORDS
for name,entry in records.items():
 raw=base64.b64decode(entry['data'],validate=True)
 if hashlib.sha256(raw).hexdigest()!=entry['sha256']:raise RuntimeError('upload_checksum_mismatch')
 target=root/name
 if target.is_symlink():raise RuntimeError('upload_symlink_refused')
 if target.exists():
  if target.read_bytes()!=raw:raise RuntimeError('immutable_upload_changed:'+name)
 else:
  with target.open('xb') as stream:stream.write(raw)
  target.chmod(0o600)
print(json.dumps({'status':'UPLOADED_NOT_ACTIVATED','stage':str(root),'files':{n:r['sha256'] for n,r in records.items()}}))
""".replace("STAGE", repr(stage(candidate)), 1).replace("RECORDS", repr(records), 1)
    return remote(candidate, "upload", source)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidate", required=True)
    parser.add_argument("action", choices=["upload", "backup", "prepare", "validate", "activate", "verify"])
    args = parser.parse_args()
    if args.action == "upload":
        output = upload(args.candidate)
    else:
        release(args.candidate)
        source = "import runpy,sys\nsys.argv=['deploy_remote.py'," + repr(args.action) + "]\nrunpy.run_path(" + repr(stage(args.candidate) + "/deploy_remote.py") + ",run_name='__main__')\n"
        output = remote(args.candidate, args.action, source, timeout=300)
    print(json.dumps(output, ensure_ascii=False))
