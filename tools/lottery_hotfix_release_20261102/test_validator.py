"""Authority and recipe contracts only; no real native/SDK/VPK acceptance."""
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
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


v = load("hotfix_validator_contract", HERE / "validator.py")
guard = load("hotfix_authority_guard_contract", ROOT / "tools/release_lineage_20261101/guard.py")


class ValidatorTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="lottery-validator-contract-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.native = self.root / "native_admission.py"
        # This intentionally synthetic policy exercises the adapter only. The
        # actual policy has independent evidence tests and is never replaced.
        self.native.write_text("def validate_native_release(request, report, manifest, signed):\n"
                               " return {'ordinary_production_acceptance': request.get('fixture_native_pass') is True, 'content_sha256': manifest['content_sha256']}\n", encoding="utf-8")
        self.sources = {"game": "1" * 40, "content": "2" * 40}
        self.plan = dict(status="UNSIGNED_REVIEW", dry_run=True, signing_key_read=False, signature_valid=False,
                         release_sequence=2026110202, source_revisions=self.sources, operator_revision="3" * 40,
                         target_pins={name: {"sha256": "a" * 64} for name in sorted(v.PAYLOADS)})
        self.report = dict(self.plan, status="BUILT_SIGNED_PENDING_NATIVE_LOTTERY_ACCEPTANCE", dry_run=False,
                           signing_key_read=True, signature_valid=True, files=6917, protected_modules_preserved=184,
                           changed_runtime_paths=sorted(v.PAYLOADS), added_runtime_paths=[], removed_runtime_paths=[],
                           trusted_review_pins={str(n): {} for n in range(19)}, source_artifact_pins={"js": {}, "css": {}},
                           content_sha256="b" * 64, authenticated_parent_manifest_sha256="c" * 64,
                           parent_resource_origins_sha256="d" * 64, resource_origins_sha256="e" * 64)
        self.manifest = {"file_count": 6917, "content_sha256": self.report["content_sha256"]}
        self.journal = self.root / "journal.json"
        self.journal.write_text('{"release_sequence":2026110104}', encoding="utf-8")
        self.plan_path = self.root / "plan.json"
        self.plan_path.write_text(json.dumps(self.plan), encoding="utf-8")
        runtime = SimpleNamespace(digest=lambda _: "f" * 64,
                                  within=lambda child, parent: child == parent or parent in child.parents)
        def require_parent(state, _):
            if state["release_sequence"] != 2026110104:
                raise ValueError("Current publication parent changed")
        self.builder = SimpleNamespace(SEQUENCE=2026110202, PAYLOADS=tuple(v.PAYLOADS), ITEM="3824360109",
            BASE_SEQUENCE=2026110104, BASE_CONTENT="0" * 64, BASE=self.root, BASE_REPORT=self.root / "parent.json",
            REPORT=self.root, OUTPUT=self.root / "package", VIEW=self.root / "view", JOURNAL=self.journal,
            pack=SimpleNamespace(runtime=runtime, handoff=SimpleNamespace(MANIFEST="resource_manifest.json")),
            plan=lambda *_: (copy.deepcopy(self.plan), {}, {}),
            reviewed_plan=lambda *_: copy.deepcopy(self.plan), load=lambda _: {},
            require_parent_journal=require_parent, baseline=lambda **_: ({}, {}),
            ledger=SimpleNamespace(load_baseline=lambda *_: dict(parent_manifest_sha256="c" * 64,
                source_anchors=self.sources, resource_origins_sha256="d" * 64)))
        self.checks = SimpleNamespace(validated_package=lambda *args, **kwargs: (self.report, self.manifest, {}))
        self.request = dict(release_sequence=2026110202, generation=2, source_revisions=self.sources,
            signed_manifest_sha256="f" * 64, content_sha256="b" * 64, report_sha256="4" * 64,
            plan_sha256="5" * 64, plan_path=str(self.plan_path),
            parent_journal_sha256=hashlib.sha256(self.journal.read_bytes()).hexdigest(), fixture_native_pass=True)
        for key, value in (("b", self.builder), ("c", self.checks), ("HERE", self.root),
                           ("NATIVE_ADMISSION_MODULE", self.native),
                           ("NATIVE_ADMISSION_SHA256", hashlib.sha256(self.native.read_bytes()).hexdigest())):
            patcher = patch.object(v, key, value)
            patcher.start()
            self.addCleanup(patcher.stop)

    def test_scoped_adapter_passes_without_legacy_boss_or_fps_fields(self):
        result = v.validate_release(self.request)
        self.assertEqual(result["release_sequence"], 2026110202)
        self.assertEqual(result["generation"], 2)
        self.assertEqual(result["content_sha256"], self.manifest["content_sha256"])
        self.assertNotIn("mean_fps", result)
        self.assertFalse(hasattr(self.builder, "shared_boss_source_review"))

    def test_native_policy_unfrozen_wrong_bytes_or_failed_acceptance_rejected(self):
        with patch.object(v, "NATIVE_ADMISSION_SHA256", None):
            with self.assertRaisesRegex(ValueError, "PENDING_REVIEWED_NATIVE"):
                v.validate_release(self.request)
        with patch.object(v, "NATIVE_ADMISSION_SHA256", "0" * 64):
            with self.assertRaisesRegex(ValueError, "admission policy changed"):
                v.validate_release(self.request)
        self.request["fixture_native_pass"] = False
        self.request["READY"] = True
        with self.assertRaisesRegex(ValueError, "Same signed normal-client"):
            v.validate_release(self.request)

    def test_other_sequence_wrong_recipe_and_bool_generation_rejected(self):
        for sequence in (2026110201, 2026110107):
            with self.subTest(sequence=sequence), self.assertRaisesRegex(ValueError, "Only this exact"):
                v.validate_release({**self.request, "release_sequence": sequence})
        with self.assertRaisesRegex(ValueError, "lineage generation"):
            v.validate_release({**self.request, "generation": True})
        self.builder.PAYLOADS += ("scripts/vscripts/systems/extra.lua",)
        with self.assertRaisesRegex(ValueError, "Exact four-resource hotfix recipe"):
            v.validate_release(self.request)

    def test_signed_scope_and_immutable_plan_drift_rejected(self):
        for field, value in (("files", 6919), ("protected_modules_preserved", 183),
                             ("trusted_review_pins", {}),
                             ("trusted_review_pins", {str(n): {} for n in range(20)}),
                             ("source_artifact_pins", {"one": {}}),
                             ("changed_runtime_paths", list(v.PAYLOADS)[:3])):
            old = self.report[field]
            self.report[field] = value
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, "nineteen-review signed hotfix"):
                v.validate_release(self.request)
            self.report[field] = old
        self.report["target_pins"] = {}
        with self.assertRaisesRegex(ValueError, "Signed report differs"):
            v.validate_release(self.request)

    def test_source_binding_and_current_parent_cas_rejected(self):
        with self.assertRaisesRegex(ValueError, "Request source/package binding"):
            v.validate_release({**self.request, "source_revisions": {"game": "9" * 40, "content": "2" * 40}})
        with self.assertRaisesRegex(ValueError, "Publication journal changed"):
            v.validate_release({**self.request, "parent_journal_sha256": "0" * 64})
        self.journal.write_text('{"release_sequence":2026110202}', encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "Current publication parent changed"):
            v.validate_release(self.request)

    def test_bootstrap_binds_parent_origins_without_claiming_full_git_export(self):
        request = dict(canonical_journal_sha256=self.request["parent_journal_sha256"],
                       parent_manifest_sha256="c" * 64, source_revisions=self.sources)
        result = v.validate_bootstrap(request)
        self.assertFalse(result["source_anchor_is_full_published_tree"])
        self.assertEqual(result["resource_origins_sha256"], "d" * 64)
        request["source_revisions"] = {"game": "9" * 40, "content": "2" * 40}
        with self.assertRaisesRegex(ValueError, "Bootstrap must bind"):
            v.validate_bootstrap(request)


class ActualParentReviewProjectionTests(unittest.TestCase):
    def test_real_parent_replaces_router_and_only_adds_production_review(self):
        builder = load("actual_hotfix_parent_review_projection", HERE / "build_release.py")
        raw = builder.BASE_REPORT.read_bytes()
        self.assertEqual(hashlib.sha256(raw).hexdigest(),
                         "70306be7a42962172fddce88bc8c4ac12dc5e73db1119d97839b871115aa01b6")
        parent = json.loads(raw)
        previous = parent["trusted_review_pins"]
        router = "scripts/vscripts/ui/ui_request_router.lua"
        production = "scripts/vscripts/ui/production_ui_service.lua"
        self.assertEqual(len(previous), 18)
        self.assertEqual(set(previous).intersection(builder.ADDITIONAL_SOURCE_REVIEWS), {router})
        self.assertNotIn(production, previous)
        values = {name: (builder.ROOT / name).read_bytes().replace(b"\r\n", b"\n")
                  for name in builder.ADDITIONAL_SOURCE_REVIEWS}
        projected = builder.trusted_review(parent, values)
        self.assertEqual(len(projected), 19)
        self.assertEqual(set(projected) - set(previous), {production})
        self.assertEqual(projected[router], builder.checks(values[router]))
        self.assertNotEqual(projected[router], previous[router])
        for name in set(previous) - {router}:
            self.assertEqual(projected[name], previous[name])


class AuthorityRegistrationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="hotfix-authority-contract-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.policy_path = self.root / "authority.json"
        self.validator = HERE / "validator.py"
        journal = self.root / "canonical.json"
        self.policy = dict(schema=1, canonical_journal=str(journal), lineage_state=str(self.root / "lineage.json"),
            publication_lock=str(journal) + ".lock", validator_path=str(self.validator),
            validator_sha256=hashlib.sha256(self.validator.read_bytes()).hexdigest(), app_id=570,
            workshop_id="3824360109", owner=v.OWNER,
            repositories={"game": str(self.root / "game"), "content": str(self.root / "content")})

    def authority(self):
        raw = json.dumps(self.policy).encode("utf-8")
        self.policy_path.write_bytes(raw)
        return guard.load_authority(self.policy_path, hashlib.sha256(raw).hexdigest())

    def test_actual_guard_registers_new_lazy_validator_without_recipe_sdk_or_vpk(self):
        authority = self.authority()
        loaded = guard._validator(authority)
        self.assertEqual(loaded.RELEASE_SEQUENCE, 2026110202)
        self.assertIsNone(loaded.b)
        self.assertIsNone(loaded.c)
        with patch.object(loaded, "NATIVE_ADMISSION_SHA256", None):
            with self.assertRaisesRegex(ValueError, "PENDING_REVIEWED_NATIVE"):
                loaded.validate_release({"release_sequence": 2026110202, "generation": 1, "READY": True})

    def test_policy_or_registered_validator_hash_tamper_rejected(self):
        authority = self.authority()
        self.policy_path.write_text("{}", encoding="utf-8")
        with self.assertRaisesRegex(guard.Refused, "release_authority_changed"):
            guard._validator(authority)
        self.policy["validator_sha256"] = "0" * 64
        authority = self.authority()
        with self.assertRaisesRegex(guard.Refused, "trusted_release_validator_changed"):
            guard._validator(authority)


if __name__ == "__main__":
    unittest.main()
