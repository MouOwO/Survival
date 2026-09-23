"""Offline guards for live lottery acceptance; no database or network access."""
from contextlib import redirect_stdout
from copy import deepcopy
import io
import json
import os
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import lottery_upgrade_acceptance as acceptance


class FakeClient:
    def __init__(self, duplicate_mutation=False, cross_player_mutation=False):
        self.profiles = {}
        self.receipts = {}
        self.calls = []
        self.duplicate_mutation = duplicate_mutation
        self.cross_player_mutation = cross_player_mutation

    def profile(self, account):
        self.calls.append(("POST", "/v1/profile"))
        if account not in self.profiles:
            self.profiles[account] = {"account_id": account, "revision": 1,
                "save": {"gameplay_stats": {"online_seconds_total": 0},
                         "content_inventory": {}, "archive": {}}}
        return deepcopy(self.profiles[account])

    def request(self, method, path, payload=None, *, authenticated=True):
        self.calls.append((method, path))
        return (404 if authenticated else 401), {"ok": False}

    def success(self, method, path, payload, code):
        self.calls.append((method, path))
        if path == "/ready":
            return {"ok": True, "database": "ready"}
        if path == "/v1/archive/config":
            return {"ok": True, "config_hash": "a" * 64}
        player = self.profiles[payload["account_id"]]
        if path == "/v1/lottery/snapshot":
            return {"ok": True, "config_hash": "a" * 64, "snapshots": [{
                "selected_pool_id": "map", "ticket_content_id": "lottery_ticket", "ten_cost": 10,
                "tickets": player["save"]["content_inventory"]["lottery_ticket"],
                "draws": player["save"]["archive"].get("draws", 0)}]}
        if path == "/v1/archive/command":
            key = payload["account_id"], payload["command"]["id"]
            if key not in self.receipts or self.duplicate_mutation:
                player["revision"] += 1
                player["save"]["content_inventory"]["lottery_ticket"] -= 10
                player["save"]["content_inventory"]["fixture_prize"] = 1
                player["save"]["archive"]["draws"] = player["save"]["archive"].get("draws", 0) + 10
                self.receipts[key] = {"ok": True, "done": True, "response": {"ok": True,
                    "count": 10, "request_id": payload["command"]["request_id"],
                    "state_persisted": True, "results": [{}] * 10}}
                if self.cross_player_mutation:
                    for account, other in self.profiles.items():
                        if account != payload["account_id"]:
                            other["revision"] += 1
            return deepcopy(self.receipts[key])
        raise AssertionError("unexpected request")


class FakeFixture:
    def __init__(self, client):
        self.client, self.counter = client, 0

    def reserve_account(self):
        self.counter += 1
        return "900" + f"{self.counter:016d}"

    def seed(self, account, before):
        self.client.profiles[account]["save"]["content_inventory"] = {
            "lottery_ticket": 20, acceptance.SENTINEL: 1}
        self.client.profiles[account]["revision"] += 1


def report_fixture(client=None):
    client = client or FakeClient()
    report = {"format": acceptance.FORMAT, "generator": acceptance.GENERATOR, "mode": "write_test",
              "status": "FAIL", "code": "not_started", "started_at": "2026-09-20T00:00:00+00:00",
              "finished_at": "2026-09-20T00:00:02+00:00", "checks": {}, "synthetic_accounts": [],
              "not_tested": acceptance.NOT_TESTED, "test_records_retained": True,
              "profile_read_side_effects": acceptance.PROFILE_READ_EFFECTS}
    app = SimpleNamespace(archive=SimpleNamespace(bundle=SimpleNamespace(hash="a" * 64)))
    acceptance.run_write(client, app, FakeFixture(client), report)
    return report, client


class LotteryAcceptanceTests(unittest.TestCase):
    def test_complete_write_report_roundtrip_and_reentry_read_only_requests(self):
        report, client = report_fixture()
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "evidence.json"
            acceptance.write_report(path, report)
            source = acceptance.load_private_report(path, acceptance.validate_report)
        client.calls.clear()
        observed = {"checks": {}}
        acceptance.verify_previous(client, source, observed)
        self.assertEqual(observed["status"], "PASS")
        self.assertEqual(client.calls, [("GET", "/ready"), ("POST", "/v1/archive/config"),
            ("POST", "/v1/profile"), ("POST", "/v1/lottery/snapshot"),
            ("POST", "/v1/profile"), ("POST", "/v1/lottery/snapshot")])
        self.assertNotIn("verification", observed)

    def test_double_debit_or_cross_player_write_cannot_pass(self):
        for options in ({"duplicate_mutation": True}, {"cross_player_mutation": True}):
            with self.subTest(options=options), self.assertRaises(acceptance.AcceptanceFailure):
                report_fixture(FakeClient(**options))

    def test_lost_item_after_restart_fails_even_when_draw_count_unchanged(self):
        report, client = report_fixture()
        account = report["synthetic_accounts"][0]
        del client.profiles[account]["save"]["content_inventory"][acceptance.SENTINEL]
        with self.assertRaisesRegex(acceptance.AcceptanceFailure, "saved_state_changed"):
            acceptance.verify_previous(client, report, {"checks": {}})

    def test_tampered_reports_refuse_live_accounts_missing_checks_and_extra_data(self):
        original, _ = report_fixture()
        variants = []
        for key, value in (("status", "FAIL"), ("mode", "verify_prior_report"),
                           ("format", True), ("checks", {}), ("verification", {})):
            report = deepcopy(original)
            report[key] = value
            variants.append(report)
        report = deepcopy(original)
        report["synthetic_accounts"][0] = "76561198000000000"
        variants.append(report)
        report = deepcopy(original)
        report["profile"] = {"secret": "never expected"}
        variants.append(report)
        for report in variants:
            with self.assertRaises(acceptance.AcceptanceFailure):
                acceptance.validate_report(report)

    def test_fixture_refuses_non_loopback_non_test_and_wrong_major_version(self):
        valid = {"host": "127.0.0.1", "port": 5432, "dbname": "goufayu_test", "server_version": 170011}
        self.assertEqual(acceptance.database_identity(SimpleNamespace(info=SimpleNamespace(**valid))),
                         ("127.0.0.1", 5432, "goufayu_test"))
        for key, value in (("host", "47.110.238.248"), ("port", 5433), ("dbname", "postgres"),
                           ("server_version", 160001)):
            with self.subTest(key=key), self.assertRaises(acceptance.AcceptanceFailure):
                acceptance.database_identity(SimpleNamespace(info=SimpleNamespace(**{**valid, key: value})))

    def test_fixture_rejects_unreserved_account_before_database_access(self):
        fixture = acceptance.Fixture.__new__(acceptance.Fixture)
        fixture.created = set()
        with patch.object(fixture, "connect") as connect, self.assertRaises(acceptance.AcceptanceFailure):
            fixture.seed("9000000000000000001", {})
        connect.assert_not_called()

    def test_fixture_passfile_is_private_and_runtime_environment_is_unchanged(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory).resolve() / "private.pgpass"
            acceptance.write_report(path, {})  # Uses the same restrictive mode/ACL.
            self.assertEqual(acceptance.private_fixture_passfile(path), str(path))
            with self.assertRaises(acceptance.AcceptanceFailure):
                acceptance.private_fixture_passfile(Path("relative.pgpass"))
            fixture = acceptance.Fixture.__new__(acceptance.Fixture)
            fixture.service, fixture.passfile = "fixture_admin", str(path)
            fixture.identity = ("127.0.0.1", 5432, "goufayu_test")
            connection = Mock()
            connection.info = SimpleNamespace(host="127.0.0.1", port=5432, dbname="goufayu_test", server_version=170011)
            fixture.psycopg = SimpleNamespace(connect=Mock(return_value=connection))
            with patch.dict(os.environ, {"PGPASSFILE": "runtime-app.pgpass"}):
                self.assertIs(fixture.connect(), connection)
                self.assertEqual(os.environ["PGPASSFILE"], "runtime-app.pgpass")
            fixture.psycopg.connect.assert_called_once_with(service="fixture_admin", connect_timeout=5,
                                                            passfile=str(path))

    def test_invalid_report_rejected_before_token_network_or_fixture_access(self):
        with tempfile.TemporaryDirectory() as directory:
            source, target = Path(directory) / "invalid.json", Path(directory) / "result.json"
            acceptance.write_report(source, {"format": 1})
            output = io.StringIO()
            with patch.object(acceptance, "read_token") as token, patch.object(acceptance, "HttpClient") as client, \
                 patch.object(acceptance, "Fixture") as fixture, redirect_stdout(output):
                result = acceptance.main(["--verify-report", str(source), "--report", str(target)])
            self.assertEqual(result, 1)
            token.assert_not_called()
            client.assert_not_called()
            fixture.assert_not_called()

    def test_existing_report_is_never_overwritten(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "existing.json"
            target.write_text("preserved", encoding="utf-8")
            with redirect_stdout(io.StringIO()), patch.object(acceptance, "read_token") as token:
                self.assertEqual(acceptance.main(["--confirm-test-writes", "--report", str(target)]), 1)
            self.assertEqual(target.read_text(encoding="utf-8"), "preserved")
            token.assert_not_called()


if __name__ == "__main__":
    unittest.main()
