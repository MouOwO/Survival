"""Bounded fixtures: fixed v04, exact launcher scope and untouched frozen body."""
from contextlib import ExitStack
from copy import deepcopy
from pathlib import Path
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch
import zlib

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_workshop_entry_candidate as candidate
from test_web_auth_candidate import manifest


OLD_INFO = b'"AddonInfo" { "maps" "template_map" "IsPlayable" "1" "EnablePickRules" "0" "template_map" { "MaxPlayers" "4" } }\n'
NEW_INFO = b'"AddonInfo" { "maps" "ws4_entry" "IsPlayable" "1" "EnablePickRules" "0" "ws4_entry" { "MaxPlayers" "1" } "template_map" { "MaxPlayers" "4" } }\n'
FROZEN_MAIN = b'local frozen_gameplay = "keep-v04-mode-behavior"\nreturn frozen_gameplay\n'
DEV_MAIN = b'local development_gameplay = "must-not-replace-the-frozen-body"\nreturn development_gameplay\n'


def map_resource(files=None):
    files = files or {"maps/ws4_entry.vmap_c": b"root compiled map", "maps/ws4_entry/world.vwrld_c": b"world",
                      "maps/ws4_entry/entities/default_ents.vents_c": b"entities"}
    rows = [{"path": path, "bytes": len(raw)} for path, raw in sorted(files.items())]
    tree, ordered, total = candidate.pack.make_tree(rows)
    payload = bytearray()
    for item in ordered:
        raw = files[item["row"]["path"]]
        struct.pack_into("<I", tree, item["crc_position"], zlib.crc32(raw))
        payload.extend(raw)
    return struct.pack("<7I", 0x55AA1234, 2, len(tree), total, 0, 0, 0) + tree + payload


class WorkshopEntryCandidateTest(unittest.TestCase):
    def fixture(self):
        protected = [candidate.POLICY_MODULE] + [
            "scripts/vscripts/config/generated/entry_fixture_%03d.lua" % index for index in range(179)]
        files = {name: ("protected:" + name).encode() for name in protected}
        files.update({candidate.MAIN: FROZEN_MAIN, candidate.ADDONINFO: OLD_INFO,
                      candidate.WEB_CONFIG: b"return {enabled = true}\n",
                      "scripts/vscripts/config/release_profile.lua": b'return {channel="production"}\n',
                      "maps/template_map.vpk": b"unchanged original game map",
                      "scripts/vscripts/systems/player_web_auth.lua": b"frozen WS4-WEB-04 auth",
                      candidate.pack.handoff.ACCESS_FILE: b"unchanged four-account whitelist"})
        for index in range(candidate.BASE_FILES - len(files)):
            files["materials/entry_fixture_%04d.vmat_c" % index] = b"unchanged compiled material"
        patches = {candidate.MAIN: candidate.ENTRY_PREFIX + FROZEN_MAIN, candidate.ADDONINFO: NEW_INFO,
                   candidate.ENTRY_MODULE: b'local revision = "WS4-ENTRY-05"\nreturn {}\n',
                   candidate.CLIENT_MODULE: b'local revision = "WS4-ENTRY-05"\nreturn {}\n',
                   candidate.ENTRY_MAP: map_resource()}
        return protected, files, patches

    def sources(self, root, base, *, crlf=False):
        _, _, patches = self.fixture()
        inputs = dict(patches, **{candidate.MAIN: candidate.ENTRY_PREFIX + DEV_MAIN})
        if crlf:
            inputs[candidate.MAIN] = inputs[candidate.MAIN].replace(b"\n", b"\r\n")
        for name, raw in inputs.items():
            target = root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(raw)
        frozen = base / candidate.MAIN
        frozen.parent.mkdir(parents=True, exist_ok=True)
        frozen.write_bytes(FROZEN_MAIN)
        return inputs, patches

    def plan_mocks(self, stack, root, base, protected, files):
        stack.enter_context(patch.object(candidate, "ROOT", root))
        stack.enter_context(patch.object(candidate, "authenticate_base", return_value=(
            base, manifest(files), {"release_sequence": candidate.BASE_SEQUENCE})))
        stack.enter_context(patch.object(candidate.web, "protected_paths", return_value=protected))
        stack.enter_context(patch.object(candidate.web, "git", return_value=b"reviewed-entry-head\n"))
        stack.enter_context(patch.object(candidate.web, "output_paths", side_effect=AssertionError("unexpected output/key access")))
        stack.enter_context(patch.object(candidate.pack.protect_data, "sign_manifest", side_effect=AssertionError("test must not sign")))
        stack.enter_context(patch.object(candidate.pack, "package", side_effect=AssertionError("test must not package")))

    def test_fixed_v04_identity_and_keyless_readonly_defaults(self):
        args = candidate.parser().parse_args([])
        self.assertFalse(args.build)
        for name in ("destination", "trusted_source", "signing_key", "package_output"):
            self.assertIsNone(getattr(args, name))
        self.assertEqual(args.sequence, 2026102405)
        self.assertEqual(candidate.BASE.name, "20261024_ws4_web_auth_v04")
        self.assertEqual(candidate.BASE_SEQUENCE, 2026102404)
        self.assertEqual(candidate.BASE_SHA, "f5be8205cd107797f75c5b930224933de8c15f10e9a9e17932b3d6d747f91eb7")
        self.assertEqual(candidate.BASE_FILES, 6627)
        self.assertEqual(candidate.REVISION, "WS4-ENTRY-05")
        self.assertEqual(candidate.ENTRY_PREFIX, (
            b"-- Keep the Workshop entry independent of gameplay and cloud initialization.\n"
            b'if type(GetMapName) == "function" and GetMapName() == "ws4_entry" then\n'
            b'    local entry = require("systems/workshop_entry")\n'
            b"    function Precache() end\n"
            b"    function Activate()\n"
            b"        local ok, reason = entry.activate()\n"
            b'        if not ok then print("[WS4-ENTRY-05] server_unavailable reason=" .. tostring(reason)) end\n'
            b"    end\n"
            b"    return\nend\n\n"
        ))
        self.assertEqual(candidate.MODIFIED, {candidate.MAIN, candidate.ADDONINFO})
        self.assertEqual(candidate.ADDED, {candidate.ENTRY_MAP, candidate.ENTRY_MODULE, candidate.CLIENT_MODULE})

    def test_plan_never_reads_keys_creates_outputs_or_uses_development_gameplay_body(self):
        protected, files, _ = self.fixture()
        with tempfile.TemporaryDirectory() as folder, ExitStack() as stack:
            root, base = Path(folder).resolve() / "checkout", Path(folder).resolve() / "base"
            snapshots, _ = self.sources(root, base)
            self.plan_mocks(stack, root, base, protected, files)
            result = candidate.build(candidate.parser().parse_args([]))
            self.assertEqual(result["status"], "READ_ONLY_PLAN")
            self.assertEqual(result["expected_files"], 6630)
            self.assertEqual(result["protected_modules_preserved"], 180)
            self.assertEqual(result["sources"], {name: candidate.web.sha(raw) for name, raw in snapshots.items()})
            self.assertEqual(result["patches"][candidate.MAIN], candidate.web.sha(candidate.ENTRY_PREFIX + FROZEN_MAIN))
            self.assertNotEqual(result["sources"][candidate.MAIN], result["patches"][candidate.MAIN])
            self.assertTrue(result["frozen_main_body_preserved"])
            for name in ("development_main_body_substituted", "online_authentication_changed", "online_cheats_allowed",
                         "workshop_upload_performed", "game_started"):
                self.assertFalse(result[name])
            self.assertEqual(set(Path(folder).resolve().iterdir()), {root, base})

    def test_releases_other_than_exact_v05_fail_before_baseline_io(self):
        with patch.object(candidate, "authenticate_base", side_effect=AssertionError("unexpected baseline I/O")):
            for sequence in (2026102403, 2026102404, 2026102406):
                with self.subTest(sequence=sequence), self.assertRaisesRegex(ValueError, "fixed v05"):
                    candidate.build(candidate.parser().parse_args(["--sequence", str(sequence)]))

    def test_explicit_build_still_requires_a_key_before_output_access(self):
        protected, files, _ = self.fixture()
        with tempfile.TemporaryDirectory() as folder, ExitStack() as stack:
            root, base = Path(folder).resolve() / "checkout", Path(folder).resolve() / "base"
            self.sources(root, base)
            self.plan_mocks(stack, root, base, protected, files)
            with self.assertRaisesRegex(ValueError, "requires --signing-key"):
                candidate.build(candidate.parser().parse_args(["--build"]))

    def test_capture_prefixes_exact_frozen_bytes_and_accepts_crlf_checkout(self):
        for crlf in (False, True):
            with self.subTest(crlf=crlf), tempfile.TemporaryDirectory() as folder:
                root, base = Path(folder).resolve() / "checkout", Path(folder).resolve() / "base"
                snapshots, expected = self.sources(root, base, crlf=crlf)
                with patch.object(candidate, "ROOT", root):
                    actual, patches, review = candidate.capture_inputs(base)
                self.assertEqual(actual, snapshots)
                self.assertEqual(patches, expected)
                self.assertEqual(patches[candidate.MAIN][len(candidate.ENTRY_PREFIX):], FROZEN_MAIN)
                self.assertTrue(review["crc32_verified"])

    def test_changed_prefix_missing_marker_or_unreviewed_map_layout_are_rejected(self):
        cases = ((candidate.MAIN, b"-- missing reviewed prefix\n" + DEV_MAIN),
                 (candidate.ENTRY_MODULE, b"return {}\n"), (candidate.CLIENT_MODULE, b"old client\n"),
                 (candidate.ADDONINFO, OLD_INFO),
                 (candidate.ADDONINFO, NEW_INFO.replace(b'"MaxPlayers" "1"', b'"MaxPlayers" "2"')),
                 (candidate.ADDONINFO, NEW_INFO.replace(b'"ws4_entry" "IsPlayable"', b'"ws4_entry template_map" "IsPlayable"')),
                 (candidate.ADDONINFO, NEW_INFO + b'"unreviewed" "1"'))
        for name, invalid in cases:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as folder:
                root, base = Path(folder).resolve() / "checkout", Path(folder).resolve() / "base"
                self.sources(root, base)
                (root / name).write_bytes(invalid)
                with patch.object(candidate, "ROOT", root), self.assertRaises(ValueError):
                    candidate.capture_inputs(base)

    def test_entry_map_requires_bounded_self_contained_valid_crc_and_world_resources(self):
        valid = map_resource()
        self.assertEqual(candidate.validate_entry_map(valid), {"entries": 3, "crc32_verified": True, "external_archives": False})
        invalid = [b"not a VPK", valid[:-1], valid + b"unreviewed-tail", valid[:-1] + bytes([valid[-1] ^ 1]),
                   map_resource({"maps/other/world.vwrld_c": b"world"}),
                   map_resource({"maps/ws4_entry/world.vwrld_c": b"world"}),
                   map_resource({"maps/ws4_entry/world.vwrld_c": b"world",
                                 "maps/ws4_entry/entities/default_ents.vents_c": b"entities"}),
                   map_resource({"maps/ws4_entry/world.vwrld_c": b"world", "maps/ws4_entry/WORLD.vwrld_c": b"duplicate"})]
        external = bytearray(valid)
        _, ordered, _ = candidate.pack.make_tree([
            {"path": "maps/ws4_entry.vmap_c", "bytes": 17},
            {"path": "maps/ws4_entry/entities/default_ents.vents_c", "bytes": 8},
            {"path": "maps/ws4_entry/world.vwrld_c", "bytes": 5}])
        struct.pack_into("<H", external, 28 + ordered[0]["crc_position"] + 6, 0)
        invalid.append(bytes(external))
        for raw in invalid:
            with self.subTest(bytes=len(raw)), self.assertRaises(ValueError):
                candidate.validate_entry_map(raw)

    def test_exact_five_path_overlay_preserves_180_modules_and_6630_inventory(self):
        protected, files, patches = self.fixture()
        changed = candidate.audit_changes(manifest(files), manifest(dict(files, **patches)), patches, protected)
        self.assertEqual({row["path"] for row in changed}, candidate.ALLOWLIST)
        self.assertEqual({row["path"] for row in changed if row["before"] is None}, candidate.ADDED)
        self.assertFalse(set(protected) & {row["path"] for row in changed})

    def test_auth_policy_profile_main_map_and_unrelated_changes_are_rejected(self):
        protected, files, patches = self.fixture()
        final = dict(files, **patches)
        for name in (*protected, candidate.WEB_CONFIG, candidate.pack.handoff.ACCESS_FILE,
                     "scripts/vscripts/config/release_profile.lua", "scripts/vscripts/systems/player_web_auth.lua",
                     "maps/template_map.vpk", "materials/entry_fixture_0000.vmat_c"):
            with self.subTest(name=name), self.assertRaises(ValueError):
                candidate.audit_changes(manifest(files), manifest(dict(final, **{name: b"unreviewed"})), patches, protected)

    def test_extra_or_removed_paths_wrong_counts_and_incomplete_overlay_are_rejected(self):
        protected, files, patches = self.fixture()
        final = dict(files, **patches)
        extra, removed = dict(final, **{"scripts/vscripts/extra.lua": b"extra"}), dict(final)
        del removed["materials/entry_fixture_0000.vmat_c"]
        for invalid in (extra, removed):
            with self.assertRaises(ValueError):
                candidate.audit_changes(manifest(files), manifest(invalid), patches, protected)
        for missing in patches:
            incomplete = dict(patches)
            del incomplete[missing]
            with self.assertRaisesRegex(ValueError, "five-file allowlist"):
                candidate.audit_changes(manifest(files), manifest(final), incomplete, protected)
        bad = manifest(final)
        bad["file_count"] -= 1
        with self.assertRaisesRegex(ValueError, "exactly 6630"):
            candidate.audit_changes(manifest(files), bad, patches, protected)

    def test_main_body_replacement_after_valid_prefix_and_staging_tampering_are_rejected(self):
        protected, files, patches = self.fixture()
        replaced = dict(patches, **{candidate.MAIN: candidate.ENTRY_PREFIX + DEV_MAIN})
        with self.assertRaisesRegex(ValueError, "Frozen server entry body"):
            candidate.audit_changes(manifest(files), manifest(dict(files, **replaced)), replaced, protected)
        staged = manifest(dict(files, **patches))
        for name in patches:
            with self.subTest(name=name), self.assertRaisesRegex(ValueError, "during staging"):
                candidate.audit_changes(manifest(files), staged, dict(patches, **{name: b"altered input"}), protected)

    def test_protected_set_cannot_shrink_duplicate_or_include_new_entry_code(self):
        protected, files, patches = self.fixture()
        baseline, staged = manifest(files), manifest(dict(files, **patches))
        for invalid in (protected[:-1], protected[:-1] + [protected[0]],
                        protected[:-1] + [candidate.MAIN], protected[:-1] + [candidate.ENTRY_MODULE]):
            with self.assertRaises(ValueError):
                candidate.audit_changes(baseline, staged, patches, invalid)

    def test_trusted_snapshot_uses_frozen_old_guards_and_candidate_entry_guards(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder).resolve()
            base, destination, original_trusted, trusted = (root / name for name in ("base", "candidate", "base-trusted", "new-trusted"))
            expected = {}
            for name in (*candidate.pack.handoff.GATE_FILES, candidate.pack.handoff.ACCESS_FILE):
                target = base / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(("frozen:" + name).encode())
                expected[name] = target.read_bytes()
            for name in (candidate.MAIN, candidate.ENTRY_MODULE, candidate.CLIENT_MODULE):
                target = destination / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(("reviewed candidate:" + name).encode())
                expected[name] = target.read_bytes()
            for name in candidate.web.POLICY_FILES:
                target = original_trusted / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(("public policy fixture:" + name).encode())
                expected[name] = target.read_bytes()
            with patch.object(candidate, "BASE_TRUSTED", original_trusted):
                candidate.trusted_snapshot(destination, trusted, base)
            actual = {path.relative_to(trusted).as_posix(): path.read_bytes() for path in trusted.rglob("*") if path.is_file()}
            self.assertEqual(actual, expected)
            self.assertEqual(len(actual), 12)

    def test_source_or_head_drift_is_rejected_before_signing(self):
        with tempfile.TemporaryDirectory() as folder:
            root, base = Path(folder).resolve() / "checkout", Path(folder).resolve() / "base"
            snapshots, _ = self.sources(root, base)
            with patch.object(candidate, "ROOT", root), patch.object(candidate.web, "git", return_value=b"reviewed-head\n") as git:
                candidate.require_review_unchanged(snapshots, "reviewed-head")
                for name, raw in snapshots.items():
                    (root / name).write_bytes(b"changed input")
                    with self.assertRaisesRegex(ValueError, "input changed"):
                        candidate.require_review_unchanged(snapshots, "reviewed-head")
                    (root / name).write_bytes(raw)
                git.return_value = b"different-head\n"
                with self.assertRaisesRegex(ValueError, "HEAD changed"):
                    candidate.require_review_unchanged(snapshots, "reviewed-head")

    def test_bad_signature_stops_before_production_or_layout_checks(self):
        with patch.object(candidate.pack.handoff, "trusted_policy", return_value=({"integrity": {"trusted_key_id": "fixture"}}, None)), \
                patch.object(candidate.pack, "authenticate", side_effect=ValueError("signature invalid")), \
                patch.object(candidate.pack.runtime, "require_production", side_effect=AssertionError("unverified base")):
            with self.assertRaisesRegex(ValueError, "signature invalid"):
                candidate.authenticate_base()

    def test_base_hash_count_sequence_key_profile_and_auth_are_fixed(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder).resolve()
            for name, raw in ((candidate.WEB_CONFIG, b"return {enabled = true}\n"),
                              ("scripts/vscripts/config/release_profile.lua", b'return {channel="production"}\n')):
                target = root / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(raw)
            baseline = {"content_sha256": candidate.BASE_SHA, "file_count": candidate.BASE_FILES}
            signature = {"release_sequence": candidate.BASE_SEQUENCE, "key_id": "fixture-key"}
            with patch.object(candidate, "BASE", root), patch.object(candidate, "BASE_TRUSTED", root / "trusted"), \
                    patch.object(candidate.pack.handoff, "trusted_policy", return_value=({"integrity": {"trusted_key_id": "fixture-key"}}, None)), \
                    patch.object(candidate.pack, "authenticate", return_value=(root, baseline, signature, {})) as authenticate:
                self.assertEqual(candidate.authenticate_base(), (root, baseline, signature))
                for field, value in (("content_sha256", "0" * 64), ("file_count", 6630)):
                    altered = deepcopy(baseline)
                    altered[field] = value
                    authenticate.return_value = root, altered, signature, {}
                    with self.assertRaisesRegex(ValueError, "baseline identity"):
                        candidate.authenticate_base()
                for field, value in (("release_sequence", 2026102403), ("key_id", "different-key")):
                    altered = deepcopy(signature)
                    altered[field] = value
                    authenticate.return_value = root, baseline, altered, {}
                    with self.assertRaises(ValueError):
                        candidate.authenticate_base()
                authenticate.return_value = root, baseline, signature, {}
                (root / candidate.WEB_CONFIG).write_bytes(b"return {enabled = false}\n")
                with self.assertRaisesRegex(ValueError, "must stay enabled"):
                    candidate.authenticate_base()
                (root / candidate.WEB_CONFIG).write_bytes(b"return {enabled = true}\n")
                (root / "scripts/vscripts/config/release_profile.lua").write_bytes(b'return {channel="development"}\n')
                with self.assertRaises(ValueError):
                    candidate.authenticate_base()


if __name__ == "__main__":
    unittest.main()
