"""Select every supported pending compiled resource from one pinned full review.

Cold cost: two Git tree indexes plus O(review rows + unique resources) lookups.
No source blob reads, compiler, recurring scan, Git mutation or runtime writes.
Historical byte matches remain selected; only original compiler receipts can
prove a compilation. The original review is preserved without rewriting it.
"""
from __future__ import annotations

import argparse
from collections import Counter
from copy import deepcopy
import json
from pathlib import Path, PurePosixPath
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import release_compile_scope as compiler

TOOL = "tools/complete_delivery_release_20261103/compile_scope.py"
LOADED_SHA = compiler.sha(Path(__file__).read_bytes().replace(b"\r\n", b"\n"))
REVIEW_KIND = "ALL_PENDING_AND_CURRENT_WORKTREE_SCOPE_REVIEW_NOT_A_BUILD_RECIPE"
DECISION = "IMMUTABLE_AUTHORS_AVAILABLE_RECOMPILE_OR_VALIDATE_EMBEDDED_BINDING"


def _authors(resource):
    primary = compiler.content_source(resource)  # Reject unknown native types.
    values = [("content", primary)]
    if PurePosixPath(primary).suffix in {".js", ".css", ".xml"}:
        values.append(("game", primary.replace("panorama/", "panorama/src/", 1)))
    return set(values)


def select(scope_raw, scope_sha256, pins, trees, *, original_path):
    """Pure selection over actual caller-supplied immutable Git tree indexes."""
    need = compiler.need
    need(isinstance(scope_raw, bytes) and len(scope_raw) <= 16 * 1024 * 1024,
         "bounded_original_full_scope_required")
    need(compiler.HEX.fullmatch(scope_sha256 or "") and compiler.sha(scope_raw) == scope_sha256,
         "original_scope_raw_sha256_mismatch")
    scope = json.loads(scope_raw)
    need(isinstance(scope, dict) and scope.get("schema") == 1 and scope.get("kind") == REVIEW_KIND,
         "original_full_pending_scope_review_required")
    need(set(pins) == {"game", "content"} and set(trees) == set(pins), "explicit_source_pair_required")
    for revision in pins.values(): need(compiler.REV.fullmatch(revision or ""), "immutable_commit_required")
    need(scope.get("observed_commits") == pins, "scope_observed_commits_differ_from_selected_sources")
    need(scope.get("current_worktree_runtime") == [], "scope_has_uncommitted_runtime_changes")
    need(isinstance(scope.get("decisions"), list), "full_scope_decisions_required")
    groups, removals = {}, set()
    for index, row in enumerate(scope["decisions"]):
        need(isinstance(row, dict), "scope_decision_object_required")
        resource = compiler.safe(row.get("resource"))
        suffix = PurePosixPath(resource).suffix
        if suffix not in compiler.inventory.COMPILED_SUFFIXES and not suffix.endswith("_c"):
            continue
        source = row.get("source", {})
        role, path = source.get("repo"), source.get("path")
        need(role in trees, "scope_source_repo_invalid")
        compiler.safe(path)
        actual = trees[role].get(path)
        need(source.get("head_oid") == (actual or {}).get("oid"), "scope_source_git_oid_drift:" + path)
        if source.get("head_oid") is None:
            removals.add(resource)
            continue
        need(not row.get("working_tree_dirty"), "scope_has_uncommitted_runtime_changes")
        expected = _authors(resource)
        authors = row.get("candidate_authors")
        need(isinstance(authors, list) and len(authors) == len(expected)
             and {(a.get("repo"), a.get("path")) for a in authors} == expected,
             "scope_author_mapping_incomplete:" + resource)
        for author in authors:
            repo, name = author["repo"], author["path"]
            actual = trees[repo].get(name)
            need(author.get("exists_in_observed_commit") is True and actual is not None
                 and actual.get("kind") == "blob" and actual.get("mode") in {"100644", "100755"},
                 "scope_immutable_author_missing:" + name)
            need(author.get("source_commit") == pins[repo] and author.get("oid") == actual.get("oid")
                 and author.get("bytes") == actual.get("bytes"), "scope_author_git_drift:" + name)
            need(not author.get("working_copy_dirty"), "scope_has_uncommitted_runtime_changes")
        groups.setdefault(resource, []).append({"original_index": index, "decision": deepcopy(row)})
    need(not removals.intersection(groups), "scope_conflicting_live_and_removed_compiled_resource")
    need(groups, "nonempty_supported_compile_scope_required")
    decisions = []
    for resource, originals in sorted(groups.items()):
        row = deepcopy(originals[0]["decision"])
        row.update(inventory_status="UNBOUND_COMPILED_ARTIFACT", review_decision=DECISION,
                   original_inventory_rows=originals,
                   selection_reason="ALL_PENDING_SUPPORTED_AUTHORS_INCLUDING_HISTORICAL_BYTE_MATCHES")
        decisions.append(row)
    need([r["resource"] for r in compiler.selected_rows({"decisions": decisions})] == sorted(groups),
         "actual_compiler_selector_dropped_dynamic_resource")
    return dict(schema=1, kind="DYNAMIC_ALL_PENDING_SUPPORTED_OFFICIAL_COMPILE_SCOPE",
        observed_commits=pins.copy(), original_scope_document=scope,
        original_scope=dict(path=str(original_path), sha256=scope_sha256, bytes=len(scope_raw)),
        decisions=decisions, explicit_runtime_removals=sorted(removals),
        selection_counts=dict(unique_resources=len(decisions), original_compiled_rows=sum(map(len, groups.values())),
                              by_suffix=dict(sorted(Counter(PurePosixPath(n).suffix for n in groups).items()))),
        immutable_release_sources_selected=True, compilation_performed=False, publication_ready=False,
        sdk_calls=0, network_calls=0, git_mutations=0, project_worktree_writes=0)


def _operator(revision):
    compiler.immutable(ROOT, revision)
    declared = compiler.run_git(ROOT, "show", revision + ":" + TOOL).replace(b"\r\n", b"\n")
    actual = Path(__file__).read_bytes().replace(b"\r\n", b"\n")
    compiler.need(compiler.sha(declared) == LOADED_SHA and actual == declared,
                  "scope_generator_not_in_frozen_operator_commit")
    # The tree inventory functions invoked below must also be the committed ones.
    binding = compiler.operator_binding(revision)
    binding["tools_lf_sha256"][TOOL] = LOADED_SHA
    return binding


def generate(scope_path, scope_sha256, pins, operator_revision):
    roots = {"game": ROOT, "content": compiler.CONTENT}
    operator = _operator(operator_revision)
    for role in roots: compiler.immutable(roots[role], pins[role])
    counts = Counter()
    trees = {role: compiler.inventory.git_tree(root, counts, pins[role]) for role, root in roots.items()}
    compiler.read_json(scope_path, scope_sha256)
    raw = scope_path.read_bytes()
    result = select(raw, scope_sha256, pins, trees, original_path=scope_path)
    result.update(operator_binding=operator, read_costs=dict(counts))
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scope", type=Path, required=True)
    parser.add_argument("--scope-sha256", required=True)
    parser.add_argument("--game-source", required=True)
    parser.add_argument("--content-source", required=True)
    parser.add_argument("--operator-source", required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args(argv)
    destination = args.out.absolute()
    compiler.need(destination.suffix == ".json", "scope_output_json_required")
    compiler.no_reparse(destination, ROOT / "output")
    result = generate(args.scope, args.scope_sha256,
                      {"game": args.game_source, "content": args.content_source}, args.operator_source)
    compiler.write_new(destination, compiler.canonical(result))
    print(json.dumps(dict(kind=result["kind"], report=str(destination),
        sha256=compiler.sha(compiler.canonical(result)), counts=result["selection_counts"],
        publication_ready=False, compilation_performed=False)))


if __name__ == "__main__": main()
