"""Small selection/safety contracts; no native tool, Steam or real package IO."""
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import native_package_reads_v08 as native


def rows():
    result = [dict(path="textures/archive_%d.vtex_c" % i, archive=i) for i in range(4)]
    result.extend(dict(path=name, archive=0) for name in (native.TEAL, *native.CHANGED_JS))
    return result


class NativeReadSafetyTest(unittest.TestCase):
    def test_pending_or_wrong_archive_pins_fail_before_report_or_external_io(self):
        for members in (None, [], [dict(name="unexpected.vpk", bytes=1, sha256="0" * 64)]):
            with self.subTest(members=members), patch.object(native, "MEMBERS", members), \
                    patch.object(native.Path, "mkdir", side_effect=AssertionError("report IO")), \
                    self.assertRaisesRegex(ValueError, "pins_not_finalized"):
                native.run("package")

    def test_only_two_fixed_targets_and_v08_pins(self):
        self.assertEqual(set(native.TARGETS), {"package", "download"})
        self.assertIn("20261025_ws4_ui_stackable_v08", str(native.TARGETS["package"]))
        self.assertEqual(native.SEQUENCE, 2026102503)
        self.assertEqual(native.CONTENT_SHA, "88611d026e49c52b5bce7324818f36a11a60059a2844b8f646b884ba15debaa9")

    def test_selects_four_archive_textures_teal_and_all_three_changed_js(self):
        selected = native.select_rows(rows())
        self.assertEqual(len(selected), 8)
        self.assertEqual([r["archive"] for r in selected[:4]], [0, 1, 2, 3])
        self.assertEqual([r["path"] for r in selected[4:]], [native.TEAL, *native.CHANGED_JS])

    def test_missing_js_or_archive_texture_is_fail_closed(self):
        for path in (native.CHANGED_JS[0], native.TEAL, "textures/archive_3.vtex_c"):
            with self.subTest(path=path), self.assertRaisesRegex(ValueError, "required_resource|four_archives|texture_missing"):
                native.select_rows([r for r in rows() if r["path"] != path])

    def test_duplicate_and_unexpected_archive_are_rejected(self):
        for data in (rows() + [rows()[0]], rows() + [dict(path="textures/unreviewed.vtex_c", archive=4)]):
            with self.assertRaisesRegex(ValueError, "duplicate_resource|four_archives"):
                native.select_rows(data)

    def test_teal_cannot_satisfy_the_independent_archive_texture_sample(self):
        data = [r for r in rows() if r["path"] != "textures/archive_0.vtex_c"]
        with self.assertRaisesRegex(ValueError, "texture_missing"):
            native.select_rows(data)

    def test_success_needs_native_header_exact_resource_and_zero_exit(self):
        path = native.CHANGED_JS[0]
        raw = ("Info for resource file " + path.replace("/", "\\")).encode()
        self.assertTrue(native.parse_native_result(raw, 0, path)["ok"])
        self.assertFalse(native.parse_native_result(raw, 1, path)["ok"])
        self.assertFalse(native.parse_native_result(path.encode(), 0, path)["ok"])
        self.assertFalse(native.parse_native_result(b"Info for resource file other.vjs_c", 0, path)["ok"])

    def test_failed_16_bytes_is_rejected_even_with_zero_exit_and_header(self):
        path = native.TEAL
        raw = ("Info for resource file " + path + "\nFATAL ERROR: Failed to read 16 bytes").encode()
        result = native.parse_native_result(raw, 0, path)
        self.assertFalse(result["ok"])
        self.assertTrue(result["failed_to_read_16_bytes"])

    def test_unknown_target_fails_before_report_or_external_file_io(self):
        with patch.object(native.Path, "mkdir", side_effect=AssertionError("report IO")), \
                self.assertRaisesRegex(ValueError, "target_not_allowed"):
            native.run("unreviewed")

    def test_each_failed_attempt_writes_a_new_report_without_overwrite(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(native, "REPORT_ROOT", Path(folder)), \
                patch.object(native, "require_package_pins"), \
                patch.object(native, "MEMBERS", [{"sha256": "0" * 64}]), \
                patch.object(native.pack.handoff, "regular_path", side_effect=ValueError("fixture not installed")), \
                patch.object(native.subprocess, "run", side_effect=AssertionError("native launch")):
            first, first_path = native.run("download")
            before = first_path.read_bytes()
            second, second_path = native.run("download")
            self.assertFalse(first["ok"] or second["ok"])
            self.assertNotEqual(first_path, second_path)
            self.assertEqual(first_path.read_bytes(), before)


if __name__ == "__main__":
    unittest.main()
