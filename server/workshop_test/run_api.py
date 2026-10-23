"""Run only against the independent ws4 PostgreSQL instance and four accounts."""
from pathlib import Path
import json
import os
import sys
from urllib.parse import urlparse

from fishing_api.config import Settings
from fishing_api.server import build_application, make_handler, BoundedThreadingHTTPServer
from archive_backend.test_access import TestAccountPolicy, install
from workshop_test.auth import Policy, handler


def main():
    try:
        settings = Settings.from_env()
        dsn = urlparse(settings.postgres_dsn)
        if (settings.database_backend != "postgres" or settings.host != "127.0.0.1"
                or settings.port != 18765 or dsn.hostname != "127.0.0.1" or dsn.port != 15432
                or dsn.path != "/goufayu_ws4" or settings.payment_mode != "test"):
            raise ValueError("isolated_database_required")
        policy = TestAccountPolicy.from_environment(os.environ)
        if policy is None or len(policy.account_ids) != 4:
            raise ValueError("four_test_accounts_required")
        # Check all isolation and account constraints before the builder's
        # initial definition/config synchronization can write to PostgreSQL.
        app = build_application(settings)
        install(app)
        auth = Policy(Path("/etc/goufayu-ws4/pins.json"), Path("/var/lib/goufayu-ws4/pairing/pending.json"))
        base = make_handler(app, client_timeout=settings.http_client_timeout_seconds,
                            request_deadline=settings.http_request_deadline_seconds)
        server = BoundedThreadingHTTPServer((settings.host, settings.port), handler(base, auth),
                                           max_concurrency=settings.http_max_concurrency)
    except Exception:
        print("WS4_STARTUP_ERROR", file=sys.stderr, flush=True)
        return 2
    print("WS4_READY", flush=True)
    try:
        server.serve_forever()
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
