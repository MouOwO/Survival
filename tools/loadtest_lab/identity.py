"""Test-only consent substitute; uses real session storage and proxy validation.

Cold cost: O(1) range index, O(saved lab sessions) revocation once at startup.
Issue/retry/release: indexed O(1); memory O(issued leases), capped by accounts.
No periodic account scans and no Steam or payment network calls.
"""
from __future__ import annotations
from collections.abc import Mapping
import hmac
import math
import re
import secrets
import threading
import time

from .guard import ACCOUNT_START, PORTS, account, need, canonical, sha
from player_web_auth.service import Settings, Service, AuthError, STEAM_BASE, digest
from .status import TOKEN_GRACE_SECONDS, CLOCK_SKEW_SECONDS, CLOCK_PRECISION_SECONDS, sign_status


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
    """Run-scoped synthetic identity and O(1) ready-state accounting.

    This does not test production's four-hour authorization refresh. Synthetic
    grants share the declared run endpoint plus a fixed cleanup margin; new
    business still stops at the monotonic run deadline. No identity renewal,
    replacement or unknown-write replay is performed here.
    """
    def __init__(self, root, cfg, private, forward, *, clock=time.time, monotonic=time.monotonic):
        duration = cfg.get('duration_seconds')
        need(type(duration) is int and 60 <= duration <= 18000, 'lab_duration_budget_invalid')
        self.cfg, self.private = cfg, private
        self.monotonic = monotonic
        started_mono, started_wall = monotonic(), clock()
        need(self._finite(started_mono) and self._finite(started_wall), 'lab_clock_invalid')
        self._started_monotonic, self._started_wall = float(started_mono), float(started_wall)
        self.deadline = self._started_monotonic + duration
        self.token_expires_at = int(self._started_wall) + duration + TOKEN_GRACE_SECONDS
        self._last_seen_monotonic = self._last_verified_monotonic = self._started_monotonic
        self._clock_error = None
        self._tracking_ended = self._database_closed = False
        self._closed_at = None
        self._target_since = self._target_last_ended = None
        self._target_longest_seconds = 0.0
        self._status_requests = 0
        # O(S) static-manifest binding once at startup; S is the existing bounded
        # source list. Ready/token bookkeeping is O(1), independent of players.
        self._manifest_sha256 = sha(canonical(cfg))
        self.lease_lock = threading.RLock()
        self.leases, self.next_index, self.active, self.request_count = {}, 0, 0, 0
        self.ready, self.max_ready, self.ready_at_target_seconds = 0, 0, 0.0
        self.ready_changed = self._started_monotonic
        self.boot = secrets.token_hex(8)
        super().__init__(LabSettings(root, cfg, private), clock=clock, forward=forward,
                         verify_steam=lambda fields: False)
        with self.lock, self.db:
            self.db.execute('UPDATE challenges SET revoked=1 WHERE revoked=0')

    @staticmethod
    def _finite(value):
        if type(value) not in (int, float):
            return False
        try:
            return math.isfinite(value)
        except (OverflowError, ValueError):
            return False

    def _time_state(self):
        """Sticky clock failure; an unknown interval ends at last verified time.

        Keep the wall-clock expiry check used by the real Service. With clock
        skew <=60s, every run-live request has approximately 59s margin before the synthetic
        expiry. A larger clock change invalidates the run rather than silently
        extending tokens or counting unverified ready time.
        """
        raw_mono, wall = self.monotonic(), self.clock()
        if not self._finite(raw_mono) or not self._finite(wall):
            error = 'lab_clock_invalid'
        elif raw_mono < self._last_seen_monotonic:
            error = 'lab_monotonic_regressed'
        elif abs((wall - self._started_wall) - (raw_mono - self._started_monotonic)) > CLOCK_SKEW_SECONDS + CLOCK_PRECISION_SECONDS:
            error = 'lab_clock_skew'
        else:
            error = None
        if self._finite(raw_mono):
            self._last_seen_monotonic = max(self._last_seen_monotonic, float(raw_mono))
        if self._clock_error is None:
            if error is not None:
                self._clock_error = error
            else:
                self._last_verified_monotonic = float(raw_mono)
        now = self._last_seen_monotonic
        cutoff = self._last_verified_monotonic if self._clock_error else now
        cutoff = min(cutoff, self.deadline)
        if self._closed_at is not None:
            cutoff = min(cutoff, self._closed_at)
        cutoff = max(self.ready_changed, cutoff)
        live = (self._clock_error is None and not self._database_closed and now < self.deadline
                and wall < self.token_expires_at)
        return now, cutoff, live

    def _end_target_interval(self, end):
        if self._target_since is not None:
            self._target_longest_seconds = max(self._target_longest_seconds,
                                               max(0.0, end - self._target_since))
            self._target_last_ended = end
            self._target_since = None

    def _advance_ready(self):
        now, end, live = self._time_state()
        if self.ready == self.cfg['active'] and self._target_since is not None:
            self.ready_at_target_seconds += max(0.0, end - self.ready_changed)
            if not live or self._tracking_ended:
                self._end_target_interval(end)
        self.ready_changed = end
        return now, end, live

    def _require_business_live(self):
        now, end, live = self._advance_ready()
        if not live:
            raise AuthError(self._clock_error or 'lab_deadline_reached', 503)
        return now, end

    def budget(self, *, controller=False):
        """Preserve total budgets; only bounded control cleanup gets grace."""
        with self.lease_lock:
            now, _, _ = self._advance_ready()
            until = self.deadline + (TOKEN_GRACE_SECONDS if controller else 0)
            if self._database_closed or now >= until:
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
            self._require_business_live()
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
            now = int(self.clock())
            with self.lock, self.db:
                self.db.execute('INSERT INTO challenges(device_hash,user_code,account,match_id,created,expires,'
                    'approved_steam,approved_at,token_hash,token_expires,revoked,last_poll) VALUES(?,?,?,?,?,?,?,?,?,?,0,0)',
                    (device, 'LT' + secrets.token_hex(8), raw_account, match, now, self.token_expires_at,
                     str(STEAM_BASE + int(raw_account)), now, digest(internal_token), self.token_expires_at))
            reply = {'ok': True, 'run_id': self.cfg['run_id'], 'account_id': raw_account,
                     'match_session_id': match, 'access_token': 'lt1_' + internal_token[5:],
                     'expires_at': self.token_expires_at, 'synthetic_only': True}
            self.leases[lease] = {'reply': reply, 'released': False, 'device': device, 'ready': False}
            self.next_index += 1; self.active += 1
            return dict(reply)

    def release(self, payload):
        if (not isinstance(payload, dict) or set(payload) != {'run_id', 'lease_id'}
                or payload.get('run_id') != self.cfg['run_id']):
            raise AuthError('invalid_lab_lease', 400)
        with self.lease_lock:
            _, end, _ = self._advance_ready()
            value = self.leases.get(payload.get('lease_id'))
            if value is None:
                raise AuthError('unknown_lab_lease', 404)
            if not value['released']:
                if self._database_closed:
                    raise AuthError('lab_deadline_reached', 503)
                with self.lock, self.db:
                    self.db.execute('UPDATE challenges SET revoked=1 WHERE device_hash=?', (value['device'],))
                value['released'] = True; self.active -= 1
                if value['ready']:
                    self.ready -= 1
                    self._end_target_interval(end)
            return {'ok': True}

    def mark_ready(self, payload):
        if not isinstance(payload, dict) or set(payload) != {'run_id', 'lease_id'} or payload['run_id'] != self.cfg['run_id']:
            raise AuthError('invalid_lab_lease', 400)
        with self.lease_lock:
            _, at = self._require_business_live()
            value = self.leases.get(payload.get('lease_id'))
            if value is None or value['released']:
                raise AuthError('unknown_lab_lease', 404)
            if not value['ready']:
                value['ready'] = True; self.ready += 1
                self.max_ready = max(self.max_ready, self.ready)
                if self.ready == self.cfg['active'] and not self._tracking_ended:
                    self._target_since = at
            return {'ok': True}

    def counts(self):
        """Fixed aggregates only; raw marked/lease counts are never fabricated."""
        with self.lease_lock:
            now, _, business_live = self._advance_ready()
            # These public flags describe measurement validity. An already
            # accepted request may remain authorized during shutdown drain.
            live = business_live and not self._tracking_ended
            current = max(0.0, now - self._target_since) if live and self._target_since is not None else 0.0
            elapsed = max(0.0, now - self._started_monotonic)
            relative = lambda value: None if value is None else round(max(0.0, value - self._started_monotonic), 6)
            return {'issued': self.next_index, 'active_leases': self.active,
                    'client_confirmed_ready': self.ready, 'max_client_confirmed_ready': self.max_ready,
                    'seconds_at_target_ready': round(self.ready_at_target_seconds, 6),
                    'effective_ready': self.ready if live else 0, 'ready_valid': live,
                    'target_ready_since_seconds': relative(self._target_since),
                    'target_ready_last_ended_seconds': relative(self._target_last_ended),
                    'target_ready_current_seconds': round(current, 6),
                    'target_ready_longest_seconds': round(max(self._target_longest_seconds, current), 6),
                    'run_live': live, 'closed': self._tracking_ended or self._database_closed,
                    'clock_valid': self._clock_error is None, 'clock_error': self._clock_error,
                    'run_elapsed_seconds': round(elapsed, 6),
                    'business_remaining_seconds': round(max(0.0, self.deadline - now), 6),
                    'controller_remaining_seconds': round(max(0.0, self.deadline + TOKEN_GRACE_SECONDS - now), 6),
                    'synthetic_token_expires_at': self.token_expires_at,
                    'token_grace_seconds': TOKEN_GRACE_SECONDS, 'status_requests': self._status_requests}

    def identity_policy(self):
        return {'kind': 'RUN_BOUND_SYNTHETIC_IDENTITY_V1',
                'synthetic_only': True, 'production_auth_refresh_covered': False,
                'run_duration_seconds': self.cfg['duration_seconds'],
                'token_expires_at': self.token_expires_at,
                'token_grace_seconds': TOKEN_GRACE_SECONDS,
                'clock_skew_seconds': CLOCK_SKEW_SECONDS,
                'clock_precision_seconds': CLOCK_PRECISION_SECONDS,
                'clock_source': 'wall_expiry_with_sticky_monotonic_skew_guard',
                'clock_failure_accounting': 'freeze_at_last_verified_monotonic',
                'status_run_live_semantics': 'measurement_live_not_server_or_auth_liveness',
                'measurement_ends_before_shutdown_drain': True,
                'accepted_business_may_finish_after_measurement_end': True,
                'automatic_token_refresh': False, 'automatic_account_replacement': False}

    def status(self, nonce):
        if type(nonce) is not str or not re.fullmatch('[a-f0-9]{32}', nonce):
            raise AuthError('lab_nonce_required', 400)
        with self.lease_lock:
            self._status_requests += 1
            return sign_status(self.cfg['run_id'], self._manifest_sha256, self.private['controller'],
                               nonce, self.counts(), active_budget=self.cfg['active'],
                               account_budget=self.cfg['accounts'])

    def end_tracking(self):
        with self.lease_lock:
            if not self._tracking_ended:
                _, end, _ = self._advance_ready()
                self._end_target_interval(end)
                self._tracking_ended = True
                self._closed_at = end

    def close(self):
        with self.lease_lock:
            self.end_tracking()
            if not self._database_closed:
                super().close()
                self._database_closed = True

    def principal(self, bearer, payload):
        if not isinstance(bearer, str) or not re.fullmatch('lt1_[a-f0-9]{64}', bearer):
            raise AuthError('lab_session_required', 403)
        with self.lease_lock:
            self._require_business_live()
        return super().principal('pwa1_' + bearer[4:], payload)

    def rate(self, scope, actor, maximum):
        if scope == 'global-http':
            maximum = self.cfg['global_http_per_minute']
        return super().rate(scope, actor, maximum)

    def proxy(self, path, bearer, payload, peer):
        if path not in {'/v1/session/authenticate', '/v1/session/login', '/v1/profile',
                        '/v1/archive/config', '/v1/lottery/catalog', '/v1/lottery/snapshot',
                        '/v1/archive/command', '/v1/archive/endless-batch', '/v1/online-time/checkpoint'}:
            raise AuthError('lab_business_route_not_allowed', 403)
        if path == '/v1/archive/command' and (not isinstance(payload, dict)
                or not isinstance(payload.get('command'), dict)
                or payload['command'].get('kind') not in ('lottery_draw', 'benefit_claim', 'daily_claim')):
            raise AuthError('lab_business_command_not_allowed', 403)
        if path == '/v1/archive/endless-batch':
            commands = payload.get('commands') if isinstance(payload, dict) else None
            if (type(commands) is not list or not 1 <= len(commands) <= 32
                    or any(type(command) is not dict or command.get('kind') != 'endless'
                           for command in commands)):
                raise AuthError('lab_business_command_not_allowed', 403)
        return super().proxy(path, bearer, payload, peer)
