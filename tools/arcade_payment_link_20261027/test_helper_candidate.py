"""Payment-only candidate isolation tests. Never stage or sign external data."""
from contextlib import ExitStack
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import struct
import sys
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_helper_candidate as candidate
sys.path.insert(0, str(candidate.ROOT / "tools/workshop_test"))
from test_web_auth_candidate import manifest


def resource(data):
    return struct.pack("<IHHII", 28 + len(data), 12, 0, 8, 1) + struct.pack("<4sII", b"DATA", 8, len(data)) + data


class HelperCandidateTests(unittest.TestCase):
    def fixture(self):
        policy = candidate.pack.handoff.load_json(candidate.ROOT / "tools/lua_protection_policy.json")
        protected = list(policy["business_modules"]) + [policy["generated_prefix"] + "fixture_%03d.lua" % i for i in range(176)]
        files = {name: ("protected:" + name).encode() for name in protected}
        files.update({name: ("frozen:" + name).encode() for name in candidate.MODIFIED})
        files.update({name: ("immutable:" + name).encode() for name in candidate.FROZEN_CODE_PINS})
        files.update({"maps/template_map.vpk": b"unchanged map", "scripts/vscripts/config/release_profile.lua": b"production",
                      "scripts/vscripts/config/test_access.lua": b"same four testers",
                      "panorama/scripts/custom_game/arcade_shop_catalog.vjs_c": b"same 173 public offers"})
        files.update({"materials/fixture_%04d.vmat_c" % i: b"frozen art" for i in range(candidate.BASE_FILES - len(files))})
        patches = {name: ("reviewed:" + name).encode() for name in candidate.ALLOWLIST}
        return files, patches, protected

    def ui_fixture(self):
        root, content = Path("fixture_root"), Path("fixture_content")
        receipt_path, logs = root / "output/compile.json", root / "output/native_compile"
        rows, pins, inputs = [], {}, {}
        for index, source in enumerate(candidate.PINS):
            raw = ("// reviewed source %d\r\n" % index).encode()
            compiled = candidate.PINS[source][1]
            runtime = resource(raw if source.endswith(".js") else b"compiled XML DATA")
            pin = (candidate.web.sha(raw), compiled, candidate.web.sha(runtime), len(runtime));pins[source] = pin
            log = logs / (Path(source).name + ".log")
            rows.append(dict(source="panorama/src/" + source, source_sha256=pin[0], content="panorama/" + source,
                             compiled=compiled, compiled_sha256=pin[2], compiled_bytes=len(runtime), log=str(log)))
            inputs[root / "panorama/src" / source] = raw;inputs[content / "panorama" / source] = raw
            inputs[root / compiled] = runtime;inputs[log] = b"OK: 1 compiled, 0 failed, 0 skipped\n"
        receipt = dict(ok=True, kind="WS4_PAYMENT_LINK_COMPILE", original_102_bytes_preserved=True, records=rows)
        def encode():
            raw = json.dumps(receipt).encode();inputs[receipt_path] = raw;return candidate.web.sha(raw)
        def read(path, snapshots):
            raw = inputs[path];snapshots[path] = raw;return raw
        return root, content, receipt_path, logs, pins, receipt, inputs, encode, read

    def capture_ui(self, fixture):
        root, content, receipt, logs, pins, _, _, encode, read = fixture
        with ExitStack() as stack:
            for name, value in (("ROOT", root), ("CONTENT", content), ("COMPILE_REPORT", receipt),
                                ("COMPILE_LOG_DIRECTORY", logs), ("PINS", pins), ("COMPILE_REPORT_SHA", encode())):
                stack.enter_context(patch.object(candidate, name, value))
            stack.enter_context(patch.object(candidate, "read_input", side_effect=read))
            return candidate.capture_ui({})

    def test_fixed_default_scope_and_no_packaging_option(self):
        args = candidate.parser().parse_args([])
        self.assertFalse(args.build);self.assertIsNone(args.signing_key);self.assertIsNone(args.package_output)
        self.assertEqual(args.sequence, 2026102701);self.assertEqual(candidate.BASE_SEQUENCE, 2026102604)
        self.assertEqual((candidate.BASE_FILES, candidate.EXPECTED_FILES), (6637, 6639))
        self.assertEqual(candidate.BASE_SHA, "b38b10b76aaa4674c8a2d0ffc436922723a793f4b71665916956b4323f40b744")
        self.assertEqual(len(candidate.ALLOWLIST), 12);self.assertEqual(len(candidate.MODIFIED), 10)
        self.assertEqual(candidate.ADDED, {candidate.CASH_CONFIG, "panorama/scripts/custom_game/payment_capability.vjs_c"})
        self.assertFalse(set(candidate.FROZEN_CODE_PINS) & candidate.ALLOWLIST)
        candidate.require_review_pins()

    def test_unsafe_build_requests_fail_before_baseline_or_key_access(self):
        arguments = (["--sequence", "2026102604"], ["--build"],
                     ["--build", "--signing-key", "never-read", "--destination", str(candidate.BASE)],
                     ["--build", "--signing-key", "never-read", "--trusted-source", str(candidate.BASE_TRUSTED)])
        for values in arguments:
            with self.subTest(values=values), patch.object(candidate, "authenticate_base", side_effect=AssertionError("baseline read")), self.assertRaises(ValueError):
                candidate.build(candidate.parser().parse_args(values))
        args = candidate.parser().parse_args([]);args.package_output = Path("never-create")
        with patch.object(candidate, "authenticate_base", side_effect=AssertionError("baseline read")), self.assertRaises(ValueError): candidate.build(args)

    def test_projection_preserves_all_gameplay_maps_trust_and_180_protected_modules(self):
        files, patches, protected = self.fixture();before = manifest(files)
        after = candidate.projected_manifest(before, patches)
        changes = candidate.audit_changes(before, after, patches, protected)
        self.assertEqual({row["path"] for row in changes}, candidate.ALLOWLIST)
        original, final = ({row["path"]:row for row in doc["files"]} for doc in (before, after))
        self.assertTrue(all(original[name] == final[name] for name in original if name not in candidate.MODIFIED))
        self.assertEqual(set(final) - set(original), candidate.ADDED)
        self.assertEqual(len(candidate.protected_paths(before)), 180)

    def test_foreign_main_provider_maps_roster_protection_or_catalog_changes_rejected(self):
        files, patches, protected = self.fixture()
        for name in (*candidate.FROZEN_CODE_PINS, protected[0], "maps/template_map.vpk", "scripts/vscripts/config/test_access.lua",
                     "scripts/vscripts/config/release_profile.lua", "panorama/scripts/custom_game/arcade_shop_catalog.vjs_c"):
            changed = dict(files, **patches);changed[name] = b"unreviewed"
            with self.subTest(name=name), self.assertRaises(ValueError): candidate.audit_changes(manifest(files), manifest(changed), patches, protected)
        for action in (lambda data:data.update({"scripts/vscripts/foreign.lua":b"extra"}), lambda data:data.pop("maps/template_map.vpk")):
            changed = dict(files, **patches);action(changed)
            with self.assertRaises(ValueError): candidate.audit_changes(manifest(files), manifest(changed), patches, protected)

    def test_missing_duplicate_or_foreign_overlay_and_patch_tampering_rejected(self):
        files, patches, protected = self.fixture();missing = dict(patches);missing.pop(next(iter(missing)))
        for value in (missing, dict(patches, **{"scripts/vscripts/foreign.lua":b"bad"})):
            with self.assertRaises(ValueError): candidate.projected_manifest(manifest(files), value)
        changed = dict(files, **patches);changed[next(iter(patches))] = b"different bytes"
        with self.assertRaises(ValueError): candidate.audit_changes(manifest(files), manifest(changed), patches, protected)
        prior = dict(files);prior[next(iter(candidate.ADDED))] = b"already exists"
        with self.assertRaises(ValueError): candidate.projected_manifest(manifest(prior), patches)

    def test_six_native_receipt_resources_require_exact_source_mirror_and_data(self):
        fixture = self.ui_fixture();captured = self.capture_ui(fixture)
        self.assertEqual(set(captured), candidate.UI)
        fixture = self.ui_fixture();root, content, _, _, pins, _, inputs, _, _ = fixture
        source = next(iter(pins));inputs[content / "panorama" / source] = b"mirror differs"
        with self.assertRaises(ValueError): self.capture_ui(fixture)
        fixture = self.ui_fixture();root, _, _, _, pins, receipt, inputs, _, _ = fixture
        source = next(name for name in pins if name.endswith(".js"));old = pins[source];raw = resource(b"wrong JS DATA")
        pins[source] = (old[0], old[1], candidate.web.sha(raw), len(raw));inputs[root / old[1]] = raw
        row = next(row for row in receipt["records"] if row["compiled"] == old[1]);row.update(compiled_sha256=candidate.web.sha(raw),compiled_bytes=len(raw))
        with self.assertRaisesRegex(ValueError,"DATA"): self.capture_ui(fixture)

    def test_bad_receipt_duplicate_source_compile_failure_and_native_header_rejected(self):
        for mutation in (lambda receipt:receipt.update(kind="mocked"),
                         lambda receipt:receipt["records"].__setitem__(1, deepcopy(receipt["records"][0])),
                         lambda receipt:receipt["records"][0].update(content="panorama/foreign.js")):
            fixture = self.ui_fixture();mutation(fixture[5])
            with self.assertRaises(ValueError): self.capture_ui(fixture)
        fixture = self.ui_fixture();fixture[6][Path(fixture[5]["records"][0]["log"])] = b"1 compiled, 1 failed, 0 skipped"
        with self.assertRaises(ValueError): self.capture_ui(fixture)
        with self.assertRaises(ValueError): candidate.frozen.compiled_data(b"not native compiled DATA")

    def test_web_auth_only_inserts_invalidate_without_current_lobby_or_other_changes(self):
        base = b"function M.enabled() return false end\n\nfunction M.resolve(account, session, success, failure)\n return nil\nend\n"
        source = b"local unrelated_lobby_change=true\nfunction M.invalidate(account, session)\n return false\nend\n\nfunction M.resolve(account, session, success, failure)\nend\n"
        after = candidate.invalidate_only(base, source)
        self.assertIn(b"function M.enabled() return false end", after)
        self.assertEqual(after.count(b"function M.invalidate"), 1);self.assertNotIn(b"unrelated_lobby_change", after)
        self.assertTrue(after.endswith(base[base.index(b"function M.resolve"):]))
        for before, current in ((after, source), (base + base, source), (base, b"no invalidate"), (base, source + source)):
            with self.assertRaises(ValueError): candidate.invalidate_only(before, current)

    def test_configuration_replacements_are_exact_and_ambiguous_matches_fail(self):
        self.assertEqual(candidate.replace_once(b"enabled = false", b"enabled = false", b"enabled = true"), b"enabled = true")
        for raw in (b"enabled = true", b"enabled = false enabled = false"):
            with self.assertRaises(ValueError): candidate.replace_once(raw, b"enabled = false", b"enabled = true")

    def test_private_key_or_literal_credential_cannot_enter_overlay(self):
        for raw in (b"-----BEGIN PRIVATE KEY-----", b"Bearer " + b"x" * 30, b'access_token = "' + b"x" * 30 + b'"'):
            with self.assertRaises(ValueError): candidate.no_credentials({candidate.PAYMENT:raw})
        candidate.no_credentials({candidate.PAYMENT:b'http:SetHTTPRequestHeaderValue("Authorization","Bearer "..token)'})
        with self.assertRaises(ValueError): candidate.no_credentials({"../foreign.lua":b"bad"})

    def test_readonly_plan_does_not_resolve_key_create_stage_sign_package_or_install(self):
        files, patches, protected = self.fixture();before = manifest(files)
        with ExitStack() as stack:
            stack.enter_context(patch.object(candidate,"authenticate_base",return_value=(Path("frozen"),before,{"key_id":"same-key"},{})))
            stack.enter_context(patch.object(candidate,"protected_paths",return_value=protected))
            stack.enter_context(patch.object(candidate,"capture_inputs",return_value=({},patches)))
            stack.enter_context(patch.object(candidate,"trust_inputs",return_value={}));stack.enter_context(patch.object(candidate,"check_lua"))
            stack.enter_context(patch.object(candidate,"require_unchanged"));stack.enter_context(patch.object(candidate.web,"git",return_value=b"same-head\n"))
            for owner, name in ((candidate.web,"output_paths"),(candidate,"stage_runtime"),(candidate,"trusted_snapshot"),
                                (candidate.pack.protect_data,"sign_manifest"),(candidate.pack,"package")):
                stack.enter_context(patch.object(owner,name,side_effect=AssertionError("mutation/key read")))
            stack.enter_context(patch.object(Path,"mkdir",side_effect=AssertionError("directory write")))
            stack.enter_context(patch.object(Path,"write_bytes",side_effect=AssertionError("file write")))
            result = candidate.build(candidate.parser().parse_args(["--signing-key","NEVER-READ.pem"]))
        self.assertEqual(result["status"],"READ_ONLY_PLAN");self.assertFalse(result["workshop_upload_performed"])
        self.assertFalse(result["alias_install_performed"]);self.assertFalse(result["game_started"]);self.assertFalse(result["vpk_packaged"])
        self.assertFalse(result["unpublished_blood_attack_fixes_included"]);self.assertFalse(result["actual_payment_verified"])
        self.assertEqual(result["web_auth_patch"],"invalidate_only_no_hosted_lobby_change")


if __name__ == "__main__": unittest.main(verbosity=2)
