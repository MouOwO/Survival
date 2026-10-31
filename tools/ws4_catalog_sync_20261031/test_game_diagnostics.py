"""No network, database, real identities, credentials or reward operations."""
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import sys
from types import SimpleNamespace
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "server"))
from player_web_auth.game_diagnostics import DiagnosticSink, ObservedService, observe
from player_web_auth.service import AuthError


class Diagnostics(unittest.TestCase):
    def setUp(self):
        self.now, self.lines = 10., []
        self.clock = lambda: self.now
        self.sink = DiagnosticSink(clock=self.clock, write=self.lines.append)

    def invoke(self, call, path="/v1/archive/command"):
        return observe(call, path, "SECRET_BEARER", {"account_id": "SECRET_ACCOUNT"},
                       "SECRET_PEER", sink=self.sink, clock=self.clock)

    def test_success_preserves_exact_response_and_forwarded_inputs(self):
        body = b'{"ok":true,"private":"SECRET_PROFILE"}'
        calls = []
        def original(path, bearer, payload, peer):
            calls.append(path)
            self.assertEqual(bearer, "SECRET_BEARER")
            self.assertEqual(payload["account_id"], "SECRET_ACCOUNT")
            self.assertEqual(peer, "SECRET_PEER")
            return 200, body
        status, result = self.invoke(original)
        self.assertEqual(status, 200); self.assertIs(result, body)
        self.assertEqual(calls, ["/v1/archive/command"])
        self.assertNotIn("SECRET", "".join(self.lines))
        self.assertTrue(json.loads(self.lines[0].split(" ", 1)[1])["ok"])

    def test_authorization_failure_rethrows_same_error_without_secret_message(self):
        error = AuthError("player_session_expired", 403)
        def original(*args): raise error
        with self.assertRaises(AuthError) as caught: self.invoke(original)
        self.assertIs(caught.exception, error)
        self.assertIn('"http":403', self.lines[0])
        self.assertIn("player_session_expired", self.lines[0])

    def test_upstream_business_error_is_recorded_without_profile(self):
        body = b'{"ok":false,"error":"archive_config_mismatch","private":"SECRET"}'
        self.assertEqual(self.invoke(lambda *args: (200, body)), (200, body))
        self.assertIn("archive_config_mismatch", self.lines[0])
        self.assertNotIn("SECRET", self.lines[0])

    def test_only_fixed_prefix_is_inspected(self):
        body = b" " * 512 + b'{"ok":false,"error":"SECRET_LATE_CODE"}'
        self.invoke(lambda *args: (200, body))
        self.assertNotIn("SECRET", self.lines[0])

    def test_unwatched_routes_and_expired_diagnostics_do_not_record(self):
        call = lambda *args: (200, b"unchanged")
        self.invoke(call, "/v1/profile")
        self.now = self.sink.until
        self.assertEqual(self.invoke(call), (200, b"unchanged"))
        self.assertEqual(self.lines, [])

    def test_sink_limits_concurrent_writes_and_resets_next_real_minute(self):
        with ThreadPoolExecutor(max_workers=8) as pool:
            list(pool.map(lambda _: self.sink({"http": 200}), range(200)))
        self.assertEqual(len(self.lines), 60)
        self.now = 61.; self.sink({"http": 200})
        self.assertEqual(len(self.lines), 61)

    def test_logging_failure_cannot_break_response_or_change_exception(self):
        def broken(event): raise BrokenPipeError("SECRET_LOG_FAILURE")
        self.sink.write = broken
        self.assertEqual(self.invoke(lambda *args: (200, b"ok")), (200, b"ok"))
        def original(*args): raise ValueError("SECRET_INTERNAL_DETAIL")
        with self.assertRaisesRegex(ValueError, "SECRET_INTERNAL_DETAIL"):
            self.invoke(original)

    def test_other_instances_are_rejected_before_database_initialization(self):
        with self.assertRaisesRegex(ValueError, "ws4_diagnostic_scope_required"):
            ObservedService(SimpleNamespace(bind="127.0.0.1", port=8765,
                public_base="https://example.invalid", upstream="http://127.0.0.1:8765"))

    def test_total_budget_stops_even_when_minute_budget_resets(self):
        for minute in range(8):
            self.now = 10. + minute * 60
            for _ in range(80): self.sink({"http": 200})
        self.assertEqual(len(self.lines), 300)
        self.assertEqual(self.sink.total, 300)
        self.assertEqual(self.invoke(lambda *args: (200, b"unchanged")), (200, b"unchanged"))
        self.assertEqual(len(self.lines), 300)


if __name__ == "__main__": unittest.main()
