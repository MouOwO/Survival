"""Read-only tests for the production HTTP daily command boundary."""
from copy import deepcopy
from pathlib import Path
from types import SimpleNamespace
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "server"))
from archive_backend.service import ArchiveError, ArchiveService


class DailyCommandAuthority(unittest.TestCase):
    def setUp(self):
        # validate() uses no database or network, and daily commands need no catalog.
        self.service = ArchiveService(None, SimpleNamespace(tables={}), None)

    def command(self, **fields):
        return dict(id="daily-audit:claim:102", kind="daily_claim", target_day=102, **fields)

    def test_client_today_is_removed_before_database_prepare(self):
        command = self.command(today=999999)
        original = deepcopy(command)
        validated = self.service.validate(command)
        self.assertNotIn("today", validated)
        self.assertEqual(validated["target_day"], 102)
        self.assertEqual(command, original)
        self.assertNotIn("today", self.service.validate({"id": "daily-audit:init:102", "kind": "daily_init", "today": 0}))

    def test_client_cannot_supply_monthly_entitlement(self):
        for field, value in (("has_pass", True), ("pass", True), ("entitlements", {"archive_pass": {"active": True}})):
            with self.subTest(field=field), self.assertRaises(ArchiveError):
                self.service.validate(self.command(**{field: value}))

    def test_target_date_must_be_an_integer(self):
        for value in (True, "102", 102.5, -1, float("nan"), float("inf")):
            with self.subTest(value=value), self.assertRaises(ArchiveError):
                self.service.validate({"id": "daily-audit:invalid-date", "kind": "daily_claim", "target_day": value})


if __name__ == "__main__":
    unittest.main()
