"""Real PostgreSQL acceptance. Fixtures always roll back, even on failure.

Run against an isolated local database with LEADERBOARD_TEST_DSN. A deployment
checker may call run_checks(conn) within its own uncommitted migration trial.
No real accounts, payments, reward grants or durable scores are produced.
"""
from __future__ import annotations
import hashlib
import json
import os
from pathlib import Path
import sys
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[2]


def run_checks(conn):
    checks = []
    conn.execute('SAVEPOINT endless_ranking_checks')
    try:
        for function in ('archive_bind_leaderboard_identity(text,text)', 'archive_endless_leaderboard()'):
            metadata = conn.execute('SELECT prosecdef,proconfig FROM pg_proc WHERE oid=%s::regprocedure', ('public.' + function,)).fetchone()
            assert metadata == (True, ['search_path=pg_catalog, public, extensions, pg_temp']), 'rpc_readiness_security_metadata_mismatch'
        checks.append('rpc_security_definer_search_path_matches_live_readiness')
        prefix = 'endless-ranking-synthetic:' + str(uuid.uuid4()) + ':'
        accounts = [hashlib.sha256((prefix + str(i)).encode()).hexdigest() for i in range(111)]
        # Values near the safe integer ceiling ensure these uncommitted
        # synthetic fixtures occupy the first 100, without touching real rows.
        for number, account in enumerate(accounts):
            conn.execute('INSERT INTO public.survival_players(account_id) VALUES(%s)', (account,))
            floor = 9007199254740991 - number if number < 105 else 0
            conn.execute('INSERT INTO public.player_archive_state(account_id,archive) VALUES(%s,%s::jsonb)',
                         (account, json.dumps({'endless_best_wave': floor, 'endless_score': number})))
        ids = dict(conn.execute('SELECT account_id,entry_id::text FROM public.archive_leaderboard_identities WHERE account_id=ANY(%s)', (accounts,)).fetchall())
        assert len(ids) == len(accounts), 'future_insert_trigger_did_not_cover_all_rows'
        checks.append('future_save_identity_seed')
        read = lambda: conn.execute('SELECT public.archive_endless_leaderboard()').fetchone()[0]
        board = read()['entries']
        assert len(board) == 100
        assert [r['entry_id'] for r in board] == [ids[a] for a in accounts[:100]]
        assert all(r['steam_id'] == '' for r in board)
        assert all(set(r) == {'entry_id', 'steam_id', 'best_floor', 'endless_score'} for r in board)
        checks.append('all_historical_and_future_accounts_top_100_anonymous')
        # Select an unclaimed valid public ID. These are never committed.
        public_id = 4294967295
        while conn.execute('SELECT 1 FROM public.archive_leaderboard_identities WHERE public_account_id=%s', (str(public_id),)).fetchone():
            public_id -= 1
        bind = lambda account, public: conn.execute('SELECT public.archive_bind_leaderboard_identity(%s,%s)', (account, public)).fetchone()[0]
        original_row = conn.execute('SELECT to_jsonb(a) FROM public.player_archive_state a WHERE account_id=%s', (accounts[0],)).fetchone()[0]
        assert bind(accounts[0], str(public_id)) == {'ok': True}
        assert bind(accounts[0], str(public_id)) == {'ok': True}
        known = read()['entries'][0]
        assert known['entry_id'] == ids[accounts[0]]
        assert known['steam_id'] == str(76561197960265728 + public_id)
        assert conn.execute('SELECT to_jsonb(a) FROM public.player_archive_state a WHERE account_id=%s', (accounts[0],)).fetchone()[0] == original_row
        checks.append('steam_binding_is_idempotent_stable_and_archive_unchanged')
        def rejected(sql, params=(), expected=None):
            conn.execute('SAVEPOINT rejected_endless_check')
            caught = False
            try:
                conn.execute(sql, params).fetchall()
            except Exception as exc:
                caught = True
                if expected is not None:
                    assert expected in str(exc), str(exc)
            finally:
                conn.execute('ROLLBACK TO SAVEPOINT rejected_endless_check')
                conn.execute('RELEASE SAVEPOINT rejected_endless_check')
            assert caught, 'unsafe_operation_was_accepted'
        rejected('SELECT public.archive_bind_leaderboard_identity(%s,%s)', (accounts[0], str(public_id - 1)), 'leaderboard_identity_immutable')
        rejected('SELECT public.archive_bind_leaderboard_identity(%s,%s)', (accounts[1], str(public_id)))
        for public in ('0', '0001', '-1', '4294967296', '99999999999999999999999999999999', 'x'):
            rejected('SELECT public.archive_bind_leaderboard_identity(%s,%s)', (accounts[1], public), 'leaderboard_identity_invalid')
        rejected('SELECT public.archive_bind_leaderboard_identity(%s,%s)', ('not-an-account', '100'), 'leaderboard_identity_invalid')
        rejected('SELECT public.archive_bind_leaderboard_identity(%s,%s)', ('f' * 64, str(public_id - 1)), 'leaderboard_account_missing')
        checks.append('immutable_binding_collision_missing_parent_and_bad_identity_rejected')
        for raw in ('null', '"12"', '-1', '1.5', 'true', '9007199254740992', '{}', '[]'):
            assert conn.execute('SELECT public.archive_leaderboard_integer(%s::jsonb)', (raw,)).fetchone()[0] == 0
        assert conn.execute("SELECT public.archive_leaderboard_integer('12.0'::jsonb)").fetchone()[0] == 12
        checks.append('malformed_or_unsafe_values_never_become_scores')
        # Equal floors use points, then the permanent public UUID; an identity
        # update cannot move a player who has the same floor and score.
        conn.execute('UPDATE public.player_archive_state SET archive=%s::jsonb WHERE account_id=ANY(%s)',
                     (json.dumps({'endless_best_wave': 9007199254740991, 'endless_score': 10000}), accounts[:3]))
        tie = read()['entries'][:3]
        assert [r['entry_id'] for r in tie] == sorted(ids[a] for a in accounts[:3])
        conn.execute("UPDATE public.player_archive_state SET archive=jsonb_set(archive,'{endless_score}','10001') WHERE account_id=%s", (accounts[2],))
        assert read()['entries'][0]['entry_id'] == ids[accounts[2]]
        checks.append('floor_points_then_public_uuid_order')
        conn.execute('SAVEPOINT role_checks')
        conn.execute('SET LOCAL ROLE goufayu_app')
        assert read()['ok'] is True
        assert bind(accounts[0], str(public_id))['ok'] is True
        rejected('SELECT * FROM public.archive_leaderboard_identities', expected='permission denied')
        rejected('SELECT * FROM public.player_archive_state', expected='permission denied')
        conn.execute('ROLLBACK TO SAVEPOINT role_checks')
        conn.execute('RELEASE SAVEPOINT role_checks')
        for role in ('anon', 'authenticated', 'service_role'):
            conn.execute('SAVEPOINT role_checks')
            conn.execute('SET LOCAL ROLE ' + role)
            rejected('SELECT public.archive_endless_leaderboard()', expected='permission denied')
            rejected('SELECT public.archive_bind_leaderboard_identity(%s,%s)', (accounts[0], str(public_id)), 'permission denied')
            conn.execute('ROLLBACK TO SAVEPOINT role_checks')
            conn.execute('RELEASE SAVEPOINT role_checks')
        checks.append('only_application_rpc_role_can_read_or_bind_private_table_denied')
        # The top list cannot leak any HMAC key or carry saved account data.
        serialized = json.dumps(read())
        assert all(account not in serialized for account in accounts)
        checks.append('no_private_hmac_or_save_payload_disclosure')
    finally:
        conn.execute('ROLLBACK TO SAVEPOINT endless_ranking_checks')
        conn.execute('RELEASE SAVEPOINT endless_ranking_checks')
    assert not conn.execute('SELECT 1 FROM public.survival_players WHERE account_id=ANY(%s)', (accounts,)).fetchone()
    assert not conn.execute('SELECT 1 FROM public.archive_leaderboard_identities WHERE account_id=ANY(%s)', (accounts,)).fetchone()
    checks.append('all_111_fixtures_rolled_back')
    return {'ok': True, 'checks': checks, 'groups': len(checks), 'synthetic_players': 111,
            'real_orders': 0, 'durable_player_changes': 0}


class DatabaseTests(unittest.TestCase):
    @unittest.skipUnless(os.environ.get('LEADERBOARD_TEST_DSN'), 'LEADERBOARD_TEST_DSN is not configured')
    def test_real_database(self):
        sys.path.insert(0, str(ROOT / 'output/video_shop_20261015/deps'))
        import psycopg
        with psycopg.connect(os.environ['LEADERBOARD_TEST_DSN']) as conn:
            result = run_checks(conn)
            self.assertTrue(result['ok'])
            print(json.dumps(result, ensure_ascii=False))


if __name__ == '__main__':
    unittest.main()
