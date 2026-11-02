"""Actual PostgreSQL/app-role/Lua checks in a schema-only disposable WS4 DB."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import copy
import hashlib
import json
import re
import shutil
import sys
import uuid


def same_balances(before, after):
    # Existing zero-price settlement materializes an absent currency as zero.
    # Compare value, preserving every nonzero/unknown-currency difference.
    return all(before.get(key, 0) == after.get(key, 0) for key in set(before) | set(after))


def make_app(client, actors, defaults):
    class App:
        rpc_client = client
        def _database_account_id(self, public): return actors[public]
        def _ensure_gameplay_stats(self, account):
            return self.rpc_client.rpc('ensure_player_gameplay_stats', {'p_account_id': account, 'p_gameplay_stats': defaults})
        def _public_response(self, value, account, public):
            if isinstance(value, dict): return {k: public if k == 'account_id' and v == account else self._public_response(v, account, public) for k,v in value.items()}
            if isinstance(value, list): return [self._public_response(v, account, public) for v in value]
            return value
        def profile(self, payload):
            public = payload['account_id']; account = self._database_account_id(public)
            self._ensure_gameplay_stats(account)
            value = self.rpc_client.rpc('get_fishing_profile', {'p_account_id': account})
            return self._public_response(value, account, public)
    return App()


def probe_snapshot_and_lock(connect):
    """Two connections, disposable table, only inside the named schema clone."""
    import psycopg
    with connect() as conn:
        assert re.fullmatch(r'goufayu_ws4_ticket_[a-f0-9]{12}', conn.info.dbname)
        conn.execute('CREATE TABLE public.ticket_registry_cas_probe(id integer PRIMARY KEY)')
        conn.execute('INSERT INTO public.ticket_registry_cas_probe VALUES(1)')
    try:
        with connect() as first:
            first.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ')
            assert first.execute('SELECT pg_try_advisory_xact_lock(2026110205)').fetchone()[0]
            with connect() as second: second.execute('INSERT INTO public.ticket_registry_cas_probe VALUES(2)')
            first.execute('LOCK TABLE public.ticket_registry_cas_probe IN SHARE ROW EXCLUSIVE MODE')
            assert first.execute('SELECT count(*) FROM public.ticket_registry_cas_probe').fetchone()[0] == 1
            first.rollback()
        with connect() as first:
            first.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ')
            first.execute('LOCK TABLE public.ticket_registry_cas_probe IN SHARE ROW EXCLUSIVE MODE')
            assert first.execute('SELECT pg_try_advisory_xact_lock(2026110205)').fetchone()[0]
            def blocked_writer():
                try:
                    with connect() as writer:
                        writer.execute("SET LOCAL lock_timeout='250ms'")
                        writer.execute('INSERT INTO public.ticket_registry_cas_probe VALUES(3)')
                except psycopg.Error as error:
                    assert error.sqlstate == '55P03'; return True
                return False
            with ThreadPoolExecutor(max_workers=1) as pool:
                assert pool.submit(blocked_writer).result(timeout=5), 'table_lock_must_block_conflicting_writer'
            assert first.execute('SELECT count(*) FROM public.ticket_registry_cas_probe').fetchone()[0] == 2
            first.rollback()
        with connect() as writer: writer.execute('INSERT INTO public.ticket_registry_cas_probe VALUES(3)')
    finally:
        with connect() as conn: conn.execute('DROP TABLE public.ticket_registry_cas_probe')
    return ['old_select_before_lock_stale_snapshot_reproduced', 'table_lock_before_select_blocks_writer',
            'writer_succeeds_after_lock_release']


def run(connect, release, registry, *, register_synthetic):
    import psycopg
    from psycopg.types.json import Jsonb
    from psycopg.conninfo import make_conninfo
    with connect() as conn:
        database = conn.info.dbname
        assert database.startswith('goufayu_ws4_ticket_') and len(database.rsplit('_', 1)[1]) == 12
        assert conn.execute('SELECT count(*) FROM public.redemption_codes').fetchone()[0] == 0
        assert conn.execute('SELECT count(*) FROM public.survival_players').fetchone()[0] == 0
    sys.path.insert(0, str(release / 'backend'))
    from fishing_api.postgres import PostgresRpcClient
    from archive_backend.service import ArchiveService
    from archive_backend.bundle import Bundle
    from archive_backend.redemption_codes import normalize
    pointer = json.loads((release / 'addon/server/bundles/current.json').read_bytes())
    bundle = Bundle(release / 'addon/server/bundles' / pointer['hash'])
    assert bundle.hash == 'd573588b64d2ea6d1431c856d52e0515b5ed471cfdf6af4456ff618d0f568488'
    defaults = {r['field_id']: r['default_value'] for r in bundle.configs['player_gameplay_stats']['rows']}
    client = PostgresRpcClient(make_conninfo(host='127.0.0.1', port=15432, dbname=database,
        user='goufayu_app', password=Path('/etc/goufayu-ws4/app-password').read_text().strip()))
    assert client.ready()
    actors = {}; session = 'ticket_clone_' + uuid.uuid4().hex
    lua = shutil.which('lua5.1') or shutil.which('lua'); assert lua
    service = ArchiveService(make_app(client, actors, defaults), bundle, lua)
    def actor():
        public = str(91000000000000000 + len(actors)); internal = hashlib.sha256(uuid.uuid4().bytes).hexdigest(); actors[public] = internal
        with connect() as conn:
            conn.execute('SELECT public.ensure_player_gameplay_stats(%s,%s)', (internal, Jsonb(defaults)))
            conn.execute("SELECT public.match_profile_login(%s,%s,'standard',%s)", (internal, session, Jsonb(defaults)))
        return public
    def profile(public): return client.rpc('get_fishing_profile', {'p_account_id': actors[public]})
    def redeem(public, code, token):
        return service.command({'account_id': public, 'match_session_id': session, 'config_hash': bundle.hash,
            'command': {'kind':'redemption_redeem','id':'redeem:'+token,'request_id':token,'code':code}})
    def tickets(saved): return saved['save'].get('content_inventory', {}).get('lottery_ticket', 0)
    checked = []; codes = {}; synthetic = copy.deepcopy(registry['codes'])
    for row, quantity in zip(synthetic, (10,50,100,200)):
        raw = 'QA-TICKET-' + uuid.uuid4().hex.upper()
        digest = hashlib.sha256(normalize(raw).encode()).hexdigest()
        row['code_hash'] = digest; row['code_id'] = 'r_' + digest[:32]; codes[quantity] = raw
    with connect() as conn:
        registered = register_synthetic(conn, synthetic)
        assert registered['inserted'] == 4 and registered['existing_claims_preserved_in_same_rr_snapshot']
    checked.append('production_insert_four_sql_with_four_synthetic_hashes')
    checked.extend(probe_snapshot_and_lock(connect))
    public = actor()
    for row, quantity in zip(registry['codes'], (10,50,100,200)):
        reward = copy.deepcopy(row['rewards']); assert reward['products'][0]['grants']['items'] == {'lottery_ticket':quantity}
        raw = codes[quantity]; before = profile(public)
        response = redeem(public, raw, 'qa_tier_' + str(quantity)); assert response['ok'] and 'command' not in response
        after = profile(public); assert tickets(after) - tickets(before) == quantity
        assert after['save']['gameplay_stats'] == before['save']['gameplay_stats']
        before_balance = before['save'].get('archive', {}).get('commerce', {}).get('balances', {})
        after_balance = after['save'].get('archive', {}).get('commerce', {}).get('balances', {})
        assert same_balances(before_balance, after_balance)
        snapshot = service.lottery_snapshot({'account_id':public,'config_hash':bundle.hash})
        for pool in snapshot['snapshots']:
            assert pool['tickets'] == (tickets(after) if pool['selected_pool_id'] == 'map' else 0)
    checked.append('four_exact_ticket_deltas_and_four_pool_projection')
    saved = profile(public); assert redeem(public,codes[50],'qa_tier_50')['ok']
    assert redeem(public,codes[50],'qa_same_code_new_request')['error'] == 'redeem_already_used'
    assert profile(public) == saved; peer = actor(); assert redeem(peer,codes[50],'qa_other_actor_50')['ok']
    assert tickets(profile(peer)) == 50; checked.append('same_account_once_retry_and_peer_isolation')
    public = actor()
    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(lambda i:redeem(public,codes[200],'qa_parallel_'+str(i)),range(2)))
    assert any(r['ok'] for r in results) and tickets(profile(public)) == 200
    checked.append('actual_postgres_concurrent_single_grant')
    public = actor()
    class LostReply:
        once = True
        def rpc(self, name, args):
            value = client.rpc(name,args)
            if name == 'redemption_commit' and self.once:
                self.once=False; raise TimeoutError('synthetic_lost_reply')
            return value
    service.app.rpc_client = LostReply()
    try: redeem(public,codes[100],'qa_lost_reply_100')
    except TimeoutError: pass
    else: raise AssertionError('lost_reply_not_simulated')
    service.app.rpc_client = client; saved = profile(public)
    assert redeem(public,codes[100],'qa_lost_reply_100')['ok'] and profile(public) == saved and tickets(saved) == 100
    checked.append('actual_committed_reply_loss_idempotency')
    return {'ok':True,'checks':checked,'actual_app_rpc':True,'real_lua_reducer':True,'clone_only':True,
            'real_player_redemption':False,'real_code_definitions_copied':False}
