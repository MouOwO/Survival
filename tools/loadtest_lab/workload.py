"""Real request choreography, shared by the smoke test and Locust.

No automatic replay of ambiguous mutations. The explicit idempotency probe
reuses the exact request and checks persisted state before/after replay.
Per-user state is O(1); tasks issue bounded requests, never scan other users.
"""
from __future__ import annotations
import copy
import hashlib
import json
import re
import secrets
import time

from .guard import canonical, need, verify_attestation


class BusinessFailure(ValueError):
    pass


def checked(value):
    if not isinstance(value, dict) or value.get('ok') is False or value.get('error'):
        code = value.get('error') if isinstance(value, dict) else None
        safe = code if isinstance(code, str) and re.fullmatch('[a-z0-9_:]{1,100}', code) else 'invalid_business_response'
        raise BusinessFailure(safe)
    return value


def profile(value, account):
    value = checked(value)
    p = value if 'schema_version' in value else value.get('profile')
    need(isinstance(p, dict), 'profile_response_missing')
    p = p.get('account_profile', p)
    need(p.get('account_id') == account and type(p.get('revision')) is int
         and isinstance(p.get('save'), dict), 'account_profile_identity_mismatch')
    return p


def persisted_fingerprint(value):
    return hashlib.sha256(canonical({k: value.get(k) for k in
        ('account_id', 'revision', 'save', 'entitlements')})).hexdigest()


class Player:
    def __init__(self, transport, cfg, controller, *, clock=time.monotonic):
        self.transport, self.cfg, self.controller, self.clock = transport, cfg, controller, clock
        self.lease = secrets.token_hex(16)
        self.identity = self.token = self.config_hash = None
        self.next_checkpoint = None
        self.last_profile = None
        self.claimed = False
        self.draws = self.replays_verified = 0

    def admin(self, path, payload):
        return checked(self.transport('POST', path, payload, 'Bearer ' + self.controller, '[setup] ' + path))

    def business(self, path, extra=None, label=None):
        need(self.identity is not None, 'synthetic_identity_required')
        body = {'account_id': self.identity['account_id'], 'match_session_id': self.identity['match_session_id']}
        body.update(extra or {})
        return checked(self.transport('POST', path, body, 'Bearer ' + self.token, label or path))

    def start(self):
        nonce = secrets.token_hex(16)
        value = self.transport('GET', '/_loadtest/context?nonce=' + nonce, None,
                               'Bearer ' + self.controller, '[setup] attestation')
        verify_attestation(value, self.cfg, self.controller, nonce)
        value = self.admin('/_loadtest/identity', {'run_id': self.cfg['run_id'], 'lease_id': self.lease})
        need(value.get('synthetic_only') is True and value.get('run_id') == self.cfg['run_id']
             and isinstance(value.get('access_token'), str) and re.fullmatch('lt1_[a-f0-9]{64}', value['access_token']),
             'invalid_synthetic_identity_response')
        number = int(value['account_id'])
        need(self.cfg['account_start'] <= number < self.cfg['account_start'] + self.cfg['accounts'], 'unexpected_account_namespace')
        self.identity, self.token = value, value['access_token']
        response = self.business('/v1/session/authenticate', label='[setup] authenticate')
        need(response.get('authenticated') is True and response.get('account_id') == value['account_id'], 'authenticate_not_confirmed')
        self.last_profile = profile(self.business('/v1/session/login', {'mode': 'pure'}, '[setup] login'), value['account_id'])
        config = self.business('/v1/archive/config', label='[setup] archive/config')
        need(bool(re.fullmatch('[a-f0-9]{64}', config.get('config_hash', ''))), 'invalid_archive_config_hash')
        self.config_hash = config['config_hash']
        self.business('/v1/lottery/catalog', label='[setup] lottery/catalog')
        self.checkpoint()
        self.admin('/_loadtest/ready', {'run_id': self.cfg['run_id'], 'lease_id': self.lease})

    def read_profile(self):
        self.last_profile = profile(self.business('/v1/profile'), self.identity['account_id'])
        return self.last_profile

    def checkpoint(self, final=False, request=None):
        request = request or ('lt_checkpoint_' + secrets.token_hex(16))
        value = self.business('/v1/online-time/checkpoint',
            {'session_id': self.identity['match_session_id'], 'request_id': request, 'final': final})
        if isinstance(value.get('profile'), dict):
            self.last_profile = profile(value, self.identity['account_id'])
        self.next_checkpoint = self.clock() + 60
        return value

    def snapshot(self):
        value = self.business('/v1/lottery/snapshot', {'config_hash': self.config_hash})
        need(isinstance(value.get('snapshots'), list) and len(value['snapshots']) > 0, 'lottery_snapshot_missing')
        return value

    def command(self, kind, **fields):
        operation = 'lt_' + secrets.token_hex(16)
        return {'config_hash': self.config_hash,
                'command': {'id': self.identity['match_session_id'] + ':' + operation, 'kind': kind, **fields}}

    def transact(self, payload, *, replay=False):
        first = self.business('/v1/archive/command', payload)
        if replay:
            before = persisted_fingerprint(self.read_profile())
            second = self.business('/v1/archive/command', copy.deepcopy(payload), '[idempotency] archive/command')
            after = persisted_fingerprint(self.read_profile())
            need(before == after, 'idempotent_replay_changed_persisted_state')
            a, b = first.get('response', first), second.get('response', second)
            for key in ('results', 'pool_id', 'count', 'rewards'):
                need(a.get(key) == b.get(key), 'idempotent_replay_receipt_changed')
            self.replays_verified += 1
        return first

    def draw(self, *, replay=False):
        request = 'lt_draw_' + secrets.token_hex(16)
        result = self.transact(self.command('lottery_draw', pool_id='map', count=10, request_id=request), replay=replay)
        receipt = result.get('response', result)
        need(receipt.get('count') == 10 and isinstance(receipt.get('results'), list)
             and len(receipt['results']) == 10, 'ten_draw_receipt_missing')
        self.draws += 10
        return result

    def claim(self, *, replay=False):
        # All active identities have an explicit synthetic archive_pass fixture.
        result = self.transact(self.command('benefit_claim', track='daily_time', tier_id='daily_time_0'), replay=replay)
        self.claimed = True
        return result

    def stop(self):
        if self.identity is None:
            return
        try:
            self.checkpoint(final=True)
        finally:
            self.admin('/_loadtest/release', {'run_id': self.cfg['run_id'], 'lease_id': self.lease})
            self.identity = self.token = None
