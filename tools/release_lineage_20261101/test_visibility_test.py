"""Isolated SDK-capability and restore tests; no real SDK/network/Git calls."""
from contextlib import ExitStack
import copy
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from test_guard import Fixture
from release_lineage_20261101 import guard as g
import release_visibility_test as v


class VisibilityTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.f = Fixture(self.tmp.name)
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        self.stack.enter_context(patch.object(g, 'require_ancestor'))
        self.f.seed()
        self.stack.enter_context(patch.object(g, 'CANONICAL_JOURNAL', self.f.journal))
        self.project = Path(self.f.policy['repositories']['game'])
        self.project.mkdir()
        approval = json.loads((g.ROOT / v.APPROVAL).read_bytes())
        self.approval = approval
        for relative in (*v.OPERATORS, v.APPROVAL):
            path = self.project / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(g.canonical(approval) if relative == v.APPROVAL else relative.encode())
        def fake_git(root, *args):
            if args == ('rev-parse', 'HEAD'):
                return b'd' * 40
            return (self.project / args[1].split(':', 1)[1]).read_bytes()
        self.stack.enter_context(patch.object(g, '_git', side_effect=fake_git))
        self.stack.enter_context(patch('release_packager.core.baseline', return_value=dict(
            cursor={'baseline_sha256': '6' * 64}, baseline={'official_parent_manifest': '123'})))
        # The production approval validator only accepts the original real item;
        # the low-level lease tests intentionally use Fixture's synthetic item42.
        self.stack.enter_context(patch.object(v, 'validate_approval'))
        self.request = dict(parent_journal_sha256=self.f.parent_sha, generation=1,
            release_sequence=104, baseline_sha256='6' * 64, steam_manifest='123',
            authority_sha256=self.f.pin, operator_files=list(v.OPERATORS), approval=approval,
            authorization_budget={'previous_receipt': None, 'public_seconds_before': 0.0},
            source_revisions={'game': 'c' * 40, 'content': 'd' * 40}, request_sha256='7' * 64)

    def call(self, suffix, args, result):
        self.f.call(suffix, args, result)

    def submit_public(self):
        self.call('StartItemUpdate', (570, 42), 10)
        self.call('SetItemVisibility', (10, 0), True)
        self.call('SubmitItemUpdate', (10, b''), 100)

    def test_two_stage_capabilities_and_package_history_preserved(self):
        original = self.f.journal.read_bytes()
        with g.visibility_test_lease(self.f.authority, self.request) as lease:
            pending, _ = g.read_json(self.f.state)
            self.assertEqual(pending['pending']['kind'], 'TEMPORARY_VISIBILITY_TEST')
            for suffix in ('SetItemContent', 'SetItemTitle', 'SetItemDescription', 'DeleteItem'):
                with self.assertRaises(g.Refused):
                    g.require_sdk_mutation(suffix, (10, b'x'), authority_sha256=self.f.pin)
            with self.assertRaises(g.Refused):
                lease.prepare_restore_attempt(None, query_attempted=True)
            self.submit_public()
            with self.assertRaises(g.Refused):
                g.before_journal_write(self.f.journal, self.f.parent, authority_sha256=self.f.pin)
            with self.assertRaises(g.Refused):
                self.call('StartItemUpdate', (570, 42), 11)
            lease.prepare_restore_attempt({'item': '42', 'visibility': 0}, query_attempted=True)
            self.call('StartItemUpdate', (570, 42), 11)
            with self.assertRaises(g.Refused):
                self.call('SetItemVisibility', (11, 0), True)
            with self.assertRaises(g.Refused):
                self.call('SetItemVisibility', (10, 3), True)
            self.call('SetItemVisibility', (11, 3), True)
            self.call('SubmitItemUpdate', (11, b''), 101)
            path = self.f.root / 'verified.json'
            path.write_bytes(g.canonical(dict(status='VISIBILITY_TEST_RESTORED_UNLISTED',
                request_sha256='7' * 64, final_visibility=3)))
            lease.finish_visibility_test(path)
        state, _ = g.read_json(self.f.state)
        self.assertIsNone(state['pending'])
        self.assertEqual(state['generation'], 1)
        self.assertEqual(self.f.journal.read_bytes(), original)

    def test_timeout_can_only_restore_never_replay_public(self):
        with self.assertRaisesRegex(g.Refused, 'pending_restore'):
            with g.visibility_test_lease(self.f.authority, self.request) as lease:
                self.submit_public()
                lease.prepare_restore_attempt(None, query_attempted=True)
                with self.assertRaises(g.Refused):
                    lease.prepare_restore_attempt(None, query_attempted=True)
                self.call('StartItemUpdate', (570, 42), 11)
                with self.assertRaises(g.Refused):
                    self.call('SetItemVisibility', (11, 0), True)
        self.assertIsNotNone(g.read_json(self.f.state)[0]['pending'])

    def test_stale_parent_never_grants_capability_or_writes_intent(self):
        before = self.f.state.read_bytes()
        with self.assertRaises(g.Refused):
            with g.visibility_test_lease(self.f.authority, dict(self.request, generation=99)):
                self.fail('entered stale lease')
        self.assertEqual(self.f.state.read_bytes(), before)

    def test_normal_release_still_refuses_public(self):
        with self.assertRaisesRegex(g.Refused, 'not_completed'):
            with g.release_lease(self.f.authority, self.f.request):
                self.call('StartItemUpdate', (570, 42), 10)
                with self.assertRaisesRegex(g.Refused, 'unlisted'):
                    self.call('SetItemVisibility', (10, 0), True)

    def test_protected_text_and_resources_cannot_drift(self):
        before = {k: k for k in (*v.PROTECTED, 'description')}
        before['visibility'] = 3
        public = dict(before, visibility=0)
        v.verify_snapshot(before, public, 0)
        for key in ('description', 'title', 'content_file', 'tags', 'preview_url'):
            with self.subTest(key=key), self.assertRaises(g.Refused):
                v.verify_snapshot(before, {**public, key: 'changed'}, 0)

    def run_mock_sdk(self, *, public_query_error=False, callback_unknown=False):
        report = self.f.root / 'report'
        report.mkdir()
        request = {k: value for k, value in self.request.items() if k != 'request_sha256'}
        (report / 'request.json').write_bytes(g.canonical(request))
        request_sha = g.sha((report / 'request.json').read_bytes())
        calls = []
        active = [0]
        outer = self
        class FakeSteam:
            def __enter__(self):
                active[0] += 1
                return self
            def __exit__(self, *args): active[0] -= 1
            def ug(self, suffix, result_type, arg_types, *args):
                calls.append((suffix, args))
                result = len(calls) + 100 if suffix != 'SetItemVisibility' else True
                outer.call(suffix, args, result)
                return result
            def wait(self, *args, **kwargs):
                if callback_unknown and len(calls) == 3:
                    raise TimeoutError('simulated callback timeout')
                return SimpleNamespace(result=1, item=42, legal=False)
        snapshot = {k: k for k in (*v.PROTECTED, 'description')}
        snapshot.update(item='42', visibility=3)
        results = [snapshot, snapshot, TimeoutError('simulated readback failure')
                   if public_query_error else dict(snapshot, visibility=0), snapshot, snapshot]
        sdk = SimpleNamespace(Steam=FakeSteam, APP=570, Submitted=object())
        def stop_after_sdk_shutdown(*args):
            self.assertEqual(active[0], 0, 'SDK must be released during observation')
            return True
        with patch.dict(sys.modules, steam_workshop_upload=sdk), patch.object(v, 'fresh_item',
                side_effect=results), patch.object(v, 'early_restore', side_effect=stop_after_sdk_shutdown):
            receipt = v.run(self.f.authority, report, request_sha)
        self.assertEqual([args[1] for suffix, args in calls if suffix == 'SetItemVisibility'], [0, 3])
        self.assertIsNone(g.read_json(self.f.state)[0]['pending'])
        return receipt

    def test_unknown_public_callback_uses_readback_then_restores_once(self):
        receipt = self.run_mock_sdk(callback_unknown=True)
        self.assertEqual(receipt['public_callback']['outcome'], 'CALLBACK_UNKNOWN_NO_REPLAY')
        self.assertEqual(receipt['final_visibility'], 3)

    def test_readback_exception_still_executes_inverse_update(self):
        receipt = self.run_mock_sdk(public_query_error=True)
        self.assertIn('TimeoutError', receipt['test_error'])
        self.assertEqual(receipt['status'], 'VISIBILITY_TEST_RESTORED_UNLISTED')

    def test_retest_carries_prior_exposure_and_closed_authorization_refuses_reuse(self):
        receipt = self.run_mock_sdk()
        state, _ = g.read_json(self.f.state)
        budget = v.authorization_budget(state)
        self.assertEqual(budget['public_seconds_before'], receipt['public_to_verified_restore_seconds'])
        self.assertEqual(budget['previous_receipt'], state['last_visibility_test_receipt'])
        path = Path(state['last_visibility_test_receipt']['path'])
        receipt['authorization_closed'] = True
        path.write_bytes(g.canonical(receipt))
        state['last_visibility_test_receipt']['sha256'] = g.sha(path.read_bytes())
        with self.assertRaisesRegex(g.Refused, 'authorization_already_closed'):
            v.authorization_budget(state)


if __name__ == '__main__':
    unittest.main()
