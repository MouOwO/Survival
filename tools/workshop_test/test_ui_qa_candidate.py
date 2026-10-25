"""Offline rejection paths for the exact v05 -> seven-file UI QA candidate."""
from contextlib import ExitStack
from copy import deepcopy
import difflib
from pathlib import Path
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_ui_qa_candidate as candidate
from test_web_auth_candidate import manifest, reviewed_diff


def resource(data=b"// fixture source\n"):
    return struct.pack("<IHHII4sII", 28 + len(data), 12, 1, 8, 1, b"DATA", 8, len(data)) + data


class UIQACandidateTest(unittest.TestCase):
    def fixture(self):
        policy = candidate.pack.handoff.load_json(candidate.ROOT / "tools/lua_protection_policy.json")
        protected = list(policy["business_modules"]) + [
            policy["generated_prefix"] + "fixture_%03d.lua" % i for i in range(176)]
        files = {name: ("protected:" + name).encode() for name in protected}
        for name in candidate.ALLOWLIST:
            files[name] = ("old:" + name).encode()
        gates = (*candidate.pack.handoff.GATE_FILES, *candidate.pack.handoff.ENTRY_GATE_FILES,
                 candidate.pack.handoff.ACCESS_FILE)
        for name in gates:
            files[name] = ("frozen gate:" + name).encode()
        for name in (candidate.RELEASE_PROFILE, candidate.WEB_CONFIG,
                     "scripts/vscripts/core/commerce_release_policy.lua",
                     "scripts/vscripts/systems/player_profile_providers/http_fishing_provider.lua",
                     "maps/template_map.vpk", "maps/ws4_entry.vpk", "addoninfo.txt"):
            files[name] = ("frozen invariant:" + name).encode()
        for i in range(candidate.BASE_FILES - len(files)):
            files["materials/fixture_%04d.vmat_c" % i] = b"unchanged resource"
        replacements = {name: ("reviewed:" + name).encode() for name in candidate.ALLOWLIST}
        return protected, files, replacements

    def compile_fixture(self, folder):
        root, content, overlay = folder / "game", folder / "content", folder / "overlay"
        pins, results = {}, []
        for name in candidate.JS_PINS:
            source = ("// pinned fixture " + name + "\r\nreturn_value=1;\r\n").encode()
            runtime = resource(source)
            pins[name] = (candidate.web.sha(source), candidate.web.sha(runtime), len(runtime))
            relative = "panorama/" + name[:-3] + ".vjs_c"
            for target, raw in ((root / ("panorama/src/" + name), source),
                                (content / ("panorama/" + name), source),
                                (root / relative, runtime), (overlay / relative, runtime)):
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(raw)
            results.append(dict(relative=name, source_sha256=pins[name][0], content_sha256=pins[name][0],
                                runtime_sha256=pins[name][1], runtime_bytes=pins[name][2]))
        report = dict(scope=list(pins), compiled_files=5, ok=True, check_only=False, results=results)
        receipt = folder / "compile.json"
        raw = candidate.pack.runtime.canonical_bytes(report)
        receipt.write_bytes(raw)
        return root, content, overlay, receipt, report, pins

    def patched_compile(self, root, content, pins, receipt):
        stack = ExitStack()
        stack.enter_context(patch.object(candidate, "ROOT", root))
        stack.enter_context(patch.object(candidate, "CONTENT", content))
        stack.enter_context(patch.object(candidate, "JS_PINS", pins))
        stack.enter_context(patch.object(candidate, "COMPILE_REPORT_SHA", candidate.web.sha(receipt.read_bytes())))
        return stack

    def test_fixed_identity_scope_sequence_and_default_plan(self):
        args = candidate.parser().parse_args([])
        self.assertFalse(args.build)
        self.assertIsNone(args.destination)
        self.assertIsNone(args.signing_key)
        self.assertEqual(args.sequence, 2026102501)
        self.assertEqual(candidate.BASE_FILES, 6630)
        self.assertEqual(candidate.BASE_SEQUENCE, 2026102405)
        self.assertEqual(candidate.BASE_SHA, "b4750e433bdd1b1ea2fab0de98d13b3660ed5d3ef80a10c63c46512eab10bc60")
        self.assertEqual(candidate.PATCH_BASELINE, "a1871d23247787e9f4e88231e224c1238c45323f")
        self.assertEqual(len(candidate.ALLOWLIST), 7)
        self.assertEqual(len(candidate.LUA_PINS), 2)
        self.assertEqual(len(candidate.COMPILED), 5)
        self.assertNotIn(candidate.MAIN, candidate.ALLOWLIST)
        self.assertNotIn(candidate.POLICY_MODULE, candidate.ALLOWLIST)

    def test_default_plan_never_accesses_key_output_or_packaging(self):
        protected, files, replacements = self.fixture()
        with patch.object(candidate, "authenticate_base", return_value=(Path("unused-base"), manifest(files),
                          {"release_sequence": candidate.BASE_SEQUENCE})), \
                patch.object(candidate, "protected_paths", return_value=protected), \
                patch.object(candidate, "capture_inputs", return_value=({}, replacements, {})), \
                patch.object(candidate, "trust_inputs", return_value={}), \
                patch.object(candidate.web, "git", return_value=b"reviewed-head\n"), \
                patch.object(candidate, "require_review_unchanged") as recheck, \
                patch.object(candidate.web, "output_paths", side_effect=AssertionError("plan touched key/outputs")), \
                patch.object(candidate.pack.protect_data, "sign_manifest", side_effect=AssertionError("plan signed")), \
                patch.object(candidate.pack, "package", side_effect=AssertionError("plan packaged")):
            result = candidate.build(candidate.parser().parse_args(["--signing-key", "not-read.pem"]))
        self.assertEqual(result["status"], "READ_ONLY_PLAN")
        self.assertEqual(result["protected_modules_preserved"], 180)
        self.assertFalse(result["alias_install_performed"])
        self.assertFalse(result["real_money_payments"])
        recheck.assert_called_once()

    def test_other_sequences_fail_before_any_baseline_io(self):
        with patch.object(candidate, "authenticate_base", side_effect=AssertionError("baseline accessed")):
            for sequence in (2026102101, 2026102405, 2026102500, 2026102502):
                with self.subTest(sequence=sequence), self.assertRaisesRegex(ValueError, "fixed 2026102501"):
                    candidate.build(candidate.parser().parse_args(["--sequence", str(sequence)]))

    def test_exact_seven_changes_leave_all_other_6630_entries_untouched(self):
        protected, files, replacements = self.fixture()
        changes = candidate.audit_changes(manifest(files), manifest(dict(files, **replacements)), replacements, protected)
        self.assertEqual({r["path"] for r in changes}, candidate.ALLOWLIST)
        self.assertEqual(len(changes), 7)

    def test_main_maps_auth_provider_cash_policy_and_unrelated_resources_cannot_change(self):
        protected, files, replacements = self.fixture()
        old, updated = manifest(files), dict(files, **replacements)
        for name in (candidate.MAIN, "maps/ws4_entry.vpk", "maps/template_map.vpk", candidate.WEB_CONFIG,
                     candidate.RELEASE_PROFILE, candidate.pack.handoff.ACCESS_FILE, candidate.POLICY_MODULE,
                     "scripts/vscripts/systems/player_profile_providers/http_fishing_provider.lua",
                     "scripts/vscripts/core/commerce_release_policy.lua", "materials/fixture_0000.vmat_c"):
            with self.subTest(path=name), self.assertRaisesRegex(ValueError, "Only the seven"):
                candidate.audit_changes(old, manifest(dict(updated, **{name: b"unreviewed"})), replacements, protected)

    def test_inventory_additions_removals_and_wrong_totals_are_rejected(self):
        protected, files, replacements = self.fixture()
        updated = dict(files, **replacements)
        for operation in ("add", "remove"):
            invalid = dict(updated)
            if operation == "add":
                invalid["materials/new.vmat_c"] = b"extra"
            else:
                del invalid["materials/fixture_0000.vmat_c"]
            with self.assertRaisesRegex(ValueError, "additions/removals"):
                candidate.audit_changes(manifest(files), manifest(invalid), replacements, protected)
        del files["materials/fixture_0000.vmat_c"]
        del updated["materials/fixture_0000.vmat_c"]
        with self.assertRaisesRegex(ValueError, "exactly 6630"):
            candidate.audit_changes(manifest(files), manifest(updated), replacements, protected)

    def test_missing_change_extra_patch_and_tampered_staging_are_rejected(self):
        protected, files, replacements = self.fixture()
        old, updated = manifest(files), dict(files, **replacements)
        one = next(iter(replacements))
        updated[one] = files[one]
        with self.assertRaisesRegex(ValueError, "Only the seven"):
            candidate.audit_changes(old, manifest(updated), replacements, protected)
        updated = dict(files, **replacements)
        with self.assertRaisesRegex(ValueError, "seven-file allowlist"):
            candidate.audit_changes(old, manifest(updated), dict(replacements, **{candidate.MAIN: b"extra"}), protected)
        with self.assertRaisesRegex(ValueError, "during staging"):
            candidate.audit_changes(old, manifest(updated), dict(replacements, **{one: b"different"}), protected)

    def test_protected_inventory_cannot_shrink_duplicate_or_swap_an_unprotected_path(self):
        protected, files, replacements = self.fixture()
        old, new = manifest(files), manifest(dict(files, **replacements))
        for invalid in (protected[:-1], protected[:-1] + [protected[0]],
                        protected[:-1] + [next(iter(candidate.ALLOWLIST))],
                        protected[:-1] + ["materials/fixture_0000.vmat_c"]):
            with self.assertRaises(ValueError):
                candidate.audit_changes(old, new, replacements, invalid)

    def test_protection_policy_mutation_is_rejected(self):
        _, files, _ = self.fixture()
        with patch.object(candidate, "LUA_POLICY_SHA", "0" * 64):
            with self.assertRaisesRegex(ValueError, "protection policy changed"):
                candidate.protected_paths(manifest(files))

    def test_compiled_data_requires_exact_unique_bounded_nonoverlapping_block(self):
        name = next(iter(candidate.COMPILED))
        self.assertEqual(candidate.compiled_data(resource(b"JS"), name), b"JS")
        for raw in (resource()[:-1], b"\0" * 30, resource().replace(b"DATA", b"REDI")):
            with self.assertRaises(ValueError):
                candidate.compiled_data(raw, name)
        two = struct.pack("<IHHII", 46, 12, 1, 8, 2) + \
            struct.pack("<4sII", b"DATA", 20, 3) + struct.pack("<4sII", b"DATA", 11, 3) + b"abcabc"
        with self.assertRaisesRegex(ValueError, "exactly one DATA"):
            candidate.compiled_data(two, name)
        overlap = struct.pack("<IHHII", 44, 12, 1, 8, 2) + \
            struct.pack("<4sII", b"DATA", 20, 4) + struct.pack("<4sII", b"REDI", 8, 4) + b"abcd"
        with self.assertRaisesRegex(ValueError, "overlap"):
            candidate.compiled_data(overlap, name)
        with self.assertRaises(ValueError):
            candidate.compiled_data(resource(), "panorama/scripts/unreviewed.vjs_c")

    def test_compile_receipt_sources_content_and_runtime_data_agree(self):
        with tempfile.TemporaryDirectory() as folder:
            root, content, overlay, receipt, _, pins = self.compile_fixture(Path(folder).resolve())
            with self.patched_compile(root, content, pins, receipt):
                snapshots, patches = candidate.read_compiled_inputs(receipt)
                self.assertEqual(set(patches), candidate.COMPILED)
                self.assertEqual(len(snapshots), 16)
                self.assertEqual(candidate.read_compiled_inputs(receipt, overlay)[1], patches)

    def test_receipt_byte_change_is_rejected_before_trusting_json_fields(self):
        with tempfile.TemporaryDirectory() as folder:
            root, content, _, receipt, _, pins = self.compile_fixture(Path(folder).resolve())
            with self.patched_compile(root, content, pins, receipt):
                receipt.write_bytes(receipt.read_bytes() + b" ")
                with self.assertRaisesRegex(ValueError, "receipt changed"):
                    candidate.read_compiled_inputs(receipt)

    def test_failed_partial_duplicate_or_forged_compile_association_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            root, content, _, receipt, original, pins = self.compile_fixture(Path(folder).resolve())
            invalid = []
            for key, value in (("ok", False), ("check_only", True), ("compiled_files", 4), ("scope", [])):
                row = deepcopy(original); row[key] = value; invalid.append(row)
            duplicate = deepcopy(original); duplicate["results"][-1] = duplicate["results"][0]; invalid.append(duplicate)
            association = deepcopy(original); association["results"][0]["source_sha256"] = "0" * 64; invalid.append(association)
            for value in invalid:
                receipt.write_bytes(candidate.pack.runtime.canonical_bytes(value))
                with self.patched_compile(root, content, pins, receipt):
                    with self.assertRaises(ValueError):
                        candidate.read_compiled_inputs(receipt)

    def test_changed_source_content_or_runtime_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            root, content, _, receipt, _, pins = self.compile_fixture(Path(folder).resolve())
            name = next(iter(pins))
            relative = "panorama/" + name[:-3] + ".vjs_c"
            for target in (root / ("panorama/src/" + name), content / ("panorama/" + name), root / relative):
                saved = target.read_bytes(); target.write_bytes(saved + b" ")
                with self.patched_compile(root, content, pins, receipt):
                    with self.assertRaises(ValueError):
                        candidate.read_compiled_inputs(receipt)
                target.write_bytes(saved)

    def test_pinned_compiled_digest_cannot_hide_different_data_source(self):
        with tempfile.TemporaryDirectory() as folder:
            root, content, _, receipt, doc, pins = self.compile_fixture(Path(folder).resolve())
            name = next(iter(pins)); relative = "panorama/" + name[:-3] + ".vjs_c"
            raw = resource(b"different DATA")
            (root / relative).write_bytes(raw)
            pins[name] = (pins[name][0], candidate.web.sha(raw), len(raw))
            row = next(r for r in doc["results"] if r["relative"] == name)
            row.update(runtime_sha256=pins[name][1], runtime_bytes=len(raw))
            receipt.write_bytes(candidate.pack.runtime.canonical_bytes(doc))
            with self.patched_compile(root, content, pins, receipt):
                with self.assertRaisesRegex(ValueError, "exact reviewed JS source"):
                    candidate.read_compiled_inputs(receipt)

    def test_overlay_extra_missing_and_linked_files_are_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            root, content, overlay, receipt, _, pins = self.compile_fixture(Path(folder).resolve())
            target = overlay / next(iter(candidate.COMPILED))
            extra = overlay / "unreviewed.vjs_c"; extra.write_bytes(resource())
            with self.patched_compile(root, content, pins, receipt):
                with self.assertRaisesRegex(ValueError, "exactly the five"):
                    candidate.read_compiled_inputs(receipt, overlay)
                extra.unlink(); saved = target.read_bytes(); target.unlink()
                with self.assertRaisesRegex(ValueError, "exactly the five"):
                    candidate.read_compiled_inputs(receipt, overlay)
                target.write_bytes(saved)
                linked = candidate.pack.protect_data.linked
                with patch.object(candidate.pack.protect_data, "linked", side_effect=lambda p: p == target or linked(p)):
                    with self.assertRaisesRegex(ValueError, "links are forbidden"):
                        candidate.read_compiled_inputs(receipt, overlay)

    def test_strict_lua_patch_preserves_frozen_crlf_and_rejects_ambiguous_context(self):
        name = next(iter(candidate.LUA_PINS))
        old = b"local a=1\nlocal b=2\nreturn a+b\n"
        new = old.replace(b"a=1", b"a=3")
        diff = reviewed_diff(old, new, name)
        self.assertEqual(candidate.patch_bytes(old.replace(b"\n", b"\r\n"), diff, name),
                         new.replace(b"\n", b"\r\n"))
        for raw in (old + old, old.replace(b"a=1", b"a=5")):
            with self.assertRaisesRegex(ValueError, "context absent or ambiguous"):
                candidate.patch_bytes(raw, diff, name)
        with self.assertRaisesRegex(ValueError, "Mixed newline"):
            candidate.patch_bytes(old.replace(b"\n", b"\r\n", 1), diff, name)

    def test_lua_patch_rejects_extra_file_binary_and_unreviewed_paths(self):
        name = next(iter(candidate.LUA_PINS))
        diff = reviewed_diff(b"old\n", b"new\n", name)
        for invalid in (diff + b"diff --git a/other.lua b/other.lua\n", diff + b"GIT binary patch\n"):
            with self.assertRaises(ValueError):
                candidate.patch_bytes(b"old\n", invalid, name)
        with self.assertRaises(ValueError):
            candidate.patch_bytes(b"old\n", diff, candidate.MAIN)

    def test_capture_lua_uses_pinned_diff_and_source_not_the_dirty_tree(self):
        with tempfile.TemporaryDirectory() as folder:
            root, base = Path(folder).resolve() / "source", Path(folder).resolve() / "frozen"
            pins, before, diffs, replacements = {}, {}, {}, {p: b"compiled" for p in candidate.COMPILED}
            for name in candidate.LUA_PINS:
                old, new = b"local a=1\nreturn a\n", b"local a=2\nreturn a\n"
                before[name], diffs[name] = old, reviewed_diff(old, new, name)
                pins[name] = dict(source_sha256=candidate.web.sha(new), patch_sha256=candidate.web.sha(diffs[name]))
                for path, raw in ((root / name, new), (base / name, old)):
                    path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(raw)
            with patch.object(candidate, "ROOT", root), patch.object(candidate, "LUA_PINS", pins), \
                    patch.object(candidate, "read_compiled_inputs", return_value=({}, replacements)), \
                    patch.object(candidate, "task_diff", side_effect=lambda n: diffs[n]), \
                    patch.object(candidate.web, "git", side_effect=lambda *a, **kw: before[a[1].split(":", 1)[1]]):
                captured, patches, _ = candidate.capture_inputs(base, Path("unused"))
                self.assertEqual(set(patches), candidate.ALLOWLIST)
                name = next(iter(pins)); path = root / name; original = path.read_bytes()
                path.write_bytes(original + b"-- another dirty edit\n")
                with self.assertRaisesRegex(ValueError, "source or patch changed"):
                    candidate.capture_inputs(base, Path("unused"))
                path.write_bytes(original); diff = diffs[name]; diffs[name] += b"\n"
                with self.assertRaisesRegex(ValueError, "source or patch changed"):
                    candidate.capture_inputs(base, Path("unused"))
                diffs[name] = diff; (base / name).write_bytes(b"different frozen module\n")
                with self.assertRaisesRegex(ValueError, "fixed patch baseline"):
                    candidate.capture_inputs(base, Path("unused"))

    def test_input_source_patch_or_head_drift_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder).resolve() / "input.js"; path.write_bytes(b"reviewed")
            name = next(iter(candidate.LUA_PINS))
            with patch.object(candidate, "task_diff", return_value=b"reviewed diff"), \
                    patch.object(candidate.web, "git", return_value=b"head\n"):
                candidate.require_review_unchanged({path: b"reviewed"}, {name: b"reviewed diff"}, "head")
                with self.assertRaisesRegex(ValueError, "input changed"):
                    candidate.require_review_unchanged({path: b"old"}, {}, "head")
                with self.assertRaisesRegex(ValueError, "patch changed"):
                    candidate.require_review_unchanged({}, {name: b"old diff"}, "head")
                with self.assertRaisesRegex(ValueError, "HEAD changed"):
                    candidate.require_review_unchanged({}, {}, "old-head")

    def test_base_rejects_identity_sequence_key_and_floor_changes(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder).resolve()
            for name, raw in ((candidate.RELEASE_PROFILE, b'return {channel="production"}\n'),
                              (candidate.WEB_CONFIG, b'return {enabled = true}\n')):
                path = root / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(raw)
            old = dict(content_sha256=candidate.BASE_SHA, file_count=candidate.BASE_FILES)
            sig = dict(release_sequence=candidate.BASE_SEQUENCE, key_id="test-pinned-key")
            policy = {"integrity": {"trusted_key_id": "test-pinned-key", "minimum_release_sequence": 2026102101}}
            with patch.object(candidate, "BASE", root), patch.object(candidate, "BASE_TRUSTED", root / "trusted"), \
                    patch.object(candidate.pack.handoff, "trusted_policy", return_value=(policy, None)), \
                    patch.object(candidate.pack, "authenticate", return_value=(root, old, sig, {})) as auth:
                self.assertEqual(candidate.authenticate_base(), (root, old, sig))
                for field, val in (("content_sha256", "0" * 64), ("file_count", 6629)):
                    with self.subTest(field=field), self.assertRaisesRegex(ValueError, "v05 candidate identity"):
                        auth.return_value = (root, dict(old, **{field: val}), sig, {})
                        candidate.authenticate_base()
                for field, val in (("release_sequence", 2026102404), ("key_id", "other-key")):
                    auth.return_value = (root, old, dict(sig, **{field: val}), {})
                    with self.assertRaises(ValueError): candidate.authenticate_base()
                auth.return_value = (root, old, sig, {})
                policy["integrity"]["minimum_release_sequence"] = candidate.RELEASE_SEQUENCE + 1
                with self.assertRaisesRegex(ValueError, "release floor"): candidate.authenticate_base()
                policy["integrity"]["minimum_release_sequence"] = 2026102101
                (root / candidate.WEB_CONFIG).write_bytes(b"return {enabled = false}\n")
                with self.assertRaisesRegex(ValueError, "must stay enabled"): candidate.authenticate_base()

    def test_frozen_trust_snapshot_never_uses_current_dirty_gate_bytes(self):
        with tempfile.TemporaryDirectory() as folder:
            root, trusted, out = Path(folder).resolve() / "dirty", Path(folder).resolve() / "trusted", Path(folder).resolve() / "new"
            names = (*candidate.pack.handoff.GATE_FILES, *candidate.pack.handoff.ENTRY_GATE_FILES,
                     candidate.pack.handoff.ACCESS_FILE, *candidate.web.POLICY_FILES)
            for name in names:
                for base, raw in ((root, b"dirty"), (trusted, b"authenticated frozen gate")):
                    path = base / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(raw)
            with patch.object(candidate, "ROOT", root), patch.object(candidate, "BASE_TRUSTED", trusted):
                candidate.trusted_snapshot(out)
            for name in names:
                self.assertEqual((out / name).read_bytes(), b"authenticated frozen gate")
            self.assertEqual(len([p for p in out.rglob("*") if p.is_file()]), 12)


if __name__ == "__main__":
    unittest.main()
