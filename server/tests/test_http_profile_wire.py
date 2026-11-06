"""Python producer -> production Lua decoder, without network or player writes."""
from copy import deepcopy
import json
import os
from pathlib import Path
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'server'))
sys.path.insert(0, str(ROOT / 'server/tests'))
from archive_backend.http_profile_wire import pack, MARKER, CAPABILITY

CAP = {'response_capabilities': {CAPABILITY: True}}


def fixture(mode='standard'):
    account = {'schema_version': 1, 'account_id': '100', 'revision': 25,
               'entitlements': {'pass': {'active': False}}, 'achievements': {},
               'save': {'content_inventory': {'lottery_ticket': 91},
                        'gameplay_stats': {'field_' + str(i): i for i in range(180)},
                        'archive': {'recent': [{'name': '示例物品', 'id': str(i)} for i in range(100)]}},
               'public': {'name': '测试账户'}}
    view = deepcopy(account)
    view.update(mode=mode, match_session_id='fixture-session-001', progression={'loaded': True},
                account_profile=deepcopy(account))
    if mode == 'pure':
        view['save'] = {'content_inventory': {'lottery_ticket': 1}, 'gameplay_stats': {'attack': 0}}
    daily = {'by_key': {'daily_' + str(i): {'current': i, 'limit': 100} for i in range(30)}}
    view['daily_limits'] = deepcopy(daily)
    view['progression']['daily_limits'] = deepcopy(daily)
    return {'ok': True, 'done': True, 'profile': view, 'daily_limits': daily,
            'response': {'ok': True, 'results': [{'id': 'fixture_item', 'count': 1}]}}


def size(value):
    return len(json.dumps(value, ensure_ascii=False, separators=(',', ':')).encode())


class HttpProfileWireTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.lua = os.environ.get('LUA_EXECUTABLE', 'C:/Program Files/lua/bin/lua5.1.exe')
        if not Path(cls.lua).is_file():
            raise RuntimeError('Real Lua interpreter is required')

    def decode_vectors(self, rows):
        result = subprocess.run([self.lua, 'tools/test_http_profile_wire.lua'], cwd=ROOT,
                                input=json.dumps(rows, ensure_ascii=False).encode('utf-8'),
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20)
        self.assertEqual(result.returncode, 0, result.stderr.decode('utf-8', errors='replace'))
        self.assertIn('HTTP_PROFILE_WIRE_VECTORS_PASS', result.stdout.decode())

    def test_standard_and_pure_round_trip_and_preserve_original(self):
        rows = []
        for mode in ('standard', 'pure'):
            original = fixture(mode)
            saved = deepcopy(original)
            packed = pack(CAP, original)
            self.assertEqual(original, saved)
            # Pure mode must retain its distinct authoritative account save.
            self.assertLess(size(packed), size(original) * (.85 if mode == 'pure' else .6))
            self.assertEqual(packed[MARKER]['v'], 1)
            if mode == 'pure':
                self.assertIn('save', packed['profile']['account_profile'])
            else:
                self.assertNotIn('save', packed['profile']['account_profile'])
            rows.append({'wire': packed, 'expected': original})
        self.decode_vectors(rows)

    def test_only_exact_boolean_capability_and_no_marker_collision(self):
        original = fixture()
        for capabilities in (None, {}, [], True, {CAPABILITY: 1}, {CAPABILITY: 'true'}, {CAPABILITY: False}):
            self.assertIs(pack({'response_capabilities': capabilities}, original), original)
        original[MARKER] = {'existing': True}
        self.assertIs(pack(CAP, original), original)

    def test_differences_false_zero_null_and_unknown_fields_are_lossless(self):
        original = fixture()
        original['profile']['public'] = {'one': True, 'nested': [None, 0, False]}
        original['profile']['account_profile']['public'] = {'one': 1, 'nested': [None, 0, False]}
        original['profile']['account_profile']['future_field'] = {'preserved': True}
        original['response']['future_response'] = [None, False, 0, '值']
        packed = pack(CAP, original)
        self.assertIn('public', packed['profile']['account_profile'])
        self.decode_vectors([{'wire': packed, 'expected': original}])

    def test_repeated_successes_replays_and_revision_order_have_no_baseline(self):
        rows = []
        for revision, tickets in ((50, 90), (51, 80), (51, 80), (49, 100), (1, 1)):
            original = fixture()
            original['profile']['revision'] = original['profile']['account_profile']['revision'] = revision
            for profile in (original['profile'], original['profile']['account_profile']):
                profile['save']['content_inventory']['lottery_ticket'] = tickets
            rows.append({'wire': pack(CAP, original), 'expected': original})
        self.decode_vectors(rows)

    def test_missing_profile_small_reply_and_failure_are_unchanged(self):
        for original in ({'ok': False, 'error': 'insufficient'}, {'ok': True},
                         {'profile': {'account_profile': {}}}):
            self.assertIs(pack(CAP, original), original)
        self.decode_vectors([{'wire': {'ok': False}, 'expected': {'ok': False}}])

    def test_small_marginal_payloads_never_grow(self):
        rows = []
        for length in range(0, 90, 3):
            account = {'public': {'caption': '字' * length}}
            original = {'profile': {**deepcopy(account), 'account_profile': deepcopy(account)}}
            packed = pack(CAP, original)
            self.assertLessEqual(size(packed), size(original))
            rows.append({'wire': packed, 'expected': original})
        self.decode_vectors(rows)

    def test_malformed_references_are_rejected_without_partial_mutation(self):
        valid = pack(CAP, fixture())
        rows = []
        for marker in ({'v': 2, 'm': 1}, {'v': 1, 'm': 0}, {'v': 1, 'm': 512},
                       {'v': 1, 'm': 1.5}, {'v': True, 'm': 1}, {'v': 1, 'm': True},
                       {'v': 1, 'm': 511, 'other': 1}, None, []):
            wire = deepcopy(valid)
            wire[MARKER] = marker
            rows.append({'wire': wire, 'invalid': True})
        for change in ('profile', 'account', 'daily', 'progression', 'overwrite'):
            wire = deepcopy(valid)
            if change == 'profile': wire['profile'] = None
            if change == 'account': wire['profile']['account_profile'] = None
            if change == 'daily': del wire['profile']['daily_limits']
            if change == 'progression': wire['profile']['progression'] = None
            if change == 'overwrite': wire['profile']['account_profile']['save'] = {'existing': True}
            rows.append({'wire': wire, 'invalid': True})
        self.decode_vectors(rows)

    def test_existing_mode_projection_hook_negotiates_without_business_change(self):
        from test_rich_match_modes import api_contract
        from types import SimpleNamespace
        module = api_contract()
        source = fixture()
        source['profile'].pop('account_profile')
        source['profile'].pop('daily_limits')
        source.pop('daily_limits')
        for mode in ('standard', 'pure', 'rich', 'cold', 'scourge'):
            context = {'mode': mode, 'match_session_id': 'fixture-session-001'}
            legacy = module.project(SimpleNamespace(), {}, source, context)
            packed = module.project(SimpleNamespace(), CAP, source, context)
            self.assertIn(MARKER, packed)
            self.decode_vectors([{'wire': packed, 'expected': legacy}])


if __name__ == '__main__':
    unittest.main()
