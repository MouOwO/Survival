"""Read the real candidate wallet catalog using an application-role fixture.

Caller supplies only the already-validated schema clone. Every fixture write
is rolled back; no original account, order or balance is read or copied.
"""
import copy, hashlib, json, shutil, sys, uuid
from pathlib import Path
from types import SimpleNamespace


def run(conn, release):
    from psycopg import sql
    from psycopg.types.json import Jsonb
    release = Path(release)
    assert conn.info.dbname.startswith('goufayu_ws4_catalog_') and conn.info.port == 15432
    sys.path.insert(0, str(release / 'backend'))
    from archive_backend.bundle import Bundle
    from archive_backend.service import ArchiveService
    from fishing_api.postgres import RPC_SIGNATURES
    directory = release / 'addon/server/bundles'
    bundle = Bundle(directory / json.loads((directory / 'current.json').read_bytes())['hash'])
    account = hashlib.sha256(('ws4-wallet-schema-probe:' + uuid.uuid4().hex).encode()).hexdigest()
    session = 'ws4_wallet_probe_' + uuid.uuid4().hex
    calls = []

    class RPC:
        def rpc(self, name, params):
            assert name in RPC_SIGNATURES
            calls.append(name)
            statement = sql.SQL('SELECT public.{}({})').format(sql.Identifier(name), sql.SQL(',').join(
                sql.SQL('{}=>%s').format(sql.Identifier(field)) for field in params))
            return conn.execute(statement, [Jsonb(value) if isinstance(value, (dict, list)) else value
                                            for value in params.values()]).fetchone()[0]

    rpc = RPC()
    conn.execute('SAVEPOINT ws4_wallet_readonly_probe')
    try:
        conn.execute('SET LOCAL ROLE goufayu_app')
        defaults = {row['field_id']: row['default_value'] for row in bundle.configs['player_gameplay_stats']['rows']}
        rpc.rpc('ensure_player_gameplay_stats', dict(p_account_id=account, p_gameplay_stats=defaults))
        context = rpc.rpc('match_profile_login', dict(p_account=account, p_session=session, p_mode='standard', p_defaults=defaults))
        assert context.get('ok') is True
        profile = lambda payload: rpc.rpc('get_fishing_profile', dict(p_account_id=account))
        app = SimpleNamespace(rpc_client=rpc, account_id_pepper='schema-probe-only', profile=profile,
            _database_account_id=lambda value: account, _ensure_gameplay_stats=lambda value: None,
            _public_response=lambda value, *args: copy.deepcopy(value))
        service = ArchiveService(app, bundle, shutil.which('lua5.1') or shutil.which('lua'))
        before = profile({})
        result = service.command(dict(account_id='100', match_session_id=session, config_hash=bundle.hash,
            command=dict(id='commerce:ws4_readonly_probe', kind='commerce_catalog')))
        assert result.get('ok') is True
        products = result['products']
        assert len(products) > 0 and len({row['sku'] for row in products}) == len(products)
        assert all(row.get('purchase_method') == 'wallet' for row in products)
        assert profile({}) == before, 'catalog_read_changed_profile'
        report = dict(ok=True, status='APPLICATION_ROLE_WALLET_CATALOG_PASS', products=len(products),
            categories=len(result['categories']), config_hash=bundle.hash, profile_unchanged=True,
            original_player_data_copied=False, orders_created=0, rpc_calls=len(calls))
    finally:
        conn.execute('ROLLBACK TO SAVEPOINT ws4_wallet_readonly_probe')
        conn.execute('RELEASE SAVEPOINT ws4_wallet_readonly_probe')
    assert not conn.execute('SELECT 1 FROM public.survival_players WHERE account_id=%s', (account,)).fetchone()
    report['synthetic_accounts_retained'] = 0
    return report
