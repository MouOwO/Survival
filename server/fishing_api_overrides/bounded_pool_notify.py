"""Small, process-local connection pool with bounded waiting and no RPC retries.

Borrow/return bookkeeping and normal head notification are O(1). Each ticket
has its own condition on one explicit shared RLock. Storage is O(size + waiters),
with size<=16 and waiters<=32. Closure wakes O(waiters) and closes <=16 idle
connections. notify_calls counts Condition.notify(1) attempts, not delivered
wakes or native elapsed time. No thread, RPC retry, user scan or extra SQL is added.
A failed close keeps
its capacity reserved rather than opening replacements past the hard limit.
"""
from __future__ import annotations

import math
import threading
import time
from collections import OrderedDict, deque
from contextlib import contextmanager
from contextvars import ContextVar
from typing import Any, Callable


_DEADLINE: ContextVar[float | None] = ContextVar("survival_db_deadline", default=None)


class PoolError(Exception):
    """Contains a fixed machine code, never connection diagnostics."""

    def __init__(self, code: str):
        self.code = code
        super().__init__(code)


@contextmanager
def request_deadline(until_monotonic: float):
    """Bind the existing HTTP absolute deadline, preserving nested shorter ones."""
    if (type(until_monotonic) not in (int, float)
            or not math.isfinite(until_monotonic)):
        raise ValueError("request_deadline_invalid")
    previous = _DEADLINE.get()
    until = min(previous, until_monotonic) if previous is not None else until_monotonic
    token = _DEADLINE.set(until)
    try:
        yield
    finally:
        _DEADLINE.reset(token)


def remaining_budget() -> float | None:
    until = _DEADLINE.get()
    return None if until is None else max(0.0, until - time.monotonic())


class BoundedConnectionPool:
    """Exclusive leases; at most max_size physical connections, including opens.

    `release(reusable=True)` requires the caller to have reset the connection
    and verified that it is idle. Any transaction error must release with False.
    A closed/expired known connection may be replaced before any RPC executes;
    a failed opening or RPC is never replayed here.
    """

    def __init__(self, opener: Callable[[], Any], *, max_size: int = 4,
                 max_waiters: int = 4, wait_timeout: float = 2.0,
                 reusable: Callable[[Any], bool]):
        if (not callable(opener) or not callable(reusable)
                or type(max_size) is not int or not 1 <= max_size <= 16
                or type(max_waiters) is not int or not 0 <= max_waiters <= 32
                or type(wait_timeout) not in (int, float)
                or not math.isfinite(wait_timeout) or not 0 < wait_timeout <= 5):
            raise ValueError("connection_pool_configuration_invalid")
        self._opener = opener
        self._reusable = reusable
        self._max_size = max_size
        self._max_waiters = max_waiters
        self._wait_timeout = float(wait_timeout)
        # SURVIVAL_TARGETED_POOL_NOTIFY_V1
        self._lock = threading.RLock()
        self._condition = threading.Condition(self._lock)
        self._idle: deque[Any] = deque()
        self._leased: dict[int, Any] = {}
        self._known: dict[int, Any] = {}
        self._waiters: OrderedDict[object, threading.Condition] = OrderedDict()
        self._quarantined: dict[int, Any] = {}
        self._total = 0
        self._connecting = 0
        self._closing = 0
        self._waiting = 0
        self._closed = False
        self._counts = dict(opened=0, reused=0, returned=0, discarded=0,
                            connect_failed=0, reset_failed=0, close_failed=0,
                            busy=0, timed_out=0, waited=0, max_waiting=0,
                            max_connections=0, notify_calls=0)

    def __repr__(self) -> str:
        return "BoundedConnectionPool()"

    def _deadline(self) -> float:
        now = time.monotonic()
        until = now + self._wait_timeout
        request_until = _DEADLINE.get()
        return min(until, request_until) if request_until is not None else until

    def _healthy(self, connection: Any) -> bool:
        try:
            return self._reusable(connection) is True
        except Exception:
            return False

    def _notify_head_locked(self) -> None:
        # The caller holds the explicit shared RLock. Notification grants no
        # ownership; the original FIFO/deadline checks still decide each lease.
        if self._waiters and not self._closed:
            self._counts['notify_calls'] += 1
            next(iter(self._waiters.values())).notify(1)

    def _notify_closed_waiters_locked(self) -> None:
        # Closure is the only O(Q) wakeup. No connection is directly handed off.
        for condition in self._waiters.values():
            self._counts['notify_calls'] += 1
            condition.notify(1)

    def acquire(self) -> Any:
        until = self._deadline()
        ticket = object()
        waiting = False
        connection = None
        with self._condition:
            try:
                while True:
                    if self._closed:
                        raise PoolError("database_unavailable")
                    if time.monotonic() >= until:
                        self._counts["timed_out"] += 1
                        raise PoolError("database_timeout")
                    eligible = (not self._waiters or waiting
                                and next(iter(self._waiters)) is ticket)
                    if eligible and self._idle:
                        connection = self._idle.pop()
                        self._leased[id(connection)] = connection
                        break
                    if eligible and self._total < self._max_size:
                        self._total += 1
                        self._connecting += 1
                        self._counts["max_connections"] = max(
                            self._counts["max_connections"], self._total)
                        break
                    if not waiting:
                        if self._waiting >= self._max_waiters:
                            self._counts["busy"] += 1
                            raise PoolError("database_busy")
                        self._waiting += 1
                        self._waiters[ticket] = threading.Condition(self._lock)
                        waiting = True
                        self._counts["waited"] += 1
                        self._counts["max_waiting"] = max(
                            self._counts["max_waiting"], self._waiting)
                    self._waiters[ticket].wait(max(0.0, until - time.monotonic()))
            finally:
                if waiting:
                    self._waiting -= 1
                    self._waiters.pop(ticket)
                    self._notify_head_locked()
        if connection is not None:
            if self._healthy(connection):
                with self._condition:
                    self._counts["reused"] += 1
                return connection
            # Drop just this stale idle connection. Do not scan the whole pool
            # or retry a statement; replacement is a new borrow by this caller.
            self.release(connection, reusable=False)
            with self._condition:
                if self._closed or self._total >= self._max_size or self._waiters:
                    raise PoolError("database_unavailable")
                if time.monotonic() >= until:
                    self._counts["timed_out"] += 1
                    raise PoolError("database_timeout")
                self._total += 1
                self._connecting += 1
        try:
            connection = self._opener()
            if connection is None:
                raise PoolError("database_unavailable")
        except BaseException as exc:
            with self._condition:
                self._connecting -= 1
                self._total -= 1
                self._counts["connect_failed"] += 1
                self._notify_head_locked()
            if not isinstance(exc, Exception):
                raise
            raise PoolError("database_unavailable") from None
        with self._condition:
            self._connecting -= 1
            self._counts["opened"] += 1
            # Connect itself retains the existing finite libpq connect_timeout.
            # Do not execute SQL after the encompassing request has expired.
            expired = remaining_budget() == 0.0
            if id(connection) in self._known:
                # A broken injected opener must not give one connection to two
                # callers. Reserve this slot permanently and stop new borrows.
                self._closed = True
                self._total -= 1
                self._notify_closed_waiters_locked()
                raise PoolError("database_unavailable")
            self._known[id(connection)] = connection
            self._leased[id(connection)] = connection
            closed = self._closed
            if expired:
                self._counts["timed_out"] += 1
        if closed or expired:
            self.release(connection, reusable=False)
            raise PoolError("database_timeout" if expired else "database_unavailable")
        return connection

    def release(self, connection: Any, *, reusable: bool) -> None:
        """Return exactly once; failed close quarantines capacity until shutdown."""
        with self._condition:
            if self._leased.pop(id(connection), None) is not connection:
                raise ValueError("connection_pool_lease_invalid")
            if reusable and not self._closed and self._healthy(connection):
                self._idle.append(connection)
                self._counts["returned"] += 1
                self._notify_head_locked()
                return
            self._closing += 1
            self._counts["discarded"] += 1
        self._close_reserved(connection)

    def _close_reserved(self, connection: Any) -> None:
        failed = False
        try:
            connection.close()
            failed = getattr(connection, "closed", True) is not True
        except Exception:
            failed = True
        with self._condition:
            self._closing -= 1
            if failed:
                self._quarantined[id(connection)] = connection
                self._counts["close_failed"] += 1
            else:
                self._total -= 1
                self._known.pop(id(connection), None)
            self._notify_head_locked()

    def note_reset_failed(self) -> None:
        with self._condition:
            self._counts["reset_failed"] += 1

    def stats(self) -> dict[str, int | float | bool]:
        """Fixed aggregate schema; no SQL, identities, addresses or credentials."""
        with self._condition:
            return dict(self._counts, max_size=self._max_size,
                        max_waiters=self._max_waiters, wait_timeout=self._wait_timeout,
                        total=self._total, idle=len(self._idle), in_use=len(self._leased),
                        connecting=self._connecting, closing=self._closing,
                        quarantined=len(self._quarantined), waiting=self._waiting,
                        closed=self._closed)

    def close(self) -> None:
        """Stop new borrows, wake waiters, close idle now and leases on return."""
        with self._condition:
            self._closed = True
            connections = list(self._idle)
            self._idle.clear()
            connections.extend(self._quarantined.values())
            self._quarantined.clear()
            self._closing += len(connections)
            self._notify_closed_waiters_locked()
        for connection in connections:
            self._close_reserved(connection)
