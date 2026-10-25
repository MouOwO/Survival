"""Synthetic rejection tests; no real candidate, private key, game or network."""
from contextlib import ExitStack
from copy import deepcopy
import json
from pathlib import Path
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_archive_font_candidate as candidate
from test_web_auth_candidate import manifest

SOURCE = "scripts/custom_game/common/archive_font_v36.js"
RUNTIME = "panorama/scripts/custom_game/common/archive_font_v36.vjs_c"


def resource(data=b"// reviewed fixture\n"):
    return struct.pack("<IHHII4sII", 28 + len(data), 12, 1, 8, 1, b"DATA", 8, len(data)) + data


class ArchiveFontCandidateTest(unittest.TestCase):
    def fixture(self):
        policy = candidate.pack.handoff.load_json(candidate.ROOT / "tools/lua_protection_policy.json")
        protected = list(policy["business_modules"]) + [
            policy["generated_prefix"] + "fixture_%03d.lua" % i for i in range(176)]
        files = {name: ("protected:" + name).encode() for name in protected}
        for name in candidate.ALLOWLIST | {
                candidate.MAIN, candidate.WEB_CONFIG, candidate.RELEASE_PROFILE,
                candidate.pack.handoff.ACCESS_FILE, "maps/template_map.vpk", "maps/ws4_entry.vpk",
                "scripts/vscripts/systems/payment_service.lua", "scripts/vscripts/systems/commerce_service.lua",
                "scripts/vscripts/core/commerce_release_policy.lua", "addoninfo.txt"}:
            files[name] = ("frozen:" + name).encode()
        for i in range(candidate.BASE_FILES - len(files)):
            files["materials/fixture_%04d.vmat_c" % i] = b"frozen texture"
        return protected, files, {name: resource(("// reviewed " + name).encode()) for name in candidate.ALLOWLIST}

    def compile_fixture(self, folder):
        folder = folder.resolve()
        root, content, overlay = folder / "game", folder / "content", folder / "overlay"
        sources, runtimes, rows = {}, {}, []
        for name in sorted(candidate.SOURCE_NAMES):
            source = ("// reviewed fixture " + name + "\r\nvar ready = false;\r\n").encode()
            runtime = resource(source)
            relative = "panorama/" + name[:-3] + ".vjs_c"
            sources[name], runtimes[relative] = source, runtime
            for path, raw in ((root / ("panorama/src/" + name), source),
                              (content / ("panorama/" + name), source),
                              (root / relative, runtime), (overlay / relative, runtime)):
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(raw)
            rows.append(dict(relative=name, source_sha256=candidate.web.sha(source),
                             content_sha256=candidate.web.sha(source), runtime_sha256=candidate.web.sha(runtime),
                             runtime_bytes=len(runtime)))
        report = dict(ok=True, check_only=False, compiled_files=3, scope=sorted(candidate.SOURCE_NAMES), results=rows)
        receipt = folder / "compile.json"
        receipt.write_bytes(candidate.pack.runtime.canonical_bytes(report))
        return root, content, overlay, sources, runtimes, receipt, report

    def compile_pins(self, data):
        root, content, _, sources, runtimes, receipt, _ = data
        pins = {name: (candidate.web.sha(source), candidate.web.sha(runtimes["panorama/" + name[:-3] + ".vjs_c"]),
                       len(runtimes["panorama/" + name[:-3] + ".vjs_c"])) for name, source in sources.items()}
        stack = ExitStack()
        for name, value in (("ROOT", root), ("CONTENT", content), ("JS_PINS", pins),
                            ("COMPILE_REPORT_SHA", candidate.web.sha(receipt.read_bytes()))):
            stack.enter_context(patch.object(candidate, name, value))
        return stack

    def test_fixed_v06_identity_exact_three_scope_and_default_plan(self):
        args = candidate.parser().parse_args([])
        self.assertFalse(args.build)
        self.assertIsNone(args.signing_key)
        self.assertIsNone(args.destination)
        self.assertEqual(candidate.BASE_SEQUENCE, 2026102501)
        self.assertEqual(args.sequence, 2026102502)
        self.assertEqual(candidate.BASE_FILES, 6630)
        self.assertEqual(candidate.BASE_SHA, "1dd9d88f885f8e1617985f933bbdb450884f91a7cdb96b10e0315d2b0cdaa884")
        self.assertEqual(candidate.ALLOWLIST, {RUNTIME, "panorama/scripts/custom_game/commerce_wallet.vjs_c",
                                             "panorama/scripts/custom_game/daily_remaining_5d5c1152eb.vjs_c"})
        self.assertEqual(candidate.REVISION, "WS4-UI-FONT-WALLET-07")
        self.assertTrue(all(not name.endswith(".lua") for name in candidate.ALLOWLIST))

    def test_unreviewed_pins_fail_before_baseline_or_any_key_access(self):
        with patch.object(candidate, "COMPILE_REPORT_SHA", None), \
                patch.object(candidate, "authenticate_base", side_effect=AssertionError("baseline read")), \
                patch.object(candidate.web, "output_paths", side_effect=AssertionError("key/output read")):
            with self.assertRaisesRegex(ValueError, "not finalized"):
                candidate.build(candidate.parser().parse_args([]))

    def test_other_sequence_fails_before_review_or_io(self):
        with patch.object(candidate, "require_review_pins", side_effect=AssertionError("pins read")):
            for seq in (2026102405, 2026102501, 2026102503):
                with self.subTest(seq=seq), self.assertRaisesRegex(ValueError, "fixed 2026102502"):
                    candidate.build(candidate.parser().parse_args(["--sequence", str(seq)]))

    def test_review_pins_cannot_shrink_or_expand_scope(self):
        for pins in ({SOURCE: ("0" * 64, "0" * 64, 50)},
                     dict(candidate.JS_PINS, **{"scripts/custom_game/payment_test.js": ("0" * 64, "0" * 64, 50)})):
            with patch.object(candidate, "JS_PINS", pins), self.assertRaisesRegex(ValueError, "exact three"):
                candidate.require_review_pins()

    def test_default_plan_never_touches_key_outputs_or_signing(self):
        protected, files, patches = self.fixture()
        with patch.object(candidate, "require_review_pins"), \
                patch.object(candidate, "authenticate_base", return_value=(Path("unused"), manifest(files),
                             {"release_sequence": candidate.BASE_SEQUENCE})), \
                patch.object(candidate, "protected_paths", return_value=protected), \
                patch.object(candidate, "capture_inputs", return_value=({}, patches)), \
                patch.object(candidate, "trust_inputs", return_value={}), \
                patch.object(candidate.web, "git", return_value=b"reviewed\n"), \
                patch.object(candidate, "require_review_unchanged"), \
                patch.object(candidate.web, "output_paths", side_effect=AssertionError("key/output")), \
                patch.object(candidate.pack.protect_data, "sign_manifest", side_effect=AssertionError("sign")), \
                patch.object(candidate.pack, "package", side_effect=AssertionError("package")):
            result = candidate.build(candidate.parser().parse_args(["--signing-key", "never-read.pem"]))
        self.assertEqual(result["status"], "READ_ONLY_PLAN")
        self.assertEqual(result["protected_modules_preserved"], 180)
        self.assertFalse(result["game_started"] or result["online_authentication_changed"])

    def test_base_signed_identity_sequence_key_and_floor_are_required(self):
        with tempfile.TemporaryDirectory() as folder:
            base = Path(folder).resolve()
            path = base / candidate.WEB_CONFIG
            path.parent.mkdir(parents=True)
            path.write_bytes(b"return { enabled = true }\n")
            doc = dict(content_sha256=candidate.BASE_SHA, file_count=6630)
            sig = dict(release_sequence=candidate.BASE_SEQUENCE, key_id="reviewed-key")
            policy = dict(integrity=dict(trusted_key_id="reviewed-key", minimum_release_sequence=2026102501))
            with patch.object(candidate.pack.handoff, "trusted_policy", return_value=(policy, {})), \
                    patch.object(candidate.pack, "authenticate", return_value=(base, doc, sig, {})) as auth, \
                    patch.object(candidate.pack.runtime, "require_production"):
                self.assertEqual(candidate.authenticate_base()[0], base)
                for bad_doc, bad_sig in ((dict(doc, content_sha256="0" * 64), sig),
                                         (dict(doc, file_count=1), sig),
                                         (doc, dict(sig, release_sequence=2026102405)),
                                         (doc, dict(sig, key_id="wrong"))):
                    auth.return_value = base, bad_doc, bad_sig, {}
                    with self.assertRaises(ValueError): candidate.authenticate_base()
                auth.return_value = base, doc, sig, {}
                policy["integrity"]["minimum_release_sequence"] = 2026102503
                with self.assertRaisesRegex(ValueError, "floor"): candidate.authenticate_base()

    def test_exact_three_changes_preserve_all_6630(self):
        protected, files, replacements = self.fixture()
        changes = candidate.audit_changes(manifest(files), manifest(dict(files, **replacements)), replacements, protected)
        self.assertEqual({row["path"] for row in changes}, candidate.ALLOWLIST)
        self.assertEqual(len(changes), 3)

    def test_extra_lua_auth_cash_maps_atlas_and_unrelated_changes_rejected(self):
        protected, files, replacements = self.fixture()
        paths = [candidate.MAIN, candidate.POLICY_MODULE, candidate.WEB_CONFIG, candidate.RELEASE_PROFILE,
                 candidate.pack.handoff.ACCESS_FILE, "maps/template_map.vpk", "maps/ws4_entry.vpk",
                 "scripts/vscripts/systems/payment_service.lua", "scripts/vscripts/systems/commerce_service.lua",
                 "scripts/vscripts/core/commerce_release_policy.lua", "materials/fixture_0000.vmat_c"]
        for name in paths:
            with self.subTest(name=name), self.assertRaisesRegex(ValueError, "Only the three reviewed"):
                candidate.audit_changes(manifest(files), manifest(dict(files, **replacements, **{name: b"unexpected"})),
                                        replacements, protected)

    def test_add_remove_wrong_count_or_no_actual_font_change_rejected(self):
        protected, files, replacements = self.fixture()
        newer = dict(files, **replacements)
        for invalid in (dict(newer, **{"new_atlas.vtex_c": b"new"}),
                        {name: raw for name, raw in newer.items() if name != "materials/fixture_0000.vmat_c"}):
            with self.assertRaisesRegex(ValueError, "additions/removals"):
                candidate.audit_changes(manifest(files), manifest(invalid), replacements, protected)
        with self.assertRaisesRegex(ValueError, "Only the three reviewed"):
            candidate.audit_changes(manifest(files), manifest(files), replacements, protected)
        for missing in candidate.ALLOWLIST:
            incomplete = dict(newer, **{missing: files[missing]})
            with self.subTest(missing=missing), self.assertRaisesRegex(ValueError, "Only the three reviewed"):
                candidate.audit_changes(manifest(files), manifest(incomplete), replacements, protected)
        with patch.object(candidate, "BASE_FILES", 6627), self.assertRaisesRegex(ValueError, "6630"):
            candidate.audit_changes(manifest(files), manifest(newer), replacements, protected)

    def test_wrong_patch_or_stage_bytes_or_protected_inventory_rejected(self):
        protected, files, replacements = self.fixture()
        old, new = manifest(files), manifest(dict(files, **replacements))
        with self.assertRaisesRegex(ValueError, "allowlist"):
            candidate.audit_changes(old, new, dict(replacements, extra=b"no"), protected)
        with self.assertRaisesRegex(ValueError, "staging"):
            candidate.audit_changes(old, new, dict(replacements, **{RUNTIME: b"tamper"}), protected)
        for invalid in (protected[:-1], protected[:-1] + [protected[0]],
                        protected[:-1] + ["materials/fixture_0000.vmat_c"]):
            with self.assertRaises(ValueError): candidate.audit_changes(old, new, replacements, invalid)

    def test_policy_pin_mismatch_rejected(self):
        _, files, _ = self.fixture()
        with patch.object(candidate, "LUA_POLICY_SHA", "0" * 64), self.assertRaisesRegex(ValueError, "policy changed"):
            candidate.protected_paths(manifest(files))

    def test_exact_native_compile_capture_game_and_overlay(self):
        with tempfile.TemporaryDirectory() as folder:
            data = self.compile_fixture(Path(folder))
            with self.compile_pins(data):
                for overlay in (None, data[2]):
                    snapshots, patches = candidate.capture_inputs(data[5], overlay)
                    self.assertEqual(patches, data[4])
                    self.assertEqual(len(snapshots), 10)

    def test_receipt_hash_scope_status_or_association_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            data = self.compile_fixture(Path(folder)); receipt, original = data[5], data[6]
            with self.compile_pins(data):
                receipt.write_bytes(b"{}")
                with self.assertRaisesRegex(ValueError, "receipt changed"): candidate.capture_inputs(receipt)
                for change in (dict(check_only=True), dict(ok=False), dict(compiled_files=2),
                               dict(scope=sorted(candidate.SOURCE_NAMES) + ["scripts/custom_game/payment_test.js"]),
                               dict(results=[]), dict(results=[dict(row, runtime_sha256="0" * 64) for row in original["results"]])):
                    invalid = dict(original, **change)
                    receipt.write_bytes(candidate.pack.runtime.canonical_bytes(invalid))
                    with patch.object(candidate, "COMPILE_REPORT_SHA", candidate.web.sha(receipt.read_bytes())), \
                            self.assertRaises(ValueError): candidate.capture_inputs(receipt)

    def test_content_source_and_runtime_changes_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            data = self.compile_fixture(Path(folder))
            with self.compile_pins(data):
                content = data[1] / ("panorama/" + SOURCE)
                content.write_bytes(b"changed")
                with self.assertRaisesRegex(ValueError, "source differs"): candidate.capture_inputs(data[5])
                content.write_bytes(data[3][SOURCE])
                runtime = data[0] / RUNTIME
                runtime.write_bytes(b"changed")
                with self.assertRaisesRegex(ValueError, "compiled font/wallet resource differs"): candidate.capture_inputs(data[5])

    def test_hash_pinned_runtime_still_must_embed_exact_source(self):
        with tempfile.TemporaryDirectory() as folder:
            data = self.compile_fixture(Path(folder))
            bad = resource(b"// different DATA\n")
            (data[0] / RUNTIME).write_bytes(bad)
            next(row for row in data[6]["results"] if row["relative"] == SOURCE).update(
                runtime_sha256=candidate.web.sha(bad), runtime_bytes=len(bad))
            data[5].write_bytes(candidate.pack.runtime.canonical_bytes(data[6]))
            with self.compile_pins(data):
                pins = dict(candidate.JS_PINS)
                pins[SOURCE] = (pins[SOURCE][0], candidate.web.sha(bad), len(bad))
                with patch.object(candidate, "JS_PINS", pins), self.assertRaisesRegex(ValueError, "DATA is not"):
                    candidate.capture_inputs(data[5])

    def test_overlay_extra_or_linked_resource_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            data = self.compile_fixture(Path(folder)); overlay = data[2]
            with self.compile_pins(data):
                extra = overlay / "extra.lua"; extra.write_bytes(b"return {}")
                with self.assertRaisesRegex(ValueError, "exactly"): candidate.capture_inputs(data[5], overlay)
                extra.unlink()
                linked = candidate.pack.protect_data.linked
                with patch.object(candidate.pack.protect_data, "linked",
                                  side_effect=lambda p: p == overlay / RUNTIME or linked(p)), \
                        self.assertRaisesRegex(ValueError, "links"): candidate.capture_inputs(data[5], overlay)

    def test_resource_header_truncation_duplicate_data_and_overlap_rejected(self):
        raw = resource()
        cases = [b"tiny", raw[:-1], struct.pack("<IHHII", len(raw), 11, 1, 8, 1) + raw[16:]]
        # Two table entries reference the same bytes, so even a second DATA or
        # another tag cannot hide an overlapping unreviewed resource block.
        data = b"x" * 16
        cases.append(struct.pack("<IHHII", 40 + len(data), 12, 1, 8, 2)
                     + struct.pack("<4sII", b"DATA", 20, len(data))
                     + struct.pack("<4sII", b"DATA", 8, len(data)) + data)
        for raw in cases:
            with self.subTest(size=len(raw)), self.assertRaises((ValueError, struct.error)):
                candidate.compiled_data(raw, RUNTIME)

    def test_reviewed_input_or_head_drift_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder).resolve() / "input.js"; path.write_bytes(b"same")
            with patch.object(candidate.web, "git", return_value=b"head\n"):
                candidate.require_review_unchanged({path: b"same"}, "head")
                with self.assertRaisesRegex(ValueError, "input changed"):
                    candidate.require_review_unchanged({path: b"old"}, "head")
                with self.assertRaisesRegex(ValueError, "HEAD changed"):
                    candidate.require_review_unchanged({path: b"same"}, "other")


if __name__ == "__main__":
    unittest.main()
