"""Offline guards for the two-check deployment acceptance entrypoint."""
from contextlib import redirect_stdout
from dataclasses import dataclass
import importlib.util
import io
import json
import os
from pathlib import Path
import sys
import tempfile
from types import ModuleType, SimpleNamespace
import unittest
from unittest.mock import Mock, patch


HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
spec = importlib.util.spec_from_file_location("postgres_acceptance_under_test", HERE / "test_postgres_acceptance.py")
acceptance = importlib.util.module_from_spec(spec)
spec.loader.exec_module(acceptance)


@dataclass
class Application:
    token: str
    account_id_pepper: str
    definitions: object
    rpc_client: object
    gameplay_stats: object = None
    online_time_lease_seconds: int = 90
    interval_min_seconds: int = 60
    interval_max_seconds: int = 600

    def sync_definitions(self):
        raise AssertionError("configuration sync must not run")


class Archive:
    def __init__(self, app, bundle, lua):
        self.app, self.bundle, self.lua = app, bundle, lua

    def sync(self):
        raise AssertionError("configuration sync must not run")


def module(name, **values):
    value = ModuleType(name)
    value.__dict__.update(values)
    return value


class FocusedAcceptanceTests(unittest.TestCase):
    def test_failed_client_keeps_real_archive_path_bound_to_clone(self):
        original = Application("token", "pepper", object(), object())
        original.archive = Archive(original, object(), "lua")
        bad_client = Mock()
        with patch.dict(sys.modules, {"archive_backend.service": module("archive_backend.service", ArchiveService=Archive)}):
            bad = acceptance.application_with_failed_database(original, bad_client)
        self.assertIs(bad.rpc_client, bad_client)
        self.assertIs(bad.archive.app, bad)
        self.assertIsNot(bad.archive, original.archive)
        self.assertIs(original.archive.app, original)
        self.assertIs(bad.archive.bundle, original.archive.bundle)
        self.assertEqual(bad.archive.lua, "lua")
        self.assertEqual(bad_client.mock_calls, [])

    def test_live_preflight_only_reads_ready_and_configuration(self):
        from http_acceptance import HttpClient
        settings = SimpleNamespace(host="127.0.0.1", port=8765, api_token="private")
        bundle = SimpleNamespace(hash="a" * 64)
        with patch.object(HttpClient, "request", side_effect=[
            (200, {"ok": True, "database": "ready"}),
            (200, {"ok": True, "protocol": 1, "config_hash": bundle.hash}),
        ]) as request:
            acceptance.verify_live_bundle(settings, bundle)
        self.assertEqual([call.args for call in request.call_args_list], [
            ("GET", "/ready"), ("POST", "/v1/archive/config", {})])

    def test_live_configuration_mismatch_is_rejected(self):
        from http_acceptance import AcceptanceFailure, HttpClient
        settings = SimpleNamespace(host="127.0.0.1", port=8765, api_token="private")
        with patch.object(HttpClient, "request", side_effect=[
            (200, {"ok": True, "database": "ready"}),
            (200, {"ok": True, "protocol": 1, "config_hash": "b" * 64}),
        ]):
            with self.assertRaisesRegex(AcceptanceFailure, "focused_live_bundle_mismatch"):
                acceptance.verify_live_bundle(settings, SimpleNamespace(hash="a" * 64))

    def test_focused_application_does_not_sync_global_configuration(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "server/bundles").mkdir(parents=True)
            (root / "server/bundles/current.json").write_text(json.dumps({"hash": "a" * 64}), encoding="utf-8")
            settings = SimpleNamespace(addon_root=root, reward_csv=root / "reward.csv", rule_csv=root / "rule.csv",
                gameplay_stats_csv=root / "stats.csv", api_token="private", account_id_pepper="private",
                postgres_dsn="service=fixture", postgres_connect_timeout_seconds=3,
                postgres_statement_timeout_ms=5000, postgres_lock_timeout_ms=1000, postgres_max_concurrency=4,
                archive_lua_path="lua")
            client = Mock()
            client.ready.return_value = True
            client.rpc.side_effect = AssertionError("no RPC allowed during focused initialization")
            constructor = Mock(return_value=client)
            bundle = SimpleNamespace(hash="a" * 64)
            modules = {
                "archive_backend.bundle": module("archive_backend.bundle", Bundle=Mock(return_value=bundle)),
                "archive_backend.service": module("archive_backend.service", ArchiveService=Archive),
                "fishing_api.application": module("fishing_api.application", FishingApplication=Application),
                "fishing_api.definitions": module("fishing_api.definitions",
                    load_definitions=Mock(return_value=SimpleNamespace(version=1)),
                    load_rule=Mock(return_value=SimpleNamespace(definition_version=1, online_time_lease_seconds=90,
                        interval_min_seconds=60, interval_max_seconds=600))),
                "fishing_api.gameplay_stats": module("fishing_api.gameplay_stats", load_gameplay_stats=Mock(return_value={})),
                "fishing_api.postgres": module("fishing_api.postgres", PostgresRpcClient=constructor),
            }
            with patch.dict(sys.modules, modules), patch.object(acceptance, "verify_live_bundle") as preflight:
                app = acceptance.build_current_test_application(settings)
            preflight.assert_called_once_with(settings, bundle)
            client.ready.assert_called_once_with()
            client.rpc.assert_not_called()
            self.assertIs(app.archive.app, app)
            self.assertIs(app.archive.bundle, bundle)
            with patch.dict(sys.modules, modules), patch.object(acceptance, "verify_live_bundle", side_effect=RuntimeError("mismatch")):
                constructor.reset_mock()
                with self.assertRaisesRegex(RuntimeError, "mismatch"):
                    acceptance.build_current_test_application(settings)
                constructor.assert_not_called()

    def test_mode_is_fixed_to_two_non_admin_tests(self):
        self.assertEqual(acceptance.FOCUSED_TESTS, (
            "test_old_revision_cannot_overwrite_new_permanent_reward",
            "test_http_database_outage_no_empty_profile_or_write"))
        calls = []
        fake = type("OnlyTwo", (unittest.TestCase,), {
            name: (lambda case, name=name: calls.append(name)) for name in acceptance.FOCUSED_TESTS})
        stream = io.StringIO()
        with patch.dict(os.environ, {"GOUFAYU_ACCEPTANCE": "local-test", "GOUFAYU_TEST_ADMIN_SERVICE": ""}), \
             patch.object(acceptance, "PostgresAcceptance", fake), redirect_stdout(stream):
            self.assertEqual(acceptance.focused_main(["--focused-current", "--confirm-test-writes"]), 0)
        self.assertEqual(tuple(calls), acceptance.FOCUSED_TESTS)
        self.assertEqual(json.loads(stream.getvalue())["tests_run"], 2)

    def test_admin_environment_is_rejected_before_suite_runs(self):
        stream = io.StringIO()
        with patch.dict(os.environ, {"GOUFAYU_ACCEPTANCE": "local-test", "GOUFAYU_TEST_ADMIN_SERVICE": "forbidden"}), \
             patch.object(acceptance.unittest, "TestSuite") as suite, redirect_stdout(stream):
            self.assertEqual(acceptance.focused_main(["--focused-current", "--confirm-test-writes"]), 1)
        suite.assert_not_called()
        self.assertEqual(json.loads(stream.getvalue())["code"], "focused_test_environment_required")

    def test_failure_output_does_not_expose_traceback_or_credentials(self):
        def fail(case):
            raise RuntimeError("password=never-print-this")
        fake = type("FailsSafely", (unittest.TestCase,), {name: fail for name in acceptance.FOCUSED_TESTS})
        stream = io.StringIO()
        with patch.dict(os.environ, {"GOUFAYU_ACCEPTANCE": "local-test", "GOUFAYU_TEST_ADMIN_SERVICE": ""}), \
             patch.object(acceptance, "PostgresAcceptance", fake), redirect_stdout(stream):
            self.assertEqual(acceptance.focused_main(["--focused-current", "--confirm-test-writes"]), 1)
        self.assertNotIn("never-print-this", stream.getvalue())
        self.assertNotIn("Traceback", stream.getvalue())
        self.assertFalse(any(json.loads(stream.getvalue())["checks"].values()))


if __name__ == "__main__":
    unittest.main()
