"""Package only reviewed payment sources, never keys or local configuration."""
import hashlib
import argparse
import json
from pathlib import Path
import shutil
import tarfile

ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument('--release-id',default='20260928-payment01')
NAME=parser.parse_args().release_id
import re
if not re.fullmatch(r'[0-9]{8}-payment[0-9]{2}',NAME):raise SystemExit('invalid_release_id')
target=ROOT/'output/payment_release'/NAME
if target.exists():raise SystemExit('release_already_exists')
target.mkdir(parents=True)
source=ROOT/'server/payment_backend'
for path in source.iterdir():
    if path.is_file() and path.suffix in ('.py','.sql','.txt'):
        destination=target/('deploy.py' if path.name=='deploy.py' else 'payment_backend/'+path.name)
        destination.parent.mkdir(exist_ok=True)
        destination.write_bytes(path.read_bytes().replace(b'\r\n',b'\n'))
manifest={p.relative_to(target).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in target.rglob('*') if p.is_file()}
(target/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
archive=target.with_suffix('.tar.gz')
with tarfile.open(archive,'x:gz') as tar:
    def safe(info):
        info.uid=info.gid=0;info.uname=info.gname='root';info.mode=0o755 if info.isdir() else 0o644
        return info
    tar.add(target,arcname=NAME,filter=safe)
print(json.dumps({'archive':str(archive),'sha256':hashlib.sha256(archive.read_bytes()).hexdigest(),'files':len(manifest)}))
