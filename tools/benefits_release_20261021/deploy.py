"""Sealed test-host benefits publication. Default audit is read-only.

Prepare and validate do not activate the release or commit SQL. The operator
offers an explicit safe rollback which keeps new stackable item support.
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
OUT = ROOT / 'tmp/benefits_20261021/release_candidate'
OPERATOR = Path(__file__).with_name('remote_operator.py')
sha = lambda raw: hashlib.sha256(raw).hexdigest()
canonical = lambda value: json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':'), allow_nan=False).encode()
spec = importlib.util.spec_from_file_location('benefits_pinned_transport', ROOT / 'tools/archive_caps_20261020/remote_driver.py')
transport = importlib.util.module_from_spec(spec); spec.loader.exec_module(transport)


def seal():
    baseline = json.loads((OUT.parent / 'online_baseline/baseline.json').read_bytes())
    report = json.loads((OUT / 'report.json').read_bytes())
    audit = json.loads((OUT / 'audit.json').read_bytes())
    overlay = {}
    for name in ('candidate_hash', 'rollback_hash'):
        digest = report[name]
        directory = OUT / 'bundles' / digest
        data = json.loads((directory / 'bundle.json').read_bytes())
        assert sha((directory / 'bundle.json').read_bytes()) == digest
        overlay['addon/server/bundles/' + digest + '/bundle.json'] = (directory / 'bundle.json').read_bytes()
        for relative in data['sources']:
            overlay['addon/server/bundles/' + digest + '/' + relative] = (directory / relative).read_bytes()
    for name in report['changed_python']:
        overlay[name] = (OUT / name).read_bytes()
    for path in (OUT / 'csv').rglob('*.csv'):
        overlay['addon/' + path.relative_to(OUT / 'csv').as_posix()] = path.read_bytes()
    migrations = []
    for name in ('202610210001_archive_benefits.sql', '202610210002_archive_stackable_items.sql'):
        relative = 'database/migrations/target/' + name
        raw = (ROOT / 'server/aliyun/database/target' / name).read_bytes().replace(b'\r\n', b'\n')
        overlay[relative] = raw
        migrations.append(dict(id='target/' + name, path=relative, sha256=sha(raw)))
    for name in ('verify_stackable_constraints.sql', 'verify_benefit_api.sql'):
        path = ROOT / 'tools/benefits_20261021' / name
        if path.is_file(): overlay['validation/' + name] = path.read_bytes()
    probe = ROOT / 'server/tests/archive_benefits_database.sql'
    if probe.is_file(): overlay['validation/archive_benefits_database.sql'] = probe.read_bytes()
    plan = {key: baseline[key] for key in ('archive_release', 'archive_bundle', 'archive_manifest_sha256',
        'payment_release', 'payment_manifest_sha256', 'payment_pid')}
    plan.update(bundle=report['candidate_hash'], rollback_bundle=report['rollback_hash'],
        new_release='20261021-benefits-' + report['candidate_hash'][:12],
        rollback_release='20261021-benefits-safe-' + report['rollback_hash'][:12],
        audit=audit, migrations=migrations, overlay={name: sha(raw) for name, raw in overlay.items()})
    files = {'plan.json': canonical(plan), 'remote_operator.py': OPERATOR.read_bytes(),
             **{'overlay/' + name: raw for name, raw in overlay.items()}}
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode='w:gz') as archive:
        for name, raw in sorted(files.items()):
            item = tarfile.TarInfo(name); item.size = len(raw); item.mode = 0o600; item.mtime = 0
            archive.addfile(item, io.BytesIO(raw))
    raw = buffer.getvalue(); (OUT / 'release.tar.gz').write_bytes(raw)
    stage = '/root/goufayu_upload/benefits-20261021-' + sha(files['plan.json'])[:16]
    seal = dict(archive_sha256=sha(raw), files={name: sha(raw) for name, raw in files.items()},
                plan_sha256=sha(files['plan.json']), stage=stage)
    (OUT / 'plan.json').write_bytes(files['plan.json'])
    (OUT / 'seal.json').write_bytes(canonical(seal))
    print(json.dumps(dict(ok=True, phase='SEALED_NOT_ACTIVATED', bundle=plan['bundle'],
        release=plan['new_release'], rollback_release=plan['rollback_release'], files=len(files))))


def execute(mode):
    if mode == 'audit':
        baseline = json.loads((OUT.parent / 'online_baseline/baseline.json').read_bytes())
        source = 'MODE="audit"\nP=' + repr(baseline) + '\nSTAGE=None\n'
        source += OPERATOR.read_text(encoding='utf-8')
    else:
        seal = json.loads((OUT / 'seal.json').read_bytes())
        assert sha(OPERATOR.read_bytes()) == seal['files']['remote_operator.py'], 'sealed_operator_changed'
        source = 'STAGE=' + repr(seal['stage']) + '\nMODE=' + repr(mode) + '\nEXPECTED=' + repr(seal) + '\n'
        if mode == 'prepare':
            raw = (OUT / 'release.tar.gz').read_bytes(); assert sha(raw) == seal['archive_sha256']
            source += 'PAYLOAD=' + repr(base64.b64encode(raw).decode()) + '\n'
            source += '''
from pathlib import Path,PurePosixPath
import base64,hashlib,io,tarfile
directory=Path(STAGE)
assert directory.parent==Path('/root/goufayu_upload') and not directory.is_symlink()
directory.mkdir(parents=True,exist_ok=True,mode=0o700);directory.chmod(0o700)
raw=base64.b64decode(PAYLOAD,validate=True)
assert hashlib.sha256(raw).hexdigest()==EXPECTED['archive_sha256']
with tarfile.open(fileobj=io.BytesIO(raw),mode='r:gz') as archive:
 members=archive.getmembers();assert len(members)==len(EXPECTED['files'])
 for item in members:
  name=PurePosixPath(item.name)
  assert item.isfile() and not name.is_absolute() and '..' not in name.parts and item.name in EXPECTED['files']
  content=archive.extractfile(item).read();assert hashlib.sha256(content).hexdigest()==EXPECTED['files'][item.name]
  target=directory/item.name;assert not target.is_symlink()
  target.parent.mkdir(parents=True,exist_ok=True,mode=0o700)
  if target.exists():assert target.read_bytes()==content
  else:target.write_bytes(content)
  target.chmod(0o600)
'''
        source += '''
from pathlib import Path
import hashlib
directory=Path(STAGE)
for name,digest in EXPECTED['files'].items():
 target=directory/name;assert not target.is_symlink() and hashlib.sha256(target.read_bytes()).hexdigest()==digest
exec(compile((directory/'remote_operator.py').read_bytes(),str(directory/'remote_operator.py'),'exec'))
'''
    output = transport.remote(source, timeout=180 if mode == 'activate' else 110)
    records = [json.loads(line) for line in output.splitlines() if line.strip()]
    assert records and records[-1].get('ok'), 'remote_operator_failed'
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / ('audit.json' if mode == 'audit' else 'remote_' + mode + '.json')).write_bytes(canonical(records[-1]))
    if mode == 'audit':
        print(json.dumps(dict(ok=True, phase='AUDITED_READ_ONLY', functions=len(records[-1]['functions']),
            ledger_entries=len(records[-1]['ledger']), player_rows_read=0, writes=0)))
    else: print(output.strip())


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=('audit', 'seal', 'prepare', 'validate', 'activate', 'verify', 'rollback-safe'))
    mode = parser.parse_args().mode
    seal() if mode == 'seal' else execute(mode)
