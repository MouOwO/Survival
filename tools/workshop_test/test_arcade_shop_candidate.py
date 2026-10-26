"""Synthetic SHOP01 isolation tests; never sign, package, publish or run Dota."""
from contextlib import ExitStack
from copy import deepcopy
import json
from pathlib import Path
import shutil
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_arcade_shop_candidate as candidate
from test_web_auth_candidate import manifest


def resource(data):
    return struct.pack("<IHHII4sII", 28 + len(data), 12, 1, 8, 1, b"DATA", 8, len(data)) + data


class ShopCandidateTests(unittest.TestCase):
    def runtime_fixture(self):
        policy = candidate.pack.handoff.load_json(candidate.ROOT / "tools/lua_protection_policy.json")
        protected = list(policy["business_modules"]) + [policy["generated_prefix"] + "fixture_%03d.lua" % i for i in range(176)]
        files = {name: ("protected:" + name).encode() for name in protected}
        files.update({name: resource(("frozen:" + name).encode()) for name in candidate.MODIFIED})
        files.update({"maps/template_map.vpk": b"unchanged game map", "addoninfo.txt": b"unchanged four-player layout",
                      "scripts/vscripts/config/session_multiplayer_test.lua": b"unchanged enabled memory provider",
                      "scripts/vscripts/config/player_web_auth.lua": b"unchanged disabled cloud authentication",
                      "scripts/vscripts/config/release_profile.lua": b"unchanged production profile",
                      "panorama/layout/custom_game/custom_ui_manifest.vxml_c": resource(b"unchanged manifest")})
        files.update({"materials/fixture_%04d.vmat_c" % i: b"frozen art" for i in range(candidate.BASE_FILES - len(files))})
        patches = {name: resource(("reviewed:" + name).encode()) for name in candidate.ALLOWLIST}
        pins = {"scripts/custom_game/source_%d.js" % i: ("a" * 64, name, candidate.web.sha(raw), len(raw))
                for i, (name, raw) in enumerate(sorted(patches.items()))}
        return files, patches, protected, pins

    def compile_fixture(self):
        files, pins, records = {}, {}, []
        data = dict(schema_version=1, checkout_enabled=False, products=[{} for _ in range(173)],
                    catalog_sha256=candidate.CATALOG_SHA)
        for source, (_, compiled, _, _) in candidate.PINS.items():
            raw = candidate.public_shop.javascript(data, "panorama") if source == candidate.CATALOG_SOURCE else ("reviewed " + source).encode()
            runtime = resource(raw)
            pins[source] = (candidate.web.sha(raw), compiled, candidate.web.sha(runtime), len(runtime))
            files[candidate.ROOT / "panorama/src" / source] = raw
            files[candidate.CONTENT / "panorama" / source] = raw
            files[candidate.ROOT / compiled] = runtime
            log = candidate.COMPILE_LOG_DIRECTORY / (Path(source).name + ".log")
            files[log] = b"OK: 1 compiled, 0 failed, 0 skipped"
            records.append(dict(source="panorama/src/" + source, source_sha256=pins[source][0], compiled=compiled,
                                compiled_sha256=pins[source][2], compiled_bytes=len(runtime), log=str(log)))
        receipt = dict(ok=True, kind="WS4_SHOP_NATIVE_COMPILE", original_102_bytes_preserved=True, records=records)
        files[candidate.COMPILE_REPORT] = json.dumps(receipt).encode()
        for name in ("tools/workshop_test/build_public_shop_catalog.py", "server/payment_backend/csv_catalog.py",
                     "server/payment_backend/commerce_bundles.py", "server/payment_backend/ucoin_catalog.py"):
            files[candidate.ROOT / name] = b"reviewed compiler fixture"
        return files, pins, receipt, data

    def fake_read(self, files):
        def read(path, snapshots):
            raw = files[path]
            snapshots[path] = raw
            return raw
        return patch.object(candidate, "read_input", side_effect=read)

    def capture_context(self, files, pins, data):
        stack = ExitStack()
        stack.enter_context(self.fake_read(files))
        stack.enter_context(patch.object(candidate, "PINS", pins))
        stack.enter_context(patch.object(candidate, "COMPILE_REPORT_SHA", candidate.web.sha(files[candidate.COMPILE_REPORT])))
        stack.enter_context(patch.object(candidate.public_shop, "catalog", return_value=data))
        stack.enter_context(patch.object(candidate.public_shop, "build", return_value=dict(reference_hashes={}, tables={}, commerce_tables={})))
        return stack

    def test_fixed_identity_and_four_resource_scope(self):
        args = candidate.parser().parse_args([])
        self.assertFalse(args.build)
        self.assertIsNone(args.signing_key)
        self.assertEqual(candidate.REVISION, "WS4-SHOP-01")
        self.assertEqual(args.sequence, 2026102603)
        self.assertEqual(candidate.BASE_SHA, "d76cffd911f1680922b2ed91e244ea2179f6527d71c89c9d13c920ba13967161")
        self.assertEqual((candidate.BASE_FILES, candidate.BASE_SEQUENCE, candidate.EXPECTED_FILES), (6636, 2026102507, 6637))
        self.assertEqual((len(candidate.MODIFIED), len(candidate.ADDED)), (3, 1))
        self.assertTrue(all(name.startswith("panorama/") for name in candidate.ALLOWLIST))
        candidate.require_review_pins()

    def test_missing_review_pin_or_wrong_args_fail_before_baseline_and_key_io(self):
        with patch.object(candidate, "authenticate_base", side_effect=AssertionError("baseline accessed")), \
                patch.object(candidate.web, "output_paths", side_effect=AssertionError("private key accessed")):
            with patch.object(candidate, "COMPILE_REPORT_SHA", None), self.assertRaisesRegex(ValueError, "pins are not finalized"):
                candidate.build(candidate.parser().parse_args([]))
            for arguments in (["--sequence", "2026102507"], ["--build"],
                              ["--resume-staged"],
                              ["--build", "--destination", str(candidate.BASE), "--trusted-source", str(candidate.BASE_TRUSTED)],
                              ["--build", "--destination", str(candidate.DESTINATION), "--trusted-source", str(candidate.TRUSTED_DESTINATION),
                               "--package-output", "elsewhere", "--signing-key", "not-read"],
                              ["--build", "--destination", str(candidate.DESTINATION), "--trusted-source", str(candidate.TRUSTED_DESTINATION)]):
                with self.subTest(arguments=arguments), self.assertRaises(ValueError):
                    candidate.build(candidate.parser().parse_args(arguments))

    def test_read_only_plan_never_writes_or_reads_key_even_when_argument_supplied(self):
        files, patches, protected, pins = self.runtime_fixture()
        baseline = manifest(files)
        with ExitStack() as stack:
            stack.enter_context(patch.object(candidate, "PINS", pins))
            stack.enter_context(patch.object(candidate, "authenticate_base", return_value=(Path("frozen-base"), baseline,
                dict(key_id="public-key-id", release_sequence=candidate.BASE_SEQUENCE), {})))
            stack.enter_context(patch.object(candidate, "protected_paths", return_value=protected))
            stack.enter_context(patch.object(candidate, "capture_inputs", return_value=({}, patches)))
            stack.enter_context(patch.object(candidate, "trust_inputs", return_value={}))
            stack.enter_context(patch.object(candidate, "require_review_unchanged"))
            stack.enter_context(patch.object(candidate.web, "git", return_value=b"fixture-head\n"))
            stack.enter_context(patch.object(candidate.web, "output_paths", side_effect=AssertionError("key/output access")))
            stack.enter_context(patch.object(Path, "mkdir", side_effect=AssertionError("directory write")))
            stack.enter_context(patch.object(Path, "write_bytes", side_effect=AssertionError("file write")))
            stack.enter_context(patch.object(candidate.pack.runtime, "atomic_write_json", side_effect=AssertionError("report write")))
            stack.enter_context(patch.object(candidate.pack.protect_data, "sign_manifest", side_effect=AssertionError("signing")))
            stack.enter_context(patch.object(candidate.pack, "package", side_effect=AssertionError("VPK packaging")))
            stack.enter_context(patch.object(candidate, "stage_runtime", side_effect=AssertionError("runtime staging")))
            result = candidate.build(candidate.parser().parse_args(["--signing-key", "DO-NOT-READ.pem", "--package-output", "DO-NOT-CREATE"]))
        self.assertEqual(result["status"], "READ_ONLY_PLAN")
        self.assertEqual(result["protected_modules_preserved"], 180)
        self.assertEqual(result["expected_files"], 6637)
        self.assertFalse(result["real_money_payments"])
        self.assertFalse(result["game_started"])
        self.assertFalse(result["workshop_upload_performed"])

    def test_projection_preserves_every_nonpatch_record_and_all_180_protected_modules(self):
        files, patches, protected, pins = self.runtime_fixture()
        baseline = manifest(files)
        with patch.object(candidate, "PINS", pins):
            projected = candidate.projected_manifest(baseline, patches)
            changes = candidate.audit_changes(baseline, projected, patches, protected)
        self.assertEqual({row["path"] for row in changes}, candidate.ALLOWLIST)
        before = {row["path"]: row for row in baseline["files"]}
        after = {row["path"]: row for row in projected["files"]}
        self.assertTrue(all(before[name] == after[name] for name in before if name not in candidate.MODIFIED))
        self.assertEqual(len(candidate.protected_paths(baseline)), 180)

    def test_foreign_lua_map_profile_manifest_art_addition_removal_all_fail_closed(self):
        files, patches, protected, pins = self.runtime_fixture()
        for name in (protected[0], "maps/template_map.vpk", "scripts/vscripts/config/session_multiplayer_test.lua",
                     "scripts/vscripts/config/player_web_auth.lua", "scripts/vscripts/config/release_profile.lua",
                     "panorama/layout/custom_game/custom_ui_manifest.vxml_c", "materials/fixture_0000.vmat_c"):
            changed = dict(files, **patches)
            changed[name] = b"foreign bytes must not enter candidate"
            with self.subTest(name=name), patch.object(candidate, "PINS", pins), self.assertRaises(ValueError):
                candidate.audit_changes(manifest(files), manifest(changed), patches, protected)
        for change in (lambda f: f.update({"scripts/vscripts/foreign.lua": b"foreign"}),
                       lambda f: f.pop("maps/template_map.vpk"),
                       lambda f: f.pop(next(iter(candidate.ADDED)))):
            changed = dict(files, **patches)
            change(changed)
            with patch.object(candidate, "PINS", pins), self.assertRaises(ValueError):
                candidate.audit_changes(manifest(files), manifest(changed), patches, protected)

    def test_missing_modified_resource_unreviewed_patch_and_stale_pin_fail_closed(self):
        files, patches, protected, pins = self.runtime_fixture()
        changed = dict(files, **patches)
        changed[next(iter(candidate.MODIFIED))] = files[next(iter(candidate.MODIFIED))]
        with patch.object(candidate, "PINS", pins), self.assertRaises(ValueError):
            candidate.audit_changes(manifest(files), manifest(changed), patches, protected)
        with self.assertRaisesRegex(ValueError, "overlay scope"):
            candidate.projected_manifest(manifest(files), dict(patches, **{"scripts/vscripts/not_allowed.lua": b"bad"}))
        broken = deepcopy(pins)
        name = next(iter(broken))
        broken[name] = (broken[name][0], broken[name][1], "f" * 64, broken[name][3])
        with patch.object(candidate, "PINS", broken), self.assertRaisesRegex(ValueError, "patch bytes"):
            candidate.audit_changes(manifest(files), manifest(dict(files, **patches)), patches, protected)

    def test_compile_capture_binds_four_game_content_and_runtime_resources(self):
        files, pins, _, data = self.compile_fixture()
        with self.capture_context(files, pins, data):
            snapshots, patches = candidate.capture_inputs()
        self.assertEqual(set(patches), candidate.ALLOWLIST)
        self.assertTrue(all(candidate.ROOT / "panorama/src" / name in snapshots for name in pins))
        self.assertTrue(all(candidate.CONTENT / "panorama" / name in snapshots for name in pins))

    def test_compile_receipt_duplicates_paths_hashes_mirrors_or_log_failure_rejected(self):
        for mutation in (lambda f, p, r, d: r["records"].append(deepcopy(r["records"][0])),
                         lambda f, p, r, d: r["records"][0].update(source="panorama/src/../foreign.js"),
                         lambda f, p, r, d: r["records"][0].update(compiled="scripts/vscripts/injected.lua"),
                         lambda f, p, r, d: r["records"][0].update(compiled_sha256="f" * 64),
                         lambda f, p, r, d: r["records"][0].update(log="../wrong.log"),
                         lambda f, p, r, d: r.update(original_102_bytes_preserved=False),
                         lambda f, p, r, d: f.update({candidate.CONTENT / "panorama" / next(iter(p)): b"mirror changed"}),
                         lambda f, p, r, d: f.update({candidate.COMPILE_LOG_DIRECTORY / (Path(next(iter(p))).name + ".log"): b"1 compiled, 1 failed"})):
            files, pins, receipt, data = self.compile_fixture()
            mutation(files, pins, receipt, data)
            files[candidate.COMPILE_REPORT] = json.dumps(receipt).encode()
            with self.subTest(mutation=mutation), self.capture_context(files, pins, data), self.assertRaises(ValueError):
                candidate.capture_inputs()

    def test_compiled_js_data_must_equal_source_even_with_matching_new_runtime_pins(self):
        files, pins, receipt, data = self.compile_fixture()
        source = next(name for name in pins if name.endswith(".js"))
        source_sha, compiled, _, _ = pins[source]
        bad = resource(b"different executable JS")
        files[candidate.ROOT / compiled] = bad
        pins[source] = (source_sha, compiled, candidate.web.sha(bad), len(bad))
        next(row for row in receipt["records"] if row["source"] == "panorama/src/" + source).update(
            compiled_sha256=candidate.web.sha(bad), compiled_bytes=len(bad))
        files[candidate.COMPILE_REPORT] = json.dumps(receipt).encode()
        with self.capture_context(files, pins, data), self.assertRaisesRegex(ValueError, "JS DATA"):
            candidate.capture_inputs()

    def test_formal_catalog_drift_or_enabling_checkout_rejected(self):
        for mutation in (lambda d: d.update(catalog_sha256="f" * 64),
                         lambda d: d.update(checkout_enabled=True), lambda d: d["products"].pop()):
            files, pins, _, data = self.compile_fixture()
            mutation(data)
            with self.capture_context(files, pins, data), self.assertRaisesRegex(ValueError, "formal catalog"):
                candidate.capture_inputs()

    def test_staging_copies_manifest_only_and_never_private_metadata_or_foreign_files(self):
        with tempfile.TemporaryDirectory(prefix="shop01-stage-fixture-") as folder:
            root = Path(folder).resolve()
            base, destination = root / "base", root / "new"
            files = {name: b"frozen resource" for name in candidate.MODIFIED}
            files["maps/template_map.vpk"] = b"map bytes"
            for name, raw in dict(files, **{"_private_key.pem": b"NEVER COPY", "output/debug.log": b"NEVER COPY"}).items():
                target = base / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(raw)
            patches = {name: b"reviewed resource" for name in candidate.ALLOWLIST}
            candidate.stage_runtime(base, destination, manifest(files), patches)
            actual = {file.relative_to(destination).as_posix(): file.read_bytes() for file in destination.rglob("*") if file.is_file()}
            self.assertEqual(actual, dict(files, **patches))
            self.assertEqual((base / "_private_key.pem").read_bytes(), b"NEVER COPY")
            with self.assertRaises(FileExistsError):
                candidate.stage_runtime(base, destination, manifest(files), patches)

    def test_trusted_snapshot_copies_only_original_whitelist_and_preserves_bytes(self):
        with tempfile.TemporaryDirectory(prefix="shop01-trust-fixture-") as folder:
            root = Path(folder).resolve()
            original, destination = root / "old_trust", root / "new_trust"
            names = ("scripts/vscripts/gate.lua", "tools/security/policy.json", "tools/security/public.pem")
            for name in (*names, "private.pem", "output/debug.log"):
                target = original / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(("original:" + name).encode())
            with patch.object(candidate, "BASE_TRUSTED", original), patch.object(candidate, "trust_names", return_value=names):
                candidate.trusted_snapshot(destination)
            actual = {file.relative_to(destination).as_posix(): file.read_bytes() for file in destination.rglob("*") if file.is_file()}
            self.assertEqual(set(actual), set(names))
            self.assertTrue(all(raw == (original / name).read_bytes() for name, raw in actual.items()))

    def test_disk_reserve_includes_optional_package_and_rejects_before_copy(self):
        with tempfile.TemporaryDirectory(prefix="shop01-space-fixture-") as folder:
            destination = Path(folder).resolve() / "new"
            for package, free, allowed in ((None, candidate.SPACE_RESERVE + 100, True),
                                           (None, candidate.SPACE_RESERVE + 99, False),
                                           (Path("package"), candidate.SPACE_RESERVE + 199, False),
                                           (Path("package"), candidate.SPACE_RESERVE + 200, True)):
                with self.subTest(package=package, free=free), patch.object(candidate.shutil, "disk_usage", return_value=shutil._ntuple_diskusage(free, 0, free)):
                    if allowed:
                        candidate.require_space(destination, {"bytes": 100}, package)
                    else:
                        with self.assertRaisesRegex(ValueError, "Insufficient free space"):
                            candidate.require_space(destination, {"bytes": 100}, package)
            for package, free, allowed in ((None, candidate.SPACE_RESERVE, True),
                                           (None, candidate.SPACE_RESERVE - 1, False),
                                           (Path("package"), candidate.SPACE_RESERVE + 99, False),
                                           (Path("package"), candidate.SPACE_RESERVE + 100, True)):
                with self.subTest(resume=True, package=package, free=free), patch.object(candidate.shutil, "disk_usage", return_value=shutil._ntuple_diskusage(free, 0, free)):
                    if allowed:
                        candidate.require_space(destination, {"bytes": 100}, package, resume=True)
                    else:
                        with self.assertRaisesRegex(ValueError, "Insufficient free space"):
                            candidate.require_space(destination, {"bytes": 100}, package, resume=True)

    def test_real_runtime_metadata_is_not_part_of_signed_projection_comparison(self):
        with tempfile.TemporaryDirectory(prefix="shop01-real-metadata-") as folder:
            destination = Path(folder).resolve() / "unsigned"
            projected = self.small_unsigned_stage(destination)
            actual = candidate.pack.runtime.manifest(destination, check_critical=False)
            self.assertNotEqual(actual, projected)
            self.assertIn("source_root", actual)
            self.assertIn("excluded_runtime_tree_files", actual)
            candidate.require_projection(actual, projected)
            changed = {row["path"]: (destination / row["path"]).read_bytes() for row in projected["files"]}
            changed["materials/fixture.vmat_c"] = b"different runtime bytes"
            with self.assertRaisesRegex(ValueError, "read-only projection"):
                candidate.require_projection(manifest(changed), projected)

    def small_unsigned_stage(self, destination):
        files = {"addoninfo.txt": b'"AddonInfo" { "maps" "template_map" }\n',
                 "scripts/custom_net_tables.txt": b"{}\n", "maps/template_map.vpk": b"frozen fixture map",
                 "scripts/vscripts/config/release_profile.lua": b'return { channel = "production" }\n',
                 "materials/fixture.vmat_c": b"real fixture resource bytes"}
        for name, raw in files.items():
            target = destination / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(raw)
        return manifest(files)

    def test_resume_verifies_real_unsigned_stage_hashes_without_writing_or_copying(self):
        with tempfile.TemporaryDirectory(prefix="shop01-resume-valid-") as folder:
            destination = Path(folder).resolve() / "unsigned"
            projected = self.small_unsigned_stage(destination)
            real_manifest = candidate.pack.runtime.manifest
            before = {file.relative_to(destination).as_posix(): file.read_bytes() for file in destination.rglob("*") if file.is_file()}
            with patch.object(candidate.pack.runtime, "manifest", side_effect=lambda root: real_manifest(root, check_critical=False)), \
                    patch.object(candidate, "stage_runtime", side_effect=AssertionError("resume copied runtime")), \
                    patch.object(Path, "write_bytes", side_effect=AssertionError("resume wrote runtime")):
                actual = candidate.verify_unsigned_stage(destination, projected)
            self.assertEqual(actual["content_sha256"], projected["content_sha256"])
            self.assertEqual(before, {file.relative_to(destination).as_posix(): file.read_bytes() for file in destination.rglob("*") if file.is_file()})

    def test_resume_rejects_missing_changed_extra_metadata_provenance_and_empty_extra_directory(self):
        for name in ("missing", "changed", "README.txt", candidate.pack.handoff.MANIFEST,
                     candidate.pack.handoff.SIGNATURE, "_arcade_shop_provenance.json", "empty_directory"):
            with self.subTest(name=name), tempfile.TemporaryDirectory(prefix="shop01-resume-invalid-") as folder:
                destination = Path(folder).resolve() / "unsigned"
                projected = self.small_unsigned_stage(destination)
                if name == "missing":
                    (destination / "materials/fixture.vmat_c").unlink()
                elif name == "changed":
                    (destination / "materials/fixture.vmat_c").write_bytes(b"changed existing bytes")
                elif name == "empty_directory":
                    (destination / name).mkdir()
                else:
                    (destination / name).write_bytes(b"must never be accepted or overwritten")
                real_manifest = candidate.pack.runtime.manifest
                with patch.object(candidate.pack.runtime, "manifest", side_effect=lambda root: real_manifest(root, check_critical=False)), self.assertRaises(ValueError):
                    candidate.verify_unsigned_stage(destination, projected)

    def test_resume_rejects_directory_and_file_link_markers_before_hashing(self):
        for linked_name in ("materials", "materials/fixture.vmat_c"):
            with self.subTest(name=linked_name), tempfile.TemporaryDirectory(prefix="shop01-resume-linked-") as folder:
                destination = Path(folder).resolve() / "unsigned"
                projected = self.small_unsigned_stage(destination)
                original = candidate.pack.protect_data.linked
                with patch.object(candidate.pack.protect_data, "linked", side_effect=lambda value: Path(value) == destination / linked_name or original(value)), \
                        patch.object(candidate.pack.runtime, "manifest", side_effect=AssertionError("linked stage reached hashing")), self.assertRaises(ValueError):
                    candidate.verify_unsigned_stage(destination, projected)

    def test_resume_output_paths_require_new_trusted_and_package_without_reading_key(self):
        for existing in (None, "trusted", "package"):
            with self.subTest(existing=existing), tempfile.TemporaryDirectory(prefix="shop01-resume-paths-") as folder:
                root = Path(folder).resolve()
                destination, trusted, package, key = root / "unsigned", root / "trusted", root / "package", root / "keys/signing.pem"
                destination.mkdir()
                key.parent.mkdir()
                key.write_bytes(b"synthetic placeholder; never parsed")
                if existing == "trusted":
                    trusted.mkdir()
                if existing == "package":
                    package.mkdir()
                args = candidate.parser().parse_args(["--build", "--resume-staged", "--destination", str(destination),
                    "--trusted-source", str(trusted), "--package-output", str(package), "--signing-key", str(key)])
                with patch.object(Path, "read_bytes", side_effect=AssertionError("resume path validation read private key")):
                    if existing:
                        with self.assertRaisesRegex(ValueError, "output already exists"):
                            candidate.resume_output_paths(args, root / "base")
                    else:
                        self.assertEqual(candidate.resume_output_paths(args, root / "base"), (destination, trusted, package, key))

    def test_resume_build_routes_to_validation_without_copy_or_existing_output_flow(self):
        files, patches, protected, pins = self.runtime_fixture()
        baseline = manifest(files)
        projected = candidate.projected_manifest(baseline, patches)
        actual = dict(projected, source_root="synthetic unsigned stage", excluded_runtime_tree_files=[])

        class ReachedNewTrustedDirectory(Exception):
            pass

        with ExitStack() as stack:
            stack.enter_context(patch.object(candidate, "PINS", pins))
            stack.enter_context(patch.object(candidate, "authenticate_base", return_value=(Path("base"), baseline,
                dict(key_id="public-key-id", release_sequence=candidate.BASE_SEQUENCE), {})))
            stack.enter_context(patch.object(candidate, "protected_paths", return_value=protected))
            stack.enter_context(patch.object(candidate, "capture_inputs", return_value=({}, patches)))
            stack.enter_context(patch.object(candidate, "trust_inputs", return_value={}))
            stack.enter_context(patch.object(candidate, "require_review_unchanged"))
            stack.enter_context(patch.object(candidate.web, "git", return_value=b"fixture-head\n"))
            stack.enter_context(patch.object(candidate.web, "output_paths", side_effect=AssertionError("default output flow used")))
            stack.enter_context(patch.object(candidate, "resume_output_paths", return_value=(candidate.DESTINATION, candidate.TRUSTED_DESTINATION, None, Path("synthetic-key"))))
            space = stack.enter_context(patch.object(candidate, "require_space"))
            verify = stack.enter_context(patch.object(candidate, "verify_unsigned_stage", return_value=actual))
            inventory = stack.enter_context(patch.object(candidate, "unsigned_inventory"))
            stack.enter_context(patch.object(candidate, "stage_runtime", side_effect=AssertionError("resume copied runtime")))
            stack.enter_context(patch.object(candidate.pack.runtime, "require_production"))
            stack.enter_context(patch.object(candidate.pack.handoff, "require_single_map"))
            stack.enter_context(patch.object(candidate.pack.handoff, "configured_ids", return_value=["four", "fixed", "test", "accounts"]))
            stack.enter_context(patch.object(candidate.frozen.previous, "require_base_unchanged"))
            stack.enter_context(patch.object(candidate, "trusted_snapshot", side_effect=ReachedNewTrustedDirectory))
            stack.enter_context(patch.object(candidate.pack.protect_data, "sign_manifest", side_effect=AssertionError("real signing attempted")))
            with self.assertRaises(ReachedNewTrustedDirectory):
                candidate.build(candidate.parser().parse_args(["--build", "--resume-staged", "--destination", str(candidate.DESTINATION),
                    "--trusted-source", str(candidate.TRUSTED_DESTINATION), "--signing-key", "synthetic-never-read"]))
            space.assert_called_once_with(candidate.DESTINATION, projected, None, resume=True)
            verify.assert_called_once_with(candidate.DESTINATION, projected)
            inventory.assert_called_once_with(candidate.DESTINATION, projected)

    def test_reviewed_bytes_or_head_change_is_rejected(self):
        with tempfile.TemporaryDirectory(prefix="shop01-input-fixture-") as folder:
            path = Path(folder).resolve() / "input.js"
            path.write_bytes(b"reviewed")
            with patch.object(candidate.web, "git", return_value=b"same-head\n"):
                candidate.require_review_unchanged({path: b"reviewed"}, "same-head")
                with self.assertRaises(ValueError):
                    candidate.require_review_unchanged({path: b"changed"}, "same-head")
                with self.assertRaises(ValueError):
                    candidate.require_review_unchanged({path: b"reviewed"}, "changed-head")


if __name__ == "__main__":
    unittest.main(verbosity=2)
