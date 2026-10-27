"""Real Ed25519 fixtures; no production resources, Steam calls or publication."""
import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import incremental_vpk as tool

fixture_spec = importlib.util.spec_from_file_location("original_stream_vpk_tests",
    HERE.parent / "test_stream_workshop_vpk.py")
fixture_module = importlib.util.module_from_spec(fixture_spec)
fixture_spec.loader.exec_module(fixture_module)


class IncrementalVPKTests(unittest.TestCase):
    def setUp(self):
        self.fixture = fixture_module.StreamingVPKTests()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        fixture = self.fixture
        policy = fixture.source / "tools/release_security/protection_policy.json"
        policy.parent.mkdir(parents=True)
        shutil.copyfile(fixture.source / "policy.json", policy)
        self.initial = fixture.build_split()
        self.base_vpk = Path(self.initial["output"])
        self.base_manifest = fixture.manifest
        self.overlay, self.view, self.output = [fixture.base / name for name in ("thin", "view", "new-vpk")]
        self.overlay.mkdir()
        self.output.mkdir()
        values = dict(BASE=fixture.candidate, BASE_TRUSTED=fixture.source, BASE_VPK=self.base_vpk,
            BASE_CONTENT=self.base_manifest["content_sha256"], BASE_COUNT=self.base_manifest["file_count"],
            BASE_SEQUENCE=10, NATIVE_SEQUENCE=11, HELPER_SEQUENCE=12, ITEM="123456789",
            BASE_PACKAGE=tool.pack.package_inventory(self.base_vpk), RESERVE=0)
        for name, value in values.items():
            context = patch.object(tool, name, value)
            context.start(); self.addCleanup(context.stop)
        context = patch.object(tool.pack, "ARCHIVE_BYTES", tool.pack.CHUNK + 256)
        context.start(); self.addCleanup(context.stop)
        self.base_hashes = {path: tool.pack.runtime.digest(path) for path in tool.pack.package_paths(self.base_vpk)}
        self.old_file_hashes = {row["path"]: row["sha256"] for row in self.base_manifest["files"]}
        self.reseal({"panorama/images/test/spaced binary.vtex_c": b"changed small fixture"})

    def reseal(self, replacements, *, deleted=(), sequence=11):
        for child in list(self.overlay.iterdir()):
            if child.is_dir():
                shutil.rmtree(child)
            else:
                child.unlink()
        manifest = copy.deepcopy(self.base_manifest)
        rows = {row["path"]: row for row in manifest["files"] if row["path"] not in deleted}
        for relative, raw in replacements.items():
            path = self.overlay / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(raw)
            rows[relative] = dict(path=relative, bytes=len(raw),
                md5=hashlib.md5(raw, usedforsecurity=False).hexdigest(), sha256=hashlib.sha256(raw).hexdigest())
        manifest["files"] = [rows[path] for path in sorted(rows)]
        manifest["file_count"] = len(rows)
        manifest["bytes"] = sum(row["bytes"] for row in rows.values())
        manifest["content_sha256"] = hashlib.sha256(tool.pack.runtime.manifest_payload(manifest)).hexdigest()
        (self.overlay / tool.pack.handoff.MANIFEST).write_text(json.dumps(manifest), encoding="utf8")
        tool.pack.protect_data.sign_manifest(self.overlay / tool.pack.handoff.MANIFEST,
            self.fixture.private, self.overlay / tool.pack.handoff.SIGNATURE, sequence)
        self.manifest = manifest

    def run_tool(self, *, build=False, reuse="hardlink", sequence=11, view=None, output=None):
        return tool.run(self.overlay, view or self.view, output or self.output, build=build,
                        reuse=reuse, sequence=sequence, review_root=self.fixture.source)

    def assert_base_unchanged(self):
        self.assertEqual(self.base_hashes,
            {path: tool.pack.runtime.digest(path) for path in tool.pack.package_paths(self.base_vpk)})
        self.assertTrue(tool.pack.runtime.verify(self.fixture.candidate, self.base_manifest)["ok"])

    def test_default_is_read_only_and_reports_only_impacted_volumes(self):
        result = self.run_tool()
        changed_entry = next(row for row in tool.read_entries(self.base_vpk)
            if row["path"] == "panorama/images/test/spaced binary.vtex_c")
        self.assertEqual(result["rebuilt_archives"], [changed_entry["archive"]])
        self.assertFalse(self.view.exists())
        self.assertEqual(list(self.output.iterdir()), [])
        self.assertTrue(result["signature_valid"])
        self.assertFalse(result["workshop_upload_performed"])
        self.assert_base_unchanged()

    def test_build_real_signed_roundtrip_reuses_unchanged_inodes_and_preserves_base(self):
        result = self.run_tool(build=True)
        self.assertTrue(result["immutable_base_unchanged"])
        self.assertTrue(result["full_runtime_validator_passed"])
        output = Path(result["output"])
        self.assertEqual(result["package_files"], tool.pack.package_inventory(output))
        verification = tool.pack.verify_vpk(output, self.manifest)
        self.assertTrue(verification["manifest_dual_hashes_verified"])
        for index in result["reused_archives"]:
            self.assertTrue(os.path.samefile(output.with_name(f"123456789_{index:03}.vpk"),
                                            self.base_vpk.with_name(f"123456789_{index:03}.vpk")))
        for index in result["rebuilt_archives"]:
            self.assertFalse(os.path.samefile(output.with_name(f"123456789_{index:03}.vpk"),
                                             self.base_vpk.with_name(f"123456789_{index:03}.vpk")))
        changed = set(result["changed_runtime_paths"])
        for relative in self.old_file_hashes:
            self.assertEqual(os.path.samefile(self.view / relative, self.fixture.candidate / relative),
                             relative not in changed)
        self.assert_base_unchanged()
        # Independent existing Node reader verifies the new grouping too.
        node = shutil.which("node")
        self.assertIsNotNone(node)
        script = ("const c=require('crypto'),p=require(process.argv[1]).open(process.argv[2]);"
                  "process.stdout.write(JSON.stringify(p.entries.map(e=>({path:e.path,"
                  "sha256:c.createHash('sha256').update(p.read(e)).digest('hex')}))));")
        observed = json.loads(subprocess.check_output([node, "-e", script,
            str(HERE.parent / "vpk_inspect.cjs"), str(output)], text=True))
        self.assertEqual(sorted(observed, key=lambda row: row["path"]),
            [{"path": row["path"], "sha256": row["sha256"]} for row in self.manifest["files"]])

    def test_copy_reuse_and_repeat_build_are_identical_without_sharing_volumes(self):
        first = self.run_tool(build=True, reuse="copy")
        second_output, second_view = self.fixture.base / "second-vpk", self.fixture.base / "second-view"
        second = self.run_tool(build=True, output=second_output, view=second_view)
        self.assertEqual(first["package_files"], second["package_files"])
        for index in first["reused_archives"]:
            self.assertFalse(os.path.samefile(self.output / f"123456789_{index:03}.vpk",
                                             self.base_vpk.with_name(f"123456789_{index:03}.vpk")))
        self.assert_base_unchanged()

    def test_multiple_changed_archives_and_added_resource_keep_existing_assignments(self):
        entries = tool.read_entries(self.base_vpk)
        candidates = [row for row in entries if row["path"].startswith("panorama/images/test/")]
        selected = {}
        for row in candidates:
            selected.setdefault(row["archive"], row["path"])
        self.assertGreaterEqual(len(selected), 2)
        changes = {path: b"shortened " + str(index).encode() for index, path in selected.items()}
        changes["panorama/images/test/new.vtex_c"] = b"new resource"
        self.reseal(changes)
        result = self.run_tool(build=True)
        self.assertEqual(result["rebuilt_archives"], sorted(set(selected) | {entries[-1]["archive"]}))
        old_assignments = {row["path"]: row["archive"] for row in entries}
        new_assignments = {row["path"]: row["archive"] for row in tool.read_entries(Path(result["output"]))}
        for path, index in old_assignments.items():
            self.assertEqual(new_assignments[path], index)
        self.assert_base_unchanged()

    def test_tampered_or_extra_overlay_and_bad_signature_fail_before_materialization(self):
        path = self.overlay / "panorama/images/test/spaced binary.vtex_c"
        raw = path.read_bytes()
        path.write_bytes(raw + b"tampered")
        with self.assertRaisesRegex(ValueError, "hash mismatch"):
            self.run_tool(build=True)
        path.write_bytes(raw)
        extra = self.overlay / "secret.txt"
        extra.write_bytes(b"not runtime")
        with self.assertRaisesRegex(ValueError, "exactly changed"):
            self.run_tool(build=True)
        extra.unlink()
        signature = self.overlay / tool.pack.handoff.SIGNATURE
        document = json.loads(signature.read_text())
        document["signature"] = "A" * 88
        signature.write_text(json.dumps(document))
        with self.assertRaises(Exception):
            self.run_tool(build=True)
        self.assertFalse(self.view.exists())
        self.assertEqual(list(self.output.iterdir()), [])

    def test_wrong_sequence_changed_gate_or_roster_and_overflow_are_rejected(self):
        self.reseal({"panorama/images/test/spaced binary.vtex_c": b"x"}, sequence=10)
        with self.assertRaisesRegex(ValueError, "sequence"):
            self.run_tool(build=True)
        self.reseal({tool.pack.handoff.GATE_FILES[0]: b"return {}"})
        with self.assertRaisesRegex(ValueError, "admission guard"):
            self.run_tool(build=True)
        self.reseal({tool.pack.handoff.ACCESS_FILE: b"return {enabled=false,allowed_steamids={}}"})
        with self.assertRaisesRegex(ValueError, "access"):
            self.run_tool(build=True)
        self.reseal({"panorama/images/test/spaced binary.vtex_c": b"a" * tool.pack.ARCHIVE_BYTES})
        with self.assertRaisesRegex(ValueError, "archive exceeds"):
            self.run_tool(build=True)
        self.assertFalse(self.view.exists())

    def test_base_volume_tampering_and_incorrect_base_pin_are_rejected(self):
        with patch.object(tool, "BASE_CONTENT", "a" * 64):
            with self.assertRaisesRegex(ValueError, "identity"):
                self.run_tool(build=True)
        volume = tool.pack.package_paths(self.base_vpk)[1]
        raw = volume.read_bytes()
        volume.write_bytes(raw + b"bad")
        with self.assertRaisesRegex(ValueError, "VPK inventory"):
            self.run_tool(build=True)
        volume.write_bytes(raw)
        self.assertFalse(self.view.exists())

    def test_existing_targets_and_overlap_are_never_replaced(self):
        occupied = self.output / "keep.txt"
        occupied.write_bytes(b"user file")
        with self.assertRaisesRegex(ValueError, "empty"):
            self.run_tool(build=True)
        self.assertEqual(occupied.read_bytes(), b"user file")
        occupied.unlink()
        self.view.mkdir()
        with self.assertRaisesRegex(ValueError, "new directory"):
            self.run_tool(build=True)
        self.view.rmdir()
        with self.assertRaisesRegex(ValueError, "overlap"):
            self.run_tool(build=True, output=self.overlay / "output")

    def test_late_copy_failure_removes_only_owned_view_and_keeps_base(self):
        def fail(source, destination, row):
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(b"partial")
            raise ValueError("injected copy failure")
        with patch.object(tool, "copy_new", side_effect=fail):
            with self.assertRaisesRegex(ValueError, "injected copy"):
                self.run_tool(build=True)
        self.assertFalse(self.view.exists())
        self.assertEqual(list(self.output.iterdir()), [])
        self.assert_base_unchanged()

    def test_full_runtime_validator_rejects_signed_unallowed_resource(self):
        self.reseal({"scripts/vscripts/forbidden.txt": b"not a shipping runtime extension"})
        with self.assertRaisesRegex(ValueError, "full inventory"):
            self.run_tool(build=True)
        self.assertFalse(self.view.exists())
        self.assertEqual(list(self.output.iterdir()), [])

    def test_changed_payload_race_is_rejected_without_touching_shared_base_resources(self):
        original = tool.pack.copy_payload
        def mutate(source, stream, row):
            if self.view in source.parents and row["path"] == "panorama/images/test/spaced binary.vtex_c":
                source.write_bytes(source.read_bytes() + b"late mutation")
            return original(source, stream, row)
        with patch.object(tool.pack, "copy_payload", side_effect=mutate):
            with self.assertRaisesRegex(ValueError, "grew|hash mismatch"):
                self.run_tool(build=True)
        self.assertFalse(self.view.exists())
        self.assertEqual(list(self.output.iterdir()), [])
        self.assert_base_unchanged()

    def test_final_index_publication_race_preserves_competing_writer_and_removes_owned_volumes(self):
        original = tool.os.link
        competing = self.output / "123456789.vpk"
        def race(source, destination):
            if destination == competing:
                competing.write_bytes(b"competing writer")
            return original(source, destination)
        with patch.object(tool.os, "link", side_effect=race):
            with self.assertRaises(FileExistsError):
                self.run_tool(build=True)
        self.assertEqual(list(self.output.iterdir()), [competing])
        self.assertEqual(competing.read_bytes(), b"competing writer")
        self.assert_base_unchanged()


if __name__ == "__main__":
    unittest.main()
