"""Server-side read-only baseline export. No secrets or player rows leave host."""
from pathlib import Path
import base64
import hashlib
import json
import sys
import urllib.request

payment = Path('/opt/goufayu/payments/current').resolve(strict=True)
archive = Path('/opt/goufayu/releases/current').resolve(strict=True)
manifest = json.loads((payment / 'manifest.json').read_bytes())
archive_manifest = json.loads((archive / 'release_manifest.json').read_bytes())
pointer = json.loads((archive / 'addon/server/bundles/current.json').read_bytes())
export = {}
for name, digest in manifest.items():
    path = Path(name)
    assert not path.is_absolute() and '..' not in path.parts and '\\' not in name, 'unsafe_payment_manifest_path'
    assert path.suffix in ('.py', '.sql', '.csv', '.json', '.md', '.txt'), 'nonpublic_release_file'
    assert not any(token in name.lower() for token in ('.env', '.pem', 'secret', 'password', 'private_key', 'config.json')), 'private_release_file_refused'
    source = payment / name
    assert not source.is_symlink(), 'payment_manifest_symlink'
    raw = source.read_bytes()
    assert hashlib.sha256(raw).hexdigest() == digest, 'payment_manifest_drift'
    export['payment/' + name] = base64.b64encode(raw).decode()
export['payment/manifest.json'] = base64.b64encode((payment / 'manifest.json').read_bytes()).decode()
bundle_dir = archive / 'addon/server/bundles' / pointer['hash']
for source in bundle_dir.rglob('*'):
    if not source.is_file():
        continue
    assert not source.is_symlink(), 'bundle_symlink'
    name = source.relative_to(archive).as_posix()
    export['archive/' + name] = base64.b64encode(source.read_bytes()).decode()
for name in ('release_manifest.json', 'addon/server/bundles/current.json', 'backend/archive_backend/bundle.py',
             'backend/archive_backend/config_compatibility.py', 'backend/archive_backend/commerce_catalog.py'):
    source = archive / name
    if source.is_file():
        export['archive/' + name] = base64.b64encode(source.read_bytes()).decode()
sys.path.insert(0, str(payment))
from deploy import connection
functions = {}
with connection() as conn:
    conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY')
    assert conn.execute('SELECT current_database()').fetchone()[0] == 'goufayu_test', 'database_scope_changed'
    for signature, definition, owner, acl, security in conn.execute("SELECT p.oid::regprocedure::text,pg_get_functiondef(p.oid),pg_get_userbyid(p.proowner),p.proacl::text,p.prosecdef FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='payments' ORDER BY 1"):
        functions[signature] = dict(definition=definition, sha256=hashlib.sha256(definition.encode()).hexdigest(), owner=owner, acl=acl, security_definer=security)
    products = [r[0] for r in conn.execute('SELECT to_jsonb(p) FROM payments.products p ORDER BY sku')]
    catalog_hash = conn.execute('SELECT catalog_hash FROM payments.catalog_state WHERE singleton').fetchone()[0]
    triggers = conn.execute("SELECT tgname,pg_get_triggerdef(oid) FROM pg_trigger WHERE tgrelid='payments.orders'::regclass AND NOT tgisinternal ORDER BY tgname").fetchall()
    conn.rollback()
health = {}
for name, port in (('archive', 8765), ('payments', 8766)):
    with urllib.request.urlopen('http://127.0.0.1:' + str(port) + '/health', timeout=10) as response:
        body = json.load(response)
        assert response.status == 200 and body.get('ok') is True, 'unhealthy_service'
        health[name] = True
print(json.dumps(dict(status='READONLY_PREFLIGHT_PASS', payment_release=payment.name,
                     payment_manifest_sha256=hashlib.sha256((payment / 'manifest.json').read_bytes()).hexdigest(),
                     archive_release=archive.name, archive_manifest_sha256=hashlib.sha256((archive / 'release_manifest.json').read_bytes()).hexdigest(),
                     archive_bundle=pointer['hash'], payment_manifest=manifest, archive_manifest=archive_manifest,
                     functions=functions, products=products, catalog_hash=catalog_hash, triggers=triggers,
                     export_files=export, health=health, database_writes=0, orders_created=0, gateway_requests=0)))
