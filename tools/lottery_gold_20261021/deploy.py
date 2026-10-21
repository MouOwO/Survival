"""Publish the sealed, display-only ticket rename and cultivation currency rule.

The pinned test-host transport never exports tokens or connects to a gateway.
Modes are sequential: seal, prepare, validate, activate, verify. Rollback restores
the preserved archive release without deleting configs, accounts, or receipts.
"""
from pathlib import Path
import argparse
import base64
import hashlib
import importlib.util
import io
import json
import tarfile

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'tmp/tooltip_ticket_20261021/currency_candidate'
STAGE = '/root/goufayu_upload/lottery-gold-20261021-bbaf4162a941'
OPERATOR = Path(__file__).with_name('remote_operator.py')
sha = lambda raw: hashlib.sha256(raw).hexdigest()
canonical = lambda value: json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':'), allow_nan=False).encode()
spec = importlib.util.spec_from_file_location('pinned_transport', ROOT / 'tools/archive_caps_20261020/remote_driver.py')
transport = importlib.util.module_from_spec(spec)
spec.loader.exec_module(transport)


def seal():
    baseline = json.loads((OUT / 'online_baseline.json').read_bytes())
    report = json.loads((OUT / 'report_final.json').read_bytes())
    bundle = Path(report['candidate_directory']) / 'bundle.json'
    raw = bundle.read_bytes()
    digest = sha(raw)
    assert digest == report['candidate_hash'] == 'bbaf4162a941449082f4c5ddcb6d02b056db54a656e08e681d4cae4adbdccf6d'
    data = json.loads(raw)
    product_records = [json.loads(line) for line in (OUT / 'payment_ticket_baseline.jsonl').read_text(encoding='utf-8').splitlines() if line]
    product = next(row for record in product_records for row in record.get('products', []) if row['sku'] == 'video_p001')
    assert product['title'] == '红色抽奖券' and product['amount'] == 600
    relative = 'addon/server/bundles/' + digest + '/'
    overlay = {relative + 'bundle.json': raw,
               **{relative + name: source.encode() for name, source in data['sources'].items()},
               'addon/server/bundles/current.json': canonical(dict(hash=digest, protocol=1))}
    plan = {key: baseline[key] for key in ('archive_release', 'archive_bundle', 'archive_manifest_sha256',
        'payment_release', 'payment_manifest_sha256', 'payment_pid', 'archive_sync_sha256', 'catalog_hash')}
    plan.update(bundle=digest, new_release='20261021-lottery-gold-' + digest[:12], payment_product=product,
        new_catalog_hash=sha(canonical(dict(parent=baseline['catalog_hash'], publication='lottery-gold-20261021',
            sku='video_p001', title='金色抽奖券'))),
        csv_files=['data/csv/抽奖系统/lottery_pool_definitions.csv', 'data/csv/抽奖系统/lottery_currency_definitions.csv',
                   'data/csv/商城兑换系统/commerce_products.csv', 'data/csv/商城兑换系统/commerce_import_status.csv'],
        overlay={name: sha(content) for name, content in overlay.items()})
    files = {'plan.json': canonical(plan), 'bundle.json': raw, 'remote_operator.py': OPERATOR.read_bytes()}
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode='w:gz') as archive:
        for name, content in files.items():
            item = tarfile.TarInfo(name)
            item.size = len(content)
            item.mode = 0o600
            item.mtime = 0
            archive.addfile(item, io.BytesIO(content))
    frozen = buffer.getvalue()
    (OUT / 'release.tar.gz').write_bytes(frozen)
    seal = dict(archive_sha256=sha(frozen), files={name: sha(content) for name, content in files.items()},
                plan_sha256=sha(files['plan.json']), stage=STAGE)
    (OUT / 'seal.json').write_text(json.dumps(seal, indent=2) + '\n', encoding='utf-8')
    (OUT / 'plan.json').write_bytes(files['plan.json'])
    print(json.dumps(dict(ok=True, phase='SEALED', bundle=digest, release=plan['new_release'],
                         archive_sha256=seal['archive_sha256'], payload_files=len(files))))


def execute(mode):
    seal = json.loads((OUT / 'seal.json').read_bytes())
    assert sha(OPERATOR.read_bytes()) == seal['files']['remote_operator.py'], 'sealed_operator_changed'
    source = 'STAGE=' + repr(STAGE) + '\nMODE=' + repr(mode) + '\nEXPECTED=' + repr(seal) + '\n'
    if mode == 'prepare':
        raw = (OUT / 'release.tar.gz').read_bytes()
        assert sha(raw) == seal['archive_sha256'], 'sealed_archive_changed'
        source += 'PAYLOAD=' + repr(base64.b64encode(raw).decode()) + '\n'
        source += r'''
from pathlib import Path,PurePosixPath
import base64,hashlib,io,tarfile
directory=Path(STAGE)
assert directory.parent==Path('/root/goufayu_upload') and not directory.is_symlink()
directory.mkdir(parents=True,exist_ok=True,mode=0o700);directory.chmod(0o700)
assert directory.stat().st_uid==0
raw=base64.b64decode(PAYLOAD,validate=True)
assert hashlib.sha256(raw).hexdigest()==EXPECTED['archive_sha256']
with tarfile.open(fileobj=io.BytesIO(raw),mode='r:gz') as archive:
 members=archive.getmembers()
 assert len(members)==len(EXPECTED['files'])
 for item in members:
  name=PurePosixPath(item.name)
  assert item.isfile() and name.as_posix() in EXPECTED['files'] and not name.is_absolute() and '..' not in name.parts
  target=directory/item.name;assert not target.is_symlink()
  content=archive.extractfile(item).read();assert hashlib.sha256(content).hexdigest()==EXPECTED['files'][item.name]
  if target.exists():assert target.read_bytes()==content
  else:target.write_bytes(content)
  target.chmod(0o600)
'''
    source += r'''
from pathlib import Path
import hashlib
directory=Path(STAGE)
for name,digest in EXPECTED['files'].items():
 target=directory/name
 assert not target.is_symlink() and hashlib.sha256(target.read_bytes()).hexdigest()==digest
exec(compile((directory/'remote_operator.py').read_bytes(),str(directory/'remote_operator.py'),'exec'))
'''
    output = transport.remote(source, timeout=110 if mode == 'activate' else 90)
    (OUT / ('remote_' + mode + '.jsonl')).write_text(output, encoding='utf-8')
    print(output.strip())


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=('seal', 'prepare', 'validate', 'activate', 'verify', 'rollback'))
    mode = parser.parse_args().mode
    seal() if mode == 'seal' else execute(mode)
