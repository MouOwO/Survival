"""Offline candidate boundaries; never signs, publishes, starts Dota or reads keys."""
from contextlib import ExitStack
from copy import deepcopy
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_arcade_two_player_candidate as candidate
from test_web_auth_candidate import manifest

MAIN = b"-- original LF entry prefix\nlocal M = {}\r\nfunction Activate() end\r\n" + candidate.MAIN_INIT + b"\r\nreturn M\r\n"
PROFILE = b"-- frozen profile\r\n" + b"\r\n".join(before for before, _ in candidate.PROFILE_PATCHES)
INFO = (b'"AddonInfo" { "maps"              "ws4_entry" "IsPlayable" "1" "EnablePickRules" "0" '
        b'"ws4_entry" { "MaxPlayers" "1" } "template_map" { "MaxPlayers" "4" } }\r\n')
NETTABLES = b'{\r\r\n        "survival_commerce_actions",\r\r\n}\r\r\n'
OLD_MANIFEST = b'<root>\n  <Panel hittest="false">\n  </Panel>\n</root>\n'


def resource(data=b"fixture"):
    return struct.pack("<IHHII4sII", 28 + len(data), 12, 1, 8, 1, b"DATA", 8, len(data)) + data


class ArcadeCandidateTest(unittest.TestCase):
    def read_from(self, files):
        def read(path, snapshots):
            raw = files[path]
            snapshots[path] = raw
            return raw
        return patch.object(candidate, "read_input", side_effect=read)

    def ui_fixture(self):
        files, rows, compiles = {}, [], []
        for source, compiled, log in zip(candidate.UI_SOURCES, candidate.UI_COMPILED, candidate.UI_LOGS):
            data = ("reviewed " + source).encode()
            for path in (candidate.CONTENT/"panorama"/source, candidate.ROOT/"panorama/src"/source): files[path] = data
            files[candidate.ROOT/compiled] = resource(data)
            files[candidate.UI_DIRECTORY/log] = b"OK: 1 compiled, 0 failed, 0 skipped"
            compiles.append(dict(source=str(candidate.CONTENT/"panorama"/source), exit_code=0, native_one_success=True,
                                 log=str(candidate.UI_DIRECTORY/log)))
        files[candidate.ROOT/candidate.UI_TEST] = b"reviewed UI behavioral tests"
        for path, raw in list(files.items()):
            if path.parent != candidate.UI_DIRECTORY:
                rows.append(dict(path=str(path), bytes=len(raw), sha256=candidate.web.sha(raw)))
        receipt = dict(status="PASS", real_orders=0, payment_requests=0, files=rows, native_resource_compile=compiles)
        files[candidate.UI_REPORT] = json.dumps(receipt).encode()
        return files, receipt

    def pins(self, patches=None, sources=None):
        stack = ExitStack()
        stack.enter_context(patch.object(candidate, "PATCH_PINS", {name: candidate.web.sha(raw) for name, raw in (patches or {}).items()}))
        stack.enter_context(patch.object(candidate, "SOURCE_PINS", {name: candidate.web.sha(raw) for name, raw in (sources or {}).items()}))
        stack.enter_context(patch.object(candidate, "WRAPPER_SHA", candidate.web.sha(candidate.WRAPPER)))
        stack.enter_context(patch.object(candidate, "UI_REPORT_SHA", "a" * 64))
        stack.enter_context(patch.object(candidate, "MANIFEST_REPORT_SHA", "b" * 64))
        return stack

    def fixture(self):
        policy = candidate.pack.handoff.load_json(candidate.ROOT / "tools/lua_protection_policy.json")
        protected = list(policy["business_modules"]) + [policy["generated_prefix"] + "fixture_%03d.lua" % i for i in range(176)]
        files = {name: ("protected:" + name).encode() for name in protected}
        files.update({candidate.MAIN: MAIN, candidate.PROFILE: PROFILE, candidate.ADDONINFO: INFO,
                      candidate.NETTABLES: NETTABLES, candidate.WEB_CONFIG: b"return { enabled = true }\n",
                      candidate.MANIFEST_COMPILED: resource(b"original manifest"), candidate.ENTRY_MAP: b"dormant signed entry map",
                      candidate.RELEASE_PROFILE: b'return { channel = "production" }\r\n', "maps/template_map.vpk": b"signed game map"})
        files.update({"materials/fixture_%04d.vmat_c" % i: b"frozen resource" for i in range(candidate.BASE_FILES - len(files))})
        sources = {candidate.SESSION_CONFIG: b'return { enabled = false, expected_map = "template_map" }\r\n',
                   candidate.SESSION: b"-- reviewed native session provider\r\nreturn {}\r\n",
                   candidate.PROBE: b"-- WS4-MP-10\r\nfunction M.public_status() end\r\n",
                   candidate.STATUS: b"-- reviewed status only\r\nreturn {}\r\n"}
        patches = {candidate.MAIN: candidate.patch_main(MAIN), candidate.PROFILE: candidate.patch_profile(PROFILE),
                   candidate.ADDONINFO: INFO.replace(b'"maps"              "ws4_entry"', b'"maps"              "template_map"'),
                   candidate.NETTABLES: candidate.patch_nettables(NETTABLES), candidate.WEB_CONFIG: b"return { enabled = false }\n",
                   candidate.MANIFEST_COMPILED: resource(b"reviewed manifest"), **sources}
        patches[candidate.SESSION_CONFIG] = sources[candidate.SESSION_CONFIG].replace(b"enabled = false", b"enabled = true")
        patches.update({name: resource(name.encode()) for name in candidate.UI_COMPILED})
        return files, patches, sources, protected

    def test_fixed_identity_scope_and_incomplete_review_defaults(self):
        args = candidate.parser().parse_args([])
        self.assertFalse(args.build); self.assertIsNone(args.signing_key)
        self.assertEqual(args.sequence, 2026102507)
        self.assertEqual(candidate.BASE_SHA, "88611d026e49c52b5bce7324818f36a11a60059a2844b8f646b884ba15debaa9")
        self.assertEqual((len(candidate.MODIFIED), len(candidate.ADDED), candidate.EXPECTED_FILES), (6, 7, 6636))
        self.assertNotIn(candidate.ENTRY_MAP, candidate.ALLOWLIST)
        with patch.object(candidate,"UI_REPORT_SHA",None), \
                patch.object(candidate, "authenticate_base", side_effect=AssertionError("baseline IO")), \
                patch.object(candidate.web, "output_paths", side_effect=AssertionError("private key IO")):
            with self.assertRaisesRegex(ValueError, "pins are not finalized"): candidate.build(args)

    def test_wrong_identity_and_outputs_rejected_before_baseline_or_key_io(self):
        _, patches, sources, _ = self.fixture()
        with self.pins(patches, sources), patch.object(candidate, "authenticate_base", side_effect=AssertionError("baseline IO")):
            for sequence in (2026102504, 2026102505):
                with self.assertRaisesRegex(ValueError, "fixed sequence"):
                    candidate.build(candidate.parser().parse_args(["--sequence", str(sequence)]))
            with self.assertRaisesRegex(ValueError, "fixed new"):
                candidate.build(candidate.parser().parse_args(["--build", "--destination", str(candidate.BASE)]))
            with self.assertRaisesRegex(ValueError, "fixed directory"):
                candidate.build(candidate.parser().parse_args(["--build", "--destination", str(candidate.DESTINATION),
                    "--trusted-source", str(candidate.TRUSTED_DESTINATION), "--package-output", "relative"]))

    def test_main_patch_reverses_all_bytes_including_mixed_newlines(self):
        result = candidate.patch_main(MAIN)
        self.assertEqual(candidate.restore_main(result), MAIN)
        self.assertTrue(result.startswith(b"-- original LF entry prefix\n"))
        self.assertTrue(result.endswith(candidate.WRAPPER + candidate.TAIL))
        self.assertNotIn(b"onboarding", result)
        for invalid in (MAIN.replace(candidate.MAIN_INIT, b""), MAIN + candidate.MAIN_INIT,
                        MAIN.replace(candidate.MAIN_INIT, candidate.MAIN_INIT.replace(b".init()", b".init(nil)")),
                        MAIN.replace(candidate.TAIL, b"return Other\r\n")):
            with self.assertRaises(ValueError): candidate.patch_main(invalid)

    def test_every_profile_context_is_unique_and_inverse_preserves_entire_original(self):
        result = candidate.patch_profile(PROFILE)
        self.assertEqual(candidate.restore_profile(result), PROFILE)
        self.assertIn(b"if not injected_provider or session_multiplayer_provider then", result)
        self.assertIn(b"assert(injected_provider and require", result)
        self.assertIn(b"session_multiplayer_provider = options and options.session_multiplayer_test == true or false", result)
        for before, _ in candidate.PROFILE_PATCHES:
            for invalid in (PROFILE.replace(before, b"", 1), PROFILE + before):
                with self.assertRaises(ValueError): candidate.patch_profile(invalid)

    def test_net_table_and_manifest_allow_one_literal_insertion_only(self):
        result = candidate.patch_nettables(NETTABLES)
        self.assertEqual(result.replace(b'\r\r\n        "survival_arcade_multiplayer_test",', b""), NETTABLES)
        self.assertEqual(candidate.manifest_source(OLD_MANIFEST).replace(candidate.MANIFEST_LINE + b"\n", b""), OLD_MANIFEST)
        for raw in (candidate.manifest_source(OLD_MANIFEST), OLD_MANIFEST + b"  </Panel>"):
            with self.assertRaises(ValueError): candidate.manifest_source(raw)
        with self.assertRaises(ValueError): candidate.patch_nettables(result)

    def test_actual_wrapper_preserves_varargs_and_isolates_both_diagnostic_failures(self):
        program = (b'local order = {}\nActivate = function(...) order[#order+1]="old"; return 7,nil,false end\n'
                   b'require = function(name) return { activate=function() order[#order+1]=name; error("fixture") end } end\n'
                   + candidate.WRAPPER +
                   b'local function capture(...) return {n=select("#",...),...} end\nlocal v=capture(Activate(1,nil,3))\n'
                   b'assert(v.n==3 and v[1]==7 and v[2]==nil and v[3]==false)\n'
                   b'assert(table.concat(order,",")=="old,systems/workshop_network_probe,systems/arcade_multiplayer_test")\n'
                   b'print("MP10_WRAPPER_PASS")\n')
        result = subprocess.run([str(candidate.web.LUA_COMPILER.with_name("lua5.1.exe")), "-"], input=program, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors="replace"))
        self.assertIn(b"MP10_WRAPPER_PASS", result.stdout)

    def test_exact_audit_preserves_all_180_protected_and_removes_only_new_candidates_entry(self):
        files, patches, sources, protected = self.fixture()
        before = manifest(files)
        with self.pins(patches, sources):
            after = candidate.projected_manifest(before, patches)
            changes = candidate.audit_changes(before, after, patches, protected)
            self.assertEqual(len(changes), 14)
            self.assertEqual(after["file_count"], 6636)
            final = {name:raw for name,raw in dict(files,**patches).items() if name not in candidate.REMOVED}
            for name in (protected[0], "maps/template_map.vpk", candidate.RELEASE_PROFILE):
                invalid = dict(final); invalid[name] = b"tampered"
                with self.assertRaises(ValueError): candidate.audit_changes(before, manifest(invalid), patches, protected)
            for invalid in (dict(final, **{"scripts/extra.lua": b"bad"}),
                            dict(final, **{candidate.ENTRY_MAP:files[candidate.ENTRY_MAP]})):
                with self.assertRaises(ValueError): candidate.audit_changes(before, manifest(invalid), patches, protected)

    def test_audit_rejects_changed_main_or_profile_beyond_reversible_patch_even_if_repinned(self):
        files, patches, sources, protected = self.fixture()
        for name in (candidate.MAIN, candidate.PROFILE):
            tampered = dict(patches); tampered[name] = b"-- unrelated current code\r\n" + tampered[name]
            with self.pins(tampered, sources), self.assertRaisesRegex(ValueError, "entire frozen"):
                candidate.audit_changes(manifest(files), candidate.projected_manifest(manifest(files), tampered), tampered, protected)

    def test_default_plan_does_not_write_sign_compile_stage_package_or_read_private_key(self):
        files, patches, sources, protected = self.fixture()
        with self.pins(patches, sources), ExitStack() as stack:
            stack.enter_context(patch.object(candidate, "authenticate_base", return_value=(Path("unused"), manifest(files), {"key_id":"fixture"}, {})))
            stack.enter_context(patch.object(candidate, "protected_paths", return_value=protected))
            stack.enter_context(patch.object(candidate, "capture_inputs", return_value=({}, patches)))
            stack.enter_context(patch.object(candidate, "trust_inputs", return_value={}))
            stack.enter_context(patch.object(candidate.web, "git", return_value=b"head\n"))
            for target, method in ((candidate, "stage_runtime"), (candidate.web, "output_paths"),
                                   (candidate.pack.protect_data, "sign_manifest"), (candidate.pack.runtime, "atomic_write_json"),
                                   (candidate.web.protect_runtime_lua, "syntax_check"), (candidate.pack, "package")):
                stack.enter_context(patch.object(target, method, side_effect=AssertionError("forbidden plan mutation/key read")))
            result = candidate.build(candidate.parser().parse_args(["--signing-key", "PRIVATE_NOT_READ.pem"]))
        self.assertEqual(result["status"], "READ_ONLY_PLAN")
        self.assertTrue(result["session_only"] and result["original_entry_map_preserved"])
        self.assertEqual(result["allowed_removals"],[candidate.ENTRY_MAP])
        self.assertFalse(result["real_money_payments"] or result["cloud_archive_enabled"] or result["workshop_upload_performed"])

    def test_trust_snapshot_updates_both_gates_and_preserves_all_other_old_trust(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory).resolve(); old, new, trusted = (folder / name for name in ("old", "new", "trusted"))
            for name in candidate.trust_names():
                path = old / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(("old:"+name).encode())
            for name in (candidate.MAIN, candidate.PROFILE):
                path = new / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(("new:"+name).encode())
            with patch.object(candidate, "BASE_TRUSTED", old): candidate.trusted_snapshot(new, trusted)
            self.assertEqual({path.relative_to(trusted).as_posix() for path in trusted.rglob("*") if path.is_file()}, set(candidate.trust_names()))
            for name in candidate.trust_names():
                self.assertEqual((trusted/name).read_bytes(), (("new:" if name in (candidate.MAIN,candidate.PROFILE) else "old:")+name).encode())
            with self.assertRaises(FileExistsError): candidate.trusted_snapshot(new, trusted)

    def test_actual_staging_preserves_base_and_refuses_existing_destination(self):
        files, patches, _, _ = self.fixture()
        small = {name: files[name] for name in (candidate.MAIN,candidate.PROFILE,candidate.ENTRY_MAP,candidate.RELEASE_PROFILE)}
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory).resolve(); base, destination = folder/"base", folder/"new"
            for name, raw in small.items():
                path=base/name; path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(raw)
            candidate.stage_runtime(base, destination, manifest(small), patches)
            for name, raw in small.items(): self.assertEqual((base/name).read_bytes(), raw)
            self.assertFalse((destination/candidate.ENTRY_MAP).exists())
            self.assertEqual((destination/candidate.PROFILE).read_bytes(), patches[candidate.PROFILE])
            with self.assertRaises(FileExistsError): candidate.stage_runtime(base,destination,manifest(small),patches)

    def test_compiled_resource_validates_data_and_rejects_header_or_block_corruption(self):
        raw = resource(b"reviewed JS bytes")
        self.assertEqual(candidate.compiled_data(raw), b"reviewed JS bytes")
        for invalid in (raw[:-1], b"x"*40, raw[:4]+b"\x0b\x00"+raw[6:]):
            with self.assertRaises(ValueError): candidate.compiled_data(invalid)

    def test_ui_receipt_requires_exact_ten_files_mirrors_and_real_compile_success(self):
        files, receipt = self.ui_fixture()
        with self.read_from(files), patch.object(candidate,"UI_REPORT_SHA",candidate.web.sha(files[candidate.UI_REPORT])):
            patches = candidate.capture_ui({})
            self.assertEqual(set(patches), set(candidate.UI_COMPILED))
        mutations = (
            lambda r: r["files"][0].update(path="../private.pem"),
            lambda r: r["files"].append(deepcopy(r["files"][0])),
            lambda r: r["files"][0].update(sha256="0"*64),
            lambda r: r["native_resource_compile"][0].update(exit_code=1),
            lambda r: r["native_resource_compile"][0].update(log="../unreviewed.log"),
            lambda r: r.update(real_orders=1),
        )
        for change in mutations:
            bad=deepcopy(receipt);change(bad);files[candidate.UI_REPORT]=json.dumps(bad).encode()
            with self.read_from(files),patch.object(candidate,"UI_REPORT_SHA",candidate.web.sha(files[candidate.UI_REPORT])),self.assertRaises(ValueError):
                candidate.capture_ui({})

    def test_capture_never_substitutes_current_main_profile_or_unrelated_development_changes(self):
        files, patches, sources, _ = self.fixture()
        inputs={candidate.BASE/name:files[name] for name in (candidate.MAIN,candidate.PROFILE,candidate.ADDONINFO,candidate.NETTABLES,candidate.WEB_CONFIG)}
        inputs.update({candidate.ROOT/name:raw for name,raw in sources.items()})
        with self.pins(patches,sources),self.read_from(inputs), \
                patch.object(candidate,"capture_ui",return_value={name:patches[name] for name in candidate.UI_COMPILED}), \
                patch.object(candidate,"capture_manifest",return_value=patches[candidate.MANIFEST_COMPILED]):
            snapshots,actual=candidate.capture_inputs(candidate.BASE)
        self.assertEqual(actual,patches)
        self.assertNotIn(candidate.ROOT/candidate.MAIN,snapshots)
        self.assertNotIn(candidate.ROOT/candidate.PROFILE,snapshots)

    def test_unified_manifest_receipt_binds_historical_source_exact_paths_and_all_four_compiles(self):
        files,_=self.ui_fixture(); names=(*candidate.UI_SOURCES,candidate.MANIFEST_SOURCE)
        manifest_source=candidate.manifest_source(OLD_MANIFEST)
        source_paths=[candidate.ROOT/"panorama/src"/n for n in candidate.UI_SOURCES]+[
            candidate.COMPILE_DIRECTORY/"manifest_compile_sources/source/panorama/src"/candidate.MANIFEST_SOURCE]
        content_paths=[candidate.CONTENT/"panorama"/n for n in candidate.UI_SOURCES]+[
            candidate.COMPILE_DIRECTORY/"manifest_compile_sources/content/panorama"/candidate.MANIFEST_SOURCE]
        runtime_paths=[candidate.ROOT/n for n in candidate.UI_COMPILED]+[candidate.MANIFEST_OVERLAY/candidate.MANIFEST_COMPILED]
        files[source_paths[-1]]=manifest_source;files[content_paths[-1]]=manifest_source
        files[runtime_paths[-1]]=resource(b"compiled historical manifest")
        logs=("compile_hud_xml.log","compile_hud_css.log","compile_hud_js.log","compile_manifest_overlay.log")
        rows=[]
        for name,source,content,runtime,log in zip(names,source_paths,content_paths,runtime_paths,logs):
            log_path=candidate.UI_DIRECTORY/candidate.UI_LOGS[2] if name==candidate.UI_SOURCES[2] else candidate.COMPILE_DIRECTORY/log
            files[log_path]=b"OK: 1 compiled, 0 failed, 0 skipped"
            rows.append(dict(relative=name,source_path=str(source),content_path=str(content),runtime_path=str(runtime),
                source_sha256=candidate.web.sha(files[source]),content_sha256=candidate.web.sha(files[content]),
                runtime_sha256=candidate.web.sha(files[runtime]),source_bytes=len(files[source]),content_bytes=len(files[content]),
                runtime_bytes=len(files[runtime]),exit_code=0,native_one_success=True,log_path=str(log_path)))
        receipt=dict(ok=True,check_only=False,compiled_files=4,scope=list(names),results=rows,
            overlay=dict(historical_commit=candidate.MANIFEST_COMMIT,historical_source_sha256=candidate.web.sha(OLD_MANIFEST),
            sole_insertion=(candidate.MANIFEST_LINE+b"\n").decode(),removing_insertion_restores_historical_source=True,onboarding_or_lobby_added=False))
        files[candidate.MANIFEST_REPORT]=json.dumps(receipt).encode()
        with self.read_from(files),patch.object(candidate,"MANIFEST_REPORT_SHA",candidate.web.sha(files[candidate.MANIFEST_REPORT])), \
                patch.object(candidate.web,"git",return_value=OLD_MANIFEST):
            self.assertEqual(candidate.capture_manifest({}),files[runtime_paths[-1]])
        for change in (lambda r:r["results"][-1].update(source_path="../escape.xml"),
                       lambda r:r["results"][-1].update(runtime_path=str(candidate.ROOT/candidate.MANIFEST_COMPILED)),
                       lambda r:r["overlay"].update(onboarding_or_lobby_added=True),
                       lambda r:r["results"].append(deepcopy(r["results"][0]))):
            bad=deepcopy(receipt);change(bad);files[candidate.MANIFEST_REPORT]=json.dumps(bad).encode()
            with self.read_from(files),patch.object(candidate,"MANIFEST_REPORT_SHA",candidate.web.sha(files[candidate.MANIFEST_REPORT])), \
                    patch.object(candidate.web,"git",return_value=OLD_MANIFEST),self.assertRaises(ValueError):
                candidate.capture_manifest({})

    def test_changed_review_input_or_head_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory).resolve()/"input.lua";path.write_bytes(b"reviewed")
            with patch.object(candidate.web,"git",return_value=b"head\n"):
                candidate.require_review_unchanged({path:b"reviewed"},"head")
                with self.assertRaises(ValueError):candidate.require_review_unchanged({path:b"changed"},"head")
                with self.assertRaises(ValueError):candidate.require_review_unchanged({path:b"reviewed"},"other")


if __name__ == "__main__":
    unittest.main()
