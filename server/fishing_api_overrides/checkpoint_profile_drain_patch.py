"""Remove the checkpoint's duplicate outbox-list RPC, retaining profile's drain.

Preparation only; accept exactly the reviewed server and its unchanged callee.
Initialization/idle O(1). Each checkpoint removes one indexed pending-list RPC
and its full authorization check. O(K) resume/commit work for K pending durable
operations, and all transaction boundaries and account checks, remain in place.
No per-account cache, timer, scene scan or authorization bypass is introduced.
"""
from __future__ import annotations

import hashlib

SERVER = 'fishing_api/server.py'
SERVICE = 'archive_backend/service.py'
PARENTS = {
    SERVER: '20b17c5ebfd0aeca5aff7d529d90ae7d5da2960ea2223524335918582135e443',
    SERVICE: '672a1e845ec17093c755d7a724fcc4978f8cc008d935e763e7105f300b73e2f8',
}
OUTPUTS = {**PARENTS,
    SERVER: '1470ead7930e2f04279e7c9276023116e7cb7ffa9bb6dff72f763cc0b83ee90d'}
OLD = ('                            account = application._database_account_id(payload["account_id"])\n'
       '                            with measure("checkpoint_drain"):\n'
       '                                archive.drain_online(account)\n')
NEW = '                            # profile() drains the same durable outbox before returning its save.\n'


def _checked(sources, expected):
    if type(sources) is not dict or set(sources) != set(expected):
        raise ValueError('checkpoint_drain_exact_source_set_required')
    result = {}
    for name, digest in expected.items():
        source = sources[name]
        if type(source) is not str:
            raise ValueError('checkpoint_drain_text_source_required')
        source = source.replace('\r\n', '\n')
        if '\r' in source or hashlib.sha256(source.encode()).hexdigest() != digest:
            raise ValueError('checkpoint_drain_exact_source_required')
        result[name] = source
    return result


def patch_sources(sources):
    result = _checked(sources, PARENTS)
    if result[SERVER].count(OLD) != 1:
        raise ValueError('checkpoint_drain_anchor_changed')
    result[SERVER] = result[SERVER].replace(OLD, NEW, 1)
    compile(result[SERVER], '<single-profile-outbox-drain>', 'exec')
    return _checked(result, OUTPUTS)


def restore_sources(sources):
    result = _checked(sources, OUTPUTS)
    if result[SERVER].count(NEW) != 1:
        raise ValueError('checkpoint_drain_restore_anchor_changed')
    result[SERVER] = result[SERVER].replace(NEW, OLD, 1)
    return _checked(result, PARENTS)
