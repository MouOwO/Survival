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
from archive_backend.http_profile_wire import pack, MARKER, CAPABILITY, CAPABILITY_V2

CAP = {'response_capabilities': {CAPABILITY: True}}
CAP_V2 = {'response_capabilities': {CAPABILITY: True, CAPABILITY_V2: True}}


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


def daily_fixture(mode='standard', monthly=False):
    from archive_backend.bundle import Bundle
    from archive_backend.daily_limits import snapshot
    bundle = Bundle(ROOT / 'server/bundles/f8ab7087c042cc82f43555500e134262211062e78c88190b6691dcce57ebff42')
    source = fixture(mode)
    daily = snapshot({'save': {}, 'entitlements': {'archive_pass': {'active': monthly}}},
                     bundle, now=1793961863)
    source['profile']['daily_limits'] = deepcopy(daily)
    source['profile']['progression']['daily_limits'] = deepcopy(daily)
    source['daily_limits'] = deepcopy(daily)
    return source


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

    def test_v2_real_daily_config_all_modes_and_revision_order(self):
        rows = []
        for mode in ('standard', 'pure', 'rich', 'cold', 'scourge', 'ruins', 'celestial'):
            for monthly in (False, True):
                for revision in (50, 51, 51, 49, 1):
                    source = daily_fixture(mode, monthly)
                    source['profile']['revision'] = source['profile']['account_profile']['revision'] = revision
                    saved = deepcopy(source)
                    packed = pack(CAP_V2, source)
                    self.assertEqual(source, saved)
                    self.assertEqual(packed[MARKER]['v'], 2)
                    self.assertEqual(len(source['profile']['daily_limits']['rows']), 40)
                    self.assertGreater(size(pack(CAP, source)) - size(packed), 5800)
                    self.assertNotIn('by_key', packed['profile']['daily_limits'])
                    rows.append({'wire': packed, 'expected': source})
        self.decode_vectors(rows)

    def test_v2_negotiation_is_exact_and_v1_fallback_is_preserved(self):
        source = daily_fixture()
        legacy = pack(CAP, source)
        rows = [{'wire': legacy, 'expected': source}, {'wire': source, 'expected': source}]
        for value in (None, False, 0, 1, 'true', {}, []):
            request = {'response_capabilities': {CAPABILITY: True, CAPABILITY_V2: value}}
            self.assertEqual(pack(request, source), legacy)
        request = {'response_capabilities': {CAPABILITY_V2: True, 'unrelated': True}}
        saved = deepcopy(request)
        rows.append({'wire': pack(request, source), 'expected': source})
        self.assertEqual(request, saved)
        # An existing marker belongs to a previous encoder and must not be packed twice.
        already = pack(CAP_V2, source)
        self.assertIs(pack(CAP_V2, already), already)
        self.decode_vectors(rows)

    def test_v2_unknown_fields_types_and_nonmatching_indexes(self):
        source = daily_fixture()
        daily = source['profile']['daily_limits']
        daily['future'] = [False, None, 0, '保留']
        daily['rows'][0]['future'] = {'false': False, 'zero': 0, 'null': None}
        daily['by_key'][daily['rows'][0]['key']] = deepcopy(daily['rows'][0])
        rows = [{'wire': pack(CAP_V2, source), 'expected': source}]
        deep = deepcopy(source)
        node = deep
        for _ in range(70):
            node['unrelated'] = {}
            node = node['unrelated']
        rows.append({'wire': pack(CAP_V2, deep), 'expected': deep})
        for change in ('extra', 'missing', 'type', 'duplicate', 'too_many', 'bad_key', 'empty'):
            bad = deepcopy(source)
            daily = bad['profile']['daily_limits']
            if change == 'extra': daily['by_key']['extra'] = {'key': 'extra'}
            elif change == 'missing': daily['by_key'].pop(daily['rows'][0]['key'])
            elif change == 'type': daily['by_key'][daily['rows'][0]['key']]['future']['false'] = 0
            elif change == 'duplicate': daily['rows'].append(deepcopy(daily['rows'][0]))
            elif change == 'too_many': daily['rows'] *= 7
            elif change == 'empty': daily['rows'] = []; daily['by_key'] = {}
            else: daily['rows'][0]['key'] = 'INVALID'
            packed = pack(CAP_V2, bad)
            self.assertNotEqual(packed.get(MARKER, {}).get('v'), 2)
            rows.append({'wire': packed, 'expected': bad})
        self.decode_vectors(rows)

    def test_v2_daily_only_and_small_payloads_never_grow(self):
        rows = []
        for length in range(0, 90, 3):
            row = {'key': 'only', 'caption': '字' * length}
            source = {'profile': {'daily_limits': {'rows': [row], 'by_key': {'only': deepcopy(row)}}}}
            packed = pack(CAP_V2, source)
            self.assertLessEqual(size(packed), size(source))
            if MARKER in packed:
                self.assertEqual(packed[MARKER], {'v': 2, 'm': 512})
            rows.append({'wire': packed, 'expected': source})
        self.decode_vectors(rows)

    def test_v2_malformed_rows_and_late_v1_failure_are_atomic(self):
        valid = pack(CAP_V2, daily_fixture())
        rows = []
        for marker in ({'v': 2, 'm': 0}, {'v': 2, 'm': 511}, {'v': 2, 'm': 1024},
                       {'v': 2, 'm': 512.5}, {'v': 2, 'm': True},
                       {'v': 2, 'm': 512, 'future': True}, {'v': 3, 'm': 512}):
            bad = deepcopy(valid); bad[MARKER] = marker
            rows.append({'wire': bad, 'invalid': True})
        for change in ('overwrite', 'missing_rows', 'null_rows', 'object_rows', 'null_row',
                       'duplicate', 'bad_key', 'too_many', 'root_collision', 'account_collision', 'deep'):
            bad = deepcopy(valid)
            daily = bad['profile']['daily_limits']
            if change == 'overwrite': daily['by_key'] = {}
            elif change == 'missing_rows': del daily['rows']
            elif change == 'null_rows': daily['rows'] = None
            elif change == 'object_rows': daily['rows'] = {'1': daily['rows'][0]}
            elif change == 'null_row': daily['rows'][0] = None
            elif change == 'duplicate': daily['rows'].append(deepcopy(daily['rows'][0]))
            elif change == 'bad_key': daily['rows'][0]['key'] = 'INVALID'
            elif change == 'too_many': daily['rows'] *= 7
            elif change == 'root_collision': bad['daily_limits'] = {}
            elif change == 'account_collision': bad['profile']['account_profile']['save'] = {}
            else:
                node = daily['rows'][0]
                for _ in range(66): node['deep'] = {}; node = node['deep']
            rows.append({'wire': bad, 'invalid': True})
        self.decode_vectors(rows)

    def test_v2_projection_hook_keeps_modes_and_legacy_clients(self):
        from test_rich_match_modes import api_contract
        from types import SimpleNamespace
        module = api_contract()
        source = daily_fixture()
        source['profile'].pop('account_profile')
        for mode in ('standard', 'pure', 'rich', 'cold', 'scourge', 'ruins', 'celestial'):
            context = {'mode': mode, 'match_session_id': 'fixture-session-001'}
            legacy = module.project(SimpleNamespace(), {}, source, context)
            packed = module.project(SimpleNamespace(), CAP_V2, source, context)
            self.assertEqual(packed[MARKER]['v'], 2)
            self.decode_vectors([{'wire': packed, 'expected': legacy}])


if __name__ == '__main__':
    unittest.main()
