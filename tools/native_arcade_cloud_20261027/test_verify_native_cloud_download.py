"""Offline native-cloud adapter and unchanged real callback ABI contracts."""
from __future__ import annotations

from contextlib import redirect_stdout
import copy
import hashlib
import importlib.util
import io
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


tool = load("native_cloud_official_download_under_test", HERE / "verify_native_cloud_download.py")
legacy = load("native_cloud_original_protocol_tests", HERE.parent / "arcade_cleanup_20261027/test_verify_download.py")


class NativeCloudProtocolContracts(legacy.SafetyTests):
    """Run all existing callback/freshness/ACF tests against our private instance."""
    def setUp(self):
        context = patch.object(legacy, "subject", tool.protocol)
        context.start()
        self.addCleanup(context.stop)

    def test_fixed_new_release_has_no_historical_manifest_pin(self):
        p = tool.protocol
        self.assertEqual((p.ITEM, p.SEQUENCE, p.FILE_COUNT), ("3824360109", 2026102708, 6658))
        self.assertEqual(p.CONTENT, "55d9e63ea1c95bed2456c739c0cf0e3148030e91a43f3a0d72aeaf64ab540e26")
        self.assertEqual(p.CANDIDATE.name, "20261027_ws4_native_cloud_v02_view")
        self.assertEqual(p.TRUSTED.name, "20261027_ws4_native_cloud_v02_overlay_trusted_source")
        self.assertEqual(p.VPK.parent.name, "20261027_ws4_native_cloud_v02")
        self.assertEqual(p.REPORT.name, "native_cloud_v02_package.json")
        self.assertEqual(p.OUTPUT.name, "download_evidence_v02")
        self.assertEqual(p.MINIMUM_REMOTE_UPDATED, 1793069949)
        self.assertFalse(hasattr(p, "EXPECTED_STEAM_MANIFEST"))


class NativeCloudAdditionalGuards(unittest.TestCase):
    def package_inputs(self):
        return dict(report=dict(status="BUILT_AND_VERIFIED_NATIVE_CLOUD_REQUIRES_NATIVE_TEST",
            vpk_sha256="a" * 64, full_view_canonical_guard="PASS", canonical_single_map=True,
            canonical_reviewed_gate=True, immutable_base_unchanged=True,
            native_cloud_roster_required=True,
            protected_modules_preserved=180, protected_modules_rebuilt=0),
            report_sha256="b" * 64, total=1000, snapshots={}, manifest={"files": []})

    def package_pins(self):
        contexts = [patch.object(tool, name, value) for name, value in
                    (("REPORT_SHA", "b" * 64), ("INDEX_SHA", "a" * 64), ("TOTAL_BYTES", 1000))]
        for context in contexts:
            context.start(); self.addCleanup(context.stop)

    def test_pending_pins_refuse_before_release_reads_lock_or_sdk(self):
        with patch.object(tool, "REPORT_SHA", None), \
                patch.object(tool, "_verified_local_inputs", side_effect=AssertionError("release reads forbidden")), \
                patch.object(tool.api.Steam, "__enter__", side_effect=AssertionError("SDK forbidden")), \
                patch.object(tool.api, "publication_lock", side_effect=AssertionError("lock forbidden")), \
                redirect_stdout(io.StringIO()) as output:
            self.assertEqual(tool.main([]), 1)
            self.assertEqual(tool.main(["--download"]), 1)
        self.assertEqual(output.getvalue().count("native_cloud_completed_package_pins_not_yet_finalized"), 2)

    def test_completed_real_package_hash_size_and_canonical_results_are_mandatory(self):
        self.package_pins()
        tool.require_package_pins()
        original = self.package_inputs()
        tool.verify_completed_report(original)
        for key, value in (("status", "VERIFIED_NATIVE_CLOUD_PACKAGE_PLAN"), ("full_view_canonical_guard", "NOT_RUN"),
                           ("canonical_single_map", False), ("canonical_reviewed_gate", False),
                           ("immutable_base_unchanged", False), ("protected_modules_preserved", 179),
                           ("native_cloud_roster_required",False),
                           ("protected_modules_rebuilt", 1), ("vpk_sha256", "c" * 64)):
            d = copy.deepcopy(original); d["report"][key] = value
            with self.subTest(key=key), self.assertRaises(tool.callbacks.Refused): tool.verify_completed_report(d)
        for key, value in (("report_sha256", "c" * 64), ("total", 999)):
            d = copy.deepcopy(original); d[key] = value
            with self.subTest(key=key), self.assertRaises(tool.callbacks.Refused): tool.verify_completed_report(d)

    def test_full_locked_verification_forwards_to_frozen_canonical_protocol(self):
        self.package_pins()
        values = self.package_inputs()
        with patch.object(tool, "_verified_local_inputs", return_value=values) as base, \
                patch.object(tool, "verify_review_sources") as reviews:
            self.assertIs(tool.local_inputs(True, full=True), values)
        base.assert_called_once_with(True, full=True)
        reviews.assert_called_once_with(values)

    def test_exact_fourteen_review_sources_bind_both_native_modules_and_reject_foreign_files(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            values = self.package_inputs()
            for relative in tool.TRUST_NAMES:
                raw = ("reviewed fixture " + relative).encode()
                path = root / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(raw)
                if relative.startswith("scripts/"):
                    values["manifest"]["files"].append(dict(path=relative, sha256=hashlib.sha256(raw).hexdigest()))
            with patch.object(tool, "TRUSTED", root):
                tool.verify_review_sources(values)
                self.assertEqual(len(values["snapshots"]), 17)  # 14 trusted + publisher/protocol/profile parser.
                target = root / "scripts/vscripts/systems/native_cloud_roster.lua"
                raw = target.read_bytes(); target.write_bytes(raw + b"tampered")
                with self.assertRaisesRegex(tool.callbacks.Refused, "review_source_differs"): tool.verify_review_sources(values)
                target.write_bytes(raw)
                (root / "foreign.txt").write_bytes(b"not reviewed")
                with self.assertRaisesRegex(tool.callbacks.Refused, "inventory_changed"): tool.verify_review_sources(values)

    def test_frozen_original_protocol_file_is_unchanged(self):
        self.assertEqual(hashlib.sha256(tool.PROTOCOL_FILE.read_bytes().replace(b"\r\n", b"\n")).hexdigest(),
                         tool.PROTOCOL_LF_SHA)
        self.assertIsNot(legacy.subject, tool.protocol)
        self.assertEqual((legacy.subject.SEQUENCE, legacy.subject.FILE_COUNT), (2026102705, 6655))
        self.assertEqual(legacy.subject.REPORT.name, "native_package_build_v02.json")


if __name__ == "__main__":
    unittest.main()
