"""Offline immutable mode export/session validation; no HTTP or player writes."""
from __future__ import annotations

import copy
from pathlib import Path
import sys
from types import SimpleNamespace
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "server"))
from archive_backend.bundle import challenge_modes, read_csv
from archive_backend.challenge_sessions import validate, validate_batch
from archive_backend.service import ArchiveError, ArchiveService


class App:
    def __init__(self, mode):
        self.mode, self.calls, self.writes = mode, [], 0
        self.rpc_client = self
        self.context_patch = {}

    def _database_account_id(self, account):
        return "offline-account"

    def rpc(self, method, payload):
        self.calls.append((method, copy.deepcopy(payload)))
        if method != "match_profile_context":
            raise AssertionError("test must reject before mutation: " + method)
        return {"ok": True, "mode": self.mode, "account_id": payload["p_account"],
                "match_session_id": payload["p_session"], **self.context_patch}

    def _ensure_gameplay_stats(self, account):
        self.writes += 1
        raise AssertionError("invalid command must not start writes")


class ChallengeModeSessions(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.export = challenge_modes((ROOT / "scripts/vscripts/config/generated/human_monster_spec.lua").read_text(encoding="utf-8-sig"))
        cls.modes = {row["mode_id"]: row for row in cls.export["rows"]}
        definitions = read_csv(ROOT / "data/csv/存档系统/archive_challenge_definitions.csv")
        cls.definitions = {row["challenge_id"]: row for row in definitions["rows"]}

    def service(self, mode):
        app = App(mode)
        bundle = SimpleNamespace(tables={"archive_challenge_modes": copy.deepcopy(self.modes),
                                         "archive_challenge_definitions": self.definitions},
                                 hash="0" * 64, compatible_config_hashes={})
        return ArchiveService(app, bundle, "not-executed")

    def command(self, difficulty, *, variant=None, kind="endless", wave=1):
        result = {"id": "offline-session-20261029:" + kind + ":1", "kind": kind}
        if kind == "endless":
            result.update(wave=wave, difficulty=difficulty)
            if variant is not None:
                result["variant"] = variant
        else:
            result.update(challenge_id="shadow_1", kill_sequence=1, difficulty_id="n" + str(difficulty))
        return result

    def payload(self, command):
        return {"account_id": "100", "match_session_id": "offline-session-20261029",
                "config_hash": "0" * 64, "command": command}

    def test_export_uses_actual_packaged_lua_tiers(self):
        self.assertEqual({mode: max(row["difficulties"]) for mode, row in self.modes.items()},
                         {"standard": 10, "pure": 10, "rich": 30, "cold": 50,
                          "scourge": 50, "ruins": 50, "celestial": 35})

    def test_each_mode_accepts_its_own_tiers_and_rejects_the_next(self):
        for mode, row in self.modes.items():
            service = self.service(mode)
            maximum = max(row["difficulties"])
            for number in row["difficulties"]:
                with self.subTest(mode=mode, tier=number):
                    command = service.validate(self.command(number))
                    before = copy.deepcopy(command)
                    validate(service, self.payload(command), command)
                    self.assertEqual(command, before)
            if maximum < 50:
                for kind in ("endless", "challenge"):
                    with self.subTest(mode=mode, kind=kind, invalid=maximum + 1):
                        command = service.validate(self.command(maximum + 1, kind=kind))
                        with self.assertRaisesRegex(ArchiveError, "^archive_mode_difficulty_unavailable$"):
                            validate(service, self.payload(command), command)

    def test_caller_cannot_choose_a_mode_or_forge_session_identity(self):
        service = self.service("standard")
        command = self.command(30)
        with self.assertRaisesRegex(ArchiveError, "archive_command_fields_invalid"):
            service.validate({**command, "mode_id": "rich"})
        for patch in ({"mode": "unknown"}, {"account_id": "somebody-else"},
                      {"match_session_id": "another-session"}, {"ok": False}):
            service.app.context_patch = patch
            with self.subTest(patch=patch), self.assertRaises(ArchiveError):
                validate(service, self.payload(command), command)
        with self.assertRaisesRegex(ArchiveError, "match_session_missing"):
            validate(service, {}, command)

    def test_tower_requires_its_own_modes_and_minimum(self):
        for mode in self.modes:
            service = self.service(mode)
            for number in (9, 10):
                command = service.validate(self.command(number, variant="tower"))
                if mode in {"cold", "scourge"} and number >= 10:
                    validate(service, self.payload(command), command)
                else:
                    with self.assertRaisesRegex(ArchiveError, "endless_variant_unavailable"):
                        validate(service, self.payload(command), command)

    def test_variant_receipts_do_not_collide_or_modify_old_endless_commands(self):
        service = self.service("cold")
        normal = service.validate(self.command(10))
        tower = service.validate(self.command(10, variant="tower"))
        self.assertEqual(normal["id"], "offline-session-20261029:endless:1")
        self.assertEqual(tower["id"], "offline-session-20261029:tower:1")
        self.assertNotIn("variant", normal)
        for variant in ("", "bogus", True, [], {}):
            with self.subTest(variant=variant), self.assertRaisesRegex(ArchiveError, "endless_variant_invalid"):
                service.validate({**self.command(10), "variant": variant})

    def test_invalid_later_batch_entry_rejects_before_any_award(self):
        service = self.service("standard")
        commands = [self.command(10, wave=1), self.command(30, wave=2)]
        payload = self.payload(commands[0])
        payload["commands"] = commands
        with self.assertRaisesRegex(ArchiveError, "archive_mode_difficulty_unavailable"):
            service.endless_batch(payload)
        self.assertEqual(service.app.writes, 0)

    def test_batch_uses_one_bound_identity_for_all_tiers(self):
        service = self.service("cold")
        commands = [service.validate(self.command(n, wave=i + 1)) for i, n in enumerate((30, 50, 21))]
        validate_batch(service, self.payload(commands[0]), commands)
        self.assertEqual(len(service.app.calls), 1)

    def test_legacy_low_tier_and_completed_receipts_are_preserved(self):
        service = self.service("standard")
        command = service.validate(self.command(10))
        validate(service, {}, command)
        self.assertEqual(service.app.calls, [])
        completed = {"ok": True, "done": True, "profile": {"revision": 7}}
        self.assertIs(service.finish_prepared("offline-account", "old-id", completed), completed)
        service.bundle.tables.pop("archive_challenge_modes")
        with self.assertRaisesRegex(ArchiveError, "archive_challenge_mode_config_missing"):
            validate(service, self.payload(self.command(30)), self.command(30))

    def test_pending_high_tiers_and_solo_tower_revalidate_durable_session(self):
        service = self.service("cold")
        for number, variant in ((50, None), (10, "tower")):
            command = service.validate(self.command(number, variant=variant))
            validate(service, {}, command, database_account="offline-account", pending=True)
            service.app.context_patch = {"mode": "standard"}
            with self.assertRaises(ArchiveError):
                validate(service, {}, command, database_account="offline-account", pending=True)
            service.app.context_patch = {}


if __name__ == "__main__":
    unittest.main()
