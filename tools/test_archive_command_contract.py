"""Exercise the game/backend command contract without HTTP, profiles or bundles."""
from __future__ import annotations

import copy
from pathlib import Path
import sys
from types import SimpleNamespace
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "server"))
from archive_backend.bundle import read_csv
from archive_backend.service import ArchiveError, ArchiveService


class ArchiveCommandContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        definitions = read_csv(
            ROOT / "data/csv/存档系统/archive_challenge_definitions.csv"
        )
        cls.service = ArchiveService(
            None,
            SimpleNamespace(tables={"archive_challenge_definitions": {
                row["challenge_id"]: row for row in definitions["rows"]
            }}),
            "not-executed",
        )

    def command(self, kind, **fields):
        return {"id": "contract-match:" + kind + ":123", "kind": kind, **fields}

    def test_game_kill_and_clear_commands_are_accepted(self):
        commands = [
            self.command("boss_kill"),
            self.command("endless", wave=15, difficulty=10),
            self.command("challenge", challenge_id="hunt_01", kill_sequence=3,
                         difficulty_id="n10", day_key="20000"),
            self.command("clear", difficulty_id="n10", count=1,
                         day_key="20000", cooperative_win=1),
        ]
        for command in commands:
            with self.subTest(kind=command["kind"]):
                before = copy.deepcopy(command)
                result = self.service.validate(command)
                self.assertEqual(result["kind"], command["kind"])
                self.assertNotIn("day_key", result)
                self.assertEqual(command, before)
        self.assertEqual(self.service.validate(commands[1])["id"],
                         "contract-match:endless:15")
        self.assertEqual(self.service.validate(commands[2])["id"],
                         "contract-match:challenge_kind:hunt_01")
        self.assertEqual(self.service.validate(commands[3])["cooperative_win"], 1)

    def test_background_reconciliations_accept_only_persisted_progress(self):
        for kind in ("starjoy_reconcile", "welfare_reconcile", "endless_reconcile"):
            with self.subTest(kind=kind):
                command = self.command(kind)
                result = self.service.validate(command)
                self.assertEqual(result, {
                    "id": "contract-match:" + kind, "kind": kind,
                })
                for key, value in (("wave", 461), ("score", 5000),
                                   ("effects", {}), ("cooperative_win", 1)):
                    with self.subTest(kind=kind, field=key):
                        with self.assertRaisesRegex(
                                ArchiveError, "^archive_command_fields_invalid$"):
                            self.service.validate({**command, key: value})

    def test_kill_commands_reject_untrusted_reward_and_progress_fields(self):
        commands = [
            self.command("boss_kill"),
            self.command("endless", wave=15, difficulty=10),
            self.command("challenge", challenge_id="hunt_01", kill_sequence=3,
                         difficulty_id="n10"),
        ]
        for command in commands:
            for key, value in (("count", 99), ("score", 9999),
                               ("effects", {}), ("account_id", "1")):
                with self.subTest(kind=command["kind"], field=key):
                    with self.assertRaisesRegex(
                            ArchiveError, "^archive_command_fields_invalid$"):
                        self.service.validate({**command, key: value})

    def test_endless_requires_valid_wave_and_difficulty(self):
        for field in ("wave", "difficulty"):
            for value in (None, True, -1, 1.5, float("inf"), "10"):
                with self.subTest(field=field, value=value):
                    command = self.command("endless", wave=15, difficulty=10)
                    command[field] = value
                    with self.assertRaisesRegex(
                            ArchiveError, "^archive_number_invalid:" + field + "$"):
                        self.service.validate(command)

    def test_cooperative_clear_flag_is_bounded(self):
        for value in (0, 1):
            self.assertEqual(self.service.validate(self.command(
                "clear", difficulty_id="n10", count=1,
                cooperative_win=value))["cooperative_win"], value)
        for value in (True, -1, 2, "1"):
            with self.subTest(value=value):
                with self.assertRaisesRegex(
                        ArchiveError, "^archive_number_invalid:cooperative_win$"):
                    self.service.validate(self.command(
                        "clear", difficulty_id="n10", count=1,
                        cooperative_win=value))


if __name__ == "__main__":
    unittest.main()
