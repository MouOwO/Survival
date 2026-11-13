"""Exact-parent targeted pool notification overlay; preparation only.

The old bounded_pool.py and all PostgreSQL/transaction code stay unchanged.
Only one fixed runtime helper is replaced after reversible substitutions.
"""
from __future__ import annotations
import ast
import hashlib
from pathlib import Path

RUNTIME_PATH = 'fishing_api/_bounded_pool.py'
BASELINE_SHA256 = '5667e169930c644765e703d142b377a4db9b63296cd2555e5ba1a36ea7847e8a'
HELPER_SHA256 = '491faf942badc6033e1f5fb859e10eebf34e60d2ea15ff66202c547b4630d063'
MARKER = '# SURVIVAL_TARGETED_POOL_NOTIFY_V1'
REPLACEMENTS = (('Borrow/return bookkeeping is O(1); condition notifications wake O(W) bounded\nwaiters (W<=4 in the reviewed transport). Storage is O(max_size + max_waiters).\nThere is no maintenance thread, reconnect loop, user scan, or database query here.\nOnly shutdown traverses the at-most-16 idle connections. A failed close keeps\n', 'Borrow/return bookkeeping and normal head notification are O(1). Each ticket\nhas its own condition on one explicit shared RLock. Storage is O(size + waiters),\nwith size<=16 and waiters<=32. Closure wakes O(waiters) and closes <=16 idle\nconnections. notify_calls counts Condition.notify(1) attempts, not delivered\nwakes or native elapsed time. No thread, RPC retry, user scan or extra SQL is added.\nA failed close keeps\n'), ('        self._condition = threading.Condition()\n', '        # SURVIVAL_TARGETED_POOL_NOTIFY_V1\n        self._lock = threading.RLock()\n        self._condition = threading.Condition(self._lock)\n'), ('        self._waiters: OrderedDict[object, None] = OrderedDict()\n', '        self._waiters: OrderedDict[object, threading.Condition] = OrderedDict()\n'), ('                            max_connections=0)\n', '                            max_connections=0, notify_calls=0)\n'), ('    def acquire(self) -> Any:\n', "    def _notify_head_locked(self) -> None:\n        # The caller holds the explicit shared RLock. Notification grants no\n        # ownership; the original FIFO/deadline checks still decide each lease.\n        if self._waiters and not self._closed:\n            self._counts['notify_calls'] += 1\n            next(iter(self._waiters.values())).notify(1)\n\n    def _notify_closed_waiters_locked(self) -> None:\n        # Closure is the only O(Q) wakeup. No connection is directly handed off.\n        for condition in self._waiters.values():\n            self._counts['notify_calls'] += 1\n            condition.notify(1)\n\n    def acquire(self) -> Any:\n"), ('                        self._waiters[ticket] = None\n', '                        self._waiters[ticket] = threading.Condition(self._lock)\n'), ('                    self._condition.wait(max(0.0, until - time.monotonic()))\n', '                    self._waiters[ticket].wait(max(0.0, until - time.monotonic()))\n'), ('                    self._waiters.pop(ticket)\n                    self._condition.notify_all()\n', '                    self._waiters.pop(ticket)\n                    self._notify_head_locked()\n'), ('                self._counts["connect_failed"] += 1\n                self._condition.notify_all()\n', '                self._counts["connect_failed"] += 1\n                self._notify_head_locked()\n'), ('                self._closed = True\n                self._total -= 1\n                self._condition.notify_all()\n', '                self._closed = True\n                self._total -= 1\n                self._notify_closed_waiters_locked()\n'), ('                self._counts["returned"] += 1\n                self._condition.notify_all()\n', '                self._counts["returned"] += 1\n                self._notify_head_locked()\n'), ('            self._condition.notify_all()\n\n    def note_reset_failed', '            self._notify_head_locked()\n\n    def note_reset_failed'), ('            self._closing += len(connections)\n            self._condition.notify_all()\n', '            self._closing += len(connections)\n            self._notify_closed_waiters_locked()\n'))


def _normalized(source):
    if type(source) is not str:
        raise ValueError('pool_notify_source_invalid')
    result = source.replace('\r\n', '\n')
    if '\r' in result:
        raise ValueError('pool_notify_source_invalid')
    return result


def _sha(source):
    return hashlib.sha256(source.encode('utf8')).hexdigest()


def _replace(source, reverse=False):
    pairs = ((new, old) for old, new in reversed(REPLACEMENTS)) if reverse else REPLACEMENTS
    result = source
    for before, after in pairs:
        if result.count(before) != 1:
            raise ValueError('pool_notify_patch_anchor_invalid')
        result = result.replace(before, after, 1)
    return result


def patch_pool(source):
    source = _normalized(source)
    if MARKER in source:
        parent = _replace(source, reverse=True)
        if _sha(source) != HELPER_SHA256 or _sha(parent) != BASELINE_SHA256:
            raise ValueError('pool_notify_patched_source_changed')
    else:
        parent = source
        if _sha(parent) != BASELINE_SHA256:
            raise ValueError('pool_notify_source_baseline_mismatch')
    try:
        helper = _normalized(Path(__file__).with_name('bounded_pool_notify.py').read_text(encoding='utf-8-sig'))
    except (OSError, UnicodeError):
        raise ValueError('pool_notify_helper_unavailable') from None
    if _sha(helper) != HELPER_SHA256:
        raise ValueError('pool_notify_helper_changed')
    result = _replace(parent)
    restored = _replace(result, reverse=True)
    if result != helper or restored != parent or ast.dump(ast.parse(restored)) != ast.dump(ast.parse(parent)):
        raise ValueError('pool_notify_unrelated_change')
    compile(result, '<reviewed-targeted-pool-notify>', 'exec')
    return result


def patch_sources(sources):
    if type(sources) is not dict or set(sources) != {RUNTIME_PATH}:
        raise ValueError('pool_notify_source_set_invalid')
    return {RUNTIME_PATH: patch_pool(sources[RUNTIME_PATH])}
