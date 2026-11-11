"""Test-only consent substitute; uses real session storage and proxy validation.

Cold cost: O(1) range index, O(saved lab sessions) revocation once at startup.
Issue/retry/release: indexed O(1); memory O(issued leases), capped by accounts.
No periodic account scans and no Steam or payment network calls.
"""
from __future__ import annotations
from collections.abc import Mapping
import hmac
import re
import secrets
import threading
import time

from .guard import ACCOUNT_START, PORTS, account, need
from player_web_auth.service import Settings, Service, AuthError, STEAM_BASE, digest


class AccountRange(Mapping):
    def __init__(self, count):
        self.count = count

    def __len__(self):
        return self.count

    def __getitem__(self, key):
        if not isinstance(key, str) or not key.isascii() or not key.isdigit():
            raise KeyError(key)
        number = int(key)
        if str(number) != key or not ACCOUNT_START <= number < ACCOUNT_START + self.count:
            raise KeyError(key)
        return str(STEAM_BASE + number)

    def __iter__(self):
        return (str(ACCOUNT_START + i) for i in range(self.count))


class LabSettings(Settings):
    def __init__(self, root, cfg, private):
        super().__init__(database=root / 'auth/auth.sqlite3', secret=private['auth_secret'],
            upstream_bearer=private['backend'], steam_ids=tuple(str(STEAM_BASE+i) for i in range(1, 6)),
            public_base='https://loadtest.invalid/ws4-web', upstream='http://127.0.0.1:' + str(PORTS['backend']),
            bind='127.0.0.1', port=PORTS['web'], isolated_local_progress=True)
        object.__setattr__(self, '_account_range', AccountRange(cfg['accounts']))

    @property
    def accounts(self):
        return self._account_range

    def validate(self):
        # Retain the actual secret/payment rules. Only this standalone adapter
        # substitutes namespace and addresses; no production Settings is edited.
        Settings(database=self.database, secret=self.secret, upstream_bearer=self.upstream_bearer,
                 steam_ids=self.steam_ids).validate()
        need(self.upstream == 'http://127.0.0.1:' + str(PORTS['backend'])
             and self.port == PORTS['web'] and self.bind == '127.0.0.1'
             and not self.payments_enabled and not self.steam_tls_relay,
             'test_only_auth_settings_required')


class IdentityService(Service):
    def __init__(self, root, cfg, private, forward, *, clock=time.time, monotonic=time.monotonic):
        self.cfg, self.private = cfg, private
        self.monotonic = monotonic
        self.deadline = monotonic() + cfg['duration_seconds']
        self.lease_lock = threading.RLock()
        self.leases, self.next_index, self.active, self.request_count = {}, 0, 0, 0
        self.ready, self.max_ready, self.ready_at_target_seconds = 0, 0, 0.0
        self.ready_changed = monotonic()
        self.boot = secrets.token_hex(8)
        # Forward is a fixed-origin closure supplied after DB marker validation.
        super().__init__(LabSettings(root, cfg, private), clock=clock, forward=forward,
                         verify_steam=lambda fields: False)
        with self.lock, self.db:
            self.db.execute('UPDATE challenges SET revoked=1 WHERE revoked=0')

    def budget(self):
        with self.lease_lock:
            if self.monotonic() > self.deadline:
                raise AuthError('lab_deadline_reached', 503)
            if self.cfg['purpose'] == 'functional-smoke' and self.request_count >= 150:
                raise AuthError('smoke_request_budget_reached', 503)
            self.request_count += 1

    def controller(self, header):
        if not isinstance(header, str) or not hmac.compare_digest(header, 'Bearer ' + self.private['controller']):
            raise AuthError('lab_controller_required', 401)

    def issue(self, payload):
        if (not isinstance(payload, dict) or set(payload) != {'run_id', 'lease_id'}
                or payload['run_id'] != self.cfg['run_id']
                or not isinstance(payload['lease_id'], str)
                or not re.fullmatch('[a-f0-9]{32}', payload['lease_id'])):
            raise AuthError('invalid_lab_lease', 400)
        lease = payload['lease_id']
        with self.lease_lock:
            old = self.leases.get(lease)
            if old:
                if old['released']:
                    raise AuthError('lab_lease_already_released', 409)
                return dict(old['reply'])
            if self.active >= self.cfg['active'] or self.next_index >= self.cfg['accounts']:
                raise AuthError('lab_identity_budget_reached', 429)
            index = self.next_index
            raw_account = account(self.cfg, index)
            match = 'lt_' + self.cfg['run_id'][:16] + '_' + self.boot + '_' + str(index)
            device = secrets.token_hex(32)
            internal_token = self._token(device)
            now = int(self.clock()); expiry = now + min(14400, self.cfg['duration_seconds'] + 60)
            with self.lock, self.db:
                self.db.execute('INSERT INTO challenges(device_hash,user_code,account,match_id,created,expires,'
                    'approved_steam,approved_at,token_hash,token_expires,revoked,last_poll) VALUES(?,?,?,?,?,?,?,?,?,?,0,0)',
                    (device, 'LT' + secrets.token_hex(8), raw_account, match, now, expiry,
                     str(STEAM_BASE + int(raw_account)), now, digest(internal_token), expiry))
            reply = {'ok': True, 'run_id': self.cfg['run_id'], 'account_id': raw_account,
                     'match_session_id': match, 'access_token': 'lt1_' + internal_token[5:],
                     'expires_at': expiry, 'synthetic_only': True}
            self.leases[lease] = {'reply': reply, 'released': False, 'device': device, 'ready': False}
            self.next_index += 1; self.active += 1
            return dict(reply)

    def release(self, payload):
        if (not isinstance(payload, dict) or set(payload) != {'run_id', 'lease_id'}
                or payload.get('run_id') != self.cfg['run_id']):
            raise AuthError('invalid_lab_lease', 400)
        with self.lease_lock:
            value = self.leases.get(payload.get('lease_id'))
            if value is None:
                raise AuthError('unknown_lab_lease', 404)
            if not value['released']:
                self._account_ready_duration()
                with self.lock, self.db:
                    self.db.execute('UPDATE challenges SET revoked=1 WHERE device_hash=?', (value['device'],))
                value['released'] = True; self.active -= 1
                if value['ready']:
                    self.ready -= 1
            return {'ok': True}

    def _account_ready_duration(self):
        now = self.monotonic()
        if self.ready == self.cfg['active']:
            self.ready_at_target_seconds += max(0, now - self.ready_changed)
        self.ready_changed = now

    def mark_ready(self, payload):
        if not isinstance(payload, dict) or set(payload) != {'run_id', 'lease_id'} or payload['run_id'] != self.cfg['run_id']:
            raise AuthError('invalid_lab_lease', 400)
        with self.lease_lock:
            value = self.leases.get(payload.get('lease_id'))
            if value is None or value['released']:
                raise AuthError('unknown_lab_lease', 404)
            if not value['ready']:
                self._account_ready_duration()
                value['ready'] = True; self.ready += 1
                self.max_ready = max(self.max_ready, self.ready)
            return {'ok': True}

    def counts(self):
        with self.lease_lock:
            self._account_ready_duration()
            return {'issued': self.next_index, 'active_leases': self.active,
                    'client_confirmed_ready': self.ready, 'max_client_confirmed_ready': self.max_ready,
                    'seconds_at_target_ready': round(self.ready_at_target_seconds, 3)}

    def principal(self, bearer, payload):
        if not isinstance(bearer, str) or not re.fullmatch('lt1_[a-f0-9]{64}', bearer):
            raise AuthError('lab_session_required', 403)
        # The real production parser rejects lt1_. The internal representation
        # is only looked up in this lab's independent SQLite and secret namespace.
        return super().principal('pwa1_' + bearer[4:], payload)

    def rate(self, scope, actor, maximum):
        if scope == 'global-http':
            maximum = self.cfg['global_http_per_minute']
        return super().rate(scope, actor, maximum)

    def proxy(self, path, bearer, payload, peer):
        if path not in {'/v1/session/authenticate', '/v1/session/login', '/v1/profile',
                        '/v1/archive/config', '/v1/lottery/catalog', '/v1/lottery/snapshot',
                        '/v1/archive/command', '/v1/online-time/checkpoint'}:
            raise AuthError('lab_business_route_not_allowed', 403)
        if path == '/v1/archive/command' and (not isinstance(payload, dict)
                or not isinstance(payload.get('command'), dict)
                or payload['command'].get('kind') not in ('lottery_draw', 'benefit_claim', 'daily_claim')):
            raise AuthError('lab_business_command_not_allowed', 403)
        return super().proxy(path, bearer, payload, peer)
