"""Installed redemption entry point and real Lua; synthetic in-memory RPC only.

No real code, player, PostgreSQL or HTTP request is used. Every vector owns its
profile and receipt. Transport capabilities cannot change the frozen reward.
"""
from copy import deepcopy
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
from types import SimpleNamespace

TARGET = 'backend/archive_backend/redemption_codes.py'
CAPS = {'archive_profile_refs_v1': True, 'archive_profile_refs_v2': True}


def need(ok, code):
    if not ok:
        raise RuntimeError(code)


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec)
    value.__package__ = 'archive_backend'
    exec(compile(path.read_bytes(), str(path), 'exec'), value.__dict__)
    return value


def run(old, new, bundle_hash, lua='/usr/bin/lua'):
    old, new = Path(old), Path(new)
    parent = module('redemption_transport_parent', old / TARGET)
    candidate = module('redemption_transport_candidate', new / TARGET)
    sys.path.insert(0, str(new / 'backend'))
    from archive_backend.bundle import Bundle
    from archive_backend.service import ArchiveService
    bundle = Bundle(new / 'addon/server/bundles' / bundle_hash)
    need(bundle.hash == bundle_hash, 'probe_bundle_changed')
    # Public frozen reward shape of the already registered four tiers. A
    # backend release need not carry editable payment CSV/catalogue sources.
    original = dict(markers=[], wallet={}, entitlements={}, products=[dict(
        sku='special_lottery_ticket_single', item_id='pay_special_lottery_ticket_single',
        currency='u_coin', price=0, enabled=True, purchase_limit=0, ownership_quantity=1,
        title='synthetic gold ticket', effects={}, purchase_method='redemption',
        grants=dict(items={'special_lottery_ticket': 1},
                    item_limits={'special_lottery_ticket': 2147483647}, lines=[]))])
    defaults = {r['field_id']: r['default_value']
                for r in bundle.configs['player_gameplay_stats']['rows']}
    vectors, invalid = [], 0

    def fixture(quantity):
        frozen = deepcopy(original)
        product = frozen['products'][0]
        product['grants']['items'] = {'special_lottery_ticket': quantity}
        product['grants']['lines'] = [dict(kind='item', id='special_lottery_ticket',
                                         quantity=quantity, label='synthetic gold ticket')]
        profile = dict(schema_version=1, account_id='12345678', revision=1,
                       entitlements={}, achievements={}, public={},
                       save=dict(archive={}, gameplay_stats=deepcopy(defaults),
                                 content_inventory={'special_lottery_ticket': 7, 'lottery_ticket': 13}))
        calls, completed = [], {}
        digest = hashlib.sha256(b'SYNTHETICCODE123').hexdigest()
        database = 'a' * 64

        def rpc(name, value):
            calls.append((name, deepcopy(value)))
            if name == 'redemption_prepare':
                need(set(value) == {'p_account', 'p_session', 'p_code_hash', 'p_request', 'p_hash'}
                     and value['p_code_hash'] == digest and value['p_account'] == database,
                     'probe_transport_flags_reached_rpc')
                if completed:
                    return deepcopy(completed['reply'])
                return dict(ok=True, done=False, profile=deepcopy(profile), config_hash=bundle.hash,
                            command=dict(id='redeem:r_synthetic', kind='redemption_redeem',
                                         request_id=value['p_request'], rewards=deepcopy(frozen), label='synthetic'))
            need(name == 'redemption_commit' and value['p_id'] == 'redeem:r_synthetic',
                 'probe_unexpected_rpc')
            need(not completed, 'probe_duplicate_commit')
            profile['save']['archive'] = deepcopy(value['p_archive'])
            profile['save']['content_inventory'] = deepcopy(value['p_inventory'])
            profile['revision'] += 1
            completed['reply'] = dict(ok=True, done=True, response=deepcopy(value['p_response']),
                                      profile=deepcopy(profile))
            return deepcopy(completed['reply'])

        app = SimpleNamespace(rpc_client=SimpleNamespace(rpc=rpc),
                              _database_account_id=lambda account: database,
                              _ensure_gameplay_stats=lambda account: None,
                              _public_response=lambda result, database, public: result)
        service = ArchiveService(app, bundle, lua)
        # Exercise this candidate's unchanged finish implementation; the normal
        # ArchiveService delegates to the installed module in real deployment.
        service.finish_prepared = lambda account, operation, prepared: candidate.finish(
            service, account, operation, prepared)
        payload = dict(account_id='12345678', match_session_id='synthetic_transport_session',
                       config_hash=bundle.hash,
                       command=dict(id='redeem:synthetic_transport', kind='redemption_redeem',
                                    code='SYNTHETICCODE123', request_id='synthetic_transport'))
        return service, payload, profile, calls

    service, payload, _, calls = fixture(100)
    try:
        parent.command(service, dict(payload, response_capabilities=deepcopy(CAPS)))
        raise RuntimeError('probe_parent_failure_not_reproduced')
    except ValueError as error:
        need(str(error) == 'redeem_request_invalid' and not calls, 'probe_parent_failure_changed')

    for quantity in (100, 500, 1000, 2000):
        for capabilities in (None, {}, {'archive_profile_refs_v1': True}, CAPS):
            service, payload, profile, calls = fixture(quantity)
            if capabilities is not None:
                payload['response_capabilities'] = deepcopy(capabilities)
            before = deepcopy(payload)
            reply = candidate.command(service, payload)
            need(reply.get('ok') is True and reply.get('done') is True
                 and reply['response']['granted'] == 1, 'probe_redemption_not_committed')
            inventory = reply['profile']['save']['content_inventory']
            need(inventory['special_lottery_ticket'] == 7 + quantity
                 and inventory['lottery_ticket'] == 13, 'probe_wrong_ticket_delta')
            need(payload == before and [n for n, _ in calls] == ['redemption_prepare', 'redemption_commit'],
                 'probe_input_mutated_or_extra_rpc')
            saved = deepcopy(profile)
            need(candidate.command(service, payload) == reply and profile == saved
                 and [n for n, _ in calls].count('redemption_commit') == 1, 'probe_reply_retry_not_idempotent')
            vectors.append(dict(quantity=quantity, capabilities=capabilities,
                                ticket_delta=quantity, real_lua=True, commits=1))

    for bad in (None, [], 'true', {'rewards': True}, {'archive_profile_refs_v1': 1},
                {'archive_profile_refs_v2': {}}, {'archive_profile_refs_v2': 'true'}):
        service, payload, _, calls = fixture(100)
        payload['response_capabilities'] = bad
        try:
            candidate.command(service, payload)
            raise RuntimeError('probe_invalid_capabilities_accepted')
        except ValueError as error:
            need(str(error) == 'redeem_request_invalid' and not calls, 'probe_invalid_request_reached_rpc')
        invalid += 1
    for field in ('rewards', 'p_account', 'enabled', 'quantity'):
        service, payload, _, calls = fixture(100)
        payload[field] = 2000
        try:
            candidate.command(service, payload)
            raise RuntimeError('probe_unknown_reward_input_accepted')
        except ValueError as error:
            need(str(error) == 'redeem_request_invalid' and not calls, 'probe_unknown_input_reached_rpc')
        invalid += 1
    return dict(ok=True, status='ACTUAL_WS4_PREPARED_REDEMPTION_TRANSPORT_PARITY_PASS',
                changed_files=[TARGET], bundle_unchanged=True, parent_failure_reproduced=True,
                real_lua_vectors=len(vectors), malformed_vectors=invalid, vectors=vectors,
                fake_rpc_calls=len(vectors) * 3, rpc_calls=0, database_writes=0,
                real_player_data_used=False, real_player_redemption=False,
                boundary='Actual installed Python/Lua with synthetic in-memory RPC; no real redemption or HTTP latency claim')
