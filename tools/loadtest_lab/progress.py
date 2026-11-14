"""Bounded per-actor successful-business progress for isolated load tests.

No network, database, game, or background work is performed by this module.
For N active actors, registration totals O(N log N), memory O(N), stable success
costs O(log N), and snapshots cost O(1) plus at most a bounded expiration batch.
The indexed heap retains one entry per live actor. No lazy duplicate growth or
full actor scan occurs during updates, snapshots, expiry, or departure.
"""
from __future__ import annotations
import math
import threading
import time

PROFILE_ID = 'active-business-v1'
TTL_SECONDS = 120
MAX_ACTORS = 10000


def validate_profile(cfg):
    if 'actor_progress' not in cfg:
        return None
    row = cfg['actor_progress']
    if (type(row) is not dict or set(row) != {'id', 'ttl_seconds'}
            or row['id'] != PROFILE_ID or type(row['ttl_seconds']) is not int
            or row['ttl_seconds'] != TTL_SECONDS
            or cfg.get('purpose') != 'capacity'
            or cfg.get('client_workload') != 'client-v3'
            or type(cfg.get('active')) is not int
            or not 1 <= cfg['active'] <= MAX_ACTORS
            or type(cfg.get('accounts')) is not int
            or not cfg['active'] <= cfg['accounts'] <= 1000000):
        raise ValueError('loadtest_actor_progress_profile_invalid')
    return row


def _number(value):
    return type(value) in (int, float) and math.isfinite(value)


class _Actor:
    __slots__ = ('owner', 'last_success', 'expires', 'position')

    def __init__(self, owner, last_success, expires):
        self.owner = owner
        self.last_success = last_success
        self.expires = expires
        self.position = -1


class ProgressIndex:
    def __init__(self, target, account_span, *, ttl_seconds=TTL_SECONDS,
                 clock=time.monotonic, batch_limit=64, budget_ms=2):
        if (type(target) is not int or not 1 <= target <= MAX_ACTORS
                or type(account_span) is not int or not target <= account_span <= 1000000
                or not _number(ttl_seconds) or not 0 < ttl_seconds <= 300
                or type(batch_limit) is not int or not 1 <= batch_limit <= 256
                or not _number(budget_ms) or not 0 < budget_ms <= 1000):
            raise ValueError('loadtest_actor_progress_options_invalid')
        self.target, self.account_span = target, account_span
        self.ttl, self.clock = ttl_seconds, clock
        self.batch_limit, self.budget_ns = batch_limit, int(budget_ms * 1000000)
        self._actors, self._heap = {}, []
        self._lock = threading.RLock()
        self._valid, self._error, self._last_clock = True, None, None
        self._since = self._best_start = self._best_end = None
        self._completed_start = self._completed_end = self._current_end = None
        self._frozen_at = None
        self._ops = dict(comparisons=0, swaps=0, expiry_pops=0,
                         expiration_budget_yields=0, successes=0,
                         registrations=0, departures=0, snapshots=0)
        self._created = self._now()

    def _now(self):
        if not self._valid:
            raise ValueError('loadtest_actor_progress_clock_invalid')
        try:
            now = self.clock()
        except Exception:
            now = None
        if not _number(now) or now < 0 or self._last_clock is not None and now < self._last_clock:
            self._close_span()
            self._valid, self._error = False, 'clock_invalid'
            raise ValueError('loadtest_actor_progress_clock_invalid')
        self._last_clock = now
        return now

    def _close_span(self):
        if self._since is not None and self._current_end is not None:
            current = self._current_end - self._since
            best = (-1 if self._completed_start is None else
                    self._completed_end - self._completed_start)
            if current > best:
                self._completed_start, self._completed_end = self._since, self._current_end
        self._since = self._current_end = None

    def _less(self, left, right):
        self._ops['comparisons'] += 1
        a, b = self._heap[left], self._heap[right]
        ae, be = self._actors[a].expires, self._actors[b].expires
        return ae < be or ae == be and a < b

    def _swap(self, a, b):
        self._ops['swaps'] += 1
        self._heap[a], self._heap[b] = self._heap[b], self._heap[a]
        self._actors[self._heap[a]].position = a
        self._actors[self._heap[b]].position = b

    def _up(self, position):
        while position:
            parent = (position - 1) // 2
            if not self._less(position, parent):
                break
            self._swap(position, parent)
            position = parent

    def _down(self, position):
        size = len(self._heap)
        while position * 2 + 1 < size:
            child = position * 2 + 1
            if child + 1 < size and self._less(child + 1, child):
                child += 1
            if not self._less(child, position):
                break
            self._swap(child, position)
            position = child

    def _remove(self, slot):
        state = self._actors[slot]
        position = state.position
        if not 0 <= position < len(self._heap) or self._heap[position] != slot:
            raise ValueError('loadtest_actor_progress_heap_invalid')
        last = self._heap.pop()
        state.position = -1
        if position < len(self._heap):
            self._heap[position] = last
            self._actors[last].position = position
            if position and self._less(position, (position - 1) // 2):
                self._up(position)
            else:
                self._down(position)

    def _set_expiry(self, slot, expiry):
        state = self._actors[slot]
        previous, position = state.expires, state.position
        state.expires = expiry
        if position < 0:
            state.position = len(self._heap)
            self._heap.append(slot)
            self._up(state.position)
        elif expiry < previous:
            self._up(position)
        else:
            self._down(position)

    def _pending(self, now):
        return bool(self._heap and self._actors[self._heap[0]].expires <= now)

    def _expire(self, now):
        if self._pending(now):
            self._close_span()
        started, removed = time.perf_counter_ns(), 0
        while self._pending(now):
            if removed >= self.batch_limit or time.perf_counter_ns() - started >= self.budget_ns:
                self._ops['expiration_budget_yields'] += 1
                return False
            self._remove(self._heap[0])
            removed += 1
            self._ops['expiry_pops'] += 1
        return True

    def _qualify(self, now):
        complete = not self._pending(now)
        all_active = (self._valid and complete and len(self._actors) == self.target
                      and len(self._heap) == self.target)
        if not all_active:
            self._close_span()
        elif self._frozen_at is None:
            if self._since is None:
                self._since = now
            self._current_end = now
            current = now - self._since
            best = 0 if self._best_start is None else self._best_end - self._best_start
            if self._best_start is None or current >= best:
                self._best_start, self._best_end = self._since, now
        return complete, all_active

    def register(self, slot, owner, last_success):
        with self._lock:
            now = self._now()
            if (type(slot) is not int or not 0 <= slot < self.account_span
                    or owner is None or slot in self._actors
                    or len(self._actors) >= self.target
                    or not _number(last_success) or not 0 <= last_success <= now):
                raise ValueError('loadtest_actor_progress_registration_invalid')
            self._expire(now)
            self._actors[slot] = _Actor(owner, last_success, last_success + self.ttl)
            if last_success + self.ttl > now:
                self._set_expiry(slot, last_success + self.ttl)
            self._ops['registrations'] += 1
            self._qualify(now)

    def success(self, slot, owner):
        with self._lock:
            now = self._now()
            state = self._actors.get(slot)
            if state is None or state.owner is not owner:
                raise ValueError('loadtest_actor_progress_owner_invalid')
            self._expire(now)
            state.last_success = now
            self._set_expiry(slot, now + self.ttl)
            self._ops['successes'] += 1
            self._qualify(now)

    def depart(self, slot, owner):
        with self._lock:
            now = self._now()
            state = self._actors.get(slot)
            if state is None or state.owner is not owner:
                raise ValueError('loadtest_actor_progress_owner_invalid')
            self._expire(now)
            if state.position >= 0:
                self._remove(slot)
            del self._actors[slot]
            self._ops['departures'] += 1
            self._qualify(now)

    def freeze(self, at=None):
        with self._lock:
            previous_clock = self._last_clock
            now = self._now()
            if self._frozen_at is not None:
                raise ValueError('loadtest_actor_progress_already_frozen')
            if at is None:
                at = now
            if not _number(at) or not previous_clock <= at <= now:
                raise ValueError('loadtest_actor_progress_freeze_invalid')
            self._expire(now)
            self._qualify(now)
            candidates = []
            for start, end in ((self._completed_start, self._completed_end),
                               (self._since, self._current_end)):
                if start is not None and start <= at:
                    candidates.append((start, min(end, at)))
            self._best_start, self._best_end = (max(candidates, key=lambda x: x[1] - x[0])
                                               if candidates else (None, None))
            self._completed_start, self._completed_end = self._best_start, self._best_end
            self._since = self._current_end = None
            self._frozen_at = at

    def snapshot(self):
        with self._lock:
            self._ops['snapshots'] += 1
            try:
                now = self._now()
                self._expire(now)
                complete, all_active = self._qualify(now)
                earliest = (None if not self._heap else
                            self._actors[self._heap[0]].expires)
            except (ValueError, IndexError, KeyError):
                self._close_span()
                self._valid = False
                self._error = self._error or 'index_invalid'
                now = self._last_clock if self._last_clock is not None else 0
                complete, all_active, earliest = False, False, None
            return dict(v=1, target=self.target, ttl_seconds=self.ttl,
                        registered=len(self._actors), active=len(self._heap),
                        expiration_complete=complete, all_active=all_active,
                        clock_valid=self._valid, error=self._error,
                        at_monotonic=now, created_monotonic=self._created,
                        earliest_expiry=earliest,
                        full_since_monotonic=self._since,
                        best_start_monotonic=self._best_start,
                        best_end_monotonic=self._best_end,
                        best_seconds=(0 if self._best_start is None else
                                      self._best_end - self._best_start),
                        frozen_at_monotonic=self._frozen_at,
                        operations=dict(self._ops))


# One bounded observation stream per local worker. No actor IDs or credentials
# are serialized. A 5-second sampler over the maximum 5-hour lease fits 5000 rows.
import hashlib
import hmac
import json
import os
from pathlib import Path
import re

_LOG_LIMIT = 16 * 1024 * 1024
_ROW_LIMIT = 8192
_RECORD_LIMIT = 5000
_DOMAIN = b'survival-client-progress-v1\0'
_SNAPSHOT_KEYS = frozenset(('v', 'target', 'ttl_seconds', 'registered', 'active',
    'expiration_complete', 'all_active', 'clock_valid', 'error', 'at_monotonic',
    'created_monotonic', 'earliest_expiry', 'full_since_monotonic',
    'best_start_monotonic', 'best_end_monotonic', 'best_seconds',
    'frozen_at_monotonic', 'operations'))


def _canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'),
                      ensure_ascii=True, allow_nan=False).encode('ascii')


def _binding(run_id, manifest_sha256, stage_id, worker_pid, controller):
    if (not isinstance(run_id, str) or re.fullmatch('[a-f0-9]{32}', run_id) is None
            or not isinstance(manifest_sha256, str)
            or re.fullmatch('[a-f0-9]{64}', manifest_sha256) is None
            or not isinstance(stage_id, str)
            or re.fullmatch('[A-Za-z0-9_-]{1,100}', stage_id) is None
            or type(worker_pid) is not int or worker_pid <= 0
            or not isinstance(controller, str)
            or re.fullmatch('[a-f0-9]{64}', controller) is None):
        raise ValueError('loadtest_progress_binding_invalid')
    return dict(run_id=run_id, manifest_sha256=manifest_sha256,
                stage_id=stage_id, worker_pid=worker_pid)


class ProgressObservation:
    """O(1) record work plus bounded index expiry; one bounded file read at finish."""
    def __init__(self, index, folder, *, run_id, manifest_sha256, controller,
                 worker_pid=None, wall_clock=time.time):
        folder = Path(folder)
        if not folder.is_dir() or folder.is_symlink():
            raise ValueError('loadtest_progress_directory_invalid')
        self.binding = _binding(run_id, manifest_sha256, folder.name,
                                os.getpid() if worker_pid is None else worker_pid, controller)
        self.index, self._key, self._wall = index, controller.encode('ascii'), wall_clock
        self.path = folder / 'client_progress.jsonl'
        self._file = self.path.open('xb')
        self._sequence, self._bytes, self._error, self._result = 0, 0, None, None

    def sample(self, *, final=False):
        if self._result is not None or self._error is not None:
            return False
        try:
            snapshot = self.index.snapshot()
            wall = self._wall()
            if not _number(wall) or wall <= 0:
                raise ValueError('clock')
            if final and snapshot['frozen_at_monotonic'] is None:
                raise ValueError('not_frozen')
            value = dict(self.binding, sequence=self._sequence + 1,
                         at_utc_epoch=wall, snapshot=snapshot, final=bool(final))
            signature = hmac.new(self._key, _DOMAIN + _canonical(value), hashlib.sha256).hexdigest()
            raw = _canonical(dict(value, signature=signature)) + b'\n'
            if (len(raw) > _ROW_LIMIT or self._bytes + len(raw) > _LOG_LIMIT
                    or self._sequence >= _RECORD_LIMIT):
                raise ValueError('limit')
            self._file.write(raw)
            self._file.flush()
            self._sequence += 1
            self._bytes += len(raw)
            return True
        except Exception:
            self._error = 'progress_observation_not_confirmed'
            return False

    def finish(self):
        if self._result is not None:
            return dict(self._result)
        complete = self.sample(final=True)
        try:
            self._file.close()
            raw = self.path.read_bytes()
            if len(raw) != self._bytes or len(raw) > _LOG_LIMIT:
                raise ValueError('length')
            digest = hashlib.sha256(raw).hexdigest()
        except Exception:
            complete, digest = False, None
            self._error = 'progress_observation_not_confirmed'
        self._result = dict(v=1, **self.binding, complete=bool(complete),
                            records=self._sequence, bytes=self._bytes,
                            sha256=digest, error=self._error)
        return dict(self._result)


def _unique_object(pairs):
    value = {}
    for key, item in pairs:
        if key in value:
            raise ValueError('loadtest_progress_duplicate_key')
        value[key] = item
    return value


def _reject_constant(_):
    raise ValueError('loadtest_progress_nonfinite_json')


def verify_progress(path, summary, *, run_id, manifest_sha256, stage_id,
                    worker_pid, controller, target, max_sample_gap=15):
    """Read one closed worker stream, O(records), bounded by 16 MiB/5000 rows.

    This is source-bound instrumentation evidence, not a hostile-client proof.
    It adds no HTTP calls and never replaces server-ready, SQL or latency gates.
    """
    binding = _binding(run_id, manifest_sha256, stage_id, worker_pid, controller)
    expected = dict(v=1, **binding, complete=True, records=summary.get('records'),
                    bytes=summary.get('bytes'), sha256=summary.get('sha256'), error=None)
    if (summary != expected or type(target) is not int or not 1 <= target <= MAX_ACTORS
            or not _number(max_sample_gap) or not 0 < max_sample_gap <= 15):
        raise ValueError('loadtest_progress_summary_invalid')
    path = Path(path)
    if path.is_symlink() or path.stat().st_size > _LOG_LIMIT:
        raise ValueError('loadtest_progress_file_invalid')
    raw = path.read_bytes()
    lines = raw.splitlines()
    if (len(raw) != summary['bytes'] or hashlib.sha256(raw).hexdigest() != summary['sha256']
            or len(lines) != summary['records'] or not 1 <= len(lines) <= _RECORD_LIMIT
            or any(not line or len(line) + 1 > _ROW_LIMIT for line in lines)):
        raise ValueError('loadtest_progress_file_invalid')
    previous, created, final = None, None, None
    key = controller.encode('ascii')
    for sequence, line in enumerate(lines, 1):
        row = json.loads(line, object_pairs_hook=_unique_object, parse_constant=_reject_constant)
        if type(row) is not dict:
            raise ValueError('loadtest_progress_record_invalid')
        signature = row.pop('signature', None)
        if (set(row) != set(binding) | {'sequence', 'at_utc_epoch', 'snapshot', 'final'}
                or any(row[name] != value for name, value in binding.items())
                or type(row['sequence']) is not int or row['sequence'] != sequence
                or type(row['final']) is not bool or row['final'] != (sequence == len(lines))
                or not _number(row['at_utc_epoch']) or row['at_utc_epoch'] <= 0
                or not isinstance(signature, str)
                or not hmac.compare_digest(signature, hmac.new(key, _DOMAIN + _canonical(row), hashlib.sha256).hexdigest())):
            raise ValueError('loadtest_progress_record_invalid')
        state = row['snapshot']
        if type(state) is not dict or set(state) != _SNAPSHOT_KEYS:
            raise ValueError('loadtest_progress_snapshot_invalid')
        at, start, end, frozen = (state[k] for k in ('at_monotonic', 'best_start_monotonic',
                                                   'best_end_monotonic', 'frozen_at_monotonic'))
        if (state['v'] != 1 or state['target'] != target or state['ttl_seconds'] != TTL_SECONDS
                or not state['clock_valid'] or state['error'] is not None
                or any(type(state[k]) is not bool for k in ('clock_valid', 'expiration_complete', 'all_active'))
                or any(type(state[k]) is not int for k in ('registered', 'active'))
                or not 0 <= state['active'] <= state['registered'] <= target
                or not _number(at) or not _number(state['created_monotonic'])
                or not 0 <= state['created_monotonic'] <= at):
            raise ValueError('loadtest_progress_snapshot_invalid')
        if created is None:
            created = state['created_monotonic']
        if created != state['created_monotonic'] or previous is not None and at < previous['at_monotonic']:
            raise ValueError('loadtest_progress_clock_invalid')
        if previous is not None and previous['frozen_at_monotonic'] is None:
            gap_end = at if frozen is None else frozen
            if gap_end - previous['at_monotonic'] > max_sample_gap:
                raise ValueError('loadtest_progress_sampler_gap')
        if frozen is not None and (not _number(frozen) or not created <= frozen <= at):
            raise ValueError('loadtest_progress_freeze_invalid')
        if previous is not None and previous['frozen_at_monotonic'] is not None:
            if frozen != previous['frozen_at_monotonic'] or state['best_seconds'] != previous['best_seconds']:
                raise ValueError('loadtest_progress_freeze_changed')
        if start is None:
            if end is not None or state['best_seconds'] != 0:
                raise ValueError('loadtest_progress_span_invalid')
        elif (not _number(start) or not _number(end) or not _number(state['best_seconds'])
              or not created <= start <= end <= (at if frozen is None else frozen)
              or not math.isclose(end - start, state['best_seconds'], rel_tol=0, abs_tol=1e-8)):
            raise ValueError('loadtest_progress_span_invalid')
        if state['all_active'] and (state['registered'] != target or state['active'] != target
                or not state['expiration_complete'] or not _number(state['earliest_expiry'])
                or state['earliest_expiry'] <= at):
            raise ValueError('loadtest_progress_active_invalid')
        if row['final'] and frozen is None:
            raise ValueError('loadtest_progress_final_not_frozen')
        previous, final = state, state
    return dict(v=1, **binding, records=len(lines), verified=True,
                best_seconds=final['best_seconds'], best_start_monotonic=final['best_start_monotonic'],
                best_end_monotonic=final['best_end_monotonic'],
                frozen_at_monotonic=final['frozen_at_monotonic'])
