"""Lossless references within one authenticated HTTP reply, never a save delta.

Only an explicit v1 consumer receives references. Equality includes JSON types,
so false is never replaced by 0. No client baseline, cache, database access or
timer is used. Init/idle O(1); each low-frequency response costs O(B) comparisons
and size accounting for its B bytes, with shallow O(K) container copies. A
packing failure preserves the original committed reply.
"""
import json

CAPABILITY = 'archive_profile_refs_v1'
MARKER = '_http_profile_refs'
ACCOUNT_FIELDS = ('schema_version', 'account_id', 'revision', 'entitlements',
                  'achievements', 'save', 'public')
ROOT_DAILY = 128
PROGRESSION_DAILY = 256


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


def pack(payload, response):
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
