"""Behavior checks for the runtime allowlist and isolated staging boundary."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
import shutil
import subprocess
import sys

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
        data = {"files": [{"path": "../escape", "sha256": "unused"}]}
        destination = Path(self.temp.name) / "never_created"
        with self.assertRaisesRegex(ValueError, "Unsafe manifest"):
            release.stage(self.root, destination, data)
        self.assertFalse(destination.exists())

    def test_symlink_escape_is_rejected(self):
        outside = Path(self.temp.name) / "outside.lua"
        outside.write_bytes(b"not source")
        link = self.root / "scripts/vscripts/linked.lua"
        link.parent.mkdir(parents=True)
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
