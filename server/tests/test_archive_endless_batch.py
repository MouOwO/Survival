"""Real reducer/receipt tests for the bounded endless HTTP transport batch."""
from __future__ import annotations
import copy
import importlib.util
import json
import os
from pathlib import Path
import sys
import threading
import time
import types
import unittest
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'server/tests'))
sys.path.insert(0, str(ROOT / 'tools'))
import test_archive_backend as baseline
from archive_backend.service import ArchiveError
from patch_endless_batch_handler import patch_handler


class EndlessBatchTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        baseline.ArchiveTests.setUpClass.__func__(cls)

    def setUp(self):
        baseline.ArchiveTests.setUp(self)

    def payload(self, waves=(1, 2, 3)):
        return {'account_id': '100', 'config_hash': self.bundle.hash,
            'commands': [{'id': 'batch_fixture:endless:' + str(wave),
                'kind': 'endless', 'wave': wave, 'difficulty': 10} for wave in waves]}

    def test_all_scores_once_and_replay_durable_per_wave_receipts(self):
        payload = self.payload(range(1, 33))
        result = self.service.endless_batch(payload)
        self.assertTrue(result['ok'])
        self.assertEqual(len(result['results']), 32)
        score = sum(7 * ((wave - 1) // 10 + 1) - 6 for wave in range(1, 33))
        self.assertEqual(self.profile['save']['archive']['endless_score'], score)
        self.assertEqual(self.profile['save']['archive']['endless_best_wave'], 32)
        revision = self.profile['revision']
        replay = self.service.endless_batch(payload)
        self.assertTrue(replay['ok'])
        self.assertEqual(self.profile['revision'], revision)
        self.assertEqual(len(self.db.ops), 32)
        self.assertEqual(replay['profile']['account_id'], '100')

    def test_lost_partial_reply_replays_without_score_loss_or_duplication(self):
        self.db.lose_reply = True
        with self.assertRaises(TimeoutError):
            self.service.endless_batch(self.payload())
        self.assertEqual(self.profile['save']['archive']['endless_score'], 1)
        result = self.service.endless_batch(self.payload())
        self.assertTrue(result['ok'])
        self.assertEqual(self.profile['save']['archive']['endless_score'], 3)
        self.assertEqual(len(self.db.ops), 3)

    def test_whole_envelope_validated_before_first_mutation(self):
        cases = []
        too_big = self.payload(range(1, 34)); cases.append(too_big)
        empty = self.payload(()); cases.append(empty)
        mixed = self.payload(); mixed['commands'][2] = {'id': 'batch_fixture:clear', 'kind': 'clear', 'difficulty_id': 'n10', 'count': 1}; cases.append(mixed)
        forged = self.payload(); forged['commands'][2]['score'] = 999; cases.append(forged)
        duplicate = self.payload(); duplicate['commands'][2] = copy.deepcopy(duplicate['commands'][0]); cases.append(duplicate)
        invalid = self.payload(); invalid['commands'][2]['wave'] = 1001; cases.append(invalid)
        cross_session = self.payload(); cross_session['commands'][2]['id'] = 'another_match:endless:3'; cases.append(cross_session)
        for payload in cases:
            with self.subTest(payload=payload), self.assertRaises(ArchiveError):
                self.service.endless_batch(payload)
            self.assertEqual(self.db.ops, {})
            self.assertEqual(self.profile['save']['archive'], {})

    def test_previous_single_wave_and_batch_share_the_same_receipt(self):
        payload = self.payload((1,))
        self.assertTrue(self.service.command({'account_id': '100', 'config_hash': self.bundle.hash,
            'command': payload['commands'][0]})['ok'])
        self.assertTrue(self.service.endless_batch(self.payload())['ok'])
        self.assertEqual(self.profile['save']['archive']['endless_score'], 3)
        self.assertEqual(len(self.db.ops), 3)

    def test_unsupported_config_does_not_acknowledge_or_drop_earned_waves(self):
        payload = self.payload(); payload['config_hash'] = '0' * 64
        result = self.service.endless_batch(payload)
        self.assertFalse(result['ok']); self.assertEqual(result['results'], [])
        self.assertEqual(self.db.ops, {})

    def test_partial_retryable_response_keeps_acknowledgements(self):
        original = self.service.command
        calls = [0]
        def interrupted(payload):
            calls[0] += 1
            if calls[0] == 2:
                return {'ok': False, 'error': 'archive_busy_retry'}
            return original(payload)
        self.service.command = interrupted
        result = self.service.endless_batch(self.payload())
        self.assertFalse(result['ok'])
        self.assertTrue(result['results'][0]['ok'])
        self.assertFalse(result['results'][1]['ok'])
        self.assertEqual(len(result['results']), 2)
        self.service.command = original
        self.assertTrue(self.service.endless_batch(self.payload())['ok'])
        self.assertEqual(self.profile['save']['archive']['endless_score'], 3)

    def test_authenticated_route_capability_and_previous_route(self):
        backend = Path(os.environ.get('FISHING_BACKEND_ROOT', 'D:/survival_database/backend'))
        sys.path.insert(0, str(backend))
        source = patch_handler((backend / 'fishing_api/server.py').read_text(encoding='utf-8-sig'))
        self.assertEqual(patch_handler(source), source, 'patch must be idempotent')
        module = types.ModuleType('fishing_api.endless_batch_fixture')
        module.__package__ = 'fishing_api'
        exec(compile(source, str(backend / 'fishing_api/server.py'), 'exec'), module.__dict__)
        self.app.archive = self.service
        server = ThreadingHTTPServer(('127.0.0.1', 0), module.make_handler(self.app))
        thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
        def post(path, payload, authorized=True):
            request = urllib.request.Request('http://127.0.0.1:' + str(server.server_port) + path,
                data=json.dumps(payload).encode(), headers={'Authorization': 'Bearer local-test-only' if authorized else 'bad', 'Content-Type': 'application/json'})
            opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
            with opener.open(request, timeout=10) as response:
                return json.load(response)
        try:
            with self.assertRaises(urllib.error.HTTPError) as rejected:
                post('/v1/archive/endless-batch', self.payload(), False)
            self.assertEqual(rejected.exception.code, 401); rejected.exception.close()
            self.assertEqual(post('/v1/archive/config', {})['capabilities']['endless_batch'], 1)
            result = post('/v1/archive/endless-batch', self.payload())
            self.assertTrue(result['ok']); self.assertEqual(len(result['results']), 3)
            self.assertEqual(self.profile['save']['archive']['endless_score'], 3)
            self.assertTrue(post('/v1/archive/command', {'account_id': '100', 'config_hash': self.bundle.hash,
                'command': self.payload((1,))['commands'][0]})['ok'])
            with self.assertRaises(urllib.error.HTTPError) as oversized:
                post('/v1/archive/endless-batch', self.payload(range(1, 34)))
            self.assertEqual(oversized.exception.code, 400); oversized.exception.close()
            if 'match_profiles.context(' in source:
                from fishing_api import match_profiles
                from fishing_api.application import ApiError
                request = self.payload((4,)); request['match_session_id'] = 'fixture_match_001'
                before = copy.deepcopy(self.profile)
                with patch.object(match_profiles, 'context', side_effect=ApiError('match_session_missing', 409)):
                    with self.assertRaises(urllib.error.HTTPError) as missing_session:
                        post('/v1/archive/endless-batch', request)
                self.assertEqual(missing_session.exception.code, 409); missing_session.exception.close()
                self.assertEqual(self.profile, before, 'batch route must pass the existing session gate before any mutation')
                self.profile['save']['archive']['endless_score'] = 103
                self.profile['save']['gameplay_stats']['initial_wood'] = 500
                defaults = {row['field_id']: row['default_value'] for row in self.bundle.configs['player_gameplay_stats']['rows']}
                context = {'baseline': copy.deepcopy(self.profile), 'defaults': defaults,
                    'mode': 'pure', 'match_session_id': 'fixture_match_001', 'created_at': time.time()}
                with patch.object(match_profiles, 'context', return_value=context):
                    projected = post('/v1/archive/endless-batch', request)
                self.assertEqual(projected['profile']['mode'], 'pure')
                self.assertEqual(projected['profile']['save']['archive']['endless_score'], 1)
                self.assertEqual(projected['profile']['account_profile']['save']['archive']['endless_score'], 104)
                self.assertEqual(projected['profile']['save']['gameplay_stats']['initial_wood'], defaults['initial_wood'])
                self.assertTrue(all('profile' not in receipt for receipt in projected['results']))
        finally:
            server.shutdown(); server.server_close(); thread.join()


if __name__ == '__main__':
    unittest.main()
