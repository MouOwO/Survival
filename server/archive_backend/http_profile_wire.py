"""Lossless references within one authenticated HTTP reply, never a save delta.

Only an explicit v1/v2 consumer receives references. Equality includes JSON types,
so false is never replaced by 0. No client baseline, cache, database access or
timer is used. Init/idle O(1); each low-frequency response costs O(B+R) for B
bytes and at most 256 daily rows (currently 40), with shallow container copies.
V2 removes the exact rows/by_key duplicate, independent of local configuration.
A packing failure preserves a valid v1/full committed reply.
"""
import json
import re

CAPABILITY = 'archive_profile_refs_v1'
CAPABILITY_V2 = 'archive_profile_refs_v2'
MARKER = '_http_profile_refs'
ACCOUNT_FIELDS = ('schema_version', 'account_id', 'revision', 'entitlements',
                  'achievements', 'save', 'public')
ROOT_DAILY = 128
PROGRESSION_DAILY = 256
DAILY_ROWS = 512
MAX_DAILY_ROWS = 256
_DAILY_KEY = re.compile(r'[a-z][a-z0-9_]{0,95}\Z')


def _same(left, right, depth=0):
    if depth > 64 or type(left) is not type(right):
        return False
    if isinstance(left, dict):
        return (left.keys() == right.keys()
                and all(_same(value, right[key], depth + 1) for key, value in left.items()))
    if isinstance(left, list):
        return (len(left) == len(right)
                and all(_same(a, b, depth + 1) for a, b in zip(left, right)))
    return left == right


def _field_bytes(key, value):
    # Account for one removed comma/key/value; actual output is compact UTF-8.
    return len(json.dumps({key: value}, ensure_ascii=False, allow_nan=False,
                          separators=(',', ':')).encode('utf-8')) - 1


def _pack_v1(payload, response):
    capabilities = payload.get('response_capabilities') if isinstance(payload, dict) else None
    if (type(capabilities) is not dict or capabilities.get(CAPABILITY) is not True
            or not isinstance(response, dict) or MARKER in response):
        return response
    profile = response.get('profile')
    if not isinstance(profile, dict):
        return response
    try:
        result = dict(response)
        view = dict(profile)
        mask, saved = 0, 0
        account = profile.get('account_profile')
        if isinstance(account, dict):
            compact_account = dict(account)
            for index, key in enumerate(ACCOUNT_FIELDS):
                if key in account and key in profile and _same(account[key], profile[key]):
                    # A last field has no removable comma. Use the smaller
                    # bound so a marginal response can never grow.
                    saved += _field_bytes(key, compact_account.pop(key)) - 1
                    mask += 1 << index
            view['account_profile'] = compact_account
        daily = profile.get('daily_limits')
        if isinstance(daily, dict):
            if 'daily_limits' in response and _same(response['daily_limits'], daily):
                saved += _field_bytes('daily_limits', result.pop('daily_limits')) - 1
                mask += ROOT_DAILY
            progression = profile.get('progression')
            if (isinstance(progression, dict) and 'daily_limits' in progression
                    and _same(progression['daily_limits'], daily)):
                compact_progression = dict(progression)
                saved += _field_bytes('daily_limits', compact_progression.pop('daily_limits')) - 1
                view['progression'] = compact_progression
                mask += PROGRESSION_DAILY
        marker = {'v': 1, 'm': mask}
        if mask == 0 or saved <= _field_bytes(MARKER, marker):
            return response
        result['profile'] = view
        result[MARKER] = marker
        return result
    except (ValueError, TypeError, OverflowError, RecursionError):
        # Optional transport optimisation cannot turn a durable grant into an
        # apparent failed transaction. Legacy bytes remain valid for v1 clients.
        return response


def _pack_daily_rows(response):
    profile = response.get('profile')
    daily = profile.get('daily_limits') if isinstance(profile, dict) else None
    if not isinstance(daily, dict):
        return response
    rows, index = daily.get('rows'), daily.get('by_key')
    if (type(rows) is not list or not 1 <= len(rows) <= MAX_DAILY_ROWS
            or type(index) is not dict):
        return response
    expected = {}
    for row in rows:
        key = row.get('key') if type(row) is dict else None
        if type(key) is not str or not _DAILY_KEY.fullmatch(key) or key in expected:
            return response
        expected[key] = row
    if not _same(index, expected):
        return response  # Extra/index-only fields and JSON type differences survive.
    old_marker = response.get(MARKER)
    mask = old_marker['m'] if old_marker is not None else 0
    marker = {'v': 2, 'm': mask + DAILY_ROWS}
    marker_cost = _field_bytes(MARKER, marker)
    if old_marker is not None:
        marker_cost -= _field_bytes(MARKER, old_marker)
    # rows remains in this object, so removing by_key also removes one comma.
    # Keep a one-byte safety margin for compact JSON accounting.
    if _field_bytes('by_key', index) - 1 <= marker_cost:
        return response
    result = dict(response)
    result['profile'] = dict(profile)
    result['profile']['daily_limits'] = dict(daily)
    del result['profile']['daily_limits']['by_key']
    result[MARKER] = marker
    return result


def pack(payload, response):
    capabilities = payload.get('response_capabilities') if isinstance(payload, dict) else None
    if type(capabilities) is not dict or capabilities.get(CAPABILITY_V2) is not True:
        return _pack_v1(payload, response)
    if not isinstance(response, dict) or MARKER in response:
        return response
    # V2 includes v1 decoding. An old server can still return v1 or full JSON;
    # this local capability copy never changes the caller or business payload.
    local_payload = dict(payload, response_capabilities=dict(capabilities, archive_profile_refs_v1=True))
    base = _pack_v1(local_payload, response)
    try:
        return _pack_daily_rows(base)
    except (ValueError, TypeError, OverflowError, RecursionError):
        return base
