"""Real Lua + isolated receipts; no SQL, HTTP, player state, or bundle writes."""
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from copy import deepcopy
import io
import json
import os
from pathlib import Path
import shutil
import sys
import threading
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'server'))
sys.path.insert(0, str(ROOT / 'server/tests'))
from archive_backend.bundle import Bundle
from archive_backend import command_timing
from archive_backend.lottery_receipt_snapshot import attach
from archive_backend.service import ArchiveService, FIELDS
from test_archive_backend import App, Database

CAPABILITY = {'lottery_committed_profile_v1': True}
BUNDLE_HASH = 'd573588b64d2ea6d1431c856d52e0515b5ed471cfdf6af4456ff618d0f568488'


class ProjectionContractTests(unittest.TestCase):
    def setUp(self):
        self.service = Mock()
        self.service.bundle.hash = 'a' * 64
        self.service.settle.return_value = {'ok': True, 'snapshots': [{'selected_pool_id': 'map'}]}
        self.reply = {'ok': True, 'done': True, 'profile': {'save': {}}, 'response': {'receipt': 'retained'}}
        self.command = {'kind': 'lottery_draw'}

    def test_only_explicit_boolean_capability_omits_projection(self):
        values = [None, {}, [], True, {'unknown': True}, {'lottery_committed_profile_v1': False},
                  {'lottery_committed_profile_v1': 1}, {'lottery_committed_profile_v1': 'true'}]
        with patch('archive_backend.unique_points.limit_snapshot_ownership', side_effect=lambda r, b: r):
            for value in values:
                with self.subTest(value=value):
                    self.service.reset_mock()
                    result = attach(self.service, deepcopy(self.reply), self.command, 'a' * 64, value)
                    self.assertIn('lottery_snapshots', result)
                    self.service.settle.assert_called_once()
        self.service.reset_mock()
        result = attach(self.service, self.reply, self.command, 'a' * 64, CAPABILITY)
        self.assertIs(result, self.reply)
        self.service.settle.assert_not_called()
        self.service.app.rpc_client.rpc.assert_not_called()

    def test_incomplete_failed_missing_profile_and_other_commands_unchanged(self):
        for reply, command in [({'ok': False}, self.command),
                ({'ok': True, 'profile': {'save': {}}}, self.command),
                ({'ok': True, 'done': True, 'profile': {}}, self.command),
                (deepcopy(self.reply), {'kind': 'lottery_read'})]:
            original = deepcopy(reply)
            self.assertEqual(attach(self.service, reply, command, 'a' * 64, CAPABILITY), original)
        self.service.settle.assert_not_called()

    def test_legacy_projection_failure_preserves_committed_receipt(self):
        self.service.settle.side_effect = RuntimeError('synthetic-worker-failure')
        with self.assertLogs('archive_backend.lottery_receipt_snapshot', level='WARNING') as captured:
            result = attach(self.service, self.reply, self.command, 'a' * 64)
        self.assertIs(result, self.reply)
        self.assertNotIn('synthetic-worker-failure', ''.join(captured.output))


class CountedDatabase(Database):
    def __init__(self, bundle):
        super().__init__(bundle)
        self.calls = Counter()

    def rpc(self, name, payload):
        self.calls[name] += 1
        return super().rpc(name, payload)


class RealLuaReceiptTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.bundle = Bundle(ROOT / 'server/bundles' / BUNDLE_HASH)
        cls.lua = os.environ.get('LUA_EXECUTABLE') or shutil.which('lua5.1') or shutil.which('lua')
        if not cls.lua:
            raise RuntimeError('LUA_EXECUTABLE required; these are real worker tests')

    def setUp(self):
        self.summaries = []
        self.addCleanup(patch.stopall)
        patch('archive_backend.command_timing._emit', side_effect=self.summaries.append).start()
        patch('archive_backend.service.time.time', return_value=1770000000).start()

    def create(self, capability=True):
        database = CountedDatabase(self.bundle)
        app = App(database)
        service = ArchiveService(app, self.bundle, self.lua)
        database.profile(app._database_account_id('100'))['save']['content_inventory'] = {'lottery_ticket': 1000}
        request = {'account_id': '100', 'config_hash': self.bundle.hash,
                   'command': {'kind': 'lottery_draw', 'id': 'compact-test:draw-00001',
                               'request_id': 'compact-request-00001', 'pool_id': 'map', 'count': 10}}
        if capability:
            request['response_capabilities'] = deepcopy(CAPABILITY)
        return database, service, request

    @staticmethod
    def core(receipt):
        return {k: v for k, v in receipt.items() if k not in
                {'lottery_snapshots', 'snapshot_config_hash', 'snapshot_projection_ms'}}

    def test_real_lua_core_receipts_rng_and_saved_state_identical(self):
        old_db, old_service, old_request = self.create(False)
        new_db, new_service, new_request = self.create(True)
        old = old_service.command(old_request)
        new = new_service.command(new_request)
        self.assertTrue(old['ok'])
        self.assertTrue(new['ok'])
        self.assertEqual(self.core(old), self.core(new))
        self.assertEqual(old_db.profiles, new_db.profiles)
        self.assertEqual(old_db.ops, new_db.ops)
        self.assertIn('lottery_snapshots', old)
        self.assertNotIn('lottery_snapshots', new)
        self.assertEqual(old_db.calls, new_db.calls)
        self.assertEqual(new_db.calls, {'archive_prepare': 1, 'archive_commit_lottery': 1})
        self.assertEqual([s['stages']['worker'][0] for s in self.summaries], [2, 1])

    def test_capability_changes_on_done_replay_do_not_double_debit_or_grant(self):
        database, service, request = self.create()
        first = service.command(request)
        state = deepcopy(database.profiles)
        request.pop('response_capabilities')
        replay = service.command(request)
        self.assertEqual(self.core(first), self.core(replay))
        self.assertEqual(database.profiles, state)
        self.assertEqual(len(database.ops), 1)
        self.assertEqual(database.calls['archive_commit_lottery'], 1)
        self.assertEqual(self.summaries[-1]['stages']['worker'][0], 1)  # snapshot only

    def test_lost_reply_recovers_one_durable_grant_with_legacy_projection(self):
        database, service, request = self.create()
        database.lose_reply = True
        with self.assertRaises(TimeoutError):
            service.command(request)
        committed = deepcopy(database.profiles)
        request.pop('response_capabilities')
        reply = service.command(request)
        self.assertTrue(reply['ok'])
        self.assertEqual(database.profiles, committed)
        self.assertEqual(database.calls['archive_commit_lottery'], 1)
        self.assertEqual([s['outcome'] for s in self.summaries], ['exception', 'ok'])

    def test_revision_conflict_keeps_bounded_retry_and_counts_actual_work(self):
        database, service, request = self.create()
        database.conflict = True
        reply = service.command(request)
        self.assertTrue(reply['ok'])
        self.assertEqual(database.calls, {'archive_prepare': 1, 'archive_commit_lottery': 2, 'archive_resume': 1})
        stages = self.summaries[-1]['stages']
        self.assertEqual(stages['worker'][0], 2)
        self.assertEqual(stages['commit'][0], 2)
        self.assertEqual(stages['resume'][0], 1)
        self.assertEqual(len(database.ops), 1)


class CommandTimingTests(unittest.TestCase):
    def test_record_is_bounded_and_omits_all_request_content(self):
        secret = 'private-content-DO-NOT-LOG'
        payload = {'account_id': secret, 'command': {'kind': 'lottery_draw', 'id': secret,
                   'request_id': secret, 'pool_id': secret, 'count': 10}, 'token': secret}
        output = io.StringIO()
        with patch.object(command_timing.sys, 'stdout', output):
            with command_timing.CommandTiming(payload, FIELDS) as timing:
                for stage in command_timing._STAGES:
                    with command_timing.measure(stage):
                        pass
                timing.result({'ok': True, 'profile': {'account_id': secret}})
        raw = output.getvalue()
        self.assertNotIn(secret, raw)
        self.assertLessEqual(len(raw.encode()), command_timing.MAX_RECORD_BYTES)
        self.assertEqual(len(raw.splitlines()), 1)
        row = json.loads(raw[len(command_timing.PREFIX):])
        self.assertEqual(set(row), {'v', 'at_ms', 'kind', 'count', 'outcome', 'total_ms', 'stages'})
        self.assertEqual(row['outcome'], 'ok')

    def test_sink_failure_preserves_success_and_original_exception(self):
        with patch.object(command_timing.sys, 'stdout') as stream:
            stream.write.side_effect = OSError('stdout-failure')
            with command_timing.CommandTiming({}, FIELDS) as timing:
                timing.result({'ok': True})
            with self.assertRaisesRegex(ValueError, 'original-error'):
                with command_timing.CommandTiming({}, FIELDS):
                    raise ValueError('original-error')
        self.assertIsNone(command_timing._ACTIVE.get())

    def test_concurrent_commands_do_not_mix_stage_counts(self):
        barrier = threading.Barrier(2)
        rows = []
        def run(kind, count):
            with command_timing.CommandTiming({'command': {'kind': kind}}, FIELDS) as timing:
                barrier.wait(timeout=5)
                for _ in range(count):
                    with command_timing.measure('worker'):
                        pass
                timing.result({'ok': True})
            self.assertIsNone(command_timing._ACTIVE.get())
        with patch.object(command_timing, '_emit', side_effect=rows.append):
            with ThreadPoolExecutor(max_workers=2) as executor:
                futures = [executor.submit(run, 'lottery_draw', 1), executor.submit(run, 'daily_claim', 2)]
                for future in futures:
                    future.result(timeout=10)
        self.assertEqual({r['kind']: r['stages']['worker'][0] for r in rows}, {'lottery_draw': 1, 'daily_claim': 2})

    def test_idle_measure_emits_nothing_and_unknown_values_are_not_logged(self):
        rows = []
        with patch.object(command_timing, '_emit', side_effect=rows.append):
            with command_timing.measure('worker'):
                pass
            self.assertEqual(rows, [])
            with command_timing.CommandTiming({'command': {'kind': ['private'], 'count': 'private'}}, FIELDS):
                pass
        self.assertEqual(rows[0]['kind'], 'other')
        self.assertEqual(rows[0]['count'], 0)


if __name__ == '__main__':
    unittest.main()
