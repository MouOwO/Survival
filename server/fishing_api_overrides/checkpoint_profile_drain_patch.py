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
    SERVER: 'ef26ace9502091a501912c19886496c9b2bdd3b17509cc5d976fc05994386749'}
OLD = ('                            account = application._database_account_id(payload["account_id"])\n'
       '                            with measure("checkpoint_drain"):\n'
       '                                archive.drain_online(account)\n')
NEW = '                            # profile() drains the same durable outbox before returning its save.\n'


FINAL_PROFILE_HELPER = 'def _final_profile_committed(payload, response):\n    # Called only after archive.profile() completed its durable pending drain.\n    if type(payload) is not dict or type(response) is not dict:\n        return False\n    caps = payload.get("response_capabilities")\n    snapshot = response.get("profile")\n    return (payload.get("final") is True and response.get("ok") is True\n            and type(caps) is dict and caps.get("final_profile_committed_v1") is True\n            and type(payload.get("account_id")) is str\n            and type(snapshot) is dict\n            and snapshot.get("account_id") == payload["account_id"])\n'
FINAL_PROFILE_HELPER_BLOCK = '\ndef _final_profile_committed(payload, response):\n    # Called only after archive.profile() completed its durable pending drain.\n    if type(payload) is not dict or type(response) is not dict:\n        return False\n    caps = payload.get("response_capabilities")\n    snapshot = response.get("profile")\n    return (payload.get("final") is True and response.get("ok") is True\n            and type(caps) is dict and caps.get("final_profile_committed_v1") is True\n            and type(payload.get("account_id")) is str\n            and type(snapshot) is dict\n            and snapshot.get("account_id") == payload["account_id"])\n\n'
FINAL_PROFILE_HEADER = 'from __future__ import annotations\n'
FINAL_PROFILE_ANCHOR = '                                response["profile"] = archive.profile({"account_id": payload["account_id"]})\n'
FINAL_PROFILE_HINT = '                            if _final_profile_committed(payload, response):\n                                response["final_profile_committed_v1"] = 1\n'

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
    if result[SERVER].count(FINAL_PROFILE_HEADER) != 1 or result[SERVER].count(FINAL_PROFILE_ANCHOR) != 1:
        raise ValueError("final_profile_source_anchor_changed")
    result[SERVER] = result[SERVER].replace(FINAL_PROFILE_HEADER, FINAL_PROFILE_HEADER + FINAL_PROFILE_HELPER_BLOCK, 1).replace(FINAL_PROFILE_ANCHOR, FINAL_PROFILE_ANCHOR + FINAL_PROFILE_HINT, 1)
    compile(result[SERVER], '<single-profile-outbox-drain>', 'exec')
    return _checked(result, OUTPUTS)


def restore_sources(sources):
    result = _checked(sources, OUTPUTS)
    if result[SERVER].count(FINAL_PROFILE_HELPER_BLOCK) != 1 or result[SERVER].count(FINAL_PROFILE_HINT) != 1:
        raise ValueError("final_profile_restore_anchor_changed")
    result[SERVER] = result[SERVER].replace(FINAL_PROFILE_HELPER_BLOCK, "", 1).replace(FINAL_PROFILE_HINT, "", 1)
    if result[SERVER].count(NEW) != 1:
        raise ValueError('checkpoint_drain_restore_anchor_changed')
    result[SERVER] = result[SERVER].replace(NEW, OLD, 1)
    return _checked(result, PARENTS)
