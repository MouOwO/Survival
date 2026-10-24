"""Frozen v03 identity, two-file scope, and single-resource diagnostic overlays."""
from copy import deepcopy
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_web_auth_diagnostic_candidate as candidate
from test_web_auth_candidate import manifest, resource


class WebAuthDiagnosticCandidateTest(unittest.TestCase):
    def fixture(self):
        protected = [candidate.POLICY_MODULE] + [
            "scripts/vscripts/config/generated/fixture_%03d.lua" % index for index in range(179)]
        files = {name: ("protected:" + name).encode() for name in protected}
        files.update({candidate.MODULE: b"old plaintext authorization module",
                      candidate.COMPILED: b"old compiled authorization UI",
                      candidate.RELEASE_PROFILE: b'return {channel="production"}\n',
                      candidate.WEB_CONFIG: b'return {enabled = true}\n',
                      candidate.pack.handoff.ACCESS_FILE: b"unchanged four-account admission"})
        for index in range(candidate.BASE_FILES - len(files)):
            files["materials/fixture_%04d.vmat_c" % index] = b"unchanged compiled resource"
        replacements = {candidate.MODULE: b'local revision = "WS4-WEB-04"\nreturn {}\n',
                        candidate.COMPILED: resource()}
        return protected, files, replacements

    def test_default_is_a_keyless_read_only_plan_for_exact_v04(self):
        args = candidate.parser().parse_args([])
        self.assertFalse(args.build)
        self.assertIsNone(args.signing_key)
        self.assertIsNone(args.destination)
        self.assertIsNone(args.compiled_overlay)
        self.assertEqual(args.sequence, 2026102404)
        self.assertEqual(candidate.BASE_SEQUENCE, 2026102403)
        self.assertEqual(candidate.BASE_SHA, "549750458285ba1de04436dbeaa0249f5bd587dcf6f6cb914feb84d81d0587d9")
        self.assertEqual(candidate.ALLOWLIST, {candidate.MODULE, candidate.COMPILED})

    def test_plan_never_reads_a_key_creates_outputs_or_packages(self):
        protected, files, replacements = self.fixture()
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder).resolve()
            for name, raw in ((candidate.MODULE, replacements[candidate.MODULE]),
                              (candidate.UI_SOURCE, b"// diagnostic UI source snapshot\n")):
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(raw)
            base = root / "frozen"
            with patch.object(candidate, "ROOT", root), \
                    patch.object(candidate, "authenticate_base", return_value=(base, manifest(files),
                                 {"release_sequence": candidate.BASE_SEQUENCE})), \
                    patch.object(candidate.web, "protected_paths", return_value=protected), \
                    patch.object(candidate.web, "git", return_value=b"reviewed-head\n"), \
                    patch.object(candidate.web, "output_paths", side_effect=AssertionError("plan accessed output/key paths")), \
                    patch.object(candidate, "read_overlay", side_effect=AssertionError("plan read build overlay")), \
                    patch.object(candidate.pack.protect_data, "sign_manifest", side_effect=AssertionError("plan signed")), \
                    patch.object(candidate.pack, "package", side_effect=AssertionError("plan packaged")):
                result = candidate.build(candidate.parser().parse_args([]))
            self.assertEqual(result["status"], "READ_ONLY_PLAN")
            self.assertEqual(result["protected_modules_preserved"], 180)
            self.assertEqual(result["sources"][candidate.MODULE], candidate.web.sha(replacements[candidate.MODULE]))
            self.assertFalse(result["workshop_upload_performed"])
            self.assertFalse(result["game_started"])
            self.assertFalse(base.exists())

    def test_exact_two_changes_preserve_all_6627_files_and_180_protected_modules(self):
        protected, files, replacements = self.fixture()
        result = candidate.audit_changes(manifest(files), manifest(dict(files, **replacements)), replacements, protected)
        self.assertEqual({row["path"] for row in result}, candidate.ALLOWLIST)
        self.assertNotIn(candidate.POLICY_MODULE, {row["path"] for row in result})

    def test_policy_profile_auth_admission_or_unrelated_resource_changes_are_rejected(self):
        protected, files, replacements = self.fixture()
        baseline = manifest(files)
        changed = dict(files, **replacements)
        for name in (candidate.POLICY_MODULE, protected[1], candidate.RELEASE_PROFILE, candidate.WEB_CONFIG,
                     candidate.pack.handoff.ACCESS_FILE, "materials/fixture_0000.vmat_c"):
            with self.subTest(name=name), self.assertRaises(ValueError):
                candidate.audit_changes(baseline, manifest(dict(changed, **{name: b"unreviewed replacement"})),
                                        replacements, protected)

    def test_inventory_addition_removal_and_even_matching_wrong_file_counts_are_rejected(self):
        protected, files, replacements = self.fixture()
        changed = dict(files, **replacements)
        extra = dict(changed, **{"materials/extra.vmat_c": b"extra"})
        missing = dict(changed)
        del missing["materials/fixture_0000.vmat_c"]
        for invalid in (extra, missing):
            with self.assertRaisesRegex(ValueError, "additions/removals"):
                candidate.audit_changes(manifest(files), manifest(invalid), replacements, protected)
        del files["materials/fixture_0000.vmat_c"]
        with self.assertRaisesRegex(ValueError, "exactly 6627"):
            candidate.audit_changes(manifest(files), manifest(missing), replacements, protected)

    def test_missing_change_unreviewed_patch_and_staging_tampering_are_rejected(self):
        protected, files, replacements = self.fixture()
        baseline = manifest(files)
        changed = dict(files, **replacements)
        with self.assertRaises(ValueError):
            candidate.audit_changes(baseline, manifest(dict(files, **{candidate.MODULE: replacements[candidate.MODULE]})),
                                    replacements, protected)
        with self.assertRaisesRegex(ValueError, "two-file allowlist"):
            candidate.audit_changes(baseline, manifest(changed),
                                    dict(replacements, **{candidate.POLICY_MODULE: files[candidate.POLICY_MODULE]}), protected)
        with self.assertRaisesRegex(ValueError, "during staging"):
            candidate.audit_changes(baseline, manifest(changed),
                                    dict(replacements, **{candidate.MODULE: b"different source"}), protected)

    def test_protected_set_cannot_shrink_duplicate_replace_or_include_diagnostic_files(self):
        protected, files, replacements = self.fixture()
        old, new = manifest(files), manifest(dict(files, **replacements))
        for invalid in (protected[:-1], protected[:-1] + [protected[0]],
                        protected[1:] + [candidate.MODULE], protected[:-1] + [candidate.MODULE]):
            with self.assertRaises(ValueError):
                candidate.audit_changes(old, new, replacements, invalid)

    def test_overlay_has_exactly_one_reviewed_vjs_and_valid_source2_blocks(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder).resolve()
            path = root / candidate.COMPILED
            path.parent.mkdir(parents=True)
            path.write_bytes(resource())
            self.assertEqual(candidate.read_overlay(root), {candidate.COMPILED: resource()})
            extra = root / "unreviewed.vcss_c"
            extra.write_bytes(resource())
            with self.assertRaisesRegex(ValueError, "exactly the single"):
                candidate.read_overlay(root)
            extra.unlink()
            path.write_bytes(resource()[:-1])
            with self.assertRaises(ValueError):
                candidate.read_overlay(root)
            path.unlink()
            with self.assertRaisesRegex(ValueError, "exactly the single"):
                candidate.read_overlay(root)

    def test_overlay_link_is_rejected_without_following_it(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder).resolve()
            target = root / candidate.COMPILED
            target.parent.mkdir(parents=True)
            target.write_bytes(resource())
            original = candidate.pack.protect_data.linked
            with patch.object(candidate.pack.protect_data, "linked",
                              side_effect=lambda path: path == target or original(path)):
                with self.assertRaisesRegex(ValueError, "links are forbidden"):
                    candidate.read_overlay(root)

    def test_base_identity_sequence_and_checkout_key_pin_are_fixed(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder).resolve()
            for name, raw in ((candidate.RELEASE_PROFILE, b'return {channel="production"}\n'),
                              (candidate.WEB_CONFIG, b'return {enabled = true}\n')):
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(raw)
            baseline = {"content_sha256": candidate.BASE_SHA, "file_count": candidate.BASE_FILES}
            signature = {"release_sequence": candidate.BASE_SEQUENCE, "key_id": "pinned-test-key"}
            with patch.object(candidate, "BASE", root), patch.object(candidate, "BASE_TRUSTED", root / "trusted"), \
                    patch.object(candidate.pack.handoff, "trusted_policy",
                                 return_value=({"integrity": {"trusted_key_id": "pinned-test-key"}}, None)), \
                    patch.object(candidate.pack, "authenticate", return_value=(root, baseline, signature, {})) as authenticate:
                self.assertEqual(candidate.authenticate_base(), (root, baseline, signature))
                for field, value in (("content_sha256", "0" * 64), ("file_count", 6626)):
                    invalid = deepcopy(baseline)
                    invalid[field] = value
                    authenticate.return_value = (root, invalid, signature, {})
                    with self.assertRaisesRegex(ValueError, "v03 candidate identity"):
                        candidate.authenticate_base()
                for field, value in (("release_sequence", 2026102402), ("key_id", "untrusted-key")):
                    invalid = deepcopy(signature)
                    invalid[field] = value
                    authenticate.return_value = (root, baseline, invalid, {})
                    with self.assertRaises(ValueError):
                        candidate.authenticate_base()
                authenticate.return_value = (root, baseline, signature, {})
                (root / candidate.WEB_CONFIG).write_bytes(b"return {enabled = false}\n")
                with self.assertRaisesRegex(ValueError, "must stay enabled"):
                    candidate.authenticate_base()

    def test_non_v04_sequence_fails_before_authentication_or_any_output(self):
        with patch.object(candidate, "authenticate_base", side_effect=AssertionError("unexpected baseline I/O")):
            for sequence in (2026102403, 2026102405):
                args = candidate.parser().parse_args(["--sequence", str(sequence)])
                with self.assertRaisesRegex(ValueError, "fixed v04"):
                    candidate.build(args)


if __name__ == "__main__":
    unittest.main()
