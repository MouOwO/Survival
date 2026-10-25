"""Synthetic scoped-package tests; no real release output, key or Steam access."""
from contextlib import ExitStack, contextmanager
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import package_ui_stackable_v08 as scoped
import test_ui_stackable_candidate as candidate_tests
from test_web_auth_candidate import manifest


@contextmanager
def trust_fixture():
    with tempfile.TemporaryDirectory() as folder, ExitStack() as stack:
        stack.enter_context(patch.object(scoped, "CANDIDATE_SHA", "a" * 64))
        stack.enter_context(patch.object(scoped.builder, "require_review_pins"))
        root = Path(folder).resolve()
        dirs = {name: root / name for name in ("checkout", "old_trust", "new_trust", "base", "candidate", "output")}
        for path in dirs.values(): path.mkdir()
        pins = {}
        for name in scoped.TRUST_PINS:
            raw = ("reviewed:" + name).encode()
            pins[name] = scoped.web.sha(raw)
            targets = ("old_trust", "new_trust", "checkout") if name in scoped.web.POLICY_FILES else (
                "old_trust", "new_trust", "base", "candidate")
            for target in targets:
                path = dirs[target] / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(raw)
        for obj, name, value in ((scoped, "ROOT", dirs["checkout"]),
                                  (scoped, "TRUSTED", dirs["new_trust"]),
                                  (scoped, "CANDIDATE", dirs["candidate"]),
                                  (scoped, "OUTPUT", dirs["output"]),
                                  (scoped, "TRUST_PINS", pins),
                                  (scoped.builder, "BASE", dirs["base"]),
                                  (scoped.builder, "BASE_TRUSTED", dirs["old_trust"])):
            stack.enter_context(patch.object(obj, name, value))
        yield dirs


@contextmanager
def release_fixture():
    protected, before, replacements = candidate_tests.StackableCandidateTest().fixture()
    after = dict(before, **replacements)
    old, new = manifest(before), manifest(after)
    # Identity pins are independent of the synthetic inventory's aggregate.
    old["content_sha256"] = scoped.BASE_SHA
    new["content_sha256"] = scoped.CANDIDATE_SHA
    oldsig = dict(key_id="synthetic-public-key", release_sequence=2026102502, signature_valid=True)
    sig = dict(key_id="synthetic-public-key", release_sequence=2026102503, signature_valid=True)
    with ExitStack() as stack:
        stack.enter_context(patch.object(scoped, "require_release_pins"))
        stack.enter_context(patch.object(scoped, "snapshot_trust", return_value={}))
        stack.enter_context(patch.object(scoped.builder, "authenticate_base", return_value=(Path("base"), old, oldsig)))
        auth = stack.enter_context(patch.object(scoped.pack, "authenticate", return_value=(scoped.CANDIDATE, new, sig, {})))
        stack.enter_context(patch.object(scoped.builder, "protected_paths", return_value=protected))
        stack.enter_context(patch.object(scoped.builder, "capture_inputs", return_value=({}, replacements)))
        stack.enter_context(patch.object(scoped.pack.runtime, "require_production"))
        ids = stack.enter_context(patch.object(scoped.pack.handoff, "configured_ids", return_value=["1", "2", "3", "4"]))
        yield old, new, oldsig, sig, replacements, protected, auth, ids


class StackablePackageTest(unittest.TestCase):
    def test_pending_receipt_or_candidate_pins_fail_before_any_output_or_candidate_io(self):
        with patch.object(scoped.pack.handoff, "regular_path", side_effect=AssertionError("external IO")), \
                patch.object(scoped.builder, "COMPILE_REPORT_SHA", None):
            for build in (False, True):
                with self.assertRaisesRegex(ValueError, "not finalized"):
                    scoped.package(build=build)
        with patch.object(scoped.builder, "require_review_pins"), \
                patch.object(scoped, "CANDIDATE_SHA", None), \
                patch.object(scoped.pack.handoff, "regular_path", side_effect=AssertionError("external IO")):
            with self.assertRaisesRegex(ValueError, "candidate_not_pinned"):
                scoped.package()

    def test_fixed_release_scope_and_no_publish_or_key_arguments(self):
        self.assertEqual(scoped.BASE_SHA, "811170a2c77396faee948bf7a77021fe8ac07c2117a919a6c3eb7163e4525e7e")
        self.assertEqual(scoped.WORKSHOP_ID, "3824360109")
        self.assertEqual(len(scoped.ALLOWLIST), 3)
        self.assertEqual(scoped.ALLOWLIST, scoped.builder.ALLOWLIST)
        self.assertEqual(len(scoped.trust_names()), 12)
        self.assertTrue(all("private" not in name and "secret" not in name for name in scoped.TRUST_PINS))

    def test_complete_trust_inventory_is_pinned_to_old_new_and_checkout(self):
        with trust_fixture() as dirs:
            snapshots = scoped.snapshot_trust()
            self.assertEqual(len(snapshots), 46)
            scoped.unchanged(snapshots)
            changed = dirs["new_trust"] / scoped.pack.handoff.GATE_FILES[0]
            changed.write_bytes(b"different gate")
            with self.assertRaisesRegex(ValueError, "reviewed_input_changed"):
                scoped.unchanged(snapshots)

    def test_tampered_policy_public_key_each_trust_and_signed_gate_are_rejected(self):
        for directory, relative in (("checkout", scoped.web.POLICY_FILES[0]),
                                     ("checkout", scoped.web.POLICY_FILES[1]),
                                     ("old_trust", scoped.web.POLICY_FILES[1]),
                                     ("new_trust", scoped.web.POLICY_FILES[0]),
                                     ("new_trust", scoped.pack.handoff.GATE_FILES[0]),
                                     ("base", scoped.builder.MAIN),
                                     ("candidate", scoped.builder.MAIN)):
            with self.subTest(directory=directory, relative=relative), trust_fixture() as dirs:
                (dirs[directory] / relative).write_bytes(b"unreviewed")
                with self.assertRaisesRegex(ValueError, "trust_.*changed|gate_changed"):
                    scoped.snapshot_trust()

    def test_extra_or_missing_trust_file_and_shrunk_inventory_are_rejected(self):
        for mode in ("extra", "missing", "shrunk"):
            with self.subTest(mode=mode), trust_fixture() as dirs:
                if mode == "extra": (dirs["new_trust"] / "unexpected.pem").write_bytes(b"public")
                elif mode == "missing": (dirs["new_trust"] / scoped.web.POLICY_FILES[1]).unlink()
                else: scoped.TRUST_PINS.pop(scoped.web.POLICY_FILES[1])
                with self.assertRaisesRegex(ValueError, "trust_inventory_changed"):
                    scoped.snapshot_trust()

    def test_full_release_uses_real_exact_diff_and_keeps_180_protected(self):
        with release_fixture():
            new, sig, changes, _ = scoped.authenticate_release()
            self.assertEqual(new["file_count"], 6630)
            self.assertEqual(sig["release_sequence"], 2026102503)
            self.assertEqual({r["path"] for r in changes}, scoped.ALLOWLIST)

    def test_wrong_ancestor_candidate_sequence_key_and_unsigned_result_rejected(self):
        for mode in ("old_sha", "old_sequence", "new_sha", "new_count", "new_sequence", "key", "signature"):
            with self.subTest(mode=mode), release_fixture() as data:
                old, new, oldsig, sig, _, _, _, _ = data
                if mode == "old_sha": old["content_sha256"] = "0" * 64
                elif mode == "old_sequence": oldsig["release_sequence"] -= 1
                elif mode == "new_sha": new["content_sha256"] = "0" * 64
                elif mode == "new_count": new["file_count"] -= 1
                elif mode == "new_sequence": sig["release_sequence"] -= 1
                elif mode == "key": sig["key_id"] = "foreign-key"
                else: sig["signature_valid"] = False
                with self.assertRaisesRegex(ValueError, "identity_mismatch"):
                    scoped.authenticate_release()

    def test_changed_protected_lua_or_extra_runtime_diff_is_rejected(self):
        for name in (scoped.builder.POLICY_MODULE, "scripts/vscripts/systems/payment_service.lua"):
            with self.subTest(name=name), release_fixture() as data:
                for row in data[1]["files"]:
                    if row["path"] == name: row["sha256"] = "0" * 64
                with self.assertRaisesRegex(ValueError, "Only the three"):
                    scoped.authenticate_release()

    def test_shrunk_protected_set_or_different_accounts_is_rejected(self):
        with release_fixture() as data:
            data[5].pop()
            with self.assertRaisesRegex(ValueError, "protected_or_change_scope"):
                scoped.authenticate_release()
        with release_fixture() as data:
            data[7].side_effect = [["1", "2", "3", "4"], ["1", "2", "3", "5"]]
            with self.assertRaisesRegex(ValueError, "test_accounts_changed"):
                scoped.authenticate_release()

    def test_default_plan_preserves_output_and_original_context_and_guards(self):
        with trust_fixture() as dirs:
            before = (scoped.pack.handoff.ROOT, scoped.pack.handoff.POLICY)
            def existing(candidate, output, workshop_id, *, build):
                self.assertFalse(build)
                self.assertEqual(scoped.pack.handoff.ROOT, scoped.TRUSTED)
                self.assertEqual(workshop_id, "3824360109")
                return dict(content_sha256=scoped.CANDIDATE_SHA, release_sequence=2026102503,
                            files=6630, signature_valid=True, payload_changed=False,
                            workshop_upload_performed=False, dry_run=True)
            with patch.object(scoped, "authenticate_release", return_value=(
                    {"content_sha256": scoped.CANDIDATE_SHA}, {"release_sequence": 2026102503}, [], {})), \
                    patch.object(scoped.pack, "package", side_effect=existing) as original, \
                    patch.object(scoped.pack.protect_data, "sign_manifest", side_effect=AssertionError("key read")):
                result = scoped.package()
            self.assertTrue(result["existing_packager_guards_preserved"])
            self.assertEqual(original.call_count, 1)
            self.assertEqual(before, (scoped.pack.handoff.ROOT, scoped.pack.handoff.POLICY))
            self.assertEqual(list(dirs["output"].iterdir()), [])

    def test_packager_failure_restores_context_and_preserves_failure_artifact(self):
        with trust_fixture() as dirs:
            before = (scoped.pack.handoff.ROOT, scoped.pack.handoff.POLICY)
            old_failure = dirs["output"].parent / "v08_package.json"
            old_failure.write_bytes(b"")
            with patch.object(scoped, "authenticate_release", return_value=({}, {}, [], {})), \
                    patch.object(scoped.pack, "package", side_effect=ValueError("original guard rejected")):
                with self.assertRaisesRegex(ValueError, "original guard rejected"):
                    scoped.package()
            self.assertEqual(before, (scoped.pack.handoff.ROOT, scoped.pack.handoff.POLICY))
            self.assertEqual(old_failure.read_bytes(), b"")
            self.assertEqual(list(dirs["output"].iterdir()), [])

    def test_existing_output_is_not_overwritten_before_any_candidate_read(self):
        with trust_fixture() as dirs:
            old = dirs["output"] / "3824360109.vpk"
            old.write_bytes(b"keep me")
            with patch.object(scoped, "authenticate_release", side_effect=AssertionError("candidate read")):
                for build in (False, True):
                    with self.assertRaisesRegex(ValueError, "output_must_be_empty"):
                        scoped.package(build=build)
            self.assertEqual(old.read_bytes(), b"keep me")

    def test_output_overlap_is_rejected_before_candidate_authentication(self):
        with trust_fixture() as dirs, patch.object(scoped, "OUTPUT", dirs["candidate"] / "out"):
            scoped.OUTPUT.mkdir()
            with patch.object(scoped, "authenticate_release", side_effect=AssertionError("candidate read")), \
                    self.assertRaisesRegex(ValueError, "output_overlap"):
                scoped.package()

    def test_linked_trust_entry_is_rejected_without_following_it(self):
        with trust_fixture(), patch.object(scoped.pack.protect_data, "linked", return_value=True), \
                self.assertRaisesRegex(ValueError, "trust_link_forbidden|Links and junctions"):
            scoped.snapshot_trust()

    def test_unmodified_native_packager_still_rejects_foreign_signature_and_changed_gate(self):
        # This independent small fixture signs with a fresh temporary test key;
        # it exercises the real old pack.authenticate, not a mocked signature.
        sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
        from test_stream_workshop_vpk import StreamingVPKTests, vpk
        fixture = StreamingVPKTests()
        fixture.setUp()
        try:
            vpk.authenticate(fixture.candidate)
            path = fixture.candidate / vpk.handoff.GATE_FILES[0]
            path.write_bytes(b"changed gate")
            fixture.seal()
            with self.assertRaisesRegex(ValueError, "guard differs"):
                vpk.authenticate(fixture.candidate)
            path.write_bytes((fixture.source / vpk.handoff.GATE_FILES[0]).read_bytes())
            fixture.seal()
            sigpath = fixture.candidate / vpk.handoff.SIGNATURE
            doc = vpk.handoff.load_json(sigpath)
            doc["key_id"] = "foreign-key"
            sigpath.write_bytes(vpk.runtime.canonical_bytes(doc))
            with self.assertRaisesRegex(ValueError, "Signature identity"):
                vpk.authenticate(fixture.candidate)
        finally:
            fixture.doCleanups()


if __name__ == "__main__":
    unittest.main()
