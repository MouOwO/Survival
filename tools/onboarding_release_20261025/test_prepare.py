"""The candidate patch must preserve the active release byte for byte."""
from __future__ import annotations

import ast
from copy import deepcopy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("onboarding_prepare", HERE / "prepare.py")
prepare = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prepare)

SERVICE = b'''# Existing release-specific patch must survive.
class ArchiveService:
    def command(self,payload):
        requested_hash = payload.get("config_hash")
        raw_command = payload.get("command")
        kind = raw_command.get("kind") if isinstance(raw_command, dict) else None
        if not accepts(self.bundle, requested_hash, kind): return {"ok":False}
        return payload["old_receipt"]
'''
POSTGRES = b'''def _params(*items): return items
RPC_SIGNATURES = {
    "existing": _params(("account", "text", "hash")),
}
RUNTIME_ROLE = "goufayu_app"
ALLOWED_FUNCTIONS = tuple(_signature(name, parameters) for name, parameters in RPC_SIGNATURES.items())
'''


class PrepareTests(unittest.TestCase):
    def test_service_patch_preserves_release_bytes_and_old_route_behavior(self):
        result = prepare.patch_service(SERVICE)
        self.assertEqual(result.replace(prepare.SERVICE_ADDITION, b"", 1), SERVICE)
        self.assertIn(b'return payload["old_receipt"]', result)
        self.assertEqual(sum(isinstance(node, ast.ImportFrom) and node.module == "onboarding"
                             for node in ast.walk(ast.parse(result))), 1)

    def test_changed_ambiguous_or_already_patched_anchor_is_refused(self):
        for source in (SERVICE.replace(b"if not accepts", b"if accepts"),
                       SERVICE + prepare.SERVICE_ANCHOR + prepare.SERVICE_NEXT,
                       prepare.patch_service(SERVICE)):
            with self.subTest(source=source[:24]), self.assertRaises(ValueError):
                prepare.patch_service(source)

    def test_build_keeps_bundle_and_ledger_and_safe_has_only_transport_patch(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            baseline_root = root / "baseline"
            hashes = {}
            for name, raw in ((prepare.SERVICE, SERVICE), (prepare.POSTGRES, POSTGRES)):
                target = baseline_root / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(raw)
                hashes[name] = prepare.sha(raw)
            baseline = {
                "release": "reviewed-parent", "manifest_sha256": "a" * 64,
                "manifest": {"archive_bundle": "b" * 64, "files": hashes},
                "payment_release": "payment-parent", "payment_manifest_sha256": "c" * 64,
                "services": {name: {"ActiveState": "active", "MainPID": "123"}
                             for name in ("goufayu-api.service", "goufayu-payment.service")},
                "bundle": {"hash": "b" * 64, "protocol": 1},
                "ledger": {"old/migration": "d" * 64}, "functions": {"old()": "e" * 64},
                "all_backend_hashes": hashes,
                "tables": ["public.survival_players", "public._goufayu_migrations"],
                "columns": [], "definitions": {},
            }
            before = deepcopy(baseline)
            source = root / "baseline.json"
            source.write_text(json.dumps(baseline), encoding="utf-8")
            output = root / "candidate"
            with patch.object(prepare, "_source_at_commit", side_effect=lambda _, name:
                              b'"""onboarding"""\n' if name.endswith(".py") else b"SELECT 1;\n"):
                plan = prepare.build(root=prepare.ROOT, baseline_file=source,
                                     baseline_root=baseline_root, destination=output)
            self.assertEqual(plan["baseline"], before)
            self.assertEqual(plan["ledger"], before["ledger"])
            self.assertEqual(plan["bundle"], before["bundle"]["hash"])
            self.assertEqual(len(plan["overlay"]), 5)
            self.assertEqual(set(plan["safe_overlay"]), {prepare.POSTGRES})
            self.assertEqual([item["transaction_wrapper"] for item in plan["migrations"]], [True, False])
            self.assertFalse((output / "operator.py").exists())
            for name, digest in plan["overlay"].items():
                self.assertEqual(prepare.sha((output / "overlay" / name).read_bytes()), digest)
            self.assertEqual((output / "safe_overlay" / prepare.POSTGRES).read_bytes(),
                             (output / "overlay" / prepare.POSTGRES).read_bytes())
            with self.assertRaisesRegex(ValueError, "candidate_directory_already_exists"):
                prepare.build(baseline_file=source, baseline_root=baseline_root, destination=output)

    def test_tampered_baseline_is_rejected_before_creating_candidate(self):
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / "candidate"
            baseline = {"release": "parent"}
            source = Path(directory) / "baseline.json"
            source.write_text(json.dumps(baseline), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "baseline_fields_missing"):
                prepare.build(baseline_file=source, baseline_root=Path(directory), destination=destination)
            self.assertFalse(destination.exists())


if __name__ == "__main__":
    unittest.main()
