"""Bounded, content-free timings for real archive commands.

One record per command, no polling or extra database/HTTP calls. Stages may nest
(finish includes worker/commit), so their times must not be added together.
The outer HTTP authentication, match context/projection and transit are outside
this boundary. A missing record is not proof that a request never arrived.
"""
from contextlib import contextmanager
from contextvars import ContextVar
import json
import sys
from time import perf_counter_ns, time

_ACTIVE = ContextVar('archive_command_timing', default=None)
_STAGES = frozenset({'ensure', 'prepare', 'finish', 'public', 'snapshot',
                     'worker_wait', 'worker', 'worker_decode', 'commit', 'resume'})
PREFIX = 'SURVIVAL_ARCHIVE_TIMING '
MAX_RECORD_BYTES = 2048


def _emit(record):
    # A completed grant must not turn into an apparent failure if journald or
    # stdout is unavailable. No exceptions, payloads, identifiers or secrets
    # are included. This is one bounded write, not a recursively logging sink.
    try:
        line = PREFIX + json.dumps(record, separators=(',', ':'), allow_nan=False) + '\n'
        if len(line.encode('utf-8')) <= MAX_RECORD_BYTES:
            sys.stdout.write(line)
            sys.stdout.flush()
    except Exception:
        pass


class CommandTiming:
    def __init__(self, payload, allowed_kinds):
        command = payload.get('command') if isinstance(payload, dict) else None
        command = command if isinstance(command, dict) else {}
        kind = command.get('kind')
        self.kind = kind if isinstance(kind, str) and kind in allowed_kinds else 'other'
        count = command.get('count')
        self.count = count if self.kind == 'lottery_draw' and type(count) is int and count in (1, 10) else 0
        self.stages = {}
        self.outcome = 'exception'

    def __enter__(self):
        self.started = perf_counter_ns()
        self.token = _ACTIVE.set(self)
        return self

    def result(self, value):
        if not isinstance(value, dict):
            self.outcome = 'other'
        elif value.get('ok') is True:
            self.outcome = 'ok'
        elif value.get('terminal') is True:
            self.outcome = 'rejected'
        else:
            self.outcome = 'incomplete'

    def __exit__(self, error_type, error, traceback):
        _ACTIVE.reset(self.token)
        # Diagnostic failures must never mask either a real error or a receipt.
        try:
            elapsed = max(0, min(86400000, (perf_counter_ns() - self.started) / 1000000))
            record = {'v': 1, 'at_ms': int(time() * 1000), 'kind': self.kind,
                      'count': self.count, 'outcome': 'exception' if error_type else self.outcome,
                      'total_ms': round(elapsed, 3), 'stages': self.stages}
            _emit(record)
        except Exception:
            pass
        return False


@contextmanager
def measure(stage):
    active = _ACTIVE.get()
    if active is None or stage not in _STAGES:
        yield
        return
    started = perf_counter_ns()
    try:
        yield
    finally:
        elapsed = max(0, min(86400000, (perf_counter_ns() - started) / 1000000))
        previous = active.stages.get(stage, [0, 0])
        active.stages[stage] = [min(65535, previous[0] + 1),
                                round(min(86400000, previous[1] + elapsed), 3)]
