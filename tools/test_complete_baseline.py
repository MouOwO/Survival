"""Complete official checkpoint boundaries; no SDK, signing or real mutation."""
from contextlib import nullcontext
import copy
import hashlib
import io
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
from complete_delivery_release_20261103 import complete_baseline as b
from complete_delivery_release_20261103 import complete_pending as cp
import release_pipeline as pipeline
import release_workflow_diagnostics as diagnostics


def entry(oid):
    return dict(mode="100644", kind="blob", oid=oid*40, bytes=10)


class Fixture:
    def __init__(self):
        self.rows = [dict(path="scripts/a.lua", bytes=20, sha256="a"*64),
                     dict(path="scripts/b.lua", bytes=10, sha256="b"*64)]
        self.origins = {"scripts/a.lua": dict(resource_sha256="0"*64, resource_bytes=10),
                        "scripts/b.lua": dict(resource_sha256="b"*64, resource_bytes=10),
                        "scripts/deleted.lua": dict(resource_sha256="d"*64, resource_bytes=10)}
        old_inventory = dict(game={"scripts/a.lua": entry("0"), "scripts/b.lua": entry("b"),
                                   "scripts/deleted.lua": entry("d")}, content={})
        self.previous = dict(parent_sequence=104, parent_manifest_sha256="1"*64,
            parent_content_sha256="2"*64, resource_origins=self.origins,
            resource_origins_sha256=b.sha(b.canonical(self.origins)), source_inventory=old_inventory,
            deferred_sources={"historical": dict(repo="game", path="scripts/a.lua")})
        sources = dict(game="a"*40, content="b"*40)
        self.trees = dict(game=dict(commit=sources["game"], entries={"scripts/a.lua": entry("a"),
            "scripts/b.lua": entry("b")}), content=dict(commit=sources["content"], entries={}))
        binding = dict(resource="scripts/a.lua", kind="protected_lua", inputs={"game:scripts/a.lua": "8"*64},
                       output=dict(bytes=20, sha256="a"*64), receipt_sha256="9"*64)
        origins = copy.deepcopy(self.origins); del origins["scripts/deleted.lua"]
        origins["scripts/a.lua"] = dict(kind="COMPLETE_IMMUTABLE_TYPED_RUNTIME_BINDING",
            resource_sha256="a"*64, resource_bytes=20, binding=binding, source_revisions=sources,
            projection_sha256="3"*64)
        covered = ["game:scripts/a.lua", "game:scripts/deleted.lua"]
        self.projection = dict(parent_manifest_sha256="1"*64, build_ready=True, projection_sha256="3"*64,
            projected_rows=self.rows, changed_runtime_paths=["scripts/a.lua"],
            removed_runtime_paths=["scripts/deleted.lua"], coverage_ledger=dict(coverage_complete=True,
                unknown_sources=[], deferred_sources=[], pending_sources=covered, covered_sources=covered,
                historical_sources=["game:scripts/a.lua"], non_runtime_reviews=[], resource_bindings=[binding]))
        self.manifest = dict(files=self.rows, file_count=2, content_sha256="4"*64)
        self.report = dict(release_sequence=105, files=2, source_revisions=sources,
            authenticated_parent_manifest_sha256="1"*64, authenticated_parent_content_sha256="2"*64,
            resource_origins=origins, resource_origins_sha256=b.sha(b.canonical(origins)),
            parent_resource_origins_sha256=self.previous["resource_origins_sha256"],
            changed_runtime_paths=["scripts/a.lua"], removed_runtime_paths=["scripts/deleted.lua"],
            signed_manifest_sha256="5"*64)
        self.inventory = dict(rows=[dict(source=dict(repo="game", path=name))
            for name in ("scripts/a.lua", "scripts/deleted.lua")], counts=dict(dirty_runtime=0))
        self.delivery = dict(ordinary_production_acceptance=True, signature_valid=True,
                            official_full_installation_reverified=True, steam_manifest="123456789",
                            package_operator_revision="c"*40)

    def run(self):
        return b.advance(self.previous, self.report, self.manifest, self.projection,
                         self.inventory, self.trees, self.delivery)


class CheckpointTests(unittest.TestCase):
    def setUp(self):
        self.f = Fixture()

    def test_complete_typed_transform_and_deletion_advance_without_plaintext_export_claim(self):
        old = copy.deepcopy(self.f.previous)
        self.f.projection["build_ready"] = False  # plan is never signing authority
        result = self.f.run()
        self.assertEqual(result["source_inventory"]["game"], self.f.trees["game"]["entries"])
        self.assertEqual(result["deferred_sources"], {})
        self.assertNotIn("scripts/deleted.lua", result["resource_origins"])
        self.assertFalse(result["source_anchor_is_full_published_tree"])
        self.assertFalse(result["full_head_publication_claimed"])
        self.assertEqual(self.f.previous, old)

    def test_uncovered_source_even_if_bound_resource_set_is_complete_is_rejected(self):
        self.f.trees["game"]["entries"]["scripts/new.lua"] = entry("e")
        with self.assertRaisesRegex(ValueError, "uncovered"):
            self.f.run()

    def test_historical_unchanged_source_requires_review(self):
        self.f.previous["deferred_sources"]["another"] = dict(repo="game", path="scripts/b.lua")
        with self.assertRaisesRegex(ValueError, "uncovered"):
            self.f.run()

    def test_unknown_and_deferred_source_each_block_full_checkpoint(self):
        for field in ("unknown_sources", "deferred_sources"):
            with self.subTest(field=field):
                f = Fixture(); f.projection["coverage_ledger"][field] = ["game:scripts/x.lua"]
                with self.assertRaisesRegex(ValueError, "unreviewed"):
                    f.run()

    def test_dirty_runtime_cannot_be_cleared_by_a_checkpoint(self):
        self.f.inventory["counts"]["dirty_runtime"] = 1
        with self.assertRaisesRegex(ValueError, "uncovered"):
            self.f.run()

    def test_wrong_source_revision_and_wrong_parent_are_rejected(self):
        self.f.trees["content"]["commit"] = "c"*40
        with self.assertRaisesRegex(ValueError, "git_tree"):
            self.f.run()
        self.f = Fixture(); self.f.report["authenticated_parent_manifest_sha256"] = "f"*64
        with self.assertRaisesRegex(ValueError, "parent"):
            self.f.run()

    def test_changed_origin_must_have_exact_typed_binding(self):
        self.f.report["resource_origins"]["scripts/a.lua"]["binding"]["kind"] = "identity"
        # Deep copy: ledger and report must be independently derived objects.
        self.f.projection["coverage_ledger"]["resource_bindings"] = [dict(resource="scripts/a.lua", kind="protected_lua")]
        self.f.report["resource_origins_sha256"] = b.sha(b.canonical(self.f.report["resource_origins"]))
        with self.assertRaisesRegex(ValueError, "typed_binding"):
            self.f.run()

    def test_unchanged_origin_cannot_be_relabelled(self):
        self.f.report["resource_origins"]["scripts/b.lua"]["kind"] = "new forged provenance"
        self.f.report["resource_origins_sha256"] = b.sha(b.canonical(self.f.report["resource_origins"]))
        with self.assertRaisesRegex(ValueError, "unaffected"):
            self.f.run()

    def test_wrong_removed_resource_set_is_rejected(self):
        self.f.report["removed_runtime_paths"] = []
        with self.assertRaisesRegex(ValueError, "changed_removed"):
            self.f.run()

    def test_missing_actual_native_or_official_reverification_is_rejected(self):
        for field in ("ordinary_production_acceptance", "official_full_installation_reverified", "signature_valid"):
            with self.subTest(field=field):
                f=Fixture(); f.delivery[field] = False
                with self.assertRaisesRegex(ValueError, "actual_ordinary"):
                    f.run()

    def test_official_delivery_checks_dynamic_volume_count_and_real_callback_schema(self):
        from test_release_delivery_state import fixture
        state=fixture(); report=state["local_package"]; receipt=state["download_receipt"]
        report["package_files"]=report["package_files"][:3]
        files=report["package_files"]; total=sum(row["bytes"] for row in files)
        state["journal"]["package_files"]=copy.deepcopy(files)
        receipt["verification"]["package_files"]=copy.deepcopy(files)
        receipt["verification"]["verification"]["archive_count"]=2
        receipt["pre_query"]["total_files_bytes"]=receipt["post_query"]["total_files_bytes"]=total
        report["protected_modules_verified"]=receipt["protected_modules_verified"]=186
        receipt["download"]["callback"]["callback_id"]=3406
        receipt["verification"]["callback"]=copy.deepcopy(receipt["download"]["callback"])
        receipt["verification"].update(size_on_disk=total,expected_size_on_disk=total)
        receipt["acf_installed_entry"]=dict(manifest=receipt["steam_manifest"],size=str(total),timeupdated="123")
        result=b.verified_delivery(report,dict(files=state["local_resources"]),"e"*64,
                                   state["journal"],"d"*64,receipt)
        self.assertTrue(result["official_download_evidence_matches_target"])
        receipt["download"]["callback"]["callback_id"]=0
        with self.assertRaisesRegex(ValueError,"native_callback"):
            b.verified_delivery(report,dict(files=state["local_resources"]),"e"*64,
                                state["journal"],"d"*64,receipt)

    def test_new_diagnostics_cursor_routes_only_to_fixed_complete_loader(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); cursor=root/"output/release_baselines/complete_active.json"
            cursor.parent.mkdir(parents=True); cursor.write_text("{}")
            expected=dict(rows=[], counts=dict(pending=0, dirty_runtime=0))
            with patch.object(diagnostics, "ROOT", root), patch.object(cp, "inventory", return_value=expected) as load:
                self.assertIs(diagnostics.pending_inventory(), expected)
            load.assert_called_once_with()

    def test_complete_pending_keeps_new_runtime_changes_and_dirty_files(self):
        checkpoint=self.f.run()
        current=dict(game={**checkpoint["source_inventory"]["game"], "scripts/new.lua": entry("c")}, content={})
        import release_pending_inventory as pending
        policy=dict(business_modules=[], generated_prefix="generated/", generated_exclusions=[])
        with patch.object(b, "load_active", return_value=(checkpoint,self.f.manifest,{})), \
             patch("complete_delivery_release_20261103.pipeline_recipe.verify_operator_paths"), \
             patch.object(pending, "_git", return_value=("c"*40).encode()), \
             patch.object(pending, "git_tree", side_effect=lambda root,counts,revision: current["game" if root==cp.ROOT else "content"]), \
             patch.object(pending, "git_dirty", side_effect=lambda root,role,counts: [dict(repo=role,path="scripts/local.lua")] if role=="game" else []), \
             patch.object(pending, "read_git_facts", return_value={"scripts/new.lua": dict(hash_state="VERIFIED",sha256="c"*64,bytes=10)}), \
             patch.object(pending, "_read_json", return_value=policy):
            result=cp.inventory()
        self.assertEqual(result["counts"]["pending"],1)
        self.assertEqual(result["counts"]["dirty_runtime"],1)
        self.assertEqual(result["sdk_calls"],0)

    def test_failed_completion_validation_performs_no_checkpoint_writes(self):
        with tempfile.TemporaryDirectory() as folder:
            active=Path(folder)/"active.json"; base=Path(folder)/"history"
            auth=SimpleNamespace(policy=dict(publication_lock=str(Path(folder)/"lock")))
            with patch.object(b,"checked_authority",return_value=auth), patch.object(b,"ACTIVE",active), \
                 patch.object(b,"BASE",base), patch.object(b,"collect_verified",side_effect=ValueError("actual native missing")):
                with self.assertRaisesRegex(ValueError,"native missing"):
                    b.record_verified_delivery(auth,None,{},"receipt")
            self.assertFalse(active.exists()); self.assertFalse(base.exists())

    def test_unchanged_snapshot_cas_catches_updated_journal(self):
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/"journal";path.write_bytes(b"new")
            with self.assertRaisesRegex(ValueError,"changed_before_commit"):
                b.unchanged({path:b"old"})

    def test_complete_hook_runs_before_delivery_status_without_second_publish(self):
        root=Path("D:/synthetic")
        auth=SimpleNamespace(policy=dict(recipe_path=str(root/"tools/complete_delivery_release_20261103/pipeline_recipe.py")))
        builder=SimpleNamespace()
        received=dict(status="OFFICIAL_REFRESH_NATIVE_DOWNLOAD_FULLY_VERIFIED",evidence="D:/receipt.json",release_sequence=105)
        def download_main(args):
            print(json.dumps(received)); return 0
        completion=SimpleNamespace(record_verified_delivery=Mock())
        download=SimpleNamespace(main=download_main)
        order=[]
        completion.record_verified_delivery.side_effect=lambda *args:order.append("checkpoint")
        def state(*args,**kwargs):
            order.append("status")
            return dict(upload_evidence_matches_target=True,official_download_evidence_matches_target=True,
                task_package_status="WORKSHOP_SYNCED",project_status="WORKSHOP_SYNCED",workshop_synchronized=True,
                pending_counts=dict(pending=0))
        with patch.object(pipeline,"publish",return_value=dict(release_sequence=105)) as publish, \
             patch.object(pipeline,"pinned_module",side_effect=lambda auth,prefix:download if prefix=="download" else completion), \
             patch.object(diagnostics,"delivery_status",side_effect=state):
            result=pipeline.complete(auth,builder,dict(report_sha256="a"*64))
        self.assertEqual(order,["checkpoint","status"])
        self.assertTrue(result["project_workshop_synchronized"])
        publish.assert_called_once()

    def test_failed_checkpoint_keeps_uploaded_pending_and_does_not_claim_synced(self):
        auth=SimpleNamespace(policy=dict(recipe_path="D:/tools/complete_delivery_release_20261103/pipeline_recipe.py"))
        def main(args):
            print(json.dumps(dict(status="OFFICIAL_REFRESH_NATIVE_DOWNLOAD_FULLY_VERIFIED",evidence="D:/receipt.json")));return 0
        with patch.object(pipeline,"publish",return_value=dict(release_sequence=105)) as publish, \
             patch.object(pipeline,"pinned_module",side_effect=lambda auth,prefix:SimpleNamespace(main=main) if prefix=="download" else
                 SimpleNamespace(record_verified_delivery=Mock(side_effect=ValueError("CAS changed")))):
            result=pipeline.complete(auth,None,{})
        self.assertFalse(result["workshop_synchronized"])
        self.assertFalse(result["automatic_resubmit"])
        publish.assert_called_once()


if __name__ == "__main__":
    unittest.main()
