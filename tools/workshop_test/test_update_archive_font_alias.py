"""Only synthetic temporary aliases; no real svt_w24 or signing key access."""
from contextlib import contextmanager
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import update_archive_font_alias as scoped
import update_ui_qa_alias as historical
import test_update_ui_qa_alias as historical_tests


@contextmanager
def fixture(engine):
    # Reuse the reviewed temporary-data generator, never its installed alias.
    # The module reference is restored on every exit; production globals and
    # historical updater functions/constants are not reassigned.
    with patch.object(historical_tests, "updater", engine):
        with historical_tests.fixture() as data:
            yield data


class ArchiveFontAliasTest(unittest.TestCase):
    def test_unpinned_v07_fails_before_loading_engine_or_any_alias_io(self):
        with patch.object(scoped, "CANDIDATE_SHA", None), \
                patch.object(scoped, "load_engine", side_effect=AssertionError("alias touched")):
            for apply in (False, True):
                with self.assertRaisesRegex(RuntimeError, "candidate_not_pinned"):
                    scoped.run(apply=apply)

    def test_independent_engine_fixed_v06_receipt_and_three_resource_scope(self):
        before = {name: getattr(historical, name) for name in
                  ("builder", "ROOT", "TARGET", "CANDIDATE", "TRUSTED", "CANDIDATE_SHA", "OLD_RECEIPT_SHA", "ALLOWLIST")}
        original_receipt = historical.updated_receipt()
        engine = scoped.load_engine()
        another = scoped.load_engine()
        self.assertIsNot(engine, historical)
        self.assertIsNot(engine, another)
        self.assertIsNot(engine.run.__globals__, historical.run.__globals__)
        self.assertIs(engine.builder, scoped.builder)
        self.assertEqual(engine.ALLOWLIST, {"panorama/scripts/custom_game/common/archive_font_v36.vjs_c",
                                           "panorama/scripts/custom_game/daily_remaining_5d5c1152eb.vjs_c",
                                           "panorama/scripts/custom_game/commerce_wallet.vjs_c"})
        self.assertEqual(engine.builder.REVISION, "WS4-UI-FONT-WALLET-07")
        self.assertEqual(engine.OLD_RECEIPT_SHA, scoped.web.sha(original_receipt))
        self.assertEqual(scoped.builder.BASE_SHA, historical.CANDIDATE_SHA)
        self.assertEqual(scoped.builder.BASE_SEQUENCE, historical.builder.RELEASE_SEQUENCE)
        self.assertEqual(scoped.builder.RELEASE_SEQUENCE, 2026102502)
        self.assertEqual(engine.TARGET, scoped.ROOT.parent / "svt_w24")
        self.assertEqual(engine.STORE, historical.STORE)
        self.assertEqual({name: getattr(historical, name) for name in before}, before)
        self.assertEqual(historical.updated_receipt(), original_receipt)

    def test_changed_transaction_engine_source_is_rejected(self):
        with patch.object(scoped, "ENGINE_SHA", "0" * 64), \
                self.assertRaisesRegex(RuntimeError, "engine_changed"):
            scoped.load_engine()

    def test_prior_receipt_contract_is_pinned(self):
        with patch.object(scoped, "OLD_RECEIPT_SHA", "0" * 64), \
                self.assertRaisesRegex(RuntimeError, "prior_receipt_contract_changed"):
            scoped.load_engine()

    def test_default_plan_has_no_copy_replace_key_or_write(self):
        engine = scoped.load_engine()
        with fixture(engine) as data, patch.object(engine, "dota_pids", return_value=[42]), \
                patch.object(engine, "copy_verified", side_effect=AssertionError("copy")), \
                patch.object(engine, "atomic_replace", side_effect=AssertionError("replace")), \
                patch.object(engine, "write_verified", side_effect=AssertionError("write")), \
                patch.object(scoped, "CANDIDATE_SHA", "a" * 64), \
                patch.object(scoped, "load_engine", return_value=engine):
            result = scoped.run()
            self.assertTrue(result["dry_run"] and result["dota_running"])
            self.assertFalse(result["private_key_read"])
            self.assertEqual(result["changed_paths"], sorted(scoped.builder.ALLOWLIST))
            self.assertFalse(data.store.exists())

    def test_live_dota_rejects_apply_before_backup_creation(self):
        engine = scoped.load_engine()
        with fixture(engine) as data, patch.object(engine, "dota_pids", return_value=[42]), \
                self.assertRaisesRegex(RuntimeError, "dota_still_running"):
            engine.run(apply=True)
        self.assertFalse(data.store.exists())

    def test_success_changes_three_ui_resources_then_receipt_preserving_other_runtime(self):
        engine = scoped.load_engine()
        with fixture(engine) as data:
            original = engine.atomic_replace
            operations = []
            def replace(source, target, row, **options):
                operations.append(target.relative_to(data.target).as_posix())
                return original(source, target, row, **options)
            with patch.object(engine, "atomic_replace", side_effect=replace):
                result = engine.run(apply=True)
            self.assertEqual(operations, sorted(engine.ALLOWLIST) + [engine.RECEIPT])
            self.assertEqual(result["release_sequence"], 2026102502)
            self.assertTrue(result["full_after_verification"])
            self.assertEqual((data.target / engine.RECEIPT).read_bytes(), engine.updated_receipt())
            for name in data.files:
                self.assertEqual((data.target / name).read_bytes(), data.new_files[name])
                self.assertEqual((data.base / name).read_bytes(), data.files[name])
                self.assertEqual((data.candidate / name).read_bytes(), data.new_files[name])
            for name, raw in data.caches.items(): self.assertEqual((data.target / name).read_bytes(), raw)
            self.assertFalse((data.store / "active.lock").exists())

    def test_failure_after_each_ui_replace_restores_all_three_and_v06_receipt(self):
        for fail_at in (1, 2, 3):
            engine = scoped.load_engine()
            with self.subTest(replacement=fail_at), fixture(engine) as data:
                original, count = engine.atomic_replace, 0
                def fail_once(source, target, row, **options):
                    nonlocal count
                    result = original(source, target, row, **options)
                    if target.name != engine.RECEIPT and source.name.endswith("_new.tmp"):
                        count += 1
                        if count == fail_at: raise OSError("injected_after_ui_replace")
                    return result
                with patch.object(engine, "atomic_replace", side_effect=fail_once):
                    with self.assertRaises(engine.UpdateFailure) as caught: engine.run(apply=True)
                self.assertTrue(caught.exception.report["rollback"]["ok"])
                self.assertEqual((data.target / engine.RECEIPT).read_bytes(), data.receipt)
                engine.verify_runtime(data.target, data.old)

    def test_receipt_failure_and_post_receipt_verification_failure_restore_v06(self):
        for where in ("receipt", "final_verify"):
            engine = scoped.load_engine()
            with self.subTest(where=where), fixture(engine) as data:
                original, verify, new_count = engine.atomic_replace, engine.verify_runtime, 0
                def replace(source, target, row, **options):
                    if where == "receipt" and target.name == engine.RECEIPT and source.name.endswith("_new.tmp"):
                        raise OSError("injected_font_receipt_failure")
                    return original(source, target, row, **options)
                def check(target, doc):
                    nonlocal new_count
                    if doc == data.new:
                        new_count += 1
                        if where == "final_verify" and new_count == 2:
                            raise RuntimeError("injected_font_final_verification_failure")
                    return verify(target, doc)
                with patch.object(engine, "atomic_replace", side_effect=replace), \
                        patch.object(engine, "verify_runtime", side_effect=check):
                    with self.assertRaises(engine.UpdateFailure) as caught: engine.run(apply=True)
                self.assertTrue(caught.exception.report["rollback"]["ok"])
                self.assertEqual((data.target / engine.RECEIPT).read_bytes(), data.receipt)
                engine.verify_runtime(data.target, data.old)

    def test_dota_appears_after_staging_and_old_bytes_remain(self):
        engine = scoped.load_engine()
        with fixture(engine) as data:
            calls = 0
            def processes():
                nonlocal calls
                calls += 1
                return [42] if calls >= 2 else []
            with patch.object(engine, "dota_pids", side_effect=processes):
                with self.assertRaises(engine.UpdateFailure) as caught: engine.run(apply=True)
            self.assertTrue(caught.exception.report["rollback"]["ok"])
            engine.verify_runtime(data.target, data.old)
            self.assertEqual((data.target / engine.RECEIPT).read_bytes(), data.receipt)

    def test_replacement_cannot_touch_lua_auth_cash_or_atlas(self):
        engine = scoped.load_engine()
        with fixture(engine) as data:
            for name in (engine.builder.WEB_CONFIG, engine.builder.POLICY_MODULE,
                         "scripts/vscripts/systems/payment_service.lua", "materials/unreviewed_atlas.vtex_c"):
                target = data.target / name
                target.parent.mkdir(parents=True, exist_ok=True)
                if not target.exists(): target.write_bytes(b"unchanged")
                old = target.read_bytes()
                source = engine.sibling(target, "c" * 32, "new")
                source.write_bytes(b"unreviewed")
                with self.assertRaisesRegex(RuntimeError, "replace_scope_invalid"):
                    engine.atomic_replace(source, target, engine.row_bytes(b"unreviewed"))
                self.assertEqual(target.read_bytes(), old)

    def test_real_release_boundary_checks_v07_identity_sequence_signature_and_exact_diff(self):
        engine = scoped.load_engine()
        original = engine.releases
        with fixture(engine) as data, \
                patch.object(engine.builder, "authenticate_base", return_value=(data.base, data.old, data.context["old_signature"])), \
                patch.object(engine.builder, "protected_paths", return_value=data.protected), \
                patch.object(engine.pack, "authenticate", return_value=(data.candidate, data.new, data.context["signature"], {})) as auth:
            self.assertEqual(original()["new"], data.new)
            for field, value in (("content_sha256", "0" * 64), ("file_count", 1)):
                auth.return_value = data.candidate, dict(data.new, **{field: value}), data.context["signature"], {}
                with self.assertRaisesRegex(RuntimeError, "identity_mismatch"): original()
            for field, value in (("release_sequence", 2026102501), ("key_id", "wrong")):
                auth.return_value = data.candidate, data.new, dict(data.context["signature"], **{field: value}), {}
                with self.assertRaisesRegex(RuntimeError, "signature_identity_mismatch"): original()
            auth.side_effect = ValueError("invalid signature")
            with self.assertRaisesRegex(ValueError, "invalid signature"): original()

    def test_mismatched_installed_receipt_and_inventory_fail_before_writes(self):
        engine = scoped.load_engine()
        with fixture(engine) as data:
            receipt = data.target / engine.RECEIPT
            receipt.write_bytes(b"{}")
            with self.assertRaisesRegex(RuntimeError, "receipt_changed"): engine.run()
            receipt.write_bytes(data.receipt)
            (data.target / sorted(engine.ALLOWLIST)[0]).write_bytes(b"corrupt font")
            with self.assertRaisesRegex(RuntimeError, "full_runtime_verification_failed"): engine.run()
            self.assertFalse(data.store.exists())


if __name__ == "__main__":
    unittest.main()
