"""Validate challenge unlocks against the deployed immutable archive bundle.

No HTTP requests or player writes are made. The Lua receipt cases use an
isolated in-memory account and the actual packaged settlement worker.
Set SURVIVAL_CHALLENGE_SERVICE_CANDIDATE to test a staged service.py, with
unchanged dependencies loaded from the workspace backend package.
"""
from __future__ import annotations

import copy
import importlib
import json
import os
from pathlib import Path
import shutil
import sys
from types import ModuleType, SimpleNamespace
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "server"))
sys.path.insert(0, str(ROOT))
from archive_backend.bundle import Bundle
from archive_backend.service import ArchiveError, ArchiveService
from tools.test_endless_archive_upgrade import App, ReceiptDatabase


class ChallengeUnlockTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        global ArchiveError, ArchiveService
        candidate = os.environ.get("SURVIVAL_CHALLENGE_SERVICE_CANDIDATE")
        backend = Path(candidate).resolve().parent if candidate else None
        if backend:
            package = ModuleType("offline_challenge_unlock_backend")
            package.__path__ = [str(backend), str(ROOT / "server/archive_backend")]
            sys.modules[package.__name__] = package
            service_module = importlib.import_module(package.__name__ + ".service")
            ArchiveError = service_module.ArchiveError
            ArchiveService = service_module.ArchiveService
        current = json.loads((ROOT / "server/bundles/current.json").read_text(
            encoding="utf-8"))
        directory = Path(os.environ.get("SURVIVAL_CHALLENGE_BUNDLE", str(
            ROOT / "server/bundles" / current["hash"])))
        cls.bundle = Bundle(directory)
        cls.lua = os.environ.get("LUA_EXECUTABLE") or shutil.which("lua5.1") or shutil.which("lua")
        if not cls.lua:
            cls.lua = "C:/Program Files/lua/bin/lua5.1.exe"
        if not Path(cls.lua).is_file():
            raise RuntimeError("set LUA_EXECUTABLE to a Lua 5.1 executable")

    def setUp(self):
        self.db = ReceiptDatabase(self.bundle)
        self.service = ArchiveService(App(self.db), self.bundle, self.lua)

    def command(self, challenge="shadow_1", difficulty="n1", **extra):
        return {"id": "offline-challenge-match:challenge:1", "kind": "challenge",
                "challenge_id": challenge, "kill_sequence": 1,
                "difficulty_id": difficulty, **extra}

    def payload(self, command, digest=None):
        return {"account_id": "100", "config_hash": digest or self.bundle.hash,
                "command": command}

    def test_every_enabled_challenge_accepts_its_configured_minimum(self):
        enabled = [row for row in self.bundle.tables[
            "archive_challenge_definitions"].values() if row.get("enabled")]
        self.assertGreater(len(enabled), 0)
        for row in enabled:
            with self.subTest(challenge=row["challenge_id"]):
                difficulty = int(row["min_difficulty"])
                command = self.command(row["challenge_id"], "n" + str(difficulty))
                before = copy.deepcopy(command)
                accepted = self.service.validate(command)
                self.assertEqual(accepted["difficulty_id"], "n" + str(difficulty))
                self.assertEqual(command, before)

    def test_below_configured_minimum_stays_locked(self):
        for row in self.bundle.tables["archive_challenge_definitions"].values():
            minimum = int(row["min_difficulty"])
            if row.get("enabled") and minimum > 1:
                with self.subTest(challenge=row["challenge_id"]):
                    with self.assertRaisesRegex(ArchiveError, "^archive_challenge_locked$"):
                        self.service.validate(self.command(
                            row["challenge_id"], "n" + str(minimum - 1)))

    def test_n1_n2_low_difficulty_challenges_do_not_require_n3(self):
        for challenge, minimum in (("shadow_1", 1), ("shadow_2", 2),
                                   ("social_friend", 1), ("social_ex", 1),
                                   ("social_beast", 1)):
            with self.subTest(challenge=challenge):
                self.assertEqual(self.bundle.tables["archive_challenge_definitions"][
                    challenge]["min_difficulty"], minimum)
                accepted = self.service.validate(self.command(challenge, "N" + str(minimum)))
                self.assertEqual(accepted["difficulty_id"], "n" + str(minimum))

    def test_difficulty_limits_and_invalid_formats_are_rejected(self):
        for raw in ("n0", "n21", "n01", "n1.0", "n-1", "n1junk", "1 ",
                    "", None, True, False, 1.5, float("inf"), [], {}):
            with self.subTest(difficulty=raw):
                with self.assertRaisesRegex(ArchiveError, "^archive_difficulty_invalid$"):
                    self.service.validate(self.command(difficulty=raw))
        self.assertEqual(self.service.validate(self.command(difficulty="n20"))[
            "difficulty_id"], "n20")

    def test_disabled_and_unknown_challenges_are_rejected(self):
        with self.assertRaisesRegex(ArchiveError, "^archive_challenge_invalid$"):
            self.service.validate(self.command(challenge="unknown_offline_challenge"))
        tables = copy.deepcopy(self.bundle.tables)
        tables["archive_challenge_definitions"]["shadow_1"]["enabled"] = False
        service = ArchiveService(None, SimpleNamespace(tables=tables), self.lua)
        with self.assertRaisesRegex(ArchiveError, "^archive_challenge_invalid$"):
            service.validate(self.command())

    def test_clients_cannot_choose_drops_effects_or_reward_counts(self):
        for field, value in (("drops", ["shadow_23"]), ("effects", {}),
                             ("count", 99), ("reward_key", "n4"),
                             ("source_boss_difficulty", "n4"),
                             ("has_pass", True), ("account_id", "100")):
            with self.subTest(field=field):
                with self.assertRaisesRegex(ArchiveError, "^archive_command_fields_invalid$"):
                    self.service.validate(self.command(**{field: value}))

    def test_n1_n2_settle_two_items_from_their_own_pools_and_replay_once(self):
        for challenge, difficulty in (("shadow_1", "n1"), ("shadow_2", "n2")):
            with self.subTest(challenge=challenge):
                before_counts = copy.deepcopy(self.db.profile["save"]["archive"].get(
                    "shadow_counts", {}))
                response = self.service.command(self.payload(self.command(challenge, difficulty)))
                self.assertTrue(response["ok"], response)
                counts = self.db.profile["save"]["archive"]["shadow_counts"]
                awarded = {key: value - before_counts.get(key, 0)
                           for key, value in counts.items() if value != before_counts.get(key, 0)}
                self.assertEqual(sum(awarded.values()), 2)
                for item in awarded:
                    self.assertEqual(self.bundle.tables["archive_shadow_items"][item][
                        "source_boss_difficulty"], difficulty)
                settled = copy.deepcopy(self.db.profile)
                committed = self.db.commit_count
                replay = self.service.command(self.payload(self.command(challenge, difficulty)))
                self.assertTrue(replay["ok"], replay)
                self.assertEqual(self.db.profile, settled)
                self.assertEqual(self.db.commit_count, committed)

    def test_pre_upgrade_match_hash_can_settle_n1_challenge(self):
        aliases = self.bundle.compatible_config_hashes
        self.assertGreater(len(aliases), 0)
        for digest, rule in aliases.items():
            if "challenge" not in rule["commands"]:
                continue
            with self.subTest(hash=digest):
                db = ReceiptDatabase(self.bundle)
                service = ArchiveService(App(db), self.bundle, self.lua)
                response = service.command(self.payload(self.command(), digest))
                self.assertTrue(response["ok"], response)
                self.assertEqual(sum(db.profile["save"]["archive"]["shadow_counts"].values()), 2)
                self.assertEqual(db.prepared_hashes, [digest])
                settled = copy.deepcopy(db.profile)
                self.assertTrue(service.command(self.payload(self.command(), digest))["ok"])
                self.assertEqual(db.profile, settled)
                self.assertEqual(db.commit_count, 1)


if __name__ == "__main__":
    unittest.main()
