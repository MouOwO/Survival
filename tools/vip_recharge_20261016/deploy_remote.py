"""Pinned VIP-only deployment. Payment service, prices and player rows are untouched.

Prepare creates a backup and a new immutable archive release. Activate replaces
one read-only ranking function and restarts only the archive API. On failure it
restores that function and the previous API code, retaining legitimate rewards.
"""
from pathlib import Path, PurePosixPath
import argparse
import contextlib
import fcntl
import hashlib
import importlib.util
import io
import json
import os
import secrets
import shutil
import subprocess
import sys
import tarfile
import time
import urllib.request

STAGE = Path('/tmp/survival-vip-recharge-20261016-v1')
PLAN_PIN = None
OPERATOR_PIN = None


def need(value, reason):
    if not value:
        raise RuntimeError(reason)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def record(name, value=None):
    path = STAGE / (name + '.json')
    if value is None:
        data = json.loads(path.read_bytes())
        need(data['plan_sha'] == PLAN_PIN and data['operator_sha'] == OPERATOR_PIN, 'record_pin_changed')
        return data
    data = dict(value, plan_sha=PLAN_PIN, operator_sha=OPERATOR_PIN)
    temp = path.with_name(path.name + '.' + secrets.token_hex(4))
    temp.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')
    temp.chmod(0o600)
    os.replace(temp, path)
    return data


def plan():
    need(sha(STAGE / 'release_plan.json') == PLAN_PIN and sha(__file__) == OPERATOR_PIN, 'artifact_changed')
    p = json.loads((STAGE / 'release_plan.json').read_bytes())
    need(p['kind'] == 'vip_recharge_progression' and p['version'] == 1, 'plan_scope')
    need(p['old_release'] == '/opt/goufayu/releases/20261016-shop-functional-v2'
         and p['old_payment'] == '/opt/goufayu/payments/20261016-shop-functional-v2'
         and p['target_release'] == '/opt/goufayu/releases/20261016-vip-recharge-v1', 'release_scope')
    need(set(p['files']) == {'backend/archive_backend/service.py', 'backend/archive_backend/endless_leaderboard.py',
         'backend/archive_backend/vip_progression.py', 'ranking.sql', 'rollback_ranking.sql'}, 'overlay_scope')
    return p


def pointers(archive):
    p = plan()
    need(Path('/opt/goufayu/releases/current').resolve() == Path(archive), 'archive_pointer_changed')
    need(Path('/opt/goufayu/payments/current').resolve() == Path(p['old_payment']), 'payment_pointer_changed')


def manifest(root):
    m = json.loads((root / 'release_manifest.json').read_bytes())
    for name, digest in m['files'].items():
        relative = PurePosixPath(name)
        need(not relative.is_absolute() and '..' not in relative.parts and '\\' not in name
             and ':' not in name and relative.as_posix() == name, 'unsafe_manifest_path')
        need(not (root / name).is_symlink() and sha(root / name) == digest, 'release_file_changed:' + name)
    return m


def payment():
    p = plan()
    sys.path.insert(0, p['old_payment'])
    return load('vip_payment_connection', Path(p['old_payment']) / 'deploy.py')


def definition(c):
    return c.execute("SELECT pg_get_functiondef('public.archive_endless_leaderboard()'::regprocedure)").fetchone()[0]


def invariants(c, ranking_sha=None):
    p = plan()
    need(c.execute('SELECT current_database()').fetchone()[0] == 'goufayu_test', 'database_scope')
    for name, expected in [('payments.apply_effects(text,jsonb,boolean)', p['apply_sha']),
                           ('public.archive_sync_config(text,jsonb)', p['sync_sha'])]:
        text = c.execute('SELECT pg_get_functiondef(%s::regprocedure)', (name,)).fetchone()[0]
        need(hashlib.sha256(text.encode()).hexdigest() == expected, 'unrelated_function_changed:' + name)
    need(c.execute('SELECT catalog_hash FROM payments.catalog_state WHERE singleton').fetchone()[0] == p['cash_hash'], 'catalog_changed')
    if ranking_sha:
        need(hashlib.sha256(definition(c).encode()).hexdigest() == ranking_sha, 'ranking_changed')


def health():
    values = {}
    for name, port in [('archive', 8765), ('payment', 8766)]:
        with urllib.request.urlopen('http://127.0.0.1:' + str(port) + '/health', timeout=5) as response:
            value = json.load(response)
            need(response.status == 200 and value.get('ok') is True, 'health_failed:' + name)
            values[name] = {'ok': True, 'service': value.get('service')}
    return values


def prepare():
    p = plan()
    pointers(p['old_release'])
    old = Path(p['old_release'])
    need(sha(old / 'release_manifest.json') == p['old_manifest_sha'], 'online_manifest_changed')
    m = manifest(old)
    need(json.loads((old / 'addon/server/bundles/current.json').read_bytes())['hash'] == p['bundle'], 'bundle_changed')
    health()
    with payment().connection() as c:
        c.execute('SET TRANSACTION READ ONLY')
        invariants(c, p['old_ranking_sha'])
        c.rollback()
    backup = Path('/var/backups/goufayu-vip-recharge') / PLAN_PIN
    need(not backup.exists(), 'backup_exists')
    backup.mkdir(parents=True, mode=0o700)
    with tarfile.open(backup / 'sources.tar.gz', 'x:gz') as tar:
        for name in [*m['files'], 'release_manifest.json']:
            tar.add(old / name, arcname='archive/' + name, recursive=False)
        tar.add(STAGE / 'rollback_ranking.sql', arcname='rollback_ranking.sql', recursive=False)
    capture = io.StringIO()
    with contextlib.redirect_stdout(capture):
        payment().backup()
    backed = json.loads(capture.getvalue().splitlines()[-1])
    dump = Path(backed['local_backup'])
    need(dump.is_file() and dump.stat().st_size > 0 and dump.with_suffix('.sha256').read_text().strip() == sha(dump), 'backup_invalid')
    target = Path(p['target_release'])
    need(not target.exists(), 'target_exists')
    target.mkdir(mode=0o755)
    for name in m['files']:
        dest = target / name
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(old / name, dest)
    (target / '.venv').symlink_to(old / '.venv', target_is_directory=True)
    for name in p['files']:
        if name.startswith('backend/'):
            shutil.copyfile(STAGE / name, target / name)
            (target / name).chmod(0o644)
    changed = {name for name in m['files'] if sha(target / name) != m['files'][name]}
    need(changed == set(p['old_backend']), 'unrelated_code_changed')
    m.update(release=target.name, previous_release=old.name,
             description='Verified recharge VIP privileges and public ranking badges; existing reducers and prices retained')
    for name in p['files']:
        if name.startswith('backend/'):
            m['files'][name] = sha(target / name)
    (target / 'release_manifest.json').write_text(json.dumps(m, ensure_ascii=False, indent=2) + '\n')
    (target / 'release_manifest.json').chmod(0o644)
    manifest(target)
    load('vip_prepare_manage', target / 'deploy/manage.py').validated_release(str(target))
    return record('prepared', {'status': 'PREPARED_NOT_ACTIVE', 'release_manifest_sha': sha(target / 'release_manifest.json'),
        'database_backup': str(dump), 'database_sha': sha(dump), 'source_backup': str(backup / 'sources.tar.gz'),
        'source_sha': sha(backup / 'sources.tar.gz'), 'payment_manifest_sha': sha(Path(p['old_payment']) / 'manifest.json'),
        'changed_existing_files': sorted(changed), 'new_tables': 0, 'player_commands': 0})


def checked_target():
    p = plan()
    data = record('prepared')
    need(sha(data['database_backup']) == data['database_sha'] and sha(data['source_backup']) == data['source_sha'], 'backup_changed')
    need(sha(Path(p['old_payment']) / 'manifest.json') == data['payment_manifest_sha'], 'payment_code_changed')
    target = Path(p['target_release'])
    need(sha(target / 'release_manifest.json') == data['release_manifest_sha'], 'candidate_manifest_changed')
    manifest(target)
    return target


def sql_source():
    source = (STAGE / 'ranking.sql').read_text()
    need(source.count('BEGIN;') == 1 and source.count('COMMIT;') == 1, 'transaction_markers_changed')
    return source.replace('BEGIN;', '').replace('COMMIT;', '')


def validate():
    p = plan()
    pointers(p['old_release'])
    target = checked_target()
    # The exact ranking migration is tried inside a transaction and rolled back.
    with payment().connection() as c:
        try:
            invariants(c, p['old_ranking_sha'])
            c.execute('SET LOCAL ROLE goufayu_owner')
            c.execute(sql_source())
            value = c.execute('SELECT public.archive_endless_leaderboard()').fetchone()[0]
            need(value.get('ok') is True and len(value['entries']) <= 100, 'ranking_projection_failed')
            need(all(type(row['vip_level']) is int and 0 <= row['vip_level'] <= 12
                     and type(row['vip_medal_level']) is int and 0 <= row['vip_medal_level'] <= 10 for row in value['entries']), 'ranking_badge_failed')
            new_sha = hashlib.sha256(definition(c).encode()).hexdigest()
        finally:
            c.rollback()
    with payment().connection() as c:
        c.execute('SET TRANSACTION READ ONLY')
        invariants(c, p['old_ranking_sha'])
        c.rollback()
    # Compilation uses no pycache and never runs application startup/profile calls.
    for name in p['files']:
        if name.endswith('.py'):
            compile((target / name).read_text(), name, 'exec')
    return record('validation', {'status': 'VALIDATED', 'ranking_sha': new_sha,
                                 'ranking_trial_rolled_back': True, 'player_rows_written': 0})


def service(action):
    subprocess.run(['systemctl', action, 'goufayu-api.service'], check=True, capture_output=True)


def switch(path):
    temporary = Path('/opt/goufayu/releases/current.vip.' + secrets.token_hex(4))
    temporary.symlink_to(path, target_is_directory=True)
    os.replace(temporary, '/opt/goufayu/releases/current')


def ready(directory):
    for attempt in range(30):
        try:
            with contextlib.redirect_stdout(io.StringIO()):
                load('vip_ready_manage', directory / 'deploy/manage.py').health()
            health()
            pid = subprocess.run(['systemctl', 'show', 'goufayu-api.service', '--property=MainPID', '--value'], capture_output=True, text=True, check=True).stdout.strip()
            configured = subprocess.run(['systemctl', 'show', 'goufayu-api.service', '--property=WorkingDirectory', '--value'], capture_output=True, text=True, check=True).stdout.strip()
            need(pid.isdigit() and int(pid) > 1 and Path('/proc/' + pid + '/cwd').resolve() == directory
                 and Path(configured).resolve() == directory, 'archive_process_directory_changed')
            return
        except Exception:
            if attempt == 29:
                raise RuntimeError('strict_readiness_failed') from None
            time.sleep(0.5)


def verify():
    p = plan()
    target = checked_target()
    pointers(target)
    ready(target)
    with payment().connection() as c:
        c.execute('SET TRANSACTION READ ONLY')
        invariants(c, record('validation')['ranking_sha'])
        c.rollback()
    return record('verified', {'status': 'VERIFIED', 'archive_release': str(target),
        'payment_release': p['old_payment'], 'archive_bundle': p['bundle'], 'cash_catalog_hash': p['cash_hash'],
        'payment_restarted': False, 'prices_changed': False, 'health': health(), 'real_orders_created': 0})


def activate():
    p = plan()
    target = checked_target()
    pointers(p['old_release'])
    need(record('validation')['status'] == 'VALIDATED', 'validation_missing')
    stopped = False
    try:
        stopped = True
        service('stop')
        pointers(p['old_release'])
        with payment().connection() as c:
            invariants(c, p['old_ranking_sha'])
            c.execute('SET LOCAL ROLE goufayu_owner')
            c.execute(sql_source())
            invariants(c, record('validation')['ranking_sha'])
        switch(target)
        service('start')
        return verify()
    except BaseException:
        # A committed gift is a legitimate player reward; no player data is
        # restored from backup. Only code and the read-only SQL projection roll back.
        if stopped:
            service('stop')
            with payment().connection() as c:
                actual = hashlib.sha256(definition(c).encode()).hexdigest()
                need(actual in [p['old_ranking_sha'], record('validation')['ranking_sha']], 'external_ranking_change')
                c.execute('SET LOCAL ROLE goufayu_owner')
                c.execute((STAGE / 'rollback_ranking.sql').read_text())
            need(Path('/opt/goufayu/releases/current').resolve() in [Path(p['old_release']), target], 'external_release_change')
            switch(p['old_release'])
            service('start')
            ready(Path(p['old_release']))
            record('recovery', {'status': 'ROLLED_BACK', 'player_rewards_preserved': True})
        raise


def main():
    global PLAN_PIN, OPERATOR_PIN
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['prepare', 'validate', 'activate', 'verify'])
    parser.add_argument('--plan-sha', required=True)
    parser.add_argument('--operator-sha', required=True)
    args = parser.parse_args()
    PLAN_PIN, OPERATOR_PIN = args.plan_sha, args.operator_sha
    need(Path(__file__).resolve().parent == STAGE and os.geteuid() == 0, 'operator_scope')
    p = plan()
    for name, expected in p['files'].items():
        need(not (STAGE / name).is_symlink() and sha(STAGE / name) == expected, 'overlay_changed:' + name)
    with open('/var/lock/goufayu-vip-recharge.lock', 'w') as guard:
        fcntl.flock(guard, fcntl.LOCK_EX | fcntl.LOCK_NB)
        result = globals()[args.action]()
        print(json.dumps(result, ensure_ascii=False))


if __name__ == '__main__':
    try:
        main()
    except Exception as exc:
        print(json.dumps({'status': 'FAILED', 'error_type': type(exc).__name__,
                          'reason': str(exc) if type(exc) is RuntimeError else 'diagnostics_available_on_host'}))
        sys.exit(1)
