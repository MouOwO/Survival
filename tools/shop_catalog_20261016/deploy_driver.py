"""Explicit reviewed shop deployment transport. No network or mutation on import.

The root agent runs individual phases after review. OpenSSH alone reads the
existing identity; this program never prints secrets or sends player commands.
"""
from __future__ import annotations
import argparse, base64, hashlib, json, re, subprocess, sys, tarfile
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[2]
RELEASE = ROOT / "design_refs/shop_catalog_20261016/release"
REPORT = ROOT / "design_refs/shop_catalog_20261016/deployment"
STAGE = "/tmp/survival-shop-catalog-20261016"
HOST = "47.110.238.248"
REMOTE_PYTHON = "/opt/goufayu/payments/current/.venv/bin/python -B -"
ACTIONS = ("check", "upload", "backup", "prepare", "validate", "activate", "verify")


def need(value, reason):
    if not value:
        raise RuntimeError(reason)


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def release(candidate=None):
    path = RELEASE / "release_plan.json"
    data = json.loads(path.read_bytes())
    digest = data["candidate"]
    need(re.fullmatch(r"[0-9a-f]{64}", digest), "candidate_hash_invalid")
    need(candidate is None or candidate == digest, "reviewed_candidate_changed")
    need(data.get("version") == 1 and data.get("kind") == "shop_catalog_points_only", "release_plan_kind_invalid")
    return data


def checked(candidate=None):
    data = release(candidate)
    archive = RELEASE / "overlay.tar.gz"
    need(sha(archive.read_bytes()) == data["tar_sha256"], "reviewed_archive_changed")
    files = {}
    with tarfile.open(archive, "r:gz") as stream:
        for member in stream.getmembers():
            relative = PurePosixPath(member.name)
            need(member.isfile() and member.name not in files and not relative.is_absolute() and ".." not in relative.parts
                and "\\" not in member.name and ":" not in member.name and relative.as_posix() == member.name, "unsafe_payload_archive")
            files[member.name] = sha(stream.extractfile(member).read())
    need(files == data["files"], "reviewed_payload_manifest_changed")
    required = {"bundle/" + data["candidate"] + "/bundle.json", "configuration.json",
        "upgrade_archive_shop_compat.sql", "test_archive_shop_compat.py", "smoke.py"}
    need(required <= set(files), "reviewed_payload_incomplete")
    operator = Path(__file__).with_name("deploy_remote.py")
    return {"status": "LOCAL_ARTIFACTS_VERIFIED", "candidate": data["candidate"],
        "plan_sha256": sha((RELEASE / "release_plan.json").read_bytes()), "operator_sha256": sha(operator.read_bytes()),
        "tar_sha256": data["tar_sha256"], "payload_files": len(files), "remote_executed": False}


def ssh_options():
    sys.path.insert(0, str(ROOT / "tools"))
    import aliyun_local_config
    from aliyun_test_connection import ECS_HOST, verify_known_hosts
    need(ECS_HOST == HOST, "reviewed_host_changed")
    config = aliyun_local_config.load(ROOT)
    known = ROOT / "tools/deploy/goufayu_test_known_hosts"
    verify_known_hosts(known)
    # cwd is ROOT, so the pinned known_hosts option contains no Windows spaces.
    return ["ssh.exe", "-T", "-F", "none", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes",
        "-o", "UserKnownHostsFile=" + known.relative_to(ROOT).as_posix(), "-o", "GlobalKnownHostsFile=none",
        "-o", "HostKeyAlgorithms=ssh-ed25519", "-o", "IdentitiesOnly=yes", "-o", "ConnectTimeout=10",
        "-o", "PreferredAuthentications=publickey", "-o", "PasswordAuthentication=no", "-o", "KbdInteractiveAuthentication=no",
        "-i", str(config["ssh_key"]), "root@" + HOST, REMOTE_PYTHON]


def remote(action, source, timeout=300):
    REPORT.mkdir(parents=True, exist_ok=True)
    result = subprocess.run(ssh_options(), input=source.encode("utf-8"), capture_output=True, timeout=timeout,
        cwd=ROOT, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    (REPORT / (action + ".stdout.txt")).write_bytes(result.stdout)
    (REPORT / (action + ".stderr.txt")).write_bytes(result.stderr)
    parsed = None
    for line in reversed(result.stdout.decode("utf-8", errors="replace").splitlines()):
        if line.startswith("{"):
            try:
                parsed = json.loads(line)
            except ValueError:
                continue
            break
    if parsed is not None:
        (REPORT / (action + ".json")).write_text(json.dumps(parsed, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    need(result.returncode == 0 and parsed is not None and parsed.get("status") != "FAILED", "remote_" + action + "_failed_diagnostics_saved")
    return parsed


def upload(candidate=None):
    review = checked(candidate)
    paths = {"overlay.tar.gz": RELEASE / "overlay.tar.gz", "release_plan.json": RELEASE / "release_plan.json",
        "deploy_remote.py": Path(__file__).with_name("deploy_remote.py")}
    entries = {name: {"sha256": sha(path.read_bytes()), "data": base64.b64encode(path.read_bytes()).decode("ascii")}
        for name, path in paths.items()}
    source = """from pathlib import Path
import base64,hashlib,json,os
os.umask(0o077)
root=Path(STAGE_VALUE)
if root.is_symlink():raise RuntimeError('stage_symlink_refused')
root.mkdir(mode=0o700,exist_ok=True)
if root.stat().st_uid!=0 or root.stat().st_mode&0o077:raise RuntimeError('stage_not_private_root_directory')
records=ENTRIES_VALUE
for name,entry in records.items():
 raw=base64.b64decode(entry['data'],validate=True)
 if hashlib.sha256(raw).hexdigest()!=entry['sha256']:raise RuntimeError('upload_checksum_mismatch')
 target=root/name
 if target.is_symlink():raise RuntimeError('upload_symlink_refused')
 if target.exists():
  if not target.is_file() or target.read_bytes()!=raw:raise RuntimeError('immutable_uploaded_file_changed')
 else:
  with target.open('xb') as stream:stream.write(raw)
  target.chmod(0o600)
print(json.dumps({'status':'UPLOADED_NOT_ACTIVATED','stage':str(root),'files':{n:r['sha256'] for n,r in records.items()}}))
""".replace("STAGE_VALUE", repr(STAGE), 1).replace("ENTRIES_VALUE", repr(entries), 1)
    result = remote("upload", source)
    need(result["files"]["release_plan.json"] == review["plan_sha256"] and result["files"]["deploy_remote.py"] == review["operator_sha256"], "uploaded_review_pins_differ")
    return result


def execute(action, candidate=None):
    need(action in ACTIONS, "unsupported_action")
    if action == "check":
        return checked(candidate)
    if action == "upload":
        return upload(candidate)
    review = checked(candidate)
    args = ["deploy_remote.py", action, "--plan-sha", review["plan_sha256"], "--operator-sha", review["operator_sha256"]]
    source = "import runpy,sys\nsys.dont_write_bytecode=True\nsys.argv=" + repr(args) + "\nrunpy.run_path(" + repr(STAGE + "/deploy_remote.py") + ",run_name='__main__')\n"
    return remote(action, source)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=ACTIONS)
    parser.add_argument("--candidate")
    args = parser.parse_args()
    print(json.dumps(execute(args.action, args.candidate), ensure_ascii=False))


if __name__ == "__main__":
    main()
