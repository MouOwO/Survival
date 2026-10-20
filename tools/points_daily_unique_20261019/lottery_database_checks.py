"""Reviewed old-client lottery receipts plus the new CHECK, all in a savepoint."""
import hashlib
import json
import shutil
import uuid


def run_checks(conn, bundle, recorded_hash):
    from archive_backend.service import ArchiveService
    from psycopg import sql
    from psycopg.types.json import Jsonb
    from types import SimpleNamespace
    conn.execute('SAVEPOINT daily_identical_lottery_checks')
    nonce = uuid.uuid4().hex
    account = hashlib.sha256(('daily-identical-lottery:' + nonce).encode()).hexdigest()
    checks = []
    try:
        conn.execute('INSERT INTO public.survival_players(account_id) VALUES(%s)', (account,))
        defaults = {row['field_id']: row['default_value'] for row in bundle.configs['player_gameplay_stats']['rows']}
        conn.execute('SELECT public.ensure_player_gameplay_stats(%s,%s)', (account, Jsonb(defaults)))
        points = {row['item_id']: row for row in bundle.configs['lottery_item_definitions']['rows']
                  if row.get('enabled') is not False and row['item_type'] == '积分道具'}
        inventory = {identity: 1 for identity in points}
        inventory.update(lottery_ticket=100, unrelated_material=999999)
        saved = {'commerce': {'balances': {'shop_points': 100000, 'u_coin': 7}}}
        conn.execute('INSERT INTO public.player_archive_state(account_id,archive,content_inventory) VALUES(%s,%s,%s)',
                     (account, Jsonb(saved), Jsonb(inventory)))

        class RPC:
            lost_reply = True

            def rpc(self, name, params):
                assert name in ('archive_prepare', 'archive_resume', 'archive_commit', 'archive_commit_lottery')
                fields = sorted(params)
                statement = sql.SQL('SELECT public.{}({})').format(sql.Identifier(name),
                    sql.SQL(',').join(sql.SQL('{}=>%s').format(sql.Identifier(field)) for field in fields))
                values = [Jsonb(params[field]) if isinstance(params[field], (dict, list)) else params[field] for field in fields]
                result = conn.execute(statement, values).fetchone()[0]
                if name == 'archive_commit_lottery' and self.lost_reply:
                    self.lost_reply = False
                    raise TimeoutError('synthetic_lost_reply_after_database_commit')
                return result

        rpc = RPC()
        app = SimpleNamespace(account_id_pepper='synthetic-only-daily-compatibility-check', rpc_client=rpc,
            _database_account_id=lambda _: account, _ensure_gameplay_stats=lambda _: None,
            _public_response=lambda result, *_: result)
        executable = shutil.which('lua5.1') or shutil.which('lua')
        assert executable, 'reviewed_lua_runtime_missing'
        service = ArchiveService(app, bundle, executable)

        def payload(kind, token, **values):
            return dict(account_id='100', config_hash=recorded_hash,
                command=dict(id='daily-compat:' + token, kind=kind, pool_id='map', request_id=token, **values))

        def state():
            return conn.execute('''SELECT a.archive,a.content_inventory,p.profile_revision,
                to_jsonb(g)-'player_id'-'created_at'-'updated_at'
                FROM public.player_archive_state a JOIN public.survival_players p USING(account_id)
                JOIN public.player_gameplay_stats g ON g.player_id=a.account_id WHERE a.account_id=%s''', (account,)).fetchone()

        before = state()
        command = payload('lottery_draw', 'daily_pair_draw_' + nonce[:16], count=10)
        try:
            service.command(command)
        except TimeoutError:
            pass
        else:
            raise AssertionError('The lost reply fixture did not exercise receipt recovery')
        committed = state()
        result = service.command(command)
        assert result['ok'] is True and len(result['response']['results']) == 10
        assert state() == committed, 'A replay must never grant/debit again'
        assert committed[1]['lottery_ticket'] == 90
        assert all(committed[1][identity] == 1 for identity in points)
        assert committed[3] == before[3], 'Owned duplicates cannot reapply permanent effects'
        assert committed[0]['commerce']['balances']['shop_points'] > 100000
        assert committed[1]['unrelated_material'] == 999999
        checks.append('trusted_ccc_pending_draw_real_rpc_and_lost_reply_unique_receipt')

        members = {row['item_id'] for row in bundle.configs['lottery_pool_items']['rows']
                   if row['pool_id'] == 'map' and row.get('enabled') is not False}
        item = next(row for identity, row in points.items() if identity in members and row.get('exchange_enabled')
                    and row['exchange_points'] > 0 and 'starjoy_points' not in row['effect_ids'])
        conn.execute('UPDATE public.player_archive_state SET content_inventory=content_inventory-%s WHERE account_id=%s',
                     (item['item_id'], account))
        conn.execute('UPDATE public.player_gameplay_stats SET starjoy_points=100000 WHERE player_id=%s', (account,))
        command = payload('lottery_exchange', 'daily_pair_exchange_' + nonce[:16], item_id=item['item_id'])
        result = service.command(command)
        assert result['ok'] is True
        exchanged = state()
        assert exchanged[1][item['item_id']] == 1
        assert exchanged[3]['starjoy_points'] == 100000 - item['exchange_points']
        assert service.command(command)['response'] == result['response'] and state() == exchanged
        rejected = service.command(payload('lottery_exchange', 'daily_pair_owned_' + nonce[:16], item_id=item['item_id']))
        assert rejected.get('error') == 'lottery_item_owned' and state() == exchanged
        checks.append('trusted_ccc_pending_exchange_keeps_original_currency_cost_and_receipt')

        conn.execute('SAVEPOINT daily_pair_bad_inventory')
        try:
            conn.execute('UPDATE public.player_archive_state SET content_inventory=%s WHERE account_id=%s',
                         (Jsonb({**exchanged[1], item['item_id']: 2}), account))
        except Exception as error:
            assert getattr(error, 'sqlstate', None) == '23514'
        else:
            raise AssertionError('Trusted compatibility bypassed the database ownership constraint')
        finally:
            conn.execute('ROLLBACK TO SAVEPOINT daily_pair_bad_inventory')
            conn.execute('RELEASE SAVEPOINT daily_pair_bad_inventory')
        assert state() == exchanged
        checks.append('trusted_pair_does_not_relax_actual_database_count_check')
    finally:
        conn.execute('ROLLBACK TO SAVEPOINT daily_identical_lottery_checks')
        conn.execute('RELEASE SAVEPOINT daily_identical_lottery_checks')
    assert not conn.execute('SELECT 1 FROM public.survival_players WHERE account_id=%s', (account,)).fetchone()
    return dict(ok=True, groups=len(checks), checks=checks, synthetic_players=1, durable_player_changes=0, real_payments=0)
