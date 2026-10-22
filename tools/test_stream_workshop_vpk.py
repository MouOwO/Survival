"""Small real-signed VPK roundtrips; no production package or upload is made."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zlib

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

spec = importlib.util.spec_from_file_location("stream_vpk", Path(__file__).with_name("stream_workshop_vpk.py"))
vpk = importlib.util.module_from_spec(spec)
spec.loader.exec_module(vpk)


class StreamingVPKTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve()
        self.source, self.candidate, self.output = [self.base / n for n in ("trusted", "candidate", "vpk-output")]
        for folder in (self.source, self.candidate, self.output):
            folder.mkdir()
        self.write("addoninfo.txt", b'"AddonInfo" { "maps" "template_map" "IsPlayable" "1" "template_map" {"MaxPlayers" "4"} }')
        self.write(vpk.runtime.RELEASE_PROFILE, b'return {channel="production"}')
        self.write(vpk.handoff.ACCESS_FILE, ('return {enabled=true, allowed_steamids={' +
                   ','.join(json.dumps(str(vpk.handoff.STEAM_BASE + n)) for n in (101, 102, 103, 104)) + '}}').encode())
        for name in vpk.runtime.CRITICAL | vpk.runtime.map_files(self.candidate):
            if not (self.candidate / name).exists():
                self.write(name, b"return {}" if name.endswith(".lua") else b"native test fixture")
        for name in vpk.handoff.GATE_FILES:
            raw = (vpk.handoff.ROOT / name).read_bytes()
            self.write(name, raw)
            trusted = self.source / name
            trusted.parent.mkdir(parents=True, exist_ok=True)
            trusted.write_bytes(raw)
        self.write("panorama/images/test/empty.vtex_c", b"")
        self.write("panorama/images/test/spaced binary.vtex_c", bytes(range(256)) * 9)
        self.write("panorama/images/test/chunked.vtex_c", b"\x00\xfe\x05" * (vpk.CHUNK // 3 + 33))
        # Metadata outside the signed runtime inventory must never enter VPK.
        self.write("docs/private.md", b"not a runtime file")
        self.key = Ed25519PrivateKey.generate()
        self.private = self.base / "private.pem"
        self.private.write_bytes(self.key.private_bytes(serialization.Encoding.PEM,
                                 serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
        (self.source / "public.pem").write_bytes(self.key.public_key().public_bytes(
            serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo))
        policy = json.loads(vpk.handoff.POLICY.read_text(encoding="utf-8"))
        policy["integrity"].update(trusted_public_key="public.pem", minimum_release_sequence=10,
                                   trusted_key_id=vpk.protect_data.public_id(self.key.public_key()))
        policy_path = self.source / "policy.json"
        policy_path.write_text(json.dumps(policy), encoding="utf-8")
        for name, value in (("ROOT", self.source), ("POLICY", policy_path)):
            context = patch.object(vpk.handoff, name, value)
            context.start(); self.addCleanup(context.stop)
        self.seal()

    def write(self, name, data):
        path = self.candidate / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)

    def seal(self, sequence=10):
        self.manifest = vpk.runtime.manifest(self.candidate)
        (self.candidate / vpk.handoff.MANIFEST).write_text(json.dumps(self.manifest), encoding="utf-8")
        signature = self.candidate / vpk.handoff.SIGNATURE
        signature.unlink(missing_ok=True)
        vpk.protect_data.sign_manifest(self.candidate / vpk.handoff.MANIFEST, self.private, signature, sequence)

    def build(self, **kwargs):
        return vpk.package(self.candidate, self.output, "123456789", build=True, **kwargs)

    def test_default_is_read_only_with_real_signature_full_hashes_and_no_private_metadata(self):
        result = vpk.package(self.candidate, self.output, "123456789")
        self.assertEqual(result["status"], "VERIFIED_DRY_RUN")
        self.assertTrue(result["signature_valid"])
        self.assertTrue(result["full_input_hash_verification"])
        self.assertFalse(result["ready_for_upload"])
        self.assertEqual(list(self.output.iterdir()), [])

    def test_real_roundtrip_streams_and_independent_existing_reader_matches_every_payload(self):
        node = shutil.which("node")
        self.assertIsNotNone(node, "Independent existing Node parser is required for this regression")
        large = self.candidate / "panorama/images/test/chunked.vtex_c"
        original_open = Path.open
        reads = []

        class BoundedRead:
            def __init__(self, file): self.file = file
            def __enter__(self): return self
            def __exit__(self, *args): return self.file.__exit__(*args)
            def __getattr__(self, name): return getattr(self.file, name)
            def read(self, size=-1):
                if not 0 <= size <= vpk.CHUNK:
                    raise AssertionError("Unbounded source read")
                reads.append(size)
                return self.file.read(size)

        def bounded(path, *args, **kwargs):
            file = original_open(path, *args, **kwargs)
            return BoundedRead(file) if path == large else file

        with patch.object(Path, "open", bounded):
            result = self.build()
        self.assertGreater(len(reads), 3)
        self.assertEqual(result["status"], "BUILT_AND_VERIFIED_FOR_NATIVE_TEST_ONLY")
        self.assertEqual(result["native_over_2gib_read_test"], "NOT_RUN")
        self.assertFalse(result["workshop_upload_performed"])
        path = Path(result["output"])
        self.assertEqual(path.stat().st_size, result["container_bytes"])
        script = ("const crypto=require('crypto'); const p=require(process.argv[1]).open(process.argv[2]);"
                  "const rows=p.entries.map(e=>({path:e.path,bytes:p.read(e).length,"
                  "sha256:crypto.createHash('sha256').update(p.read(e)).digest('hex')}));"
                  "process.stdout.write(JSON.stringify(rows));")
        parser = Path(__file__).with_name("vpk_inspect.cjs").resolve()
        rows = json.loads(subprocess.check_output([node, "-e", script, str(parser), str(path)], text=True))
        expected = [{key: row[key] for key in ("path", "bytes", "sha256")} for row in self.manifest["files"]]
        self.assertEqual(sorted(rows, key=lambda row: row["path"]), expected)
        self.assertNotIn(vpk.handoff.MANIFEST, {row["path"] for row in rows})
        self.assertEqual(list(self.output.iterdir()), [path])

    def test_tampered_payload_signature_wrong_key_rollback_and_extra_runtime_fail_before_output(self):
        payload = "panorama/images/test/spaced binary.vtex_c"
        original = (self.candidate / payload).read_bytes()
        self.write(payload, original + b"changed")
        with self.assertRaisesRegex(ValueError, "full inventory"):
            self.build()
        self.write(payload, original); self.seal(sequence=9)
        with self.assertRaisesRegex(ValueError, "sequence"):
            self.build()
        self.seal()
        signature = self.candidate / vpk.handoff.SIGNATURE
        document = json.loads(signature.read_text(encoding="utf-8"))
        document["signature"] = "A" * 88
        signature.write_text(json.dumps(document), encoding="utf-8")
        with self.assertRaises(Exception):
            self.build()
        self.seal()
        other = Ed25519PrivateKey.generate()
        self.private.write_bytes(other.private_bytes(serialization.Encoding.PEM,
                                 serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
        self.seal()
        with self.assertRaisesRegex(ValueError, "identity"):
            self.build()
        self.private.write_bytes(self.key.private_bytes(serialization.Encoding.PEM,
                                 serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
        self.seal()
        self.write("scripts/vscripts/unlisted.lua", b"return {}")
        with self.assertRaisesRegex(ValueError, "full inventory"):
            self.build()
        self.assertEqual(list(self.output.iterdir()), [])

    def test_manifest_replaced_during_signature_verification_is_detected(self):
        real_verify = vpk.verify_signed_snapshot

        def swap(*args, **kwargs):
            result = real_verify(*args, **kwargs)
            path = self.candidate / vpk.handoff.MANIFEST
            path.write_bytes(path.read_bytes() + b"\n")
            return result

        with patch.object(vpk, "verify_signed_snapshot", side_effect=swap):
            with self.assertRaisesRegex(ValueError, "Signed inventory changed"):
                self.build()
        self.assertEqual(list(self.output.iterdir()), [])

    def test_source_changes_after_initial_verification_never_publish_partial_output(self):
        original = vpk.copy_payload
        changed = False

        def mutate(source, stream, row):
            nonlocal changed
            if not changed:
                changed = True
                source.write_bytes(source.read_bytes() + b"late")
            return original(source, stream, row)

        with patch.object(vpk, "copy_payload", side_effect=mutate):
            with self.assertRaisesRegex(ValueError, "grew|changed/hash"):
                self.build()
        self.assertEqual(list(self.output.iterdir()), [])

    def test_existing_output_and_invalid_id_and_internal_or_overlapping_output_rejected(self):
        target = self.output / "123456789.vpk"
        target.write_bytes(b"keep")
        with self.assertRaisesRegex(ValueError, "existing VPK"):
            self.build()
        self.assertEqual(target.read_bytes(), b"keep")
        for value in ("0", "../1", "survival", "01", str(2**64)):
            with self.subTest(value=value), self.assertRaises(ValueError):
                vpk.package(self.candidate, self.output, value, build=True)
        for output in (self.candidate, self.source, vpk.handoff.INSTALL):
            with self.subTest(output=output), self.assertRaisesRegex(ValueError, "external|overlap"):
                vpk.package(self.candidate, output, "98", build=True)

    def test_signed_unsafe_or_case_duplicate_manifest_is_rejected_before_output(self):
        for path in ("../escape.lua", "scripts/vscripts/../../escape.lua", "scripts/vscripts/a.lua:ads"):
            manifest = copy.deepcopy(self.manifest)
            manifest["files"][0]["path"] = path
            manifest["files"].sort(key=lambda row: row["path"])
            manifest["content_sha256"] = hashlib.sha256(vpk.runtime.manifest_payload(manifest)).hexdigest()
            (self.candidate / vpk.handoff.MANIFEST).write_text(json.dumps(manifest), encoding="utf-8")
            with self.subTest(path=path), self.assertRaises(ValueError):
                self.build()
        manifest = copy.deepcopy(self.manifest)
        duplicate = copy.deepcopy(manifest["files"][0])
        duplicate["path"] = duplicate["path"].upper()
        manifest["files"].append(duplicate)
        manifest["files"].sort(key=lambda row: row["path"])
        (self.candidate / vpk.handoff.MANIFEST).write_text(json.dumps(manifest), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "Duplicate manifest path"):
            self.build()
        self.assertEqual(list(self.output.iterdir()), [])

    def test_container_corruption_crc_offset_terminator_truncation_and_section_digest_rejected(self):
        result = self.build()
        path = Path(result["output"])
        original = path.read_bytes()
        tree, ordered, _ = vpk.make_tree(self.manifest["files"])
        first = vpk.HEADER.size + ordered[0]["crc_position"]
        mutations = []
        damaged = bytearray(original); damaged[first] ^= 0xFF
        mutations.append((damaged, "CRC32"))
        damaged = bytearray(original)
        data_start = vpk.HEADER.size + len(tree)
        length = ordered[0]["row"]["bytes"]
        damaged[data_start] ^= 1
        struct.pack_into("<I", damaged, first, zlib.crc32(damaged[data_start:data_start + length]))
        mutations.append((damaged, "authenticated hash"))
        damaged = bytearray(original); struct.pack_into("<I", damaged, first + 8, 0xFFFFFFFF)
        mutations.append((damaged, "offset"))
        damaged = bytearray(original); damaged[first + 16] = 0
        mutations.append((damaged, "terminator"))
        damaged = bytearray(original); damaged[-48] ^= 1
        mutations.append((damaged, "section MD5"))
        damaged = bytearray(original); damaged[-1] ^= 1
        mutations.append((damaged, "whole-file MD5"))
        mutations.append((original[:-1], "size mismatch"))
        for raw, message in mutations:
            path.write_bytes(raw)
            with self.subTest(message=message), self.assertRaisesRegex(ValueError, message):
                vpk.verify_vpk(path, self.manifest)

    def test_unsigned_offset_boundary_and_64bit_seek_without_large_allocation(self):
        rows = [{"path": "a.bin", "bytes": 0x80000001}, {"path": "b.bin", "bytes": 7}]
        tree, ordered, total = vpk.make_tree(rows)
        self.assertEqual(total, 0x80000008)
        parsed = vpk.read_tree(tree)
        self.assertEqual(parsed[1]["offset"], 0x80000001)
        self.assertEqual(ordered[1]["offset"], 0x80000001)
        with tempfile.TemporaryFile() as file:
            self.assertEqual(file.seek(0x80000004), 0x80000004)
            self.assertEqual(file.tell(), 0x80000004)
            self.assertEqual(file.seek(0, 2), 0)  # Seek only; never allocate a >2 GiB file.
        for size in (0x100000000, -1, True):
            with self.subTest(size=size), self.assertRaisesRegex(ValueError, "uint32"):
                vpk.make_tree([{"path": "a.bin", "bytes": size}])
        with self.assertRaisesRegex(ValueError, "uint32"):
            vpk.make_tree([{"path": "a.bin", "bytes": 0xFFFFFFFF}, {"path": "b.bin", "bytes": 1}])

    def test_tree_roundtrip_root_extensionless_nested_and_multiple_dots(self):
        names = ["README", "root.txt", "folder/a.more.bin", "folder/zero.bin"]
        tree, _, total = vpk.make_tree([{"path": name, "bytes": 0} for name in names])
        self.assertEqual({entry["path"] for entry in vpk.read_tree(tree)}, set(names))
        self.assertEqual(total, 0)

    def test_metadata_limits_fail_before_build_or_tree_overallocation(self):
        with patch.object(vpk, "MAX_MANIFEST", 16):
            with self.assertRaisesRegex(ValueError, "bounded read limit"):
                self.build()
        with patch.object(vpk, "MAX_TREE", 32):
            with self.assertRaisesRegex(ValueError, "bounded metadata limit"):
                vpk.make_tree([{"path": "a/" + "x" * 100 + ".bin", "bytes": 0}])
        self.assertEqual(list(self.output.iterdir()), [])

    def test_target_appearing_during_build_is_never_overwritten(self):
        real_link = vpk.os.link
        target = self.output / "123456789.vpk"

        def race(source, destination):
            target.write_bytes(b"other producer's original")
            return real_link(source, destination)

        with patch.object(vpk.os, "link", side_effect=race):
            with self.assertRaises(FileExistsError):
                self.build()
        self.assertEqual(target.read_bytes(), b"other producer's original")
        self.assertEqual(list(self.output.iterdir()), [target])

    def test_key_replaced_after_trust_check_cannot_change_the_pinned_identity(self):
        other = Ed25519PrivateKey.generate()
        self.private.write_bytes(other.private_bytes(serialization.Encoding.PEM,
                                 serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
        self.seal()
        real_policy = vpk.handoff.trusted_policy

        def swap(*args, **kwargs):
            policy, public_path = real_policy(*args, **kwargs)
            public_path.write_bytes(other.public_key().public_bytes(serialization.Encoding.PEM,
                                     serialization.PublicFormat.SubjectPublicKeyInfo))
            return policy, public_path

        with patch.object(vpk.handoff, "trusted_policy", side_effect=swap):
            with self.assertRaisesRegex(ValueError, "identity"):
                self.build()
        self.assertEqual(list(self.output.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
