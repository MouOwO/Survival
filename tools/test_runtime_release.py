"""Behavior checks for the runtime allowlist and isolated staging boundary."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
import shutil
import subprocess
import sys
import copy
import hashlib
import json
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("runtime_release", Path(__file__).with_name("build_runtime_release.py"))
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class RuntimeReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "source"
        self.root.mkdir()
        self.write("addoninfo.txt", b'"AddonInfo" { "maps" "template_map" }')
        self.write(release.RELEASE_PROFILE, b'return { channel = "production", }\n')

    def write(self, relative, data=b"runtime"):
        target = self.root / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)

    def test_runtime_families_and_font_licenses_remain_development_is_excluded(self):
        wanted = {"panorama/videos/custom_game/sequence.webm", "panorama/fonts/source-han-sans-LICENSE.txt",
                  "panorama/images/custom_game/dynamically_named/item_png.vtex_c", "models/runtime.vmdl_c",
                  "scripts/vscripts/systems/dynamic_provider.lua", "resource/custom_game_whitelist.txt",
                  "scripts/vscripts/tools/runtime_helper.lua",
                  "maps/template_map.vpk", "maps/portraits/doom_soft_a.vpk", "maps/loose_entity.vmdl_c"}
        unwanted = {"panorama/src/scripts/test.js", "art/large.psd", "server/private.env", "output/secret.lua",
                    "scripts/vscripts/tests/test_runtime.lua", "scripts/vscripts/__pycache__/compiled.pyc",
                    "panorama/fonts/font_manifest.json", "maps/old_concept_review.vpk"}
        for path in wanted | unwanted:
            self.write(path)
        files, _ = release.select(self.root, check_critical=False)
        self.assertTrue(wanted <= set(files))
        self.assertFalse(unwanted & set(files))

    def test_missing_required_runtime_is_an_error(self):
        with self.assertRaisesRegex(ValueError, "Missing required"):
            release.manifest(self.root)

    def test_entry_inventory_retains_only_its_fixed_internal_gameplay_map(self):
        self.write("addoninfo.txt", b'"AddonInfo" { "maps" "ws4_entry" }')
        for path in ("maps/ws4_entry.vpk", "maps/template_map.vpk", "maps/unrelated_review.vpk"):
            self.write(path)
        files, _ = release.select(self.root, check_critical=False)
        self.assertIn("maps/ws4_entry.vpk", files)
        self.assertIn("maps/template_map.vpk", files)
        self.assertNotIn("maps/unrelated_review.vpk", files)
        self.write("addoninfo.txt", b'"AddonInfo" { "maps" "another_entry" }')
        self.assertNotIn("maps/template_map.vpk", release.map_files(self.root))

    def test_retired_lottery_compiled_fixture_is_retained_but_not_shipped(self):
        fixture = "panorama/styles/custom_game/lottery_fullscreen_v2.vcss_c"
        active = "panorama/styles/custom_game/lottery_gw2.vcss_c"
        self.write(fixture, b"offline regression base")
        self.write(active, b"active style")
        files, excluded = release.select(self.root, check_critical=False)
        self.assertNotIn(fixture, files)
        self.assertIn(active, files)
        self.assertIn({"path": fixture, "reason": "retired UI regression fixture"}, excluded)
        self.assertEqual((self.root / fixture).read_bytes(), b"offline regression base")

    def test_unknown_compiled_extension_requires_review(self):
        self.write("models/new_type.vfuture_c")
        with self.assertRaisesRegex(ValueError, "Unreviewed compiled"):
            release.select(self.root, check_critical=False)

    def test_explicit_new_external_stage_matches_manifest_without_source_edits(self):
        self.write("panorama/images/live_png.vtex_c", b"native bytes")
        data = release.manifest(self.root, check_critical=False)
        destination = Path(self.temp.name) / "candidate"
        release.stage(self.root, destination, data)
        for row in data["files"]:
            self.assertEqual(release.digest(destination / row["path"]), row["sha256"])
            self.assertEqual(release.digest(self.root / row["path"]), row["sha256"])
        self.assertTrue((destination / "_release_manifest.json").is_file())
        with self.assertRaisesRegex(ValueError, "already exists"):
            release.stage(self.root, destination, data)

    def test_stage_rejects_source_descendant_and_source_changes(self):
        data = release.manifest(self.root, check_critical=False)
        with self.assertRaisesRegex(ValueError, "outside"):
            release.stage(self.root, self.root / "candidate", data)
        with self.assertRaisesRegex(ValueError, "absolute"):
            release.stage(self.root, Path("relative_candidate"), data)
        self.write("addoninfo.txt", b"changed")
        destination = Path(self.temp.name) / "never_created"
        with self.assertRaisesRegex(ValueError, "Source changed"):
            release.stage(self.root, destination, data)
        self.assertFalse(destination.exists())

    def test_manifest_cannot_stage_outside_relative_paths(self):
        data = release.manifest(self.root, check_critical=False)
        data["files"][0]["path"] = "../escape"
        destination = Path(self.temp.name) / "never_created"
        with self.assertRaisesRegex(ValueError, "Unsafe manifest"):
            release.stage(self.root, destination, data)
        self.assertFalse(destination.exists())

    def reseal(self, data):
        data["content_sha256"] = hashlib.sha256(release.manifest_payload(data)).hexdigest()

    def test_dual_hashes_and_aggregate_cover_exact_file_bytes(self):
        self.write("panorama/images/live_png.vtex_c", b"native bytes\x00\xff")
        data = release.manifest(self.root, check_critical=False)
        self.assertEqual(data["schema"], 2)
        self.assertEqual(data["hash_algorithms"], ["md5", "sha256"])
        for row in data["files"]:
            raw = (self.root / row["path"]).read_bytes()
            self.assertEqual(row["md5"], hashlib.md5(raw).hexdigest())
            self.assertEqual(row["sha256"], hashlib.sha256(raw).hexdigest())
        release.validate_manifest(data)
        local = copy.deepcopy(data)
        local["source_root"] = "another workstation"
        self.assertEqual(release.manifest_payload(data), release.manifest_payload(local))
        data["files"][0]["sha256"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "content ID"):
            release.validate_manifest(data)

    def test_diff_lists_added_changed_removed_and_supports_legacy_baseline(self):
        self.write("scripts/vscripts/removed.lua", b"old")
        self.write("scripts/vscripts/changed.lua", b"same length1")
        before = release.manifest(self.root, check_critical=False)
        (self.root / "scripts/vscripts/removed.lua").unlink()
        self.write("scripts/vscripts/changed.lua", b"same length2")
        self.write("scripts/vscripts/added.lua", b"new")
        after = release.manifest(self.root, check_critical=False)
        difference = release.compare_manifests(before, after)
        self.assertEqual(difference["added"], ["scripts/vscripts/added.lua"])
        self.assertEqual(difference["removed"], ["scripts/vscripts/removed.lua"])
        self.assertEqual(difference["modified"][0]["path"], "scripts/vscripts/changed.lua")
        self.assertEqual(difference["modified"][0]["changed"], ["md5", "sha256"])
        self.assertFalse(difference["updates_applied"])
        legacy = copy.deepcopy(before)
        legacy["schema"] = 1
        for row in legacy["files"]:
            del row["md5"]
        self.assertEqual(release.compare_manifests(legacy, after)["modified"][0]["changed"], ["sha256"])
        with self.assertRaisesRegex(ValueError, "md5|Legacy"):
            release.verify(self.root, legacy, check_critical=False)

    def test_verify_fails_for_missing_same_length_edit_and_unexpected_runtime(self):
        self.write("scripts/vscripts/missing.lua", b"old")
        self.write("scripts/vscripts/changed.lua", b"same length1")
        data = release.manifest(self.root, check_critical=False)
        self.assertTrue(release.verify(self.root, data, check_critical=False)["ok"])
        (self.root / "scripts/vscripts/missing.lua").unlink()
        self.write("scripts/vscripts/changed.lua", b"same length2")
        self.write("scripts/vscripts/unexpected.lua", b"new")
        result = release.verify(self.root, data, check_critical=False)
        self.assertFalse(result["ok"])
        self.assertEqual(result["missing"], ["scripts/vscripts/missing.lua"])
        self.assertEqual(result["modified"][0]["path"], "scripts/vscripts/changed.lua")
        self.assertEqual(result["unexpected_runtime"], ["scripts/vscripts/unexpected.lua"])
        self.assertFalse(result["files_changed"])
        self.assertFalse(result["authenticity_verified"])

    def test_each_hash_is_checked_even_if_manifest_aggregate_is_resealed(self):
        original = release.manifest(self.root, check_critical=False)
        for field, width in (("md5", 32), ("sha256", 64)):
            data = copy.deepcopy(original)
            data["files"][0][field] = "0" * width
            self.reseal(data)
            result = release.verify(self.root, data, check_critical=False)
            self.assertFalse(result["ok"])
            self.assertEqual(result["modified"][0]["changed"], [field])

    def test_duplicate_windows_alias_and_unsafe_paths_are_rejected(self):
        original = release.manifest(self.root, check_critical=False)
        for unsafe in ("../escape.lua", "C:/escape.lua", "/escape.lua", "scripts\\escape.lua",
                       "scripts//escape.lua", "scripts/./escape.lua"):
            data = copy.deepcopy(original)
            data["files"][0]["path"] = unsafe
            with self.subTest(unsafe=unsafe), self.assertRaisesRegex(ValueError, "Unsafe"):
                release.validate_manifest(data)
        data = copy.deepcopy(original)
        duplicate = copy.deepcopy(data["files"][0])
        duplicate["path"] = duplicate["path"].upper()
        data["files"].append(duplicate)
        with self.assertRaisesRegex(ValueError, "Duplicate"):
            release.validate_manifest(data)

    def test_stage_rejects_extra_runtime_before_creating_destination(self):
        data = release.manifest(self.root, check_critical=False)
        self.write("scripts/vscripts/injected.lua", b"not in release")
        destination = Path(self.temp.name) / "not_created"
        with self.assertRaisesRegex(ValueError, "Source changed"):
            release.stage(self.root, destination, data)
        self.assertFalse(destination.exists())

    def test_atomic_report_failure_preserves_previous_output(self):
        target = Path(self.temp.name) / "report.json"
        target.write_text("old report", encoding="utf-8")
        with patch.object(release.os, "replace", side_effect=OSError("simulated replace failure")):
            with self.assertRaises(OSError):
                release.atomic_write_json(target, {"new": True})
        self.assertEqual(target.read_text(encoding="utf-8"), "old report")
        self.assertEqual(list(target.parent.glob(".report.json.*.tmp")), [])

    def test_cli_build_compare_verify_and_failed_verification_report(self):
        for relative in (release.CRITICAL | release.map_files(self.root)) - {"addoninfo.txt", release.RELEASE_PROFILE}:
            self.write(relative)
        base = Path(self.temp.name)
        baseline, candidate, differences, report = [base / name for name in
                                                   ("before.json", "after.json", "diff.json", "verify.json")]
        command = [sys.executable, "-B", str(Path(release.__file__)), "--root", str(self.root)]
        initial = subprocess.run(command + ["--manifest", str(baseline)], capture_output=True, text=True)
        self.assertEqual(initial.returncode, 0, initial.stderr)
        self.write("scripts/vscripts/added.lua", b"new runtime")
        changed = subprocess.run(command + ["--manifest", str(candidate), "--baseline", str(baseline),
                                            "--diff", str(differences)], capture_output=True, text=True)
        self.assertEqual(changed.returncode, 0, changed.stderr)
        self.assertEqual(json.loads(differences.read_text())["added"], ["scripts/vscripts/added.lua"])
        checked = subprocess.run(command + ["--verify", str(candidate), "--report", str(report)],
                                 capture_output=True, text=True)
        self.assertEqual(checked.returncode, 0, checked.stderr)
        self.assertTrue(json.loads(report.read_text())["ok"])
        self.write("scripts/vscripts/added.lua", b"tampered")
        failed = subprocess.run(command + ["--verify", str(candidate), "--report", str(report)],
                                capture_output=True, text=True)
        self.assertEqual(failed.returncode, 1, failed.stderr)
        self.assertFalse(json.loads(report.read_text())["ok"])
        self.assertEqual(json.loads(report.read_text())["modified"][0]["path"], "scripts/vscripts/added.lua")

    def test_cli_cannot_overwrite_runtime_file_or_input_manifest(self):
        command = [sys.executable, "-B", str(Path(release.__file__)), "--root", str(self.root)]
        original = (self.root / "addoninfo.txt").read_bytes()
        result = subprocess.run(command + ["--manifest", str(self.root / "addoninfo.txt")],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertEqual((self.root / "addoninfo.txt").read_bytes(), original)
        target = Path(self.temp.name) / "manifest.json"
        target.write_text("do not overwrite", encoding="utf-8")
        result = subprocess.run(command + ["--verify", str(target), "--report", str(target)],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(target.read_text(encoding="utf-8"), "do not overwrite")

    def test_release_profile_is_explicit_literal_production_and_never_executed(self):
        accepted = (b'-- human comment mentions development\nreturn {channel="production",}',
                    b"return -- channel\n{ channel = 'production' }; -- done\n")
        for source in accepted:
            self.write(release.RELEASE_PROFILE, source)
            release.require_production(self.root)
        rejected = (b'return { channel="development" } -- production',
                    b'-- return { channel="production" }',
                    b'return { channel="production", channel="development" }',
                    b'return { channel="production" }; os.execute("unexpected")',
                    b'--[[\nreturn { channel="production" }\n--]]',
                    b'return { channel=("production") }', b'return {}')
        for source in rejected:
            self.write(release.RELEASE_PROFILE, source)
            with self.subTest(source=source), self.assertRaisesRegex(ValueError, "profile"):
                release.manifest(self.root, check_critical=False)
        (self.root / release.RELEASE_PROFILE).unlink()
        with self.assertRaisesRegex(ValueError, "profile"):
            release.manifest(self.root, check_critical=False)

    def test_verify_and_stage_reject_development_even_with_matching_file_hashes(self):
        data = release.manifest(self.root, check_critical=False)
        self.write(release.RELEASE_PROFILE, b'return { channel="development" }')
        for row in data["files"]:
            if row["path"] == release.RELEASE_PROFILE:
                row.update(release.checksums(self.root / release.RELEASE_PROFILE))
        data["bytes"] = sum(row["bytes"] for row in data["files"])
        self.reseal(data)
        result = release.verify(self.root, data, check_critical=False)
        self.assertFalse(result["ok"])
        self.assertEqual(result["modified"], [])
        self.assertEqual(result["errors"][0]["path"], release.RELEASE_PROFILE)
        destination = Path(self.temp.name) / "development_not_staged"
        with self.assertRaisesRegex(ValueError, "verification"):
            release.stage(self.root, destination, data)
        self.assertFalse(destination.exists())

    def test_symlink_escape_is_rejected(self):
        outside = Path(self.temp.name) / "outside.lua"
        outside.write_bytes(b"not source")
        link = self.root / "scripts/vscripts/linked.lua"
        link.parent.mkdir(parents=True, exist_ok=True)
        try:
            link.symlink_to(outside)
        except OSError:
            self.skipTest("Creating symlinks needs a Windows permission")
        with self.assertRaisesRegex(ValueError, "link"):
            release.select(self.root, check_critical=False)


class RetiredWorkflowTests(unittest.TestCase):
    def test_historical_entrypoints_fail_before_reading_or_rebuilding_art(self):
        folder = release.ROOT / "art/ui/development/remaining_ui_handoff_v1"
        commands = [[sys.executable, "-B", str(folder / "audit_alpha.py")]]
        node = shutil.which("node")
        if node:
            commands += [[node, str(folder / name)] for name in ("prepare.cjs", "verify.cjs")]
        for command in commands:
            with self.subTest(entry=command[-1]):
                result = subprocess.run(command, capture_output=True, text=True, encoding="utf-8")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("RETIRED_UI_WORKFLOW", result.stdout + result.stderr)
                self.assertNotIn("ENOENT", result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
