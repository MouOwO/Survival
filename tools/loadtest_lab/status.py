"""Fixed, run-bound synthetic status proof; no IO or production auth changes.

The status kind is its HMAC domain, distinct from static target attestation.
Per-observation signing/validation touches only a constant schema; no leases or
accounts are enumerated. Client callers cache the manifest digest once.
"""
from __future__ import annotations
import hmac
import json
import math
import re
from .guard import canonical

TOKEN_GRACE_SECONDS = 120
CLOCK_SKEW_SECONDS = 60
CLOCK_PRECISION_SECONDS = 0.000001
KIND = 'SURVIVAL_ISOLATED_LOADTEST_STATUS_V1'
STATS_KEYS = frozenset(('issued','active_leases','client_confirmed_ready','max_client_confirmed_ready',
    'seconds_at_target_ready','effective_ready','ready_valid','target_ready_since_seconds',
    'target_ready_last_ended_seconds','target_ready_current_seconds','target_ready_longest_seconds',
    'run_live','closed','clock_valid','clock_error','run_elapsed_seconds','business_remaining_seconds',
    'controller_remaining_seconds','synthetic_token_expires_at','token_grace_seconds','status_requests'))
BODY_KEYS = frozenset(('v','kind','run_id','manifest_sha256','nonce','synthetic_only','stats'))
CLOCK_ERRORS = frozenset(('lab_clock_invalid','lab_monotonic_regressed','lab_clock_skew'))


def _require(value, code):
    if not value:raise ValueError(code)


def _binding(run_id, manifest_sha256, controller, nonce):
    _require(type(run_id)is str and re.fullmatch('[a-f0-9]{32}',run_id),'lab_status_run_invalid')
    _require(type(manifest_sha256)is str and re.fullmatch('[a-f0-9]{64}',manifest_sha256),'lab_status_manifest_invalid')
    _require(type(controller)is str and re.fullmatch('[a-f0-9]{64}',controller),'lab_status_controller_invalid')
    _require(type(nonce)is str and re.fullmatch('[a-f0-9]{32}',nonce),'lab_status_nonce_invalid')


def _number(value):
    if type(value) not in (int, float) or value < 0:
        return False
    try:
        return math.isfinite(value)
    except (OverflowError, ValueError):
        return False


def validate_stats(stats, *, active_budget, account_budget):
    _require(type(active_budget)is int and 1<=active_budget<=4000 and type(account_budget)is int
             and active_budget<=account_budget<=100000,'lab_status_budget_invalid')
    _require(type(stats)is dict and set(stats)==STATS_KEYS,'lab_status_fields_invalid')
    for key in ('issued','active_leases','client_confirmed_ready','max_client_confirmed_ready',
                'effective_ready','synthetic_token_expires_at','token_grace_seconds','status_requests'):
        _require(type(stats[key])is int and 0<=stats[key]<4_000_000_000_000_000,'lab_status_counter_invalid')
    _require(stats['effective_ready']<=stats['client_confirmed_ready']<=stats['active_leases']
             <=stats['issued']<=account_budget and stats['active_leases']<=active_budget
             and stats['client_confirmed_ready']<=stats['max_client_confirmed_ready']
             and stats['max_client_confirmed_ready']<=active_budget,'lab_status_counter_order_invalid')
    for key in ('ready_valid','run_live','closed','clock_valid'):
        _require(type(stats[key])is bool,'lab_status_flag_invalid')
    _require(stats['token_grace_seconds']==TOKEN_GRACE_SECONDS,'lab_status_grace_invalid')
    _require(stats['clock_error'] is None or type(stats['clock_error'])is str
             and stats['clock_error']in CLOCK_ERRORS,'lab_status_clock_error_invalid')
    _require(stats['clock_valid']==(stats['clock_error'] is None),'lab_status_clock_flag_invalid')
    _require(not stats['run_live'] or stats['clock_valid'] and not stats['closed'],
             'lab_status_liveness_invalid')
    _require(stats['ready_valid']==stats['run_live'] and (stats['effective_ready']==
             (stats['client_confirmed_ready'] if stats['ready_valid'] else 0)),
             'lab_status_effective_ready_invalid')
    for key in ('seconds_at_target_ready','target_ready_current_seconds','target_ready_longest_seconds',
                'run_elapsed_seconds','business_remaining_seconds','controller_remaining_seconds'):
        _require(_number(stats[key]),'lab_status_duration_invalid')
    for key in ('target_ready_since_seconds','target_ready_last_ended_seconds'):
        _require(stats[key] is None or _number(stats[key]) and stats[key]<=stats['run_elapsed_seconds']+.000002,
                 'lab_status_timestamp_invalid')
    _require(stats['target_ready_current_seconds']<=stats['target_ready_longest_seconds']+.000002
             and stats['target_ready_longest_seconds']<=stats['seconds_at_target_ready']+.000002,
             'lab_status_continuity_invalid')
    _require(stats['seconds_at_target_ready']<=stats['run_elapsed_seconds']+.000002,
             'lab_status_cumulative_invalid')
    _require(not (stats['ready_valid'] and stats['effective_ready']==active_budget)
             or stats['target_ready_since_seconds'] is not None, 'lab_status_target_start_missing')
    _require(stats['target_ready_current_seconds']==0 or stats['ready_valid']
             and stats['effective_ready']==active_budget and stats['target_ready_since_seconds'] is not None,
             'lab_status_current_target_invalid')


def sign_status(run_id, manifest_sha256, controller, nonce, stats, *, active_budget, account_budget):
    _binding(run_id,manifest_sha256,controller,nonce)
    validate_stats(stats,active_budget=active_budget,account_budget=account_budget)
    body={'v':1,'kind':KIND,'run_id':run_id,'manifest_sha256':manifest_sha256,
          'nonce':nonce,'synthetic_only':True,'stats':dict(stats)}
    return {**body,'signature':hmac.new(controller.encode(),canonical(body),'sha256').hexdigest()}


def verify_status(value, run_id, manifest_sha256, controller, nonce, *, active_budget, account_budget):
    """Reject unknown schema, cross-run/challenge proof and static attestation."""
    _binding(run_id,manifest_sha256,controller,nonce)
    _require(type(value)is dict and set(value)==BODY_KEYS|{'signature'},'lab_status_proof_fields_invalid')
    _require(type(value['v'])is int and value['v']==1 and value['kind']==KIND
             and value['run_id']==run_id and value['manifest_sha256']==manifest_sha256
             and value['nonce']==nonce and value['synthetic_only'] is True,'lab_status_proof_binding_invalid')
    validate_stats(value['stats'],active_budget=active_budget,account_budget=account_budget)
    signature=value['signature']
    _require(type(signature)is str and re.fullmatch('[a-f0-9]{64}',signature),'lab_status_signature_invalid')
    body={key:value[key] for key in BODY_KEYS}
    expected=hmac.new(controller.encode(),canonical(body),'sha256').hexdigest()
    _require(hmac.compare_digest(signature,expected),'lab_status_signature_mismatch')
    return dict(value['stats'])


def decode_status(raw, run_id, manifest_sha256, controller, nonce, *, active_budget, account_budget):
    """Decode one bounded strict JSON status body, rejecting duplicate keys."""
    _require(type(raw) is bytes and len(raw) <= 16 * 1024, 'lab_status_body_invalid')
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:raise ValueError('lab_status_duplicate_key')
            result[key] = value
        return result
    def constant(_):raise ValueError('lab_status_constant_invalid')
    try:
        value = json.loads(raw.decode('utf-8'), object_pairs_hook=pairs, parse_constant=constant)
    except (ValueError, UnicodeError, RecursionError):
        raise ValueError('lab_status_body_invalid') from None
    return verify_status(value, run_id, manifest_sha256, controller, nonce,
                         active_budget=active_budget, account_budget=account_budget)
