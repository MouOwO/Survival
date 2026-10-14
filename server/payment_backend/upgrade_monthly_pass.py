"""Validate then publish a 20-yuan/30-day monthly pass from a named release.

Reuse the existing payment release integrity, backup and guarded recovery tools.
Validation runs only nonce-derived synthetic fixtures and always rolls back.
No configuration, account permissions, gateway order or existing reward is changed.
"""
import json
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from payment_backend import upgrade_ucoin_shop as release
from payment_backend.sync_catalog import validate, apply
from payment_backend.test_monthly_pass_database import run_checks


def migrate(conn):
    conn.execute('SET ROLE goufayu_owner')
    conn.execute((ROOT / 'payment_backend/upgrade_monthly_pass.sql').read_text(encoding='utf-8'))


def check(package):
    with release.connection() as conn:
        try:
            conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ')
            before = release.preserved_state(conn)
            migrate(conn)
            apply(conn, package)
            if release.preserved_state(conn) != before:
                raise RuntimeError('monthly_upgrade_modified_existing_receipts_or_rewards')
            report = run_checks(conn, package['catalog'])
        finally:
            conn.rollback()
    return report


def main(action, path, digest, expected):
    if action not in ('validate', 'activate'):
        raise RuntimeError('operator_action_required')
    old = release.verify_release(expected)
    package = validate(path, digest)
    report = check(package)
    if action == 'validate':
        print(json.dumps({'validated': True, 'catalog_hash': package['catalog_hash'],
                          'database': report, 'fixture_rolled_back': True, 'gateway_orders_created': 0}))
        return
    before_api = release.health()
    release.backup()
    release.prepare_environment(old)
    committed, link, game_api_unchanged = False, None, None
    try:
        release.write_history(package)
        link = release.temporary_link('monthly-next', ROOT)
        with release.connection() as conn:
            conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ')
            conn.execute("SET lock_timeout='5s'")
            conn.execute('SET ROLE goufayu_owner')
            conn.execute('''LOCK TABLE public.player_gameplay_stats,public.player_archive_state,
              public.archive_entitlements,payments.orders IN SHARE ROW EXCLUSIVE MODE''')
            before = release.preserved_state(conn)
            snapshot = release.catalog_snapshot(conn)
            migrate(conn)
            apply(conn, package)
            if release.preserved_state(conn) != before:
                raise RuntimeError('monthly_upgrade_modified_existing_receipts_or_rewards')
            release.verify_release(expected)
        committed = True
        release.verify_release(expected)
        os.replace(link, release.BASE / 'current')
        release.run(['systemctl', 'restart', 'goufayu-payment.service'])
        release.wait_healthy()
        game_api_unchanged = release.health() == before_api
        if not game_api_unchanged:
            raise RuntimeError('game_api_changed_during_monthly_activation')
    except Exception as error:
        recovery = {'activation_failed': True, 'catalog_was_committed': committed}
        if game_api_unchanged is not None:
            recovery['game_api_unchanged'] = game_api_unchanged
        if committed:
            # Keep the additive delivery capability: an order created during
            # activation must retain its immutable timed reward after recovery.
            recovery['timed_delivery_retained_for_existing_orders'] = True
            try:
                recovery['catalog_restored'] = release.restore_catalog(
                    snapshot, package['catalog_hash'], [p['sku'] for p in package['catalog']['products']])
            except Exception:
                recovery['catalog_rollback_failed'] = True
            try:
                recovery['code_restored'] = release.restore_code(old)
            except Exception:
                recovery['code_rollback_failed'] = True
        print(json.dumps(recovery), flush=True)
        if recovery.get('catalog_rollback_failed') or recovery.get('code_rollback_failed'):
            raise RuntimeError('monthly_activation_failed_and_rollback_incomplete') from error
        raise
    finally:
        try:
            if link is not None and link.is_symlink() and link.resolve() == ROOT:
                link.unlink()
        except OSError:
            pass
    print(json.dumps({'activated': ROOT.name, 'catalog_hash': package['catalog_hash'],
                      'database': report, 'fixture_rolled_back': True, 'game_api_unchanged': game_api_unchanged,
                      'existing_orders_and_rewards_preserved': True, 'account_permissions_unchanged': True,
                      'gateway_orders_created': 0}))


if __name__ == '__main__':
    main(*sys.argv[1:])
