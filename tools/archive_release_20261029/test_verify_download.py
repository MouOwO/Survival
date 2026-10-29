"""Input rejection and read-only planning; no Steam, game or release writes."""
from contextlib import redirect_stdout
import copy
import hashlib
import importlib.util
import io
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import sys
sys.dont_write_bytecode = True

spec = importlib.util.spec_from_file_location("archive2901_verifier_test", Path(__file__).with_name("verify_download.py"))
subject = importlib.util.module_from_spec(spec)
spec.loader.exec_module(subject)


class DownloadContractTests(unittest.TestCase):
    def pins(self):
        result = {key: "a" * 64 for key in ("report_sha256", "content_sha256", "index_sha256",
            "protection_report_sha256", "production_manifest_sha256", "assembly_sha256", "reviewed_plan_sha256", "plan_sha256")}
        result.update(file_count=6695, selected_count=184, container_bytes=500,
            metadata_sha256={subject.api.pack.handoff.MANIFEST: "b" * 64, subject.api.pack.handoff.SIGNATURE: "c" * 64},
            review_sources={path: "d" * 64 for path in subject.TRUST_NAMES})
        return result

    def completed(self):
        pins = self.pins()
        manifest = {"file_count": pins["file_count"], "bytes": 1000}
        signature = {"content_sha256": pins["content_sha256"], "release_sequence": subject.SEQUENCE}
        report = dict(status="BUILT_AND_VERIFIED_FOR_NATIVE_TEST_ONLY", content_sha256=pins["content_sha256"],
            release_sequence=subject.SEQUENCE, files=pins["file_count"], protected_modules_rebuilt=pins["selected_count"],
            protected_modules_preserved=0, full_source_plan_sha256=pins["plan_sha256"], signature_valid=True,
            dry_run=False, payload_changed=False, workshop_upload_performed=False, full_input_hash_verification=True,
            full_runtime_validator_passed=True, candidate=str(subject.CANDIDATE), trusted_source=str(subject.TRUSTED),
            output=str(subject.VPK), package_files=[dict(name=name, bytes=100, sha256=pins["index_sha256"])
                for name in subject.protocol.EXPECTED_NAMES], vpk_sha256=pins["index_sha256"],
            verification={**{key: True for key in subject.callbacks.CHECKS}, "files": pins["file_count"], "archive_count": 4},
            container_bytes=pins["container_bytes"], payload_bytes=manifest["bytes"])
        return pins, report, manifest, signature

    def test_frozen_protocol_is_unchanged_and_target_is_new_release(self):
        self.assertEqual(hashlib.sha256(subject.PROTOCOL_FILE.read_bytes().replace(b"\r\n", b"\n")).hexdigest(), subject.PROTOCOL_LF_SHA)
        self.assertEqual((subject.ITEM, subject.SEQUENCE), ("3824360109", 2026102901))
        self.assertEqual(subject.CANDIDATE.name, "20261029_ws4_archive_all_v01_view")
        self.assertEqual(len(subject.protocol.EXPECTED_NAMES), 5)
        self.assertFalse(hasattr(subject, "EXPECTED_STEAM_MANIFEST"))

    def test_pending_pins_refuse_before_release_reads_or_steam(self):
        with patch.object(subject, "PINS", None), patch.object(subject, "pinned_snapshot", side_effect=AssertionError("release read forbidden")), \
                self.assertRaisesRegex(subject.callbacks.Refused, "not_yet_finalized"):
            subject.local_inputs()

    def test_missing_or_malformed_identity_pins_are_rejected(self):
        valid = self.pins()
        with patch.object(subject, "PINS", valid):
            subject.require_package_pins()
        mutations = [("file_count", True), ("selected_count", 0), ("selected_count", 6696),
                     ("report_sha256", ""), ("metadata_sha256", {}), ("review_sources", {})]
        for key, value in mutations:
            with self.subTest(key=key, value=value), patch.object(subject, "PINS", {**valid, key: value}), \
                    self.assertRaisesRegex(subject.callbacks.Refused, "pins_invalid"):
                subject.require_package_pins()

    def test_current_report_accepts_dynamic_count_and_rejects_historical_180(self):
        pins, report, manifest, signature = self.completed()
        with patch.object(subject, "PINS", pins):
            self.assertEqual(subject.verify_completed_report(report, manifest, signature), 500)
            for key, value in [("protected_modules_rebuilt", 180), ("protected_modules_preserved", 180),
                ("files", 6658), ("files", True), ("content_sha256", "0" * 64), ("full_source_plan_sha256", "0" * 64),
                ("output", "D:/unreviewed.vpk"), ("signature_valid", False), ("dry_run", True),
                ("full_runtime_validator_passed", False)]:
                with self.subTest(key=key), self.assertRaises(subject.callbacks.Refused):
                    subject.verify_completed_report({**report, key: value}, manifest, signature)
            for change in [{"archive_count": 3}, {"files": 6658}, {subject.callbacks.CHECKS[0]: False}]:
                with self.subTest(change=change), self.assertRaises(subject.callbacks.Refused):
                    subject.verify_completed_report({**report, "verification": {**report["verification"], **change}}, manifest, signature)
            bad = {**report, "package_files": list(reversed(report["package_files"]))}
            with self.assertRaises(subject.callbacks.Refused):
                subject.verify_completed_report(bad, manifest, signature)

    def test_selection_comes_from_current_policy_and_exact_pinned_count(self):
        pins = self.pins()
        pins["selected_count"] = 3
        selected = [{"path": "module" + str(i), "kind": "generated_table"} for i in range(3)]
        with patch.object(subject, "PINS", pins), patch.object(subject.protocol.protect_runtime_lua, "check_policy"), \
                patch.object(subject.api.pack.runtime, "CRITICAL", {"critical"}), \
                patch.object(subject.protocol.protect_runtime_lua, "selected_files", return_value=selected) as choose:
            manifest = {"files": [{"path": "critical"}]}
            self.assertEqual(subject.protected_inventory(manifest, {}), selected)
            choose.assert_called_once_with(["critical"], {})
            choose.return_value = [selected[0]] * 3
            with self.assertRaisesRegex(subject.callbacks.Refused, "inventory_mismatch"):
                subject.protected_inventory(manifest, {})
            choose.return_value = selected
            with self.assertRaisesRegex(subject.callbacks.Refused, "missing_critical"):
                subject.protected_inventory({"files": []}, {})

    def test_protection_source_and_signed_output_bindings_reject_missing_transformation(self):
        pins = self.pins(); pins["selected_count"] = 1
        before = dict(bytes=10, md5="b" * 32, sha256="b" * 64)
        after = dict(bytes=20, md5="c" * 32, sha256="c" * 64)
        selected = [{"path": "module.lua", "kind": "generated_table"}]
        source = {"files": [{"path": "module.lua", **before}]}
        manifest = {"files": [{"path": "module.lua", **after}]}
        evidence = dict(status="PASS_REQUIRES_NATIVE_SMOKE", syntax={"status": "PASS"}, selected_files=1,
            semantic_verification=dict(status="PASS", all_generated_values_exact=True,
                gameplay_rng_untouched_while_loading=True, new_runtime_io_os_debug_dependency=False, summary={"files": 1}),
            files=[{**selected[0], "before": before, "after": after}])
        assembly = dict(status="READY_FOR_NATIVE_SMOKE_ONLY", full_file_verification=True, runtime_files=pins["file_count"],
                        protected_lua_files=1, content_sha256=pins["content_sha256"], release_sequence=subject.SEQUENCE)
        plan = dict(plan_sha256=pins["plan_sha256"], release_sequence=subject.SEQUENCE,
                    runtime_files=pins["file_count"], protected_modules_rebuild=1, protected_modules_preserve=0)
        def check(changed=None):
            with patch.object(subject, "PINS", pins), patch.object(subject, "pinned_snapshot", side_effect=[source, changed or evidence, assembly, plan]), \
                    patch.object(subject.api.pack.handoff, "decode_json", side_effect=lambda value: value), \
                    patch.object(subject.api.pack.runtime, "validate_manifest"):
                subject.verify_protection_evidence(manifest, selected, {})
        check()
        forged = copy.deepcopy(evidence); forged["files"][0]["after"] = before
        with self.assertRaisesRegex(subject.callbacks.Refused, "source_or_signed_bytes"):
            check(forged)
        forged = copy.deepcopy(evidence); forged["files"].append(forged["files"][0])
        with self.assertRaisesRegex(subject.callbacks.Refused, "inventory_mismatch"):
            check(forged)

    def test_default_plan_does_not_initialize_steam_lock_or_write(self):
        inputs = dict(total=1000, snapshots={}, success=False, expected_manifest=None)
        with patch.object(subject, "local_inputs", return_value=inputs), \
                patch.object(subject.protocol.shutil, "disk_usage", return_value=SimpleNamespace(free=2 ** 40)), \
                patch.object(subject.api.Steam, "__enter__", side_effect=AssertionError("Steam forbidden")), \
                patch.object(subject.api, "publication_lock", side_effect=AssertionError("lock forbidden")), \
                patch.object(subject.callbacks, "write_exclusive", side_effect=AssertionError("write forbidden")), \
                redirect_stdout(io.StringIO()) as output:
            self.assertEqual(subject.main([]), 0)
        self.assertIn('"steam_initialized": false', output.getvalue())
        self.assertIn('"files_written": 0', output.getvalue())

    def test_download_summary_reports_actual_selected_count(self):
        with patch.object(subject, "_official_download_once", return_value={"protected_modules_verified": 180}) as original:
            self.assertEqual(subject.download_once({"protected_modules": 184})["protected_modules_verified"], 184)
        original.assert_called_once_with({"protected_modules": 184})

    def test_old_manifest_history_is_never_a_success_pin(self):
        self.assertIsNone(subject.protocol.journal_manifest({"previous_release": {"steam_manifest": "123"}}))
        for value in [123, True, "0", "01", str(2 ** 64)]:
            with self.subTest(value=value), self.assertRaises(subject.callbacks.Refused):
                subject.protocol.journal_manifest({"steam_manifest": value})


if __name__ == "__main__":
    unittest.main()
