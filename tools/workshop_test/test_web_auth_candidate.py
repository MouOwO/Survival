"""Small fixtures for frozen patching, signed provenance, and overlay isolation."""
import difflib
import hashlib
from pathlib import Path
import struct
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_web_auth_candidate as candidate


def reviewed_diff(before, after, relative):
    return ("diff --git a/" + relative + " b/" + relative + "\n" + "".join(difflib.unified_diff(
        before.decode().splitlines(keepends=True), after.decode().splitlines(keepends=True),
        fromfile="a/" + relative, tofile="b/" + relative))).encode()


def resource():
    return struct.pack("<IHHII4sII", 32, 12, 1, 8, 1, b"DATA", 8, 4) + b"test"


def manifest(files):
    rows = [{"path": name, "bytes": len(raw), "md5": hashlib.md5(raw).hexdigest(),
             "sha256": hashlib.sha256(raw).hexdigest()} for name, raw in sorted(files.items())]
    result = {"schema": 2, "kind": "runtime_release_allowlist", "hash_algorithms": ["md5", "sha256"],
              "file_count": len(rows), "bytes": sum(row["bytes"] for row in rows), "files": rows}
    result["content_sha256"] = candidate.sha(candidate.pack.runtime.manifest_payload(result))
    return result


class FrozenCandidateTest(unittest.TestCase):
    def test_fixed_baseline_diff_survives_a_real_fix_commit(self):
        relative = candidate.PATCHED_LUA[0]
        with tempfile.TemporaryDirectory(prefix="ws4-git-baseline-") as folder:
            root = Path(folder)
            candidate.git("init", root=root)
            candidate.git("config", "user.name", "WS4 fixture", root=root)
            candidate.git("config", "user.email", "fixture@example.invalid", root=root)
            candidate.git("config", "core.autocrlf", "false", root=root)
            target = root / relative
            target.parent.mkdir(parents=True)
            before = b"local transport = 'original'\nreturn transport\n"
            after = b"local transport = 'player-web-session'\nreturn transport\n"
            target.write_bytes(before)
            candidate.git("add", "--", relative, root=root)
            candidate.git("commit", "-m", "Immutable task baseline fixture", root=root)
            baseline = candidate.git("rev-parse", "HEAD", root=root).decode("ascii").strip()
            target.write_bytes(after)
            uncommitted = candidate.task_diff(relative, root=root, baseline=baseline)
            self.assertTrue(uncommitted)
            candidate.git("add", "--", relative, root=root)
            candidate.git("commit", "-m", "Commit player web transport fixture", root=root)
            self.assertEqual(candidate.git("diff", "HEAD", "--", relative, root=root), b"")
            committed = candidate.task_diff(relative, root=root, baseline=baseline)
            self.assertEqual(committed, uncommitted)
            self.assertEqual(candidate.patch_bytes(before, committed, relative), after)

    def test_strict_patch_preserves_unrelated_frozen_lines_and_crlf(self):
        relative = candidate.PATCHED_LUA[0]
        head = "".join("line-%02d\n" % index for index in range(30)).encode()
        after = head.replace(b"line-15\n", b"reviewed-auth-only\n")
        frozen = head.replace(b"line-29\n", b"old-gameplay-stays\n").replace(b"\n", b"\r\n")
        patched = candidate.patch_bytes(frozen, reviewed_diff(head, after, relative), relative)
        self.assertEqual(patched, frozen.replace(b"line-15\r\n", b"reviewed-auth-only\r\n"))

    def test_absent_or_ambiguous_patch_context_is_rejected(self):
        relative = candidate.PATCHED_LUA[0]
        before = b"a\nb\nc\nold\nd\ne\nf\n"
        diff = reviewed_diff(before, before.replace(b"old", b"new"), relative)
        for frozen in (before.replace(b"old", b"different"), before + before):
            with self.assertRaisesRegex(ValueError, "context absent or ambiguous"):
                candidate.patch_bytes(frozen, diff, relative)

    def test_patch_cannot_include_unrelated_file_or_binary_replacement(self):
        relative = candidate.PATCHED_LUA[0]
        diff = reviewed_diff(b"old\n", b"new\n", relative)
        for changed in (diff + b"diff --git a/other.lua b/other.lua\n", diff + b"GIT binary patch\n"):
            with self.assertRaises(ValueError):
                candidate.patch_bytes(b"old\n", changed, relative)

    def test_compiled_resource_size_and_blocks_are_checked(self):
        candidate.validate_compiled(resource(), candidate.COMPILED[0])
        for broken in (resource()[:-1], b"\x00" * 32,
                       resource()[:20] + struct.pack("<I", 0xFFFFFFFF) + resource()[24:]):
            with self.assertRaises(ValueError):
                candidate.validate_compiled(broken, candidate.COMPILED[0])

    def test_overlay_contains_exact_three_resources_without_extra_assets(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for name in candidate.COMPILED:
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(resource())
            self.assertEqual(set(candidate.read_overlay(root)), set(candidate.COMPILED))
            (root / "unreviewed.vtex_c").write_bytes(resource())
            with self.assertRaisesRegex(ValueError, "exactly the three"):
                candidate.read_overlay(root)

    def test_audit_rejects_unlisted_resource_or_protected_gameplay_change(self):
        protected = "scripts/vscripts/config/generated/protected.lua"
        baseline_files = {candidate.PATCHED_LUA[0]: b"old provider", candidate.PATCHED_LUA[1]: b"old startup",
                          candidate.COMPILED[2]: b"old layout", protected: b"protected gameplay"}
        patches = {name: ("new:" + name).encode() for name in candidate.ALLOWLIST}
        new_files = dict(baseline_files, **patches)
        old = manifest(baseline_files)
        self.assertEqual(len(candidate.audit_changes(old, manifest(new_files), patches, [protected])), 7)
        new_files[protected] = b"unreviewed replacement"
        with self.assertRaises(ValueError):
            candidate.audit_changes(old, manifest(new_files), patches, [protected])

    def test_actual_ed25519_signature_binds_both_file_hashes_and_sequence(self):
        from cryptography.hazmat.primitives import serialization
        from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            key = Ed25519PrivateKey.generate()
            private = root / "private.pem"
            public = root / "public.pem"
            private.write_bytes(key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                                                   serialization.NoEncryption()))
            public.write_bytes(key.public_key().public_bytes(serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo))
            value = manifest({"scripts/vscripts/example.lua": b"return true\n"})
            inventory = root / "manifest.json"
            signature = root / "signature.json"
            candidate.pack.runtime.atomic_write_json(inventory, value)
            candidate.pack.protect_data.sign_manifest(inventory, private, signature, 2026102401)
            document = candidate.pack.handoff.load_json(signature)
            key_id = candidate.pack.protect_data.public_id(key.public_key())
            self.assertTrue(candidate.pack.verify_signed_snapshot(value, document, public, 2026102401, key_id)["signature_valid"])
            value["files"][0]["md5"] = "0" * 32
            value["content_sha256"] = candidate.sha(candidate.pack.runtime.manifest_payload(value))
            with self.assertRaises(Exception):
                candidate.pack.verify_signed_snapshot(value, document, public, 2026102401, key_id)
            with self.assertRaises(ValueError):
                candidate.pack.verify_signed_snapshot(manifest({"scripts/vscripts/example.lua": b"return true\n"}),
                                                       document, public, 2026102402, key_id)

    def test_default_cli_never_builds_or_requires_a_private_key(self):
        args = candidate.parser().parse_args([])
        self.assertFalse(args.build)
        self.assertIsNone(args.signing_key)
        self.assertEqual(args.sequence, 2026102401)


if __name__ == "__main__":
    unittest.main()
