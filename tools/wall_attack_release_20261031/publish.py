"""3101 preflight; --apply updates the original Unlisted item only.

Wall/native acceptance and the completed report hash are explicit inputs.
Never clears pending, changes visibility/testers, or deploys backend services.
"""
from pathlib import Path
import argparse
from datetime import datetime
import hashlib
import json
import re
import sys

sys.dont_write_bytecode = True
import build_release as build
import steam_workshop_upload as publisher

SCOPE = "OFFLINE_NATIVE_COMBAT_MODULE_EQUIVALENCE"
FIX2 = {"scripts/vscripts/modifiers/modifier_enemy_wall_ai.lua", "scripts/vscripts/systems/wall_melee_contact.lua"}
MODES = {"standard", "pure", "rich", "cold"}
MINIMUM_CLOSURE = FIX2 | {"maps/template_map.vpk", "scripts/npc/npc_units_custom.txt", *(
    "scripts/vscripts/" + name + ".lua" for name in (
        "core/team_alignment", "systems/wall_navigation_service", "systems/wall_navigation_geometry",
        "systems/wall_melee_queue", "systems/wall_target_service", "systems/enemy_attack_observer",
        "systems/enemy_ranged_stationary", "systems/wave_attack_rules", "systems/tree_attack_order_filter",
        "systems/tree_damage_rules", "combat/damage_filter_service", "systems/anti_air_rules",
        "combat/endless_stat_projection", "systems/commerce_titan_aura_values",
        "modifiers/modifier_building_under_construction", "systems/building_system", "systems/wave_system"))}


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf8")


class ProofInputs:
    """One explicit offline validation pass; no execution of proof contents."""
    def __init__(self):
        self.snapshots, self.sources = {}, {}

    @staticmethod
    def path(name, origin):
        value = Path(name)
        if not value.is_absolute():
            value = (build.ROOT if str(value).replace("\\", "/").startswith("output/") else origin.parent) / value
        return build.pack.handoff.regular_path(value)

    def reference(self, ref, origin, *, decode=True):
        build.need(isinstance(ref, dict) and isinstance(ref.get("path"), str)
                   and re.fullmatch(r"[0-9a-f]{64}", ref.get("sha256", "")) is not None, "Explicit proof path/SHA256 required")
        path = self.path(ref["path"], origin)
        raw = build.pack.read_metadata(path, build.pack.MAX_MANIFEST)
        build.need(hashlib.sha256(raw).hexdigest() == ref["sha256"], "Proof reference changed: " + path.name)
        if path in self.snapshots: build.need(self.snapshots[path] == raw, "Proof changed within admission")
        self.snapshots[path] = raw
        return (build.pack.handoff.decode_json(raw) if decode else raw), path

    def source(self, path, pin):
        if pin is None:
            build.need(not path.exists(), "Previously missing scoped source appeared: " + path.name)
            self.sources[path] = None
            return
        path = build.pack.handoff.regular_path(path)
        actual = {"bytes": path.stat().st_size, "sha256": build.pack.runtime.digest(path)}
        build.need(actual == pin, "Scoped combat source changed: " + str(path))
        self.sources[path] = actual

    def unchanged(self):
        for path, raw in self.snapshots.items():
            build.need(build.pack.read_metadata(path, build.pack.MAX_MANIFEST) == raw, "Proof changed during admission")
        for path, pin in list(self.sources.items()): self.source(path, pin)


def validate_behavior(raw, timeline_raw):
    build.need(raw.get("storage") == "session_memory" and raw.get("online_multiplayer_acceptance") is False
               and raw.get("test_kind") == "actual_native_Tools_single_formal_wave_cohort"
               and set(raw.get("observed_modes", [])) == MODES, "Four-mode offline native behavior proof required")
    build.need(raw.get("timeline_sha256") == hashlib.sha256(timeline_raw).hexdigest(), "Behavior timeline is not bound to raw report")
    mutation = raw.get("acceptance_actor_mutations", "")
    build.need(mutation.startswith("No NPC teleport") and "PerformAttack" in mutation and "forced order" in mutation,
               "Autonomous post-spawn observation scope required")
    build.need("count=1" in raw.get("fixture", "") and "restored" in raw.get("fixture", ""), "Explicit restored single-cohort fixture required")
    for mode in MODES:
        case = raw.get("labels", {}).get("after_" + mode + "_N1", {})
        build.need(case.get("native_autonomous_attack_pass") is True and case.get("all_unpaused") is True
                   and case.get("all_world_current") is True and case.get("all_enemy_acquisition_zero") is True
                   and all(type(case.get(key)) in (int, float) and case[key] > 0 for key in
                       ("max_native_records", "max_selected_damage_events", "max_wall_health_loss")),
                   "Native autonomous target AND wall damage missing for " + mode)
        final = case.get("final", {})
        build.need(final.get("match_mode") == mode and final.get("wall_rule_allowed") is True
                   and final.get("wall", {}).get("under_construction") is False,
                   "Completed wall admission missing for " + mode)


def validate_loaded(loaded, origin, inputs, manifest, package):
    build.need(loaded.get("schema_version") == 1 and loaded.get("kind") == "WALL_ATTACK_FIX2_LOADED_SOURCE_PROOF"
               and loaded.get("scope") == SCOPE and loaded.get("fresh_vm") is True and loaded.get("online") is False
               and loaded.get("loaded_source_equivalence_proven") is True and loaded.get("source_input_hashes_verified_on_host") is True
               and loaded.get("ok") is True and loaded.get("real_class_unchanged") is True
               and loaded.get("real_contact_module_unchanged") is True, "Fresh VM live loaded-source equivalence proof required")
    runtime = loaded.get("native_runtime", {})
    build.need(runtime.get("pid") == loaded.get("pid") and runtime.get("world_entindex") == loaded.get("world_entindex")
               and runtime.get("match_session_id") == loaded.get("match_session_id")
               and runtime.get("offline_storage") == "session_memory" and runtime.get("map") == "template_map"
               and loaded.get("mode") == "standard" and loaded.get("difficulty") == "N1"
               and type(loaded.get("pid")) is int and loaded["pid"] > 0 and loaded.get("proof_id"), "Loaded VM identity mismatch")
    frozen, frozen_path = inputs.reference({"path": loaded.get("input_manifest"), "sha256": loaded.get("input_manifest_sha256")}, origin)
    build.need(frozen.get("candidate_content_sha256") == package["content_sha256"]
               and loaded.get("candidate_content_sha256") == package["content_sha256"], "Frozen inputs must bind the actual signed candidate")
    build.need(datetime.fromisoformat(runtime["process_started_utc"]) > datetime.fromisoformat(frozen["created_utc"]), "VM must start after candidate source freeze")
    rows = {row["path"]: row for row in manifest["files"]}
    build.need(set(loaded.get("files", {})) == FIX2 and {r["source"] for r in frozen.get("inputs", [])} == FIX2,
               "Exactly the two confirmed plain combat files must be loaded")
    transport, _ = inputs.reference({"path": loaded.get("transport_capture"), "sha256": loaded.get("transport_sha256")}, origin)
    answers = []
    for line in transport.get("rows", []):
        if line.startswith("[WALL_ADMISSION_LOADED_PROOF] {"):
            value = json.loads(line[line.index("{"):])
            if value.get("proof_id") == loaded["proof_id"]: answers.append(value)
    build.need(transport.get("ok") is True and transport.get("pid") == loaded["pid"] and len(answers) == 1,
               "Real native transport capture/identity required")
    answer = answers[0]
    build.need(answer.get("ok") is True and answer.get("fresh_vm") is True and answer.get("pid") == loaded["pid"]
               and answer.get("world") == loaded["world_entindex"] and answer.get("match_session_id") == loaded["match_session_id"]
               and answer.get("real_class_unchanged") is True and answer.get("real_contact_module_unchanged") is True,
               "Raw native loaded proof does not match host receipt")
    raw_nodes = {node["path"]: node for node in answer.get("nodes", [])}
    frozen_rows = {row["source"]: row for row in frozen["inputs"]}
    raw_inputs = {row["source"]: row for row in answer.get("inputs", [])}
    build.need(set(raw_inputs) == FIX2 and all(raw_inputs[name]["sha256"] == rows[name]["sha256"] for name in FIX2),
               "Native transport did not compare the signed candidate inputs")
    covered_nodes = set()
    for name in FIX2:
        item, pin = loaded["files"][name], rows[name]
        build.need(item.get("frozen_source_sha256") == frozen_rows[name]["sha256"] == pin["sha256"]
                   and item.get("native_live_dump_matches_frozen_source") is True
                   and type(item.get("native_function_count")) is int and item["native_function_count"] > 0
                   and len(item.get("native_function_dumps", [])) == item["native_function_count"], "Loaded fix source/count mismatch")
        inputs.reference({"path": frozen_rows[name]["frozen_input"], "sha256": pin["sha256"]}, frozen_path, decode=False)
        for node in item["native_function_dumps"]:
            covered_nodes.add(node["function_path"])
            actual, _ = inputs.reference(node, origin, decode=False)
            observed = raw_nodes.get(node["function_path"], {})
            build.need(node.get("exact_dump_equal") is True and observed.get("exact_dump_equal") is True
                       and bytes.fromhex(observed.get("native_dump_hex", "")) == actual
                       and len(actual) == observed.get("live_bytes") == observed.get("expected_bytes"), "Native function dump mismatch")
    build.need(covered_nodes == set(raw_nodes), "Loaded-source receipt omitted native functions")
    for node in answer.get("scalar_upvalues", []): build.need(node.get("equal") is True, "Native scalar upvalue mismatch")


def function_segments(source):
    starts = list(re.finditer(r"^(?:local )?function ([\w.:]+)\s*\(", source, re.M))
    return {m[1]: source[m.start(): starts[i+1].start() if i+1 < len(starts) else len(source)].strip()
            for i, m in enumerate(starts)}


def validate_equivalence(proof, origin, inputs, manifest):
    build.need(proof.get("schema") == 1 and proof.get("scope") == SCOPE
               and proof.get("status") == "PASS_SCOPED_COMBAT_EQUIVALENCE" and proof.get("passed") is True
               and proof.get("online_multiplayer_acceptance") is False, "Complete scoped equivalence proof required")
    basis = proof.get("basis", {})
    base, dev = Path(basis["baseline_root"]), Path(basis["native_dev_root"])
    build.need(base.resolve() == build.BASE.resolve() and basis.get("baseline_release_sequence") == build.BASE_SEQUENCE,
               "Equivalence must use the verified3004 baseline")
    rows = {row["path"]: row for row in manifest["files"]}
    closure = {row["path"]: row for row in proof.get("closure", [])}
    build.need(len(closure) == len(proof.get("closure", [])) and MINIMUM_CLOSURE <= set(closure), "Combat closure incomplete/duplicate")
    exceptions = {name: item for item in proof.get("known_exceptions", []) for name in item["paths"]}
    pure, pure_path = inputs.reference(proof["pure_data"], origin)
    differences, _ = inputs.reference({"path": proof["pure_data"]["differences_path"], "sha256": proof["pure_data"]["differences_sha256"]}, origin)
    data_results = {row["name"]: row for row in proof["pure_data"]["results"]}
    build.need([{k: v for k, v in row.items() if k != "differences"} for row in differences] == proof["pure_data"]["results"], "Pure-data evidence/result mismatch")
    for name, result in data_results.items():
        left, right = pure["baseline3004"]["tables"].get(name), pure["current"]["tables"].get(name)
        left_sha, right_sha = [hashlib.sha256(canonical(value)).hexdigest() for value in (left, right)]
        build.need(result["baseline_value_sha256"] == left_sha and result["native_dev_value_sha256"] == right_sha
                   and result["equal"] is (left_sha == right_sha), "Protected pure-data result mismatch")
        if not result["equal"]:
            build.need("scripts/vscripts/" + name + ".lua" in exceptions, "Unreviewed pure-data difference")
    for name, row in closure.items():
        build.need(build.pack.runtime.safe_relative(name) and row["classification"] in ("equal", "fix2", "protected_semantic", "known_exception"), "Unknown equivalence class/path")
        inputs.source(base / name, row["baseline"]); inputs.source(dev / name, row["native_dev"])
        if row["classification"] == "equal":
            build.need(row["equal_bytes"] is True and row["baseline"] == row["native_dev"], "Plain source not byte-identical")
        elif row["classification"] == "known_exception":
            item = exceptions.get(name, {})
            build.need(item.get("does_not_claim_whole_module_equal") is True and item.get("actual_difference")
                       and item.get("n1_scope_condition"), "Scoped exception lacks precise reviewed condition")
        elif row["classification"] == "protected_semantic":
            module = name.removeprefix("scripts/vscripts/").removesuffix(".lua")
            if module in data_results:
                build.need(data_results[module]["equal"] is True and data_results[module]["difference_count"] == 0,
                           "Protected data failed deep equality")
            else:
                provenance = row.get("protection_provenance", {})
                original, _ = inputs.reference({"path": provenance.get("report_path"), "sha256": provenance.get("report_sha256")}, origin)
                entries = [item for item in original["files"] if item["path"] == name]
                build.need(len(entries) == 1 and original["semantic_verification"]["status"] == "PASS"
                           and entries[0]["before"]["sha256"] == provenance["source_before_sha256"] == row["native_dev"]["sha256"]
                           and entries[0]["after"]["sha256"] == provenance["protected_after_sha256"] == row["baseline"]["sha256"],
                           "Original protected business semantic proof mismatch")
        if name in rows and row["classification"] != "fix2" and name != build.CATALOG:
            choices = [pin["sha256"] for pin in (row["baseline"], row["native_dev"]) if pin]
            build.need(rows[name]["sha256"] in choices, "Candidate outside reviewed combat inputs")
    fixes = {row["path"]: row for row in proof.get("fix2", [])}
    build.need(set(fixes) == FIX2, "Equivalence fix scope mismatch")
    for name, row in fixes.items():
        build.need(row["matches_frozen"] is True and row["patchfrozen_sha256"] == row["native_dev_sha256"] == closure[name]["native_dev"]["sha256"], "Frozen wall fix drift")
        expected = (build.VIEW / name).read_bytes().replace(b"\r\n", b"\n")
        build.need(expected == (dev / name).read_bytes().replace(b"\r\n", b"\n"), "Candidate plain fix differs beyond line endings")
    for item in proof.get("function_projection", []):
        name = item["module"]
        left, right = [function_segments((root / name).read_text("utf-8-sig"))[item["function"]] for root in (base, dev)]
        build.need(item["equal"] is True and left == right
                   and hashlib.sha256(left.encode()).hexdigest() == item["baseline_lf_source_sha256"] == item["native_dev_lf_source_sha256"], "Spawn/completion function projection changed")
    build.need(proof.get("function_projection"), "Spawn/completion function evidence required")
    n1 = proof["n1_input_projection"]
    fields, _ = inputs.reference({"path": n1["field_data_path"], "sha256": n1["field_data_sha256"]}, origin)
    left_sha, right_sha = [hashlib.sha256(canonical(fields[name])).hexdigest() for name in ("baseline3004", "native_dev")]
    build.need(n1["equal"] is True and left_sha == right_sha == n1["baseline_sha256"] == n1["native_dev_sha256"], "N1 gameplay input projection differs")
    kv, _ = inputs.reference({"path": n1["kv_path"], "sha256": n1["kv_sha256"]}, origin)
    build.need({unit["unit_name"] for unit in kv["units"]} == {"building_wall", "npc_survival_wave_named_humanoid_white_melee"}, "Tested NPC projection incomplete")
    for unit in kv["units"]:
        build.need(unit.get("equal") is True and hashlib.sha256(unit["source"].encode()).hexdigest() == unit["lf_source_sha256"], "NPC projection hash mismatch")
    build.need(set(kv["include_graph"]) <= set(closure), "NPC include graph missing from source closure")


def acceptance(package, native_path, wall_path, manifest):
    native, wall = [build.load(path) for path in (native_path, wall_path)]
    build.need(native.get("status") == "PASS_NATIVE_SIGNED_PRODUCTION_STARTUP_ONLY"
               and native.get("content_sha256") == package["content_sha256"]
               and native.get("cheats") is False
               and native.get("signed_resources_verified") == package["files"], "Same signed production startup proof required")
    build.need(wall.get("schema") == 1 and wall.get("scope") == SCOPE
               and wall.get("candidate_content_sha256") == package["content_sha256"]
               and wall.get("online_multiplayer_acceptance") is False and "content_sha256" not in wall,
               "Explicit cross-run offline combat-equivalence schema required; do not claim same dev full content")
    inputs = ProofInputs()
    raw, _ = inputs.reference(wall["raw_acceptance"], wall_path)
    timeline, _ = inputs.reference(wall["raw_timeline"], wall_path, decode=False)
    validate_behavior(raw, timeline)
    loaded, loaded_path = inputs.reference(wall["loaded_proof"], wall_path)
    validate_loaded(loaded, loaded_path, inputs, manifest, package)
    equivalent, equivalent_path = inputs.reference(wall["equivalence_proof"], wall_path)
    validate_equivalence(equivalent, equivalent_path, inputs, manifest)
    # A new replay may accompany the new loaded-source proof. Its VM identity
    # is checked separately; the older four-mode report keeps its original PID.
    if "fresh_replay" in wall:
        replay, _ = inputs.reference(wall["fresh_replay"], wall_path)
        bound = replay.get("loaded_proof", {})
        build.need(replay.get("pid") == loaded["pid"] and replay.get("world_entindex") == loaded["world_entindex"]
                   and replay.get("match_session_id") == loaded["match_session_id"]
                   and bound.get("proof_id") == loaded["proof_id"] and bound.get("same_world") is True,
                   "Fresh replay/loaded VM identity mismatch")
    inputs.unchanged()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report-sha256", required=True)
    parser.add_argument("--native-proof", type=Path, required=True)
    parser.add_argument("--wall-proof", type=Path, required=True)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    package, manifest, _ = build.validated_package(args.report_sha256, full=True)
    acceptance(package, args.native_proof, args.wall_proof, manifest)
    listing = build.load(build.BASE_LISTING)
    build.need(listing["workshop_id"] == build.ITEM and listing["visibility_requested"] == "unlisted", "Original Unlisted listing required")
    listing.update(runtime_content_sha256=package["content_sha256"], release_sequence=build.SEQUENCE,
                   release_revision=build.REVISION, vpk_sha256=package["vpk_sha256"], runtime_files=package["files"],
                   package_bytes=sum(row["bytes"] for row in package["package_files"]), package_files=package["package_files"])
    listing["cover"] = str((build.BASE_LISTING.parent / listing["cover"]).resolve())
    target = build.REPORT / "listing.json"
    raw = json.dumps(listing, ensure_ascii=False, indent=2) + "\n"
    if target.exists(): build.need(target.read_text("utf8") == raw, "Reviewed listing changed")
    else: build.inc.write_new(target, raw.encode("utf8"))
    argv = ["--candidate", str(build.VIEW), "--vpk", str(build.OUTPUT / (build.ITEM + ".vpk")),
            "--listing", str(target), "--build-report", str(build.REPORT / "package.json"), "--state-file", str(build.JOURNAL)]
    if args.apply: argv += ["--apply", "--update-existing"]
    old = sys.argv
    try:
        sys.argv = [str(Path(__file__)), *argv]
        with build.inc.trusted_source(build.TRUSTED), build.scene_maps(): return publisher.main()
    finally:
        sys.argv = old


if __name__ == "__main__":
    try: raise SystemExit(main())
    except Exception as error:
        print(json.dumps({"status": "PUBLISH_REFUSED_PRESERVE_JOURNAL", "error": str(error)}))
        raise SystemExit(1)
