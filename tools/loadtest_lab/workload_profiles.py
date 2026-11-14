"""Source-bound client choreography; no network or import-time file reads.

CSV indexing is O(D) once per immutable configuration (D <=256). Players share
the read-only index; each response costs O(K), K <=128 grants. The eight-entry
configuration cache retains identities, so an id cannot be reused accidentally.
Prepared configurations must remain immutable throughout a run.
"""
from __future__ import annotations

from collections import OrderedDict
import csv
from dataclasses import dataclass
from decimal import Decimal, InvalidOperation
import hashlib
import io
import json
import re
import threading
from types import MappingProxyType

from .guard import canonical, need

MODES = frozenset(('legacy-v1', 'client-v2', 'client-v3'))
CSV_SOURCE = 'addon/data/csv/玩家档案系统/star_blessing_reward_definitions.csv'
MAX_DEFINITIONS = 256
MAX_GRANTS = MAX_SEEN_GRANTS = 128
COUNTERS = ('checkpoint_attempts', 'checkpoint_completed', 'checkpoint_failed',
            'grants_validated', 'grant_responses', 'grant_followup_attempts',
            'grant_followup_completed', 'grant_followup_failed',
            'finalization_attempts', 'finalization_completed', 'finalization_failed')
WORKFLOWS = ('checkpoint_setup', 'checkpoint_periodic', 'checkpoint_final', 'finalization')
_RULE_KEYS = frozenset(('reward_id', 'definition_version', 'enabled',
                        'effect_scope', 'value_min', 'value_max'))
_ID = re.compile(r'[a-z][a-z0-9_]{0,95}\Z')
_GRANT_ID = re.compile(r'[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}\Z')
_CACHE, _CACHE_LOCK = OrderedDict(), threading.RLock()


def number(value):
    """Lua tonumber-compatible finite decimal input, without bool/nonfinite."""
    need(type(value) in (str, int, float) and (type(value) is not str or len(value) <=128),
         'grant_numeric_invalid')
    try:
        result = Decimal(str(value))
    except (InvalidOperation, ValueError):
        raise ValueError('grant_numeric_invalid') from None
    need(result.is_finite() and abs(result) <= Decimal('1e15'), 'grant_numeric_invalid')
    return result


def _rule(row):
    need(type(row) is dict and set(row) == _RULE_KEYS, 'workload_rule_fields_invalid')
    identity = row['reward_id']
    need(type(identity) is str and _ID.fullmatch(identity), 'workload_reward_id_invalid')
    need(type(row['definition_version']) is int and 1 <= row['definition_version'] <=65535,
         'workload_definition_version_invalid')
    need(type(row['enabled']) is bool and row['effect_scope'] in ('permanent', 'immediate'),
         'workload_definition_flags_invalid')
    low, high = number(row['value_min']), number(row['value_max'])
    need(low <= high, 'workload_definition_range_invalid')
    return identity, (row['definition_version'], row['enabled'], row['effect_scope'], low, high)


def build_workload_profile(csv_bytes, mode='client-v2', *, compact_seed=None):
    """Prepare public metadata from the actual exported reward CSV bytes."""
    need(type(csv_bytes) is bytes and 1 <= len(csv_bytes) <=256*1024,
         'workload_csv_budget_invalid')
    try:
        lines = csv.reader(io.StringIO(csv_bytes.decode('utf-8-sig')))
        header = next(lines)
        need(len(header) == len(set(header)) and _RULE_KEYS <= set(header)
             and len(header) <=40, 'workload_csv_header_invalid')
        rows, seen = [], set()
        for values in lines:
            if not values or values[0].startswith('#'):
                continue
            need(len(values) == len(header) and len(rows) < MAX_DEFINITIONS,
                 'workload_csv_row_budget_invalid')
            raw = dict(zip(header, values))
            version = number(raw['definition_version'])
            need(version == version.to_integral_value(), 'workload_definition_version_invalid')
            enabled = raw['enabled'].strip().lower()
            need(enabled in ('0', '1', 'false', 'true'), 'workload_definition_flags_invalid')
            row = {'reward_id': raw['reward_id'], 'definition_version': int(version),
                   'enabled': enabled in ('1', 'true'), 'effect_scope': raw['effect_scope'],
                   'value_min': format(number(raw['value_min']), 'f'),
                   'value_max': format(number(raw['value_max']), 'f')}
            identity, _ = _rule(row)
            need(identity not in seen, 'workload_reward_id_duplicate')
            seen.add(identity); rows.append(row)
    except (UnicodeError, csv.Error, StopIteration):
        raise ValueError('workload_csv_invalid') from None
    need(bool(rows), 'workload_reward_definitions_empty')
    result = {'id': mode, 'source': CSV_SOURCE,
              'source_sha256': hashlib.sha256(csv_bytes).hexdigest(),
              'rules': sorted(rows, key=lambda row: row['reward_id'])}
    need(mode in ('client-v2', 'client-v3'), 'client_profile_mode_invalid')
    if mode == 'client-v3':result['compact'] = compact_contract(compact_seed)
    return result


@dataclass(frozen=True)
class ClientProfile:
    mode: str
    rules: object
    compact: object = None

    def grants(self, value):
        need(type(value) is list and len(value) <= MAX_GRANTS, 'checkpoint_grants_invalid')
        identities = []
        for grant in value:
            need(type(grant) is dict, 'checkpoint_grant_invalid')
            identity = grant.get('reward_id')
            need(type(identity) is str and identity in self.rules, 'grant_reward_missing')
            version, enabled, scope, low, high = self.rules[identity]
            need(enabled, 'grant_reward_disabled')
            # Scope is defined by the source-bound local CSV. The actual API
            # deliberately returns only grant_id/reward_id/amount/version.
            need(scope == 'permanent', 'grant_scope_mismatch')
            need(number(grant.get('definition_version')) == version, 'grant_definition_version_mismatch')
            amount = number(grant.get('amount'))
            need(low <= amount <= high, 'grant_amount_out_of_range')
            grant_id = grant.get('grant_id')
            need(type(grant_id) is str and _GRANT_ID.fullmatch(grant_id), 'grant_id_invalid')
            identities.append(grant_id)
        return identities


_LEGACY = ClientProfile('legacy-v1', MappingProxyType({}))


def validate_workload_profile(cfg, read_source=None):
    """Client checks metadata; guard may additionally rebuild from real CSV."""
    mode = cfg.get('client_workload', 'legacy-v1')
    need(type(mode) is str and mode in MODES, 'client_workload_invalid')
    if mode == 'legacy-v1':
        need('workload_profile' not in cfg, 'legacy_workload_metadata_unexpected')
        return _LEGACY
    value = cfg.get('workload_profile')
    keys = {'id', 'source', 'source_sha256', 'rules'} | ({'compact'} if mode == 'client-v3' else set())
    need(type(value) is dict and set(value) == keys
         and value.get('id') == mode and value.get('source') == CSV_SOURCE,
         'workload_profile_binding_invalid')
    digest = value['source_sha256']
    need(type(digest) is str and re.fullmatch('[a-f0-9]{64}', digest)
         and cfg.get('sources', {}).get(CSV_SOURCE) == digest,
         'workload_csv_source_mismatch')
    rows = value['rules']
    need(type(rows) is list and 1 <= len(rows) <= MAX_DEFINITIONS, 'workload_rules_budget_invalid')
    rules, order = {}, []
    for row in rows:
        identity, rule = _rule(row)
        need(identity not in rules, 'workload_reward_id_duplicate')
        rules[identity] = rule; order.append(identity)
    need(order == sorted(order), 'workload_rule_order_invalid')
    if read_source is not None:
        raw = read_source(CSV_SOURCE)
        need(type(raw) is bytes and canonical(build_workload_profile(raw, mode, compact_seed=read_source(COMPACT_TARGET) if mode == 'client-v3' else None)) == canonical(value),
             'workload_csv_rules_mismatch')
    compact = None
    if mode == 'client-v3':
        compact = value['compact']
        need(type(compact) is dict and canonical(compact) == canonical(COMPACT_METADATA), 'compact_client_metadata_changed')
        need(cfg.get('sources', {}).get(COMPACT_TARGET) == COMPACT_SEED_SHA and cfg.get('lottery_catalog_md5') == compact['catalog_md5'], 'compact_seed_source_binding_changed')
        compact = MappingProxyType(dict(compact))
    return ClientProfile(mode, MappingProxyType(rules), compact)


def profile_for(cfg):
    """One O(D) initialization, then O(1) lookups for the frozen cfg identity."""
    if cfg.get('client_workload', 'legacy-v1') == 'legacy-v1':
        return validate_workload_profile(cfg)
    key = id(cfg)
    with _CACHE_LOCK:
        entry = _CACHE.get(key)
        if entry is not None and entry[0] is cfg:
            _CACHE.move_to_end(key)
            return entry[1]
        profile = validate_workload_profile(cfg)
        _CACHE[key] = (cfg, profile)
        if len(_CACHE) > 8:
            _CACHE.popitem(last=False)
        return profile

COMPACT_TARGET = 'operator/fixtures/compact_client_v3_catalog.json'
COMPACT_SEED_SHA = '558c6830ca39df0e08615e24574b1f847a205fad175de41bfba2306764d2126e'
COMPACT_METADATA = {'id': 'compact-room-v1', 'source': 'operator/fixtures/compact_client_v3_catalog.json', 'source_sha256': '558c6830ca39df0e08615e24574b1f847a205fad175de41bfba2306764d2126e', 'catalog_md5': '4027c0e0b4d3218bd246a701478ce5c2', 'config_hash': 'd38866d1be2dec7b3b8c27ddd1315bab9cb27a1c7e0a136b670e5e9df12e3ed1', 'room_size': 4, 'catalog_interval_seconds': 30, 'checkpoint_interval_seconds': 60, 'single_worker_only': True, 'pool_revisions': {'map': '604029679-664651516', 'cultivation': '1688628271-1060922468', 'dragon_knight': '941368790-1864694631', 'summer': '474022853-1112315570'}}

def compact_contract(raw):
    need(type(raw) is bytes and len(raw) <= 256*1024 and hashlib.sha256(raw).hexdigest() == COMPACT_SEED_SHA, 'compact_catalog_source_changed')
    seed=json.loads(raw);document=seed.get('catalog_json')
    need(type(document) is str and hashlib.md5(document.encode('utf8'),usedforsecurity=False).hexdigest()==COMPACT_METADATA['catalog_md5']
         and seed.get('md5')==COMPACT_METADATA['catalog_md5'] and seed.get('config_hash')==COMPACT_METADATA['config_hash'],'compact_catalog_identity_changed')
    data=json.loads(document)
    need(data.get('schema')==1 and type(data.get('snapshots'))is list and len(data['snapshots'])==4,'compact_catalog_shape_invalid')
    need({s['selected_pool_id']:s['selected_pool']['revision']for s in data['snapshots']}==COMPACT_METADATA['pool_revisions'],'compact_pool_revision_changed')
    return dict(COMPACT_METADATA)
