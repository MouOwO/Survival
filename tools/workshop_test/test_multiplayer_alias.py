"""Synthetic temporary aliases only; never apply to the installed svt_w24."""
from contextlib import ExitStack, contextmanager, nullcontext
from pathlib import Path
from types import SimpleNamespace
import json
import os
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import update_multiplayer_alias as tool
from test_web_auth_candidate import manifest
REAL_RELEASES = tool.releases


@contextmanager
def fixture():
    with tempfile.TemporaryDirectory(prefix="ws4-mp-alias-test-") as folder:
        top = Path(folder).resolve()
        root, base, candidate = top / "workspace/survival", top / "signed_v08", top / "signed_v09"
        target = root.parent / "svt_w24"
        root.mkdir(parents=True)
        names = tool.pack.runtime.CRITICAL | tool.pack.runtime.SCENE_MAPS | tool.builder.ALLOWLIST | tool.builder.REMOVED | {
            "maps/template_map.vpk", tool.builder.WEB_CONFIG, tool.builder.POLICY_MODULE}
        names = names - tool.builder.ADDED
        files = {name: ("frozen:" + name).encode() for name in names}
        files["addoninfo.txt"] = (b'"AddonInfo" { "maps" "ws4_entry" "IsPlayable" "1" "EnablePickRules" "0" '
            b'"ws4_entry" { "MaxPlayers" "1" } "template_map" { "MaxPlayers" "4" } }\r\n')
        files[tool.pack.runtime.RELEASE_PROFILE] = b'return { channel = "production" }\r\n'
        files[tool.builder.WEB_CONFIG] = b'return { enabled = true }\r\n'
        new_files = dict(files)
        new_files[tool.builder.ADDONINFO] = files[tool.builder.ADDONINFO].replace(b'"maps" "ws4_entry"', b'"maps" "template_map"')
        new_files[tool.builder.MAIN] += b"\r\n-- exact reviewed wrapper\r\n"
        new_files[tool.builder.PROBE] = b"-- anonymous WS4-MP-09 fixture\r\n"
        del new_files[tool.builder.ENTRY_MAP]
        old, new = manifest(files), manifest(new_files)
        for destination, data in ((base, files), (target, files), (candidate, new_files)):
            for name, raw in data.items():
                path = destination / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(raw)
        marker = tool.canonical(dict(ok=True, kind="verified_online_policy_install", status="INSTALLED_FULLY_VERIFIED",
            content_sha256=old["content_sha256"], release_sequence=tool.builder.BASE_SEQUENCE,
            runtime_files=len(files), online_cheats_allowed=False, signature_valid=True,
            full_before_verification=True, full_after_verification=True, retained_original_format="v08"))
        (target / tool.MARKER).write_bytes(marker)
        caches = {name: ("original cache:" + name).encode() for name in tool.CACHES}
        for name, raw in caches.items(): (target / name).write_bytes(raw)
        for destination, doc, provenance in ((base, old, "_ui_stackable_provenance.json"),
                                              (candidate, new, "_multiplayer_provenance.json")):
            (destination / tool.pack.handoff.MANIFEST).write_bytes(tool.canonical(doc))
            (destination / tool.pack.handoff.SIGNATURE).write_bytes(b"{}\n")
            (destination / provenance).write_bytes(b"{}\n")
        context = dict(old=old, new=new, base=base, candidate=candidate, old_metadata={}, metadata={},
            patches={name: new_files[name] for name in tool.builder.ALLOWLIST},
            old_rows={r["path"]:r for r in old["files"]}, new_rows={r["path"]:r for r in new["files"]})
        with ExitStack() as stack:
            for name, value in (("ROOT", root), ("TARGET", target), ("CANDIDATE", candidate),
                ("TRUSTED", top / "trusted_v09"), ("CANDIDATE_SHA", new["content_sha256"]),
                ("OLD_MARKER_SHA", tool.web.sha(marker)),
                ("STORE", root / "output/arcade_multiplayer_20261025/alias_transactions"),
                ("SHARED", root / "output/ui_qa_20261025/release/alias_updates")):
                stack.enter_context(patch.object(tool, name, value))
            for name, value in (("BASE", base), ("BASE_SHA", old["content_sha256"]), ("BASE_FILES", len(files)),
                ("DESTINATION", candidate), ("TRUSTED_DESTINATION", top / "trusted_v09"), ("BASE_TRUSTED", top / "trusted_v08")):
                stack.enter_context(patch.object(tool.builder, name, value))
            release_mock = stack.enter_context(patch.object(tool, "releases", side_effect=lambda: dict(context)))
            stack.enter_context(patch.object(tool, "dota_pids", return_value=[]))
            yield SimpleNamespace(root=root, base=base, candidate=candidate, target=target, old=old, new=new,
                context=context, marker=marker, files=files, new_files=new_files, caches=caches,
                release_mock=release_mock, store=tool.STORE)


def assert_old(test, data):
    tool.verify_runtime(data.target, data.old, data.marker)
    test.assertEqual((data.target / tool.MARKER).read_bytes(), data.marker)
    for name, raw in data.files.items(): test.assertEqual((data.target / name).read_bytes(), raw)
    test.assertFalse((data.target / tool.builder.PROBE).exists())


class MultiplayerAliasTest(unittest.TestCase):
    def test_fixed_release_and_path_contract(self):
        self.assertEqual(tool.CANDIDATE_SHA, "839fd6edb8373af2967d0cd7de93370fb737ed0e79200a9ae622624a27a6402d")
        self.assertEqual(tool.builder.BASE_SHA, "88611d026e49c52b5bce7324818f36a11a60059a2844b8f646b884ba15debaa9")
        self.assertEqual(tool.builder.BASE_FILES, 6630)
        self.assertEqual(tool.builder.RELEASE_SEQUENCE, 2026102504)
        self.assertEqual(tool.TARGET, tool.ROOT.parent / "svt_w24")
        self.assertEqual(tool.CONTROLLED, tool.builder.ALLOWLIST | tool.builder.REMOVED | {tool.MARKER})
        self.assertTrue(sys.dont_write_bytecode)

    def test_missing_pin_fails_before_target_or_signed_source_io(self):
        with patch.object(tool, "CANDIDATE_SHA", None), patch.object(tool, "guard_release", side_effect=AssertionError("source IO")):
            with self.assertRaisesRegex(RuntimeError, "candidate_not_pinned"): tool.run()

    def test_default_plan_is_strictly_read_only_even_with_dota_running(self):
        with fixture() as data, patch.object(tool, "dota_pids", return_value=[123]), \
            patch.object(tool, "write_new", side_effect=AssertionError("write")), \
            patch.object(tool, "atomic_document", side_effect=AssertionError("replace")):
            result = tool.run()
            self.assertTrue(result["ok"] and result["dry_run"] and result["dota_running"])
            self.assertFalse(result["private_key_read"])
            self.assertFalse(data.store.exists()); assert_old(self, data)

    def test_apply_restore_exact_images_marker_and_newest_caches(self):
        with fixture() as data:
            result = tool.run(apply=True)
            self.assertEqual(result["status"], "TEMPORARY_V09_ACTIVE")
            transaction = Path(result["transaction"])
            self.assertEqual(tool.inventory(transaction / "backup"), tool.builder.MODIFIED | tool.builder.REMOVED | {tool.MARKER})
            self.assertEqual((transaction / "backup" / tool.MARKER).read_bytes(), data.marker)
            self.assertFalse((data.target / tool.builder.ENTRY_MAP).exists())
            for name, raw in data.new_files.items(): self.assertEqual((data.target / name).read_bytes(), raw)
            self.assertEqual(json.loads((data.target / tool.MARKER).read_bytes())["kind"], "temporary_multiplayer_alias_install")
            self.assertTrue(tool.run()["dry_run"])
            for name in tool.CACHES: (data.target / name).write_bytes(b"updated by native Dota")
            restored = tool.run(restore=True)
            self.assertEqual(restored["status"], "V08_RESTORED_FULLY_VERIFIED")
            assert_old(self, data)
            for name in tool.CACHES: self.assertEqual((data.target / name).read_bytes(), b"updated by native Dota")
            self.assertFalse((data.store / "active.json").exists())
            self.assertFalse((tool.SHARED / "active.lock").exists())
            self.assertTrue(transaction.exists(), "audit backups are retained")

    def test_dota_blocks_apply_and_restore_before_alias_mutation(self):
        with fixture() as data:
            with patch.object(tool, "dota_pids", return_value=[42]):
                with self.assertRaisesRegex(RuntimeError, "dota_still_running"): tool.run(apply=True)
            self.assertFalse(data.store.exists()); assert_old(self, data)
            tool.run(apply=True)
            snapshot = (data.target / tool.MARKER).read_bytes()
            with patch.object(tool, "dota_pids", return_value=[42]):
                with self.assertRaisesRegex(RuntimeError, "dota_still_running"): tool.run(restore=True)
            self.assertEqual((data.target / tool.MARKER).read_bytes(), snapshot)

    def test_unknown_extra_marker_or_runtime_drift_rejected_without_writes(self):
        for kind in ("extra", "marker", "runtime"):
            with self.subTest(kind=kind), fixture() as data:
                if kind == "extra": (data.target / "scripts/unreviewed.txt").write_bytes(b"user")
                elif kind == "marker": (data.target / tool.MARKER).write_bytes(data.marker + b" ")
                else: (data.target / tool.builder.MAIN).write_bytes(b"user main")
                with self.assertRaises(RuntimeError): tool.run(apply=True)
                self.assertFalse(data.store.exists())

    def test_links_and_hardlinks_are_rejected_including_owned_caches(self):
        with fixture() as data:
            cache = data.target / sorted(tool.CACHES)[0]
            cache.unlink(); os.link(data.target / "addoninfo.txt", cache)
            with self.assertRaisesRegex(RuntimeError, "links_forbidden"): tool.run(apply=True)
            self.assertFalse(data.store.exists())

    def test_failure_after_each_runtime_change_and_marker_rolls_back_exactly(self):
        for position in range(1, 6):
            with self.subTest(position=position), fixture() as data:
                original, count, failed = tool.cas_change, 0, False
                def injected(*args, **kwargs):
                    nonlocal count, failed
                    original(*args, **kwargs)
                    count += 1
                    if count == position and not failed: failed = True; raise OSError("injected_after_replace")
                with patch.object(tool, "cas_change", side_effect=injected):
                    with self.assertRaises(tool.TransactionFailure) as caught: tool.run(apply=True)
                self.assertTrue(caught.exception.report["recovery"]["ok"])
                assert_old(self, data)
                self.assertFalse((data.store / "active.json").exists())

    def test_drift_during_apply_preserves_user_change_and_allows_later_recovery(self):
        with fixture() as data:
            original, fired = tool.cas_change, False
            def injected(context, transaction, name, before, raw):
                nonlocal fired
                original(context, transaction, name, before, raw)
                if not fired:
                    fired = True
                    (data.target / tool.builder.MAIN).write_bytes(b"user concurrent main")
                    raise OSError("injected_user_drift")
            with patch.object(tool, "cas_change", side_effect=injected):
                with self.assertRaises(tool.TransactionFailure) as caught: tool.run(apply=True)
            self.assertFalse(caught.exception.report["recovery"]["ok"])
            self.assertEqual((data.target / tool.builder.MAIN).read_bytes(), b"user concurrent main")
            self.assertTrue((data.store / "active.json").exists())
            (data.target / tool.builder.MAIN).write_bytes(data.files[tool.builder.MAIN])
            self.assertTrue(tool.run(restore=True)["ok"]); assert_old(self, data)

    def test_changed_probe_backup_or_marker_blocks_restore_without_deleting_user_data(self):
        for kind in ("probe", "backup", "marker", "extra"):
            with self.subTest(kind=kind), fixture() as data:
                result = tool.run(apply=True)
                path = {"probe":data.target / tool.builder.PROBE,
                    "backup":Path(result["transaction"]) / "backup" / tool.builder.MAIN,
                    "marker":data.target / tool.MARKER, "extra":data.target / "user_notes.txt"}[kind]
                path.write_bytes(b"user changed")
                with self.assertRaises(RuntimeError): tool.run(restore=True)
                self.assertEqual(path.read_bytes(), b"user changed")
                self.assertTrue((data.store / "active.json").exists())

    def test_drift_between_transition_precheck_and_cas_is_never_overwritten(self):
        with fixture() as data:
            tool.run(apply=True)
            original, fired = tool.transition_rows, False
            def inject(context):
                nonlocal fired
                original(context)
                if not fired:
                    fired = True
                    (data.target / tool.builder.PROBE).write_bytes(b"user probe after precheck")
            with patch.object(tool, "transition_rows", side_effect=inject):
                with self.assertRaises(RuntimeError): tool.run(restore=True)
            self.assertEqual((data.target / tool.builder.PROBE).read_bytes(), b"user probe after precheck")

    def test_atomic_pointer_or_state_landed_then_exception_remains_recoverable(self):
        for where in ("pointer", "active_state"):
            with self.subTest(where=where), fixture() as data:
                original, fired = tool.atomic_document, False
                def injected(path, expected, raw, transaction):
                    nonlocal fired
                    original(path, expected, raw, transaction)
                    match = path.name == "active.json" if where == "pointer" else path.name == "state.json" and b'"ACTIVE"' in raw
                    if match and not fired: fired = True; raise OSError("injected_after_document_replace")
                with patch.object(tool, "atomic_document", side_effect=injected):
                    with self.assertRaises(tool.TransactionFailure) as caught: tool.run(apply=True)
                self.assertTrue(caught.exception.report["recovery"]["ok"])
                assert_old(self, data)

    def test_unlock_errors_preserve_success_or_primary_failure_report(self):
        for fail_apply in (False, True):
            with self.subTest(fail_apply=fail_apply), fixture() as data:
                with ExitStack() as stack:
                    stack.enter_context(patch.object(tool, "release_lock", side_effect=RuntimeError("injected_unlock_error")))
                    if fail_apply:
                        stack.enter_context(patch.object(tool, "cas_change", side_effect=OSError("injected_replace_error")))
                        with self.assertRaises(tool.TransactionFailure) as caught: tool.run(apply=True)
                        self.assertEqual(caught.exception.report["lock_release_error"], "injected_unlock_error")
                    else:
                        result = tool.run(apply=True)
                        self.assertFalse(result["ok"])
                        self.assertEqual(result["status"], "ALIAS_VERIFIED_LOCK_RECOVERY_REQUIRED")
                        self.assertTrue((data.store / "active.json").exists())

    def test_exact_source_provenance_is_allowed_but_unknown_source_extras_rejected(self):
        with fixture() as data, patch.object(tool.builder, "trust_names", return_value=()):
            trusted = data.root / "trust"; trusted.mkdir()
            tool.guard_release(data.base, trusted, data.old["content_sha256"])
            tool.guard_release(data.candidate, trusted, data.new["content_sha256"])
            (data.candidate / "unexpected_private.txt").write_bytes(b"not allowed")
            with self.assertRaisesRegex(RuntimeError, "release_inventory_mismatch"):
                tool.guard_release(data.candidate, trusted, data.new["content_sha256"])

    def test_scope_rejects_arbitrary_target_and_backup_store(self):
        with fixture() as data, patch.object(tool, "TARGET", data.root / "other_alias"):
            with self.assertRaisesRegex(RuntimeError, "target_not_fixed"): tool.run()
        with fixture() as data, patch.object(tool, "STORE", data.root / "other_store"):
            with self.assertRaisesRegex(RuntimeError, "store_not_fixed"): tool.run()

    def test_real_authentication_boundary_requires_both_signatures_and_exact_review(self):
        with fixture() as data, ExitStack() as stack:
            old_signature = dict(key_id="fixture-public-key", release_sequence=tool.builder.BASE_SEQUENCE)
            signature = dict(key_id="fixture-public-key", release_sequence=tool.builder.RELEASE_SEQUENCE)
            guarded = stack.enter_context(patch.object(tool, "guard_release"))
            base_auth = stack.enter_context(patch.object(tool.builder, "authenticate_base", return_value=(data.base, data.old, old_signature, {})))
            auth = stack.enter_context(patch.object(tool.pack, "authenticate", return_value=(data.candidate, data.new, signature, {})))
            trust = stack.enter_context(patch.object(tool.web, "trusted_root", side_effect=lambda _: nullcontext()))
            stack.enter_context(patch.object(tool.pack.handoff, "configured_ids", return_value=["a","b","c","d"]))
            protected = stack.enter_context(patch.object(tool.builder, "protected_paths", return_value=["signed-policy"] * 180))
            reviewed = stack.enter_context(patch.object(tool.builder, "audit_changes"))
            result = REAL_RELEASES()
            self.assertEqual(result["new"], data.new)
            self.assertEqual(guarded.call_count, 2)
            base_auth.assert_called_once_with(); auth.assert_called_once_with(data.candidate)
            trust.assert_called_once_with(tool.TRUSTED); protected.assert_called_once_with(data.old)
            reviewed.assert_called_once()
            for field, value in (("release_sequence", 1), ("key_id", "wrong-key")):
                auth.return_value = data.candidate, data.new, dict(signature, **{field:value}), {}
                with self.assertRaisesRegex(RuntimeError, "signature_identity_mismatch"): REAL_RELEASES()
            auth.side_effect = ValueError("invalid Ed25519 signature")
            with self.assertRaisesRegex(ValueError, "invalid Ed25519"): REAL_RELEASES()

    def test_restore_mid_operation_fault_can_resume_without_new_full_copy(self):
        with fixture() as data:
            tool.run(apply=True)
            original, fired = tool.cas_change, False
            def injected(*args, **kwargs):
                nonlocal fired
                original(*args, **kwargs)
                if not fired: fired = True; raise OSError("injected_restore_interruption")
            with patch.object(tool, "cas_change", side_effect=injected):
                with self.assertRaises(tool.TransactionFailure) as caught: tool.run(restore=True)
            self.assertEqual(caught.exception.report["recovery"]["status"], "RECOVERY_REQUIRED")
            self.assertTrue(tool.run(restore=True)["ok"]); assert_old(self, data)

    def test_existing_lock_and_second_apply_are_never_overwritten(self):
        with fixture() as data:
            tool.SHARED.mkdir(parents=True)
            lock = tool.SHARED / "active.lock"; lock.write_bytes(b"another tool owns this\n")
            with self.assertRaisesRegex(RuntimeError, "exclusive_file_exists"): tool.run(apply=True)
            self.assertEqual(lock.read_bytes(), b"another tool owns this\n"); assert_old(self, data)
            lock.unlink(); tool.run(apply=True)
            marker = (data.target / tool.MARKER).read_bytes()
            with self.assertRaisesRegex(RuntimeError, "transaction_already_active"): tool.run(apply=True)
            self.assertEqual((data.target / tool.MARKER).read_bytes(), marker)


if __name__ == "__main__":
    unittest.main()
