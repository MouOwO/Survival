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
        self.session_logged_in = False
        self.next_checkpoint = None
        self.last_profile = None
        self.catalog_md5 = cfg.get('lottery_catalog_md5')
        need(self.catalog_md5 is None or type(self.catalog_md5) is str
             and re.fullmatch('[a-f0-9]{32}', self.catalog_md5), 'invalid_local_catalog_md5')
        self.catalog_requests = self.catalog_hits = 0
        self.endless_batch_limit = 0
        self.next_endless_wave = 1
        self.endless_waves = self.endless_batches = 0
        self.pending_endless = None
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
        self.session_logged_in = True
        config = self.business('/v1/archive/config', label='[setup] archive/config')
        need(bool(re.fullmatch('[a-f0-9]{64}', config.get('config_hash', ''))), 'invalid_archive_config_hash')
        self.config_hash = config['config_hash']
        capabilities = config.get('capabilities', {})
        if (type(capabilities) is dict and type(capabilities.get('endless_batch')) is int
                and capabilities['endless_batch'] == 1):
            limit = capabilities.get('endless_batch_limit')
            need(type(limit) is int and 1 <= limit <= 32, 'invalid_endless_batch_limit')
            self.endless_batch_limit = limit
        self.catalog(label='[setup] lottery/catalog')
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

    def catalog(self, *, force_miss=False, label=None):
        """Use the real static-catalog MD5 contract, retaining only its digest.

        The manifest can pin the public local seed digest. Without that fixture,
        the first request is explicitly cold; it must not be called a seed hit.
        Stable hits cost O(1) local work; a cold document costs O(B) once and is
        discarded after verifying its bytes. No per-user catalog copy survives.
        """
        known = self.catalog_md5
        requested = ('f' * 32 if known == '0' * 32 else '0' * 32) if force_miss else known
        extra = {'md5': requested} if requested is not None else {}
        name = label or ('lottery/catalog cached' if known and not force_miss else 'lottery/catalog cold')
        value = self.business('/v1/lottery/catalog', extra, name)
        digest = value.get('catalog_md5')
        need(type(digest) is str and re.fullmatch('[a-f0-9]{32}', digest), 'invalid_catalog_md5')
        need(value.get('config_hash') == self.config_hash, 'catalog_config_hash_changed')
        unchanged = value.get('unchanged')
        need(type(unchanged) is bool and unchanged == (requested == digest), 'catalog_cache_receipt_invalid')
        if unchanged:
            need('catalog_json' not in value, 'cached_catalog_contains_full_document')
        else:
            document = value.get('catalog_json')
            need(type(document) is str and len(document) <= 8 * 1024 * 1024,
                 'catalog_document_missing')
            need(hashlib.md5(document.encode('utf-8'), usedforsecurity=False).hexdigest() == digest,
                 'catalog_document_digest_mismatch')
        self.catalog_md5 = digest
        self.catalog_requests += 1
        self.catalog_hits += int(unchanged)
        return value

    def endless_batch(self, count=1, *, replay=False):
        """Submit real N1 endless intents in order, with at most 32 per call.

        This is a synthetic settlement workload, not simulated combat or proof
        of wave clear times. Each session has the authored 1..1000 wave budget;
        exhaustion requires an explicit new match, never recycled receipt IDs.
        A partial/unknown result leaves its bounded payload pending and refuses
        another submission. Only an explicit replay of a confirmed whole batch
        is allowed here; network errors are never retried automatically.
        """
        need(self.pending_endless is None, 'endless_pending_receipt_requires_review')
        need(type(count) is int and 1 <= count <= self.endless_batch_limit,
             'endless_batch_count_invalid')
        first_wave = self.next_endless_wave
        need(first_wave + count - 1 <= 1000, 'endless_wave_budget_exhausted')
        need(self.identity is not None, 'synthetic_identity_required')
        session = self.identity['match_session_id']
        commands = [{'id': session + ':endless:' + str(wave), 'kind': 'endless',
                     'wave': wave, 'difficulty': 1}
                    for wave in range(first_wave, first_wave + count)]
        payload = {'config_hash': self.config_hash, 'commands': commands}
        self.pending_endless = payload

        def receipt(value):
            rows = value.get('results')
            need(type(rows) is list and len(rows) == count, 'endless_batch_receipt_count_invalid')
            for command, row in zip(commands, rows):
                need(type(row) is dict and row.get('id') == command['id']
                     and row.get('ok') is True and type(row.get('terminal')) is bool
                     and row.get('error') in (None, ''), 'endless_wave_not_confirmed')
            self.last_profile = profile(value, self.identity['account_id'])
            return rows

        value = self.business('/v1/archive/endless-batch', payload)
        rows = receipt(value)
        if replay:
            before = persisted_fingerprint(self.read_profile())
            repeated = self.business('/v1/archive/endless-batch', copy.deepcopy(payload),
                                     '[idempotency] archive/endless-batch')
            need(rows == receipt(repeated), 'endless_replay_receipts_changed')
            need(before == persisted_fingerprint(self.read_profile()),
                 'endless_replay_changed_persisted_state')
            self.replays_verified += 1
        self.next_endless_wave += count
        self.endless_waves += count
        self.endless_batches += 1
        self.pending_endless = None
        return value

    def command(self, kind, **fields):
        operation = 'lt_' + secrets.token_hex(16)
        return {'config_hash': self.config_hash,
                'command': {'id': self.identity['match_session_id'] + ':' + operation, 'kind': kind, **fields},
                'response_capabilities': {'archive_profile_refs_v1': True, 'archive_profile_refs_v2': True}}

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
        payload = self.command('lottery_draw', pool_id='map', count=10, request_id=request)
        # Match the current compact consumer: derive presentation from the
        # committed profile instead of requesting a second whole-pool snapshot.
        payload['response_capabilities']['lottery_committed_profile_v1'] = True
        result = self.transact(payload, replay=replay)
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
            self.token = None
            self.session_logged_in = False
            return
        try:
            # An issued identity is not yet a logged-in online-time session.
            # Failed authentication/login must not invent a final checkpoint.
            if self.session_logged_in:
                self.checkpoint(final=True)
        finally:
            try:
                self.admin('/_loadtest/release', {'run_id': self.cfg['run_id'], 'lease_id': self.lease})
            finally:
                self.identity = self.token = None
                self.session_logged_in = False
