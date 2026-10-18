"""Read only immutable payment source files and public process/health metadata.

Executed over the existing pinned SSH transport. It never opens payment config,
credentials, database connections, player data, account sessions or gateway APIs.
"""
from pathlib import Path, PurePosixPath
import ast
import base64
import hashlib
import json
import subprocess
import urllib.request

payment = Path('/opt/goufayu/payments/current').resolve(strict=True)
archive = Path('/opt/goufayu/releases/current').resolve(strict=True)
assert payment.parent == Path('/opt/goufayu/payments') and payment.name != 'current', 'unexpected_payment_location'
assert archive.parent == Path('/opt/goufayu/releases') and archive.name != 'current', 'unexpected_archive_location'
raw_manifest = (payment / 'manifest.json').read_bytes()
manifest = json.loads(raw_manifest)
assert isinstance(manifest, dict) and manifest, 'payment_manifest_invalid'
exports = {}
for name, expected in manifest.items():
    relative = PurePosixPath(name)
    assert relative.as_posix() == name and not relative.is_absolute() and '..' not in relative.parts and '\\' not in name and ':' not in name, 'unsafe_release_path'
    allowed = ((relative.parts[0] == 'payment_backend' and relative.suffix in ('.py', '.sql', '.txt'))
        or (relative.parts[0] == 'reference_csv' and relative.suffix == '.csv')
        or (len(relative.parts) == 1 and (name == 'deploy.py' or name.endswith('_release.json') or name.endswith('_RELEASE.md'))))
    assert allowed, 'unexpected_manifest_material'
    path = payment / name
    assert all(not item.is_symlink() for item in [path, *path.parents] if item != payment.parent), 'release_symlink_refused'
    raw = path.read_bytes()
    assert hashlib.sha256(raw).hexdigest() == expected, 'payment_manifest_drift'
    exports[name] = base64.b64encode(raw).decode('ascii')
service = (payment / 'payment_backend/service.py').read_bytes()
tree = ast.parse(service)
scripts = [node.value.value for node in tree.body if isinstance(node, ast.Assign)
           and any(isinstance(target, ast.Name) and target.id == 'JS' for target in node.targets)]
assert len(scripts) == 1, 'hosted_script_constant_missing'
with urllib.request.urlopen('http://127.0.0.1:8766/checkout.js', timeout=10) as response:
    public_script = response.read()
    assert response.status == 200 and public_script == scripts[0].encode(), 'running_script_differs_from_manifest'
health = {}
for name, port in (('payments', 8766), ('archive', 8765)):
    with urllib.request.urlopen('http://127.0.0.1:' + str(port) + '/health', timeout=5) as response:
        body = json.load(response)
        assert response.status == 200 and body.get('ok') is True, 'health_failed'
        health[name] = True
pid = subprocess.run(['systemctl', 'show', 'goufayu-payment.service', '--property=MainPID', '--value'],
                     capture_output=True, text=True, timeout=10, check=True).stdout.strip()
assert pid.isdigit() and int(pid) > 0, 'payment_service_not_running'
print(json.dumps(dict(status='READONLY_CHECKOUT_PREFLIGHT_PASS', payment_release=payment.name,
    payment_manifest_sha256=hashlib.sha256(raw_manifest).hexdigest(),
    service_sha256=hashlib.sha256(service).hexdigest(), public_script_sha256=hashlib.sha256(public_script).hexdigest(),
    archive_release=archive.name, archive_manifest_sha256=hashlib.sha256((archive / 'release_manifest.json').read_bytes()).hexdigest(),
    archive_bundle=json.loads((archive / 'addon/server/bundles/current.json').read_bytes())['hash'],
    payment_pid=int(pid), health=health, candidate_directory_exists=(payment.parent / '20261018-checkout-gcoin-v1').exists(),
    payment_manifest=manifest, export_files=exports, manifest_raw=base64.b64encode(raw_manifest).decode('ascii'),
    database_accessed=False, database_writes=0, orders_created=0, gateway_requests=0, services_restarted=False)))
