"""Offline compatibility checks for immutable old clear-operation receipts."""
from copy import deepcopy
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
from types import SimpleNamespace
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "server"))
sys.path.insert(0, str(ROOT / "server/tests"))
from archive_backend.clear_receipts import bound_command, lookup, resolve_pending_mode
from archive_backend.bundle import Bundle, build
from archive_backend.service import ArchiveError, ArchiveService
from test_rich_match_modes import RichApp, RichDatabase


class ClearReceiptTests(unittest.TestCase):
    def setUp(self):
        self.session = "trusted-clear-session-one"
        self.payload = {"account_id": "123", "match_session_id": self.session}
        self.mode = "standard"
        self.command = {"id": self.session + ":standard_clear", "kind": "mode_clear",
                        "mode_id": self.mode, "difficulty_id": "n1", "count": 1}
        self.rows, self.calls = {}, []
        def rpc(name, body):
            self.assertEqual(name, "archive_resume", "lookup must never prepare, commit or bind a mode")
            self.calls.append(deepcopy(body))
            return deepcopy(self.rows.get((body["p_account"], body["p_id"]), {
                "ok": False, "terminal": True, "error": "archive_operation_missing"}))
        self.service = SimpleNamespace(app=SimpleNamespace(
            _database_account_id=lambda account: "database-" + account,
            rpc_client=SimpleNamespace(rpc=rpc)))

    def receipt(self, operation_id, *, kind="standard_clear", done=True, **values):
        command = {"id": operation_id, "kind": kind, "difficulty_id": "n1", "count": 1,
                   "day_key": "21999", "today": 21999, **values}
        result = {"ok": True, "done": done, "terminal": done, "command": command,
                  "profile": {"account_id": "database-123", "save": {}},
                  "has_pass": True, "config_hash": "a" * 64}
        self.rows[("database-123", operation_id)] = deepcopy(result)
        return result

    def test_same_id_done_old_kind_without_mode_preserves_recorded_response(self):
        original = self.receipt(self.command["id"])
        found = lookup(self.service, self.payload, self.command)
        self.assertEqual(found.operation_id, self.command["id"])
        self.assertEqual(found.prepared, original)
        self.assertEqual(self.rows[("database-123", self.command["id"])], original)
        self.assertNotIn("mode_id", found.prepared["command"])
        self.assertEqual(found.mode_id, "standard")
        self.assertEqual(len(self.calls), 1)

    def test_pending_receipt_retains_hash_date_and_command_but_worker_copy_has_trusted_mode(self):
        original = self.receipt(self.command["id"], done=False)
        found = lookup(self.service, self.payload, self.command)
        self.assertEqual(found.prepared, original)
        worker = bound_command(found.prepared["command"], found.mode_id)
        self.assertEqual(worker, dict(original["command"], mode_id="standard"))
        self.assertEqual(found.prepared, original)
        self.assertEqual(worker["day_key"], "21999")
        self.assertEqual(found.prepared["config_hash"], "a" * 64)

    def test_standard_legacy_clear_alias_is_found_only_for_the_same_account_and_session(self):
        old_id = self.session + ":clear"
        original = self.receipt(old_id, kind="clear")
        self.rows[("database-another", self.command["id"])] = original
        self.rows[("database-123", "other-session:clear")] = original
        found = lookup(self.service, self.payload, self.command)
        self.assertEqual((found.operation_id, found.prepared), (old_id, original))
        self.assertEqual(self.calls, [
            {"p_account": "database-123", "p_id": self.command["id"]},
            {"p_account": "database-123", "p_id": old_id}])
        self.assertNotIn(("database-123", self.command["id"]), self.rows)

    def test_pure_uses_its_old_clear_id_without_reading_or_inventing_standard_receipts(self):
        pure = dict(self.command, mode_id="pure", id=self.session + ":clear")
        original = self.receipt(pure["id"], kind="clear")
        found = lookup(self.service, self.payload, pure)
        self.assertEqual(found.prepared, original)
        self.assertEqual(bound_command(found.prepared["command"], found.mode_id)["mode_id"], "pure")
        self.assertEqual(len(self.calls), 1)

    def test_advanced_modes_only_reuse_their_explicit_same_mode_receipt(self):
        for mode in ("rich", "cold", "scourge"):
            with self.subTest(mode=mode):
                command = dict(self.command, mode_id=mode, id=self.session + ":" + mode + "_clear")
                original = self.receipt(command["id"], kind=mode + "_clear")
                found = lookup(self.service, self.payload, command)
                self.assertEqual(found.prepared, original)
                self.assertEqual(found.mode_id, mode)
        self.assertEqual(len(self.calls), 3)

    def test_business_changes_or_cross_mode_receipts_still_conflict(self):
        for values in ({"difficulty_id": "n2"}, {"count": 2}, {"count": True},
                       {"cooperative_win": 1}, {"mode_id": "pure"}, {"kind": "rich_clear"}):
            with self.subTest(values=values):
                kind = values.get("kind", "standard_clear")
                original = self.receipt(self.command["id"], kind=kind,
                                        **{key: value for key, value in values.items() if key != "kind"})
                with self.assertRaisesRegex(ArchiveError, "archive_id_conflict"):
                    lookup(self.service, self.payload, self.command)
                self.assertEqual(self.rows[("database-123", self.command["id"])], original)

    def test_missing_receipts_allow_prepare_but_unknown_rpc_failure_does_not(self):
        self.assertIsNone(lookup(self.service, self.payload, self.command))
        self.assertEqual(len(self.calls), 2)
        self.rows[("database-123", self.command["id"])] = {"ok": False, "error": "backend_unavailable"}
        with self.assertRaisesRegex(ArchiveError, "archive_receipt_unavailable"):
            lookup(self.service, self.payload, self.command)

    def test_legacy_unscoped_clear_and_unrelated_commands_do_not_probe_receipts(self):
        self.assertIsNone(lookup(self.service, self.payload, {"kind": "clear", "id": "legacy:clear"}))
        self.assertIsNone(lookup(self.service, self.payload, {"kind": "boss_kill", "id": "legacy:boss"}))
        self.assertEqual(self.calls, [])

    def test_inconsistent_scoped_id_cannot_select_another_historical_receipt(self):
        with self.assertRaisesRegex(ArchiveError, "match_session_invalid"):
            lookup(self.service, self.payload, dict(self.command, id="another-session:standard_clear"))
        self.assertEqual(self.calls, [])

    def test_pending_resolver_uses_the_whole_session_and_database_account(self):
        session = "trusted:session:with:colons"
        context = {"ok": True, "account_id": "database-123", "match_session_id": session, "mode": "pure"}
        calls = []
        def rpc(name, body):
            calls.append((name, deepcopy(body)))
            return deepcopy(context)
        self.service.app.rpc_client = SimpleNamespace(rpc=rpc)
        command = {"id": session + ":clear", "kind": "clear", "difficulty_id": "n1", "count": 1}
        original = deepcopy(command)
        self.assertEqual(resolve_pending_mode(self.service, "database-123", command), "pure")
        self.assertEqual(command, original)
        self.assertEqual(calls, [("match_profile_context", {"p_account": "database-123", "p_session": session})])

    def test_pending_resolver_requires_a_matching_durable_mode_for_typed_or_mode_commands(self):
        context = {"ok": True, "account_id": "database-123", "match_session_id": self.session, "mode": "cold"}
        self.service.app.rpc_client = SimpleNamespace(rpc=lambda *args: deepcopy(context))
        command = {"id": self.session + ":cold_clear", "kind": "cold_clear", "difficulty_id": "n1", "count": 1}
        self.assertEqual(resolve_pending_mode(self.service, "database-123", command), "cold")
        self.assertEqual(resolve_pending_mode(self.service, "database-123", dict(command, kind="mode_clear", mode_id="cold")), "cold")
        for update in ({"mode": "rich"}, {"account_id": "different-account"}, {"match_session_id": "different-session"}):
            previous = deepcopy(context)
            context.update(update)
            with self.subTest(update=update), self.assertRaises(ArchiveError):
                resolve_pending_mode(self.service, "database-123", command)
            context = previous

    def test_pending_resolver_only_treats_explicit_absent_legacy_sessions_as_compatible(self):
        context = {"ok": False, "error": "match_session_missing"}
        self.service.app.rpc_client = SimpleNamespace(rpc=lambda *args: deepcopy(context))
        command = {"id": self.session + ":clear", "kind": "clear", "difficulty_id": "n1", "count": 1}
        self.assertIsNone(resolve_pending_mode(self.service, "database-123", command))
        with self.assertRaisesRegex(ArchiveError, "match_session_missing"):
            resolve_pending_mode(self.service, "database-123", dict(command, id=self.session+":rich_clear", kind="rich_clear"))
        context = {"ok": False, "error": "backend_unavailable"}
        with self.assertRaisesRegex(ArchiveError, "match_session_unavailable"):
            resolve_pending_mode(self.service, "database-123", command)
        context = None
        with self.assertRaisesRegex(ArchiveError, "match_session_unavailable"):
            resolve_pending_mode(self.service, "database-123", command)
        self.assertIsNone(resolve_pending_mode(self.service, "database-123", dict(command, id="old:clear")))


class ClearReceiptIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.lua = os.environ.get("LUA_EXECUTABLE") or shutil.which("lua5.1") or shutil.which("lua")
        if not cls.lua:
            raise RuntimeError("Set LUA_EXECUTABLE for actual pending-receipt worker tests")
        cls.temporary = tempfile.TemporaryDirectory(prefix="archive-clear-receipts-")
        cls.addClassCleanup(cls.temporary.cleanup)
        destination = Path(cls.temporary.name)
        cls.bundle = Bundle(destination / build(ROOT, destination=destination, update_game_config=False))

    def setUp(self):
        class Database(RichDatabase):
            context_failure = None
            def rpc(self, name, payload):
                if name == "match_profile_context":
                    if self.context_failure:
                        return {"ok": False, "error": self.context_failure}
                    if (payload["p_account"], payload["p_session"]) not in self.sessions:
                        return {"ok": False, "error": "match_session_missing"}
                return super().rpc(name, payload)
        self.database = Database(self.bundle)
        self.app = RichApp(self.database)
        self.app._archive_modes_active = True
        self.service = ArchiveService(self.app, self.bundle, self.lua)
        self.app.archive = self.service
        self.account, self.session = "100", "pre-upgrade-clear-session"
        self.database_account = self.app._database_account_id(self.account)
        self.profile = self.database.profile(self.database_account)
        self.profile["save"]["archive"]["completed"] = {
            row["achievement_id"]: True for row in self.bundle.configs["archive_welfare_rewards"]["rows"]}

    def context(self, mode):
        self.database.sessions[(self.database_account, self.session)] = {
            "ok": True, "mode": mode, "account_id": self.database_account,
            "match_session_id": self.session, "baseline": deepcopy(self.profile), "defaults": {}, "created_at": 100}

    def old_receipt(self, kind, *, done):
        operation_id = self.session + ":" + kind
        command = {"id": operation_id, "kind": kind, "difficulty_id": "n1", "count": 1}
        fingerprint = hashlib.sha256(json.dumps(command, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
        recorded = dict(command, day_key="21999", today=21999)
        self.database.ops[(self.database_account, operation_id)] = {
            "command": recorded, "done": done, "fingerprint": fingerprint,
            "hash": self.bundle.hash, "pass": False}
        return operation_id, deepcopy(self.database.ops[(self.database_account, operation_id)])

    def send(self, *, kind="mode_clear", difficulty="n1"):
        return self.service.command({"account_id": self.account, "config_hash": self.bundle.hash,
            "match_session_id": self.session, "command": {
                "id": "new-client-retry-intent", "kind": kind, "difficulty_id": difficulty, "count": 1}})

    def assert_receipt_immutable(self, operation_id, original):
        current = self.database.ops[(self.database_account, operation_id)]
        for key in ("command", "fingerprint", "hash", "pass"):
            self.assertEqual(current[key], original[key], key)

    def test_completed_typed_receipt_without_mode_id_replays_with_no_prepare_or_new_reward(self):
        self.context("rich")
        operation_id, original = self.old_receipt("rich_clear", done=True)
        self.profile["save"]["archive"]["rich_clear_counts"] = {"n1": 1}
        before = deepcopy(self.profile)
        result = self.send()
        self.assertTrue(result["ok"], result)
        self.assertEqual(self.profile, before)
        self.assertEqual(len(self.database.ops), 1)
        self.assert_receipt_immutable(operation_id, original)

    def test_pending_typed_receipt_keeps_original_fingerprint_and_date_through_revision_retry(self):
        self.context("rich")
        operation_id, original = self.old_receipt("rich_clear", done=False)
        before = self.profile["save"]["gameplay_stats"]["initial_wood"]
        self.database.conflict = True  # Fixture adds one unrelated 100-wood update.
        result = self.send()
        self.assertTrue(result["ok"], result)
        self.assertEqual(self.profile["save"]["archive"]["mode_clear_counts"]["rich"], {"n1": 1})
        self.assertEqual(self.profile["save"]["gameplay_stats"]["initial_wood"], before + 200)
        self.assert_receipt_immutable(operation_id, original)
        self.assertTrue(self.database.ops[(self.database_account, operation_id)]["done"])
        saved = deepcopy(self.profile)
        self.assertTrue(self.send()["ok"])
        self.assertEqual(self.profile, saved)
        self.assertEqual(len(self.database.ops), 1)

    def test_standard_old_clear_alias_does_not_create_a_second_receipt_or_increment_count(self):
        self.context("standard")
        operation_id, original = self.old_receipt("clear", done=True)
        self.profile["save"]["archive"].update(clear_counts={"n1": 1}, standard_clear_counts={"n1": 1})
        before = deepcopy(self.profile)
        self.assertTrue(self.send()["ok"])
        self.assertEqual(self.profile, before)
        self.assertEqual(len(self.database.ops), 1)
        self.assertNotIn((self.database_account, self.session + ":standard_clear"), self.database.ops)
        self.assert_receipt_immutable(operation_id, original)

    def test_new_request_business_fields_cannot_replace_a_completed_old_clear(self):
        self.context("rich")
        operation_id, original = self.old_receipt("rich_clear", done=True)
        before = deepcopy(self.profile)
        with self.assertRaisesRegex(ArchiveError, "archive_id_conflict"):
            self.send(difficulty="n2")
        self.assertEqual(self.profile, before)
        self.assert_receipt_immutable(operation_id, original)

    def test_profile_background_drain_resolves_old_pure_clear_and_never_awards_ordinary_milestones(self):
        self.context("pure")
        operation_id, original = self.old_receipt("clear", done=False)
        before = deepcopy(self.profile["save"]["gameplay_stats"])
        result = self.service.profile({"account_id": self.account})
        self.assertEqual(result["account_id"], self.account)
        archive = self.profile["save"]["archive"]
        self.assertEqual(archive["mode_clear_counts"]["pure"], {"n1": 1})
        self.assertEqual(self.profile["save"]["gameplay_stats"], before)
        self.assertNotIn("clear_n1_1", archive["completed"])
        self.assertNotIn("standard:clear_n1_1", archive["completed"])
        self.assert_receipt_immutable(operation_id, original)

    def test_profile_background_drain_preserves_pre_mode_missing_session_compatibility(self):
        operation_id, original = self.old_receipt("clear", done=False)
        before = self.profile["save"]["gameplay_stats"]["initial_wood"]
        self.service.profile({"account_id": self.account})
        self.assertEqual(self.profile["save"]["gameplay_stats"]["initial_wood"], before + 50)
        self.assertNotIn("mode_clear_counts", self.profile["save"]["archive"])
        self.assert_receipt_immutable(operation_id, original)

    def test_background_context_failure_leaves_the_original_pending_receipt_uncommitted(self):
        self.context("pure")
        operation_id, original = self.old_receipt("clear", done=False)
        self.database.context_failure = "backend_unavailable"
        before = deepcopy(self.profile)
        with self.assertRaisesRegex(ArchiveError, "match_session_unavailable"):
            self.service.profile({"account_id": self.account})
        self.assertEqual(self.profile, before)
        self.assertEqual(self.database.ops[(self.database_account, operation_id)], original)


if __name__ == "__main__":
    unittest.main()
