"""Pure complete assembly plus small real unsigned files; no SDK/key/network/Git writes."""
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import struct
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parent))
from complete_delivery_release_20261103 import collect_inputs as c, ledger as m
from test_complete_delivery_projection import fixture, inputs
from test_complete_delivery_prepare import case as file_case


def case():
    f = fixture(); old_inputs = inputs(f)
    raw = {"scripts/vscripts/a.lua": b"new code", "scripts/vscripts/identical.lua": b"same published bytes",
           "panorama/scripts/a.vjs_c": b"official compiled", "scripts/vscripts/protected.lua": b"protected source with exact values verified upstream"}
    targets = {row["resource"]: {"kind": row["kind"], "raw": raw[row["resource"]], "sources": [v["source_id"] for v in row["inputs"]],
                                "evidence": [{"kind": "SYNTHETIC_UNIT_INPUT_NOT_REAL_COMPILER"}]} for row in f["scope"]["bindings"]}
    key = "game:data/ui/review.json"; fact = f["facts"]["sources"][key]
    review = {"reference_scan_sha256": "d" * 64, "reviews": [{"source_id": key, "sha256": fact["sha256"], "git_oid": fact["git_oid"],
        "standalone_runtime_file_required": False, "authority_granted": False, "scope_action_proposal": "non_runtime_standalone_exact_path_review",
        "source_revision": f["scope"]["source_revisions"]["game"], "reason": "Exact reviewed public evidence file", "runtime_targets_requiring_separate_generator_or_compiler_binding": []}]}
    return dict(pins=f["scope"]["source_revisions"], parent_raw=old_inputs["parent_raw"], parent_sha256=old_inputs["parent_sha256"],
                base_inventory=f["inventory"], facts=f["facts"]["sources"], targets=targets, review=review,
                review_sha256=m.sha(m.canonical(review)), reference_scan_sha256="d" * 64)


class CollectTests(unittest.TestCase):
    def test_all_current_history_and_delete_become_real_projection_inputs(self):
        value = c.assemble(**case())
        self.assertFalse(value["blockers"]); self.assertEqual(len(value["projection"]["changed_runtime_paths"]), 3)
        self.assertEqual(value["projection"]["removed_runtime_paths"], ["panorama/styles/dead.vcss_c"])
        self.assertEqual(value["projection"]["coverage_ledger"]["counts"]["sources"], 7)
        self.assertFalse(value["publication_ready"])
        self.assertEqual(value["projection_sha256"], m.sha(value["projection_raw"]))

    def test_oid_unchanged_derived_protection_is_added_to_explicit_inventory(self):
        value = case(); parent = m.document(value["parent_raw"], value["parent_sha256"])
        # This source never appears in the Git-diff inventory. New ciphertext
        # still needs review and must replace the actual parent resource.
        for n in range(18):
            name = f"scripts/vscripts/derived_{n}.lua"; key = "game:" + name; plain = f"unchanged immutable source {n}".encode()
            value["facts"][key] = {"commit": value["pins"]["game"], "git_oid": hashlib.sha1(key.encode()).hexdigest(), **m.byte_fingerprint(plain)}
            value["targets"][name] = {"kind": "protected", "raw": b"new cipher " + plain, "sources": [key]}
            parent["files"].append({"path": name, **m.byte_fingerprint(b"old cipher " + plain)})
        parent["file_count"] = len(parent["files"]); parent["bytes"] = sum(row["bytes"] for row in parent["files"])
        value["parent_raw"] = m.canonical(parent); value["parent_sha256"] = m.sha(value["parent_raw"])
        value["base_inventory"]["recorded_parent_manifest_sha256"] = value["parent_sha256"]
        result = c.assemble(**value)
        inventory = m.document(result["inputs"]["inventory_raw"], result["inputs"]["inventory_sha256"])
        self.assertEqual(inventory["derived_output_rows"], 20)
        self.assertEqual(len(result["projection"]["changed_runtime_paths"]), 21)
        for n in range(18): self.assertIn(f"scripts/vscripts/derived_{n}.lua", result["projection"]["changed_runtime_paths"])

    def test_parent_identical_source_is_not_implicitly_excluded_from_review(self):
        value = case(); key = "game:scripts/vscripts/protected.lua"
        row = next(row for row in value["base_inventory"]["rows"] if row["source"]["path"] == "scripts/vscripts/protected.lua")
        row["status"] = "PARENT_BYTES_MATCH"
        result = c.assemble(**value)
        decisions = m.document(result["inputs"]["scope_raw"], result["inputs"]["scope_sha256"])["decisions"]
        self.assertEqual(next(d for d in decisions if d["source_id"] == key)["action"], "publish")

    def test_unknown_new_data_path_is_listed_not_prefix_excluded(self):
        value = case(); key = "game:data/ui/new_unknown.json"; fact = {**m.byte_fingerprint(b"new content"), "commit": value["pins"]["game"], "git_oid": "e" * 40}
        value["facts"][key] = fact
        value["base_inventory"]["rows"].append({"source": {"repo": "game", "path": key.split(":", 1)[1], "head_oid": fact["git_oid"]},
            "resource": None, "status": "UNMAPPED_SOURCE_PENDING", "history": ["historical"]})
        result = c.assemble(**value)
        self.assertEqual(result["blockers"][0]["source_id"], key); self.assertNotIn("projection", result)

    def test_review_wrong_hash_or_missing_real_derived_target_stays_blocked(self):
        for mode in ("hash", "oid", "target", "authority", "standalone"):
            with self.subTest(mode=mode):
                value = case(); review = value["review"]["reviews"][0]
                if mode == "hash": review["sha256"] = "0" * 64
                elif mode == "oid": review["git_oid"] = "0" * 40
                elif mode == "target": review["runtime_targets_requiring_separate_generator_or_compiler_binding"] = ["scripts/missing.lua"]
                elif mode == "authority": review["authority_granted"] = True
                else: review["standalone_runtime_file_required"] = True
                self.assertTrue(c.assemble(**value)["blockers"])

    def test_build_input_can_cover_json_without_shipping_json_file(self):
        value = case(); key = value["review"]["reviews"][0]["source_id"]
        value["targets"]["scripts/vscripts/protected.lua"]["sources"].append(key)
        result = c.assemble(**value)
        scope = m.document(result["inputs"]["scope_raw"], result["inputs"]["scope_sha256"])
        decision = next(row for row in scope["decisions"] if row["source_id"] == key)
        self.assertEqual(decision["action"], "publish"); self.assertEqual(decision["resource"], "scripts/vscripts/protected.lua")
        self.assertFalse(any(row["path"].startswith("data/") for row in result["projection"]["projected_rows"]))

    def test_real_unsigned_prepare_bridge_preserves_exact_review_receipt_bytes(self):
        with tempfile.TemporaryDirectory() as temporary:
            value = file_case(Path(temporary)); projection = m.document(value["reviewed_projection_raw"], value["reviewed_projection_sha256"])
            result = {"inputs": value["inputs"], "projection_raw": value["reviewed_projection_raw"], "projection_sha256": value["reviewed_projection_sha256"]}
            prepared = c.prepare(result, {"artifact_paths": value["artifact_paths"]}, parent_root=value["parent_root"],
                                 destination=value["destination"], allowed_root=value["allowed_root"])
            self.assertEqual(m.sha(prepared["unsigned_review_raw"]), prepared["unsigned_review_sha256"])
            self.assertEqual(prepared["unsigned_review"]["files"], projection["files"])
            self.assertTrue((value["destination"] / c.build.MARKER).is_file())
            self.assertFalse((value["destination"] / c.build.SIGNATURE).exists())

    def test_loaded_dependencies_reject_cached_module_after_source_changes(self):
        self.assertIn("tools/complete_delivery_release_20261103/ledger.py", c.loaded_dependencies())
        with patch.object(c.ledger, "EXECUTED_SOURCE_LF_SHA256", "0" * 64):
            with self.assertRaisesRegex(ValueError, "changed_after_import"): c.loaded_dependencies()

    def test_parent_signed_js_rebind_requires_whole_artifact_and_exact_data(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); name = "panorama/src/scripts/example.js"; runtime = "panorama/scripts/example.vjs_c"
            author = b"function example() {}\n"; data = author.replace(b"\n", b"\r\n")
            artifact = struct.pack("<IHHII", 28 + len(data), 12, 0, 8, 1) + struct.pack("<4sII", b"DATA", 8, len(data)) + data
            target = root / runtime; target.parent.mkdir(parents=True); target.write_bytes(artifact)
            values = {"game:" + name: author, "game:" + runtime: artifact, "content:panorama/scripts/example.js": author}
            ctx = SimpleNamespace(parent_rows={runtime: {"path": runtime, **m.byte_fingerprint(artifact)}}, parent_sha="d" * 64,
                                  trees={"game": {name: {}, runtime: {}}, "content": {"panorama/scripts/example.js": {}}},
                                  content=lambda key: values[key], get=lambda key: values[key])
            with patch.object(c.pending, "PARENT_MANIFEST", root / c.build.MANIFEST):
                targets = {}; c._attach_generation(ctx, targets, name, author, ["game:" + name], {"kind": "UNIT_GENERATOR"})
                self.assertEqual(targets[runtime]["evidence"][-1]["kind"], "ORIGINAL_SIGNED_RESOURCE_REBIND")
                self.assertEqual(targets[runtime]["evidence"][-1]["normalization"], "GIT_LF_TO_COMPILER_CRLF_ONLY")
                values["game:" + runtime] = artifact + b"wrong current artifact"
                with self.assertRaisesRegex(ValueError, "not_identical"):
                    c._attach_generation(ctx, {}, name, author, ["game:" + name], {"kind": "UNIT_GENERATOR"})


class RawMovieIdentityTests(unittest.TestCase):
    NAME = "panorama/videos/custom_game/lottery_cinematic_v1/bad_media_probe.webm"

    def fixture(self, name=None):
        name = name or self.NAME; value = case(); raw = b"bounded malformed media fixture"
        values = {role+":"+name: raw for role in ("game", "content")}
        for key in values:
            role, path = key.split(":", 1)
            fact = {"commit": value["pins"][role], "git_oid": hashlib.sha1(key.encode()).hexdigest(), **m.byte_fingerprint(raw)}
            value["facts"][key] = fact
            value["base_inventory"]["rows"].append({"source": {"repo": role, "path": path, "head_oid": fact["git_oid"]},
                "resource": name, "status": "PENDING_RUNTIME_ADD", "history": []})
        ctx = SimpleNamespace(pins=value["pins"], trees={role: {name: {}} for role in ("game", "content")},
                              content=lambda key: values[key], get=lambda key: values[key])
        return value, ctx, values

    def test_raw_movie_binds_both_sources_and_ships_exact_bytes_once(self):
        value, ctx, values = self.fixture()
        c._identity_target(ctx, value["targets"], self.NAME)
        result = c.assemble(**value)
        self.assertFalse(result["blockers"])
        self.assertEqual(result["artifact_bytes"][self.NAME], values["game:"+self.NAME])
        scope = m.document(result["inputs"]["scope_raw"], result["inputs"]["scope_sha256"])
        choices = [row for row in scope["decisions"] if row["source_id"].endswith(self.NAME)]
        self.assertEqual({row["source_id"] for row in choices}, {"game:"+self.NAME, "content:"+self.NAME})
        self.assertTrue(all(row["action"] == "publish" and row["resource"] == self.NAME for row in choices))
        self.assertEqual(result["projection"]["added_runtime_paths"].count(self.NAME), 1)

    def test_content_mirror_addition_can_bind_existing_unchanged_game_source(self):
        value, ctx, _ = self.fixture()
        value["base_inventory"]["rows"] = [row for row in value["base_inventory"]["rows"]
            if not (row["source"]["repo"] == "game" and row["source"]["path"] == self.NAME)]
        c._identity_target(ctx, value["targets"], self.NAME)
        self.assertFalse(c.assemble(**value)["blockers"])

    def test_mismatched_mirrors_fail_before_creating_any_identity_target(self):
        value, ctx, values = self.fixture(); values["content:"+self.NAME] += b" changed"
        with self.assertRaisesRegex(ValueError, "raw_video_game_content_bytes_differ"):
            c._identity_target(ctx, value["targets"], self.NAME)
        self.assertNotIn(self.NAME, value["targets"])

    def test_content_only_movie_cannot_invent_an_installed_game_source(self):
        value, ctx, _ = self.fixture(); ctx.trees["game"] = {}
        with self.assertRaisesRegex(ValueError, "identity_game_source_required"):
            c._identity_target(ctx, value["targets"], self.NAME)

    def test_game_only_movie_requires_its_exact_content_mirror(self):
        value, ctx, _ = self.fixture(); ctx.trees["content"] = {}
        with self.assertRaisesRegex(ValueError, "raw_video_content_source_required"):
            c._identity_target(ctx, value["targets"], self.NAME)

    def test_ledger_rejects_raw_mirror_drift_even_if_collector_is_bypassed(self):
        value, ctx, _ = self.fixture(); c._identity_target(ctx, value["targets"], self.NAME)
        value["facts"]["content:"+self.NAME].update(m.byte_fingerprint(b"different mirrored media"))
        with self.assertRaisesRegex(ValueError, "raw_video_mirror_is_not_exact_current_git_bytes"):
            c.assemble(**value)

    def test_mirror_exception_does_not_apply_to_arbitrary_identity_files(self):
        name = "scripts/vscripts/extra.lua"; value, _, values = self.fixture(name)
        value["targets"][name] = {"kind": "identity", "raw": values["game:"+name],
                                  "sources": ["game:"+name, "content:"+name]}
        with self.assertRaisesRegex(ValueError, "identity_output_is_not_exact_current_git_bytes"):
            c.assemble(**value)

    def test_missing_mirror_binding_cannot_be_hidden_as_unmapped_evidence(self):
        value, ctx, _ = self.fixture(); c._identity_target(ctx, value["targets"], self.NAME)
        value["targets"][self.NAME]["sources"] = ["game:"+self.NAME]
        result = c.assemble(**value)
        self.assertEqual(result["status"], "COMPLETE_COLLECTION_BLOCKED_UNRESOLVED_SOURCES")
        self.assertTrue(any(row["source_id"] == "content:"+self.NAME for row in result["blockers"]))


class CatalogRegistryInputTests(unittest.TestCase):
    def fixture(self, unchanged=False):
        import build_ui_static_catalog as cat
        records = {}
        registries = []
        previous = None
        for n in range(3):
            key = "fixture:" + str(n)
            records[key] = {"key": key, "domain": "fixture", "kind": "fixture", "business_id": str(n)}
            previous = cat.update_registry(records, previous)
            registries.append(previous)
        previous_raw = cat.canonical(registries[1])
        current_raw = previous_raw if unchanged else cat.canonical(registries[2])
        values = {"game:" + cat.REGISTRY_PATH: current_raw, "game:data/csv/source.csv": b"unchanged input"}
        for value in registries[:2 if unchanged else 3]:
            raw = cat.canonical(value)
            values["game:data/ui/registry_history/" + m.sha(raw) + ".json"] = raw
        manifest = {"source_hashes": {cat.REGISTRY_PATH: m.sha(previous_raw), "data/csv/source.csv": m.sha(b"unchanged input")},
                    "registry_sha256": m.sha(current_raw)}
        ctx = SimpleNamespace(pins={"game": "a" * 40}, content=lambda key: values[key])
        return cat, ctx, manifest, previous_raw, current_raw, values, registries

    def test_exact_direct_successor_binds_original_input_to_selected_history(self):
        cat, ctx, manifest, previous, current, values, registries = self.fixture()
        sources, proofs = c._catalog_sources(ctx, cat, manifest, previous, current)
        self.assertEqual(len(proofs), 1)
        proof = proofs[0]
        self.assertEqual(proof["original_path"], cat.REGISTRY_PATH)
        self.assertEqual(proof["original_input_sha256"], m.sha(previous))
        self.assertEqual(values[proof["equivalent_selected_source_id"]], previous)
        self.assertEqual((proof["original_generation"], proof["selected_generation"]), (2, 3))
        self.assertEqual(len(proof["verified_history_sources"]), 3)
        self.assertEqual(set(sources), set(values))
        self.assertEqual(proof["selected_registry_output_sha256"], m.sha(current))

    def test_unchanged_registry_preserves_original_exact_input_without_rebinding(self):
        cat, ctx, manifest, previous, current, _, _ = self.fixture(unchanged=True)
        sources, proofs = c._catalog_sources(ctx, cat, manifest, previous, current)
        self.assertFalse(proofs)
        self.assertEqual(sources, sorted("game:" + name for name in manifest["source_hashes"]))

    def test_other_input_drift_never_uses_a_history_alias(self):
        cat, ctx, manifest, previous, current, values, _ = self.fixture()
        values["game:data/csv/source.csv"] += b" changed"
        with self.assertRaisesRegex(ValueError, "catalog_input_changed_since_original_generation:data/csv/source.csv"):
            c._catalog_sources(ctx, cat, manifest, previous, current)

    def test_declared_registry_input_must_be_actual_original_bytes(self):
        cat, ctx, manifest, previous, current, _, _ = self.fixture()
        manifest["source_hashes"][cat.REGISTRY_PATH] = "0" * 64
        with self.assertRaisesRegex(ValueError, "original_input_mismatch"):
            c._catalog_sources(ctx, cat, manifest, previous, current)

    def test_parent_history_must_exist_and_match_every_original_byte(self):
        for mode in ("missing", "whitespace", "changed"):
            with self.subTest(mode=mode):
                cat, ctx, manifest, previous, current, values, _ = self.fixture()
                key = "game:data/ui/registry_history/" + m.sha(previous) + ".json"
                if mode == "missing": del values[key]
                elif mode == "whitespace": values[key] += b" "
                else: values[key] = current
                with self.assertRaises((KeyError, ValueError)):
                    c._catalog_sources(ctx, cat, manifest, previous, current)

    def test_selected_registry_and_manifest_must_be_replayed_output(self):
        for mode in ("selected", "manifest"):
            with self.subTest(mode=mode):
                cat, ctx, manifest, previous, current, values, _ = self.fixture()
                if mode == "selected": values["game:" + cat.REGISTRY_PATH] = current + b" "
                else: manifest["registry_sha256"] = "0" * 64
                with self.assertRaisesRegex(ValueError, "output_mismatch"):
                    c._catalog_sources(ctx, cat, manifest, previous, current)

    def test_only_one_generation_and_exact_parent_are_accepted(self):
        for mode in ("grandparent", "generation_jump", "bool_generation"):
            with self.subTest(mode=mode):
                cat, ctx, manifest, previous, current, values, registries = self.fixture()
                value = json.loads(current)
                if mode == "grandparent": value["parent_sha256"] = m.sha(cat.canonical(registries[0]))
                elif mode == "generation_jump": value["generation"] += 1
                else: value["generation"] = True
                current = cat.canonical(value)
                values["game:" + cat.REGISTRY_PATH] = current
                manifest["registry_sha256"] = m.sha(current)
                with self.assertRaisesRegex(ValueError, "not_direct_successor"):
                    c._catalog_sources(ctx, cat, manifest, previous, current)

    def test_entire_selected_parent_chain_including_self_remains_required(self):
        for mode in ("missing_self", "missing_ancestor", "modified_ancestor", "reassigned_id"):
            with self.subTest(mode=mode):
                cat, ctx, manifest, previous, current, values, registries = self.fixture()
                first_key = "game:data/ui/registry_history/" + m.sha(cat.canonical(registries[0])) + ".json"
                if mode == "missing_self": del values["game:data/ui/registry_history/" + m.sha(current) + ".json"]
                elif mode == "missing_ancestor": del values[first_key]
                elif mode == "modified_ancestor": values[first_key] = previous
                else:
                    value = json.loads(current); value["records"][0]["key"] = "fixture:reassigned"
                    current = cat.canonical(value)
                    values["game:" + cat.REGISTRY_PATH] = current
                    values["game:data/ui/registry_history/" + m.sha(current) + ".json"] = current
                    manifest["registry_sha256"] = m.sha(current)
                with self.assertRaises((KeyError, ValueError)):
                    c._catalog_sources(ctx, cat, manifest, previous, current)

    def test_all_four_actual_outputs_are_checked_before_any_rebinding(self):
        cat, ctx, manifest, previous, current, values, _ = self.fixture()
        origins = {role: "b" * 40 for role in ("game", "content", "operator", "atlas_reference")}
        manifest.update(source_revisions=origins, operator_hashes={}, schema_sha256="d" * 64)
        manifest_raw = m.canonical(manifest)
        output = {cat.MANIFEST_PATH: manifest_raw, cat.REGISTRY_PATH: current,
                  cat.CATALOG_PATH: b"actual catalog", cat.LOOKUP_PATH: b"actual lookup"}
        values.update({"game:" + key: raw for key, raw in output.items()})
        original = {cat.REGISTRY_PATH: previous, "data/csv/source.csv": b"unchanged input"}
        ctx.operator_blob = lambda revision, name: Path(cat.__file__).read_bytes() if name == "tools/build_ui_static_catalog.py" else original[name]
        spec = {"manifest": {"sha256": m.sha(manifest_raw)}, "source_revisions": origins,
                "previous_registry_sha256": m.sha(previous), "lua": "unused-pure-fixture"}
        with patch.object(c, "checked", return_value=(manifest, manifest_raw)), \
             patch.object(cat, "GitSource", return_value=SimpleNamespace(read=lambda path: original[path])), \
             patch.object(cat, "build", return_value=(output, json.loads(current))), \
             patch.object(c, "_catalog_sources", wraps=c._catalog_sources) as bind, \
             patch.object(c, "_attach_generation") as attach:
            values["game:" + cat.CATALOG_PATH] += b" changed"
            with self.assertRaisesRegex(ValueError, "generated_catalog_target_not_exact_current_git"):
                c.load_catalog(ctx, spec, {}, [])
            bind.assert_not_called(); attach.assert_not_called()
            values["game:" + cat.CATALOG_PATH] = output[cat.CATALOG_PATH]
            proofs = []; c.load_catalog(ctx, spec, {}, proofs)
            self.assertEqual(attach.call_count, 2)
            self.assertTrue(proofs[0]["all_four_outputs_exact"])
            self.assertEqual(len(proofs[0]["registry_input_rebindings"]), 1)


if __name__ == "__main__": unittest.main()
