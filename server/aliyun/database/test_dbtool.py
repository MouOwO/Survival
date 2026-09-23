"""Offline safety-contract tests; no database connections or original data."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import MagicMock, patch

import dbtool


class DatabaseToolTests(unittest.TestCase):
    def manifest(self):
        return {"entries": [{"id": name, "sha256": "sha-" + name, "group": group}
                            for name, group in (("a", "legacy"), ("b", "addon"), ("c", "target"))],
                "harden_sha256": "harden"}

    def test_migrate_identity_rejects_nonisolated_database_before_role_switch(self):
        conn = MagicMock()
        conn.execute.return_value.fetchone.side_effect = [(170011,), ("production", "goufayu_migrator")]
        with self.assertRaisesRegex(dbtool.Refused, "target_database_name_refused"):
            dbtool.target_identity(conn)
        self.assertFalse(any("SET ROLE" in call.args[0] for call in conn.execute.call_args_list))

    def test_ledger_empty_holes_unknown_ids_and_wrong_hashes_refused(self):
        for applied, code in (({}, "empty_migration_ledger"),
                              ({"b": "sha-b"}, "not_contiguous"),
                              ({"a": "sha-a", "c": "sha-c"}, "not_contiguous"),
                              ({"a": "bad"}, "checksum"),
                              ({"alien": "sha-alien"}, "checksum"),
                              ({"security/harden.sql": "harden"}, "not_contiguous"),
                              ({"a": "sha-a", "security/harden.sql": "harden"}, "before_business"),
                              ({"restore/source": "dump"}, "use_reconcile")):
            with self.subTest(applied=applied), self.assertRaisesRegex(dbtool.Refused, code):
                dbtool.applied_prefix(self.manifest(), applied)

    def test_valid_prefix_resume_and_appended_target_after_hardening(self):
        manifest = self.manifest()
        self.assertEqual(dbtool.applied_prefix(manifest, {"a": "sha-a"}), manifest["entries"][:1])
        self.assertEqual(dbtool.applied_prefix(manifest, {"b": "sha-b", "a": "sha-a",
                          "security/harden.sql": "harden"}), manifest["entries"][:2])

    def test_new_hardening_preserves_old_hash_and_requires_unchanged_applied_patches(self):
        manifest = self.manifest()
        manifest["hardening_patches"] = [{"id": "security/harden_lottery.sql", "path": "harden_lottery.sql", "sha256": "v2"}]
        old = {"a": "sha-a", "b": "sha-b", "security/harden.sql": "harden"}
        self.assertEqual(len(dbtool.applied_prefix(manifest, old)), 2)
        latest = dict(old, c="sha-c")
        latest["security/harden_lottery.sql"] = "v2"
        self.assertEqual(len(dbtool.applied_prefix(manifest, latest)), 3)
        latest["security/harden_lottery.sql"] = "changed"
        with self.assertRaisesRegex(dbtool.Refused, "checksum"):
            dbtool.applied_prefix(manifest, latest)

    def test_collect_appends_new_sql_after_the_complete_test03_prefix(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            legacy, addon, target = root / "legacy", root / "addon", root / "release"
            (legacy / "supabase/migrations").mkdir(parents=True)
            (addon / "server/migrations").mkdir(parents=True)
            (addon / "tools/sql").mkdir(parents=True)
            sql = b"-- preserve CRLF\r\nBEGIN; SELECT 1; COMMIT;\r\n"
            for name in dbtool.LEGACY_FILES:
                (legacy / "supabase/migrations" / name).write_bytes(sql)
            for name in (*dbtool.ARCHIVE_FILES, *(name for name, _ in dbtool.UPGRADE_FILES)):
                (addon / "server/migrations" / name).write_bytes(sql)
                (legacy / "supabase/migrations" / name).write_bytes(sql)
            (addon / "tools/sql/202609060001_archive_fishing_inventory.sql").write_bytes(sql)
            result = dbtool.collect(legacy, addon, target)
            self.assertEqual(result["migrations"], 22)
            manifest = dbtool.load_bundle(target)
            old_entries = manifest["entries"][:17]
            self.assertEqual([e["group"] for e in old_entries], ["legacy"] * 12 + ["addon"] * 3 + ["manual", "target"])
            self.assertEqual(old_entries[-1]["id"], "target/202609190001_attack_interval_semantics.sql")
            applied = {e["id"]: e["sha256"] for e in old_entries}
            applied["security/harden.sql"] = manifest["harden_sha256"]
            self.assertEqual(dbtool.applied_prefix(manifest, applied), old_entries)
            self.assertEqual(manifest["entries"][-1]["id"], "target/202609230001_match_profile_sessions.sql")
            # All deployed test05 entries remain a complete unchanged prefix.
            latest_applied = {e["id"]: e["sha256"] for e in manifest["entries"][:21]}
            latest_applied["security/harden.sql"] = manifest["harden_sha256"]
            self.assertEqual(len(dbtool.applied_prefix(manifest, latest_applied)), 21)
            for entry in manifest["entries"][:16] + manifest["entries"][17:21]:
                self.assertEqual((target / entry["path"]).read_bytes(), sql)
            (addon / "server/migrations/unreviewed.sql").write_bytes(sql)
            with self.assertRaisesRegex(dbtool.Refused, "unreviewed_addon"):
                dbtool.collect(legacy, addon, target)

    def test_new_backup_inventory_includes_migration_marker_and_lottery_function(self):
        self.assertIn("survival_data_migrations", dbtool.TABLES)
        self.assertIn("archive_commit_lottery", dbtool.FUNCTIONS)
        self.assertIn("match_profile_sessions", dbtool.TABLES)
        self.assertIn("match_profile_login", dbtool.FUNCTIONS)

    def test_git_crlf_restores_exact_historical_hash_and_rejects_real_edits(self):
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "harden.sql"
            original = dbtool.release_bytes(dbtool.HERE / "harden.sql")
            target.write_bytes(original.replace(b"\n", b"\r\n"))
            self.assertEqual(dbtool.release_bytes(target), original)
            target.write_bytes(original + b"-- changed\n")
            with self.assertRaisesRegex(dbtool.Refused, "historical_test03_sql_modified"):
                dbtool.release_bytes(target)

    def test_hardening_patch_is_checked_before_use(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "harden.sql").write_text("SELECT 1;", encoding="utf-8")
            (root / "harden_lottery.sql").write_text("SELECT 2;", encoding="utf-8")
            manifest = {"format": 1, "postgres_major": 17, "entries": [],
                        "harden_sha256": dbtool.sha256(root / "harden.sql"), "hardening_patches": [
                            {"id": "security/harden_lottery.sql", "path": "harden_lottery.sql",
                             "sha256": dbtool.sha256(root / "harden_lottery.sql")}]}
            dbtool.write_json(root / "migration_manifest.json", manifest)
            self.assertEqual(dbtool.load_bundle(root), manifest)
            (root / "harden_lottery.sql").write_text("SELECT 3;", encoding="utf-8")
            with self.assertRaisesRegex(dbtool.Refused, "patch_checksum"):
                dbtool.load_bundle(root)

    def test_schema_contract_tracks_removed_relations_and_literal_function_drop(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "one.sql").write_text("""BEGIN;
              create table if not exists public.kept(id text);
              create table public.retired(id text);
              create or replace function public.old() returns void as $$ BEGIN END $$ language plpgsql;
              -- create table public.comment_is_not_a_table(id text);
              COMMIT;""", encoding="utf-8")
            (root / "two.sql").write_text("""BEGIN;
              drop table if exists public.retired;
              DO $$ BEGIN execute 'drop function public.old()'; END $$;
              create or replace function public.new() returns void as $$ BEGIN END $$ language plpgsql;
              COMMIT;""", encoding="utf-8")
            tables, functions = dbtool.expected_prefix_objects(root, [{"path": "one.sql"}, {"path": "two.sql"}])
            self.assertEqual(tables, {"public.kept", "public._goufayu_migrations"})
            self.assertEqual(functions, {"public.new"})

    def test_unknown_extension_and_schema_refused_before_empty_check(self):
        conn = MagicMock()
        conn.execute.return_value.__iter__.return_value = iter([("hstore", "public")])
        with self.assertRaisesRegex(dbtool.Refused, "target_unknown_extension"):
            dbtool.require_empty(conn)
        conn = MagicMock()
        conn.execute.return_value.__iter__.return_value = iter([("pgcrypto", "extensions")])
        conn.execute.return_value.fetchone.return_value = (1,)
        with self.assertRaisesRegex(dbtool.Refused, "target_unknown_schema"):
            dbtool.require_empty(conn)

    def test_original_transaction_body_only_loses_outer_wrapper(self):
        body = "\nDO $$ BEGIN perform 1; END $$;\n"
        self.assertEqual(dbtool.transaction_body("-- note\nBEGIN;" + body + "COMMIT;\n"), body)
        with self.assertRaises(dbtool.Refused):
            dbtool.transaction_body("DROP TABLE something;")

    def test_trial_names_exclude_production_and_system_databases(self):
        for name in ("goufayu_test", "goufayu_restore_20260919", "goufayu_restore_canary"):
            self.assertIsNotNone(dbtool.TRIAL_RE.fullmatch(name))
        for name in ("postgres", "goufayu", "survival", "goufayu_test_live", "goufayu_restore_", "goufayu_restore_X"):
            self.assertIsNone(dbtool.TRIAL_RE.fullmatch(name))

    def test_service_names_cannot_inject_conninfo(self):
        for value in ("host=somewhere password=secret", "a b", "service\npassword", "x'", "service;drop"):
            with self.assertRaises(dbtool.Refused):
                dbtool.connect(value)

    def test_bundle_rejects_modified_sql_and_path_escape(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "migration.sql").write_text("BEGIN; SELECT 1; COMMIT;", encoding="utf-8")
            (root / "harden.sql").write_text("SELECT 1;", encoding="utf-8")
            manifest = {"format": 1, "postgres_major": 17,
                        "harden_sha256": dbtool.sha256(root / "harden.sql"),
                        "entries": [{"id": "one", "path": "migration.sql", "sha256": dbtool.sha256(root / "migration.sql")}]}
            dbtool.write_json(root / "migration_manifest.json", manifest)
            self.assertEqual(dbtool.load_bundle(root), manifest)
            (root / "migration.sql").write_text("BEGIN; SELECT 2; COMMIT;", encoding="utf-8")
            with self.assertRaisesRegex(dbtool.Refused, "checksum"):
                dbtool.load_bundle(root)
            manifest["entries"][0]["path"] = "../migration.sql"
            dbtool.write_json(root / "migration_manifest.json", manifest)
            with self.assertRaisesRegex(dbtool.Refused, "path"):
                dbtool.load_bundle(root)

    def test_existing_backup_directory_never_overwritten(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaisesRegex(dbtool.Refused, "already_exists"):
                dbtool.private_directory(tmp)

    def test_client_error_never_exposes_stderr_or_password(self):
        class Result:
            returncode = 1
            stderr = b"password=DO_NOT_PRINT account=user-data"
        with patch.object(dbtool.subprocess, "run", return_value=Result()):
            with self.assertRaises(dbtool.Refused) as got:
                dbtool.run_client(["pg_dump", "--version"])
        self.assertNotIn("DO_NOT_PRINT", str(got.exception))
        self.assertNotIn("user-data", str(got.exception))

    def test_client_readonly_environment(self):
        class Result:
            returncode = 0
            stdout = b""
        with patch.object(dbtool.subprocess, "run", return_value=Result()) as run:
            dbtool.run_client(["pg_dump", "--version"], readonly=True)
        self.assertIn("default_transaction_read_only=on", run.call_args.kwargs["env"]["PGOPTIONS"])

    def test_app_grants_match_adapter_contract(self):
        sql = "\n".join((dbtool.HERE / name).read_text(encoding="utf-8") for name in ("harden.sql", *dbtool.HARDEN_PATCHES))
        self.assertEqual(len(dbtool.RPC_SIGNATURES), 14)
        for signature in dbtool.RPC_SIGNATURES:
            self.assertIn("public." + signature, sql)
        self.assertIn("pg_catalog,public,extensions,pg_temp", sql)
        self.assertNotIn("BYPASSRLS TO goufayu_app", sql)


if __name__ == "__main__":
    unittest.main()
