"""Offline rejection fixtures: no real candidate, private key, game or service."""
from contextlib import ExitStack
from copy import deepcopy
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_multiplayer_candidate as candidate
from test_web_auth_candidate import manifest

OLD_INFO = (b'"AddonInfo"\r\n{\r\n    "maps"              "ws4_entry"\r\n'
            b'    "IsPlayable" "1"\r\n    "EnablePickRules" "0"\r\n'
            b'    "ws4_entry" { "MaxPlayers" "1" }\r\n'
            b'    "template_map" { "MaxPlayers" "4" }\r\n}\r\n')
INFO = OLD_INFO.replace(b'"maps"              "ws4_entry"', b'"maps"              "template_map"')
FROZEN = b"-- frozen entry prefix and body\r\nlocal M = {}\r\nfunction Activate() end\r\n\r\nreturn M\r\n"
WRAPPER = candidate.BEGIN + b"do local old = Activate; Activate = function() return old() end end\r\n" + candidate.END
PROBE = b"-- WS4-MP-09 public diagnostic fixture\r\nreturn { activate = function() end }\r\n"


def staged(files, patches):
    return {name: raw for name, raw in dict(files, **patches).items() if name not in candidate.REMOVED}


class MultiplayerCandidateTest(unittest.TestCase):
    def pins(self):
        stack = ExitStack()
        for name, raw in (("ADDONINFO_SHA", INFO), ("WRAPPER_SHA", WRAPPER), ("PROBE_SHA", PROBE)):
            stack.enter_context(patch.object(candidate, name, candidate.web.sha(raw)))
        return stack

    def fixture(self):
        policy = candidate.pack.handoff.load_json(candidate.ROOT / "tools/lua_protection_policy.json")
        protected = list(policy["business_modules"]) + [
            policy["generated_prefix"] + "fixture_%03d.lua" % i for i in range(176)]
        files = {name: ("protected:" + name).encode() for name in protected}
        for name in (*candidate.trust_names(), candidate.WEB_CONFIG, candidate.ENTRY_MAP,
                     "maps/template_map.vpk", "scripts/vscripts/config/release_profile.lua",
                     "scripts/vscripts/core/commerce_release_policy.lua",
                     "scripts/vscripts/systems/payment_service.lua"):
            if name not in candidate.web.POLICY_FILES:
                files[name] = ("frozen:" + name).encode()
        files[candidate.MAIN], files[candidate.ADDONINFO] = FROZEN, OLD_INFO
        for i in range(candidate.BASE_FILES - len(files)):
            files["materials/fixture_%04d.vmat_c" % i] = b"frozen runtime"
        with self.pins():
            patches = {candidate.MAIN: candidate.insert_wrapper(FROZEN, WRAPPER),
                       candidate.ADDONINFO: INFO, candidate.PROBE: PROBE}
        return protected, files, patches

    def source_fixture(self, folder):
        root, base = (folder / name for name in ("game", "base"))
        values = {candidate.MAIN: FROZEN[:-len(candidate.TAIL)] + WRAPPER + candidate.TAIL,
                  candidate.ADDONINFO: INFO, candidate.PROBE: PROBE}
        for name, raw in values.items():
            path = root / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(raw)
        for name, raw in ((candidate.MAIN, FROZEN), (candidate.ADDONINFO, OLD_INFO)):
            path = base / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(raw)
        return root, base, values

    def test_fixed_identity_exact_scope_and_readonly_default(self):
        args = candidate.parser().parse_args([])
        self.assertFalse(args.build)
        self.assertIsNone(args.signing_key)
        self.assertEqual(args.sequence, 2026102504)
        self.assertEqual(candidate.BASE_SEQUENCE, 2026102503)
        self.assertEqual(candidate.BASE_FILES, 6630)
        self.assertEqual(candidate.BASE_SHA, "88611d026e49c52b5bce7324818f36a11a60059a2844b8f646b884ba15debaa9")
        self.assertEqual(candidate.ALLOWLIST, {"addoninfo.txt", "scripts/vscripts/addon_game_mode.lua",
                                             "scripts/vscripts/systems/workshop_network_probe.lua"})
        self.assertEqual(candidate.REMOVED, {"maps/ws4_entry.vpk"})

    def test_missing_review_pins_fail_before_baseline_or_key_access(self):
        with patch.object(candidate, "PROBE_SHA", None), \
                patch.object(candidate, "authenticate_base", side_effect=AssertionError("baseline IO")), \
                patch.object(candidate.web, "output_paths", side_effect=AssertionError("key IO")):
            with self.assertRaisesRegex(ValueError, "not finalized"):
                candidate.build(candidate.parser().parse_args([]))

    def test_wrong_sequence_or_outputs_fail_before_baseline_io(self):
        with self.pins(), patch.object(candidate, "authenticate_base", side_effect=AssertionError("baseline IO")):
            for seq in (2026102503, 2026102505):
                with self.assertRaisesRegex(ValueError, "fixed 2026102504"):
                    candidate.build(candidate.parser().parse_args(["--sequence", str(seq)]))
            for destination in (str(candidate.BASE), str(candidate.ROOT / "output/unreviewed"), "relative"):
                with self.assertRaisesRegex(ValueError, "fixed new candidate/trusted"):
                    candidate.build(candidate.parser().parse_args([
                        "--build", "--destination", destination,
                        "--trusted-source", str(candidate.TRUSTED_DESTINATION)]))
            with self.assertRaisesRegex(ValueError, "fixed external directory"):
                candidate.build(candidate.parser().parse_args([
                    "--build", "--destination", str(candidate.DESTINATION),
                    "--trusted-source", str(candidate.TRUSTED_DESTINATION),
                    "--package-output", str(candidate.BASE)]))

    def test_default_plan_never_reads_key_or_writes_outputs_or_runs_compiler(self):
        protected, files, patches = self.fixture()
        with self.pins(), \
                patch.object(candidate, "authenticate_base", return_value=(Path("unused"), manifest(files),
                             {"release_sequence": candidate.BASE_SEQUENCE}, {})), \
                patch.object(candidate, "protected_paths", return_value=protected), \
                patch.object(candidate, "capture_inputs", return_value=({}, patches)), \
                patch.object(candidate, "trust_inputs", return_value={}), \
                patch.object(candidate.web, "git", return_value=b"reviewed\n"), \
                patch.object(candidate.web, "output_paths", side_effect=AssertionError("key/output IO")), \
                patch.object(candidate.pack.protect_data, "sign_manifest", side_effect=AssertionError("sign")), \
                patch.object(candidate.pack.runtime, "atomic_write_json", side_effect=AssertionError("write")), \
                patch.object(candidate.web.protect_runtime_lua, "syntax_check", side_effect=AssertionError("compile")), \
                patch.object(candidate.pack, "package", side_effect=AssertionError("network/package")):
            result = candidate.build(candidate.parser().parse_args(["--signing-key", "must-not-read.pem"]))
        self.assertEqual(result["status"], "READ_ONLY_PLAN")
        self.assertEqual(result["expected_files"], 6630)
        self.assertEqual(result["allowed_removals"], [candidate.ENTRY_MAP])
        self.assertTrue(result["original_entry_map_preserved"])
        self.assertFalse(result["game_started"] or result["workshop_upload_performed"]
                         or result["online_authentication_changed"] or result["real_money_payments"])

    def test_capture_only_adds_reviewed_wrapper_to_frozen_main(self):
        with tempfile.TemporaryDirectory() as folder, self.pins():
            root, base, values = self.source_fixture(Path(folder).resolve())
            # Unrelated development gameplay edits are never substituted.
            development = values[candidate.MAIN].replace(b"-- frozen entry prefix and body", b"-- unrelated dev edits")
            (root / candidate.MAIN).write_bytes(development)
            with patch.object(candidate, "ROOT", root):
                snapshots, patches = candidate.capture_inputs(base)
            self.assertEqual(patches[candidate.MAIN], candidate.insert_wrapper(FROZEN, WRAPPER))
            self.assertEqual(snapshots[root / candidate.MAIN], development)
            self.assertEqual(set(patches), candidate.ALLOWLIST)

    def test_source_or_probe_pin_layout_and_frozen_addoninfo_drift_rejected(self):
        with tempfile.TemporaryDirectory() as folder, self.pins():
            root, base, values = self.source_fixture(Path(folder).resolve())
            with patch.object(candidate, "ROOT", root):
                for name in (candidate.ADDONINFO, candidate.PROBE):
                    path = root / name; original = path.read_bytes(); path.write_bytes(original + b"-- changed\r\n")
                    with self.assertRaises(ValueError): candidate.capture_inputs(base)
                    path.write_bytes(original)
                old = base / candidate.ADDONINFO; old.write_bytes(OLD_INFO + b"// unreviewed metadata\r\n")
                with self.assertRaisesRegex(ValueError, "Only the frozen addoninfo"):
                    candidate.capture_inputs(base)
                old.write_bytes(OLD_INFO)
                invalid = INFO.replace(b'"template_map" { "MaxPlayers" "4" }', b'"template_map" { "MaxPlayers" "8" }')
                (root / candidate.ADDONINFO).write_bytes(invalid)
                with patch.object(candidate, "ADDONINFO_SHA", candidate.web.sha(invalid)), \
                        self.assertRaisesRegex(ValueError, "expose only template_map 4"):
                    candidate.capture_inputs(base)

    def test_wrapper_requires_unique_markers_exact_terminal_tail_and_pin(self):
        with self.pins():
            valid = candidate.insert_wrapper(FROZEN, WRAPPER)
            self.assertEqual(candidate.wrapper_bytes(valid), WRAPPER)
            for invalid in (valid + b"-- after return\r\n", valid.replace(WRAPPER, WRAPPER + WRAPPER),
                            valid.replace(b"return old()", b"return true"), valid.replace(b"\r\n", b"\n")):
                with self.assertRaises(ValueError): candidate.wrapper_bytes(invalid)
            for frozen in (FROZEN[:-2], FROZEN + b"-- after return\r\n", valid,
                           FROZEN.replace(b"\r\n", b"\n"), b"return M\r\n"):
                with self.assertRaises(ValueError): candidate.insert_wrapper(frozen, WRAPPER)

    def test_exact_three_patches_one_omission_preserve_6630_count_and_protected_180(self):
        protected, files, patches = self.fixture()
        with self.pins():
            changes = candidate.audit_changes(manifest(files), manifest(staged(files, patches)), patches, protected)
        self.assertEqual({row["path"] for row in changes}, candidate.ALLOWLIST | candidate.REMOVED)
        self.assertEqual(sum(row["before"] is None for row in changes), 1)
        self.assertEqual(sum(row["after"] is None for row in changes), 1)
        self.assertIn(candidate.ENTRY_MAP, files, "The old candidate fixture stays intact")

    def test_auth_cash_access_maps_and_protected_bytes_cannot_change(self):
        protected, files, patches = self.fixture()
        paths = [candidate.WEB_CONFIG, candidate.POLICY_MODULE, candidate.pack.handoff.ACCESS_FILE,
                 "maps/template_map.vpk", "scripts/vscripts/config/release_profile.lua",
                 "scripts/vscripts/core/commerce_release_policy.lua",
                 "scripts/vscripts/systems/payment_service.lua", "materials/fixture_0000.vmat_c"]
        with self.pins():
            for name in paths:
                with self.subTest(name=name), self.assertRaisesRegex(ValueError, "Only addoninfo"):
                    candidate.audit_changes(manifest(files), manifest(dict(staged(files, patches), **{name: b"tamper"})),
                                            patches, protected)

    def test_only_entry_map_may_be_omitted_no_other_addition_or_no_change_is_accepted(self):
        protected, files, patches = self.fixture()
        final = staged(files, patches)
        with self.pins():
            for invalid in ({name: raw for name, raw in final.items() if name != "maps/template_map.vpk"},
                            dict(final, **{candidate.ENTRY_MAP: files[candidate.ENTRY_MAP]}),
                            dict(final, **{"scripts/vscripts/debug/backdoor.lua": b"unexpected"}), files):
                with self.assertRaises(ValueError):
                    candidate.audit_changes(manifest(files), manifest(invalid), patches, protected)
            with patch.object(candidate, "BASE_FILES", 6629), self.assertRaisesRegex(ValueError, "6630"):
                candidate.audit_changes(manifest(files), manifest(final), patches, protected)

    def test_whole_main_body_must_restore_after_removing_only_insertion(self):
        protected, files, patches = self.fixture()
        tampered = dict(patches)
        tampered[candidate.MAIN] = tampered[candidate.MAIN].replace(b"function Activate() end", b"function Activate() error('bad') end")
        with self.pins(), self.assertRaisesRegex(ValueError, "entire frozen main body"):
            candidate.audit_changes(manifest(files), manifest(staged(files, tampered)), tampered, protected)

    def test_manifest_paths_duplicate_count_staging_and_inventory_are_checked(self):
        protected, files, patches = self.fixture(); before, after = manifest(files), manifest(staged(files, patches))
        with self.pins():
            invalid = dict(staged(files, patches), **{"../outside.lua": b"escape"})
            with self.assertRaisesRegex(ValueError, "Unsafe manifest path"):
                candidate.audit_changes(before, manifest(invalid), patches, protected)
            duplicate = deepcopy(after); duplicate["files"].append(duplicate["files"][0])
            with self.assertRaisesRegex(ValueError, "Duplicate manifest path"):
                candidate.audit_changes(before, duplicate, patches, protected)
            with self.assertRaisesRegex(ValueError, "allowlist"):
                candidate.audit_changes(before, after, dict(patches, other=b"no"), protected)
            with self.assertRaisesRegex(ValueError, "staging"):
                candidate.audit_changes(before, after, dict(patches, **{candidate.PROBE: b"changed"}), protected)
            for invalid in (protected[:-1], protected[:-1] + [protected[0]],
                            protected[:-1] + ["materials/fixture_0000.vmat_c"]):
                with self.assertRaisesRegex(ValueError, "180-module"):
                    candidate.audit_changes(before, after, patches, invalid)

    def test_policy_pin_and_inventory_selection_cannot_be_bypassed(self):
        _, files, _ = self.fixture()
        with patch.object(candidate, "LUA_POLICY_SHA", "0" * 64), self.assertRaisesRegex(ValueError, "policy changed"):
            candidate.protected_paths(manifest(files))

    def test_normal_map_policy_accepts_direct_map_without_legacy_vpk(self):
        original = candidate.pack.runtime.SCENE_MAPS
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder).resolve(); (root / candidate.ADDONINFO).write_bytes(INFO)
            path = root / "maps/template_map.vpk"; path.parent.mkdir(); path.write_bytes(b"map fixture")
            candidate.pack.handoff.require_single_map(root)
            maps = candidate.pack.runtime.map_files(root)
            self.assertIn("maps/template_map.vpk", maps)
            self.assertNotIn(candidate.ENTRY_MAP, maps)
            self.assertFalse((root / candidate.ENTRY_MAP).exists())
        self.assertIs(candidate.pack.runtime.SCENE_MAPS, original)

    def test_real_staging_omits_only_legacy_map_preserves_source_and_passes_normal_runtime_verification(self):
        with tempfile.TemporaryDirectory() as folder, self.pins():
            folder = Path(folder).resolve(); base, target = folder / "base", folder / "candidate"
            files = {candidate.ADDONINFO: OLD_INFO, candidate.MAIN: FROZEN,
                     candidate.ENTRY_MAP: b"old entry map", "maps/template_map.vpk": b"gameplay map",
                     "scripts/vscripts/config/release_profile.lua": b'return { channel = "production" }\r\n'}
            patches = {candidate.ADDONINFO: INFO, candidate.MAIN: candidate.insert_wrapper(FROZEN, WRAPPER),
                       candidate.PROBE: PROBE}
            for name, raw in files.items():
                path = base / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(raw)
            candidate.stage_runtime(base, target, manifest(files), patches)
            self.assertEqual({p.relative_to(target).as_posix() for p in target.rglob("*") if p.is_file()},
                             set(staged(files, patches)))
            self.assertEqual((base / candidate.ENTRY_MAP).read_bytes(), files[candidate.ENTRY_MAP])
            self.assertEqual((base / candidate.MAIN).read_bytes(), FROZEN)
            self.assertEqual((base / candidate.ADDONINFO).read_bytes(), OLD_INFO)
            candidate.pack.handoff.require_single_map(target)
            doc = candidate.pack.runtime.manifest(target, check_critical=False)
            self.assertEqual(doc["file_count"], len(files))
            self.assertTrue(candidate.pack.runtime.verify(target, doc, check_critical=False)["ok"])
            with self.assertRaises(FileExistsError): candidate.stage_runtime(base, target, manifest(files), patches)

    def test_baseline_signed_identity_sequence_key_floor_and_production_required(self):
        with tempfile.TemporaryDirectory() as folder:
            base = Path(folder).resolve(); path = base / candidate.WEB_CONFIG
            path.parent.mkdir(parents=True); path.write_bytes(b"return { enabled = true }\r\n")
            doc = dict(content_sha256=candidate.BASE_SHA, file_count=candidate.BASE_FILES)
            sig = dict(release_sequence=candidate.BASE_SEQUENCE, key_id="fixture-public-key")
            policy = dict(integrity=dict(trusted_key_id="fixture-public-key", minimum_release_sequence=2026102503))
            with patch.object(candidate.pack.handoff, "trusted_policy", return_value=(policy, {})), \
                    patch.object(candidate.pack, "authenticate", return_value=(base, doc, sig, {})) as auth, \
                    patch.object(candidate.pack.handoff, "configured_ids", return_value=["fixture"]), \
                    patch.object(candidate.pack.runtime, "require_production") as production:
                self.assertEqual(candidate.authenticate_base()[0], base)
                for bad_doc, bad_sig in ((dict(doc, content_sha256="0" * 64), sig),
                                         (dict(doc, file_count=6629), sig),
                                         (doc, dict(sig, release_sequence=2026102502)),
                                         (doc, dict(sig, key_id="other"))):
                    auth.return_value = base, bad_doc, bad_sig, {}
                    with self.assertRaises(ValueError): candidate.authenticate_base()
                auth.return_value = base, doc, sig, {}
                policy["integrity"]["minimum_release_sequence"] = 2026102505
                with self.assertRaisesRegex(ValueError, "floor"): candidate.authenticate_base()
                policy["integrity"]["minimum_release_sequence"] = 2026102503
                production.side_effect = ValueError("production required")
                with self.assertRaisesRegex(ValueError, "production required"): candidate.authenticate_base()
                production.side_effect = None; path.write_bytes(b"return { enabled = false }\r\n")
                with self.assertRaisesRegex(ValueError, "stay enabled"): candidate.authenticate_base()

    def test_trust_snapshot_changes_only_main_and_preserves_exact_inventory(self):
        with tempfile.TemporaryDirectory() as folder:
            folder = Path(folder).resolve(); old, new, trusted = (folder / name for name in ("old", "new", "trust"))
            for name in candidate.trust_names():
                path = old / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(name.encode())
            main = new / candidate.MAIN; main.parent.mkdir(parents=True); main.write_bytes(b"reviewed frozen insertion")
            with patch.object(candidate, "BASE_TRUSTED", old): candidate.trusted_snapshot(new, trusted)
            actual = {p.relative_to(trusted).as_posix() for p in trusted.rglob("*") if p.is_file()}
            self.assertEqual(actual, set(candidate.trust_names()))
            for name in actual:
                self.assertEqual((trusted / name).read_bytes(), main.read_bytes() if name == candidate.MAIN else name.encode())

    def test_reviewed_input_and_head_drift_or_disappearance_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder).resolve() / "input.lua"; path.write_bytes(b"reviewed")
            with patch.object(candidate.web, "git", return_value=b"head\n"):
                candidate.require_review_unchanged({path: b"reviewed"}, "head")
                with self.assertRaisesRegex(ValueError, "input changed"):
                    candidate.require_review_unchanged({path: b"changed"}, "head")
                with self.assertRaisesRegex(ValueError, "HEAD changed"):
                    candidate.require_review_unchanged({path: b"reviewed"}, "other")
                path.unlink()
                with self.assertRaises(ValueError): candidate.require_review_unchanged({path: b"reviewed"}, "head")

    def test_old_candidate_disappearance_metadata_or_runtime_drift_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            base = Path(folder).resolve() / "gone"
            with self.assertRaisesRegex(ValueError, "does not exist"):
                candidate.require_base_unchanged(base, {}, {})
            base.mkdir()
            with patch.object(candidate.pack, "inventory_unchanged", side_effect=ValueError("signed metadata changed")):
                with self.assertRaisesRegex(ValueError, "metadata changed"):
                    candidate.require_base_unchanged(base, {}, {})
            with patch.object(candidate.pack, "inventory_unchanged"), \
                    patch.object(candidate.pack.runtime, "verify", return_value={"ok": False}), \
                    self.assertRaisesRegex(ValueError, "disappeared or changed"):
                candidate.require_base_unchanged(base, {}, {})

    def test_linked_source_or_ancestor_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder, self.pins():
            root, base, _ = self.source_fixture(Path(folder).resolve())
            original = candidate.pack.protect_data.linked
            with patch.object(candidate, "ROOT", root), \
                    patch.object(candidate.pack.protect_data, "linked", side_effect=lambda p:
                                 p in {root / candidate.PROBE, root / "scripts"} or original(p)), \
                    self.assertRaisesRegex(ValueError, "linked|Linked"):
                candidate.capture_inputs(base)


if __name__ == "__main__":
    unittest.main()
