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
ERROR_CODE = re.compile(r'[a-z][a-z0-9_]{0,63}\Z')
PRIVATE_IDENTIFIER = re.compile(r'[0-9]{8,}|[a-f0-9]{32,}')
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


def safe_error_code(value, fallback='error_unavailable'):
    """Keep short machine codes, never an account ID, digest or bearer value."""
    if (type(value) is not str or not ERROR_CODE.fullmatch(value)
            or PRIVATE_IDENTIFIER.search(value)
            or value.startswith(('lt1_', 'bearer_', 'sk_', 'access_token_', 'refresh_token_'))):
        return fallback
    return value


def http_error_label(status, value):
    status = status if type(status) is int and 100 <= status <= 599 else 0
    code = safe_error_code(value.get('error') if type(value) is dict else None)
    return 'http_' + str(status) + ':' + code


def failure_label(error, fallback='invalid_response'):
    code = str(error)
    match = re.fullmatch(r'http_([0-9]{1,3}):([a-z][a-z0-9_]{0,63})', code)
    if match:
        return http_error_label(int(match[1]), {'error': match[2]})
    return safe_error_code(code, fallback)


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


INCOMPLETE_KINDS = ('greenlet_exit', 'stop_user', 'cleanup_timeout',
                    'keyboard_interrupt', 'system_exit', 'other')
INCOMPLETE_NAMES = {'GreenletExit': 'greenlet_exit', 'StopUser': 'stop_user',
                    'CleanupTimeout': 'cleanup_timeout', 'KeyboardInterrupt': 'keyboard_interrupt',
                    'SystemExit': 'system_exit'}


# Public fixed route IDs only. Unknown targets share ID0; user-controlled
# paths, queries, account IDs and authorization never enter this report.
_ROUTE_KEYS = tuple(sorted({('POST', path) for path in BUSINESS_PATHS} | {
    ('GET', '/_loadtest/context'), ('POST', '/_loadtest/identity'),
    ('POST', '/_loadtest/ready'), ('POST', '/_loadtest/release'),
    ('POST', '/_loadtest/abort')}))
_ROUTE_IDS = {key: index + 1 for index, key in enumerate(_ROUTE_KEYS)}
_ROUTE_BUCKETS = (128, 512, 1024, 4096, 16384, 65536, codec.MAX_BYTES)
_ROUTE_SUM_FIELDS = ('requests', 'responses', 'body_bytes', 'non_200_responses', 'parsed_http_errors',
                     'decode_failures', 'decode_wall_ns', 'incomplete_exchanges')
_ROUTE_MAX_FIELDS = ('max_body_bytes', 'max_decode_wall_ns')
_ROUTE_FIELDS = frozenset(('id', 'body_histogram') + _ROUTE_SUM_FIELDS + _ROUTE_MAX_FIELDS)


class RouteByteStats:
    """O(1) expected updates, O(R*8) memory; R<=fixed public route count+1.

    Setup creates immutable route indexes once. Each response updates exactly
    one row and <=7 size comparisons, reusing the existing decode clock.
    Snapshot/merge cost O(R*8), only at explicit reporting; no timer, user scan,
    network/DB call, payload capture or per-account cache.
    """
    def __init__(self):
        self.rows = {}

    def row(self, method, path):
        identity = _ROUTE_IDS.get((method, path), 0)
        row = self.rows.get(identity)
        if row is None:
            row = dict.fromkeys(_ROUTE_SUM_FIELDS + _ROUTE_MAX_FIELDS, 0)
            row.update(id=identity, body_histogram=[0] * (len(_ROUTE_BUCKETS) + 1))
            self.rows[identity] = row
        return row

    def request(self, method, path):
        self.row(method, path)['requests'] += 1

    def response(self, method, path, raw, status):
        row = self.row(method, path)
        size = len(raw) if type(raw) is bytes else 0
        row['responses'] += 1
        row['body_bytes'] += size
        row['max_body_bytes'] = max(row['max_body_bytes'], size)
        row['non_200_responses'] += int(status != 200)
        bucket = 0
        while bucket < len(_ROUTE_BUCKETS) and size > _ROUTE_BUCKETS[bucket]:
            bucket += 1
        row['body_histogram'][bucket] += 1
        return row

    def report(self):
        return {'kind': 'ROUTE_WIRE_BYTES_V1',
                'route_table': [[index + 1, *key] for index, key in enumerate(_ROUTE_KEYS)],
                'bucket_upper_bytes': list(_ROUTE_BUCKETS),
                'rows': [{**row, 'body_histogram': list(row['body_histogram'])}
                         for _, row in sorted(self.rows.items())],
                'scope': 'completed HTTP response bodies; no headers, TLS/SSH, payloads or account identifiers; includes setup/ramp/finalization',
                'p95_is_bucket_upper_bound_not_exact_quantile': True}


def _aggregate_route_bytes(reports, wire_counts, incomplete_counts):
    if not any(value is not None for value in reports):
        return None  # Legacy/default-off reports keep exactly their old shape.
    merged = RouteByteStats()
    expected = merged.report()
    expected_keys = set(expected)
    for report in reports:
        if (type(report) is not dict or set(report) != expected_keys
                or any(report[key] != expected[key] for key in expected_keys - {'rows'})
                or type(report['rows']) is not list or len(report['rows']) > len(_ROUTE_KEYS) + 1):
            raise ValueError('loadtest_route_bytes_report_invalid')
        seen = set()
        for row in report['rows']:
            if (type(row) is not dict or set(row) != _ROUTE_FIELDS
                    or any(type(row[key]) is not int or row[key] < 0
                           for key in _ROUTE_SUM_FIELDS + _ROUTE_MAX_FIELDS + ('id',))
                    or row['id'] > len(_ROUTE_KEYS) or row['id'] in seen
                    or type(row['body_histogram']) is not list
                    or len(row['body_histogram']) != len(_ROUTE_BUCKETS) + 1
                    or any(type(n) is not int or n < 0 for n in row['body_histogram'])
                    or sum(row['body_histogram']) != row['responses']
                    or row['responses'] > row['requests']
                    or row['non_200_responses'] > row['responses']
                    or row['parsed_http_errors'] > row['non_200_responses']
                    or row['decode_failures'] > row['responses']
                    or row['max_body_bytes'] > row['body_bytes']
                    or row['max_decode_wall_ns'] > row['decode_wall_ns']
                    or row['responses'] + row['incomplete_exchanges'] > row['requests']):
                raise ValueError('loadtest_route_bytes_row_invalid')
            seen.add(row['id'])
            target = merged.rows.setdefault(row['id'], dict.fromkeys(_ROUTE_SUM_FIELDS + _ROUTE_MAX_FIELDS, 0))
            target.setdefault('id', row['id'])
            target.setdefault('body_histogram', [0] * (len(_ROUTE_BUCKETS) + 1))
            for key in _ROUTE_SUM_FIELDS:
                target[key] += row[key]
            for key in _ROUTE_MAX_FIELDS:
                target[key] = max(target[key], row[key])
            for index, amount in enumerate(row['body_histogram']):
                target['body_histogram'][index] += amount
    for key, original in [('requests', 'requests'), ('responses', 'responses'),
                          ('body_bytes', 'response_body_bytes'), ('parsed_http_errors', 'http_error_responses'),
                          ('decode_failures', 'invalid_responses'), ('decode_wall_ns', 'decode_wall_ns')]:
        if sum(row[key] for row in merged.rows.values()) != wire_counts[original]:
            raise ValueError('loadtest_route_bytes_totals_unsettled')
    if sum(row['incomplete_exchanges'] for row in merged.rows.values()) != sum(incomplete_counts.values()):
        raise ValueError('loadtest_route_bytes_incomplete_unsettled')
    if max((row['max_decode_wall_ns'] for row in merged.rows.values()), default=0) != wire_counts['max_decode_wall_ns']:
        raise ValueError('loadtest_route_bytes_decode_max_unsettled')
    return merged.report()


def profile_cache_header(state):
    if (type(state) is dict and type(state.get('hash')) is str
            and re.fullmatch('[0-9a-f]{64}', state['hash']) and type(state.get('snapshot')) is dict):
        return 'v1:' + state['hash']
    return 'v1'


def _profile_cache_clone(value):
    nodes, expanded_bytes = 0, 0
    def copy(current, depth):
        nonlocal nodes, expanded_bytes
        nodes += 1
        if nodes > 100000 or depth > 64:
            raise ValueError('loadtest_profile_cache_budget')
        if type(current) is str:
            expanded_bytes += 6 * len(current.encode('utf8')) + 2
        elif type(current) is bool:
            expanded_bytes += 5
        elif current is None:
            expanded_bytes += 4
        elif type(current) in (int, float):
            expanded_bytes += 64
        elif type(current) not in (dict, list):
            raise ValueError('loadtest_profile_cache_value')
        if expanded_bytes > 1024 * 1024:
            raise ValueError('loadtest_profile_cache_budget')
        if type(current) is dict:
            result = {}
            for key, child in current.items():
                expanded_bytes += 6 * len(key.encode('utf8')) + 4
                result[key] = copy(child, depth + 1)
            return result
        if type(current) is list:
            expanded_bytes += 2 + len(current)
            return [copy(child, depth + 1) for child in current]
        return current
    return copy(value, 0)


def decode_profile_cache(value, baseline):
    """Same optional read contract as gameLua; no persistent/global cache.

    The caller pins one authenticated user's baseline for this attempt. The
    decoder returns a detached full value and a separately owned next baseline.
    A complete legacy reply stays valid; invalid/missing same baselines fail
    conservatively here (the game independently tests one bounded read recovery).
    """
    if type(value) is not dict:
        raise ValueError('loadtest_profile_cache_invalid')
    if '_hp' not in value:
        return value, None, 'legacy'
    marker = value['_hp']
    if (type(marker) is not list or len(marker) != 3 or type(marker[0]) is not int
            or marker[0] != 1 or type(marker[1]) is not str
            or not re.fullmatch('[0-9a-f]{64}', marker[1])
            or type(marker[2]) is not int or marker[2] not in (0, 1)):
        raise ValueError('loadtest_profile_cache_invalid')
    if marker[2] == 1:
        if set(value) != {'_hp'}:
            raise ValueError('loadtest_profile_cache_invalid')
        if (type(baseline) is not dict or baseline.get('hash') != marker[1]
                or type(baseline.get('snapshot')) is not dict):
            raise ValueError('loadtest_profile_cache_miss')
        return _profile_cache_clone(baseline['snapshot']), baseline, 'unchanged'
    result = {key: child for key, child in value.items() if key != '_hp'}
    try:
        next_state = {'hash': marker[1], 'snapshot': _profile_cache_clone(result)}
    except (ValueError, RecursionError):
        next_state = None
    return result, next_state, 'full'


def decode_profile_cache_seed(value):
    # A full checkpoint remains complete even if optional cache metadata fails.
    if type(value) is not dict or '_hp' not in value:
        return value, None, 'legacy_seed'
    result = {key: child for key, child in value.items() if key != '_hp'}
    marker = value['_hp']
    if (type(marker) is not list or len(marker) != 3 or type(marker[0]) is not int
            or marker[0] != 1 or type(marker[1]) is not str
            or not re.fullmatch('[0-9a-f]{64}', marker[1])
            or type(marker[2]) is not int or marker[2] != 2
            or value.get('ok') is not True or type(value.get('profile')) is not dict):
        return result, None, 'seed_ignored'
    try:
        state = {'hash': marker[1], 'snapshot': _profile_cache_clone(value['profile'])}
    except (ValueError, RecursionError):
        return result, None, 'seed_ignored'
    return result, state, 'seed'


_CACHE_STAT_KEYS = ('responses', 'full', 'unchanged', 'legacy', 'seed',
                    'legacy_seed', 'seed_ignored', 'errors')


class WireClient:
    def __init__(self, mode=WIRE_MODE, *, measure_routes=False):
        if mode not in MODES:
            raise ValueError('loadtest_wire_mode_invalid')
        if type(measure_routes) is not bool:
            raise ValueError('loadtest_route_bytes_mode_invalid')
        self._routes = RouteByteStats() if measure_routes else None
        self.mode = mode
        self._counts = dict.fromkeys(COUNTERS, 0)
        self._incomplete = dict.fromkeys(INCOMPLETE_KINDS, 0)
        self._cache_stats = dict.fromkeys(_CACHE_STAT_KEYS, 0)

    @staticmethod
    def business(method, path):
        return method == 'POST' and path in BUSINESS_PATHS

    def headers(self, method, path, authorization):
        business = self.business(method, path)
        if self._routes is not None:
            self._routes.request(method, path)
        self._counts['requests'] += 1
        self._counts['business_requests' if business else 'control_requests'] += 1
        headers = {'Authorization': authorization, 'Content-Type': 'application/json'}
        if business and self.mode == WIRE_MODE:
            headers[codec.HEADER] = codec.SCHEMA_HASH
            self._counts['negotiated_requests'] += 1
        return headers

    def decode(self, method, path, raw, status=200, *, request_body=None, profile_context=None):
        """Decode once. Any malformed/ambiguous result fails without resending."""
        counts = self._counts
        if profile_context is not None:
            self._cache_stats['responses'] += 1
        route_row = None if self._routes is None else self._routes.response(method, path, raw, status)
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
                if route_row is not None:
                    route_row['parsed_http_errors'] += 1
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
            if profile_context is not None:
                if method != 'POST' or path not in ('/v1/profile', '/v1/online-time/checkpoint') or status != 200 or type(profile_context) is not dict:
                    raise ValueError('loadtest_profile_cache_scope')
                if path == '/v1/profile':
                    value, next_state, kind = decode_profile_cache(value, profile_context.get('baseline'))
                else:
                    value, next_state, kind = decode_profile_cache_seed(value)
                self._cache_stats[kind] += 1
                profile_context.update(next_state=next_state, kind=kind)
            return value
        except Exception:
            if profile_context is not None:
                self._cache_stats['errors'] += 1
            if route_row is not None:
                route_row['decode_failures'] += 1
            counts['invalid_responses'] += 1
            raise
        finally:
            elapsed = time.perf_counter_ns() - started
            counts['decode_wall_ns'] += elapsed
            counts['max_decode_wall_ns'] = max(counts['max_decode_wall_ns'], elapsed)
            if route_row is not None:
                route_row['decode_wall_ns'] += elapsed
                route_row['max_decode_wall_ns'] = max(route_row['max_decode_wall_ns'], elapsed)

    def note_incomplete(self, error, method=None, path=None):
        # Fixed enum only: never serialize an exception message, token or URL.
        self._incomplete[INCOMPLETE_NAMES.get(type(error).__name__, 'other')] += 1
        if self._routes is not None:
            self._routes.row(method, path)['incomplete_exchanges'] += 1

    def report(self):
        return {**({'route_bytes_v1': self._routes.report()} if self._routes is not None else {}),
                **({'profile_cache_v1': dict(self._cache_stats)} if self._cache_stats['responses'] else {}),
                'mode': self.mode, 'schema_hash': codec.SCHEMA_HASH,
                'decoder': 'production_player_web_auth.business_wire.decode',
                'profile_refs_decoder': 'production_lua_contract_v1_v2_bounded',
                'counters': dict(self._counts),
                'incomplete_exchanges': dict(self._incomplete),
                'counter_scope': 'entire_process_including_rampup_and_finalization_not_locust_reset_stats',
                'timing_scope': 'client_parse_and_decode_wall_time_not_server_time'}


def aggregate_reports(reports, mode):
    """O(worker count * fixed counters), independent of the player population."""
    total = dict.fromkeys(COUNTERS, 0)
    incomplete = dict.fromkeys(INCOMPLETE_KINDS, 0)
    route_reports = []
    cache_stats = dict.fromkeys(_CACHE_STAT_KEYS, 0)
    cache_observed = False
    for report in reports:
        if (type(report) is not dict or report.get('mode') != mode
                or report.get('schema_hash') != codec.SCHEMA_HASH
                or type(report.get('counters')) is not dict
                or set(report['counters']) != set(COUNTERS)):
            raise ValueError('loadtest_worker_wire_report_invalid')
        route_reports.append(report.get('route_bytes_v1'))
        cache = report.get('profile_cache_v1')
        if cache is not None:
            if (type(cache) is not dict or set(cache) != set(_CACHE_STAT_KEYS)
                    or any(type(n) is not int or n < 0 for n in cache.values())
                    or cache['responses'] != sum(cache[key] for key in _CACHE_STAT_KEYS if key != 'responses')
                    or cache['responses'] > report['counters'].get('responses', -1)
                    or cache['errors'] > report['counters'].get('invalid_responses', -1)):
                raise ValueError('loadtest_profile_cache_statistics_invalid')
            cache_observed = True
            for key in _CACHE_STAT_KEYS:
                cache_stats[key] += cache[key]

        value = report.get('incomplete_exchanges', dict.fromkeys(INCOMPLETE_KINDS, 0))
        if (type(value) is not dict or set(value) != set(INCOMPLETE_KINDS)
                or any(type(item) is not int or item < 0 for item in value.values())):
            raise ValueError('loadtest_incomplete_exchange_report_invalid')
        for name in INCOMPLETE_KINDS:
            incomplete[name] += value[name]
        for name in COUNTERS:
            value = report['counters'][name]
            if type(value) is not int or value < 0:
                raise ValueError('loadtest_worker_wire_counter_invalid')
            total[name] = max(total[name], value) if name == 'max_decode_wall_ns' else total[name] + value
    result = WireClient(mode).report()
    result['counters'] = total
    result['incomplete_exchanges'] = incomplete
    routes = _aggregate_route_bytes(route_reports, total, incomplete)
    if routes is not None:
        result['route_bytes_v1'] = routes
    if cache_observed:
        result['profile_cache_v1'] = cache_stats
    return result
