"""Opt-in unchanged read-profile replies, after complete authorization/SQL.

No server cache or business payload changes. Every negotiated response parses
O(B + sum(K log K)) bounded JSON canonicalization and hashes the complete snapshot; an unchanged reply avoids
encoding/transferring that same snapshot again. Init/idle O(1), temporary O(B)
space (plus bounded object-key sorting), no account scan, lock, timer, DB/RPC call or mutation retry.
"""
from __future__ import annotations
import hashlib
import json
import re

HEADER = 'X-Survival-Profile-Cache'
MARKER = '_hp'
MAX_BYTES = 8 * 1024 * 1024
_HEADER = re.compile(r'v1(?::([0-9a-f]{64}))?\Z')


def _unique(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('profile_cache_duplicate_key')
        result[key] = value
    return result


def _nonfinite(value):
    raise ValueError('profile_cache_nonfinite')


def _snapshot(value):
    return (type(value) is dict and value.get('ok') is not False
            and type(value.get('account_id')) is str and 1 <= len(value['account_id']) <= 128
            and type(value.get('match_session_id')) is str and 8 <= len(value['match_session_id']) <= 160
            and type(value.get('mode')) is str and 1 <= len(value['mode']) <= 32
            and type(value.get('revision')) is int and value['revision'] >= 0
            and type(value.get('save')) is dict)


def _fingerprint(value):
    # Canonical full-snapshot identity also permits a complete checkpoint's
    # profile to seed the next read. ALL values/types remain in the digest.
    canonical = json.dumps(value, ensure_ascii=False, allow_nan=False,
                           sort_keys=True, separators=(',', ':')).encode('utf8')
    return hashlib.sha256(canonical).hexdigest()


def prepare(body, advertised):
    """Called ONLY after successful authenticated POST /v1/profile.

    HTTP304 is not used for thisPOST API. Missing/duplicate/invalid negotiation,
    failures, reserved-marker collisions and oversized input retain full bytes.
    Hashing covers ALL snapshot fields, including account/session/mode and
    entitlements/day-dependent state, with no reliance on a revision counter.
    """
    if (type(body) is not bytes or not 256 <= len(body) <= MAX_BYTES - 128
            or type(advertised) is not str or len(advertised) > 67):
        return body, None
    match = _HEADER.fullmatch(advertised)
    if match is None:
        return body, None
    try:
        value = json.loads(body, object_pairs_hook=_unique, parse_constant=_nonfinite)
        if not _snapshot(value) or MARKER in value:
            return body, None
        digest = _fingerprint(value)
        if match.group(1) == digest:
            marker = [1, digest, 1]
            return b'{"_hp":[1,"' + digest.encode('ascii') + b'",1]}', {MARKER: marker}
        original = body.rstrip(b' \t\r\n')
        if not original.endswith(b'}'):
            return body, None
        # Retain the original JSON member order/numbers/Unicode representation.
        # Only a transport marker is appended; the fingerprint excludes it.
        marker = [1, digest, 0]
        return (original[:-1] + b',"_hp":[1,"' + digest.encode('ascii') + b'",0]}',
                {**value, MARKER: marker})
    except (ValueError, TypeError, OverflowError, RecursionError, UnicodeError):
        return body, None


def pack_bytes(body, advertised):
    """Compatibility wrapper for callers that need only transport bytes."""
    return prepare(body, advertised)[0]


def prepare_checkpoint_seed(body, advertised):
    """Augment a COMPLETE successful checkpoint; never omit any write result.

    Existing grants/profile/session/request fields remain byte-for-byte in the
    original JSON. Only an opt-in fingerprint of that included full profile is
    added. Malformed/legacy/failed replies retain their complete original bytes.
    No transaction, authorization, lookup, RPC or retry is introduced here.
    """
    if (type(body) is not bytes or not 256 <= len(body) <= MAX_BYTES - 128
            or type(advertised) is not str or len(advertised) > 67
            or _HEADER.fullmatch(advertised) is None):
        return body, None
    try:
        value = json.loads(body, object_pairs_hook=_unique, parse_constant=_nonfinite)
        if (type(value) is not dict or MARKER in value or value.get('ok') is not True
                or type(value.get('grants')) is not list or not _snapshot(value.get('profile'))):
            return body, None
        digest = _fingerprint(value['profile'])
        original = body.rstrip(b' \t\r\n')
        if not original.endswith(b'}'):
            return body, None
        marker = [1, digest, 2]
        return (original[:-1] + b',"_hp":[1,"' + digest.encode('ascii') + b'",2]}',
                {**value, MARKER: marker})
    except (ValueError, TypeError, OverflowError, RecursionError, UnicodeError):
        return body, None
