"""Temporary WS4 request diagnostics; never log identities, bodies or credentials.

This separate entry point keeps the existing Service and all authorization
decisions unchanged. Recording has time, per-minute and total record limits.
"""
import json
import re
import threading
import time

from .service import AuthError, Service

PATHS = frozenset(("/v1/archive/command", "/v1/payments/catalog",
                   "/v1/online-time/checkpoint"))
PREFIX_BYTES = 512
LIFETIME_SECONDS = 24 * 60 * 60
MAX_RECORDS = 300
CODE = re.compile(r"[A-Za-z][A-Za-z0-9_]{0,95}\Z")
OK = re.compile(rb'"ok"\s*:\s*(true|false)\b')
ERROR = re.compile(rb'"error"\s*:\s*"([A-Za-z][A-Za-z0-9_]{0,95})"')


class DiagnosticSink:
    def __init__(self, *, clock=time.monotonic, write=None):
        self.clock = clock
        self.until = clock() + LIFETIME_SECONDS
        self.write = write or (lambda line: print(line, flush=True))
        self.lock = threading.Lock()
        self.window, self.count = None, 0
        self.total = 0

    def __call__(self, event):
        now = self.clock()
        if now >= self.until:
            return
        with self.lock:
            window = int(now // 60)
            if window != self.window:
                self.window, self.count = window, 0
            if self.count >= 60 or self.total >= MAX_RECORDS:
                return
            self.count += 1
            self.total += 1
        try:
            self.write("WS4_GAME_DIAG " + json.dumps(event, sort_keys=True, separators=(",", ":")))
        except Exception:
            # Observability must never change an authentication/payment result.
            pass


def observe(call, path, bearer, payload, peer, *, sink, clock=time.monotonic):
    if path not in PATHS:
        return call(path, bearer, payload, peer)
    started = clock()
    if started >= sink.until or sink.total >= MAX_RECORDS:
        return call(path, bearer, payload, peer)

    def record(status, ok, error, size=0):
        event = dict(path=path, http=status, ok=ok,
                     error=error if isinstance(error, str) and CODE.fullmatch(error) else None,
                     bytes=size, elapsed_ms=max(0, round((clock() - started) * 1000)))
        try:
            sink(event)
        except Exception:
            pass

    try:
        status, body = call(path, bearer, payload, peer)
    except AuthError as error:
        record(error.status, False, error.code)
        raise
    except Exception as error:
        record(500, False, type(error).__name__)
        raise
    # Only inspect a fixed prefix of an already-returned byte response. Never
    # decode or retain a player's profile, balances, reward list or request.
    prefix = body[:PREFIX_BYTES] if isinstance(body, bytes) else b""
    ok, error = OK.search(prefix), ERROR.search(prefix)
    record(status, ok[1] == b"true" if ok else None,
           error[1].decode("ascii") if error else None,
           len(body) if isinstance(body, bytes) else 0)
    return status, body


class ObservedService(Service):
    def __init__(self, settings, **kwargs):
        if (settings.bind != "127.0.0.1" or settings.port != 18767
                or settings.public_base != "https://pay.xiaofengnet.com/ws4-web"
                or settings.upstream != "http://127.0.0.1:18765"):
            raise ValueError("ws4_diagnostic_scope_required")
        super().__init__(settings, **kwargs)
        self.diagnostic_sink = DiagnosticSink()

    def proxy(self, path, bearer, payload, peer):
        return observe(super().proxy, path, bearer, payload, peer,
                       sink=self.diagnostic_sink)


def main():
    from . import run
    run.Service = ObservedService
    return run.main()


if __name__ == "__main__":
    raise SystemExit(main())
