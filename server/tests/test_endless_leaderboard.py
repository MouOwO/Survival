from __future__ import annotations
import copy
from http.server import ThreadingHTTPServer
import hashlib
import json
from pathlib import Path
import sys
import threading
import types
import unittest
from unittest.mock import patch
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'server'))
sys.path.insert(0, str(ROOT / 'tools'))
from archive_backend.endless_leaderboard import EndlessLeaderboard, public_identity, install
from patch_endless_leaderboard_handler import patch_handler, patch_archive_install


def row(number, floor, score, account=None):
    return {'entry_id': '00000000-0000-4000-8000-' + f'{number:012x}',
            'steam_id': public_identity(str(account))[1] if account else '',
            'best_floor': floor, 'endless_score': score}


class Database:
    def __init__(self):
        self.rows = [row(1, 100, 900, 100), row(2, 90, 800), row(3, 80, 700, 300)]
        self.calls = []

    def rpc(self, name, payload):
        self.calls.append((name, copy.deepcopy(payload)))
        if name == 'archive_bind_leaderboard_identity':
            return {'ok': True}
        if name == 'archive_endless_leaderboard':
            return {'ok': True, 'entries': copy.deepcopy(self.rows)}
        raise AssertionError(name)


class App:
    def __init__(self):
        self.rpc_client = Database()
    def _database_account_id(self, account):
        return hashlib.sha256(account.encode()).hexdigest()
    def authorized(self, value):
        return value == 'Bearer local-test-only'


class LeaderboardTests(unittest.TestCase):
    def setUp(self):
        self.app = App()
        self.ranking = EndlessLeaderboard(self.app)

    def test_top_contract_own_highlight_and_anonymous_historical_player(self):
        result = self.ranking.read({'account_id': '100'})
        self.assertTrue(result['ok'])
        self.assertEqual(result['total'], 3)
        self.assertEqual(result['limit'], 100)
        self.assertEqual(result['self'], {'listed': True, 'rank': 1})
        self.assertEqual(result['entries'][1]['display_name'], '资料待同步')
        self.assertEqual(result['entries'][1]['steam_id'], '')
        self.assertEqual([x['rank'] for x in result['entries']], [1, 2, 3])
        self.assertNotIn(self.app._database_account_id('100'), json.dumps(result))

    def test_unchanged_response_has_no_rows_and_only_one_identity_bind(self):
        first = self.ranking.read({'account_id': '100'})
        second = self.ranking.read({'account_id': '100', 'revision': first['revision']})
        self.assertTrue(second['unchanged'])
        self.assertNotIn('entries', second)
        self.assertEqual(second['total'], 3)
        self.assertEqual(second['self'], first['self'])
        self.assertEqual(sum(name == 'archive_bind_leaderboard_identity'
                             for name, payload in self.app.rpc_client.calls), 1)
        self.assertEqual(sum(name == 'archive_endless_leaderboard'
                             for name, payload in self.app.rpc_client.calls), 2)

    def test_only_visible_changes_alter_revision(self):
        first = self.ranking.read({'account_id': '100'})
        self.app.rpc_client.rows[0]['unrelated_profile_revision'] = 999
        stable = self.ranking.read({'account_id': '100', 'revision': first['revision']})
        self.assertTrue(stable['unchanged'])
        self.app.rpc_client.rows[0]['endless_score'] += 1
        changed = self.ranking.read({'account_id': '100', 'revision': first['revision']})
        self.assertFalse(changed['unchanged'])
        self.assertNotEqual(changed['revision'], first['revision'])

    def test_unranked_and_zero_entries_remain_an_honest_empty_board(self):
        unlisted = self.ranking.read({'account_id': '400'})
        self.assertEqual(unlisted['self'], {'listed': False})
        self.app.rpc_client.rows = []
        empty = self.ranking.read({'account_id': '400'})
        self.assertEqual(empty['entries'], [])
        self.assertEqual(empty['total'], 0)

    def test_requests_never_accept_score_rank_pagination_or_identity_override(self):
        for extra in ({'best_floor': 9999}, {'score': 50000}, {'rank': 1},
                      {'steam_id': public_identity('300')[1]}, {'limit': 500}, {'page': 2}):
            with self.subTest(extra=extra), self.assertRaisesRegex(ValueError, 'request_fields_invalid'):
                self.ranking.read(dict(account_id='100', **extra))
        self.assertEqual(self.app.rpc_client.calls, [])

    def test_invalid_accounts_and_revisions_do_not_reach_database(self):
        for account in (None, '', 100, True, '0', '-1', '00100', '4294967296', '100;DROP TABLE'):
            with self.subTest(account=account), self.assertRaisesRegex(ValueError, 'account_id_invalid'):
                self.ranking.read({'account_id': account})
        for revision in (None, 12, [], 'x', 'a' * 65, 'A' * 64):
            with self.subTest(revision=revision), self.assertRaisesRegex(ValueError, 'revision_invalid'):
                self.ranking.read({'account_id': '100', 'revision': revision})
        self.assertEqual(self.app.rpc_client.calls, [])

    def test_steam_conversion_is_integer_exact(self):
        self.assertEqual(public_identity('1'), ('1', '76561197960265729'))
        self.assertEqual(public_identity('4294967295')[1], '76561202255233023')

    def test_invalid_rpc_rows_fail_closed_instead_of_drawing_a_fake_board(self):
        cases = [[row(1, 10, 10)] * 2, [row(2, 10, 10), row(1, 10, 10)],
                 [row(1, 10, 10), row(2, 11, 0)], [row(1, 0, 10)],
                 [row(1, 1, -1)], [row(1, True, 0)], [row(1, 1, 0)] * 101,
                 [dict(row(1, 1, 0), steam_id='private-hmac')],
                 [dict(row(1, 1, 0), entry_id='not-a-uuid')]]
        for rows in cases:
            self.app.rpc_client.rows = rows
            with self.subTest(rows=rows[:2]), self.assertRaises(ValueError):
                self.ranking.read({'account_id': '100'})

    def test_100_rows_and_ties_are_stable(self):
        self.app.rpc_client.rows = [row(number, 10, 5, number) for number in range(1, 101)]
        result = self.ranking.read({'account_id': '100'})
        self.assertEqual(result['total'], 100)
        self.assertEqual(result['self'], {'listed': True, 'rank': 100})
        self.assertEqual(result['entries'][-1]['rank'], 100)

    def test_profile_hook_is_idempotent_keeps_existing_response_and_failed_profile_unbound(self):
        original = {'save': {'archive': {'endless_best_wave': 3}}, 'revision': 8}
        service = types.SimpleNamespace(app=self.app, profile=lambda payload: original)
        self.assertIs(install(service), service)
        self.assertIs(install(service), service)
        self.assertIs(service.profile({'account_id': '100'}), original)
        self.assertTrue(service.endless_leaderboard({'account_id': '100'})['ok'])
        self.assertEqual(sum(name == 'archive_bind_leaderboard_identity'
                             for name, payload in self.app.rpc_client.calls), 1)
        def failure(payload):
            raise ValueError('old-profile-failure')
        failed = types.SimpleNamespace(app=self.app, profile=failure)
        install(failed)
        with self.assertRaisesRegex(ValueError, 'old-profile-failure'):
            failed.profile({'account_id': '300'})
        self.assertNotIn('300', failed._endless_leaderboard._bound)

    def test_exact_handler_and_install_patch_preserve_old_source(self):
        source = (ROOT / 'server/staged/fishing_api/server.py').read_text(encoding='utf-8-sig')
        patched = patch_handler(source)
        self.assertEqual(patch_handler(patched), patched)
        self.assertEqual(patched.count('/v1/archive/command'), source.count('/v1/archive/command'))
        self.assertIn('if not self._authorized():', patched)
        service = (ROOT / 'design_refs/endless_leaderboard_20261016/baseline/archive_service.py').read_text()
        new_service = patch_archive_install(service)
        self.assertEqual(patch_archive_install(new_service), new_service)
        self.assertEqual(new_service.replace('    from .endless_leaderboard import install as install_endless_leaderboard\n    install_endless_leaderboard(service)\n', ''), service)

    def test_legacy_wide_numeric_profile_id_is_preserved_without_false_steam_binding(self):
        original = {'account_id': '76561198000000001', 'save': {'archive': {}}, 'revision': 1}
        service = types.SimpleNamespace(app=self.app, profile=lambda payload: original)
        install(service)
        self.assertIs(service.profile({'account_id': original['account_id']}), original)
        self.assertEqual(self.app.rpc_client.calls, [])

    def test_real_http_unauthorized_and_validation_rejected(self):
        backend = Path('D:/survival_database/backend')
        if not backend.is_dir():
            self.skipTest('Local base HTTP dependencies unavailable')
        sys.path.insert(0, str(backend))
        source = patch_handler((ROOT / 'server/staged/fishing_api/server.py').read_text())
        module = types.ModuleType('fishing_api.endless_leaderboard_fixture')
        module.__package__ = 'fishing_api'
        exec(compile(source, '<leaderboard-handler>', 'exec'), module.__dict__)
        self.app.archive = types.SimpleNamespace(endless_leaderboard=self.ranking.read)
        server = ThreadingHTTPServer(('127.0.0.1', 0), module.make_handler(self.app))
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        def post(payload, token='local-test-only'):
            request = urllib.request.Request(f'http://127.0.0.1:{server.server_port}/v1/archive/endless-leaderboard',
                data=json.dumps(payload).encode(), headers={'Authorization': 'Bearer ' + token})
            with opener.open(request, timeout=5) as response:
                return json.load(response)
        try:
            with self.assertRaises(urllib.error.HTTPError) as rejected:
                post({'account_id': '100'}, 'wrong')
            self.assertEqual(rejected.exception.code, 401)
            rejected.exception.close()
            self.assertEqual(self.app.rpc_client.calls, [])
            good = post({'account_id': '100'})
            self.assertEqual(good['total'], 3)
            self.assertTrue(post({'account_id': '100', 'revision': good['revision']})['unchanged'])
            with self.assertRaises(urllib.error.HTTPError) as invalid:
                post({'account_id': '100', 'score': 9000000})
            self.assertEqual(invalid.exception.code, 400)
            invalid.exception.close()
        finally:
            server.shutdown()
            server.server_close()
            thread.join()

    def test_modern_http_session_gate_and_pure_mode_cannot_project_rankings(self):
        backend = Path('D:/survival_database/backend')
        handler = ROOT / 'output/endless_batch_20261010/baseline/backend/fishing_api/server.py'
        if not backend.is_dir() or not handler.is_file():
            self.skipTest('Modern local HTTP fixture unavailable')
        sys.path.insert(0, str(backend))
        from fishing_api.application import ApiError
        source = patch_handler(handler.read_text(encoding='utf-8-sig'))
        self.assertEqual(patch_handler(source), source)
        self.assertIn('except (ArchiveError, ValueError) as exc:', source)
        module = types.ModuleType('fishing_api.endless_leaderboard_modern_fixture')
        module.__package__ = 'fishing_api'
        exec(compile(source, '<modern-leaderboard-handler>', 'exec'), module.__dict__)
        self.app.archive = types.SimpleNamespace(endless_leaderboard=self.ranking.read)
        sessions = types.ModuleType('fishing_api.match_profiles')
        def context(application, payload):
            if payload.get('match_session_id') != 'fixture_match_001':
                raise ApiError('match_session_missing', 409)
            return {'mode': 'pure', 'baseline': {'save': {'archive': {'endless_best_wave': 999}}}}
        def project(application, payload, response, session):
            self.assertNotIn('profile', response)
            self.assertNotIn('schema_version', response)
            return response
        sessions.context, sessions.project = context, project
        server = ThreadingHTTPServer(('127.0.0.1', 0), module.make_handler(self.app))
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        def post(payload):
            request = urllib.request.Request(f'http://127.0.0.1:{server.server_port}/v1/archive/endless-leaderboard',
                data=json.dumps(payload).encode(), headers={'Authorization': 'Bearer local-test-only'})
            with opener.open(request, timeout=5) as response:
                return json.load(response)
        with patch.dict(sys.modules, {'fishing_api.match_profiles': sessions}):
            import fishing_api
            with patch.object(fishing_api, 'match_profiles', sessions, create=True):
                thread.start()
                try:
                    with self.assertRaises(urllib.error.HTTPError) as no_session:
                        post({'account_id': '100'})
                    self.assertEqual(no_session.exception.code, 409)
                    no_session.exception.close()
                    self.assertEqual(self.app.rpc_client.calls, [])
                    good = post({'account_id': '100', 'match_session_id': 'fixture_match_001'})
                    self.assertEqual(good['entries'][0]['best_floor'], 100)
                    self.assertEqual(good['total'], 3)
                    with self.assertRaises(urllib.error.HTTPError) as invalid:
                        post({'account_id': '100', 'match_session_id': 'fixture_match_001', 'rank': 1})
                    self.assertEqual(invalid.exception.code, 400)
                    invalid.exception.close()
                finally:
                    server.shutdown()
                    server.server_close()
                    thread.join()


if __name__ == '__main__':
    unittest.main()
