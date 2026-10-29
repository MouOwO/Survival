"""Real Python admission -> SQL-contract fixture -> packaged Lua -> commit.

The game archive queue runtime and authenticated startup session deliberately
differ. No network, real account, active bundle pointer or database is changed.
"""
from __future__ import annotations

import copy
import hashlib
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "server"))
from archive_backend.bundle import Bundle, build
from archive_backend.service import ArchiveError, ArchiveService


class DatabaseContract:
    account = "a" * 64
    account_id_pepper = "offline-regression-only"

    def __init__(self, mode="cold", session="survival_startupSessionB"):
        self.mode, self.session = mode, session
        self.rpc_client = self
        self.calls, self.operations = [], {}
        self.lose_challenge_reply, self.revision_conflict = False, False
        self.profile = {"account_id": self.account, "revision": 1,
                        "save": {"archive": {}, "gameplay_stats": {},
                                 "content_inventory": {"unrelated_material": 37}}}

    def _database_account_id(self, account):
        assert account == "100"
        return self.account

    def _ensure_gameplay_stats(self, account):
        assert account == self.account

    def _public_response(self, result, database_id, public_id):
        assert database_id == self.account and public_id == "100"
        return copy.deepcopy(result)

    def resume(self, identity):
        row = self.operations[identity]
        return {"ok": row.get("error") is None, "done": row.get("done", False),
                "terminal": row.get("done", False), "error": row.get("error"),
                "command": copy.deepcopy(row["command"]),
                "config_hash": row["hash"], "has_pass": False,
                "response": copy.deepcopy(row.get("response")),
                "event_at": 1793232000, "profile": copy.deepcopy(self.profile)}

    def rpc(self, method, payload):
        self.calls.append((method, copy.deepcopy(payload)))
        assert payload["p_account"] == self.account
        if method == "match_profile_context":
            if payload["p_session"] != self.session:
                return {"ok": False, "error": "match_session_missing"}
            return {"ok": True, "mode": self.mode, "account_id": self.account,
                    "match_session_id": self.session}
        if method == "archive_prepare":
            identity, command = payload["p_id"], payload["p_command"]
            assert command["id"] == identity
            digest = hashlib.sha256(json.dumps(command, sort_keys=True,
                separators=(",", ":"), ensure_ascii=False).encode()).hexdigest()
            assert digest == payload["p_fingerprint"]
            if identity in self.operations:
                row = self.operations[identity]
                if row["fingerprint"] != digest or row["hash"] != payload["p_hash"]:
                    return {"ok": False, "terminal": True, "error": "archive_id_conflict"}
            else:
                # archive_prepare adds the server date after fingerprinting.
                self.operations[identity] = {"command": {**copy.deepcopy(command),
                    "day_key": "20754", "today": 20754}, "hash": payload["p_hash"],
                    "fingerprint": digest}
            return self.resume(identity)
        if method == "archive_resume":
            if payload["p_id"] not in self.operations:
                return {"ok": False, "terminal": True, "error": "archive_operation_missing"}
            return self.resume(payload["p_id"])
        if method in {"archive_commit", "archive_commit_challenge"}:
            row = self.operations[payload["p_id"]]
            if method == "archive_commit_challenge":
                assert row["command"]["kind"] == "challenge"
                assert "p_inventory" not in payload
            if row.get("done"):
                return self.resume(payload["p_id"])
            if self.revision_conflict:
                self.revision_conflict = False
                self.profile["revision"] += 1
            if payload["p_revision"] != self.profile["revision"]:
                return {"ok": False, "error": "archive_revision_conflict"}
            if method == "archive_commit_challenge":
                assert isinstance(payload["p_response"], dict)
            row["done"], row["error"] = True, payload["p_error"]
            if row["error"] is None:
                self.profile["save"]["archive"] = copy.deepcopy(payload["p_archive"])
                stats = self.profile["save"]["gameplay_stats"]
                for key, delta in payload["p_deltas"].items():
                    stats[key] = stats.get(key, 0) + delta
                self.profile["revision"] += 1
                if method == "archive_commit_challenge":
                    row["response"] = copy.deepcopy(payload["p_response"])
            if method == "archive_commit_challenge" and self.lose_challenge_reply:
                self.lose_challenge_reply = False
                raise TimeoutError("challenge reply lost after atomic commit")
            return self.resume(payload["p_id"])
        raise AssertionError("unexpected RPC: " + method)


class ChallengeReceiptFlow(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory(prefix="archive-receipt-flow-")
        cls.destination = Path(cls.directory.name)
        digest = build(ROOT, cls.destination, update_game_config=False)
        cls.bundle = Bundle(cls.destination / digest)
        cls.lua = shutil.which("lua5.1") or shutil.which("lua") or "C:/Program Files/lua/bin/lua5.1.exe"
        # A genuinely old accepted operation lacks the new session-tier table.
        old = json.loads((cls.bundle.directory / "bundle.json").read_bytes())
        old["configs"].pop("archive_challenge_modes")
        raw = json.dumps(old, ensure_ascii=False, sort_keys=True,
                         separators=(",", ":"), allow_nan=False).encode()
        cls.old_hash = hashlib.sha256(raw).hexdigest()
        old_directory = cls.destination / cls.old_hash
        for name, source in old["sources"].items():
            output = old_directory / name
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_text(source, encoding="utf-8", newline="\n")
        (old_directory / "bundle.json").write_bytes(raw)

    @classmethod
    def tearDownClass(cls):
        cls.directory.cleanup()

    def service(self, **options):
        app = DatabaseContract(**options)
        return ArchiveService(app, self.bundle, self.lua), app

    def payload(self, app, command):
        return {"account_id": "100", "match_session_id": app.session,
                "config_hash": self.bundle.hash, "command": command}

    def endless(self, number=30, wave=20, variant=None, runtime="archiveRuntimeA"):
        command = {"id": runtime + ":endless:" + str(wave), "kind": "endless",
                   "difficulty": number, "wave": wave}
        if variant is not None:
            command["variant"] = variant
        return command

    def test_high_endless_distinct_runtime_prepare_worker_commit_retry(self):
        service, app = self.service()
        command = self.endless()
        before = copy.deepcopy(command)
        self.assertTrue(service.command(self.payload(app, command))["ok"])
        identity = app.session + ":endless:20"
        self.assertEqual(command, before)
        self.assertEqual(set(app.operations), {identity})
        self.assertTrue(app.operations[identity]["done"])
        archive = app.profile["save"]["archive"]
        self.assertEqual(archive["endless_score"], 2)
        self.assertEqual(sum(archive["challenge_gear_counts"].values()), 1)
        self.assertEqual(archive["challenge_gear_progress"][app.session]["endless"], 1)
        previous = copy.deepcopy(app.profile)
        self.assertTrue(service.command(self.payload(app, self.endless(runtime="archiveRetryC")))["ok"])
        self.assertEqual(app.profile, previous)
        self.assertTrue(all(payload["p_session"] == app.session for method, payload in app.calls
                            if method == "match_profile_context"))

    def test_tower_low_numeric_tier_uses_its_own_bound_receipt(self):
        service, app = self.service(session="survival:startupSessionB")
        result = service.command(self.payload(app, self.endless(10, 15, "tower")))
        self.assertTrue(result["ok"], result)
        self.assertEqual(set(app.operations), {app.session + ":tower:15"})
        archive = app.profile["save"]["archive"]
        self.assertEqual(archive["endless_score"], 4)
        self.assertEqual(archive["tower_best_wave"], 15)
        self.assertEqual(sum(archive["challenge_gear_counts"].values()), 1)

    def test_high_challenge_runs_packaged_reward_worker(self):
        service, app = self.service()
        command = {"id": "archiveRuntimeA:challenge_kind:football", "kind": "challenge",
                   "challenge_id": "football", "difficulty_id": "N30", "kill_sequence": 7}
        result = service.command(self.payload(app, command))
        self.assertTrue(result["ok"], result)
        self.assertEqual(set(app.operations), {app.session + ":challenge_kind:football"})
        self.assertEqual(app.profile["save"]["archive"]["challenge_points"]["football"], 10)
        self.assertEqual(result["response"], app.operations[app.session + ":challenge_kind:football"]["response"])

    def test_challenge_lost_ack_returns_exact_durable_roll_without_reducing_again(self):
        service, app = self.service()
        command = {"id": "archiveRuntimeA:challenge_kind:shadow_1", "kind": "challenge",
                   "challenge_id": "shadow_1", "difficulty_id": "N30", "kill_sequence": 9}
        request = self.payload(app, command)
        app.lose_challenge_reply = True
        with patch.object(service, "settle", wraps=service.settle) as worker:
            with self.assertRaisesRegex(TimeoutError, "lost after atomic commit"):
                service.command(request)
            identity = app.session + ":challenge_kind:shadow_1"
            receipt = copy.deepcopy(app.operations[identity])
            granted = copy.deepcopy(app.profile)
            self.assertGreater(receipt["response"]["awarded"], 0)
            self.assertEqual(sum(row["count"] for row in receipt["response"]["rewards"]),
                             receipt["response"]["awarded"])
            result = service.command(request)
            self.assertTrue(result["done"] and result["ok"])
            self.assertEqual(result["response"], receipt["response"])
            self.assertEqual(app.operations[identity], receipt)
            self.assertEqual(app.profile, granted)
            self.assertEqual(worker.call_count, 1)
            self.assertEqual(app.profile["save"]["content_inventory"], {"unrelated_material": 37})
            self.assertEqual(sum(method == "archive_commit_challenge" for method, _ in app.calls), 1)
            self.assertFalse(any(method == "archive_commit_lottery" for method, _ in app.calls))

    def test_challenge_conflict_reduces_latest_profile_and_stores_accepted_response(self):
        service, app = self.service()
        app.revision_conflict = True
        command = {"id": "archiveRuntimeA:challenge_kind:football", "kind": "challenge",
                   "challenge_id": "football", "difficulty_id": "N30", "kill_sequence": 3}
        result = service.command(self.payload(app, command))
        commits = [payload for method, payload in app.calls if method == "archive_commit_challenge"]
        self.assertEqual([row["p_revision"] for row in commits], [1, 2])
        self.assertEqual(app.profile["revision"], 3)
        self.assertEqual(result["response"], commits[1]["p_response"])
        self.assertEqual(app.profile["save"]["archive"]["challenge_points"]["football"], 10)

    def test_old_completed_challenge_without_detail_is_never_reduced_or_supplemented(self):
        service, app = self.service(mode="standard")
        command = {"id": "archiveRuntimeA:challenge_kind:hunt_01", "kind": "challenge",
                   "challenge_id": "hunt_01", "difficulty_id": "n10", "kill_sequence": 1}
        validated = service.validate(command)
        fingerprint = hashlib.sha256(json.dumps(validated, sort_keys=True,
            separators=(",", ":"), ensure_ascii=False).encode()).hexdigest()
        app.operations[command["id"]] = {"command": {**validated, "day_key": "20754"},
            "hash": self.bundle.hash, "fingerprint": fingerprint, "done": True}
        previous = copy.deepcopy((app.operations, app.profile))
        with patch.object(service, "settle", side_effect=AssertionError("completed receipt re-reduced")):
            result = service.command(self.payload(app, command))
        self.assertTrue(result["ok"] and result["done"])
        self.assertIsNone(result["response"])
        self.assertEqual((app.operations, app.profile), previous)
        self.assertFalse(any(method == "archive_commit_challenge" for method, _ in app.calls))

    def test_ineligible_recipient_skip_is_durable_and_never_becomes_a_reward_on_retry(self):
        service, app = self.service()
        command = {"id": "archiveRuntimeA:challenge_kind:social_wife", "kind": "challenge",
                   "challenge_id": "social_wife", "difficulty_id": "N30", "kill_sequence": 3}
        request = self.payload(app, command)
        result = service.command(request)
        self.assertTrue(result["ok"] and result["done"])
        self.assertEqual(result["response"]["awarded"], 0)
        self.assertTrue(result["response"]["skipped_reason"])
        before = copy.deepcopy((app.profile, app.operations))
        with patch.object(service, "settle", side_effect=AssertionError("skip re-reduced")):
            self.assertEqual(service.command(request)["response"], result["response"])
        self.assertEqual((app.profile, app.operations), before)

    def test_reducer_rejection_commits_terminal_receipt_without_success_response(self):
        service, app = self.service()
        command = {"id": "archiveRuntimeA:challenge_kind:hunt_01", "kind": "challenge",
                   "challenge_id": "hunt_01", "difficulty_id": "N30", "kill_sequence": 4}
        before = copy.deepcopy(app.profile)
        with patch.object(service, "settle", return_value={"ok": False, "error": "fixture_rejected"}):
            result = service.command(self.payload(app, command))
        self.assertTrue(result["done"] and result["terminal"])
        self.assertFalse(result["ok"])
        self.assertIsNone(result["response"])
        self.assertEqual(app.profile, before)

    def test_batch_scopes_only_after_raw_validation_and_keeps_ack_ids(self):
        service, app = self.service()
        commands = [self.endless(30, 20), self.endless(30, 40)]
        payload = self.payload(app, commands[0])
        payload.pop("command")
        payload["commands"] = commands
        result = service.endless_batch(payload)
        self.assertTrue(result["ok"], result)
        self.assertEqual([row["id"] for row in result["results"]], [row["id"] for row in commands])
        self.assertEqual(set(app.operations), {app.session + ":endless:20", app.session + ":endless:40"})
        self.assertEqual(app.profile["save"]["archive"]["endless_score"], 6)
        service, app = self.service()
        payload = self.payload(app, commands[0])
        payload["commands"] = [commands[0], {**commands[1], "session": app.session}]
        with self.assertRaisesRegex(ArchiveError, "archive_command_fields_invalid"):
            service.endless_batch(payload)
        self.assertEqual(app.operations, {})

    def test_invalid_later_batch_mode_never_prepares_earlier_wave(self):
        service, app = self.service(mode="standard")
        commands = [self.endless(10, 1), self.endless(30, 2)]
        payload = self.payload(app, commands[0])
        payload["commands"] = commands
        with self.assertRaisesRegex(ArchiveError, "archive_mode_difficulty_unavailable"):
            service.endless_batch(payload)
        self.assertEqual(app.operations, {})

    def test_existing_low_tier_id_and_fingerprint_stay_unchanged(self):
        service, app = self.service(mode="standard")
        command = self.endless(10, 1)
        expected = service.validate(command)
        fingerprint = hashlib.sha256(json.dumps(expected, sort_keys=True,
            separators=(",", ":"), ensure_ascii=False).encode()).hexdigest()
        self.assertTrue(service.command(self.payload(app, command))["ok"])
        self.assertEqual(set(app.operations), {"archiveRuntimeA:endless:1"})
        self.assertEqual(app.operations[expected["id"]]["fingerprint"], fingerprint)

    def test_old_accepted_high_tier_receipt_keeps_recorded_identity(self):
        service, app = self.service()
        command = service.validate(self.endless())
        identity = command["id"]
        app.operations[identity] = {"command": {**command, "day_key": "20754"},
                                    "hash": self.old_hash, "fingerprint": "unchanged-legacy"}
        result = service.finish_prepared(app.account, identity, app.resume(identity))
        self.assertTrue(result["ok"], result)
        self.assertEqual(set(app.operations), {identity})
        self.assertEqual(app.operations[identity]["fingerprint"], "unchanged-legacy")
        self.assertFalse(any(method == "match_profile_context" for method, _ in app.calls))
        self.assertEqual(app.profile["save"]["archive"]["endless_score"], 2)

    def test_http_retry_of_old_accepted_high_tier_never_creates_second_receipt(self):
        service, app = self.service()
        command = service.validate(self.endless())
        identity = command["id"]
        app.operations[identity] = {"command": {**command, "day_key": "20754"},
                                    "hash": self.old_hash, "fingerprint": "unchanged-legacy"}
        self.assertTrue(service.command(self.payload(app, command))["ok"])
        self.assertEqual(set(app.operations), {identity})
        self.assertEqual(app.operations[identity]["fingerprint"], "unchanged-legacy")
        previous = copy.deepcopy(app.profile)
        self.assertTrue(service.command(self.payload(app, command))["ok"])
        self.assertEqual(app.profile, previous)
        self.assertFalse(any(method == "archive_prepare" for method, _ in app.calls))

    def test_legacy_receipt_lookup_preserves_business_conflict_checks(self):
        service, app = self.service()
        command = service.validate(self.endless())
        identity = command["id"]
        app.operations[identity] = {"command": {**command, "difficulty": 21, "day_key": "20754"},
                                    "hash": self.old_hash, "fingerprint": "unchanged-legacy"}
        with self.assertRaisesRegex(ArchiveError, "archive_id_conflict"):
            service.command(self.payload(app, command))
        self.assertFalse(any(method in {"archive_prepare", "archive_commit"} for method, _ in app.calls))


if __name__ == "__main__":
    unittest.main()
