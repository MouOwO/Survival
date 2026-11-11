"""Explicit read-only export of code/public config and schema, never player rows."""
from __future__ import annotations
import base64
import importlib.util
import json
from pathlib import Path
import subprocess
from .guard import need, sha, relative, write_new

REMOTE = r'''
from pathlib import Path
import subprocess,json,base64,hashlib,os
def working():
 return Path(subprocess.check_output(['systemctl','show','goufayu-ws4.service','--property=WorkingDirectory','--value']).decode().strip())
root=working()
assert str(root).startswith('/opt/goufayu-ws4/releases/') and root.name=='backend'
files={}
for directory in ('fishing_api','archive_backend'):
 for p in (root/directory).rglob('*'):
  if not p.is_file() or '__pycache__' in p.parts or p.suffix not in ('.py','.json','.csv') or p.is_symlink():continue
  files[p.relative_to(root).as_posix()]=p.read_bytes()
bundles=root.parent/'addon/server/bundles'
digest=json.loads((bundles/'current.json').read_bytes())['hash']
assert len(digest)==64 and all(c in '0123456789abcdef' for c in digest)
for p in (bundles/digest).rglob('*'):
 if p.is_file():
  assert not p.is_symlink() and p.suffix in ('.json','.lua','.txt')
  files['bundles/'+p.relative_to(bundles).as_posix()]=p.read_bytes()
files['bundles/current.json']=(bundles/'current.json').read_bytes()
env=dict(os.environ,PGPASSWORD=Path('/etc/goufayu-ws4/admin-password').read_text().strip())
p=subprocess.run(['podman','exec','--env','PGPASSWORD','goufayu-ws4-db','pg_dump',
 '-h','127.0.0.1','-U','postgres','-d','goufayu_ws4','--schema-only','--no-owner'],
 capture_output=True,env=env,timeout=30)
assert p.returncode==0
files['database/schema.sql']=p.stdout
assert working()==root and sum(map(len,files.values()))<32*1024*1024 and len(files)<=200
print(json.dumps({'backend_root':str(root),'files':{k:base64.b64encode(v).decode() for k,v in files.items()},
 'source_hashes':{k:hashlib.sha256(v).hexdigest() for k,v in files.items()}}))
'''


def snapshot(directory):
    from .cli import ROOT
    from datetime import datetime, timezone
    root = Path(directory).resolve()
    need(not root.exists() and not root.is_relative_to(ROOT), 'new_external_snapshot_directory_required')
    transport_path = ROOT / 'tools/archive_caps_20261020/remote_driver.py'
    pinned = subprocess.run(['git', '-C', str(ROOT), 'show', 'HEAD:tools/archive_caps_20261020/remote_driver.py'],
                            capture_output=True, check=True).stdout.replace(b'\r\n', b'\n')
    need(transport_path.read_bytes().replace(b'\r\n', b'\n') == pinned, 'snapshot_transport_source_changed')
    import types
    transport = types.ModuleType('loadtest_pinned_transport'); transport.__file__ = str(transport_path)
    exec(compile(pinned, str(transport_path), 'exec'), transport.__dict__)
    value = json.loads(transport.remote(REMOTE, timeout=90).strip().splitlines()[-1])
    root.mkdir(parents=True, mode=0o700)
    code = root / 'backend_source'; code.mkdir()
    need(set(value['files']) == set(value['source_hashes']), 'snapshot_file_set_mismatch')
    for name, encoded in value['files'].items():
        path = code.joinpath(*relative(name).parts)
        raw = base64.b64decode(encoded, validate=True)
        need(sha(raw) == value['source_hashes'][name], 'snapshot_byte_digest_mismatch')
        path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(raw)
    receipt = root / 'source_snapshot_receipt.json'
    write_new(receipt, {'kind': 'READ_ONLY_LOADTEST_BACKEND_SOURCE_SNAPSHOT',
        'observed_at': datetime.now(timezone.utc).isoformat(), 'artifact_root': str(root),
        'source_root': str(code), 'remote_source': value['backend_root'],
        'source_hashes': value['source_hashes'], 'production_rows_copied': 0,
        'source_files': len(value['files']), 'remote_operator_sha256': sha(REMOTE.encode()),
        'transport_sha256': sha(pinned)})
    return {'status': 'READ_ONLY_SOURCE_SNAPSHOT_READY', 'receipt': str(receipt), 'files': len(value['files'])}
