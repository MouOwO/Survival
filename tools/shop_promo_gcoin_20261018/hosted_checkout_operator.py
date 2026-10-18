"""One reviewed, code-only payment release. Transport supplies immutable inputs.

No database connection, payment configuration, player/account session, catalog
mutation, SQL migration or gateway call is used in any phase.
"""
from pathlib import Path, PurePosixPath
from datetime import datetime, timezone
import base64
import hashlib
import io
import json
import os
import secrets
import subprocess
import tarfile
import time
import urllib.request

STAGE = Path(STAGE)
OLD = Path('/opt/goufayu/payments') / PLAN['baseline']
NEW = OLD.parent / PLAN['candidate']
CURRENT = OLD.parent / 'current'
ARCHIVE = Path('/opt/goufayu/releases') / PLAN['archive_release']
ARCHIVE_CURRENT = ARCHIVE.parent / 'current'


def need(value, code):
    if not value:raise RuntimeError(code)


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def report(name, value):
    path = STAGE / (name + '.json')
    need(not path.is_symlink(), 'report_symlink_refused')
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n');path.chmod(0o600)
    return value


def read_report(name):
    return json.loads((STAGE / (name + '.json')).read_bytes())


def run(*args):
    result = subprocess.run(args, capture_output=True, text=True, timeout=120)
    need(result.returncode == 0, 'system_command_failed:' + args[0])
    return result.stdout.strip()


def relative_path(name):
    value = PurePosixPath(name)
    need(value.as_posix() == name and not value.is_absolute() and '..' not in value.parts
         and '\\' not in name and ':' not in name and bool(value.parts), 'unsafe_release_path')
    return value


def verify_files(root, filename, expected_sha, nested=False):
    raw = (root / filename).read_bytes()
    need(sha(raw) == expected_sha, 'release_manifest_drift')
    value = json.loads(raw);files = value['files'] if nested else value
    for name, digest in files.items():
        relative_path(name);path = root / name
        need(all(not p.is_symlink() for p in [path, *path.parents] if p != root.parent), 'release_file_symlink')
        need(sha(path.read_bytes()) == digest, 'release_source_drift')
    return files


def public_script_sha():
    with urllib.request.urlopen('http://127.0.0.1:8766/checkout.js', timeout=10) as response:
        need(response.status == 200, 'checkout_script_unavailable')
        return sha(response.read())


def health():
    result = {}
    for name, port in (('payments', 8766), ('archive', 8765)):
        with urllib.request.urlopen('http://127.0.0.1:' + str(port) + '/health', timeout=5) as response:
            need(response.status == 200 and json.load(response).get('ok') is True, 'health_failed:' + name)
            result[name] = True
    return result


def pid(service):
    value = run('systemctl', 'show', service, '--property=MainPID', '--value')
    need(value.isdigit() and int(value) > 0, 'service_not_running')
    return int(value)


def archive_state():
    need(ARCHIVE_CURRENT.resolve() == ARCHIVE, 'archive_pointer_drift')
    verify_files(ARCHIVE, 'release_manifest.json', PLAN['archive_manifest_sha256'], True)
    need(json.loads((ARCHIVE / 'addon/server/bundles/current.json').read_bytes())['hash'] == PLAN['archive_bundle'], 'archive_bundle_drift')
    return dict(release=ARCHIVE.name, manifest_sha256=PLAN['archive_manifest_sha256'],
                bundle=PLAN['archive_bundle'], pid=pid('goufayu-api.service'))


def baseline():
    need(CURRENT.resolve() == OLD, 'payment_pointer_drift')
    files = verify_files(OLD, 'manifest.json', PLAN['baseline_manifest_sha256'])
    need(files['payment_backend/service.py'] == PLAN['baseline_service_sha256'], 'baseline_service_drift')
    need(public_script_sha() == BASELINE_JS_SHA, 'baseline_running_script_drift')
    return dict(payment_release=OLD.name, payment_pid=pid('goufayu-payment.service'),
                archive=archive_state(), health=health())


def candidate():
    files = verify_files(NEW, 'manifest.json', PLAN['candidate_manifest_sha256'])
    need(files == CANDIDATE_MANIFEST, 'candidate_manifest_content_drift')
    old_files = verify_files(OLD, 'manifest.json', PLAN['baseline_manifest_sha256'])
    need(set(files) == set(old_files) and [name for name in files if files[name] != old_files[name]] == ['payment_backend/service.py'], 'candidate_scope_changed')
    need(sha((NEW / 'payment_backend/service.py').read_bytes()) == PLAN['candidate_service_sha256'], 'candidate_service_drift')
    need((NEW / '.venv').is_symlink() and (NEW / '.venv').readlink() == OLD / '.venv', 'candidate_environment_drift')


def prepare():
    before = baseline()
    need(not NEW.exists() and not NEW.is_symlink(), 'candidate_destination_exists')
    need(not STAGE.is_symlink(), 'stage_symlink_refused')
    STAGE.mkdir(mode=0o700, exist_ok=True);STAGE.chmod(0o700)
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    saved = Path('/var/backups/goufayu-payment') / ('checkout-gcoin-' + stamp + '-' + PLAN['tarball_sha256'][:8])
    need(not saved.exists() and not saved.is_symlink(), 'backup_destination_exists')
    saved.mkdir(mode=0o700)
    (saved / 'manifest.json').write_bytes((OLD / 'manifest.json').read_bytes())
    (saved / 'service.py').write_bytes((OLD / 'payment_backend/service.py').read_bytes())
    backup = dict(baseline=before, current_target=str(OLD),
        manifest_sha256=sha((saved / 'manifest.json').read_bytes()), service_sha256=sha((saved / 'service.py').read_bytes()))
    need(backup['manifest_sha256'] == PLAN['baseline_manifest_sha256']
         and backup['service_sha256'] == PLAN['baseline_service_sha256'], 'backup_verification_failed')
    (saved / 'backup.json').write_text(json.dumps(backup, ensure_ascii=False, indent=2) + '\n')
    for path in saved.iterdir():path.chmod(0o600)
    raw = base64.b64decode(PAYLOAD, validate=True)
    need(sha(raw) == PLAN['tarball_sha256'], 'uploaded_tarball_changed')
    allowed = {NEW.name + '/' + name for name in [*CANDIDATE_MANIFEST, 'manifest.json']}
    with tarfile.open(fileobj=io.BytesIO(raw), mode='r:') as stream:
        members = stream.getmembers()
        need(len(members) == len(allowed) and {m.name for m in members} == allowed, 'uploaded_file_set_changed')
        for member in members:
            relative_path(member.name)
            need(member.isfile() and not member.issym() and not member.islnk(), 'unsafe_archive_member')
        NEW.mkdir(mode=0o755)
        for member in members:
            name = PurePosixPath(member.name).relative_to(NEW.name).as_posix();path = NEW / name
            path.parent.mkdir(parents=True, exist_ok=True)
            with stream.extractfile(member) as source, path.open('xb') as output:output.write(source.read())
            path.chmod(0o644)
    need((OLD / '.venv/bin/python').is_file(), 'baseline_environment_missing')
    (NEW / '.venv').symlink_to(OLD / '.venv', target_is_directory=True)
    candidate()
    need(baseline() == before, 'baseline_changed_during_preparation')
    return report('prepared', dict(status='PREPARED_NOT_ACTIVATED', baseline=before,
        backup=str(saved), candidate=NEW.name, candidate_manifest_sha256=PLAN['candidate_manifest_sha256'],
        changed_files=['payment_backend/service.py'], other_files_unchanged=75,
        database_accessed=False, services_restarted=False))


def switch(expected, target):
    need(CURRENT.resolve() == expected, 'payment_pointer_changed_by_another_operator')
    temporary = CURRENT.with_name('current.checkout-gcoin.' + secrets.token_hex(8))
    temporary.symlink_to(target, target_is_directory=True);os.replace(temporary, CURRENT)


def verified(new=True):
    need(CURRENT.resolve() == (NEW if new else OLD), 'payment_pointer_verify_failed')
    expected = CANDIDATE_JS_SHA if new else BASELINE_JS_SHA
    last = None
    for attempt in range(30):
        try:
            healthy = health();need(public_script_sha() == expected, 'running_checkout_script_mismatch')
            return dict(health=healthy, public_script_sha256=expected, payment_pid=pid('goufayu-payment.service'))
        except Exception as error:
            last = error;time.sleep(.5)
    raise last


def rollback():
    prepared = read_report('prepared')
    need(CURRENT.resolve() == NEW, 'rollback_refused_pointer_not_our_candidate')
    verify_files(OLD, 'manifest.json', PLAN['baseline_manifest_sha256'])
    need(archive_state() == prepared['baseline']['archive'], 'rollback_archive_drift')
    switch(NEW, OLD);run('systemctl', 'restart', 'goufayu-payment.service')
    checked = verified(False)
    need(archive_state() == prepared['baseline']['archive'], 'rollback_archive_changed')
    return report('rolled_back', dict(status='ROLLED_BACK_CODE_ONLY', restored_payment=OLD.name,
        **checked, archive_unchanged=True, database_accessed=False))


def activate():
    prepared = read_report('prepared')
    need(prepared['status'] == 'PREPARED_NOT_ACTIVATED', 'verified_prepare_required')
    candidate()
    need(baseline() == prepared['baseline'], 'baseline_changed_after_review')
    try:
        switch(OLD, NEW)
        run('systemctl', 'restart', 'goufayu-payment.service')
        checked = verified(True)
        need(archive_state() == prepared['baseline']['archive'], 'archive_changed_during_payment_restart')
        candidate()
    except Exception:
        if CURRENT.resolve() == NEW:rollback()
        else:report('recovery_refused', dict(status='POINTER_CHANGED_BY_ANOTHER_OPERATOR', database_accessed=False))
        raise
    return report('activated', dict(status='ACTIVATED_CHECKOUT_DISPLAY_ONLY', payment_release=NEW.name,
        candidate_manifest_sha256=PLAN['candidate_manifest_sha256'], service_sha256=PLAN['candidate_service_sha256'],
        backup=prepared['backup'], **checked, archive=prepared['baseline']['archive'], archive_unchanged=True,
        changed_files=['payment_backend/service.py'], database_accessed=False,
        database_writes=0, orders_created=0, gateway_requests=0))


def verify():
    candidate();checked = verified(True);prepared = read_report('prepared')
    need(archive_state() == prepared['baseline']['archive'], 'final_archive_drift')
    return report('verified', dict(status='VERIFIED_CHECKOUT_GCOIN', payment_release=NEW.name,
        manifest_sha256=PLAN['candidate_manifest_sha256'], service_sha256=PLAN['candidate_service_sha256'],
        **checked, archive=prepared['baseline']['archive'], archive_unchanged=True,
        database_accessed=False, orders_created=0, gateway_requests=0))


if MODE == 'prepare':value = prepare()
elif MODE == 'activate':value = activate()
elif MODE == 'verify':value = verify()
elif MODE == 'rollback':value = rollback()
else:raise RuntimeError('unsupported_checkout_release_mode')
print(json.dumps(value, ensure_ascii=False))
