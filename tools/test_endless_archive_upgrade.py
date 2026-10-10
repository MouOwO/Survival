"""Offline receipt and reward tests for a narrowly compatible endless upgrade.

Set SURVIVAL_ENDLESS_UPGRADE_BUNDLE to the candidate bundle directory. The
captured baseline contains packaged code/configuration only; these tests never
connect to HTTP or PostgreSQL, and never use a real player's profile.
"""
from __future__ import annotations

import copy
import hashlib
import importlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
from types import ModuleType
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "server"))
from archive_backend.bundle import Bundle
from archive_backend.service import ArchiveError, ArchiveService


def materialize(root, raw):
    digest = hashlib.sha256(raw).hexdigest()
    directory = root / digest
    directory.mkdir()
    data = json.loads(raw)
    (directory / "bundle.json").write_bytes(raw)
    for name, source in data["sources"].items():
        path = directory / name
        assert path.resolve().is_relative_to(directory.resolve())
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(source, encoding="utf-8", newline="\n")
    return Bundle(directory)


class ReceiptDatabase:
    """Preserve the SQL receipt's fingerprint AND immutable configuration hash."""
    def __init__(self, bundle):
        self.profile = {
            "schema_version": 1, "account_id": "offline-account", "revision": 1,
            "entitlements": {}, "achievements": {}, "public": {},
            "save": {"archive": {}, "gameplay_stats": {
                row["field_id"]: float(row.get("default_value", 0))
                for row in bundle.configs["player_gameplay_stats"]["rows"]
            }},
        }
        self.ops = {}
        self.prepared_hashes = []
        self.commit_count = 0
        self.lose_reply = False
        self.conflict = False

    def resume(self, identifier):
        op = self.ops[identifier]
        return copy.deepcopy({
            "ok": not op.get("error"), "terminal": op["done"],
            "done": op["done"], "error": op.get("error"),
            "profile": self.profile, "command": op["command"],
            "config_hash": op["hash"], "has_pass": False,
        })

    def rpc(self, method, payload):
        identifier = payload.get("p_id")
        if method == "archive_prepare":
            self.prepared_hashes.append(payload["p_hash"])
            if identifier in self.ops:
                op = self.ops[identifier]
                if (op["fingerprint"] != payload["p_fingerprint"]
                        or op["hash"] != payload["p_hash"]):
                    return {"ok": False, "terminal": True,
                            "error": "archive_id_conflict"}
            else:
                command = copy.deepcopy(payload["p_command"])
                command.update(today=20000, day_key="20000")
                self.ops[identifier] = {
                    "command": command, "hash": payload["p_hash"],
                    "fingerprint": payload["p_fingerprint"], "done": False,
                }
            return self.resume(identifier)
        if method == "archive_resume":
            return self.resume(identifier)
        if method == "archive_commit":
            op = self.ops[identifier]
            if op["done"]:
                return self.resume(identifier)
            if self.conflict:
                self.conflict = False
                self.profile["revision"] += 1
                self.profile["save"]["gameplay_stats"]["initial_wood"] += 100
            if self.profile["revision"] != payload["p_revision"]:
                return {"ok": False, "error": "archive_revision_conflict"}
            if not payload["p_error"]:
                self.profile["save"]["archive"] = copy.deepcopy(payload["p_archive"])
                for key, delta in payload["p_deltas"].items():
                    self.profile["save"]["gameplay_stats"][key] += delta
                self.profile["revision"] += 1
            op.update(done=True, error=payload["p_error"])
            self.commit_count += 1
            if self.lose_reply:
                self.lose_reply = False
                raise TimeoutError("offline reply lost after commit")
            return self.resume(identifier)
        if method in ("archive_pending", "archive_online_pending"):
            return [{"id": key} for key, op in self.ops.items() if not op["done"]]
        if method == "get_fishing_profile":
            return copy.deepcopy(self.profile)
        raise AssertionError("unexpected offline RPC: " + method)


class App:
    account_id_pepper = "offline-only-not-a-real-secret"
    def __init__(self, db):
        self.rpc_client = db
    def _database_account_id(self, account):
        return "offline-account"
    def _ensure_gameplay_stats(self, account):
        pass
    def profile(self, payload):
        return copy.deepcopy(self.rpc_client.profile)
    def _public_response(self, result, account, public):
        return copy.deepcopy(result)


class EndlessUpgradeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        global ArchiveService, ArchiveError, Bundle
        candidate = os.environ.get("SURVIVAL_ENDLESS_UPGRADE_BUNDLE")
        baseline_path = Path(os.environ.get("SURVIVAL_ARCHIVE_BASELINE_PATH", str(
            ROOT / "output/archive_command_sync_20261009/remote_baseline.json")))
        if not baseline_path.is_file():
            raise unittest.SkipTest("set SURVIVAL_ARCHIVE_BASELINE_PATH to a captured deployment baseline")
        baseline = json.loads(baseline_path.read_text(encoding="utf-8"))
        cls.temp = tempfile.TemporaryDirectory(prefix="endless-upgrade-receipts-")
        cls.addClassCleanup(cls.temp.cleanup)
        directory = Path(cls.temp.name)
        if candidate:
            candidate = Path(candidate)
            fragment = candidate.parents[3]
        else:
            spec = importlib.util.spec_from_file_location(
                "offline_endless_upgrade_builder", ROOT / "tools/build_endless_archive_upgrade.py")
            builder = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(builder)
            fragment = directory / "fragment"
            game_hash_before = (ROOT / "scripts/vscripts/config/generated/archive_http_bundle.lua").read_bytes()
            result = builder.build(baseline, fragment)
            assert (ROOT / "scripts/vscripts/config/generated/archive_http_bundle.lua").read_bytes() == game_hash_before
            candidate = fragment / "addon/server/bundles" / result["hash"]
        package = ModuleType("offline_endless_candidate_backend")
        package.__path__ = [str(fragment / "backend/archive_backend")]
        sys.modules[package.__name__] = package
        stage = importlib.import_module(package.__name__ + ".service")
        # Exercise the exact narrowly patched live service and loader, rather
        # than the workspace's larger, undeployed feature set.
        ArchiveService, ArchiveError = stage.ArchiveService, stage.ArchiveError
        Bundle = importlib.import_module(package.__name__ + ".bundle").Bundle
        cls.old = materialize(directory, baseline["bundle_raw"].encode("utf-8"))
        cls.new = materialize(directory, (candidate / "bundle.json").read_bytes())
        cls.old_data = json.loads((cls.old.directory / "bundle.json").read_bytes())
        cls.new_data = json.loads((cls.new.directory / "bundle.json").read_bytes())
        cls.lua = os.environ.get("LUA_EXECUTABLE") or shutil.which("lua5.1") or shutil.which("lua")
        if not cls.lua:
            cls.lua = "C:/Program Files/lua/bin/lua5.1.exe"
        if not Path(cls.lua).is_file():
            raise RuntimeError("set LUA_EXECUTABLE to a Lua 5.1 executable")

    def setUp(self):
        self.db = ReceiptDatabase(self.old)
        self.app = App(self.db)
        self.service = ArchiveService(self.app, self.new, self.lua)
        self.legacy = ArchiveService(self.app, self.old, self.lua)

    def payload(self, kind, *, match="offline-match", version=None, **fields):
        return {"account_id": "100", "config_hash": version or self.old.hash,
                "command": {"id": match + ":operation", "kind": kind, **fields}}

    def award_count(self):
        return sum(bool(self.db.profile["save"]["archive"].get("completed", {}).get(
            "endless_" + str(number))) for number in range(51, 83))

    def test_upgrade_preserves_old_rewards_and_every_unrelated_config_and_source(self):
        for name, config in self.old_data["configs"].items():
            if name == "archive_endless_achievements":
                self.assertEqual(self.new_data["configs"][name]["rows"][:50], config["rows"])
                self.assertEqual(len(self.new_data["configs"][name]["rows"]), 82)
            else:
                self.assertEqual(self.new_data["configs"][name], config, name)
        for name, source in self.old_data["sources"].items():
            if name != "systems/archive_settlement.lua":
                self.assertEqual(self.new_data["sources"][name], source, name)

    def test_legacy_completed_wave_retry_returns_receipt_without_double_score(self):
        self.db.profile["save"]["archive"] = {"endless_best_wave": 400, "endless_score": 100}
        command = self.payload("endless", wave=400, difficulty=10)
        self.assertTrue(self.legacy.command(command)["ok"])
        after = copy.deepcopy(self.db.profile)
        committed = self.db.commit_count
        self.assertTrue(self.service.command(command)["ok"])
        self.assertEqual(self.db.profile, after)
        self.assertEqual(self.db.commit_count, committed)
        self.assertEqual(self.db.prepared_hashes[-1], self.old.hash)

    def test_legacy_unfinished_wave_uses_new_floor_rewards_without_hash_conflict(self):
        command = self.service.validate(self.payload("endless", wave=400, difficulty=10)["command"])
        fingerprint = hashlib.sha256(json.dumps(command, sort_keys=True,
            separators=(",", ":"), ensure_ascii=False).encode()).hexdigest()
        prepared = self.db.rpc("archive_prepare", {
            "p_hash": self.old.hash, "p_fingerprint": fingerprint,
            "p_id": command["id"], "p_command": command,
        })
        self.assertFalse(prepared["done"])
        response = self.service.command(self.payload("endless", wave=400, difficulty=10))
        self.assertTrue(response["ok"], response)
        self.assertGreater(self.award_count(), 0)
        self.assertEqual(self.db.ops[command["id"]]["hash"], self.old.hash)

    def test_unknown_hash_and_forged_progress_cannot_claim_rewards(self):
        before = copy.deepcopy(self.db.profile)
        rejected = self.service.command(self.payload("endless_reconcile", version="f" * 64))
        self.assertEqual(rejected["error"], "archive_config_mismatch")
        for key, value in (("wave", 461), ("score", 6000000), ("effects", {})):
            with self.subTest(field=key):
                with self.assertRaisesRegex(ArchiveError, "archive_command_fields_invalid"):
                    self.service.command(self.payload("endless_reconcile", **{key: value}))
        self.assertEqual(self.db.profile, before)
        self.assertEqual(self.db.commit_count, 0)

    def test_score_milestones_still_use_score_and_empty_profile_gets_no_floor_reward(self):
        self.assertTrue(self.service.command(self.payload("endless_reconcile"))["ok"])
        self.assertEqual(self.award_count(), 0)
        self.db.profile["save"]["archive"]["endless_score"] = 6000000
        self.assertTrue(self.service.command(self.payload(
            "endless_reconcile", match="offline-score"))["ok"])
        completed = self.db.profile["save"]["archive"]["completed"]
        self.assertTrue(all(completed.get("endless_" + str(number)) for number in range(1, 51)))
        self.assertEqual(self.award_count(), 0)

    def test_saved_floor_400_rewards_once_even_when_committed_reply_is_lost(self):
        self.db.profile["save"]["archive"] = {"endless_best_wave": 400}
        command = self.payload("endless_reconcile")
        self.db.lose_reply = True
        with self.assertRaises(TimeoutError):
            self.service.command(command)
        after = copy.deepcopy(self.db.profile)
        self.assertGreater(self.award_count(), 0)
        expected = sum(bool(row.get("enabled") and row.get("required_wave", 10000) <= 400)
                       for row in self.new.configs["archive_endless_achievements"]["rows"])
        self.assertEqual(self.award_count(), expected)
        self.assertTrue(self.service.command(command)["ok"])
        self.assertEqual(self.db.profile, after)
        self.assertTrue(self.service.command(self.payload(
            "endless_reconcile", match="offline-another-match"))["ok"])
        self.assertEqual(self.db.profile["save"], after["save"])

    def test_reconcile_then_next_wave_in_same_match_advances_score_and_rewards(self):
        self.db.profile["save"]["archive"] = {"endless_best_wave": 400, "endless_score": 123}
        self.assertTrue(self.service.command(self.payload("endless_reconcile"))["ok"])
        before = copy.deepcopy(self.db.profile["save"])
        self.assertTrue(self.service.command(self.payload("endless", wave=401, difficulty=10))["ok"])
        archive = self.db.profile["save"]["archive"]
        self.assertEqual(archive["endless_best_wave"], 401)
        rules = self.old.configs["archive_endless_rules"]["rows"][0]
        score = rules["score_multiplier"] * ((401 - 1) // rules["score_block_size"] + 1) + rules["score_offset"]
        self.assertEqual(archive["endless_score"], 123 + score)
        completed = archive["completed"]
        self.assertTrue(all(completed.get(key) for key in before["archive"]["completed"]))

    def test_pending_nonendless_receipt_keeps_original_reducer(self):
        command = self.service.validate(self.payload("boss_kill")["command"])
        fingerprint = hashlib.sha256(json.dumps(command, sort_keys=True,
            separators=(",", ":"), ensure_ascii=False).encode()).hexdigest()
        prepared = self.db.rpc("archive_prepare", {
            "p_hash": self.old.hash, "p_fingerprint": fingerprint,
            "p_id": command["id"], "p_command": command,
        })
        self.db.profile["save"]["archive"] = {"endless_best_wave": 400}
        prepared = self.db.resume(command["id"])
        called = []
        original = ArchiveService.settle
        def tracked(service, *args):
            called.append(service.bundle.hash)
            return original(service, *args)
        from unittest.mock import patch
        with patch.object(ArchiveService, "settle", tracked):
            result = self.service.finish_prepared("offline-account", command["id"], prepared)
        self.assertTrue(result["ok"], result)
        self.assertEqual(called, [self.old.hash])
        self.assertEqual(self.db.profile["save"]["archive"]["boss_kills"], 1)
        self.assertEqual(self.award_count(), 0)

    def test_legacy_lottery_snapshot_returns_requested_hash_without_mutating_save(self):
        before = copy.deepcopy(self.db.profile)
        response = self.service.lottery_snapshot({
            "account_id": "100", "config_hash": self.old.hash,
        })
        self.assertTrue(response["ok"], response)
        self.assertEqual(response["config_hash"], self.old.hash)
        self.assertEqual(self.db.profile, before)
        self.assertEqual(self.db.commit_count, 0)

    def test_new_hash_receipts_keep_new_hash_and_legacy_alias_stays_narrow(self):
        response = self.service.command(self.payload("endless", wave=1,
            difficulty=10, version=self.new.hash))
        self.assertTrue(response["ok"], response)
        self.assertEqual(self.db.prepared_hashes[-1], self.new.hash)
        before = copy.deepcopy(self.db.profile)
        for kind in ("starjoy_reconcile", "welfare_reconcile", "faith_cheat"):
            with self.subTest(kind=kind):
                response = self.service.command(self.payload(kind))
                self.assertEqual(response["error"], "archive_config_mismatch")
        self.assertEqual(self.db.profile, before)

    def test_configuration_switch_on_same_operation_cannot_overwrite_old_receipt(self):
        old = self.payload("endless", wave=400, difficulty=10)
        self.assertTrue(self.service.command(old)["ok"])
        before = copy.deepcopy(self.db.profile)
        new = copy.deepcopy(old)
        new["config_hash"] = self.new.hash
        response = self.service.command(new)
        self.assertEqual(response["error"], "archive_id_conflict")
        self.assertEqual(self.db.profile, before)
        self.assertEqual(self.db.commit_count, 1)

    def test_revision_conflict_retries_preserve_other_writer_and_award_floors_once(self):
        self.db.profile["save"]["archive"] = {"endless_best_wave": 400}
        wood_before = self.db.profile["save"]["gameplay_stats"]["initial_wood"]
        self.db.conflict = True
        result = self.service.command(self.payload("endless_reconcile"))
        self.assertTrue(result["ok"], result)
        self.assertEqual(self.db.profile["save"]["gameplay_stats"]["initial_wood"], wood_before + 100)
        self.assertGreater(self.award_count(), 0)
        self.assertEqual(self.db.commit_count, 1)

    def test_bundle_policy_cannot_upgrade_commerce_or_expand_endless_fields(self):
        compatibility = importlib.import_module("offline_endless_candidate_backend.config_compatibility")
        metadata = {"compatible_config_hashes": {self.old.hash: {
            "commands": ["endless", "commerce_purchase"],
            "upgrade_commands": ["commerce_purchase"],
        }}}
        with self.assertRaisesRegex(ValueError, "bundle_compatibility_upgrade_invalid"):
            compatibility.parse(metadata)
        metadata["compatible_config_hashes"][self.old.hash]["upgrade_commands"] = ["endless"]
        metadata["compatible_config_hashes"][self.old.hash]["commands"] = ["endless", "endless"]
        with self.assertRaisesRegex(ValueError, "bundle_compatibility_commands_invalid"):
            compatibility.parse(metadata)


if __name__ == "__main__":
    unittest.main()
