"""Fixed WS4 launch maintenance. Importing never contacts services or databases.

prepare makes inactive copies only. apply requires an exact preparation digest
and a separately recorded user-confirmed normal client exit. Financial records
are never deleted; an uncertain COMMIT is read back, never replayed.
"""
from __future__ import annotations
import argparse
from contextlib import ExitStack, closing
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sqlite3
import subprocess
import time
import urllib.request

PREFIX = Path('/root/goufayu_upload/public_launch')
ROLES = {'api': ('goufayu-ws4.service', '/opt/goufayu-ws4/releases/'),
         'web': ('goufayu-ws4-web.service', '/opt/goufayu-ws4-web/releases/'),
         'payment': ('goufayu-ws4-payment.service', '/opt/goufayu-ws4-payment/releases/')}
CONFIG = Path('/etc/goufayu-ws4-payment/config.json')
AUTH = Path('/var/lib/goufayu-ws4-web/auth.sqlite3')
DROPIN = 'zzzz-public-launch-20261119.conf'


def need(value, reason):
    if not value:
        raise ValueError(reason)


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def canonical(value):
    return (json.dumps(value, sort_keys=True, default=str) + '\n').encode()


def new(path, raw, *, mode=0o600):
    with path.open('xb') as stream:
        stream.write(raw)
        stream.flush()
        os.fsync(stream.fileno())
    path.chmod(mode)


def command(args, **kwargs):
    result = subprocess.run(args, capture_output=True, timeout=180, **kwargs)
    need(result.returncode == 0, 'launch_maintenance_subprocess_failed')
    return result.stdout


def context(manifest):
    pins = {}
    for role, (unit, prefix) in ROLES.items():
        raw = command(['systemctl', 'show', unit, '--property=MainPID,WorkingDirectory,User']).decode()
        fields = dict(line.split('=', 1) for line in raw.splitlines() if '=' in line)
        pid = int(fields['MainPID'])
        need(pid > 0, 'required_launch_service_not_running')
        cwd = Path(os.readlink('/proc/' + str(pid) + '/cwd')).resolve()
        need(str(cwd) == manifest['remote_parent_roots'][role] and str(cwd).startswith(prefix),
             'active_launch_service_source_changed')
        argv = Path('/proc/' + str(pid) + '/cmdline').read_bytes().decode().strip('\0').split('\0')
        need(len(argv) in (4, 8) and argv[1:3] == ['-B', '-m'], 'reviewed_module_start_required')
        need(argv[3] == {'api': 'workshop_test.run_api', 'web': 'player_web_auth.game_diagnostics',
                         'payment': 'payment_backend.service'}[role], 'service_entrypoint_changed')
        unit_bytes = command(['systemctl', 'cat', unit])
        pins[role] = dict(pid=pid, cwd=str(cwd), argv=argv, user=fields['User'],
                          unit_sha256=sha(unit_bytes))
    for row in manifest['files']:
        role, relative = row['target'].split('/', 1)
        need(sha((Path(pins[role]['cwd']) / relative).read_bytes()) == row['active_parent_sha256'],
             'live_source_changed_since_candidate')
    return pins


def prepare(stage):
    manifest = json.loads((stage / 'manifest.json').read_bytes())
    need(manifest['host'] == '47.111.16.128' and not manifest['secrets_included'], 'fixed_launch_candidate_required')
    pins = context(manifest)
    label = '20261119-public-' + sha((stage / 'manifest.json').read_bytes())[:12]
    releases, working = {}, {}
    for role, (_, prefix) in ROLES.items():
        old_cwd = Path(pins[role]['cwd'])
        old = old_cwd.parent if role == 'api' else old_cwd
        target = Path(prefix) / label
        need(not target.exists(), 'fresh_inactive_release_required')
        shutil.copytree(old, target, copy_function=os.link, symlinks=True)
        releases[role] = str(target)
        working[role] = str(target / 'backend' if role == 'api' else target)
    for row in manifest['files']:
        role, relative = row['target'].split('/', 1)
        raw = (stage / row['target']).read_bytes()
        need(sha(raw) == row['result_sha256'], 'candidate_source_changed')
        destination = Path(working[role]) / relative
        # Never write a shared hardlink; replacement creates a new inode.
        temp = destination.with_name(destination.name + '.public-launch-new')
        stat = destination.stat()
        new(temp, raw, mode=stat.st_mode & 0o777)
        os.chown(temp, stat.st_uid, stat.st_gid)
        os.replace(temp, destination)
    config_bytes = CONFIG.read_bytes()
    config = json.loads(config_bytes)
    need(config.get('access_mode', 'test') == 'test'
         and config['public_base'] == 'https://pay.xiaofengnet.com/ws4-payments',
         'original_private_ws4_payment_config_required')
    config['access_mode'] = 'public'
    candidate_config = CONFIG.with_name(label + '.json')
    new(candidate_config, canonical(config))
    stat = CONFIG.stat()
    os.chown(candidate_config, stat.st_uid, stat.st_gid)
    for role, (unit, _) in ROLES.items():
        text = '[Service]\nWorkingDirectory=' + working[role] + '\n'
        if role != 'payment':
            key = 'SURVIVAL_ACCESS_MODE' if role == 'api' else 'PLAYER_WEB_AUTH_ACCESS_MODE'
            text += 'Environment="' + key + '=public"\n'
        else:
            argv = pins[role]['argv'][:]
            need(argv[4:] == ['--config', str(CONFIG), '--port', '18769'], 'payment_arguments_changed')
            argv[5] = str(candidate_config)
            need(all(re.fullmatch(r'[A-Za-z0-9_/.:\-]+', part) for part in argv), 'plain_service_arguments_required')
            text += 'ExecStart=\nExecStart=' + ' '.join(argv) + '\n'
        new(stage / (role + '.conf'), text.encode())
        new(Path(releases[role]) / 'public-launch-source.json', canonical({
            'source_revision': manifest['source_revision'], 'manifest_sha256': sha((stage / 'manifest.json').read_bytes()),
            'role': role, 'active': False, 'unchanged_parent': pins[role]['cwd']}))
        # Import actual candidate modules using each actual service interpreter.
        module = {'api': 'archive_backend.test_access', 'web': 'player_web_auth.run',
                  'payment': 'payment_backend.service'}[role]
        command([pins[role]['argv'][0], '-B', '-c', 'import ' + module], cwd=working[role])
    result = dict(status='PUBLIC_BACKEND_PREPARED_INACTIVE', source_revision=manifest['source_revision'],
                  service_pins=pins, releases=releases, working_directories=working,
                  candidate_config=str(candidate_config), original_config_sha256=sha(config_bytes),
                  candidate_config_sha256=sha(candidate_config.read_bytes()),
                  active_services_changed=False, database_modified=False)
    new(stage / 'prepared.json', canonical(result))
    return dict(status=result['status'], prepared_sha256=sha((stage / 'prepared.json').read_bytes()),
                source_revision=result['source_revision'], active_services_changed=False, database_modified=False)


def connect():
    import psycopg
    return psycopg.connect(host='127.0.0.1', port=15432, dbname='goufayu_ws4', user='postgres',
                           password=Path('/etc/goufayu-ws4/admin-password').read_text().strip())


def backup(stage):
    env = dict(os.environ, PGPASSWORD=Path('/etc/goufayu-ws4/admin-password').read_text().strip())
    dump = command(['podman', 'exec', '--env', 'PGPASSWORD', 'goufayu-ws4-db', 'pg_dump',
                    '-h', '127.0.0.1', '-U', 'postgres', '-d', 'goufayu_ws4', '-Fc'], env=env)
    new(stage / 'database.dump', dump)
    listing = command(['podman', 'exec', '-i', 'goufayu-ws4-db', 'pg_restore', '--list'], input=dump)
    need(all(name in listing for name in (b'TABLE DATA public survival_players',
         b'TABLE DATA payments orders', b'TABLE DATA payments vip_recharge_credits')),
         'complete_financial_backup_required')
    with closing(sqlite3.connect(AUTH.as_uri() + '?mode=ro', uri=True)) as source:
        with closing(sqlite3.connect(stage / 'auth.sqlite3')) as target:
            source.backup(target)
            need(target.execute('PRAGMA integrity_check').fetchone() == ('ok',), 'auth_backup_invalid')
            target.commit()
    (stage / 'auth.sqlite3').chmod(0o600)
    result = {name: {'sha256': sha((stage / name).read_bytes()), 'bytes': (stage / name).stat().st_size}
              for name in ('database.dump', 'auth.sqlite3')}
    new(stage / 'backup.json', canonical(result))
    return result


def apply(stage, expected, client_exit_sha):
    from account_cleanup import engine as old
    from public_launch import progress_reset as engine
    need(sha((stage / 'prepared.json').read_bytes()) == expected, 'exact_preparation_required')
    exit_raw = (stage / 'client_exit.json').read_bytes()
    exit_proof = json.loads(exit_raw)
    need(sha(exit_raw) == client_exit_sha and exit_proof.get('normal_exit_confirmed_by_user') is True
         and exit_proof.get('dota_process_count') == 0, 'user_confirmed_normal_client_exit_required')
    need(not (stage / 'apply_intent.json').exists(), 'existing_launch_intent_no_replay')
    prepared = json.loads((stage / 'prepared.json').read_bytes())
    manifest = json.loads((stage / 'manifest.json').read_bytes())
    need(context(manifest) == prepared['service_pins'], 'service_changed_since_preparation')
    need(sha(CONFIG.read_bytes()) == prepared['original_config_sha256']
         and sha(Path(prepared['candidate_config']).read_bytes()) == prepared['candidate_config_sha256'],
         'payment_config_changed')
    metadata = json.loads((stage / 'defaults.json').read_bytes())
    need(sha(Path(metadata['csv_path']).read_bytes()) == metadata['csv_sha256'], 'actual_gameplay_defaults_changed')
    defaults = metadata['defaults']
    contract = json.loads((stage / 'schema_contract.json').read_bytes())
    new(stage / 'apply_intent.json', canonical({'client_exit_sha256': client_exit_sha,
        'prepared_sha256': expected, 'financial_scope': '保留已支付余额和权益，仅重置玩法进度'}))
    units = [ROLES[role][0] for role in ('web', 'payment', 'api')]
    known, committed, conn = True, False, None
    installed = []
    for unit in units:
        target = Path('/etc/systemd/system') / (unit + '.d') / DROPIN
        need(not target.exists(), 'fresh_launch_dropin_required')
    try:
        for unit in units:
            command(['systemctl', 'stop', unit])
        need(all(command(['systemctl', 'show', unit, '--property=MainPID', '--value']).strip() == b'0'
                 for unit in units), 'launch_writer_still_running')
        saved = backup(stage)
        conn = connect()
        old.lock_tables(conn, contract)
        accounts = [row[0] for row in conn.execute('SELECT account_id FROM public.survival_players ORDER BY account_id')]
        plan = engine.preview(conn, accounts, contract, defaults)
        new(stage / 'private_reset_plan.json', canonical(plan))
        result = engine.apply_locked(conn, plan, contract, defaults)
        before_digest = engine.digest(plan['before'])
        after_digest = result['after_fingerprint']
        new(stage / 'commit_intent.json', canonical({'before': before_digest, 'after': after_digest}))
        with closing(sqlite3.connect(AUTH)) as auth:
            with auth:
                auth.execute('BEGIN EXCLUSIVE')
                revoked = auth.execute('UPDATE challenges SET revoked=1,approved_steam=NULL,approved_at=NULL,'
                                       'token_hash=NULL,token_expires=NULL WHERE revoked=0').rowcount
                auth.execute('DELETE FROM flows')
        new(stage / 'auth_revoked.json', canonical({'revoked': revoked, 'nonces_and_financial_bindings_retained': True}))
        known = False
        try:
            conn.commit()
            known, committed = True, True
        except Exception:
            conn.close()
            conn = connect()
            conn.execute('SET TRANSACTION READ ONLY')
            summary = {account: old.snapshot(conn, account, contract)[0] for account in accounts}
            observed = engine.digest(summary)
            known = observed in (before_digest, after_digest)
            committed = observed == after_digest
            need(known and committed, 'commit_unknown_or_rolled_back_no_replay')
        new(stage / 'reset_applied.json', canonical({'accounts': len(accounts), 'after_fingerprint': after_digest,
            'financial_history_preserved': True, 'paid_inventory_preserved': True, 'balances_preserved': True}))
        for role, (unit, _) in ROLES.items():
            path = Path('/etc/systemd/system') / (unit + '.d') / DROPIN
            path.parent.mkdir(parents=True, exist_ok=True)
            new(path, (stage / (role + '.conf')).read_bytes(), mode=0o644)
            installed.append(path)
        command(['systemctl', 'daemon-reload'])
        for unit in reversed(units):
            command(['systemctl', 'start', unit])
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        for port in (18765, 18767, 18769):
            healthy = False
            for attempt in range(10):
                try:
                    with opener.open('http://127.0.0.1:' + str(port) + '/health', timeout=1) as response:
                        healthy = response.status == 200 and json.loads(response.read(8192)).get('ok') is True
                except (OSError, ValueError):
                    pass
                if healthy:
                    break
                time.sleep(0.2)
            need(healthy, 'fresh_public_service_health_failed')
        for role, (unit, _) in ROLES.items():
            pid = command(['systemctl', 'show', unit, '--property=MainPID', '--value']).decode().strip()
            need(Path(os.readlink('/proc/' + pid + '/cwd')).resolve() == Path(prepared['working_directories'][role]),
                 'new_service_source_not_active')
            if role != 'payment':
                env = dict(value.split(b'=', 1) for value in Path('/proc/' + pid + '/environ').read_bytes().split(b'\0') if b'=' in value)
                key = b'SURVIVAL_ACCESS_MODE' if role == 'api' else b'PLAYER_WEB_AUTH_ACCESS_MODE'
                need(env.get(key) == b'public', 'new_service_public_mode_not_active')
            else:
                argv = Path('/proc/' + pid + '/cmdline').read_bytes().decode().strip('\0').split('\0')
                need(argv[5] == prepared['candidate_config'], 'new_payment_config_not_active')
        receipt = dict(status='PUBLIC_BACKEND_ACTIVE_PAID_PRESERVED', host='47.111.16.128', database='goufayu_ws4',
            source_revision=manifest['source_revision'], public_admission={'api': True, 'web': True, 'payment': True},
            financial_history_preserved=True, paid_inventory_preserved=True, balances_preserved=True,
            full_backup_verified=True, old_auth_revoked=True, fresh_health_verified=True,
            reset_accounts=len(accounts), backups=saved, after_fingerprint=after_digest)
        new(stage / 'result.json', canonical(receipt))
        return receipt
    except Exception as error:
        if conn is not None and known:
            conn.rollback()
        new(stage / 'failed.json', canonical({'error_type': type(error).__name__,
            'commit_known': known, 'reset_committed': committed, 'automatic_replay': False}))
        # Unknown financial state stays offline. Known state may restore only
        # service selection; never automatically restore an old financial DB.
        if known:
            for unit in units:
                command(['systemctl', 'stop', unit])
            for path in installed:
                need(path.name == DROPIN and path.parent.parent == Path('/etc/systemd/system'),
                     'owned_dropin_only')
                path.unlink()
            command(['systemctl', 'daemon-reload'])
            for unit in reversed(units):
                command(['systemctl', 'start', unit])
        raise
    finally:
        if conn is not None:
            conn.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('prepare', 'apply', 'status'))
    parser.add_argument('--stage', type=Path, required=True)
    parser.add_argument('--expected-prepare-sha')
    parser.add_argument('--client-exited-sha')
    args = parser.parse_args()
    stage = args.stage.resolve(strict=True)
    need(stage.parent == PREFIX and stage.name.startswith('candidate_') and not args.stage.is_symlink(),
         'fixed_inactive_launch_stage_required')
    import fcntl
    with ExitStack() as stack:
        for name in sorted(('goufayu_ws4_account_cleanup', 'goufayu_ws4_redemption',
                            'goufayu_admission_five', 'goufayu_public_launch')):
            lock = stack.enter_context(open('/var/lock/' + name + '.lock', 'a+b'))
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if args.action == 'prepare':
            result = prepare(stage)
        elif args.action == 'apply':
            need(args.expected_prepare_sha and args.client_exited_sha, 'explicit_launch_apply_pins_required')
            result = apply(stage, args.expected_prepare_sha, args.client_exited_sha)
        else:
            result = {name: json.loads((stage / name).read_bytes()) for name in
                      ('backup.json', 'commit_intent.json', 'reset_applied.json', 'result.json', 'failed.json')
                      if (stage / name).is_file()}
        print(json.dumps(result))


if __name__ == '__main__':
    main()
