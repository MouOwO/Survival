"""Real signatures and byte-level assembly checks on a small runtime fixture."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

spec = importlib.util.spec_from_file_location("assembly_under_test", Path(__file__).with_name("assemble_release.py"))
assembly = importlib.util.module_from_spec(spec)
spec.loader.exec_module(assembly)


class AssemblyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve()
        self.source, self.protected = self.base / "source", self.base / "protected"
        self.source.mkdir(); self.protected.mkdir()
        self.output = self.base / "assembled"
        self.signing = Ed25519PrivateKey.generate()
        self.key = self.base / "private-signing.pem"
        self.key.write_bytes(self.signing.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                                                      serialization.NoEncryption()))
        self.public_name = "trusted_public_key.pem"
        self.write(self.source, self.public_name, self.signing.public_key().public_bytes(
            serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo))
        self.lua_policy = json.loads(assembly.LUA_POLICY.read_text(encoding="utf-8"))
        self.lua_policy["business_modules"] = ["scripts/vscripts/core/release_policy.lua"]
        self.lua_policy_name = "lua_policy.json"
        self.lua_policy_file = self.source / self.lua_policy_name
        self.lua_policy_file.write_text(json.dumps(self.lua_policy), encoding="utf-8")
        self.policy = json.loads(assembly.POLICY.read_text(encoding="utf-8"))
        self.policy["integrity"].update({"trusted_public_key": self.public_name,
                                         "trusted_key_id": assembly.protect_data.public_id(self.signing.public_key()),
                                         "minimum_release_sequence": 10})
        self.policy["lua_distribution"]["policy"] = self.lua_policy_name
        self.policy_file = self.source / "policy.json"
        self.policy_file.write_text(json.dumps(self.policy), encoding="utf-8")
        self.write(self.source, "addoninfo.txt", b'"AddonInfo" { "maps" "template_map" }')
        self.write(self.source, assembly.api.RELEASE_PROFILE, b'return { channel="production" }')
        for path in (assembly.api.CRITICAL | assembly.api.map_files(self.source)) - {"addoninfo.txt", assembly.api.RELEASE_PROFILE}:
            self.write(self.source, path, b"return {}" if path.endswith(".lua") else b"fixture native bytes")
        self.write(self.source, "scripts/vscripts/core/release_policy.lua",
                   (assembly.ROOT / "scripts/vscripts/core/release_policy.lua").read_bytes())
        self.table = "scripts/vscripts/config/generated/probe.lua"
        self.write(self.source, self.table, b'return {rows={{id="one",value=0.33333333333333331}}}')
        self.source_manifest = assembly.api.manifest(self.source)
        paths = [row["path"] for row in self.source_manifest["files"]
                 if row["path"].startswith("scripts/vscripts/") and row["path"].endswith(".lua")]
        selected = assembly.lua_protection.selected_files(paths, self.lua_policy)
        report = {
            "schema": 1, "kind": "offline_lua51_protection", "status": "PASS_REQUIRES_NATIVE_SMOKE",
            "policy_sha256": hashlib.sha256(assembly.api.canonical_bytes(self.lua_policy)).hexdigest(),
            "dependency": {**self.lua_policy["dependency"], "path": str(self.base / "unused_pinned_dependency"),
                           "verified_source_tree_sha256": self.lua_policy["dependency"]["source_tree_sha256"]},
            "source_modified": False, "network_used_for_transform": False, "workshop_upload_performed": False,
            "steps": self.lua_policy["steps"], "generated_steps": ["ConstantArray", "EncryptStrings", "NumbersToExpressions", "WrapInFunction"],
            "generated_string_obfuscation": {"enabled": True, "step": "EncryptStrings", "private_rng": True,
                                               "cryptographic_confidentiality": False},
            "syntax": {"status": "PASS", "all_lua_files": len(paths)},
            "semantic_verification": {"status": "PASS", "all_generated_values_exact": True,
                                      "gameplay_rng_untouched_while_loading": True,
                                      "new_runtime_io_os_debug_dependency": False,
                                      "business_probe_modules": self.lua_policy["business_modules"],
                                      "summary": {"files": len(selected)}},
            "selected_files": len(selected), "files": [],
        }
        for row in selected:
            path = row["path"]
            raw = (self.source / path).read_bytes()
            self.write(self.protected, path, b"return(function(...)\n" + raw + b"\nend)(...)")
            report["files"].append({**row, "before": assembly.api.checksums(self.source / path),
                                    "after": assembly.api.checksums(self.protected / path)})
        self.report_file = self.protected / "_lua_protection_report.json"
        self.save_report(report)
        # Dependency content pinning is covered by its dedicated real-source
        # tests. No Prometheus tool is executed by the assembler itself.
        patcher = patch.object(assembly.lua_protection, "dependency_identity", return_value=self.lua_policy["dependency"])
        patcher.start(); self.addCleanup(patcher.stop)

    @staticmethod
    def write(root, path, data):
        target = root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)

    def save_report(self, report):
        self.report_file.write_text(json.dumps(report), encoding="utf-8")

    def assemble(self, **kwargs):
        return assembly.assemble(self.source, self.output, self.protected, kwargs.pop("key", self.key),
                                 kwargs.pop("sequence", 10), policy_path=self.policy_file,
                                 lua_policy_path=self.lua_policy_file, **kwargs)

    def assert_failed(self):
        self.assertFalse((self.output / assembly.READY).exists())
        self.assertEqual(json.loads((self.output / assembly.FAILED).read_text())["status"], "FAILED_DO_NOT_PUBLISH")

    def test_real_assembly_copies_only_selected_protection_and_signs_final_exact_bytes(self):
        latest = "scripts/vscripts/systems/new_current_source.lua"
        self.write(self.source, latest, b"return {latest=true}")
        # A stale/unselected file in the old protected tree is never copied.
        self.write(self.protected, latest, b"return {latest=false}")
        result = self.assemble()
        self.assertEqual(result["status"], "READY_FOR_NATIVE_SMOKE_ONLY")
        self.assertFalse(result["ready_for_upload"])
        self.assertEqual((self.output / self.table).read_bytes(), (self.protected / self.table).read_bytes())
        self.assertEqual((self.output / latest).read_bytes(), b"return {latest=true}")
        self.assertEqual((self.source / self.table).read_bytes(), b'return {rows={{id="one",value=0.33333333333333331}}}')
        self.assertFalse((self.output / "private-signing.pem").exists())
        signed = assembly.protect_data.verify_signature(self.output / assembly.MANIFEST, self.output / assembly.SIGNATURE,
                                                       self.source / self.public_name, minimum_sequence=10)
        self.assertTrue(signed["signature_valid"])
        manifest = json.loads((self.output / assembly.MANIFEST).read_text())
        self.assertTrue(assembly.api.verify(self.output, manifest)["ok"])
        self.assertEqual(manifest["content_sha256"], result["content_sha256"])
        self.assertEqual(list(self.base.glob(".assembled.assembly-*")), [])

    def test_modified_source_or_protected_file_is_rejected_before_staging(self):
        for edit_root in (self.source, self.protected):
            previous = (edit_root / self.table).read_bytes()
            (edit_root / self.table).write_bytes(previous + b" -- unexpected")
            with self.subTest(root=edit_root), self.assertRaisesRegex(ValueError, "changed"):
                self.assemble()
            self.assert_failed()
            self.assertFalse((self.output / self.table).exists())
            (edit_root / self.table).write_bytes(previous)
            self.output = self.base / "second_attempt"

    def test_forged_pass_report_cannot_hide_a_changed_value(self):
        self.write(self.protected, self.table, b'return {rows={{id="one",value=99}}}')
        report = json.loads(self.report_file.read_text())
        for row in report["files"]:
            if row["path"] == self.table:
                row["after"] = assembly.api.checksums(self.protected / self.table)
        self.save_report(report)
        with self.assertRaisesRegex(ValueError, "value changed"):
            self.assemble()
        self.assert_failed()
        failure = json.loads((self.output / assembly.FAILED).read_text())
        partial = Path(failure["partial_workspace"])
        self.assertTrue((partial / assembly.FAILED).exists())
        self.assertFalse((partial / assembly.READY).exists())

    def test_selection_hash_dependency_rng_and_string_evidence_are_mandatory(self):
        original = json.loads(self.report_file.read_text())
        edits = [lambda r: r.update(policy_sha256="0" * 64),
                 lambda r: r["dependency"].update(commit="untrusted"),
                 lambda r: r["generated_string_obfuscation"].update(enabled=False),
                 lambda r: r["semantic_verification"].update(gameplay_rng_untouched_while_loading=False),
                 lambda r: r["files"].pop()]
        for index, edit in enumerate(edits):
            self.output = self.base / ("rejected_" + str(index))
            report = copy.deepcopy(original); edit(report); self.save_report(report)
            with self.subTest(index=index), self.assertRaises(ValueError):
                self.assemble()
            self.assert_failed()

    def test_wrong_signing_key_and_rollback_sequence_never_stage(self):
        other = Ed25519PrivateKey.generate()
        other_file = self.base / "other-private.pem"
        other_file.write_bytes(other.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                                                 serialization.NoEncryption()))
        with self.assertRaisesRegex(ValueError, "Signing key"):
            self.assemble(key=other_file)
        self.assert_failed()
        self.output = self.base / "rollback"
        with self.assertRaisesRegex(ValueError, "sequence"):
            self.assemble(sequence=9)
        self.assert_failed()

    def test_existing_or_source_destination_is_never_changed(self):
        self.output.mkdir()
        marker = self.output / "user-file"
        marker.write_bytes(b"preserve")
        with self.assertRaisesRegex(ValueError, "already exists"):
            self.assemble()
        self.assertEqual(marker.read_bytes(), b"preserve")
        self.assertFalse((self.output / assembly.FAILED).exists())
        self.output = self.source / "forbidden"
        with self.assertRaisesRegex(ValueError, "outside"):
            self.assemble()
        self.assertFalse(self.output.exists())

    def test_copy_failure_is_failed_and_never_falls_back_to_source(self):
        real_copy = assembly.shutil.copyfile
        def fail_protected(source, destination, *args, **kwargs):
            if Path(source) == self.protected / self.table:
                raise OSError("fixture protected copy failure")
            return real_copy(source, destination, *args, **kwargs)
        with patch.object(assembly.shutil, "copyfile", side_effect=fail_protected):
            with self.assertRaisesRegex(OSError, "protected copy failure"):
                self.assemble()
        self.assert_failed()


if __name__ == "__main__":
    unittest.main()
