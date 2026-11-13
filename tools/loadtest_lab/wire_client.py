"""Bounded client for the real, exactly negotiated business-response codec.

The production schema and indexes are imported once per process: O(S) setup.
Header selection and fixed counters are O(1); a response is O(B + sum K log K)
for the real decoder, O(B+N) space, with the same byte/node/depth bounds.
No timer, player scan, network request, or transaction retry is added here.
"""
from __future__ import annotations

import json
import math
import re
import time

try:
    from player_web_auth import business_wire as codec
except ModuleNotFoundError as error:
    if error.name != 'player_web_auth':
        raise
    from server.player_web_auth import business_wire as codec


WIRE_MODE = 'business-wire-v1'
LEGACY_MODE = 'legacy-json'
MODES = frozenset((WIRE_MODE, LEGACY_MODE))
PROFILE_CAPABILITIES = ('archive_profile_refs_v1', 'archive_profile_refs_v2')
PROFILE_MARKER = '_http_profile_refs'
ACCOUNT_FIELDS = ('schema_version', 'account_id', 'revision', 'entitlements',
                  'achievements', 'save', 'public')
DAILY_KEY = re.compile(r'[a-z][a-z0-9_]{0,95}\Z')
BUSINESS_PATHS = frozenset((
    '/v1/session/authenticate', '/v1/session/login', '/v1/profile',
    '/v1/archive/config', '/v1/lottery/catalog', '/v1/lottery/snapshot',
    '/v1/archive/command', '/v1/archive/endless-batch', '/v1/online-time/checkpoint',
))
COUNTERS = (
    'requests', 'business_requests', 'control_requests', 'negotiated_requests',
    'responses', 'response_body_bytes', 'packed_responses', 'packed_body_bytes',
    'plain_fallback_responses', 'plain_fallback_body_bytes',
    'legacy_json_responses', 'control_responses', 'http_error_responses',
    'profile_refs_v1_responses', 'profile_refs_v2_responses',
    'invalid_responses', 'decode_wall_ns', 'max_decode_wall_ns',
)


def _unique(pairs):
    value = {}
    for key, child in pairs:
        if key in value:
            raise ValueError('loadtest_response_duplicate_key')
        value[key] = child
    return value


def _nonfinite(_):
    raise ValueError('loadtest_response_nonfinite_number')


def _plain_budget(value):
    count = 0

    def visit(current, depth):
        nonlocal count
        count += 1
        if depth > codec.MAX_DEPTH or count > codec.MAX_NODES:
            raise ValueError('loadtest_plain_response_budget_exceeded')
        if type(current) is dict:
            for child in current.values():
                visit(child, depth + 1)
        elif type(current) is list:
            for child in current:
                visit(child, depth + 1)
        elif type(current) is float and not math.isfinite(current):
            raise ValueError('loadtest_response_nonfinite_number')

    visit(value, 0)
    return count


def decode_profile_refs(value, capabilities):
    """The real Lua consumer's same-response v1/v2 reference contract.

    At most seven account fields and two daily views are reconstructed, plus
    at most 256 daily row keys. Copies are bounded globally and atomic to the
    parsed input. No cross-message cache or persistent player state is used.
    """
    if type(value) is not dict or PROFILE_MARKER not in value:
        return value, 0
    marker = value[PROFILE_MARKER]
    if (type(marker) is not dict or set(marker) != {'v', 'm'}
            or type(marker['v']) not in (int, float) or marker['v'] not in (1, 2)
            or type(marker['m']) not in (int, float) or not 1 <= marker['m'] <= 1023
            or marker['m'] != math.floor(marker['m'])):
        raise ValueError('http_profile_wire_invalid')
    version, mask = int(marker['v']), int(marker['m'])
    if (type(capabilities) is not dict
            or not (capabilities.get(PROFILE_CAPABILITIES[version - 1]) is True
                    or version == 1 and capabilities.get(PROFILE_CAPABILITIES[1]) is True)):
        raise ValueError('loadtest_profile_refs_not_negotiated')
    if not (1 <= mask <= 511 if version == 1 else 512 <= mask <= 1023):
        raise ValueError('http_profile_wire_invalid')
    profile = value.get('profile')
    if type(profile) is not dict:
        raise ValueError('http_profile_wire_invalid')
    count = _plain_budget(value)

    def clone(current, depth=0):
        nonlocal count
        count += 1
        if depth > codec.MAX_DEPTH or count > codec.MAX_NODES:
            raise ValueError('loadtest_profile_refs_expansion_budget_exceeded')
        if type(current) is dict:
            return {key: clone(child, depth + 1) for key, child in current.items()}
        if type(current) is list:
            return [clone(child, depth + 1) for child in current]
        return current

    result = dict(value)
    view = dict(profile)
    result['profile'] = view
    for key in ('account_profile', 'progression'):
        if type(profile.get(key)) is dict:
            view[key] = dict(profile[key])
    if version == 2:
        daily = profile.get('daily_limits')
        rows = daily.get('rows') if type(daily) is dict else None
        if (type(daily) is not dict or 'by_key' in daily or type(rows) is not list
                or not 1 <= len(rows) <= 256):
            raise ValueError('http_profile_wire_invalid')
        seen = set()
        for row in rows:
            key = row.get('key') if type(row) is dict else None
            if type(key) is not str or not DAILY_KEY.fullmatch(key) or key in seen:
                raise ValueError('http_profile_wire_invalid')
            seen.add(key)
        view['daily_limits'] = dict(daily)
        view['daily_limits']['by_key'] = {row['key']: clone(row) for row in rows}
        mask -= 512
    assignments = []
    account = view.get('account_profile')
    for index, key in enumerate(ACCOUNT_FIELDS):
        if mask & (1 << index):
            if type(account) is not dict or key in account or key not in view:
                raise ValueError('http_profile_wire_invalid')
            assignments.append((account, key, view[key]))
    if mask & (128 | 256) and type(view.get('daily_limits')) is not dict:
        raise ValueError('http_profile_wire_invalid')
    if mask & 128:
        if 'daily_limits' in result:
            raise ValueError('http_profile_wire_invalid')
        assignments.append((result, 'daily_limits', view['daily_limits']))
    if mask & 256:
        progression = view.get('progression')
        if type(progression) is not dict or 'daily_limits' in progression:
            raise ValueError('http_profile_wire_invalid')
        assignments.append((progression, 'daily_limits', view['daily_limits']))
    copies = [(target, key, clone(source)) for target, key, source in assignments]
    for target, key, restored in copies:
        target[key] = restored
    del result[PROFILE_MARKER]
    _plain_budget(result)
    if len(codec.canonical(result)) > codec.MAX_BYTES:
        raise ValueError('loadtest_profile_refs_expansion_budget_exceeded')
    return result, version


class WireClient:
    def __init__(self, mode=WIRE_MODE):
        if mode not in MODES:
            raise ValueError('loadtest_wire_mode_invalid')
        self.mode = mode
        self._counts = dict.fromkeys(COUNTERS, 0)

    @staticmethod
    def business(method, path):
        return method == 'POST' and path in BUSINESS_PATHS

    def headers(self, method, path, authorization):
        business = self.business(method, path)
        self._counts['requests'] += 1
        self._counts['business_requests' if business else 'control_requests'] += 1
        headers = {'Authorization': authorization, 'Content-Type': 'application/json'}
        if business and self.mode == WIRE_MODE:
            headers[codec.HEADER] = codec.SCHEMA_HASH
            self._counts['negotiated_requests'] += 1
        return headers

    def decode(self, method, path, raw, status=200, *, request_body=None):
        """Decode once. Any malformed/ambiguous result fails without resending."""
        counts = self._counts
        counts['responses'] += 1
        if type(raw) is bytes:
            counts['response_body_bytes'] += len(raw)
        started = time.perf_counter_ns()
        try:
            if type(raw) is not bytes or len(raw) > codec.MAX_BYTES:
                raise ValueError('loadtest_response_byte_budget_exceeded')
            try:
                value = json.loads(raw, object_pairs_hook=_unique, parse_constant=_nonfinite)
            except (json.JSONDecodeError, UnicodeError, RecursionError):
                raise ValueError('loadtest_response_json_invalid') from None
            business = self.business(method, path)
            if status != 200:
                counts['http_error_responses'] += 1
            if type(value) is dict and codec.MARKER in value:
                if not business or self.mode != WIRE_MODE or status != 200:
                    raise ValueError('loadtest_response_wire_not_negotiated')
                value = codec.decode(value)
                counts['packed_responses'] += 1
                counts['packed_body_bytes'] += len(raw)
            else:
                _plain_budget(value)
                if status == 200:
                    if not business:
                        counts['control_responses'] += 1
                    elif self.mode == WIRE_MODE:
                        counts['plain_fallback_responses'] += 1
                        counts['plain_fallback_body_bytes'] += len(raw)
                    else:
                        counts['legacy_json_responses'] += 1
            if type(value) is dict and PROFILE_MARKER in value:
                if not business or status != 200:
                    raise ValueError('loadtest_profile_refs_not_negotiated')
                capabilities = request_body.get('response_capabilities') if type(request_body) is dict else None
                value, version = decode_profile_refs(value, capabilities)
                counts['profile_refs_v' + str(version) + '_responses'] += 1
            return value
        except Exception:
            counts['invalid_responses'] += 1
            raise
        finally:
            elapsed = time.perf_counter_ns() - started
            counts['decode_wall_ns'] += elapsed
            counts['max_decode_wall_ns'] = max(counts['max_decode_wall_ns'], elapsed)

    def report(self):
        return {'mode': self.mode, 'schema_hash': codec.SCHEMA_HASH,
                'decoder': 'production_player_web_auth.business_wire.decode',
                'profile_refs_decoder': 'production_lua_contract_v1_v2_bounded',
                'counters': dict(self._counts),
                'counter_scope': 'entire_process_including_rampup_and_finalization_not_locust_reset_stats',
                'timing_scope': 'client_parse_and_decode_wall_time_not_server_time'}


def aggregate_reports(reports, mode):
    """O(worker count * fixed counters), independent of the player population."""
    total = dict.fromkeys(COUNTERS, 0)
    for report in reports:
        if (type(report) is not dict or report.get('mode') != mode
                or report.get('schema_hash') != codec.SCHEMA_HASH
                or type(report.get('counters')) is not dict
                or set(report['counters']) != set(COUNTERS)):
            raise ValueError('loadtest_worker_wire_report_invalid')
        for name in COUNTERS:
            value = report['counters'][name]
            if type(value) is not int or value < 0:
                raise ValueError('loadtest_worker_wire_counter_invalid')
            total[name] = max(total[name], value) if name == 'max_decode_wall_ns' else total[name] + value
    result = WireClient(mode).report()
    result['counters'] = total
    return result
