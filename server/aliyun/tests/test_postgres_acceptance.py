"""Opt-in real PostgreSQL + HTTP acceptance. Uses synthetic accounts, never clears tables.

Set GOUFAYU_ACCEPTANCE=local-test, FISHING_BACKEND_ROOT, SURVIVAL_ADDON_ROOT,
POSTGRES_DSN=service=goufayu_app, PGSERVICEFILE/PGPASSFILE and ARCHIVE_LUA_PATH.
GOUFAYU_TEST_ADMIN_SERVICE is optional (extra invariant/permission checks).
Run only against a disposable copy named goufayu_test or goufayu_restore_*.

For an already running test deployment, --focused-current --confirm-test-writes
selects only stale-permanent-reward and archive-outage checks. This mode verifies
the live loopback service's bundle hash and skips all configuration sync RPCs.
It never selects permission probes or administrator fixture tests.
"""
from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from dataclasses import replace
import argparse
import hashlib
import http.client
import json
import os
from pathlib import Path
import re
import secrets
import sys
import threading
import unittest
from unittest.mock import patch
import uuid


FOCUSED_TESTS = (
    "test_old_revision_cannot_overwrite_new_permanent_reward",
    "test_http_database_outage_no_empty_profile_or_write",
)


def verify_live_bundle(settings, bundle):
    """Read only the existing service; never send a profile or business command."""
    from http_acceptance import HttpClient, require
    client = HttpClient((settings.host, settings.port), settings.api_token)
    status, value = client.request("GET", "/ready")
    require(status == 200 and value.get("ok") is True and value.get("database") == "ready",
            "focused_live_service_not_ready")
    status, value = client.request("POST", "/v1/archive/config", {})
    require(status == 200 and value.get("ok") is True and value.get("protocol") == 1
            and value.get("config_hash") == bundle.hash, "focused_live_bundle_mismatch")


def build_current_test_application(settings):
    """Use already initialized configuration without any global sync writes."""
    from archive_backend.bundle import Bundle
    from archive_backend.service import ArchiveService
    from fishing_api.application import FishingApplication
    from fishing_api.definitions import load_definitions, load_rule
    from fishing_api.gameplay_stats import load_gameplay_stats
    from fishing_api.postgres import PostgresRpcClient
    current = json.loads((settings.addon_root / "server/bundles/current.json").read_text(encoding="utf-8"))
    digest = current.get("hash", "")
    if not isinstance(digest, str) or re.fullmatch(r"[0-9a-f]{64}", digest) is None:
        raise AssertionError("focused_bundle_pointer_invalid")
    bundle = Bundle(settings.addon_root / "server/bundles" / digest)
    verify_live_bundle(settings, bundle)
    definitions = load_definitions(settings.reward_csv, allow_decimal_values=True)
    rule = load_rule(settings.rule_csv)
    if definitions.version != rule.definition_version:
        raise AssertionError("focused_definition_version_mismatch")
    client = PostgresRpcClient(settings.postgres_dsn,
        connect_timeout=settings.postgres_connect_timeout_seconds,
        statement_timeout_ms=settings.postgres_statement_timeout_ms,
        lock_timeout_ms=settings.postgres_lock_timeout_ms,
        max_concurrency=settings.postgres_max_concurrency)
    if not client.ready():
        raise AssertionError("focused_database_not_ready")
    application = FishingApplication(settings.api_token, settings.account_id_pepper, definitions,
        client, load_gameplay_stats(settings.gameplay_stats_csv),
        online_time_lease_seconds=rule.online_time_lease_seconds,
        interval_min_seconds=rule.interval_min_seconds, interval_max_seconds=rule.interval_max_seconds)
    application.archive = ArchiveService(application, bundle, settings.archive_lua_path)
    return application


def application_with_failed_database(application, failed_client):
    from archive_backend.service import ArchiveService
    bad = replace(application, rpc_client=failed_client)
    # archive is installed dynamically, so dataclasses.replace does not copy it.
    # Binding directly avoids install()/sync() against the intentionally bad DB.
    bad.archive = ArchiveService(bad, application.archive.bundle, application.archive.lua)
    return bad


@unittest.skipUnless(os.environ.get("GOUFAYU_ACCEPTANCE") == "local-test", "real database acceptance explicitly opt-in")
class PostgresAcceptance(unittest.TestCase):
    focused_current = False

    @classmethod
    def setUpClass(cls):
        import psycopg
        sys.path.insert(0, os.environ["FISHING_BACKEND_ROOT"])
        from fishing_api.config import Settings
        from fishing_api.server import build_application
        cls.settings = Settings.from_env()
        if cls.settings.database_backend != "postgres" or not cls.settings.archive_http:
            raise AssertionError("acceptance requires PostgreSQL and archive HTTP")
        with psycopg.connect(cls.settings.postgres_dsn) as connection:
            cls.connection_identity = (connection.info.host, connection.info.port, connection.info.dbname)
            database = connection.execute("SELECT current_database()").fetchone()[0]
            if database != "goufayu_test" and not database.startswith("goufayu_restore_"):
                raise AssertionError("refuse non-test database")
            assert connection.info.server_version // 10000 == 17
        if cls.focused_current and os.environ.get("GOUFAYU_TEST_ADMIN_SERVICE"):
            raise AssertionError("focused_administrator_service_refused")
        cls.app = build_current_test_application(cls.settings) if cls.focused_current else build_application(cls.settings)

    def setUp(self):
        self.account = str(9_000_000_000_000_000 + secrets.randbelow(999_999_999_999))
        self.other = str(int(self.account) + 1)

    def profile(self, account=None):
        return self.app.archive.profile({"account_id": account or self.account})

    def command(self, kind="boss_kill"):
        return {"account_id": self.account, "config_hash": self.app.archive.bundle.hash,
                "command": {"id": "acceptance:" + uuid.uuid4().hex, "kind": kind}}

    def grant(self):
        row = next(row for row in self.app.definitions.rows if row["reward_id"] == "star_blessing_002")
        return {"account_id": self.account, "grant_id": str(uuid.uuid4()),
                "reward_id": row["reward_id"], "definition_version": self.app.definitions.version,
                "amount": row["value_min"]}

    def test_save_write_new_application_reentry_and_isolation(self):
        from fishing_api.server import build_application
        before = self.profile()
        self.profile(self.other)
        self.assertTrue(self.app.archive.command(self.command())["ok"])
        fresh_app = build_application(self.settings)
        saved = fresh_app.archive.profile({"account_id": self.account})
        self.assertGreater(saved["revision"], before["revision"])
        self.assertEqual(saved["save"]["archive"]["boss_kills"], 1)
        self.assertEqual(self.profile(self.other)["save"]["archive"].get("boss_kills", 0), 0)

    def test_concurrent_identical_grant_and_replayed_archive_are_once(self):
        self.profile()
        grant = self.grant()
        with ThreadPoolExecutor(max_workers=4) as pool:
            results = list(pool.map(lambda _: self.app.grant_out_of_match_reward(grant), range(4)))
        self.assertTrue(all(result["ok"] for result in results))
        self.assertEqual(self.profile()["save"]["fishing_inventory"][grant["reward_id"]], 1)
        command = self.command()
        with ThreadPoolExecutor(max_workers=4) as pool:
            results = list(pool.map(lambda _: self.app.archive.command(command), range(4)))
        self.assertTrue(all(result["ok"] for result in results))
        self.assertEqual(self.profile()["save"]["archive"]["boss_kills"], 1)

    def test_old_revision_cannot_overwrite_new_permanent_reward(self):
        old = self.profile()
        database_account = self.app._database_account_id(self.account)
        operation = self.command()["command"]
        rpc = self.app.rpc_client
        prepared = rpc.rpc("archive_prepare", {"p_account": database_account, "p_id": operation["id"],
            "p_hash": self.app.archive.bundle.hash, "p_fingerprint": hashlib.sha256(operation["id"].encode()).hexdigest(),
            "p_command": operation})
        self.assertTrue(prepared["ok"])
        grant = self.grant()
        self.app.grant_out_of_match_reward(grant)
        stale = rpc.rpc("archive_commit", {"p_account": database_account, "p_id": operation["id"],
            "p_revision": old["revision"], "p_archive": {}, "p_deltas": {}, "p_error": None})
        self.assertEqual(stale["error"], "archive_revision_conflict")
        current = self.profile()  # Replays pending command against the new revision.
        self.assertEqual(current["save"]["fishing_inventory"][grant["reward_id"]], 1)
        self.assertEqual(current["save"]["archive"]["boss_kills"], 1)
        self.assertGreater(current["revision"], old["revision"])

    def test_response_lost_after_commit_retries_without_duplicate(self):
        self.profile()
        grant = self.grant()
        original = self.app.rpc_client
        class LoseReply:
            def rpc(inner, name, payload):
                value = original.rpc(name, payload)
                if name == "grant_out_of_match_reward":
                    raise TimeoutError("synthetic lost reply after committed transaction")
                return value
        app = replace(self.app, rpc_client=LoseReply())
        with self.assertRaises(TimeoutError):
            app.grant_out_of_match_reward(grant)
        self.assertTrue(self.app.grant_out_of_match_reward(grant)["ok"])
        self.assertEqual(self.profile()["save"]["fishing_inventory"][grant["reward_id"]], 1)

    def test_http_database_outage_no_empty_profile_or_write(self):
        from fishing_api.postgres import PostgresRpcClient
        from fishing_api.server import make_handler
        from http.server import ThreadingHTTPServer
        self.app.archive.command(self.command())
        before = self.profile()
        # Uses a closed local port instead of interrupting any existing database.
        bad = application_with_failed_database(self.app, PostgresRpcClient(
            "host=127.0.0.1 port=1 user=goufayu_app dbname=goufayu_test", connect_timeout=2))
        self.assertIs(bad.archive.app, bad)
        server = ThreadingHTTPServer(("127.0.0.1", 0), make_handler(bad))
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            connection = http.client.HTTPConnection("127.0.0.1", server.server_port, timeout=10)
            body = json.dumps({"account_id": self.account})
            with patch.object(bad.archive, "profile", wraps=bad.archive.profile) as archive_profile:
                connection.request("POST", "/v1/profile", body, {"Authorization": "Bearer " + self.settings.api_token,
                                    "Content-Type": "application/json"})
                response = connection.getresponse()
                value = json.loads(response.read())
                archive_profile.assert_called_once_with({"account_id": self.account})
            self.assertEqual(response.status, 503)
            self.assertFalse(value["ok"])
            self.assertNotIn("profile", value)
            self.assertNotIn("save", value)
            connection.close()
        finally:
            server.shutdown(); server.server_close(); thread.join()
        self.assertEqual(self.profile()["save"], before["save"])

    def test_runtime_cannot_read_write_tables_or_create_objects(self):
        import psycopg
        for statement in ("SELECT * FROM public.survival_players", "DELETE FROM public.survival_players",
                          "CREATE TABLE public.forbidden_acceptance(id integer)",
                          "CREATE TEMP TABLE forbidden_acceptance(id integer)", "SET ROLE goufayu_owner"):
            with psycopg.connect(self.settings.postgres_dsn) as connection:
                with self.assertRaises(psycopg.errors.InsufficientPrivilege):
                    connection.execute(statement)
        self.assertTrue(self.app.rpc_client.ready())

    def test_online_checkpoint_duplicate_is_one_persistent_receipt(self):
        self.profile()
        request = {"account_id": self.account, "session_id": "acceptance:" + uuid.uuid4().hex,
                   "request_id": "acceptance:" + uuid.uuid4().hex, "final": False}
        one = self.app.online_checkpoint(request)
        two = self.app.online_checkpoint(request)
        self.assertEqual(one, two)
        self.assertTrue(one["ok"])

    @unittest.skipUnless(os.environ.get("GOUFAYU_TEST_ADMIN_SERVICE"), "isolated fixture administration not configured")
    def test_online_outbox_recovery_and_independent_permanent_inventory(self):
        import psycopg
        self.profile()
        database_id = self.app._database_account_id(self.account)
        payload = {"account_id": self.account, "session_id": "acceptance:" + uuid.uuid4().hex,
                   "request_id": "acceptance:" + uuid.uuid4().hex, "final": False}
        self.app.online_checkpoint(payload)
        with psycopg.connect(service=os.environ["GOUFAYU_TEST_ADMIN_SERVICE"]) as admin:
            self.assertEqual((admin.info.host, admin.info.port, admin.info.dbname), self.connection_identity)
            # Change only this test's synthetic account to simulate a recent heartbeat.
            admin.execute("UPDATE public.online_time_sessions SET last_checkpoint_at=clock_timestamp()-interval '30 seconds' WHERE account_id=%s", (database_id,))
            admin.execute("INSERT INTO public.player_archive_state(account_id,content_inventory) VALUES(%s,'{\"acceptance_permanent_item\":1}'::jsonb) ON CONFLICT(account_id) DO UPDATE SET content_inventory=EXCLUDED.content_inventory", (database_id,))
            admin.execute("UPDATE public.survival_players SET profile_revision=profile_revision+1 WHERE account_id=%s", (database_id,))
        payload["request_id"] = "acceptance:" + uuid.uuid4().hex
        first = self.app.online_checkpoint(payload)  # Deliberately leave the durable outbox undrained.
        self.assertGreaterEqual(first["elapsed_seconds"], 29)
        self.assertEqual(self.app.online_checkpoint(payload), first)
        with psycopg.connect(service=os.environ["GOUFAYU_TEST_ADMIN_SERVICE"]) as admin:
            self.assertEqual(admin.execute("SELECT count(*) FROM public.archive_online_outbox WHERE account_id=%s AND request_id=%s", (database_id, payload["request_id"])).fetchone()[0], 1)
        recovered = self.profile()
        self.assertEqual(recovered["save"]["archive"]["online"]["actual_seconds"], first["elapsed_seconds"])
        self.app.archive.command(self.command())
        self.assertEqual(self.profile()["save"]["content_inventory"]["acceptance_permanent_item"], 1)


def focused_main(argv):
    parser = argparse.ArgumentParser(description="Two non-admin acceptance checks against an existing test deployment")
    parser.add_argument("--focused-current", action="store_true", required=True)
    parser.add_argument("--confirm-test-writes", action="store_true", required=True)
    parser.parse_args(argv)
    if os.environ.get("GOUFAYU_ACCEPTANCE") != "local-test" or os.environ.get("GOUFAYU_TEST_ADMIN_SERVICE"):
        print(json.dumps({"status": "FAIL", "code": "focused_test_environment_required"}))
        return 1
    PostgresAcceptance.focused_current = True
    class FocusedResult(unittest.TestResult):
        succeeded = set()

        def addSuccess(self, test):
            super().addSuccess(test)
            self.succeeded.add(test._testMethodName)

    result = FocusedResult()
    unittest.TestSuite(PostgresAcceptance(name) for name in FOCUSED_TESTS).run(result)
    passed = result.wasSuccessful() and result.testsRun == 2 and not result.skipped
    # Do not print unittest tracebacks: a driver/config exception can contain credentials.
    print(json.dumps({"status": "PASS" if passed else "FAIL", "code": "focused_acceptance_passed" if passed else "focused_acceptance_failed",
        "tests_run": result.testsRun, "checks": {name: name in result.succeeded for name in FOCUSED_TESTS},
        "configuration_sync_disabled": True, "administrator_fixture_disabled": True,
        "existing_database_service_interrupted": False, "synthetic_test_records_retained": True,
        "not_tested": ["real_database_outage", "legacy_database_migration", "real_game_client"]}))
    return 0 if passed else 1


if __name__ == "__main__":
    if "--focused-current" in sys.argv[1:]:
        raise SystemExit(focused_main(sys.argv[1:]))
    unittest.main(verbosity=2)
