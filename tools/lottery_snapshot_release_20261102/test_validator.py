"""Synthetic authority contracts plus actual published-parent review keys.

No SDK, package scan, signing, process query or common-policy activation.
"""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec)
    sys.modules[name] = value
    spec.loader.exec_module(value)
    return value


v = load("snapshot0203_authority_contract", HERE / "validator.py")
g = load("snapshot0203_guard_contract", ROOT / "tools/release_lineage_20261101/guard.py")
ARCHIVE = "scripts/vscripts/systems/archive_service.lua"


class SnapshotAdapterTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="snapshot0203-adapter-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        native = self.root / "native_admission.py"
        native.write_text("def validate_native_release(req, report, manifest, signed):\n"
                          " return {'ordinary_production_acceptance': req.get('synthetic_native_pass') is True, 'content_sha256': manifest['content_sha256']}\n", encoding="utf-8")
        self.sources = {"game": "1" * 40, "content": "2" * 40}
        self.plan = dict(status="UNSIGNED_REVIEW", dry_run=True, signing_key_read=False, signature_valid=False,
            release_sequence=2026110203, source_revisions=self.sources, operator_revision="3" * 40,
            target_pins={path: {"sha256": "a" * 64} for path in sorted(v.PAYLOADS)})
        self.report = dict(self.plan, status="BUILT_SIGNED_PENDING_NATIVE_LOTTERY_SNAPSHOT_ACCEPTANCE",
            dry_run=False, signing_key_read=True, signature_valid=True, files=6917, protected_modules_preserved=184,
            changed_runtime_paths=sorted(v.PAYLOADS), added_runtime_paths=[], removed_runtime_paths=[],
            trusted_review_pins={str(n): {} for n in range(20)}, source_artifact_pins={"js": {}, "css": {}},
            content_sha256="b" * 64, authenticated_parent_manifest_sha256="c" * 64,
            parent_resource_origins_sha256="d" * 64, resource_origins_sha256="e" * 64)
        self.journal = self.root / "journal.json"
        self.journal.write_text('{"release_sequence":2026110104}', encoding="utf-8")
        self.plan_path = self.root / "plan.json"
        self.plan_path.write_text(json.dumps(self.plan), encoding="utf-8")
        def parent(state, _):
            if state["release_sequence"] != 2026110104:
                raise ValueError("Current parent differs")
        self.builder = SimpleNamespace(SEQUENCE=2026110203, PAYLOADS=tuple(v.PAYLOADS), ITEM="3824360109",
            BASE_SEQUENCE=2026110104, BASE_CONTENT="0" * 64, BASE=self.root, BASE_REPORT=self.root / "parent.json",
            REPORT=self.root, VIEW=self.root / "view", OUTPUT=self.root / "output", JOURNAL=self.journal,
            pack=SimpleNamespace(handoff=SimpleNamespace(MANIFEST="resource_manifest.json"),
                runtime=SimpleNamespace(digest=lambda _: "f" * 64,
                    within=lambda child, base: child == base or base in child.parents)),
            require_parent_journal=parent, load=lambda _: {}, reviewed_plan=lambda *_: copy.deepcopy(self.plan),
            plan=lambda *_: (copy.deepcopy(self.plan),), baseline=lambda **_: ({}, {}),
            ledger=SimpleNamespace(load_baseline=lambda *_: dict(source_anchors=self.sources,
                parent_manifest_sha256="c" * 64, resource_origins_sha256="d" * 64)))
        checks = SimpleNamespace(validated_package=lambda *_, **kw: (self.report, {"content_sha256": "b" * 64}, {}))
        self.request = dict(release_sequence=2026110203, generation=2, source_revisions=self.sources,
            signed_manifest_sha256="f" * 64, report_sha256="4" * 64, plan_sha256="5" * 64,
            plan_path=str(self.plan_path), parent_journal_sha256=hashlib.sha256(self.journal.read_bytes()).hexdigest(),
            synthetic_native_pass=True)
        for name, value in (("b", self.builder), ("c", checks), ("HERE", self.root),
                ("NATIVE_ADMISSION_MODULE", native), ("NATIVE_ADMISSION_SHA256", hashlib.sha256(native.read_bytes()).hexdigest())):
            handle = patch.object(v.p, name, value)
            handle.start()
            self.addCleanup(handle.stop)

    def test_five_resource_adapter_accepts_only_checked_synthetic_policy(self):
        self.assertIn(ARCHIVE, v.PAYLOADS)
        self.assertEqual(len(v.PAYLOADS), 5)
        result = v.validate_release(self.request)
        self.assertEqual(result["release_sequence"], 2026110203)
        self.assertNotIn("mean_fps", result)
        self.assertNotIn("boss", result)

    def test_unreviewed_or_failed_native_rejected_even_with_ready_flag(self):
        with patch.object(v.p, "NATIVE_ADMISSION_SHA256", None):
            with self.assertRaisesRegex(ValueError, "PENDING_REVIEWED_NATIVE"):
                v.validate_release(self.request)
        self.request.update(synthetic_native_pass=False, READY=True)
        with self.assertRaisesRegex(ValueError, "Same signed normal-client"):
            v.validate_release(self.request)

    def test_old0202_or_four_resource_recipe_cannot_be_relabelled(self):
        with self.assertRaisesRegex(ValueError, "exact five-resource"):
            v.validate_release({**self.request, "release_sequence": 2026110202})
        self.builder.PAYLOADS = tuple(path for path in v.PAYLOADS if path != ARCHIVE)
        with self.assertRaisesRegex(ValueError, "Exact five-resource snapshot recipe"):
            v.validate_release(self.request)

    def test_wrong_review_count_archive_omission_and_plan_drift_rejected(self):
        for count in (19, 21):
            old = self.report["trusted_review_pins"]
            self.report["trusted_review_pins"] = {str(n): {} for n in range(count)}
            with self.assertRaisesRegex(ValueError, "twenty-review"):
                v.validate_release(self.request)
            self.report["trusted_review_pins"] = old
        self.report["target_pins"] = {path: value for path, value in self.report["target_pins"].items() if path != ARCHIVE}
        with self.assertRaisesRegex(ValueError, "Signed report differs"):
            v.validate_release(self.request)

    def test_parent_cas_and_source_pair_still_bind_the_candidate(self):
        with self.assertRaisesRegex(ValueError, "Publication journal changed"):
            v.validate_release({**self.request, "parent_journal_sha256": "0" * 64})
        with self.assertRaisesRegex(ValueError, "source/package binding"):
            v.validate_release({**self.request, "source_revisions": {"game": "9" * 40, "content": "2" * 40}})
        self.journal.write_text('{"release_sequence":2026110203}', encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "Current parent differs"):
            v.validate_release(self.request)


class ActualParentAndRegistrationTests(unittest.TestCase):
    def test_actual_parent_key_projection_is_twenty_not_twenty_one(self):
        raw = (ROOT / "output/admission_five_20261101/package.json").read_bytes()
        self.assertEqual(hashlib.sha256(raw).hexdigest(), "70306be7a42962172fddce88bc8c4ac12dc5e73db1119d97839b871115aa01b6")
        previous = set(json.loads(raw)["trusted_review_pins"])
        updates = {ARCHIVE, "scripts/vscripts/ui/ui_request_router.lua", "scripts/vscripts/ui/production_ui_service.lua"}
        self.assertEqual(len(previous), 18)
        self.assertEqual(previous & updates, {"scripts/vscripts/ui/ui_request_router.lua"})
        self.assertEqual(len(previous | updates), 20)

    def test_new_authority_can_register_without_touching_current_policy_or_sdk(self):
        with tempfile.TemporaryDirectory(prefix="snapshot0203-authority-") as directory:
            root = Path(directory).resolve()
            journal = root / "canonical.json"
            path = HERE / "validator.py"
            policy = dict(schema=1, app_id=570, workshop_id="3824360109", owner=v.OWNER,
                canonical_journal=str(journal), lineage_state=str(root / "lineage.json"),
                publication_lock=str(journal) + ".lock", validator_path=str(path),
                validator_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                repositories={"game": str(root / "game"), "content": str(root / "content")})
            raw = json.dumps(policy).encode("utf-8")
            file = root / "authority.json"
            file.write_bytes(raw)
            loaded = g._validator(g.load_authority(file, hashlib.sha256(raw).hexdigest()))
            self.assertEqual(loaded.RELEASE_SEQUENCE, 2026110203)
            self.assertIsNone(loaded.p.b)
            self.assertIsNone(loaded.p.c)
            with patch.object(loaded.p, "NATIVE_ADMISSION_SHA256", None):
                with self.assertRaisesRegex(ValueError, "PENDING_REVIEWED_NATIVE"):
                    loaded.validate_release({"release_sequence": 2026110203, "generation": 1})

    def test_frozen0202_adapter_and_exact_source_transforms_are_bound(self):
        self.assertEqual(hashlib.sha256(v.PARENT.read_bytes()).hexdigest(), v.PARENT_SHA256)
        self.assertEqual(v.PARENT_SHA256, "70fb19bc302967dd527e28e80eca58a00d63254a11d6766a2e23d909835b716b")
        self.assertEqual(v.p.RELEASE_SEQUENCE, 2026110203)
        self.assertEqual(len(v.TRANSFORMS), 12)


if __name__ == "__main__":
    unittest.main()
