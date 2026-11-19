"""Activate prepared WS4 services after an already committed paid-preserving reset.

There is no gameplay reset or database write here. Directory metadata preserves
the original service ownership; payment keeps its fixed WS4 config namespace.
"""
from __future__ import annotations
import argparse
from contextlib import ExitStack
from decimal import Decimal
import json
import os
from pathlib import Path
import stat
import time
import urllib.request
from uuid import uuid4

from public_launch.maintenance import (PREFIX, ROLES, CONFIG, DROPIN, canonical,
    command, connect, context, need, new, sha)


def repair_directories(original, candidate):
    original, candidate = Path(original).resolve(), Path(candidate).resolve()
    need(original != candidate and original.parent == candidate.parent, 'separate_sibling_releases_required')
    visited = changed = 0
    for current, directories, _ in os.walk(original, followlinks=False):
        current = Path(current)
        directories[:] = [name for name in directories if not (current / name).is_symlink()]
        target = candidate / current.relative_to(original)
        need(not target.is_symlink() and target.resolve().is_relative_to(candidate), 'candidate_directory_escaped')
        source_stat, target_stat = current.stat(), target.stat()
        need(stat.S_ISDIR(target_stat.st_mode), 'candidate_directory_required')
        visited += 1
        if (source_stat.st_uid, source_stat.st_gid) != (target_stat.st_uid, target_stat.st_gid):
            os.chown(target, source_stat.st_uid, source_stat.st_gid, follow_symlinks=False)
            changed += 1
        if stat.S_IMODE(source_stat.st_mode) != stat.S_IMODE(target_stat.st_mode):
            os.chmod(target, stat.S_IMODE(source_stat.st_mode), follow_symlinks=False)
    return dict(visited_directories=visited, restored_ownership=changed, shared_files_modified=0)


def fixed_payment_config(current, prepared):
    old, revised = json.loads(current), json.loads(prepared)
    need(old.get('access_mode', 'test') == 'test' and revised.get('access_mode') == 'public',
         'reviewed_private_to_public_config_required')
    before, after = dict(old), dict(revised)
    before.pop('access_mode', None)
    after.pop('access_mode', None)
    need(before == after and revised['public_base'] == 'https://pay.xiaofengnet.com/ws4-payments',
         'only_payment_access_mode_may_change')
    return revised


def verify_paid_state(stage):
    """SELECT-only snapshots: compare history, balances and ownership to reset plan."""
    from account_cleanup import engine
    plan = json.loads((stage / 'private_reset_plan.json').read_bytes())
    contract = json.loads((stage / 'schema_contract.json').read_bytes())
    conn = connect()
    try:
        conn.execute('SET TRANSACTION READ ONLY')
        for account in plan['accounts']:
            summary, raw = engine.snapshot(conn, account, contract, keep_rows=True)
            for table in ('payments.orders', 'payments.vip_recharge_credits', 'payments.test_resets',
                          'public.archive_daily_unique_backups', 'public.archive_leaderboard_identities'):
                need(summary['tables'][table] == plan['before'][account]['tables'][table],
                     'preserved_financial_history_changed')
            kept = plan['preserve'][account]
            state = json.loads(raw['public.player_archive_state'][0])
            stats = json.loads(raw['public.player_gameplay_stats'][0], parse_float=Decimal)
            need(state['archive'].get('commerce', {}).get('balances', {})
                 == kept['archive'].get('commerce', {}).get('balances', {}), 'preserved_wallet_changed')
            need(state['content_inventory'] == kept['inventory'], 'preserved_paid_inventory_changed')
            for key, value in kept['stats'].items():
                need(Decimal(str(stats[key])) == Decimal(value), 'preserved_paid_balance_changed')
            actual_entitlements = [json.loads(value) for value in raw['public.archive_entitlements']]
            need(sorted(actual_entitlements, key=lambda row: row['entitlement_id'])
                 == sorted(kept['entitlements'], key=lambda row: row['entitlement_id']),
                 'preserved_entitlement_changed')
    finally:
        conn.rollback()
        conn.close()
    return len(plan['accounts'])


def activate(stage):
    need((stage / 'reset_applied.json').is_file() and (stage / 'failed.json').is_file(),
         'recorded_committed_reset_required')
    failed = json.loads((stage / 'failed.json').read_bytes())
    need(failed['commit_known'] is True and failed['reset_committed'] is True,
         'known_committed_reset_only_no_replay')
    manifest = json.loads((stage / 'manifest.json').read_bytes())
    prepared = json.loads((stage / 'prepared.json').read_bytes())
    need(sha((stage / 'prepared.json').read_bytes())
         == '9df2276368195ca43a86aaf60eda2d7983168d381fdba0aef2ece1e76d525c7a', 'reviewed_preparation_changed')
    context(manifest)
    before = CONFIG.read_bytes()
    revised = Path(prepared['candidate_config']).read_bytes()
    need(sha(before) == prepared['original_config_sha256']
         and sha(revised) == prepared['candidate_config_sha256'], 'reviewed_payment_config_changed')
    fixed_payment_config(before, revised)
    backups = json.loads((stage / 'backup.json').read_bytes())
    for name, facts in backups.items():
        need(sha((stage / name).read_bytes()) == facts['sha256'], 'private_server_backup_changed')
    count = verify_paid_state(stage)
    output = PREFIX / ('activation_recovery_' + uuid4().hex)
    output.mkdir(mode=0o700)
    new(output / 'intent.json', canonical({'source_stage': str(stage), 'gameplay_reset': False,
        'source_revision': manifest['source_revision'], 'fixed_payment_config_path': str(CONFIG)}))
    new(output / 'payment-config.before.json', before)
    metadata = {}
    for role, (unit, _) in ROLES.items():
        original = Path(manifest['remote_parent_roots'][role])
        if role == 'api':
            original = original.parent
        metadata[role] = repair_directories(original, prepared['releases'][role])
        # Exercise filesystem access as the actual service user before stopping.
        user = prepared['service_pins'][role]['user']
        command(['runuser', '-u', user, '--', 'test', '-x', prepared['working_directories'][role]])
        destination = Path('/etc/systemd/system') / (unit + '.d') / DROPIN
        need(not destination.exists(), 'fresh_owned_activation_dropin_required')
    new(output / 'directory_receipt.json', canonical(metadata))
    units = [ROLES[role][0] for role in ('web', 'payment', 'api')]
    installed, config_changed = [], False
    old_stat = CONFIG.stat()
    try:
        for unit in units:
            command(['systemctl', 'stop', unit])
        verify_paid_state(stage)
        temp = CONFIG.with_name('config.json.' + output.name + '.pending')
        new(temp, revised, mode=stat.S_IMODE(old_stat.st_mode))
        os.chown(temp, old_stat.st_uid, old_stat.st_gid)
        os.replace(temp, CONFIG)
        config_changed = True
        for role, (unit, _) in ROLES.items():
            destination = Path('/etc/systemd/system') / (unit + '.d') / DROPIN
            text = (stage / (role + '.conf')).read_bytes() if role != 'payment' else (
                '[Service]\nWorkingDirectory=' + prepared['working_directories'][role] + '\n').encode()
            destination.parent.mkdir(parents=True, exist_ok=True)
            new(destination, text, mode=0o644)
            installed.append(destination)
        command(['systemctl', 'daemon-reload'])
        for unit in reversed(units):
            command(['systemctl', 'start', unit])
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        for role, port in (('api', 18765), ('web', 18767), ('payment', 18769)):
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
            need(healthy, 'public_service_health_failed:' + role)
        for role, (unit, _) in ROLES.items():
            pid = command(['systemctl', 'show', unit, '--property=MainPID', '--value']).decode().strip()
            need(Path(os.readlink('/proc/' + pid + '/cwd')).resolve() == Path(prepared['working_directories'][role]),
                 'public_service_source_not_active')
            if role == 'payment':
                argv = Path('/proc/' + pid + '/cmdline').read_bytes().decode().strip('\0').split('\0')
                need(argv[5] == str(CONFIG) and json.loads(CONFIG.read_bytes())['access_mode'] == 'public',
                     'fixed_public_payment_config_not_active')
            else:
                env = dict(value.split(b'=', 1) for value in Path('/proc/' + pid + '/environ').read_bytes().split(b'\0') if b'=' in value)
                key = b'SURVIVAL_ACCESS_MODE' if role == 'api' else b'PLAYER_WEB_AUTH_ACCESS_MODE'
                need(env.get(key) == b'public', 'public_access_environment_not_active')
        verify_paid_state(stage)
        result = dict(status='PUBLIC_BACKEND_ACTIVE_PAID_PRESERVED', host='47.111.16.128', database='goufayu_ws4',
            source_revision=manifest['source_revision'], public_admission={'api': True, 'web': True, 'payment': True},
            financial_history_preserved=True, paid_inventory_preserved=True, balances_preserved=True,
            full_backup_verified=True, old_auth_revoked=True, fresh_health_verified=True,
            reset_accounts=count, gameplay_reset_repeated=False, backups_stay_on_server=True,
            recovery_directory=str(output), directory_metadata=metadata)
        new(output / 'result.json', canonical(result))
        return result
    except Exception as error:
        new(output / 'failed.json', canonical({'error_type': type(error).__name__, 'gameplay_reset': False}))
        for unit in units:
            command(['systemctl', 'stop', unit])
        for path in installed:
            need(path.name == DROPIN and path.parent.parent == Path('/etc/systemd/system'), 'owned_dropin_only')
            path.unlink()
        if config_changed:
            need(sha(CONFIG.read_bytes()) == sha(revised), 'concurrent_payment_config_change_preserved')
            temp = CONFIG.with_name('config.json.' + output.name + '.rollback')
            new(temp, before, mode=stat.S_IMODE(old_stat.st_mode))
            os.chown(temp, old_stat.st_uid, old_stat.st_gid)
            os.replace(temp, CONFIG)
        command(['systemctl', 'daemon-reload'])
        for unit in reversed(units):
            command(['systemctl', 'start', unit])
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--stage', type=Path, required=True)
    args = parser.parse_args()
    stage = args.stage.resolve(strict=True)
    need(stage == PREFIX / 'candidate_3e21e385_03628864b0' and not args.stage.is_symlink(), 'fixed_launch_stage_required')
    import fcntl
    with ExitStack() as stack:
        for name in sorted(('goufayu_ws4_account_cleanup', 'goufayu_ws4_redemption',
                            'goufayu_admission_five', 'goufayu_public_launch')):
            lock = stack.enter_context(open('/var/lock/' + name + '.lock', 'a+b'))
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        print(json.dumps(activate(stage)))


if __name__ == '__main__':
    main()
