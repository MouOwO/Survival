"""Offline regression checks for preserving historical rows during upgrade."""
import copy
from decimal import Decimal
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import dbtool
import verify_upgrade as audit


class UpgradeAuditTests(unittest.TestCase):
    def fixture(self):
        manifest = {"entries": [{"id": "legacy/one", "sha256": "old", "group": "legacy"},
                                {"id": audit.WOOD_MIGRATION, "sha256": "wood", "group": "target"}],
                    "harden_sha256": "secure"}
        stamp = "2026-09-19T10:00:00+00:00"
        ledger = {"legacy/one": {"migration_id": "legacy/one", "sha256": "old", "applied_at": stamp},
                  "security/harden.sql": {"migration_id": "security/harden.sql", "sha256": "secure", "applied_at": stamp}}
        stats, players = {}, {}
        for key, wood in (("private-account-a", Decimal("3.5")), ("private-account-b", 0), ("private-account-c", 1)):
            stats[key] = {"player_id": key, "wood_per_second": wood, "hero_basic_attack_growth": 7, "updated_at": stamp}
            players[key] = {"account_id": key, "profile_revision": 4, "updated_at": stamp}
        names = [*audit.MUTABLE, dbtool.LEDGER, "reward_grants", "player_archive_state", "archive_operations", "archive_online_outbox"]
        before = {"database": "goufayu_restore_audit", "tables": [{"name": name} for name in names],
                  "ledger": ledger, "markers": {}, "records": {"player_gameplay_stats": stats, "survival_players": players},
                  "hashes": {"public." + name: {"rows": 3, "sha256": "original"} for name in names[3:]}}
        after = copy.deepcopy(before)
        new_stamp = "2026-09-20T10:00:00+00:00"
        after["tables"].append({"name": audit.MARKER})
        for key in ("private-account-a", "private-account-c"):
            after["records"]["player_gameplay_stats"][key]["wood_per_second"] -= 1
            after["records"]["player_gameplay_stats"][key]["updated_at"] = new_stamp
            after["records"]["survival_players"][key]["profile_revision"] += 1
            after["records"]["survival_players"][key]["updated_at"] = new_stamp
        after["ledger"][audit.WOOD_MIGRATION] = {"migration_id": audit.WOOD_MIGRATION, "sha256": "wood", "applied_at": new_stamp}
        after["markers"][dbtool.WOOD_MARKER] = {"migration_id": dbtool.WOOD_MARKER, "applied_at": new_stamp}
        return before, after, manifest

    def test_accepts_only_once_subtraction_and_matching_revisions(self):
        before, after, manifest = self.fixture()
        result = audit.audit_snapshots(before, after, manifest)
        self.assertEqual(result["status"], "PASS")
        self.assertEqual(result["wood_rows_adjusted_once"], 2)
        self.assertNotIn("private-account", json.dumps(result))
        self.assertFalse(result["repeat_run_all_business_rows_unchanged"])

    def test_existing_marker_prevents_repeated_subtraction_even_with_pending_sql(self):
        before, after, manifest = self.fixture()
        before["tables"].append({"name": audit.MARKER})
        before["markers"] = copy.deepcopy(after["markers"])
        after["records"] = copy.deepcopy(before["records"])
        result = audit.audit_snapshots(before, after, manifest)
        self.assertEqual(result["wood_rows_adjusted_once"], 0)

    def test_every_immutable_table_hash_is_checked(self):
        before, after, manifest = self.fixture()
        for name in before["hashes"]:
            with self.subTest(table=name):
                changed = copy.deepcopy(after)
                changed["hashes"][name]["sha256"] = "modified"
                with self.assertRaisesRegex(dbtool.Refused, "immutable_history"):
                    audit.audit_snapshots(before, changed, manifest)

    def test_unrelated_stat_or_missing_revision_or_unaffected_timestamp_is_refused(self):
        before, after, manifest = self.fixture()
        for table, key, field, value in (
            ("player_gameplay_stats", "private-account-a", "hero_basic_attack_growth", 0),
            ("survival_players", "private-account-a", "profile_revision", 4),
            ("player_gameplay_stats", "private-account-b", "updated_at", "2026-09-20T11:00:00+00:00"),
        ):
            with self.subTest(table=table, field=field):
                changed = copy.deepcopy(after)
                changed["records"][table][key][field] = value
                with self.assertRaisesRegex(dbtool.Refused, "player_data_unexpected"):
                    audit.audit_snapshots(before, changed, manifest)

    def test_old_ledger_and_marker_are_immutable(self):
        before, after, manifest = self.fixture()
        changed = copy.deepcopy(after)
        changed["ledger"]["legacy/one"]["applied_at"] = "replaced"
        with self.assertRaisesRegex(dbtool.Refused, "old_ledger_row_changed"):
            audit.audit_snapshots(before, changed, manifest)
        changed = copy.deepcopy(after)
        changed["markers"] = {}
        with self.assertRaisesRegex(dbtool.Refused, "marker_inventory"):
            audit.audit_snapshots(before, changed, manifest)

    def test_repeat_run_requires_all_business_rows_exactly_unchanged(self):
        _, before, manifest = self.fixture()
        after = copy.deepcopy(before)
        result = audit.audit_snapshots(before, after, manifest)
        self.assertTrue(result["repeat_run_all_business_rows_unchanged"])
        self.assertEqual(result["schema_migrations_applied"], 0)
        self.assertEqual(result["wood_rows_adjusted_once"], 0)
        after["records"]["player_gameplay_stats"]["private-account-a"]["wood_per_second"] -= 1
        with self.assertRaisesRegex(dbtool.Refused, "player_data_unexpected"):
            audit.audit_snapshots(before, after, manifest)

    def test_unexpected_new_account_or_table_is_refused(self):
        before, after, manifest = self.fixture()
        changed = copy.deepcopy(after)
        changed["records"]["survival_players"]["unexpected"] = {}
        with self.assertRaisesRegex(dbtool.Refused, "rows_added_or_removed"):
            audit.audit_snapshots(before, changed, manifest)
        changed = copy.deepcopy(after)
        changed["tables"].append({"name": "unexpected_table"})
        with self.assertRaisesRegex(dbtool.Refused, "table_inventory"):
            audit.audit_snapshots(before, changed, manifest)

    def test_explicit_session_migration_may_only_add_an_empty_table(self):
        before, after, manifest = self.fixture()
        manifest["entries"].append({"id": audit.SESSION_MIGRATION, "sha256": "sessions", "group": "target"})
        after["ledger"][audit.SESSION_MIGRATION] = {"migration_id": audit.SESSION_MIGRATION, "sha256": "sessions"}
        after["tables"].append({"name": audit.SESSION_TABLE})
        after["added_counts"] = {audit.SESSION_TABLE: 0}
        self.assertEqual(audit.audit_snapshots(before, after, manifest)["status"], "PASS")
        changed = copy.deepcopy(after)
        changed["added_counts"][audit.SESSION_TABLE] = 1
        with self.assertRaisesRegex(dbtool.Refused, "session_table_not_empty"):
            audit.audit_snapshots(before, changed, manifest)
        # A subsequent run preserves existing immutable session baselines too.
        after["hashes"]["public." + audit.SESSION_TABLE] = {"rows": 3, "sha256": "saved-baselines"}
        again = copy.deepcopy(after)
        self.assertTrue(audit.audit_snapshots(after, again, manifest)["repeat_run_all_business_rows_unchanged"])
        again["hashes"]["public." + audit.SESSION_TABLE]["sha256"] = "erased"
        with self.assertRaisesRegex(dbtool.Refused, "immutable_history"):
            audit.audit_snapshots(after, again, manifest)

    def test_report_is_exclusive_and_errors_never_contain_driver_details(self):
        with tempfile.TemporaryDirectory() as tmp:
            report = Path(tmp) / "report.json"
            with patch.object(dbtool, "load_bundle", side_effect=RuntimeError("password=secret private-account-a")):
                result = audit.run("service", "bundle", report)
            self.assertEqual(result["error"], "RuntimeError")
            self.assertNotIn("secret", report.read_text())
            with patch.object(dbtool, "load_bundle") as load:
                with self.assertRaises(FileExistsError):
                    audit.run("service", "bundle", report)
                load.assert_not_called()


if __name__ == "__main__":
    unittest.main()
