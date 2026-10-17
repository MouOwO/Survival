"""Build payment02 strictly from the reviewed payment01 manifest, never workspace catalog."""
import hashlib
import json
from pathlib import Path
import tarfile

ROOT = Path(__file__).resolve().parents[2]
BASELINE = ROOT / 'output/payment_release/20261015-payment01'
TARGET = ROOT / 'output/payment_release/20261015-payment02'
BASELINE_SHA = 'f51785753b60192f6c6d6e2c6fefdf81b82c4dac8fe9af60997af6ae463018d7'
CATALOG_HASH = 'b56e72aaf6b1cd512ada1f5fe460be98a2f871e7d5dc1b7131701fb4654f4cbe'
ARCHIVE_HASH = 'dee53fe2e9fb8d1bc97ba6b822a86896e97e94b6bad84501fad5791920c3ca26'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    raw = (BASELINE / 'manifest.json').read_bytes()
    assert sha(raw) == BASELINE_SHA, 'baseline_manifest_changed'
    baseline = json.loads(raw)
    files = {}
    for name, digest in baseline.items():
        rel = Path(name)
        source = BASELINE / name
        assert not rel.is_absolute() and '..' not in rel.parts and '\\' not in name
        assert not source.is_symlink() and BASELINE.resolve() in source.resolve().parents
        data = source.read_bytes()
        assert sha(data) == digest, 'baseline_source_changed:' + name
        files[name] = data
    for name in ('service.py', 'order_quantity.py', 'upgrade_order_quantity.sql', 'upgrade_order_quantity.py'):
        source = ROOT / 'server/payment_backend' / name
        files['payment_backend/' + name] = source.read_text(encoding='utf-8-sig').replace('\r\n', '\n').encode('utf-8')
    fixture = (ROOT / 'tools/compact_checkout_20261015/test_quantity_database.py').read_text(encoding='utf-8-sig')
    old = "ROOT = Path(__file__).resolve().parents[2]\nMIGRATION = ROOT / 'server/payment_backend/upgrade_order_quantity.sql'"
    new = "MIGRATION = Path(__file__).with_name('upgrade_order_quantity.sql')"
    assert fixture.count(old) == 1, 'fixture_resource_path_changed'
    files['payment_backend/test_order_quantity_database.py'] = fixture.replace(old, new).encode('utf-8')
    scope = dict(baseline_release=BASELINE.name, baseline_manifest_sha256=BASELINE_SHA,
                 catalog_hash=CATALOG_HASH, archive_hash=ARCHIVE_HASH,
                 replacement=['payment_backend/service.py'],
                 additions=['payment_backend/order_quantity.py', 'payment_backend/upgrade_order_quantity.sql',
                   'payment_backend/upgrade_order_quantity.py', 'payment_backend/test_order_quantity_database.py',
                   'order_quantity_release.json', 'ORDER_QUANTITY_RELEASE.md'],
                 catalog_archive_rebuilt=False, fixture_resource_path_only_adapted=True)
    files['order_quantity_release.json'] = (json.dumps(scope, ensure_ascii=False, indent=2) + '\n').encode()
    files['ORDER_QUANTITY_RELEASE.md'] = ('''# Reviewed quantity-only payment release\n\nBaseline: 20261015-payment01. Keep its catalog and archive pointers unchanged.\nOnly the HTTP service is replaced; helper, SQL, operator and rollback fixtures are additive.\nAll other baseline manifest entries are copied byte-for-byte. No credentials are included.\n\nFrom the named payment02 release, with the existing protected deployment identity:\n\n```sh\n/opt/goufayu/payments/20261015-payment01/.venv/bin/python -m payment_backend.upgrade_order_quantity validate /opt/goufayu/payments/20261015-payment01\n/opt/goufayu/payments/20261015-payment01/.venv/bin/python -m payment_backend.upgrade_order_quantity activate /opt/goufayu/payments/20261015-payment01\n```\n\nRun those commands with payment02 as the working directory, using the reviewed baseline\ninterpreter. Activation links that exact existing virtualenv; validation needs no new environment.\nNever invoke deploy.activate or earlier catalog/bundle/monthly upgrade commands.\nThe operator guards both reviewed manifests, the expected current symlink and unchanged\ncatalog/archive hashes. Validation migration and nonce fixtures always roll back. Activation\nbacks up first, installs only this SQL under bounded exclusive locks and restarts only payment.\n\nAfter committed v5 order capability, do not restore payment01 or replay earlier migrations.\nFailure recovery keeps the verified v5-compatible reader. If another operator has changed\ncurrent, recovery refuses to overwrite it and reports incomplete recovery for human review.\nNo old order snapshot, QR, paid reward, VIP claim, player permission or catalog is rewritten.\n\nThe bundled test fixture differs from the workspace fixture only in its SQL resource path.\n''').encode()
    manifest = {name: sha(data) for name, data in sorted(files.items())}
    changed = sorted(name for name in baseline if manifest.get(name) != baseline[name])
    added = sorted(set(manifest) - set(baseline))
    assert changed == scope['replacement'] and added == sorted(scope['additions'])
    # Rebuild only our named candidate files; unknown material is never removed.
    if TARGET.exists():
        known = set(files) | {'manifest.json'}
        actual = {p.relative_to(TARGET).as_posix() for p in TARGET.rglob('*') if p.is_file()}
        assert actual <= known and not any(p.is_symlink() for p in TARGET.rglob('*')), 'candidate_has_unexpected_files'
    for name, data in files.items():
        path = TARGET / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    (TARGET / 'manifest.json').write_text(json.dumps(manifest, indent=2, sort_keys=True) + '\n', encoding='utf-8')
    archive = TARGET.with_suffix('.tar.gz')
    with tarfile.open(archive, 'w:gz') as stream:
        for name in sorted([*files, 'manifest.json']):
            path = TARGET / name
            info = stream.gettarinfo(str(path), arcname=TARGET.name + '/' + name)
            info.uid = info.gid = 0
            info.uname = info.gname = ''
            info.mode = 0o644
            with path.open('rb') as data:
                stream.addfile(info, data)
    report = dict(scope, baseline_file_count=len(baseline), candidate_file_count=len(manifest),
                  changed=changed, added=added, removed=[],
                  baseline_manifest_sha256=sha(raw), manifest_sha256=sha((TARGET/'manifest.json').read_bytes()),
                  tar_sha256=sha(archive.read_bytes()), candidate=str(TARGET), tar=str(archive),
                  source_files={name:manifest[name] for name in changed+added},
                  unchanged_reference_csv=True, unchanged_other_migrations=True)
    evidence = ROOT / 'output/compact_checkout_20261015/quantity_release_manifest.json'
    evidence.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
