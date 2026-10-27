"""Boundary tests use local inputs or mocks; never SSH, SQL writes or gateways."""
import base64
from contextlib import redirect_stderr
import copy
import hashlib
import io
import json
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

import catalog_validation
import deploy_plan
import remote_review
import run
import restore_cloud_sources


class ReviewTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.plan, cls.files = deploy_plan.build()

    def test_candidate_freezes_formal_counts_and_has_no_legacy_operator(self):
        self.assertEqual((self.plan["catalog"]["cash_enabled"], self.plan["catalog"]["wallet_enabled"]), (48, 125))
        self.assertFalse(self.plan["payments_enabled"])
        self.assertFalse(self.plan["activation_implemented"])
        self.assertNotIn("payment_backend/deploy.py", self.files)
        self.assertNotIn("payment_backend/sync_catalog.py", self.files)
        self.assertFalse(any(name.startswith("payment_backend/upgrade_") and name.endswith(".py") for name in self.files))
        self.assertEqual(set(self.plan["migration_source_hashes"]), set(deploy_plan.SCHEMA_SOURCES))
        self.assertEqual(json.loads(self.files["plan.json"]), self.plan)
        for name, digest in self.plan["source_hashes"].items():
            self.assertEqual(hashlib.sha256(self.files[name]).hexdigest(), digest)

    def test_plan_identity_and_fixed_stage_prevent_retargeting(self):
        remote_review.validate_plan(self.plan)
        for edit in (lambda p:p.update(stage="/etc/goufayu"),
                     lambda p:p["payment"].update(port=8766),
                     lambda p:p["payment"]["dsn_identity"].update(dbname="goufayu_test"),
                     lambda p:p.update(payments_enabled=True)):
            candidate = copy.deepcopy(self.plan)
            edit(candidate)
            with self.assertRaises(RuntimeError):
                remote_review.validate_plan(candidate)

    def test_cli_cannot_activate_and_prepare_requires_reviewed_identity(self):
        self.assertEqual(run.arguments([]).mode, "plan")
        with self.assertRaises(SystemExit), redirect_stderr(io.StringIO()):
            run.arguments(["activate"])
        with self.assertRaises(SystemExit), redirect_stderr(io.StringIO()):
            run.arguments(["prepare"])
        with patch.object(run, "build", return_value=(self.plan, self.files)), patch.object(run, "remote") as remote:
            with self.assertRaisesRegex(ValueError, "reviewed_candidate_changed"):
                run.main(["prepare", "--review-hash", "0" * 64])
            remote.assert_not_called()

    def test_default_plan_never_uses_transport_or_writes_output(self):
        with patch.object(run, "build", return_value=(self.plan, self.files)), patch.object(run, "remote") as remote, \
             patch.object(Path, "mkdir") as mkdir, patch("builtins.print"):
            run.main([])
            remote.assert_not_called()
            mkdir.assert_not_called()

    def test_queries_enforce_fixed_container_database_and_read_only_transaction(self):
        with patch.object(remote_review, "command", return_value=b'{"ok":true}\n') as command:
            self.assertEqual(remote_review.sql("SELECT json_build_object('ok',true);"), {"ok": True})
        args, body = command.call_args.args
        self.assertIn("goufayu-ws4-db", args)
        self.assertEqual(args[-1], "goufayu_ws4")
        self.assertIn(b"READ ONLY", body)
        self.assertTrue(body.rstrip().endswith(b"ROLLBACK;"))
        for source in ("UPDATE payments.products SET enabled=false", "DELETE FROM payments.orders", "COMMIT;", "SELECT 1; COMMIT; UPDATE payments.orders SET state='delivered';"):
            with self.assertRaises(RuntimeError):
                remote_review.sql(source)

    def test_stage_file_set_hash_and_paths_are_checked_before_any_write(self):
        encoded = deploy_plan.encoded_files(self.files)
        self.assertEqual(remote_review.decode_files(self.plan, encoded), self.files)
        missing = dict(encoded)
        missing.pop("plan.json")
        with self.assertRaisesRegex(RuntimeError, "stage_file_set_mismatch"):
            remote_review.decode_files(self.plan, missing)
        changed = {**encoded, "catalog-package.json": base64.b64encode(b"changed").decode()}
        with self.assertRaisesRegex(RuntimeError, "stage_source_hash_mismatch"):
            remote_review.decode_files(self.plan, changed)
        for name in ("../escape.py", "/etc/goufayu-payment/config.json", "path//alias.py", "path\\file.py"):
            plan = copy.deepcopy(self.plan)
            plan["source_hashes"][name] = hashlib.sha256(b"x").hexdigest()
            bad = {**encoded, name: base64.b64encode(b"x").decode()}
            bad["plan.json"] = base64.b64encode(remote_review.canonical(plan)).decode()
            with self.assertRaisesRegex(RuntimeError, "stage_relative_path_required"):
                remote_review.decode_files(plan, bad)

    def test_review_operator_has_no_service_or_role_mutation_command(self):
        source = Path(remote_review.__file__).read_text(encoding="utf-8")
        compile("try:\n" + "".join(" " + line + "\n" for line in source.splitlines()) + "except Exception:\n pass\n", "pinned_transport_wrapper", "exec")
        for forbidden in ("systemctl restart", "systemctl stop", "ALTER ROLE", "GRANT CONNECT", "psycopg.connect"):
            self.assertNotIn(forbidden, source)
        with self.assertRaises(SystemExit), patch("builtins.print"):
            remote_review.main("activate", self.plan)

    def test_isolated_catalog_owner_rejects_old_database_before_any_query(self):
        info = SimpleNamespace(host="127.0.0.1", port=15432, dbname="goufayu_ws4", user="goufayu_owner")
        connection = Mock(info=info)
        connection.execute.return_value.fetchone.return_value = ("goufayu_ws4", "goufayu_owner")
        self.assertTrue(catalog_validation.assert_isolated_connection(connection))
        for values in ({"port": 5432}, {"dbname": "goufayu_test"}, {"host": "localhost"}, {"user": "goufayu_payment"}):
            rejected = Mock(info=SimpleNamespace(**{**vars(info), **values}))
            with self.assertRaises(ValueError):
                catalog_validation.assert_isolated_connection(rejected)
            rejected.execute.assert_not_called()

    def test_catalog_compiler_requires_matching_ws4_bundle_and_preserves_disabled_entries(self):
        package, wallet = json.loads(self.files["catalog-package.json"]), json.loads(self.files["wallet-catalog.json"])
        reference = {name[len("reference_csv/"):]:raw.decode() for name,raw in self.files.items() if name.startswith("reference_csv/")}
        bundle = {"csv_hashes": self.plan["required_bundle_sources"]}
        digest = hashlib.sha256(catalog_validation.canonical(bundle)).hexdigest()
        report = catalog_validation.validate_catalog(package, wallet, reference, bundle, expected_bundle_hash=digest)
        self.assertEqual((report["cash_total"], report["wallet_total"]), (50, 129))
        with self.assertRaisesRegex(ValueError, "bundle_identity_changed"):
            catalog_validation.validate_catalog(package, wallet, reference, bundle, expected_bundle_hash="0" * 64)
        changed = copy.deepcopy(bundle)
        changed["csv_hashes"][next(iter(changed["csv_hashes"]))] = "0" * 64
        digest = hashlib.sha256(catalog_validation.canonical(changed)).hexdigest()
        with self.assertRaisesRegex(ValueError, "bundle_catalog_source_mismatch"):
            catalog_validation.validate_catalog(package, wallet, reference, changed, expected_bundle_hash=digest)

    def test_auxiliary_entitlement_authority_is_explicit_and_cannot_replace_bundle_authority(self):
        package, wallet = json.loads(self.files["catalog-package.json"]), json.loads(self.files["wallet-catalog.json"])
        reference = {name[len("reference_csv/"):]:raw.decode() for name,raw in self.files.items() if name.startswith("reference_csv/")}
        bundle = {"csv_hashes": copy.deepcopy(self.plan["required_bundle_sources"])}
        name = "商店系统/entitlement_definitions.csv"
        expected = bundle["csv_hashes"].pop("data/csv/" + name)
        digest = hashlib.sha256(catalog_validation.canonical(bundle)).hexdigest()
        with self.assertRaisesRegex(ValueError, "bundle_catalog_source_mismatch"):
            catalog_validation.validate_catalog(package, wallet, reference, bundle, expected_bundle_hash=digest)
        auxiliary = {name: expected}
        catalog_validation.validate_catalog(package, wallet, reference, bundle, expected_bundle_hash=digest, auxiliary_reference_hashes=auxiliary)
        with self.assertRaisesRegex(ValueError, "auxiliary_source_not_allowed"):
            catalog_validation.validate_catalog(package, wallet, reference, bundle, expected_bundle_hash=digest,
                                                auxiliary_reference_hashes={**auxiliary, "商城兑换系统/commerce_products.csv": "0" * 64})
        bundle["csv_hashes"]["data/csv/" + name] = "0" * 64
        digest = hashlib.sha256(catalog_validation.canonical(bundle)).hexdigest()
        with self.assertRaisesRegex(ValueError, "bundle_catalog_source_mismatch"):
            catalog_validation.validate_catalog(package, wallet, reference, bundle, expected_bundle_hash=digest, auxiliary_reference_hashes=auxiliary)

    def test_config_source_restore_is_fixed_read_only_and_default_does_not_fetch(self):
        with patch.object(restore_cloud_sources, "fetch") as fetch, patch("builtins.print"):
            restore_cloud_sources.main([])
        fetch.assert_not_called()
        source = restore_cloud_sources.remote_source()
        compile("try:\n" + "".join(" " + line + "\n" for line in source.splitlines()) + "except Exception:\n pass\n", "fixed_source_wrapper", "exec")
        for forbidden in ("glob(", "rglob(", "read_text(\"/etc", "psycopg", "systemctl", "write_bytes", "mkdir"):
            self.assertNotIn(forbidden, source)
        self.assertEqual(len(restore_cloud_sources.source_names()), 11)
        with self.assertRaisesRegex(ValueError, "fixed_cloud_source_snapshot_required"):
            deploy_plan.build(cloud_snapshot=deploy_plan.ROOT / "server")


if __name__ == "__main__":
    unittest.main()
