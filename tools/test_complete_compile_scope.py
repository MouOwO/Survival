"""Dynamic compiler coverage, provenance, and actual immutable Git drift gates."""
from collections import Counter
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
from complete_delivery_release_20261103 import compile_scope as m

PINS = {"game": "a" * 40, "content": "b" * 40}


def fixture(resources):
    trees = {"game": {}, "content": {}}
    rows = []
    for resource in resources:
        authors = []
        for repo, name in sorted(m._authors(resource)):
            oid = hashlib.sha1((repo + ":" + name).encode()).hexdigest()
            trees[repo][name] = dict(oid=oid, mode="100644", kind="blob", bytes=len(name))
            authors.append(dict(repo=repo, path=name, oid=oid, bytes=len(name),
                source_commit=PINS[repo], exists_in_observed_commit=True, working_copy_dirty=False))
        source = next(a for a in authors if a["repo"] == "content")
        rows.append(dict(resource=resource,
            source=dict(repo="content", path=source["path"], head_oid=source["oid"]),
            inventory_status="PENDING_RUNTIME_UPDATE",
            review_decision="LOCAL_HISTORICAL_MANIFEST_BYTES_MATCH_INPUT_BINDING_STILL_REQUIRED",
            working_tree_dirty=False, candidate_authors=authors,
            local_manifest_byte_matches=[dict(sha256="c" * 64, proof="HISTORICAL_DECLARATION_ONLY")]))
    scope = dict(schema=1, kind=m.REVIEW_KIND, observed_commits=PINS.copy(),
                 current_worktree_runtime=[], decisions=rows)
    return scope, trees


def select(scope, trees, pins=None, digest=None):
    raw = (json.dumps(scope, ensure_ascii=False, indent=2) + "\n").encode()
    return m.select(raw, digest or m.compiler.sha(raw), pins or PINS, trees,
                    original_path="original_review.json")


class DynamicScopeTests(unittest.TestCase):
    def test_all_supported_types_and_historical_rows_are_selected_once_with_exact_provenance(self):
        resources = ["panorama/scripts/a.vjs_c", "panorama/styles/a.vcss_c",
                     "panorama/layout/a.vxml_c", "panorama/images/a.vtex_c", "panorama/images/a.vsvg_c"]
        scope, trees = fixture(resources)
        duplicate = deepcopy(scope["decisions"][0])
        duplicate.update(inventory_status="UNCOMPILED_BINDING_REQUIRED", review_decision=m.DECISION)
        scope["decisions"].append(duplicate)
        before = deepcopy(scope)
        result = select(scope, trees)
        self.assertEqual(scope, before)
        self.assertEqual(result["original_scope_document"], before)
        self.assertEqual({r["resource"] for r in m.compiler.selected_rows(result)}, set(resources))
        self.assertEqual(result["selection_counts"]["unique_resources"], len(resources))
        original = next(r["original_inventory_rows"] for r in result["decisions"] if r["resource"] == resources[0])
        self.assertEqual([r["decision"] for r in original], [before["decisions"][0], before["decisions"][-1]])
        raw = (json.dumps(scope, ensure_ascii=False, indent=2) + "\n").encode()
        self.assertEqual(result["original_scope"], dict(path="original_review.json", sha256=m.compiler.sha(raw), bytes=len(raw)))
        self.assertFalse(result["compilation_performed"])

    def test_raw_sha_cannot_be_replaced_by_a_reserialized_json_hash(self):
        scope, trees = fixture(["panorama/scripts/a.vjs_c"])
        with self.assertRaisesRegex(ValueError, "raw_sha256"):
            select(scope, trees, digest=m.compiler.sha(m.compiler.canonical(scope)))

    def test_partial_old_additional_scope_is_not_an_all_pending_review(self):
        scope, trees = fixture(["panorama/scripts/a.vjs_c"])
        scope["kind"] = "ADDITIONAL_TWO_RESOURCES_ONLY"
        with self.assertRaisesRegex(ValueError, "full_pending_scope"):
            select(scope, trees)

    def test_observed_commits_must_match_selected_immutable_pair(self):
        scope, trees = fixture(["panorama/scripts/a.vjs_c"])
        with self.assertRaisesRegex(ValueError, "observed_commits"):
            select(scope, trees, {**PINS, "game": "c" * 40})

    def test_author_oid_size_commit_or_presence_drift_blocks_instead_of_skipping(self):
        for field, value in (("oid", "c" * 40), ("bytes", 1), ("source_commit", "c" * 40),
                             ("exists_in_observed_commit", False)):
            with self.subTest(field=field):
                scope, trees = fixture(["panorama/scripts/a.vjs_c"])
                scope["decisions"][0]["candidate_authors"][0][field] = value
                with self.assertRaisesRegex(ValueError, "author_(git_drift|missing)"):
                    select(scope, trees)

    def test_missing_author_mapping_or_symlink_mode_cannot_pass(self):
        scope, trees = fixture(["panorama/scripts/a.vjs_c"])
        scope["decisions"][0]["candidate_authors"].pop()
        with self.assertRaisesRegex(ValueError, "mapping_incomplete"):
            select(scope, trees)
        scope, trees = fixture(["panorama/scripts/a.vjs_c"])
        author = scope["decisions"][0]["candidate_authors"][0]
        trees[author["repo"]][author["path"]]["mode"] = "120000"
        with self.assertRaisesRegex(ValueError, "immutable_author_missing"):
            select(scope, trees)

    def test_source_oid_drift_is_checked_even_if_its_authors_are_current(self):
        scope, trees = fixture(["panorama/scripts/a.vjs_c"])
        scope["decisions"][0]["source"]["head_oid"] = "c" * 40
        with self.assertRaisesRegex(ValueError, "source_git_oid_drift"):
            select(scope, trees)

    def test_known_and_unknown_unsupported_native_types_are_explicitly_rejected(self):
        for resource in ("models/a.vmdl_c", "panorama/a.newtype_c", "maps/a.vpk"):
            scope, trees = fixture(["panorama/scripts/a.vjs_c"])
            row = deepcopy(scope["decisions"][0]); row["resource"] = resource
            scope["decisions"].append(row)
            with self.subTest(resource=resource), self.assertRaisesRegex(ValueError, "unsupported_official_compiler_mapping"):
                select(scope, trees)

    def test_dirty_runtime_metadata_cannot_select_an_obsolete_source_freeze(self):
        for target in ("global", "row", "author"):
            scope, trees = fixture(["panorama/scripts/a.vjs_c"])
            if target == "global": scope["current_worktree_runtime"] = [{"path": "changed.js"}]
            elif target == "row": scope["decisions"][0]["working_tree_dirty"] = True
            else: scope["decisions"][0]["candidate_authors"][0]["working_copy_dirty"] = True
            with self.subTest(target=target), self.assertRaisesRegex(ValueError, "uncommitted_runtime"):
                select(scope, trees)

    def test_removals_are_preserved_and_never_resurrected_by_compilation(self):
        scope, trees = fixture(["panorama/scripts/a.vjs_c"])
        removed = dict(resource="panorama/scripts/deleted.vjs_c",
            source=dict(repo="game", path="panorama/scripts/deleted.vjs_c", head_oid=None))
        scope["decisions"].append(removed)
        result = select(scope, trees)
        self.assertEqual(result["explicit_runtime_removals"], [removed["resource"]])
        self.assertNotIn(removed["resource"], [r["resource"] for r in result["decisions"]])
        removed["resource"] = scope["decisions"][0]["resource"]
        with self.assertRaisesRegex(ValueError, "conflicting_live_and_removed"):
            select(scope, trees)

    def test_operator_identity_must_cover_the_loaded_generator_bytes(self):
        with patch.object(m.compiler, "immutable"), patch.object(m.compiler, "run_git", return_value=b"substituted tool"), \
                patch.object(m.compiler, "operator_binding", side_effect=AssertionError("must reject first")):
            with self.assertRaisesRegex(ValueError, "frozen_operator_commit"):
                m._operator("a" * 40)


class ActualGitScopeTests(unittest.TestCase):
    def test_real_original_trees_author_bindings_and_real_compiler_selector(self):
        pins = {"game": "a717903f6219086da17f72d872f63ef8de153160",
                "content": "3700b2328007c157325cdf204dbe47dcf7c42a9e"}
        counts = Counter()
        trees = {role: m.compiler.inventory.git_tree(root, counts, pins[role])
                 for role, root in (("game", m.ROOT), ("content", m.compiler.CONTENT))}
        resources = ["panorama/scripts/custom_game/lottery_cinematic_v1.vjs_c",
                     "panorama/styles/custom_game/lottery_cinematic_v1.vcss_c"]
        rows = []
        for resource in resources:
            authors = []
            for role, name in sorted(m._authors(resource)):
                actual = trees[role][name]
                authors.append(dict(repo=role, path=name, oid=actual["oid"], bytes=actual["bytes"],
                    source_commit=pins[role], exists_in_observed_commit=True, working_copy_dirty=False))
            actual = trees["game"][resource]
            rows.append(dict(resource=resource, source=dict(repo="game", path=resource, head_oid=actual["oid"]),
                candidate_authors=authors, inventory_status="PENDING_RUNTIME_UPDATE",
                review_decision="LOCAL_HISTORICAL_MANIFEST_BYTES_MATCH_INPUT_BINDING_STILL_REQUIRED"))
        scope = dict(schema=1, kind=m.REVIEW_KIND, observed_commits=pins,
                     current_worktree_runtime=[], decisions=rows)
        result = select(scope, trees, pins)
        self.assertEqual([r["resource"] for r in m.compiler.selected_rows(result)], sorted(resources))
        self.assertEqual(counts["git_tree_calls"], len(pins))
        scope["decisions"][0]["candidate_authors"][0]["oid"] = "f" * 40
        with self.assertRaisesRegex(ValueError, "scope_author_git_drift"):
            select(scope, trees, pins)


if __name__ == "__main__": unittest.main()
