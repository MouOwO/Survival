"""Targeted full-release gate checks, without building/uploading a release."""
from pathlib import Path
import hashlib
import importlib.util
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("archive_full_builder", Path(__file__).with_name("build_workshop.py"))
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)


class FullReleaseGates(unittest.TestCase):
    def test_exact_native_entry_patch_retains_all_ordinary_gameplay(self):
        current = (tool.ROOT / tool.MAIN).read_bytes()
        result = tool.main_source(current).decode("utf8")
        original = current.decode("utf-8-sig").replace("\r\n", "\n")
        marker = "-- Keep the Workshop entry independent of gameplay and cloud initialization.\n"
        self.assertEqual(result, original[original.index(marker):])
        block = ('if type(GetMapName) == "function" and GetMapName() == "ws4_entry" then\n'
                 '    local entry = require("systems/native_cloud_handoff")\n')
        self.assertTrue(result.startswith(marker + block))
        self.assertNotIn('require("systems/onboarding_service")', result)
        self.assertIn('victory_settled == true', result)
        with self.assertRaises(ValueError):
            tool.main_source(b'print("unreviewed prefix")\n' + current)

    def test_exact_review_inventory_and_coordinated_bundle_required(self):
        tool.require_review_inventory(tool.REVIEW_NAMES)
        for names in (tool.REVIEW_NAMES[:-1], (*tool.REVIEW_NAMES, "unreviewed.lua")):
            with self.assertRaises(ValueError): tool.require_review_inventory(names)
        tool.require_archive_bundle((tool.ROOT / tool.ARCHIVE_BUNDLE_PATH).read_bytes())
        for raw in (b'return { hash = "' + b'0' * 64 + b'" }', b'return {}'):
            with self.assertRaises(ValueError): tool.require_archive_bundle(raw)

    def test_real_production_config_rejects_development_or_disabled_auth(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory)
            names = (*tool.SOURCE_OVERRIDES, "scripts/vscripts/config/session_multiplayer_test.lua", tool.ARCHIVE_BUNDLE_PATH,
                     tool.pack.handoff.ACCESS_FILE)
            for name in names:
                if name.startswith("maps/"): continue
                original = tool.ROOT / name if name == tool.ARCHIVE_BUNDLE_PATH else tool.BASE / name
                target = source / name; target.parent.mkdir(parents=True, exist_ok=True); shutil.copyfile(original, target)
            tool.require_production_source(source)
            profile = source / tool.runtime.RELEASE_PROFILE
            saved = profile.read_bytes()
            profile.write_bytes(b'return { channel = "development" }\n')
            with self.assertRaises(ValueError): tool.require_production_source(source)
            profile.write_bytes(saved)
            auth = source / "scripts/vscripts/config/player_web_auth.lua"
            auth.write_bytes(auth.read_bytes().replace(b'enabled = true', b'enabled = false'))
            with self.assertRaises(ValueError): tool.require_production_source(source)

    def test_real_deterministic_protection_matches_native_multiplayer_pin(self):
        raw = (tool.ROOT / tool.MULTIPLAYER).read_bytes()
        self.assertEqual(hashlib.sha256(raw).hexdigest(), "7bb7fe314dc4f4d7e35ecf52c221037c4deb8900b246cf6de1c5ff94f8ab94de")
        policy = tool.load(tool.ROOT / tool.LUA_POLICY)
        tool.protection.dependency_identity(tool.PROMETHEUS, policy)
        selected = tool.protection.selected_files(tool.runtime.select(tool.ROOT)[0], policy)
        self.assertEqual(len(selected), 184)
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "multiplayer.lua"
            seed = int(hashlib.sha256((tool.MULTIPLAYER + hashlib.sha256(raw).hexdigest()).encode("ascii")).hexdigest()[:8], 16) % 2147483646 + 1
            subprocess.run([str(tool.LUA), str(tool.ROOT / "tools/lua_protection/prometheus_offline_driver.lua"),
                            str(tool.PROMETHEUS), str(tool.ROOT / tool.MULTIPLAYER), str(target), str(seed), "generated_table_strings"],
                           check=True, capture_output=True)
            self.assertEqual(hashlib.sha256(target.read_bytes()).hexdigest(), tool.pack.handoff.NATIVE_CLOUD_ENTRY_PINS[tool.MULTIPLAYER])
            subprocess.run([str(tool.LUAC), "-p", str(target)], check=True, capture_output=True)


if __name__ == "__main__": unittest.main()
