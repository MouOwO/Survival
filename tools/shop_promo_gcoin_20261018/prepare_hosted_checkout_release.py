"""Read-only preflight and local one-file checkout release; never activates it."""
from pathlib import Path, PurePosixPath
import argparse
import ast
import base64
import hashlib
import importlib.util
import io
import json
import sys
import tarfile

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'output/shop_promo_gcoin_20261018/hosted_checkout'
NAME = '20261018-checkout-gcoin-v1'
CHANGES = (
    ('var channel=d.provider==="alipay"?"支付宝":"微信";',
     'var channel=d.provider==="alipay"?"支付宝":"微信",displayTitle=String(d.title||"").replace(/U币/g,"G币");'),
    ('document.getElementById("title").textContent=d.title;',
     'document.getElementById("title").textContent=displayTitle;'),
    ('delivered:"支付成功，"+d.title+', 'delivered:"支付成功，"+displayTitle+'),
)


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def write_immutable(path, raw):
    if path.exists():
        assert not path.is_symlink() and path.read_bytes() == raw, 'candidate_material_already_exists_with_other_bytes'
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(raw)


def preflight():
    spec = importlib.util.spec_from_file_location('checkout_existing_transport', ROOT / 'tools/shop_pricing_half_20261017/remote.py')
    transport = importlib.util.module_from_spec(spec); spec.loader.exec_module(transport)
    sys.path.insert(0, str(ROOT / 'tools'))
    import aliyun_local_config
    from aliyun_test_connection import verify_known_hosts
    config = aliyun_local_config.load(ROOT)
    verify_known_hosts(ROOT / 'tools/deploy/goufayu_test_known_hosts')
    # OpenSSH reads the existing identity; this Python process never opens it.
    key_index = transport.OPTIONS.index('-i') + 1
    transport.OPTIONS[key_index] = str(config['ssh_key'])
    transport.OPTIONS.extend(['-o', 'GlobalKnownHostsFile=none', '-o', 'HostKeyAlgorithms=ssh-ed25519',
        '-o', 'PreferredAuthentications=publickey', '-o', 'PasswordAuthentication=no', '-o', 'KbdInteractiveAuthentication=no'])
    transport.OUT = OUT / 'remote'
    import contextlib
    with contextlib.redirect_stdout(io.StringIO()):
        result = transport.execute(Path(__file__).with_name('hosted_checkout_preflight.py').read_text(encoding='utf-8-sig'), 'preflight', timeout=120)
    record = result['records'][0]
    print(json.dumps({key: value for key, value in record.items() if key not in ('payment_manifest', 'export_files', 'manifest_raw')}, ensure_ascii=False))


def build():
    audit = json.loads((OUT / 'remote/preflight.json').read_bytes())
    assert audit['ssh_exit'] == 0 and len(audit['records']) == 1
    audit = audit['records'][0]
    assert audit['status'] == 'READONLY_CHECKOUT_PREFLIGHT_PASS' and not audit['database_accessed']
    assert not audit['candidate_directory_exists'] and audit['payment_release'] != NAME, 'candidate_name_already_published'
    manifest = audit['payment_manifest']; files = {}
    for name, digest in manifest.items():
        relative = PurePosixPath(name)
        assert relative.as_posix() == name and not relative.is_absolute() and '..' not in relative.parts and '\\' not in name
        raw = base64.b64decode(audit['export_files'][name], validate=True)
        assert sha(raw) == digest, 'export_file_digest_changed'
        write_immutable(OUT / 'baseline' / name, raw)
        files[name] = raw
    manifest_raw = base64.b64decode(audit['manifest_raw'], validate=True)
    assert sha(manifest_raw) == audit['payment_manifest_sha256']
    write_immutable(OUT / 'baseline/manifest.json', manifest_raw)
    name = 'payment_backend/service.py'; before = files[name]; after = before
    for old, new in CHANGES:
        a, b = old.encode(), new.encode()
        assert after.count(a) == 1 and b not in after, 'reviewed_hosted_anchor_changed'
        after = after.replace(a, b, 1)
    before_ast, after_ast = ast.parse(before), ast.parse(after)
    # Only the hosted JS constant may differ. No public(), order or gateway code.
    assignments = lambda tree: {target.id: node for node in tree.body if isinstance(node, ast.Assign)
        for target in node.targets if isinstance(target, ast.Name)}
    assignments(after_ast)['JS'].value = assignments(before_ast)['JS'].value
    assert ast.dump(before_ast, include_attributes=False) == ast.dump(after_ast, include_attributes=False), 'non_display_service_ast_changed'
    files[name] = after
    candidate_manifest = {key: sha(value) for key, value in files.items()}
    assert {key for key in manifest if manifest[key] != candidate_manifest[key]} == {name}
    assert set(candidate_manifest) == set(manifest)
    candidate = OUT / 'release' / NAME
    for key, raw in files.items():
        write_immutable(candidate / key, raw)
    new_manifest = (json.dumps(candidate_manifest, ensure_ascii=False, indent=2) + '\n').encode()
    write_immutable(candidate / 'manifest.json', new_manifest)
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode='w') as archive:
        for key in sorted([*files, 'manifest.json']):
            raw = new_manifest if key == 'manifest.json' else files[key]
            info = tarfile.TarInfo(NAME + '/' + key); info.size = len(raw); info.mode = 0o644; info.mtime = 0
            archive.addfile(info, io.BytesIO(raw))
    tar_path = OUT / 'release' / (NAME + '.tar')
    write_immutable(tar_path, buffer.getvalue())
    plan = dict(status='LOCAL_CANDIDATE_NOT_PUBLISHED', baseline=audit['payment_release'], candidate=NAME,
        baseline_manifest_sha256=audit['payment_manifest_sha256'], candidate_manifest_sha256=sha(new_manifest),
        baseline_service_sha256=sha(before), candidate_service_sha256=sha(after),
        changed_files=[name], unchanged_files=len(manifest)-1, added_files=[], removed_files=[],
        archive_release=audit['archive_release'], archive_manifest_sha256=audit['archive_manifest_sha256'],
        archive_bundle=audit['archive_bundle'], baseline_payment_pid=audit['payment_pid'],
        tarball=tar_path.relative_to(ROOT).as_posix(), tarball_sha256=sha(buffer.getvalue()),
        database_accessed=False, database_writes=0, orders_created=0, gateway_requests=0,
        sql_migrations=[], catalog_republished=False, deployment_executed=False)
    write_immutable(OUT / 'release/plan.json', (json.dumps(plan, ensure_ascii=False, indent=2) + '\n').encode())
    print(json.dumps(plan, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=('preflight', 'build'))
    args = parser.parse_args()
    preflight() if args.mode == 'preflight' else build()
