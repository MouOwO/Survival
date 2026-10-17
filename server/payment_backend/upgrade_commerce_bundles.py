"""Validate then publish reviewed commerce bundles from a named release.

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
from payment_backend.test_commerce_bundles_database import run_checks


def preserved_state(conn):
    import hashlib
    # A new column with DEFAULT {} changes to_jsonb(old_row), even without a
    # data update. Normalize that absent key before hashing; existing nonempty
    # receipts are still compared exactly and cannot be lost on a reapply.
    queries=("SELECT to_jsonb(o)||jsonb_build_object('applied_archive',coalesce(to_jsonb(o)->'applied_archive','{}'::jsonb)) FROM payments.orders o ORDER BY order_id",
        "SELECT to_jsonb(s) FROM public.player_gameplay_stats s ORDER BY player_id",
        "SELECT to_jsonb(a) FROM public.player_archive_state a ORDER BY account_id",
        "SELECT to_jsonb(e) FROM public.archive_entitlements e ORDER BY account_id,entitlement_id",
        "SELECT to_jsonb(p) FROM public.survival_players p ORDER BY account_id",
        "SELECT to_jsonb(v) FROM payments.vip_recharge_credits v ORDER BY order_id")
    return [hashlib.sha256(json.dumps(conn.execute(query).fetchall(),sort_keys=True,default=str).encode()).hexdigest() for query in queries]


def migrate(conn):
    conn.execute('SET ROLE goufayu_owner')
    conn.execute((ROOT / 'payment_backend/upgrade_commerce_bundles.sql').read_text(encoding='utf-8'))


def check(package):
    with release.connection() as conn:
        try:
            conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ')
            before = preserved_state(conn)
            migrate(conn)
            apply(conn, package)
            if preserved_state(conn) != before:
                raise RuntimeError('commerce_bundle_upgrade_modified_existing_receipts_or_rewards')
            report = run_checks(conn, package['catalog'])
        finally:
            conn.rollback()
    return report


def retain_compatible_reader(old):
    current=(release.BASE/'current').resolve()
    if current not in (ROOT,old):
        return False  # Another operator's release must never be overwritten.
    link=None
    try:
        if current!=ROOT:
            link=release.temporary_link('bundle-reader-recovery',ROOT)
            os.replace(link,release.BASE/'current')
        release.run(['systemctl','restart','goufayu-payment.service'])
        release.wait_healthy()
        return (release.BASE/'current').resolve()==ROOT
    finally:
        if link is not None and link.is_symlink() and link.resolve()==ROOT:
            link.unlink()


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
        link = release.temporary_link('commerce-bundles-next', ROOT)
        with release.connection() as conn:
            conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ')
            conn.execute("SET lock_timeout='5s'")
            conn.execute('SET ROLE goufayu_owner')
            conn.execute('''LOCK TABLE public.player_gameplay_stats,public.player_archive_state,
              public.archive_entitlements,payments.orders IN SHARE ROW EXCLUSIVE MODE''')
            before = preserved_state(conn)
            snapshot = release.catalog_snapshot(conn)
            migrate(conn)
            apply(conn, package)
            if preserved_state(conn) != before:
                raise RuntimeError('commerce_bundle_upgrade_modified_existing_receipts_or_rewards')
            release.verify_release(expected)
        committed = True
        release.verify_release(expected)
        os.replace(link, release.BASE / 'current')
        release.run(['systemctl', 'restart', 'goufayu-payment.service'])
        release.wait_healthy()
        game_api_unchanged = release.health() == before_api
        if not game_api_unchanged:
            raise RuntimeError('game_api_changed_during_commerce_bundle_activation')
    except Exception as error:
        recovery = {'activation_failed': True, 'catalog_was_committed': committed}
        if game_api_unchanged is not None:
            recovery['game_api_unchanged'] = game_api_unchanged
        if committed:
            # Keep additive delivery capability for immutable bundle snapshots.
            recovery['bundle_delivery_retained_for_existing_orders'] = True
            try:
                recovery['catalog_restored'] = release.restore_catalog(
                    snapshot, package['catalog_hash'], [p['sku'] for p in package['catalog']['products']])
            except Exception:
                recovery['catalog_rollback_failed'] = True
            try:
                # A request can create a new immutable snapshot after any
                # existence check. Once the catalog transaction committed,
                # always keep its backward-compatible reader, including after
                # restoring the previous catalog. Do not race an old reader.
                recovery['compatible_bundle_reader_retained']=retain_compatible_reader(old)
                if not recovery['compatible_bundle_reader_retained']:
                    recovery['code_rollback_failed']=True
            except Exception:
                recovery['code_rollback_failed']=True
        print(json.dumps(recovery), flush=True)
        if recovery.get('catalog_rollback_failed') or recovery.get('code_rollback_failed'):
            raise RuntimeError('commerce_bundle_activation_failed_and_rollback_incomplete') from error
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
