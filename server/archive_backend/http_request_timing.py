"""Bounded, content-free WS4 HTTP/RPC stage observations; no cached authority.

One record for selected user commands, at most 60/minute, 300 per process and
24 hours. No timers or extra HTTP/DB calls. Each measured operation updates a
fixed stage/counter map: O(1) per boundary, constant bounded retained state.
Nested stage durations overlap; they must never be summed as disjoint work.
"""
from contextlib import contextmanager
from contextvars import ContextVar
from functools import wraps
import json
import sys
import threading
import time

PREFIX = 'SURVIVAL_HTTP_TIMING '
MAX_RECORD_BYTES = 4096
KINDS = frozenset(('lottery_draw', 'daily_claim', 'benefit_claim', 'vip_claim',
                   'commerce_purchase', 'redemption_redeem', 'building_upgrade', 'work_upgrade'))
STAGES = frozenset(('authorize', 'body', 'context', 'command', 'project', 'serialize', 'write',
                    'rpc', 'db_connect', 'db_guard', 'db_role_guard', 'db_function_guard',
                    'db_query', 'db_commit', 'db_rollback', 'db_close'))
RPCS = frozenset(('match_profile_context', 'ensure_player_gameplay_stats', 'archive_prepare',
                  'archive_commit', 'archive_commit_lottery', 'archive_commit_challenge',
                  'archive_resume', 'redemption_prepare', 'redemption_commit',
                  'archive_pending', 'archive_online_pending', 'get_fishing_profile'))
_ACTIVE = ContextVar('archive_http_timing', default=None)


def _clock():
    try:
        return time.perf_counter_ns()
    except Exception:
        return None


def _elapsed(start):
    end = _clock()
    return max(0, min(86400000, (end - start) / 1000000)) if start is not None and end is not None else 0


class Budget:
    def __init__(self, *, clock=time.monotonic, records=300, per_minute=60, lifetime=86400):
        self.clock, self.maximum, self.per_minute = clock, records, per_minute
        self.until, self.total, self.window, self.count = clock() + lifetime, 0, None, 0
        self.lock = threading.Lock()

    def take(self):
        with self.lock:
            now = self.clock()
            if now >= self.until or self.total >= self.maximum:
                return False
            window = int(now // 60)
            if window != self.window:
                self.window, self.count = window, 0
            if self.count >= self.per_minute:
                return False
            self.count += 1
            self.total += 1
            return True


_BUDGET = Budget()


def _emit(record):
    try:
        if not _BUDGET.take():
            return
        line = PREFIX + json.dumps(record, allow_nan=False, separators=(',', ':')) + '\n'
        if len(line.encode('utf8')) <= MAX_RECORD_BYTES:
            sys.stdout.write(line)
            sys.stdout.flush()
    except Exception:
        # Diagnostics must not turn a durable commit into an apparent failure.
        pass


class Trace:
    def __init__(self):
        self.started = _clock()
        self.kind, self.count, self.status, self.body_bytes = None, 0, 0, 0
        self.stages, self.rpcs = {}, {}
        self.outcome = 'ok'

    def finish(self):
        if self.kind not in KINDS:
            return
        try:
            _emit(dict(v=1, at_ms=int(time.time() * 1000), kind=self.kind, count=self.count,
                       status=self.status, body_bytes=self.body_bytes,
                       outcome=self.outcome if self.outcome=='exception' else 'http_error' if self.status>=400 else 'ok',
                       total_ms=round(_elapsed(self.started), 3), stages=self.stages, rpcs=self.rpcs))
        except Exception:
            pass


def request_span(function):
    @wraps(function)
    def observed(handler, *args, **kwargs):
        if handler.path != '/v1/archive/command':
            return function(handler, *args, **kwargs)
        trace = Trace()
        token = _ACTIVE.set(trace)
        try:
            return function(handler, *args, **kwargs)
        except BaseException:
            trace.outcome = 'exception'
            raise
        finally:
            _ACTIVE.reset(token)
            trace.finish()
    return observed


def identify(payload):
    trace = _ACTIVE.get()
    if trace is None:
        return
    command = payload.get('command') if isinstance(payload, dict) else None
    kind = command.get('kind') if isinstance(command, dict) else None
    if type(kind) is str and kind in KINDS:
        trace.kind = kind
        count = command.get('count')
        trace.count = count if kind == 'lottery_draw' and type(count) is int and count in (1, 10) else 0


def sent(status, body_bytes):
    trace = _ACTIVE.get()
    if trace is not None:
        trace.status = status if type(status) is int and 100 <= status <= 599 else 0
        trace.body_bytes = max(0, min(33554432, body_bytes)) if type(body_bytes) is int else 0


@contextmanager
def measure(stage):
    trace = _ACTIVE.get()
    if trace is None or stage not in STAGES:
        yield
        return
    start = _clock()
    try:
        yield
    finally:
        try:
            old = trace.stages.get(stage, [0, 0])
            trace.stages[stage] = [min(65535, old[0] + 1),
                                   round(min(86400000, old[1] + _elapsed(start)), 3)]
        except Exception:
            pass


@contextmanager
def rpc_span(name):
    trace = _ACTIVE.get()
    if trace is not None:
        key = name if type(name) is str and name in RPCS else 'other'
        trace.rpcs[key] = min(65535, trace.rpcs.get(key, 0) + 1)
    with measure('rpc'):
        yield
