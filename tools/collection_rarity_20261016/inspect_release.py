"""Pinned SSH, read-only release metadata for the collection-rarity rollout."""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "output/collection_rarity_20261016"
sys.path.insert(0, str(ROOT / "tools"))
import aliyun_local_config
from aliyun_test_connection import ECS_HOST, verify_known_hosts

def transport(source, timeout=90):
    config = aliyun_local_config.load(ROOT)
    verify_known_hosts(config["known_hosts"])
    arguments = ["ssh.exe", "-T", "-F", "none", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes",
        "-o", 'UserKnownHostsFile="' + config["known_hosts"].as_posix() + '"', "-o", "GlobalKnownHostsFile=none",
        "-o", "HostKeyAlgorithms=ssh-ed25519", "-o", "IdentitiesOnly=yes", "-o", "ConnectTimeout=10",
        "-i", str(config["ssh_key"]), "root@" + ECS_HOST,
        "/opt/goufayu/payments/current/.venv/bin/python -B -"]
    return subprocess.run(arguments, input=source.encode("utf-8"), capture_output=True,
        timeout=timeout, cwd=ROOT, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))

SOURCE = '''from pathlib import Path
import contextlib,hashlib,importlib.util,io,json,urllib.request
def load(name,path):
 spec=importlib.util.spec_from_file_location(name,path)
 obj=importlib.util.module_from_spec(spec)
 spec.loader.exec_module(obj)
 return obj
def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
root=Path('/opt/goufayu/releases/current').resolve()
payment=Path('/opt/goufayu/payments/current').resolve()
manifest=json.loads((root/'release_manifest.json').read_bytes())
assert all((root/name).is_file() and sha(root/name)==digest for name,digest in manifest['files'].items())
pointer=json.loads((root/'addon/server/bundles/current.json').read_bytes())
raw=(root/'addon/server/bundles'/pointer['hash']/'bundle.json').read_bytes()
assert hashlib.sha256(raw).hexdigest()==pointer['hash']
bundle=json.loads(raw)
deploy=load('collection_read_only_payment',payment/'deploy.py')
with deploy.connection() as connection:
 connection.execute('SET TRANSACTION READ ONLY')
 state=connection.execute("SELECT pg_get_functiondef(oid),pg_get_userbyid(proowner),prosecdef,proconfig,proacl::text FROM pg_proc WHERE oid='public.archive_sync_config(text,jsonb)'::regprocedure").fetchone()
 registration=connection.execute('SELECT config_hash FROM public.archive_config_sets ORDER BY config_hash').fetchall()
 connection.rollback()
health={}
for name,port in [('archive',8765),('payment',8766)]:
 with urllib.request.urlopen('http://127.0.0.1:'+str(port)+'/health',timeout=5) as response:
  body=json.load(response)
  assert response.status==200 and body.get('ok') is True
  health[name]=body
with contextlib.redirect_stdout(io.StringIO()):load('collection_read_only_manage',root/'deploy/manage.py').health()
social=bundle['configs']['archive_social_items']['rows']
print(json.dumps({'status':'READ_ONLY_BASELINE_VERIFIED','base':pointer['hash'],'old_release':str(root),'old_manifest':sha(root/'release_manifest.json'),'old_service':sha(root/'backend/archive_backend/service.py'),'old_sync_function':hashlib.sha256(state[0].encode()).hexdigest(),'payment_release':str(payment),'sync_security':{'owner':state[1],'security_definer':state[2],'configuration':state[3],'acl':state[4]},'old_sync_marker_count':state[0].count(' -- Compatibility is part of the immutable config record, not a mutable alias.'),'registered_configs':len(registration),'health':health,'social_counts':{pool:len([r for r in social if r.get('pool_id')==pool]) for pool in ['ex','friend','wife','beast']},'no_writes':True}))
'''

def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    response = transport(SOURCE)
    (OUTPUT / "baseline.stdout.txt").write_bytes(response.stdout)
    (OUTPUT / "baseline.stderr.txt").write_bytes(response.stderr)
    if response.returncode:
        raise RuntimeError("read_only_baseline_failed; diagnostics saved")
    result = json.loads(next(line for line in reversed(response.stdout.decode("utf-8").splitlines()) if line.startswith("{")))
    local = json.loads((ROOT / "server/bundles/current.json").read_bytes())["hash"]
    if local != result["base"]:
        raise RuntimeError("local_and_server_bundle_differ")
    (OUTPUT / "baseline.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", "utf-8")
    print(json.dumps(result, ensure_ascii=False))

if __name__ == "__main__":
    main()
