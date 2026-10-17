"""Transport for the requested monthly-pass fixed price, with pinned host access."""
from pathlib import Path
import argparse
import base64
import contextlib
import hashlib
import importlib.util
import io
import json

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'output/monthly_pass_58_20261017'
spec = importlib.util.spec_from_file_location('monthly_release_transport', ROOT / 'tools/shop_pricing_half_20261017/remote.py')
transport = importlib.util.module_from_spec(spec); spec.loader.exec_module(transport)
transport.OUT = OUT / 'remote'


def main(mode):
    if mode == 'preflight':
        source = (ROOT / 'tools/shop_pricing_half_20261017/preflight.py').read_text(encoding='utf-8-sig')
        source = source.replace("functions = {}", "functions = {}\narchive_functions = {}")
        anchor = "    products = [r[0] for r in conn.execute"
        insert = "    definition = conn.execute(\"SELECT pg_get_functiondef('public.archive_sync_config(text,jsonb)'::regprocedure)\").fetchone()[0]\n    archive_functions['public.archive_sync_config(text,jsonb)'] = dict(definition=definition, sha256=hashlib.sha256(definition.encode()).hexdigest())\n"
        assert source.count(anchor) == 1
        source = source.replace(anchor, insert + anchor)
        source = source.replace('functions=functions, products=products,', 'functions=functions, archive_functions=archive_functions, products=products,')
        with contextlib.redirect_stdout(io.StringIO()):
            report=transport.execute(source, 'preflight', timeout=90)
        print(json.dumps({k:v for k,v in report['records'][0].items() if k in ('status','payment_release','archive_release','archive_bundle','catalog_hash','health','database_writes')},ensure_ascii=False))
        return report
    plan = json.loads((OUT / 'plan.json').read_bytes())
    raw = (OUT / 'release.tar.gz').read_bytes()
    assert hashlib.sha256(raw).hexdigest() == plan['tar_sha256'], 'frozen_monthly_tar_changed'
    stage = '/tmp/survival-monthly-58-20261017-' + plan['tar_sha256'][:12]
    source = 'STAGE=' + repr(stage) + '\nMODE=' + repr(mode) + '\n'
    if mode == 'prepare':
        source += 'PAYLOAD=' + repr(base64.b64encode(raw).decode()) + '\nEXPECTED_TAR_SHA=' + repr(plan['tar_sha256']) + '\n'
        source += '''from pathlib import Path
import base64,hashlib,io,tarfile
directory=Path(STAGE);assert not directory.is_symlink(),'stage_symlink'
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
  dest.parent.mkdir(mode=0o700,parents=True,exist_ok=True);content=archive.extractfile(item).read()
  if dest.exists():assert dest.read_bytes()==content,'existing_payload_changed'
  else:dest.write_bytes(content)
  dest.chmod(0o600)
'''
    source += Path(__file__).with_name('verify.py' if mode == 'verify' else 'remote_operator.py').read_text(encoding='utf-8-sig')
    return transport.execute(source, mode, timeout=300)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('mode', choices=('preflight', 'prepare', 'validate', 'activate', 'verify'))
    main(parser.parse_args().mode)
