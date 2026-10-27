"""Synthetic temporary aliases only; never mutate the installed svt_w24."""
from contextlib import ExitStack, contextmanager
from pathlib import Path
from types import SimpleNamespace
import base64
import json
import os
import shutil
import sys
import struct
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import install_helper as tool
from test_web_auth_candidate import manifest
from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey


@contextmanager
def fixture():
    with tempfile.TemporaryDirectory(prefix="payment-helper-alias-test-") as folder:
        top = Path(folder).resolve()
        root, base, candidate = top / "workspace/survival", top / "signed_old", top / "signed_new"
        target = root.parent / "svt_w24"
        root.mkdir(parents=True)
        modified = {"scripts/vscripts/addon_game_mode.lua", "addoninfo.txt"}
        removed = {"maps/ws4_entry.vpk"}
        added = {"panorama/scripts/custom_game/payment_capability.vjs_c"}
        names = tool.pack.runtime.CRITICAL | tool.pack.runtime.SCENE_MAPS | modified | removed | {
            "maps/template_map.vpk", "scripts/vscripts/config/player_web_auth.lua"}
        files = {name: ("frozen:" + name).encode() for name in names}
        files["addoninfo.txt"] = (b'"AddonInfo" { "maps" "ws4_entry" "IsPlayable" "1" "EnablePickRules" "0" '
            b'"ws4_entry" { "MaxPlayers" "1" } "template_map" { "MaxPlayers" "4" } }\r\n')
        files[tool.pack.runtime.RELEASE_PROFILE] = b'return { channel = "production" }\r\n'
        files["scripts/vscripts/config/player_web_auth.lua"] = b'return { enabled = true }\r\n'
        new_files = dict(files)
        new_files["addoninfo.txt"] = files["addoninfo.txt"].replace(b'"maps" "ws4_entry"', b'"maps" "template_map"')
        new_files["scripts/vscripts/addon_game_mode.lua"] += b"\r\n-- reviewed helper\r\n"
        new_files[next(iter(added))] = b"reviewed compiled fixture"
        del new_files[next(iter(removed))]
        old, new = manifest(files), manifest(new_files)
        for destination, contents in ((base, files), (target, files), (candidate, new_files)):
            for name, raw in contents.items():
                path = destination / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(raw)
        marker = tool.canonical(dict(ok=True, kind="verified_online_policy_install", status="INSTALLED_FULLY_VERIFIED",
            content_sha256=old["content_sha256"], release_sequence=tool.BASE_SEQUENCE,
            runtime_files=len(files), online_cheats_allowed=False, signature_valid=True,
            full_before_verification=True, full_after_verification=True))
        (target / tool.MARKER).write_bytes(marker)
        caches = {name: ("original cache:" + name).encode() for name in tool.CACHES}
        for name, raw in caches.items(): (target / name).write_bytes(raw)
        context = dict(old=old, new=new, base=base, candidate=candidate, old_metadata={}, metadata={},
            patches={name: new_files[name] for name in modified | added},
            old_rows={r["path"]: r for r in old["files"]}, new_rows={r["path"]: r for r in new["files"]},
            modified=modified, added=added, removed=removed, controlled=modified | added | removed | {tool.MARKER})
        with ExitStack() as stack:
            for name, value in (("ROOT", root), ("BASE", base), ("BASE_SHA", old["content_sha256"]),
                ("BASE_FILES", len(files)), ("EXPECTED_FILES", len(new_files)), ("TARGET", target),
                ("CANDIDATE", candidate), ("TRUSTED", top / "trusted_new"),
                ("BASE_TRUSTED", top / "trusted_old"), ("CANDIDATE_SHA", new["content_sha256"]),
                ("OLD_MARKER_SHA", tool.web.sha(marker)),
                ("STORE", root / "output/arcade_payment_link_20261027/alias_transactions"),
                ("SHARED", root / "output/ui_qa_20261025/release/alias_updates")):
                stack.enter_context(patch.object(tool, name, value))
            releases = stack.enter_context(patch.object(tool, "releases", side_effect=lambda: dict(context)))
            stack.enter_context(patch.object(tool, "dota_pids", return_value=[]))
            yield SimpleNamespace(root=root, base=base, candidate=candidate, target=target, old=old, new=new,
                context=context, marker=marker, files=files, new_files=new_files, caches=caches,
                releases=releases, store=tool.STORE)


def images(root):
    return {name: (root / name).read_bytes() for name in tool.inventory(root)}


class InstallHelperTests(unittest.TestCase):
    def assert_old(self, data):
        tool.verify_runtime(data.target, data.old, data.marker)
        self.assertEqual((data.target / tool.MARKER).read_bytes(), data.marker)
        for name, raw in data.files.items(): self.assertEqual((data.target / name).read_bytes(), raw)
        for name in data.context["added"]: self.assertFalse((data.target / name).exists())

    def test_fixed_identity_and_missing_pin_refuse_before_source_or_alias_io(self):
        self.assertEqual(tool.BASE_SHA, "88611d026e49c52b5bce7324818f36a11a60059a2844b8f646b884ba15debaa9")
        self.assertEqual((tool.BASE_SEQUENCE, tool.BASE_FILES, tool.RELEASE_SEQUENCE, tool.EXPECTED_FILES),
                         (2026102503, 6630, 2026102701, 6639))
        self.assertEqual(tool.TARGET, tool.ROOT.parent / "svt_w24")
        with patch.object(tool, "CANDIDATE_SHA", None), patch.object(tool, "guard_release", side_effect=AssertionError("source IO")):
            with self.assertRaisesRegex(RuntimeError, "candidate_not_pinned"): tool.run()

    def test_default_audit_never_writes_and_may_report_dota_running(self):
        with fixture() as data, patch.object(tool, "dota_pids", return_value=[123]), \
                patch.object(tool, "write_new", side_effect=AssertionError("write")), \
                patch.object(tool, "atomic_document", side_effect=AssertionError("replace")):
            result = tool.run()
            self.assertTrue(result["ok"] and result["dry_run"] and result["dota_running"])
            self.assertFalse(result["private_key_read"])
            self.assertFalse(data.store.exists())
            self.assert_old(data)

    def test_apply_and_strict_rollback_preserve_bytes_marker_and_engine_caches(self):
        with fixture() as data:
            result = tool.run(apply=True)
            self.assertEqual(result["status"], "PAYMENT_HELPER_INSTALLED_FULLY_VERIFIED")
            transaction = Path(result["transaction"])
            self.assertEqual(tool.inventory(transaction / "backup"), data.context["modified"] | data.context["removed"] | {tool.MARKER})
            marker = json.loads((data.target / tool.MARKER).read_bytes())
            self.assertEqual(marker["kind"], "verified_online_policy_install")
            self.assertTrue(marker["full_before"] and marker["full_after"] and marker["signature_valid"])
            self.assertFalse(marker["online_cheats_allowed"])
            for name, raw in data.new_files.items(): self.assertEqual((data.target / name).read_bytes(), raw)
            self.assertTrue(tool.run()["dry_run"])
            self.assertFalse(any((data.target / name).exists() for name in tool.METADATA))
            for name in tool.CACHES: (data.target / name).write_bytes(b"newer native engine cache")
            restored = tool.run(restore=True)
            self.assertEqual(restored["status"], "BASELINE_RESTORED_FULLY_VERIFIED")
            self.assert_old(data)
            for name in tool.CACHES: self.assertEqual((data.target / name).read_bytes(), b"newer native engine cache")
            self.assertFalse((data.store / "active.json").exists())
            self.assertFalse((tool.SHARED / "active.lock").exists())
            self.assertTrue(transaction.exists(), "rollback evidence must remain")

    def test_dota_blocks_both_mutations_before_transaction_writes(self):
        with fixture() as data:
            with patch.object(tool, "dota_pids", return_value=[42]), self.assertRaisesRegex(RuntimeError, "dota_still_running"):
                tool.run(apply=True)
            self.assertFalse(data.store.exists())
            self.assert_old(data)
            tool.run(apply=True)
            before = images(data.target)
            with patch.object(tool, "dota_pids", return_value=[42]), self.assertRaisesRegex(RuntimeError, "dota_still_running"):
                tool.run(restore=True)
            self.assertEqual(images(data.target), before)

    def test_raw_inventory_marker_metadata_and_runtime_drift_refuse(self):
        for kind in ("extra", "metadata", "marker", "runtime"):
            with self.subTest(kind=kind), fixture() as data:
                if kind == "extra": (data.target / "scripts/user.txt").write_bytes(b"user")
                elif kind == "metadata": (data.target / tool.pack.handoff.MANIFEST).write_bytes(b"unreviewed metadata")
                elif kind == "marker": (data.target / tool.MARKER).write_bytes(data.marker + b" ")
                else: (data.target / "scripts/vscripts/addon_game_mode.lua").write_bytes(b"user edit")
                before = images(data.target)
                with self.assertRaises(RuntimeError): tool.run(apply=True)
                self.assertEqual(images(data.target), before)
                self.assertFalse(data.store.exists())

    def test_hardlinks_reparse_points_and_traversal_are_rejected(self):
        with fixture() as data:
            cache = data.target / sorted(tool.CACHES)[0]
            cache.unlink()
            os.link(data.target / "addoninfo.txt", cache)
            with self.assertRaisesRegex(RuntimeError, "links_forbidden"): tool.run(apply=True)
            self.assertFalse(data.store.exists())
        with fixture() as data:
            for unsafe in ("../outside.txt", "D:/outside", "/outside", "scripts/../../outside", "scripts\\..\\outside"):
                with self.subTest(path=unsafe), self.assertRaises(RuntimeError): tool.file_path(data.target, unsafe, exists=False)
            original = Path.lstat
            def reparse(path, *args, **kwargs):
                info = original(path, *args, **kwargs)
                if path == data.target:
                    return SimpleNamespace(st_mode=info.st_mode, st_file_attributes=0x400, st_nlink=info.st_nlink)
                return info
            with patch.object(Path, "lstat", reparse), self.assertRaisesRegex(RuntimeError, "links_forbidden"):
                tool.run()

    def test_every_partial_apply_or_marker_failure_restores_exact_baseline(self):
        for position in range(1, 6):
            with self.subTest(position=position), fixture() as data:
                original, count, failed = tool.cas_change, 0, False
                def injected(*args, **kwargs):
                    nonlocal count, failed
                    original(*args, **kwargs)
                    count += 1
                    if count == position and not failed:
                        failed = True
                        raise OSError("injected_after_cas")
                with patch.object(tool, "cas_change", side_effect=injected), self.assertRaises(tool.TransactionFailure) as caught:
                    tool.run(apply=True)
                self.assertTrue(caught.exception.report["recovery"]["ok"])
                self.assert_old(data)
                self.assertFalse((data.store / "active.json").exists())

    def test_concurrent_user_edit_is_never_overwritten_by_automatic_recovery(self):
        with fixture() as data:
            original, fired = tool.cas_change, False
            path = data.target / "scripts/vscripts/addon_game_mode.lua"
            def injected(*args, **kwargs):
                nonlocal fired
                original(*args, **kwargs)
                if not fired:
                    fired = True
                    path.write_bytes(b"user concurrent edit")
                    raise OSError("concurrent_edit")
            with patch.object(tool, "cas_change", side_effect=injected), self.assertRaises(tool.TransactionFailure) as caught:
                tool.run(apply=True)
            self.assertFalse(caught.exception.report["recovery"]["ok"])
            self.assertEqual(path.read_bytes(), b"user concurrent edit")
            self.assertTrue((data.store / "active.json").exists())
            with self.assertRaisesRegex(RuntimeError, "requires_active_complete_install"): tool.run(restore=True)

    def test_rollback_requires_matching_active_marker_backup_and_full_new_runtime(self):
        for kind in ("runtime", "backup", "marker", "extra", "state"):
            with self.subTest(kind=kind), fixture() as data:
                result = tool.run(apply=True)
                transaction = Path(result["transaction"])
                if kind == "runtime": (data.target / next(iter(data.context["added"]))).write_bytes(b"user new bytes")
                elif kind == "backup": (transaction / "backup/addoninfo.txt").write_bytes(b"changed backup")
                elif kind == "marker": (data.target / tool.MARKER).write_bytes(b"user marker")
                elif kind == "extra": (data.target / "notes.txt").write_bytes(b"user notes")
                else:
                    state = json.loads((transaction / "state.json").read_bytes())
                    state["status"] = "APPLYING"
                    (transaction / "state.json").write_bytes(tool.canonical(state))
                before = images(data.target)
                with self.assertRaises(RuntimeError): tool.run(restore=True)
                self.assertEqual(images(data.target), before)

    def test_insufficient_delta_backup_space_cannot_start_transaction(self):
        with fixture() as data, patch.object(tool.shutil, "disk_usage", return_value=shutil._ntuple_diskusage(0, 0, 0)):
            with self.assertRaisesRegex(RuntimeError, "delta_backup_space"): tool.run(apply=True)
            self.assertFalse(data.store.exists())
            self.assert_old(data)

    def test_literal_configuration_never_executes_or_accepts_dynamic_fields(self):
        with tempfile.TemporaryDirectory(prefix="helper-literal-test-") as folder:
            root = Path(folder).resolve()
            path = root / "config.lua"
            for raw in (b'return { enabled = true }\n', b'-- comment\nreturn {enabled=true,}\n'):
                path.write_bytes(raw)
                tool.literal_config(root, "config.lua", {"enabled": True})
            for raw in (b'return {enabled=false}', b'return {enabled=true,enabled=true}',
                        b'return {enabled=os.execute("bad")}', b'return {enabled=true}; os.execute("bad")'):
                path.write_bytes(raw)
                with self.assertRaises(RuntimeError): tool.literal_config(root, "config.lua", {"enabled": True})

    def test_real_signature_and_full_hash_verification_fail_before_alias_mutation(self):
        real_releases = tool.releases
        real_authenticate = tool.pack.authenticate
        for failure in ("old_signature", "new_signature", "new_runtime", "wrong_roster"):
            with self.subTest(failure=failure), fixture() as data, ExitStack() as stack:
                private = Ed25519PrivateKey.generate()
                public = private.public_key()
                public_path = data.root.parent / "fixture_public.pem"
                public_path.write_bytes(public.public_bytes(serialization.Encoding.PEM,
                                                           serialization.PublicFormat.SubjectPublicKeyInfo))
                key_id = tool.pack.protect_data.public_id(public)
                for source, doc, sequence in ((data.base, data.old, tool.BASE_SEQUENCE),
                                              (data.candidate, data.new, tool.RELEASE_SEQUENCE)):
                    signed = private.sign(tool.pack.protect_data.DOMAIN + struct.pack(">Q", sequence)
                                          + tool.pack.runtime.manifest_payload(doc))
                    if failure == ("old_signature" if source == data.base else "new_signature"):
                        signed = bytes([signed[0] ^ 1]) + signed[1:]
                    (source / tool.pack.handoff.MANIFEST).write_bytes(tool.canonical(doc))
                    (source / tool.pack.handoff.SIGNATURE).write_bytes(tool.canonical(dict(schema=2,
                        algorithm="Ed25519", release_sequence=sequence, key_id=key_id,
                        content_sha256=doc["content_sha256"], signature=base64.b64encode(signed).decode("ascii"))))
                if failure == "new_runtime":
                    (data.candidate / "scripts/vscripts/addon_game_mode.lua").write_bytes(b"tampered signed runtime")
                # Only the fixture's trust source and unrelated game gates are stubbed.
                # Both actual Ed25519 verification and full runtime hashing still run.
                stack.enter_context(patch.object(tool, "releases", side_effect=real_releases))
                stack.enter_context(patch.object(tool, "guard_release"))
                stack.enter_context(patch.object(tool.pack.handoff, "trusted_policy", return_value=({
                    "integrity": {"minimum_release_sequence": 2026102101, "trusted_key_id": key_id}}, public_path)))
                stack.enter_context(patch.object(tool.pack.handoff, "require_single_map"))
                stack.enter_context(patch.object(tool.pack.handoff, "require_reviewed_gate"))
                stack.enter_context(patch.object(tool.pack.handoff, "configured_ids", return_value=(
                    sorted(tool.ROSTER)[:-1] if failure == "wrong_roster" else tool.ROSTER)))
                authenticate = stack.enter_context(patch.object(tool.pack, "authenticate", side_effect=real_authenticate))
                before = images(data.target)
                if failure.endswith("signature"):
                    with self.assertRaises(InvalidSignature): tool.run(apply=True)
                else:
                    expected = "full inventory/hash" if failure == "new_runtime" else "four_accounts_required"
                    with self.assertRaisesRegex((ValueError, RuntimeError), expected): tool.run(apply=True)
                self.assertEqual(authenticate.call_count, 1 if failure == "old_signature" else 2)
                self.assertEqual(images(data.target), before)
                self.assertFalse(data.store.exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
