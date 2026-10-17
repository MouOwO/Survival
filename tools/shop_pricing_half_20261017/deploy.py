"""Transport the exact reviewed overlay; separate prepare, rollback trial, activate."""
from pathlib import Path
import argparse
import base64
import hashlib
import json
from remote import execute

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'output/shop_pricing_half_20261017'


def main(mode):
    plan = json.loads((OUT / 'plan.json').read_bytes())
    raw = (OUT / 'release.tar.gz').read_bytes()
    assert hashlib.sha256(raw).hexdigest() == plan['tar_sha256'], 'release_tar_changed'
    stage = '/tmp/survival-shop-half-20261017-' + plan['tar_sha256'][:12]
    source = 'STAGE=' + repr(stage) + '\nMODE=' + repr(mode) + '\n'
    if mode == 'prepare':
        source += 'PAYLOAD=' + repr(base64.b64encode(raw).decode()) + '\nEXPECTED_TAR_SHA=' + repr(plan['tar_sha256']) + '\n'
        source += '''from pathlib import Path
import base64,hashlib,io,os,tarfile
directory=Path(STAGE)
assert not directory.is_symlink(),'stage_symlink'
directory.mkdir(mode=0o700,exist_ok=True);directory.chmod(0o700)
data=base64.b64decode(PAYLOAD,validate=True)
assert hashlib.sha256(data).hexdigest()==EXPECTED_TAR_SHA,'upload_hash_mismatch'
with tarfile.open(fileobj=io.BytesIO(data),mode='r:gz') as archive:
 seen=set()
 for item in archive.getmembers():
  name=Path(item.name)
  assert item.isfile() and not name.is_absolute() and '..' not in name.parts and item.name not in seen,'unsafe_tar_member'
  seen.add(item.name);dest=directory/name
  assert not dest.is_symlink(),'payload_symlink'
  dest.parent.mkdir(mode=0o700,parents=True,exist_ok=True)
  content=archive.extractfile(item).read()
  if dest.exists():assert dest.read_bytes()==content,'existing_payload_changed'
  else:dest.write_bytes(content)
  dest.chmod(0o600)
'''
    source += Path(__file__).with_name('verify.py' if mode == 'verify' else 'remote_operator.py').read_text(encoding='utf-8')
    execute(source, mode, timeout=300)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('mode', choices=('prepare', 'validate', 'activate', 'verify'))
    main(parser.parse_args().mode)
