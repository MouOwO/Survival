"""Complete-source projection fixtures; no SDK, VPK, Git, process or writes."""
from copy import deepcopy
import hashlib
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from complete_delivery_release_20261103 import build_release as build, ledger, validator


def fp(raw):
    return {"sha256": hashlib.sha256(raw).hexdigest(), "bytes": len(raw), "md5": hashlib.md5(raw).hexdigest()}


def fixture():
    pins = {"game": "a" * 40, "content": "b" * 40, "operator": "c" * 40}
    sources = {"game:scripts/vscripts/a.lua": b"new code", "content:panorama/scripts/a.js": b"new author\n",
               "game:panorama/scripts/a.vjs_c": b"official compiled", "game:scripts/vscripts/protected.lua": b"new readable source",
               "game:scripts/vscripts/identical.lua": b"same published bytes", "game:data/ui/review.json": b"public build review"}
    facts = {key: {**fp(raw), "git_oid": hashlib.sha1(key.encode()).hexdigest(), "commit": pins[key.split(":")[0]]}
             for key, raw in sources.items()}
    rows = []
    for key in facts:
        role, path = key.split(":", 1)
        resource = None if path.startswith("data/") else "panorama/scripts/a.vjs_c" if role == "content" else path
        rows.append({"source": {"repo": role, "path": path, "head_oid": facts[key]["git_oid"]}, "resource": resource,
                     "status": "HISTORICAL_REVIEW_REQUIRED_PARENT_BYTES_MATCH" if "identical" in key else "UNMAPPED_SOURCE_PENDING",
                     "blocking": True, "history": ["historical"] if "identical" in key else []})
    rows.append({"source": {"repo": "game", "path": "panorama/styles/dead.vcss_c", "head_oid": None},
                 "resource": "panorama/styles/dead.vcss_c", "status": "RUNTIME_REMOVAL_PENDING", "blocking": True, "history": ["unpublished0201"]})
    parent_rows = [{"path": name, **fp(raw)} for name, raw in {
        "scripts/vscripts/a.lua": b"old code", "panorama/scripts/a.vjs_c": b"old compiled", "maps/template_map.vpk": b"unchanged real map",
        "scripts/vscripts/identical.lua": sources["game:scripts/vscripts/identical.lua"], "panorama/styles/dead.vcss_c": b"deleted compiled"}.items()]
    parent = {"files": parent_rows, "file_count": len(parent_rows), "bytes": sum(row["bytes"] for row in parent_rows), "content_sha256": "f" * 64}
    inventory = {"kind": "READ_ONLY_ALL_PENDING_WORKSHOP_INVENTORY", "target_commits": {key: pins[key] for key in ("game", "content")},
                 "recorded_parent_content_sha256": parent["content_sha256"], "rows": rows, "dirty": []}
    bindings = []
    def binding(name, kind, keys, output):
        row = {"resource": name, "kind": kind, "inputs": [{"source_id": key, "sha256": facts[key]["sha256"], "git_oid": facts[key]["git_oid"]} for key in keys], "output": output}
        bindings.append(row)
        return row
    binding("scripts/vscripts/a.lua", "identity", ["game:scripts/vscripts/a.lua"], fp(sources["game:scripts/vscripts/a.lua"]))
    binding("scripts/vscripts/identical.lua", "identity", ["game:scripts/vscripts/identical.lua"], fp(sources["game:scripts/vscripts/identical.lua"]))
    compiled = binding("panorama/scripts/a.vjs_c", "compiled", ["content:panorama/scripts/a.js", "game:panorama/scripts/a.vjs_c"], fp(sources["game:panorama/scripts/a.vjs_c"]))
    protected = binding("scripts/vscripts/protected.lua", "protected", ["game:scripts/vscripts/protected.lua"], fp(b"protected source with exact values verified upstream"))
    proof = {"kind": "COMPLETE_RUNTIME_BINDING_RECEIPT", "source_revisions": pins, "bindings": {
        row["resource"]: {"kind": row["kind"], "inputs": {value["source_id"]: value["sha256"] for value in row["inputs"]}, "output": row["output"]}
        for row in (compiled, protected)}}
    proof_raw = ledger.canonical(proof); proof_sha = ledger.sha(proof_raw)
    for row in (compiled, protected): row["receipt_sha256"] = proof_sha
    review = {"kind": "NON_RUNTIME_EXACT_PATH_REVIEW", "source_revisions": pins, "source_id": "game:data/ui/review.json",
              "source_sha256": facts["game:data/ui/review.json"]["sha256"], "reason": "Exact public review input, no runtime consumer", "reference_scan_sha256": "d" * 64}
    review_raw = ledger.canonical(review); review_sha = ledger.sha(review_raw)
    decisions = []
    for row in rows:
        key = row["source"]["repo"] + ":" + row["source"]["path"]
        decisions.append({"source_id": key, "action": "remove" if row["source"]["head_oid"] is None else "non_runtime" if row["resource"] is None else "publish",
                          **({"receipt_sha256": review_sha} if row["resource"] is None else {"resource": row["resource"]})})
    scope = {"source_revisions": pins, "decisions": decisions, "bindings": bindings}
    return {"parent": parent, "inventory": inventory, "scope": scope, "facts": {"source_revisions": pins, "sources": facts},
            "receipts": {proof_sha: proof_raw, review_sha: review_raw}}


def inputs(f):
    parent_raw = ledger.canonical(f["parent"]); parent_sha = ledger.sha(parent_raw)
    f["inventory"]["recorded_parent_manifest_sha256"] = parent_sha
    inventory_raw = ledger.canonical(f["inventory"]); inventory_sha = ledger.sha(inventory_raw)
    facts_raw = ledger.canonical(f["facts"]); facts_sha = ledger.sha(facts_raw)
    f["scope"].update(parent_manifest_sha256=parent_sha, inventory_sha256=inventory_sha, source_facts_sha256=facts_sha)
    scope_raw = ledger.canonical(f["scope"])
    return dict(parent_raw=parent_raw, parent_sha256=parent_sha, inventory_raw=inventory_raw, inventory_sha256=inventory_sha,
                scope_raw=scope_raw, scope_sha256=ledger.sha(scope_raw), facts_raw=facts_raw, facts_sha256=facts_sha, receipts=f["receipts"])


class CompleteProjectionTests(unittest.TestCase):
    def test_actual_parent_projection_all_sources_history_and_removal(self):
        f = fixture(); supplied = inputs(f); result = build.project(**supplied)
        self.assertEqual(result["changed_runtime_paths"], ["panorama/scripts/a.vjs_c", "scripts/vscripts/a.lua", "scripts/vscripts/protected.lua"])
        self.assertEqual(result["added_runtime_paths"], ["scripts/vscripts/protected.lua"])
        self.assertEqual(result["removed_runtime_paths"], ["panorama/styles/dead.vcss_c"])
        self.assertEqual(result["reviewed_parent_identical_resources"], ["scripts/vscripts/identical.lua"])
        actual = {row["path"]: row for row in result["projected_rows"]}
        original = {row["path"]: row for row in f["parent"]["files"]}
        self.assertEqual(actual["maps/template_map.vpk"], original["maps/template_map.vpk"])
        self.assertEqual(result["coverage_ledger"]["counts"]["sources"], 7)
        self.assertEqual(len(result["coverage_ledger"]["historical_sources"]), 2)
        self.assertTrue(validator.validate_projection(result, **supplied)["coverage_complete"])
        self.assertFalse(result["build_ready"]); self.assertFalse(result["publication_ready"])

    def test_dynamic_more_than_old_fixed_payload_count(self):
        f = fixture()
        for n in range(12):
            name = f"scripts/vscripts/additional_{n}.lua"; key = "game:" + name; value = fp(f"source{n}".encode())
            fact = {**value, "git_oid": hashlib.sha1(key.encode()).hexdigest(), "commit": f["scope"]["source_revisions"]["game"]}
            f["facts"]["sources"][key] = fact
            f["inventory"]["rows"].append({"source": {"repo": "game", "path": name, "head_oid": fact["git_oid"]}, "resource": name, "status": "PENDING_RUNTIME_ADD", "history": []})
            f["scope"]["decisions"].append({"source_id": key, "action": "publish", "resource": name})
            f["scope"]["bindings"].append({"resource": name, "kind": "identity", "inputs": [{"source_id": key, "sha256": fact["sha256"], "git_oid": fact["git_oid"]}], "output": value})
        result = build.project(**inputs(f))
        self.assertEqual(len(result["changed_runtime_paths"]), 15)
        self.assertEqual(result["coverage_ledger"]["counts"]["sources"], 19)

    def test_historical_parent_matching_bytes_still_require_explicit_review(self):
        f = fixture(); f["scope"]["decisions"] = [row for row in f["scope"]["decisions"] if "identical" not in row["source_id"]]
        with self.assertRaisesRegex(ValueError, "complete_pending_source_coverage_required"):
            build.project(**inputs(f))

    def test_no_deferral_prefix_exclusion_unknown_source_or_duplicate_decision(self):
        for mutate, reason in (
            (lambda f: f["scope"]["decisions"][0].update(action="defer"), "no_deferred"),
            (lambda f: f["scope"]["decisions"].append(deepcopy(f["scope"]["decisions"][0])), "duplicate_source_decision"),
            (lambda f: f["scope"]["decisions"][0].update(source_id="game:scripts/**"), "unknown_or_duplicate"),
            (lambda f: f["inventory"]["rows"].append(deepcopy(f["inventory"]["rows"][0])), "duplicate_inventory"),
        ):
            f = fixture(); mutate(f)
            with self.assertRaisesRegex(ValueError, reason): build.project(**inputs(f))

    def test_compiled_old_receipt_source_hash_and_output_mix_rejected(self):
        for mutate, reason in (
            (lambda f: f["scope"]["bindings"][2]["inputs"][0].update(sha256="e" * 64), "source_hash_or_oid"),
            (lambda f: f["scope"]["bindings"][2]["output"].update(sha256="e" * 64), "receipt_output_or_inputs"),
            (lambda f: f["scope"]["source_revisions"].update(content="e" * 40), "inventory_source_commit"),
            (lambda f: f["scope"]["bindings"][2].update(receipt_sha256="e" * 64), "receipt_missing"),
        ):
            f = fixture(); mutate(f)
            with self.assertRaisesRegex(ValueError, reason): build.project(**inputs(f))

    def test_runtime_must_not_be_declared_non_runtime_or_deleted_while_live(self):
        f = fixture(); f["scope"]["decisions"][0].update(action="non_runtime", receipt_sha256=next(iter(f["receipts"])))
        with self.assertRaisesRegex(ValueError, "runtime_or_deleted_source"): build.project(**inputs(f))
        f = fixture(); f["scope"]["decisions"][0].update(action="remove")
        with self.assertRaisesRegex(ValueError, "runtime_removal"): build.project(**inputs(f))

    def test_dirty_unverified_lfs_noncanonical_paths_and_parent_duplicates_fail(self):
        for mutate, reason in (
            (lambda f: f["inventory"]["dirty"].append({"path": "x", "runtime_related": True}), "dirty_or_unclassified"),
            (lambda f: f["facts"]["sources"]["game:scripts/vscripts/a.lua"].update(lfs=True), "unresolved_lfs"),
            (lambda f: f["scope"]["bindings"][0].update(resource="scripts/../private.key"), "canonical_relative"),
            (lambda f: f["parent"]["files"].append(deepcopy(f["parent"]["files"][0])), "duplicate_or_case_colliding"),
        ):
            f = fixture(); mutate(f)
            with self.assertRaisesRegex(ValueError, reason): build.project(**inputs(f))

    def test_exact_raw_controls_and_duplicate_json_are_not_silently_normalized(self):
        supplied = inputs(fixture()); supplied["scope_raw"] += b" "
        with self.assertRaisesRegex(ValueError, "exact_bounded_document"): build.project(**supplied)
        raw = b'{"x":1,"x":2}'
        with self.assertRaisesRegex(ValueError, "duplicate_json_key"): ledger.document(raw, ledger.sha(raw))

    def test_current_compiled_bytes_cannot_bypass_compiler_receipt_as_identity(self):
        f = fixture(); binding = f["scope"]["bindings"][2]
        binding.update(kind="identity", inputs=[binding["inputs"][1]])
        binding.pop("receipt_sha256")
        with self.assertRaisesRegex(ValueError, "compiled_resource_requires_compiler_receipt"): build.project(**inputs(f))

    def test_unknown_and_nonregular_inventory_statuses_are_never_guessed(self):
        for status in ("NON_REGULAR_GIT_ENTRY", "HASH_BUDGET_EXCEEDED", "INVENTED_READY"):
            f = fixture(); f["inventory"]["rows"][0]["status"] = status
            with self.assertRaisesRegex(ValueError, "unknown_or_unverified_inventory_status"): build.project(**inputs(f))

    def test_independent_validator_detects_modified_complete_rows_and_ready_flags(self):
        supplied = inputs(fixture()); report = build.project(**supplied)
        for mutate in (lambda r: r.update(publication_ready=True), lambda r: r["projected_rows"].pop(),
                       lambda r: r["coverage_ledger"].update(unknown_sources=[] ,ledger_sha256="0" * 64)):
            changed = deepcopy(report); mutate(changed)
            with self.assertRaisesRegex(ValueError, "independent_rederivation"): validator.validate_projection(changed, **supplied)

    def test_signing_materialization_and_real_authority_remain_explicitly_blocked(self):
        for call in (build.prepare_unsigned, build.build_signed, validator.validate_release, validator.validate_bootstrap):
            with self.assertRaisesRegex(ValueError, "not_implemented_preserve"): call()
        self.assertFalse(build.static_plan()["package_build_implemented"])


if __name__ == "__main__":
    unittest.main()
