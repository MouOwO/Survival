"""Offline report/CLI guards. No HTTP, database, live token, or game accounts."""
from __future__ import annotations

from contextlib import redirect_stderr, redirect_stdout
from copy import deepcopy
import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location("http_acceptance", Path(__file__).with_name("http_acceptance.py"))
acceptance = importlib.util.module_from_spec(spec)
spec.loader.exec_module(acceptance)


def fixture():
    accounts = ["9000000000000000001", "9000000000000000002"]
    profiles = [{"account_id": account, "revision": 3 if index == 0 else 1,
                 "save": {"gameplay_stats": {"online_seconds_total": 2 if index == 0 else 0},
                          "archive": {"boss_kills": 1, "online": {"actual_seconds": 2 if index == 0 else 0}},
                          "fishing_inventory": {"fixture_reward": 1}}}
                for index, account in enumerate(accounts)]
    report = {
        "format": acceptance.REPORT_FORMAT, "generator": acceptance.REPORT_GENERATOR, "mode": "write_test",
        "status": "PASS", "code": "http_acceptance_passed",
        "started_at": "2026-09-19T00:00:00+00:00", "finished_at": "2026-09-19T00:00:02+00:00",
        "synthetic_accounts": accounts, "checks": {key: True for key in acceptance.WRITE_CHECKS},
        "not_tested": list(acceptance.NOT_TESTED), "test_records_retained": True,
        "profile_read_side_effects": acceptance.PROFILE_READ_EFFECTS,
        "verification": {"schema": 1, "test_kind": "boss_replay_online_final_v1", "config_hash": "a" * 64,
                         "boss_operation_id": "http-acceptance:" + "b" * 32,
                         "online_session_id": "http-acceptance:" + "c" * 32,
                         "online_final_request_id": "http-online-final:" + "d" * 32,
                         "players": [acceptance.profile_summary(profile) for profile in profiles]},
    }
    return report, profiles


class VerificationReportTests(unittest.TestCase):
    def test_generated_schema_and_private_file_round_trip(self):
        report, _ = fixture()
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "write-report.json"
            acceptance.write_report(target, report)
            self.assertEqual(acceptance.load_verification_report(target), report)
            if os.name == "posix":
                self.assertEqual(target.stat().st_mode & 0o077, 0)
            else:
                acceptance._windows_private_file(target)

    def test_real_accounts_and_duplicate_synthetic_identity_rejected(self):
        for account in ("76561198000000000", "123456", "900123", "90000000000000000000", 9000000000000000001):
            report, _ = fixture()
            report["synthetic_accounts"][0] = account
            report["verification"]["players"][0]["account_id"] = account
            with self.subTest(account=account), self.assertRaises(acceptance.AcceptanceFailure):
                acceptance.validate_verification_report(report)
        report, _ = fixture()
        report["synthetic_accounts"][1] = report["synthetic_accounts"][0]
        with self.assertRaises(acceptance.AcceptanceFailure):
            acceptance.validate_verification_report(report)

    def test_wrong_generation_status_and_mode_rejected(self):
        for key, value in (("format", 1), ("format", True), ("generator", "custom"),
                           ("mode", "verify_prior_report"), ("status", "FAIL"),
                           ("test_records_retained", False), ("checks", {}),
                           ("profile_read_side_effects", "database_readonly")):
            report, _ = fixture()
            report[key] = value
            with self.subTest(key=key), self.assertRaises(acceptance.AcceptanceFailure):
                acceptance.validate_verification_report(report)

    def test_extra_fields_missing_evidence_and_invalid_operations_rejected(self):
        report, _ = fixture()
        variants = []
        extra = deepcopy(report)
        extra["profile"] = {"untrusted": "data"}
        variants.append(extra)
        missing = deepcopy(report)
        del missing["verification"]
        variants.append(missing)
        bad_operation = deepcopy(report)
        bad_operation["verification"]["boss_operation_id"] = "real-operation-id"
        variants.append(bad_operation)
        mismatched = deepcopy(report)
        mismatched["verification"]["players"][0]["account_id"] = "9000000000000000123"
        variants.append(mismatched)
        for variant in variants:
            with self.assertRaises(acceptance.AcceptanceFailure):
                acceptance.validate_verification_report(variant)

    def test_counter_types_and_isolation_evidence_are_strict(self):
        for key, value in (("revision", True), ("revision", -1), ("revision", 2**63),
                           ("boss_kills", 2), ("online_seconds_total", 0),
                           ("online_seconds_total", 2.0), ("save_sha256", "bad")):
            report, _ = fixture()
            report["verification"]["players"][0][key] = value
            with self.subTest(key=key, value=value), self.assertRaises(acceptance.AcceptanceFailure):
                acceptance.validate_verification_report(report)
        report, _ = fixture()
        report["verification"]["players"][1]["online_seconds_total"] = 2
        with self.assertRaises(acceptance.AcceptanceFailure):
            acceptance.validate_verification_report(report)

    def test_report_size_duplicate_keys_and_nonfinite_json_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            for index, raw in enumerate((b" " * (acceptance.MAX_REPORT_BYTES + 1),
                                         b'{"format":2,"format":2}', b'{"format":NaN}')):
                path = Path(directory) / f"invalid-{index}.json"
                acceptance.write_report(path, {})
                path.write_bytes(raw)
                with self.assertRaises(acceptance.AcceptanceFailure):
                    acceptance.load_verification_report(path)

    def test_invalid_report_fails_before_token_read_or_http_creation(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "invalid.json"
            acceptance.write_report(path, {"format": 1, "account_id": "123456"})
            output = io.StringIO()
            with patch.object(acceptance, "read_token") as token, \
                 patch.object(acceptance, "HttpClient") as client, redirect_stdout(output):
                result = acceptance.main(["--verify-report", str(path)])
            self.assertEqual(result, 1)
            token.assert_not_called()
            client.assert_not_called()
            self.assertNotIn("123456", output.getvalue())

    def test_write_and_verify_modes_mutually_exclusive_without_echoing_arguments(self):
        output = io.StringIO()
        with redirect_stderr(output), self.assertRaises(SystemExit) as raised:
            acceptance.main(["--confirm-test-writes", "--verify-report", "private-secret-label.json"])
        self.assertEqual(raised.exception.code, 2)
        self.assertNotIn("private-secret-label", output.getvalue())

    def test_verify_mode_sends_only_readiness_config_and_existing_profile_reads(self):
        source, profiles = fixture()
        observed = []

        class ExistingProfiles:
            def success(self, method, path, payload, code):
                observed.append((method, path))
                if (method, path) == ("GET", "/ready"):
                    return {"ok": True, "database": "ready"}
                if (method, path) == ("POST", "/v1/archive/config"):
                    return {"ok": True, "config_hash": source["verification"]["config_hash"]}
                raise AssertionError("unexpected business request")

            def profile(self, account):
                observed.append(("POST", "/v1/profile"))
                return next(profile for profile in profiles if profile["account_id"] == account)

        report = {"checks": {}}
        acceptance.verify_previous_run(ExistingProfiles(), source, report)
        self.assertEqual(report["status"], "PASS")
        self.assertEqual(observed, [("GET", "/ready"), ("POST", "/v1/archive/config"),
                                    ("POST", "/v1/profile"), ("POST", "/v1/profile")])
        self.assertNotIn("verification", report)  # Cannot recursively treat a reread as the original write test.

    def test_changed_reward_content_fails_even_when_counters_match(self):
        source, profiles = fixture()
        profiles[0]["save"]["fishing_inventory"]["fixture_reward"] = 999

        class ChangedProfile:
            def success(self, method, path, payload, code):
                return {"ok": True, "database": "ready", "config_hash": source["verification"]["config_hash"]}

            def profile(self, account):
                return profiles[0]

        with self.assertRaisesRegex(acceptance.AcceptanceFailure, "saved_state_mismatch"):
            acceptance.verify_previous_run(ChangedProfile(), source, {"checks": {}})


if __name__ == "__main__":
    unittest.main()
