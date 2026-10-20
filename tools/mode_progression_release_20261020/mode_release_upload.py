"""Explicit immutable upload phase; evaluated only by the checked driver."""
from pathlib import Path, PurePosixPath
import base64
import hashlib
import io
import json
import os
import tarfile

assert MODE=='upload', 'upload_mode_required'
directory=Path(STAGE)
assert str(directory).startswith('/tmp/survival-mode-release-20261020-') and directory.parent==Path('/tmp'), 'stage_path_refused'
assert not directory.is_symlink(), 'stage_symlink'
raw=base64.b64decode(PAYLOAD,validate=True)
assert hashlib.sha256(raw).hexdigest()==EXPECTED, 'upload_digest_changed'
files={}
with tarfile.open(fileobj=io.BytesIO(raw),mode='r:gz') as stream:
    members=stream.getmembers()
    assert sum(m.size for m in members)<128*1024*1024, 'expanded_payload_too_large'
    for member in members:
        name=PurePosixPath(member.name)
        assert member.isfile() and member.name not in files and name.parts and not name.is_absolute() and '..' not in name.parts \
            and '\\' not in member.name and ':' not in member.name and '\x00' not in member.name and name.as_posix()==member.name, 'unsafe_upload_member'
        files[member.name]=stream.extractfile(member).read()
plan=json.loads(files['plan.json'])
assert {n:hashlib.sha256(b).hexdigest() for n,b in files.items() if n!='plan.json'}==plan['files'], 'upload_manifest_changed'
directory.mkdir(mode=0o700,exist_ok=True)
directory.chmod(0o700)
for name,body in files.items():
    target=directory/name
    for parent in (target,*target.parents):
        if parent==directory.parent:
            break
        assert not parent.is_symlink(), 'upload_parent_symlink'
    target.parent.mkdir(mode=0o700,parents=True,exist_ok=True)
    if target.exists():
        assert target.is_file() and target.read_bytes()==body, 'immutable_stage_changed'
    else:
        with target.open('xb') as stream:
            target.chmod(0o600);stream.write(body);stream.flush();os.fsync(stream.fileno())
print(json.dumps(dict(status='MODE_RELEASE_UPLOADED_NOT_DEPLOYED',bundle=plan['bundle'],files=len(files),database_writes=0,pointer_changes=0)))
