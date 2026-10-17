"""Publish only quantity capability from a reviewed payment01 baseline.

validate always rolls back the migration and nonce fixtures. activate does not
publish a catalog, touch archive configuration or replay earlier SQL upgrades.
After a committed v5 capability, failures retain its compatible payment reader.
"""
from contextlib import contextmanager
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from payment_backend import upgrade_ucoin_shop as release
from deploy import GAME

BASELINE = '20261015-payment01'
BASELINE_MANIFEST_SHA256 = 'f51785753b60192f6c6d6e2c6fefdf81b82c4dac8fe9af60997af6ae463018d7'
CATALOG_HASH = 'b56e72aaf6b1cd512ada1f5fe460be98a2f871e7d5dc1b7131701fb4654f4cbe'
ARCHIVE_HASH = 'dee53fe2e9fb8d1bc97ba6b822a86896e97e94b6bad84501fad5791920c3ca26'
REPLACED = frozenset({'payment_backend/service.py'})
ADDED = frozenset({'payment_backend/order_quantity.py', 'payment_backend/upgrade_order_quantity.sql',
    'payment_backend/upgrade_order_quantity.py', 'payment_backend/test_order_quantity_database.py',
    'order_quantity_release.json', 'ORDER_QUANTITY_RELEASE.md'})
TABLES = (
    ('public.player_gameplay_stats', 'player_id'), ('public.survival_players', 'account_id'),
    ('payments.orders', 'order_id'), ('public.player_archive_state', 'account_id'),
    ('public.archive_entitlements', 'account_id,entitlement_id'), ('payments.vip_recharge_credits', 'order_id'),
    ('payments.catalog_state', 'singleton'), ('payments.products', 'sku'), ('payments.providers', 'provider'),
    ('public.match_profile_sessions', 'account_id,match_session_id'), ('payments.test_settings', 'singleton'),
    ('payments.test_accounts', 'account_id'), ('payments.test_resets', 'account_id,request_id'),
    ('payments.cleared_reward_grants', 'grant_id'), ('payments.vip_recharge_levels', 'level'),
    ('public.archive_config_sets', 'config_hash'))
CORE_TABLES = tuple(name for name, _ in TABLES[:6])


def _manifest(directory):
    path = directory / 'manifest.json'
    value = json.loads(path.read_text(encoding='utf-8'))
    if not isinstance(value, dict) or not value:
        raise RuntimeError('quantity_release_manifest_invalid')
    for name, digest in value.items():
        relative = Path(name)
        target = directory / relative
        if (not isinstance(digest, str) or len(digest) != 64 or relative.is_absolute()
                or '..' in relative.parts or '\\' in name or name == 'manifest.json'
                or any(parent.is_symlink() for parent in [target, *target.parents] if parent != directory.parent)
                or directory.resolve() not in target.resolve().parents):
            raise RuntimeError('quantity_release_manifest_path_invalid')
        if hashlib.sha256(target.read_bytes()).hexdigest() != digest:
            raise RuntimeError('quantity_release_manifest_mismatch:' + name)
    return value


def verify_scope(old):
    if old.name != BASELINE or old.parent != release.BASE or ROOT.name != '20261015-payment02':
        raise RuntimeError('quantity_baseline_release_not_reviewed')
    if hashlib.sha256((old / 'manifest.json').read_bytes()).hexdigest() != BASELINE_MANIFEST_SHA256:
        raise RuntimeError('quantity_baseline_manifest_changed')
    baseline, candidate = _manifest(old), _manifest(ROOT)
    changed = {name for name in baseline if candidate.get(name) != baseline[name]}
    if changed != REPLACED or set(candidate) - set(baseline) != ADDED or set(baseline) - set(candidate):
        raise RuntimeError('quantity_release_scope_changed')
    scope = json.loads((ROOT / 'order_quantity_release.json').read_text(encoding='utf-8'))
    if (scope.get('baseline_release') != BASELINE
            or scope.get('baseline_manifest_sha256') != BASELINE_MANIFEST_SHA256
            or scope.get('catalog_hash') != CATALOG_HASH or scope.get('archive_hash') != ARCHIVE_HASH):
        raise RuntimeError('quantity_release_scope_identity_invalid')
    pointer = json.loads((GAME / 'addon/server/bundles/current.json').read_text(encoding='utf-8'))
    if pointer.get('hash') != ARCHIVE_HASH:
        raise RuntimeError('quantity_archive_changed_since_review')
    return scope


def preserved_state(conn):
    result = {}
    # Hash rows in the database's canonical JSON representation; do not print
    # customer records, authentication/session values, QR contents or claims.
    for table, order in TABLES:
        digest = hashlib.sha256()
        for row in conn.execute('SELECT to_jsonb(t)::text FROM ' + table + ' t ORDER BY ' + order):
            data = row[0].encode('utf-8')
            digest.update(len(data).to_bytes(8, 'big'))
            digest.update(data)
        result[table] = digest.hexdigest()
    return result


def catalog_identity(conn):
    row = conn.execute('SELECT catalog_hash FROM payments.catalog_state WHERE singleton').fetchone()
    if not row or row[0] != CATALOG_HASH:
        raise RuntimeError('quantity_catalog_changed_since_review')
    return row[0]


def migrate(conn):
    conn.execute('SET ROLE goufayu_owner')
    conn.execute((ROOT / 'payment_backend/upgrade_order_quantity.sql').read_text(encoding='utf-8'))


def run_checks(conn, catalog):
    path = ROOT / 'payment_backend/test_order_quantity_database.py'
    if not path.exists() and ROOT.name == 'server':
        path = ROOT.parent / 'tools/compact_checkout_20261015/test_quantity_database.py'
    spec = importlib.util.spec_from_file_location('_quantity_upgrade_fixtures', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.run_checks(conn, catalog)


def check_database():
    with release.connection() as conn:
        try:
            conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ')
            conn.execute("SET lock_timeout='5s'")
            conn.execute('SET ROLE goufayu_owner')
            catalog_identity(conn)
            before = preserved_state(conn)
            migrate(conn)
            if preserved_state(conn) != before:
                raise RuntimeError('quantity_migration_modified_existing_state')
            catalog = {'products': [row[0] for row in conn.execute('SELECT to_jsonb(p) FROM payments.products p ORDER BY sku')]}
            conn.execute('SAVEPOINT quantity_fixture_rollback')
            try:
                report = run_checks(conn, catalog)
            finally:
                conn.execute('ROLLBACK TO SAVEPOINT quantity_fixture_rollback')
                conn.execute('RELEASE SAVEPOINT quantity_fixture_rollback')
            if preserved_state(conn) != before:
                raise RuntimeError('quantity_fixtures_modified_existing_state')
            catalog_identity(conn)
        finally:
            conn.rollback()
    return {'checks': report, 'compared_tables': list(before), 'existing_state_hashes_unchanged': True,
            'migration_and_fixtures_rolled_back': True}


@contextmanager
def operator_lock():
    import fcntl  # Linux-only activation, kept lazy for offline tests.
    path = release.BASE / '.order_quantity_activation.lock'
    if path.is_symlink():
        raise RuntimeError('quantity_operator_lock_symlink')
    fd = os.open(path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        yield
    finally:
        os.close(fd)


def cleanup_link(link):
    if link is not None and link.is_symlink() and link.resolve() == ROOT:
        link.unlink()


def retain_compatible_reader(old):
    current = (release.BASE / 'current').resolve()
    if current not in (ROOT, old):
        return False  # Never roll another operator's release backward/forward.
    verify_scope(old)
    link = None
    try:
        if current != ROOT:
            link = release.temporary_link('quantity-reader-recovery', ROOT)
            if (release.BASE / 'current').resolve() != old:
                return False
            os.replace(link, release.BASE / 'current')
        if (release.BASE / 'current').resolve() != ROOT:
            return False
        release.run(['systemctl', 'restart', 'goufayu-payment.service'])
        release.wait_healthy()
        return (release.BASE / 'current').resolve() == ROOT
    finally:
        cleanup_link(link)


def activate(old, expected, report):
    before_api = release.health()
    release.backup()
    release.prepare_environment(old)
    committed, link = False, None
    try:
        release.verify_release(expected)
        verify_scope(old)
        link = release.temporary_link('quantity-next', ROOT)
        with release.connection() as conn:
            # Take fresh catalog snapshots only after advisory/table locks.
            # REPEATABLE READ could freeze a stale view while waiting for a
            # competing publication to finish. The acquired locks stabilize rows.
            conn.execute('SET TRANSACTION ISOLATION LEVEL READ COMMITTED')
            conn.execute("SET lock_timeout='5s'")
            conn.execute('SET ROLE goufayu_owner')
            conn.execute("SELECT pg_advisory_xact_lock(hashtext('payments.order_quantity.publish'))")
            conn.execute("SELECT pg_advisory_xact_lock(hashtext('payments.catalog.publish'))")
            # EXCLUSIVE also blocks concurrent FOR UPDATE readers before they
            # can lock-upgrade; plain catalog/status SELECTs remain available.
            conn.execute('LOCK TABLE ' + ','.join(CORE_TABLES) + ' IN EXCLUSIVE MODE')
            conn.execute('LOCK TABLE ' + ','.join(name for name, _ in TABLES[6:]) + ' IN SHARE MODE')
            catalog_identity(conn)
            before = preserved_state(conn)
            migrate(conn)
            if preserved_state(conn) != before:
                raise RuntimeError('quantity_activation_modified_existing_state')
            catalog_identity(conn)
            release.verify_release(expected)
            verify_scope(old)
        committed = True
        release.verify_release(expected)
        verify_scope(old)
        os.replace(link, release.BASE / 'current')
        if (release.BASE / 'current').resolve() != ROOT:
            raise RuntimeError('quantity_reader_changed_before_restart')
        release.run(['systemctl', 'restart', 'goufayu-payment.service'])
        release.wait_healthy()
        if release.health() != before_api:
            raise RuntimeError('game_api_changed_during_quantity_activation')
    except Exception as error:
        recovery = {'activation_failed': True, 'quantity_capability_committed': committed,
                    'catalog_and_archive_never_published': True}
        if committed:
            try:
                recovery['compatible_v5_reader_retained'] = retain_compatible_reader(old)
            except Exception:
                recovery['compatible_v5_reader_retained'] = False
            recovery['sql_downgraded'] = False
        print(json.dumps(recovery), flush=True)
        if committed and not recovery['compatible_v5_reader_retained']:
            raise RuntimeError('quantity_activation_failed_compatible_reader_recovery_incomplete') from error
        raise
    finally:
        try:
            cleanup_link(link)
        except OSError:
            pass
    return {'activated': ROOT.name, 'catalog_hash': CATALOG_HASH, 'archive_hash': ARCHIVE_HASH,
            'database': report, 'existing_orders_players_claims_credits_preserved': True,
            'game_api_unchanged': True, 'gateway_orders_created': 0, 'sql_downgraded': False}


def main(action, expected):
    if action not in ('validate', 'activate'):
        raise RuntimeError('operator_action_required')
    old = release.verify_release(expected)
    verify_scope(old)
    if action == 'validate':
        report = check_database()
        release.verify_release(expected)
        verify_scope(old)
        print(json.dumps({'validated': True, 'database': report, 'catalog_hash': CATALOG_HASH,
                          'archive_hash': ARCHIVE_HASH, 'gateway_orders_created': 0}))
        return
    with operator_lock():
        old = release.verify_release(expected)
        verify_scope(old)
        report = check_database()
        print(json.dumps(activate(old, expected, report)))


if __name__ == '__main__':
    main(*sys.argv[1:])
