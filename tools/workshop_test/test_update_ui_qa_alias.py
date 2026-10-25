"""Only temporary synthetic aliases are mutated; never the installed svt_w24."""
from contextlib import contextmanager, ExitStack
from copy import deepcopy
import json
from pathlib import Path
from types import SimpleNamespace
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import update_ui_qa_alias as updater
from test_web_auth_candidate import manifest


@contextmanager
def fixture():
    with tempfile.TemporaryDirectory(prefix="ws4-alias-fixture-") as folder:
        top = Path(folder).resolve()
        root, base, candidate = top / "workspace/survival", top / "signed_v05", top / "signed_v06"
        target = root.parent / "svt_w24"
        store = root / "output/ui_qa_20261025/release/alias_updates"
        root.mkdir(parents=True)
        policy = updater.pack.handoff.load_json(updater.builder.ROOT / "tools/lua_protection_policy.json")
        protected = list(policy["business_modules"]) + [
            policy["generated_prefix"] + "fixture_%03d.lua" % n for n in range(176)]
        files = {name: ("protected:" + name).encode() for name in protected}
        names = updater.pack.runtime.CRITICAL | updater.pack.runtime.SCENE_MAPS | updater.ALLOWLIST | {
            *updater.pack.handoff.GATE_FILES, *updater.pack.handoff.ENTRY_GATE_FILES,
            updater.pack.handoff.ACCESS_FILE, updater.builder.WEB_CONFIG,
            "scripts/vscripts/core/commerce_release_policy.lua",
            "scripts/vscripts/systems/player_profile_providers/http_fishing_provider.lua",
            "maps/ws4_entry.vpk", "maps/template_map.vpk"}
        files.update({name: ("old signed runtime:" + name).encode() for name in names if name not in files})
        files["addoninfo.txt"] = (b'"AddonInfo" { "maps" "ws4_entry" "IsPlayable" "1" '
            b'"ws4_entry" { "MaxPlayers" "1" } "template_map" { "MaxPlayers" "4" } }\n')
        files[updater.builder.RELEASE_PROFILE] = b'return { channel = "production" }\n'
        old = manifest(files)
        new_files = dict(files, **{name: ("reviewed v06:" + name).encode() for name in updater.ALLOWLIST})
        new = manifest(new_files)
        for destination, data in ((base, files), (target, files), (candidate, new_files)):
            for name, raw in data.items():
                path = destination / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(raw)
        for destination, doc in ((base, old), (candidate, new)):
            (destination / updater.pack.handoff.MANIFEST).write_bytes(updater.pack.runtime.canonical_bytes(doc))
            (destination / updater.pack.handoff.SIGNATURE).write_bytes(b"{}\n")
        old_trusted, new_trusted = top / "v05_trusted", top / "v06_trusted"
        for trusted in (old_trusted, new_trusted):
            for name in (*updater.pack.handoff.GATE_FILES, *updater.pack.handoff.ENTRY_GATE_FILES,
                         updater.pack.handoff.ACCESS_FILE, *updater.web.POLICY_FILES):
                path = trusted / name; path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(files.get(name, b"public fixture policy"))
        for name in (*updater.web.POLICY_FILES, "tools/lua_protection_policy.json"):
            path = root / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(b"public fixture policy")
        receipt_value = dict(ok=True, kind="verified_online_policy_install", status="INSTALLED_FULLY_VERIFIED",
            content_sha256=old["content_sha256"], release_sequence=updater.builder.BASE_SEQUENCE,
            runtime_files=len(files), online_cheats_allowed=False, signature_valid=True,
            full_before_verification=True, full_after_verification=True)
        receipt = updater.pack.runtime.canonical_bytes(receipt_value) + b"\n"
        (target / updater.RECEIPT).write_bytes(receipt)
        caches = {"tools_asset_info.bin": b"preserve engine asset cache",
                  "tools_thumbnail_cache.sqlite3": b"preserve engine thumbnails"}
        for name, raw in caches.items(): (target / name).write_bytes(raw)
        context = dict(base=base, candidate=candidate, old=old, new=new,
            old_signature=dict(key_id="fixture-key", release_sequence=updater.builder.BASE_SEQUENCE),
            signature=dict(key_id="fixture-key", release_sequence=updater.builder.RELEASE_SEQUENCE),
            old_rows={r["path"]: r for r in old["files"]}, new_rows={r["path"]: r for r in new["files"]})
        with ExitStack() as stack:
            for name, value in (("ROOT", root), ("TARGET", target), ("STORE", store), ("CANDIDATE", candidate),
                                ("TRUSTED", new_trusted), ("CANDIDATE_SHA", new["content_sha256"]),
                                ("OLD_RECEIPT_SHA", updater.web.sha(receipt))):
                stack.enter_context(patch.object(updater, name, value))
            stack.enter_context(patch.object(updater.builder, "BASE_SHA", old["content_sha256"]))
            stack.enter_context(patch.object(updater.builder, "BASE_FILES", len(files)))
            stack.enter_context(patch.object(updater.builder, "BASE", base))
            stack.enter_context(patch.object(updater.builder, "BASE_TRUSTED", old_trusted))
            release_mock = stack.enter_context(patch.object(updater, "releases", return_value=context))
            stack.enter_context(patch.object(updater, "dota_pids", return_value=[]))
            yield SimpleNamespace(root=root, base=base, candidate=candidate, target=target, store=store,
                files=files, new_files=new_files, old=old, new=new, context=context, receipt=receipt,
                receipt_value=receipt_value, caches=caches, release_mock=release_mock, protected=protected)


def assert_old(test, data):
    updater.verify_runtime(data.target, data.old)
    test.assertEqual((data.target / updater.RECEIPT).read_bytes(), data.receipt)
    for name, raw in data.caches.items(): test.assertEqual((data.target / name).read_bytes(), raw)
    test.assertFalse((data.store / "active.lock").exists())


class UIQAAliasUpdateTest(unittest.TestCase):
    def test_production_target_and_candidate_pins_are_fixed(self):
        self.assertEqual(updater.TARGET, updater.ROOT.parent / "svt_w24")
        self.assertEqual(updater.CANDIDATE_SHA, "1dd9d88f885f8e1617985f933bbdb450884f91a7cdb96b10e0315d2b0cdaa884")
        self.assertEqual(updater.OLD_RECEIPT_SHA, "2003987e89b74120d3e90cb0586449c12d5003d789fc777f2f3784f32a09f48e")
        self.assertEqual(len(updater.ALLOWLIST), 7)
        self.assertNotIn(updater.builder.MAIN, updater.ALLOWLIST)
        self.assertNotIn(updater.builder.POLICY_MODULE, updater.ALLOWLIST)

    def test_default_plan_is_read_only_and_can_report_running_game(self):
        with fixture() as data, patch.object(updater, "dota_pids", return_value=[123]), \
                patch.object(updater, "copy_verified", side_effect=AssertionError("plan copied")), \
                patch.object(updater, "atomic_replace", side_effect=AssertionError("plan replaced")), \
                patch.object(updater, "write_verified", side_effect=AssertionError("plan wrote")):
            result = updater.run()
            self.assertEqual(result["status"], "VERIFIED_READ_ONLY_PLAN")
            self.assertTrue(result["dry_run"] and result["dota_running"])
            self.assertFalse(data.store.exists())
            self.assertFalse(result["private_key_read"])
            assert_old(self, data)

    def test_live_dota_blocks_apply_before_backup_or_stage_creation(self):
        with fixture() as data, patch.object(updater, "dota_pids", return_value=[456]):
            with self.assertRaisesRegex(RuntimeError, "dota_still_running"):
                updater.run(apply=True)
            self.assertFalse(data.store.exists())
            assert_old(self, data)

    def test_old_receipt_changed_wrong_identity_or_missing_is_rejected(self):
        with fixture() as data:
            path = data.target / updater.RECEIPT
            for raw in (data.receipt + b" ", b"{}", b'{"content_sha256":"unknown"}'):
                path.write_bytes(raw)
                with self.assertRaisesRegex(RuntimeError, "old_receipt_changed"):
                    updater.run()
            path.unlink()
            with self.assertRaises(ValueError): updater.run()
            self.assertFalse(data.store.exists())

    def test_even_repinned_receipt_must_have_v05_semantics(self):
        with fixture() as data:
            for field, value in (("release_sequence", 1), ("online_cheats_allowed", True),
                                 ("runtime_files", 1), ("content_sha256", "untrusted"),
                                 ("full_after_verification", False)):
                invalid = dict(data.receipt_value, **{field: value})
                raw = updater.pack.runtime.canonical_bytes(invalid)
                (data.target / updater.RECEIPT).write_bytes(raw)
                with patch.object(updater, "OLD_RECEIPT_SHA", updater.web.sha(raw)):
                    with self.assertRaisesRegex(RuntimeError, "old_receipt_invalid"):
                        updater.run()
            self.assertFalse(data.store.exists())

    def test_modified_or_unexpected_runtime_fails_full_old_verification(self):
        with fixture() as data:
            target = data.target / next(iter(updater.ALLOWLIST))
            saved = target.read_bytes(); target.write_bytes(saved + b"corrupt")
            with self.assertRaisesRegex(RuntimeError, "full_runtime_verification_failed"):
                updater.run()
            target.write_bytes(saved)
            extra = data.target / "scripts/vscripts/unreviewed.lua"; extra.write_bytes(b"return {}")
            with self.assertRaisesRegex(RuntimeError, "full_runtime_verification_failed"):
                updater.run()
            self.assertFalse(data.store.exists())

    def test_success_changes_only_seven_files_then_receipt_and_preserves_caches(self):
        with fixture() as data:
            original = updater.atomic_replace
            verified_new, operations = [], []
            verify = updater.verify_runtime
            def check(target, doc):
                verify(target, doc)
                if doc == data.new: verified_new.append(True)
            def replace(source, target, row, **options):
                if target.name == updater.RECEIPT:
                    self.assertTrue(verified_new, "receipt cannot advance before complete v06 verification")
                operations.append(target.relative_to(data.target).as_posix())
                return original(source, target, row, **options)
            with patch.object(updater, "atomic_replace", side_effect=replace), \
                    patch.object(updater, "verify_runtime", side_effect=check):
                result = updater.run(apply=True)
            self.assertEqual(result["status"], "UPDATED_FULLY_VERIFIED")
            self.assertEqual(operations, sorted(updater.ALLOWLIST) + [updater.RECEIPT])
            self.assertEqual(data.release_mock.call_count, 2)
            updater.verify_runtime(data.target, data.new)
            receipt = json.loads((data.target / updater.RECEIPT).read_text())
            self.assertEqual(receipt["content_sha256"], data.new["content_sha256"])
            self.assertEqual(receipt["release_sequence"], updater.builder.RELEASE_SEQUENCE)
            self.assertFalse(receipt["online_cheats_allowed"])
            for name, raw in data.caches.items(): self.assertEqual((data.target / name).read_bytes(), raw)
            for name in data.files:
                self.assertEqual((data.target / name).read_bytes(), data.new_files[name])
                self.assertEqual((data.base / name).read_bytes(), data.files[name])
                self.assertEqual((data.candidate / name).read_bytes(), data.new_files[name])
            transaction = Path(result["transaction"])
            self.assertEqual((transaction / "backup" / updater.RECEIPT).read_bytes(), data.receipt)
            for name in updater.ALLOWLIST:
                self.assertEqual((transaction / "backup" / name).read_bytes(), data.files[name])
                self.assertEqual((transaction / "stage" / name).read_bytes(), data.new_files[name])
            self.assertFalse((data.store / "active.lock").exists())
            self.assertFalse([p for p in data.target.rglob("*.tmp")])

    def test_failure_at_each_runtime_replacement_restores_all_old_bytes(self):
        for fail_at in range(1, 8):
            with self.subTest(replacement=fail_at), fixture() as data:
                original, count = updater.atomic_replace, 0
                def fail_once(source, target, row, **options):
                    nonlocal count
                    if source.name.endswith("_new.tmp") and target.name != updater.RECEIPT:
                        count += 1
                        if count == fail_at: raise OSError("injected_replace_failure")
                    return original(source, target, row, **options)
                with patch.object(updater, "atomic_replace", side_effect=fail_once):
                    with self.assertRaises(updater.UpdateFailure) as caught: updater.run(apply=True)
                self.assertTrue(caught.exception.report["rollback"]["ok"])
                self.assertEqual(caught.exception.report["stage"], "replace_runtime_%d" % fail_at)
                assert_old(self, data)
                self.assertFalse([p for p in data.target.rglob("*.tmp")])

    def test_receipt_replace_failure_restores_seven_files_and_old_receipt(self):
        with fixture() as data:
            original = updater.atomic_replace
            def fail_receipt(source, target, row, **options):
                if source.name.endswith("_new.tmp") and target.name == updater.RECEIPT:
                    raise OSError("injected_receipt_failure")
                return original(source, target, row, **options)
            with patch.object(updater, "atomic_replace", side_effect=fail_receipt):
                with self.assertRaises(updater.UpdateFailure) as caught: updater.run(apply=True)
            self.assertEqual(caught.exception.report["stage"], "replace_receipt")
            self.assertTrue(caught.exception.report["rollback"]["ok"])
            assert_old(self, data)

    def test_post_receipt_full_verification_failure_restores_receipt_too(self):
        with fixture() as data:
            verify, new_count = updater.verify_runtime, 0
            def fail_second_new(target, doc):
                nonlocal new_count
                if doc == data.new:
                    new_count += 1
                    if new_count == 2: raise RuntimeError("injected_final_verification_failure")
                return verify(target, doc)
            with patch.object(updater, "verify_runtime", side_effect=fail_second_new):
                with self.assertRaises(updater.UpdateFailure) as caught: updater.run(apply=True)
            self.assertEqual(caught.exception.report["stage"], "verify_final_installation")
            self.assertTrue(caught.exception.report["rollback"]["ok"])
            assert_old(self, data)

    def test_precommit_source_change_does_not_mutate_alias(self):
        with fixture() as data:
            data.release_mock.side_effect = [data.context, RuntimeError("alias_source_changed")]
            with self.assertRaises(updater.UpdateFailure) as caught: updater.run(apply=True)
            self.assertFalse(caught.exception.report["rollback"]["attempted"])
            self.assertTrue(caught.exception.report["rollback"]["full_old_runtime_verified"])
            assert_old(self, data)

    def test_dota_appearing_after_stage_or_mid_update_forces_rollback(self):
        for fail_call in (2, 5):
            with self.subTest(process_check=fail_call), fixture() as data:
                calls = 0
                def process_list():
                    nonlocal calls
                    calls += 1
                    return [999] if calls >= fail_call else []
                with patch.object(updater, "dota_pids", side_effect=process_list):
                    with self.assertRaises(updater.UpdateFailure) as caught: updater.run(apply=True)
                self.assertEqual(caught.exception.report["error"], "alias_dota_still_running")
                self.assertTrue(caught.exception.report["rollback"]["ok"])
                assert_old(self, data)

    def test_corrupt_backup_is_rejected_before_first_replace(self):
        with fixture() as data:
            copy, corrupted = updater.copy_verified, False
            def corrupt_after_backup(source, destination, row, boundary, **options):
                nonlocal corrupted
                result = copy(source, destination, row, boundary, **options)
                if not corrupted and "stage" in destination.parts:
                    corrupted = True
                    transaction = next(p for p in data.store.iterdir() if p.is_dir())
                    (transaction / "backup" / next(iter(updater.ALLOWLIST))).write_bytes(b"corrupt backup")
                return result
            with patch.object(updater, "copy_verified", side_effect=corrupt_after_backup):
                with self.assertRaises(updater.UpdateFailure) as caught: updater.run(apply=True)
            self.assertEqual(caught.exception.report["stage"], "recheck_before_replace")
            self.assertFalse(caught.exception.report["rollback"]["attempted"])
            assert_old(self, data)

    def test_rollback_can_restore_a_runtime_file_deleted_during_failure(self):
        with fixture() as data:
            original, deleted = updater.atomic_replace, False
            def remove_once(source, target, row, **options):
                nonlocal deleted
                if not deleted and source.name.endswith("_new.tmp"):
                    deleted = True; target.unlink(); raise OSError("injected_deleted_target")
                return original(source, target, row, **options)
            with patch.object(updater, "atomic_replace", side_effect=remove_once):
                with self.assertRaises(updater.UpdateFailure) as caught: updater.run(apply=True)
            self.assertTrue(caught.exception.report["rollback"]["ok"])
            assert_old(self, data)

    def test_unrecoverable_restore_failure_is_explicit_and_keeps_backups(self):
        with fixture() as data:
            original, first = updater.atomic_replace, True
            def fail_new_and_one_restore(source, target, row, **options):
                nonlocal first
                if source.name.endswith("_new.tmp") and first:
                    first = False
                    result = original(source, target, row, **options)
                    raise OSError("injected_after_first_replace")
                if source.name.endswith("_old.tmp") and target.relative_to(data.target).as_posix() == sorted(updater.ALLOWLIST)[0]:
                    raise OSError("injected_persistent_restore_failure")
                return original(source, target, row, **options)
            with patch.object(updater, "atomic_replace", side_effect=fail_new_and_one_restore):
                with self.assertRaises(updater.UpdateFailure) as caught: updater.run(apply=True)
            self.assertFalse(caught.exception.report["rollback"]["ok"])
            transaction = Path(caught.exception.report["transaction"])
            self.assertTrue((transaction / "backup" / updater.RECEIPT).is_file())
            self.assertEqual(json.loads((transaction / "transaction.json").read_text())["status"], "RECOVERY_REQUIRED")

    def test_wrong_target_or_backup_store_is_rejected(self):
        with fixture() as data:
            with patch.object(updater, "TARGET", data.target.with_name("another_addon")):
                with self.assertRaisesRegex(RuntimeError, "not_fixed_svt_w24"): updater.run(apply=True)
            outside = data.root.parent / "outside_store"
            with patch.object(updater, "STORE", outside):
                with self.assertRaisesRegex(RuntimeError, "backup_store_not_fixed"): updater.run(apply=True)
            self.assertFalse(outside.exists())
            assert_old(self, data)

    def test_reparse_target_or_runtime_ancestor_is_rejected(self):
        with fixture() as data:
            linked = updater.pack.protect_data.linked
            runtime_linked = updater.pack.runtime.is_link
            for forbidden in (data.target, data.target / "panorama"):
                with patch.object(updater.pack.protect_data, "linked",
                                  side_effect=lambda p: p == forbidden or linked(p)), \
                        patch.object(updater.pack.runtime, "is_link",
                                     side_effect=lambda p: p == forbidden or runtime_linked(p)):
                    with self.assertRaises((RuntimeError, ValueError)): updater.run(apply=True)
                self.assertFalse(data.store.exists())

    def test_copy_rejects_traversal_and_existing_destination(self):
        with fixture() as data:
            name = sorted(updater.ALLOWLIST)[0]; source = data.target / name
            row = data.context["old_rows"][name]
            with self.assertRaisesRegex(RuntimeError, "outside_boundary"):
                updater.copy_verified(source, data.root.parent / "escaped", row, data.root)
            existing = data.root / "existing"; existing.write_bytes(b"keep")
            with self.assertRaises(FileExistsError): updater.copy_verified(source, existing, row, data.root)
            self.assertEqual(existing.read_bytes(), b"keep")

    def test_generic_windows_reparse_tag_is_rejected_even_without_symlink_or_junction(self):
        with fixture() as data:
            forbidden = data.target / sorted(updater.ALLOWLIST)[0]
            lstat = Path.lstat
            def tagged(path, *args, **options):
                if path == forbidden: return SimpleNamespace(st_file_attributes=0x400)
                return lstat(path, *args, **options)
            with patch.object(Path, "lstat", tagged):
                with self.assertRaisesRegex(RuntimeError, "reparse_path_forbidden"):
                    updater.run()
            self.assertFalse(data.store.exists())

    def test_candidate_payload_reparse_is_rejected_before_signature_payload_hashing(self):
        with fixture() as data:
            forbidden = data.candidate / sorted(updater.ALLOWLIST)[0]
            lstat = Path.lstat
            def tagged(path, *args, **options):
                if path == forbidden: return SimpleNamespace(st_file_attributes=0x400)
                return lstat(path, *args, **options)
            with patch.object(Path, "lstat", tagged):
                with self.assertRaisesRegex(RuntimeError, "reparse_path_forbidden"):
                    updater.guard_release(data.candidate, updater.TRUSTED)

    def test_other_manifest_identity_is_rejected_before_visiting_payload_paths(self):
        with fixture() as data, patch.object(updater, "CANDIDATE_SHA", "0" * 64), \
                patch.object(updater, "guard_inventory", side_effect=AssertionError("wrong manifest visited payload")):
            with self.assertRaisesRegex(RuntimeError, "pinned_manifest_identity_mismatch"):
                updater.guard_release(data.candidate, updater.TRUSTED)

    def test_partially_written_owned_temporary_is_tracked_and_not_silently_deleted(self):
        with fixture() as data:
            name = sorted(updater.ALLOWLIST)[0]
            source = data.candidate / name
            destination = updater.sibling(data.target / name, "b" * 32, "new")
            owned = {}
            def partial(read, write, length):
                write.write(b"partial"); raise OSError("injected_partial_copy")
            with patch.object(updater.shutil, "copyfileobj", side_effect=partial):
                with self.assertRaises(OSError):
                    updater.copy_verified(source, destination, data.context["new_rows"][name], data.target, owned=owned)
            self.assertIn(destination, owned)
            self.assertEqual(updater.cleanup_temporaries(owned), ["alias_file_hash_mismatch"])
            self.assertEqual(destination.read_bytes(), b"partial")

    def test_atomic_replace_cannot_touch_an_unallowlisted_file(self):
        with fixture() as data:
            target = data.target / "unrelated.txt"; target.write_bytes(b"keep")
            source = updater.sibling(target, "c" * 32, "new"); source.write_bytes(b"new")
            with self.assertRaisesRegex(RuntimeError, "replace_scope_invalid"):
                updater.atomic_replace(source, target, updater.row_bytes(b"new"))
            self.assertEqual(target.read_bytes(), b"keep")

    def test_journal_failure_after_successful_receipt_still_restores_old_install(self):
        with fixture() as data:
            original = updater.journal
            def fail_commit(transaction, value):
                if value.get("status") == "INSTALLED_FULLY_VERIFIED":
                    raise OSError("injected_commit_journal_failure")
                return original(transaction, value)
            with patch.object(updater, "journal", side_effect=fail_commit):
                with self.assertRaises(updater.UpdateFailure) as caught: updater.run(apply=True)
            self.assertTrue(caught.exception.report["rollback"]["ok"])
            assert_old(self, data)

    def test_keyboard_interrupt_during_replacement_completes_old_install_recovery(self):
        with fixture() as data:
            original, interrupted = updater.atomic_replace, False
            def interrupt_once(source, target, row, **options):
                nonlocal interrupted
                result = original(source, target, row, **options)
                if not interrupted and source.name.endswith("_new.tmp"):
                    interrupted = True; raise KeyboardInterrupt()
                return result
            with patch.object(updater, "atomic_replace", side_effect=interrupt_once):
                with self.assertRaises(updater.UpdateFailure) as caught: updater.run(apply=True)
            self.assertTrue(caught.exception.report["rollback"]["ok"])
            assert_old(self, data)

    def test_existing_lock_is_preserved_and_never_stolen(self):
        with fixture() as data:
            data.store.mkdir(parents=True)
            lock = data.store / "active.lock"; lock.write_bytes(b"another operator")
            with self.assertRaisesRegex(RuntimeError, "update_locked"): updater.run(apply=True)
            self.assertEqual(lock.read_bytes(), b"another operator")
            self.assertEqual((data.target / updater.RECEIPT).read_bytes(), data.receipt)

    def test_fixed_v06_signature_identity_and_exact_scope_are_required(self):
        with fixture() as data:
            # Exercise the real source-authentication boundary with explicit
            # fake signature results; no real candidate or key is accessed.
            original = ORIGINAL_RELEASES
            old_sig = data.context["old_signature"]
            new_sig = data.context["signature"]
            with patch.object(updater.builder, "authenticate_base", return_value=(data.base, data.old, old_sig)), \
                    patch.object(updater.pack, "authenticate", return_value=(data.candidate, data.new, new_sig, {})) as auth:
                self.assertEqual(original()["new"], data.new)
                for field, value in (("content_sha256", "0" * 64), ("file_count", 1)):
                    auth.return_value = data.candidate, dict(data.new, **{field: value}), new_sig, {}
                    with self.assertRaisesRegex(RuntimeError, "v06_identity_mismatch"): original()
                for field, value in (("release_sequence", 1), ("key_id", "wrong-key")):
                    auth.return_value = data.candidate, data.new, dict(new_sig, **{field: value}), {}
                    with self.assertRaisesRegex(RuntimeError, "signature_identity_mismatch"): original()
                auth.side_effect = ValueError("invalid signature")
                with self.assertRaises(ValueError): original()

    def test_dota_process_probe_fails_closed_on_query_error_or_malformed_pid(self):
        original = ORIGINAL_DOTA_PIDS
        for reply in (SimpleNamespace(returncode=1, stdout=b"{}"),
                      SimpleNamespace(returncode=0, stdout=b'{"dota_pids":["unknown"]}')):
            with patch.object(updater.subprocess, "run", return_value=reply):
                with self.assertRaisesRegex(RuntimeError, "process_check_failed"): original()
        with patch.object(updater.subprocess, "run", return_value=SimpleNamespace(returncode=0, stdout=b'{"dota_pids":[]}')):
            self.assertEqual(original(), [])


ORIGINAL_RELEASES = updater.releases
ORIGINAL_DOTA_PIDS = updater.dota_pids

if __name__ == "__main__":
    unittest.main()
