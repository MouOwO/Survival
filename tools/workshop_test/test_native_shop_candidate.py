"""SHOP02 replacement isolation tests; no signing, installation or uploads."""
from contextlib import ExitStack
from copy import deepcopy
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_native_shop_candidate as candidate
from test_web_auth_candidate import manifest


class NativeShopCandidateTests(unittest.TestCase):
    def fixture(self):
        policy = candidate.pack.handoff.load_json(candidate.ROOT / "tools/lua_protection_policy.json")
        protected = list(policy["business_modules"]) + [
            policy["generated_prefix"] + "fixture_%03d.lua" % i for i in range(176)]
        files = {name: ("protected:" + name).encode() for name in protected}
        files.update({name: ("frozen:" + name).encode() for name in candidate.MODIFIED})
        files.update({
            "maps/template_map.vpk": b"unchanged map",
            "scripts/vscripts/config/release_profile.lua": b"production",
            "scripts/vscripts/config/session_multiplayer_test.lua": b"four accounts, session only",
            "scripts/vscripts/config/player_web_auth.lua": b"disabled",
            "panorama/layout/custom_game/custom_ui_manifest.vxml_c": b"unchanged UI manifest",
            candidate.CATALOG_PIN[1]: b"unchanged 173-offer catalog"})
        files.update({"materials/fixture_%04d.vmat_c" % i: b"unchanged art"
                      for i in range(candidate.BASE_FILES - len(files))})
        patches = {name: ("reviewed:" + name).encode() for name in candidate.ALLOWLIST}
        pins = {"scripts/custom_game/source_%d.js" % i:
                ("a" * 64, name, candidate.web.sha(raw), len(raw))
                for i, (name, raw) in enumerate(sorted(patches.items()))}
        return files, patches, protected, pins

    def test_fixed_scope_no_additions_and_safe_default(self):
        args = candidate.parser().parse_args([])
        self.assertFalse(args.build)
        self.assertIsNone(args.signing_key)
        self.assertEqual((candidate.REVISION, args.sequence), ("WS4-SHOP-02", 2026102604))
        self.assertEqual((candidate.BASE_FILES, candidate.BASE_SEQUENCE, candidate.EXPECTED_FILES),
                         (6637, 2026102603, 6637))
        self.assertEqual(candidate.BASE_SHA, "cf15590f4c0a93977a70a2357c3c94f5685040a1dbeea44d1cd4e6b00503b109")
        self.assertEqual(len(candidate.ALLOWLIST), 6)
        self.assertFalse(candidate.ADDED)
        self.assertNotIn(candidate.CATALOG_PIN[1], candidate.ALLOWLIST)
        candidate.require_review_pins()

    def test_wrong_sequence_missing_key_and_foreign_outputs_fail_before_input_io(self):
        for arguments in (["--sequence", "2026102603"], ["--build"],
                          ["--build", "--destination", str(candidate.BASE),
                           "--trusted-source", str(candidate.BASE_TRUSTED), "--signing-key", "not-read"],
                          ["--build", "--destination", str(candidate.DESTINATION),
                           "--trusted-source", str(candidate.TRUSTED_DESTINATION)],
                          ["--build", "--destination", str(candidate.DESTINATION),
                           "--trusted-source", str(candidate.TRUSTED_DESTINATION),
                           "--signing-key", "not-read", "--package-output", "foreign-output"]):
            with self.subTest(arguments=arguments), patch.object(candidate, "authenticate_base",
                    side_effect=AssertionError("baseline was read")), self.assertRaises(ValueError):
                candidate.build(candidate.parser().parse_args(arguments))

    def test_projection_preserves_all_other_files_and_every_protected_module(self):
        files, patches, protected, pins = self.fixture()
        before = manifest(files)
        with patch.object(candidate, "PINS", pins):
            projected = candidate.projected_manifest(before, patches)
            changes = candidate.audit_changes(before, projected, patches, protected)
        self.assertEqual({row["path"] for row in changes}, candidate.MODIFIED)
        original = {row["path"]: row for row in before["files"]}
        after = {row["path"]: row for row in projected["files"]}
        self.assertEqual(original.keys(), after.keys())
        self.assertTrue(all(original[name] == after[name] for name in original if name not in candidate.MODIFIED))
        self.assertEqual(len(candidate.protected_paths(before)), 180)

    def test_lua_map_config_catalog_foreign_additions_and_removals_rejected(self):
        files, patches, protected, pins = self.fixture()
        for name in (protected[0], "maps/template_map.vpk",
                     "scripts/vscripts/config/release_profile.lua",
                     "scripts/vscripts/config/session_multiplayer_test.lua",
                     "scripts/vscripts/config/player_web_auth.lua", candidate.CATALOG_PIN[1]):
            changed = dict(files, **patches)
            changed[name] = b"unreviewed change"
            with self.subTest(name=name), patch.object(candidate, "PINS", pins), self.assertRaises(ValueError):
                candidate.audit_changes(manifest(files), manifest(changed), patches, protected)
        for action in (lambda f: f.update({"scripts/vscripts/foreign.lua": b"foreign"}),
                       lambda f: f.pop("maps/template_map.vpk"),
                       lambda f: f.pop(next(iter(candidate.MODIFIED)))):
            changed = dict(files, **patches)
            action(changed)
            with self.subTest(action=action), patch.object(candidate, "PINS", pins), self.assertRaises(ValueError):
                candidate.audit_changes(manifest(files), manifest(changed), patches, protected)

    def test_missing_overlay_and_stale_hash_pin_rejected(self):
        files, patches, protected, pins = self.fixture()
        missing = dict(patches)
        missing.pop(next(iter(missing)))
        with self.assertRaisesRegex(ValueError, "overlay scope"):
            candidate.projected_manifest(manifest(files), missing)
        broken = deepcopy(pins)
        name = next(iter(broken))
        broken[name] = (broken[name][0], broken[name][1], "f" * 64, broken[name][3])
        with patch.object(candidate, "PINS", broken), self.assertRaisesRegex(ValueError, "patch bytes"):
            candidate.audit_changes(manifest(files), manifest(dict(files, **patches)), patches, protected)

    def test_readonly_plan_never_resolves_key_or_writes_even_when_key_argument_supplied(self):
        files, patches, protected, pins = self.fixture()
        before = manifest(files)
        with ExitStack() as stack:
            stack.enter_context(patch.object(candidate, "PINS", pins))
            stack.enter_context(patch.object(candidate, "authenticate_base", return_value=(
                Path("frozen"), before, {"key_id": "public-key-id"}, {})))
            stack.enter_context(patch.object(candidate, "protected_paths", return_value=protected))
            stack.enter_context(patch.object(candidate, "capture_inputs", return_value=({}, patches)))
            stack.enter_context(patch.object(candidate, "trust_inputs", return_value={}))
            stack.enter_context(patch.object(candidate, "require_review_unchanged"))
            stack.enter_context(patch.object(candidate.web, "git", return_value=b"reviewed-head\n"))
            stack.enter_context(patch.object(candidate.web, "output_paths", side_effect=AssertionError("key resolved")))
            stack.enter_context(patch.object(candidate, "stage_runtime", side_effect=AssertionError("runtime written")))
            stack.enter_context(patch.object(candidate.pack.protect_data, "sign_manifest", side_effect=AssertionError("key read")))
            stack.enter_context(patch.object(candidate.pack, "package", side_effect=AssertionError("packaged")))
            stack.enter_context(patch.object(Path, "mkdir", side_effect=AssertionError("directory written")))
            stack.enter_context(patch.object(Path, "write_bytes", side_effect=AssertionError("file written")))
            result = candidate.build(candidate.parser().parse_args([
                "--signing-key", "NEVER-READ.pem", "--package-output", "NEVER-CREATE"]))
        self.assertEqual(result["status"], "READ_ONLY_PLAN")
        self.assertFalse(result["real_money_payments"])
        self.assertFalse(result["game_started"])
        self.assertFalse(result["workshop_upload_performed"])
        self.assertEqual(result["allowed_additions"], [])
        self.assertEqual(result["allowed_removals"], [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
