"""Prepare a reviewed daily-cap overlay from the pinned online release.

This program is local-only. It never opens SSH, connects to a database, invokes
Git, changes a live bundle pointer, or builds configuration from the worktree.
Only the explicitly listed task inputs are added to the immutable online data.
"""
from __future__ import annotations

import argparse
import ast
import copy
import csv
import difflib
import hashlib
import json
import math
from pathlib import Path
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
PACKAGE = ROOT / "tmp/archive_caps_20261020"
PARENT = "0328f6ba83a13d309b8b6df84524814cf10ed5287c019282e35e286161d27bac"
EXPECTED_RELEASE = "/opt/goufayu/releases/20261020-lottery-catalog-v1"
EXPECTED_MANIFEST = "227130b379d707b53c3d2ecc8fd95eed42c04d4f19a3e4d7b7bf0b577703284d"
CSV_NAMES = ("archive_achievements", "archive_daily_limits")
REDUCER_NAMES = ("archive_settlement", "archive_challenge_rewards", "archive_social_rewards",
                 "archive_building_rewards", "archive_online_rewards", "archive_daily_limits",
                 "archive_clear_progress")
NEW_CLEAR_KINDS = {"standard_clear", "rich_clear", "cold_clear", "scourge_clear", "mode_clear"}
CAP_UPGRADES = {"clear", "boss_kill", "endless", "endless_reconcile", "challenge", *NEW_CLEAR_KINDS}
SERVICE_METHODS = ("validate", "command", "finish_prepared")
MIGRATIONS = ("202610170001_rich_match_mode.sql", "202610200002_archive_match_modes.sql",
              "202610200003_archive_daily_limits.sql")


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def text(path):
    return Path(path).read_text(encoding="utf-8-sig")


def exact_write(path, raw):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        assert path.read_bytes() == raw, "immutable_candidate_changed:" + str(path)
    else:
        path.write_bytes(raw)


def read_csv(path):
    lines = text(path).splitlines()
    fields = next(csv.reader([lines[0]]))
    kinds = next(line[7:].split(",") for line in lines if line.startswith("#types:"))
    assert len(fields) == len(kinds), "csv_schema_mismatch"
    rows, seen = [], set()
    for raw in csv.DictReader(line for line in lines if not line.startswith("#")):
        row = {}
        for field, kind in zip(fields, kinds):
            value = (raw[field] or "").strip()
            if not value:
                continue
            if kind == "number":
                value = float(value)
                assert math.isfinite(value), "csv_nonfinite"
                if value.is_integer():
                    value = int(value)
            elif kind == "boolean":
                assert value.lower() in {"1", "0", "true", "false", "yes", "no", "on", "off"}
                value = value.lower() in {"1", "true", "yes", "on"}
            elif kind == "list":
                value = [part.strip() for part in value.split("|" if "|" in value else ",") if part.strip()]
            row[field] = value
        assert row[fields[0]] not in seen, "csv_duplicate"
        seen.add(row[fields[0]])
        rows.append(row)
    return {"key": fields[0], "rows": rows}


def node_text(source, node):
    start = min([node.lineno, *(decorator.lineno for decorator in getattr(node, "decorator_list", []))])
    return "".join(source.splitlines(keepends=True)[start - 1:node.end_lineno])


def class_methods(source):
    tree = ast.parse(source)
    cls = next(node for node in tree.body if isinstance(node, ast.ClassDef) and node.name == "ArchiveService")
    return {node.name: node for node in cls.body if isinstance(node, ast.FunctionDef)}


def module_assignment(source, name):
    return next(node for node in ast.parse(source).body if isinstance(node, ast.Assign)
                and any(isinstance(target, ast.Name) and target.id == name for target in node.targets))


def replace_nodes(source, replacements):
    lines = source.splitlines(keepends=True)
    for node, replacement in sorted(replacements, key=lambda pair: pair[0].lineno, reverse=True):
        lines[node.lineno - 1:node.end_lineno] = [replacement.rstrip("\n") + "\n"]
    return "".join(lines)


def prepare_service(parent, task):
    """Add identity/receipt/quota glue while retaining every online-only API."""
    old_methods, new_methods = class_methods(parent), class_methods(task)
    parent_fields_node, task_fields_node = module_assignment(parent, "FIELDS"), module_assignment(task, "FIELDS")
    old_fields, task_fields = ast.literal_eval(parent_fields_node.value), ast.literal_eval(task_fields_node.value)
    assert set(task_fields) - set(old_fields) <= NEW_CLEAR_KINDS, "unexpected_wire_command"
    assert all(task_fields[key] == values for key, values in old_fields.items()), "existing_wire_fields_changed"
    fields = node_text(parent, parent_fields_node).rstrip()
    assert fields.endswith("}")
    additions = "".join("    " + repr(key) + ": {" + ", ".join(repr(value) for value in sorted(task_fields[key])) + "},\n"
                        for key in sorted(set(task_fields) - set(old_fields)))
    fields = fields[:-1] + additions + "}\n"
    replacements = [(parent_fields_node, fields)]
    for method in SERVICE_METHODS:
        replacement = node_text(task, new_methods[method])
        if method == "finish_prepared":
            replacement = replacement.replace("            shared_roll = self.shared_challenge_roll(self.bundle)\n", "")
            first = '                if command["kind"] == "challenge" or not upgraded:\n'
            last = '                    reducer=ArchiveService(self.app,recorded_bundle,self.lua)\n'
            start, end = replacement.index(first), replacement.index(last) + len(last)
            replacement = replacement[:start] + (
                '                if not upgraded:\n'
                '                    reducer=ArchiveService(self.app,Bundle(self.bundle.directory.parent/version),self.lua)\n'
            ) + replacement[end:]
            first = '            elif version == self.bundle.hash or command["kind"] != "challenge":\n'
            last = '                result=reducer.settle(profile,command,prepared["has_pass"],shared_roll)\n'
            start, end = replacement.index(first), replacement.index(last) + len(last)
            replacement = replacement[:start] + (
                '            else:\n'
                '                result=reducer.settle(profile,command,prepared["has_pass"])\n'
            ) + replacement[end:]
            assert "shared_roll" not in replacement, "unexpected_seed_policy"
        replacements.append((old_methods[method], replacement))
    old_install = next(node for node in ast.parse(parent).body if isinstance(node, ast.FunctionDef) and node.name == "install")
    new_install = next(node for node in ast.parse(task).body if isinstance(node, ast.FunctionDef) and node.name == "install")
    installation = node_text(task, new_install)
    assert 'application._archive_modes_active = True' in installation, "pending_mode_scope_flag_missing"
    replacements.append((old_install, installation))
    result = replace_nodes(parent, replacements)
    compile(result, "candidate/backend/archive_backend/service.py", "exec")
    actual_methods = class_methods(result)
    preserved = sorted(set(old_methods) - set(SERVICE_METHODS))
    assert all(node_text(parent, old_methods[key]) == node_text(result, actual_methods[key]) for key in preserved), "online_endpoint_changed"
    assert node_text(parent, old_methods["settle"]) == node_text(result, actual_methods["settle"]), "rng_policy_changed"
    assert "def lottery_catalog(" in result and "def shared_challenge_roll(" not in result
    return result, {"replaced_methods": list(SERVICE_METHODS), "preserved_methods": preserved,
                    "preserved_rng": "original online HMAC(account_id + ':' + command.id)",
                    "new_wire_commands": sorted(NEW_CLEAR_KINDS)}


def prepare_compatibility(parent):
    node = module_assignment(parent, "UPGRADE_COMMANDS")
    values = set(ast.literal_eval(node.value.args[0]))
    updated = values | NEW_CLEAR_KINDS
    replacement = "UPGRADE_COMMANDS = frozenset({\n" + "".join("    " + repr(value) + ",\n" for value in sorted(updated)) + "})\n"
    result = replace_nodes(parent, [(node, replacement)])
    compile(result, "candidate/config_compatibility.py", "exec")
    return result


def lottery_proof(parent, candidate):
    configs = sorted(key for key in parent["configs"] if key.startswith("lottery_"))
    sources = sorted(key for key in parent["sources"] if "lottery" in key or key == "config/content_id_aliases.lua")
    assert configs and sources
    assert configs == sorted(key for key in candidate["configs"] if key.startswith("lottery_"))
    assert sources == sorted(key for key in candidate["sources"] if "lottery" in key or key == "config/content_id_aliases.lua")
    locked_configs = configs + ["player_gameplay_stats", "map_level_effect_rules", "archive_starjoy_levels"]
    locked_sources = sources + ["worker.lua", "core/json_encoder.lua", "core/json_decoder.lua",
                                "systems/archive_calendar.lua", "systems/archive_starjoy_rewards.lua"]
    assert all(parent["configs"][key] == candidate["configs"][key] for key in locked_configs), "lottery_configuration_changed"
    assert all(parent["sources"][key] == candidate["sources"][key] for key in locked_sources), "lottery_reducer_changed"
    return {"identical": True, "configs": {key: sha(canonical(parent["configs"][key])) for key in locked_configs},
            "sources": {key: sha(parent["sources"][key].encode()) for key in locked_sources}}


def prepare_unique(parent_source, parent_data, candidate_data, digest, baseline):
    tree = ast.parse(parent_source)
    old_node = module_assignment(parent_source, "IDENTICAL_LOTTERY_UPDATE")
    old_pair = ast.literal_eval(old_node.value)
    assert old_pair[0] == PARENT
    old_pairs = {old_pair}
    new_pairs = old_pairs | {(digest, PARENT)} | {(digest, recorded) for current, recorded in old_pairs if current == PARENT}
    proofs = {}
    for current, recorded in sorted(new_pairs - old_pairs):
        data = parent_data if recorded == PARENT else json.loads((baseline / "addon/server/bundles" / recorded / "bundle.json").read_bytes())
        proofs[recorded] = lottery_proof(data, candidate_data)
    anchor = node_text(parent_source, old_node)
    addition = "\n# Reviewed unchanged lottery rules; retain every previously trusted pair.\nIDENTICAL_LOTTERY_UPDATES = frozenset({\n" + \
        "    IDENTICAL_LOTTERY_UPDATE,\n" + "".join("    " + repr(pair) + ",\n" for pair in sorted(new_pairs - old_pairs)) + "})\n"
    assert parent_source.count(anchor) == 1
    result = parent_source.replace(anchor, anchor + addition, 1)
    old = "(current_hash, recorded_hash) == IDENTICAL_LOTTERY_UPDATE:"
    assert result.count(old) == 1
    result = result.replace(old, "(current_hash, recorded_hash) in IDENTICAL_LOTTERY_UPDATES:", 1)
    compile(result, "candidate/unique_points.py", "exec")
    return result, {"old_pairs": sorted(old_pairs), "pairs": sorted(new_pairs), "directed_pair_proofs": proofs}


def verify_baseline(baseline):
    source_manifest = json.loads((baseline / "online_snapshot_manifest.json").read_bytes())
    bundle_manifest = json.loads((baseline / "online_bundle_snapshot_manifest.json").read_bytes())
    assert source_manifest["current"] == bundle_manifest["current"] == EXPECTED_RELEASE
    assert source_manifest["bundle_hash"] == bundle_manifest["bundle_hash"] == PARENT
    assert sha((baseline / "release_manifest.json").read_bytes()) == EXPECTED_MANIFEST
    inventory = {}
    for record in source_manifest["files"] + bundle_manifest["files"]:
        relative = record["path"]
        assert not Path(relative).is_absolute() and ".." not in Path(relative).parts
        assert sha((baseline / relative).read_bytes()) == record["sha256"], "baseline_changed:" + relative
        inventory[relative] = record["sha256"]
    current = baseline / "addon/server/bundles" / PARENT
    assert sha((current / "bundle.json").read_bytes()) == PARENT
    return json.loads((current / "bundle.json").read_bytes()), inventory


def prepare_dbtool(before, after):
    def parts(source):
        result = {}
        for node in ast.parse(source).body:
            if isinstance(node, (ast.FunctionDef, ast.ClassDef)):
                result[node.name] = node_text(source, node)
            elif isinstance(node, ast.Assign):
                result["=" + ",".join(ast.unparse(target) for target in node.targets)] = node_text(source, node)
        return result
    old, new = parts(before), parts(after)
    changed = {key for key in old.keys() | new.keys() if old.get(key) != new.get(key)}
    assert changed <= {"=TABLES", "=FUNCTIONS", "expected_prefix_objects"}, "unrelated_dbtool_changes:" + repr(changed)
    return after, sorted(changed)


def build(args):
    baseline, task, stage = args.baseline.resolve(), args.task.resolve(), args.output.resolve()
    assert stage.is_relative_to(ROOT / "tmp"), "candidate_must_stay_under_workspace_tmp"
    parent, baseline_hashes = verify_baseline(baseline)
    data = copy.deepcopy(parent)
    payload, inputs = {}, {}
    def task_bytes(relative, fallback=None):
        source = task / relative
        if not source.is_file() and fallback is not None:
            source = fallback
        raw = source.read_bytes()
        inputs[str(source.relative_to(ROOT))] = sha(raw)
        return raw
    for name in CSV_NAMES:
        relative = "data/csv/存档系统/" + name + ".csv"
        raw = task_bytes(relative)
        data["configs"][name] = read_csv(task / relative)
        data["csv_hashes"][relative] = sha(raw.replace(b"\r\n", b"\n"))
        payload["addon/" + relative] = raw
    for name in REDUCER_NAMES:
        relative = "scripts/vscripts/systems/" + name + ".lua"
        data["sources"]["systems/" + name + ".lua"] = task_bytes(relative).decode("utf-8-sig").replace("\r\n", "\n")
    for name in ("difficulty_config", "recorded_mode_balance"):
        relative = "scripts/vscripts/config/" + name + ".lua"
        frozen = PACKAGE / "frontend_head_fixture" / relative
        raw = frozen.read_bytes()
        assert b"mode_progression" not in raw and b"temporary_source_difficulty_id" not in raw, "unapproved_mode_chain"
        inputs[str(frozen.relative_to(ROOT))] = sha(raw)
        data["sources"]["config/" + name + ".lua"] = raw.decode("utf-8-sig").replace("\r\n", "\n")
    service_path = args.service_after.resolve()
    service_after = text(service_path)
    inputs[str(service_path.relative_to(ROOT))] = sha(service_path.read_bytes())
    service, service_proof = prepare_service(text(baseline / "backend/archive_backend/service.py"), service_after)
    payload["backend/archive_backend/service.py"] = service.encode()
    # The online transport predates persisted rich/cold/scourge session identity.
    # Expand this one closed enum without importing a different fishing service.
    postgres_path = "backend/fishing_api/postgres.py"
    postgres_before = (baseline / postgres_path).read_bytes()
    old_enum = b'valid = value in ("pure", "standard")'
    new_enum = b'valid = value in ("pure", "standard", "rich", "cold", "scourge")'
    assert postgres_before.count(old_enum) == 1, "unexpected_online_match_mode_converter"
    postgres_after = postgres_before.replace(old_enum, new_enum, 1)
    assert postgres_after.replace(new_enum, old_enum, 1) == postgres_before
    compile(postgres_after, postgres_path, "exec")
    payload[postgres_path] = postgres_after
    for name in ("match_modes", "daily_limits", "clear_receipts"):
        relative = "server/archive_backend/" + name + ".py"
        raw = task_bytes(relative).decode("utf-8-sig").replace("\r\n", "\n").encode()
        compile(raw, relative, "exec")
        if name == "match_modes":
            assert b'if mode == "rich" and not progression(raw)["standard_clear_counts"].get("n10"):' in raw, "rich_gate_changed"
            assert b'not progression(raw)[PARENT_MODES[mode]' not in raw, "new_cold_scourge_gate"
        payload["backend/archive_backend/" + name + ".py"] = raw
    payload["backend/archive_backend/config_compatibility.py"] = prepare_compatibility(text(baseline / "backend/archive_backend/config_compatibility.py")).encode()
    commands = sorted(set(ast.literal_eval(module_assignment(service, "FIELDS").value)) | {"lottery_snapshot"})
    compatibility = data.setdefault("compatible_config_hashes", {})
    assert PARENT not in compatibility
    compatibility[PARENT] = {"commands": commands, "upgrade_commands": sorted(CAP_UPGRADES & set(commands))}
    for digest, rule in compatibility.items():
        rule["upgrade_commands"] = sorted(set(rule["upgrade_commands"]) | (CAP_UPGRADES & set(rule["commands"])))
    for digest, original in parent.get("compatible_config_hashes", {}).items():
        assert compatibility[digest]["commands"] == original["commands"]
        assert set(compatibility[digest]["upgrade_commands"]) - set(original["upgrade_commands"]) <= CAP_UPGRADES
    changed_configs = {key for key in data["configs"].keys() | parent["configs"].keys() if data["configs"].get(key) != parent["configs"].get(key)}
    changed_sources = {key for key in data["sources"].keys() | parent["sources"].keys() if data["sources"].get(key) != parent["sources"].get(key)}
    allowed_sources = {"systems/" + name + ".lua" for name in REDUCER_NAMES} | {"config/difficulty_config.lua", "config/recorded_mode_balance.lua"}
    assert changed_configs == set(CSV_NAMES), "configuration_scope_changed"
    assert changed_sources <= allowed_sources, "source_scope_changed"
    assert all(data["configs"][key] == value for key, value in parent["configs"].items() if key not in CSV_NAMES)
    assert all(data["sources"][key] == value for key, value in parent["sources"].items() if key not in allowed_sources)
    packed = canonical(data)
    digest = sha(packed)
    lottery = lottery_proof(parent, data)
    lottery.update(parent_bundle=PARENT, candidate_bundle=digest)
    helper, pair_proof = prepare_unique(text(baseline / "backend/archive_backend/unique_points.py"), parent, data, digest, baseline)
    lottery.update(pair_proof)
    payload["backend/archive_backend/unique_points.py"] = helper.encode()
    prefix = "addon/server/bundles/" + digest + "/"
    payload[prefix + "bundle.json"] = packed
    for name, value in data["sources"].items():
        payload[prefix + name] = value.encode()
    payload["addon/server/bundles/current.json"] = canonical({"hash": digest, "protocol": 1}) + b"\n"
    game_config = ('-- Reviewed archive daily-cap and mode-clear bundle.\nreturn { protocol = 1, hash = "' + digest + '" }\n').encode()
    payload["game-config/archive_http_bundle.lua"] = game_config
    payload["addon/scripts/vscripts/config/generated/archive_http_bundle.lua"] = game_config
    configuration = canonical({"configs": data["configs"], "compatible_config_hashes": compatibility})
    dbtool, dbtool_proof = prepare_dbtool(text(baseline / "database/dbtool.py"), task_bytes("server/aliyun/database/dbtool.py").decode("utf-8-sig").replace("\r\n", "\n"))
    payload["database/dbtool.py"] = dbtool.encode()
    database_manifest = json.loads((baseline / "database/migration_manifest.json").read_bytes())
    old_entries = copy.deepcopy(database_manifest["entries"])
    schema_path = PACKAGE / "online_schema.json"
    schema_raw = schema_path.read_bytes()
    schema = json.loads(schema_raw)
    ledger = schema["migration_ledger"]
    assert len(ledger) == 26 and schema["read_only"] is True and schema["player_rows_read"] == 0
    recorded = {row["id"]: row["sha256"] for row in ledger}
    assert all(recorded.get(entry["id"]) == entry["sha256"] for entry in old_entries), "deployed_ledger_changed"
    migrations = []
    for name in MIGRATIONS:
        relative = "server/aliyun/database/target/" + name
        raw = task_bytes(relative, ROOT / relative).replace(b"\r\n", b"\n")
        identifier, destination = "target/" + name, "database/migrations/target/" + name
        assert identifier not in recorded
        entry = {"id": identifier, "path": destination.removeprefix("database/"), "group": "target", "sha256": sha(raw), "bytes": len(raw)}
        database_manifest["entries"].append(entry)
        migrations.append({"id": identifier, "path": destination, "sha256": sha(raw), "bytes": len(raw)})
        payload[destination] = raw
    assert database_manifest["entries"][:len(old_entries)] == old_entries
    payload["database/migration_manifest.json"] = json.dumps(database_manifest, ensure_ascii=False, indent=2).encode() + b"\n"
    old_release_manifest = json.loads((baseline / "release_manifest.json").read_bytes())
    release_manifest = copy.deepcopy(old_release_manifest)
    file_hashes = {name: sha(raw) for name, raw in sorted(payload.items())}
    release_manifest["files"].update(file_hashes)
    release_manifest.update(release=args.release_id, baseline_release=Path(EXPECTED_RELEASE).name,
        previous_release=Path(EXPECTED_RELEASE).name, archive_bundle=digest,
        description="Reviewed daily acquisition caps and independently scoped mode-clear rewards; inherited online lottery/catalog preserved.",
        game_configuration_changed=True, includes_secrets=False,
        changed_backend_files=sorted(name for name in payload if name.startswith("backend/")),
        changed_configuration=list(CSV_NAMES), archive_caps_parent=PARENT)
    manifest_raw = json.dumps(release_manifest, ensure_ascii=False, sort_keys=True, indent=2).encode() + b"\n"
    for relative, raw in payload.items():
        assert not Path(relative).is_absolute() and ".." not in Path(relative).parts
        exact_write(stage / "overlay" / relative, raw)
    exact_write(stage / "release_manifest.json", manifest_raw)
    exact_write(stage / "configuration.json", configuration)
    exact_write(stage / "schema_before.json", schema_raw)
    exact_write(stage / "baseline_hashes.json", canonical(baseline_hashes) + b"\n")
    exact_write(stage / "input_hashes.json", canonical(inputs) + b"\n")
    source_patch = []
    for relative in sorted(name for name in payload if name.startswith("backend/") or name == "database/dbtool.py"):
        before_path = baseline / relative
        before = text(before_path) if before_path.is_file() else ""
        after = payload[relative].decode()
        source_patch.extend(difflib.unified_diff(before.splitlines(keepends=True), after.splitlines(keepends=True),
            fromfile="a/" + relative if before_path.is_file() else "/dev/null", tofile="b/" + relative))
    exact_write(stage / "backend.patch", "".join(source_patch).encode())
    plan = {"format": 1, "kind": "archive_daily_caps_mode_clear", "status": "LOCAL_CANDIDATE_NOT_DEPLOYED",
        "expected": {"release": EXPECTED_RELEASE, "release_manifest_sha256": EXPECTED_MANIFEST, "bundle_hash": PARENT,
            "ledger": ledger, "schema_path": "schema_before.json", "schema_sha256": sha(schema_raw),
            "archive_sync_sha256": schema["functions"]["public.archive_sync_config(text,jsonb)"]["sha256"]},
        "candidate": {"release_id": args.release_id, "release": "/opt/goufayu/releases/" + args.release_id,
            "bundle_hash": digest, "overlay": file_hashes, "migrations": migrations,
            "release_manifest_sha256": sha(manifest_raw), "configuration_sha256": sha(configuration)},
        "proof": {"lottery": lottery, "service": service_proof, "dbtool_changed_nodes": dbtool_proof,
            "postgres_match_mode": {"parent_sha256": sha(postgres_before), "candidate_sha256": sha(postgres_after),
                "only_change": "match_mode closed enum expanded from pure/standard to pure/standard/rich/cold/scourge"},
            "unchanged": {"non_task_configs": True, "non_task_sources": True, "online_only_endpoints": True,
                "parent_and_ancestor_bundles": True, "all_previous_compatibility_commands": True,
                "parent_seed_policy": True, "payment_service": True},
            "changed_configs": sorted(changed_configs), "changed_sources": sorted(changed_sources),
            "parent_config_count": len(parent["configs"]), "parent_source_count": len(parent["sources"]),
            "preserved_compatibility_ancestors": len(parent.get("compatible_config_hashes", {})),
            "actual_reward_maximum": {"pure": 10, "standard": 10, "rich": 10, "cold": 4, "scourge": 2},
            "archive_visible_maximum": 10,
            "stale_parent_game_config_ignored": "288f724bcfd79880c4fbd7d4ac77040a8636e2f8f3ef96836632001340d3b2a7"},
        "configuration_path": "configuration.json", "baseline_hashes_path": "baseline_hashes.json",
        "input_hashes_path": "input_hashes.json", "validation_report_path": "validation_report.json",
        "remote_writes": 0, "database_writes": 0, "payment_changes": False, "production_deployed": False}
    exact_write(stage / "plan.json", canonical(plan) + b"\n")
    exact_write(stage / "overlay_manifest.json", canonical({"files": file_hashes}) + b"\n")
    exact_write(stage / "filelist.txt", ("\n".join(sorted(file_hashes)) + "\n").encode())
    return plan


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", type=Path, default=PACKAGE / "online_baseline")
    parser.add_argument("--task", type=Path, default=PACKAGE / "task")
    parser.add_argument("--output", type=Path, default=PACKAGE / "release_candidate/stage")
    parser.add_argument("--service-after", type=Path, default=ROOT / "server/archive_backend/service.py")
    parser.add_argument("--release-id", default="20261020-archive-caps-v1")
    args = parser.parse_args()
    plan = build(args)
    print(json.dumps({"status": plan["status"], "stage": str(args.output), "bundle": plan["candidate"]["bundle_hash"],
                      "overlay_files": len(plan["candidate"]["overlay"]), "migrations": len(plan["candidate"]["migrations"])}, ensure_ascii=False))


if __name__ == "__main__":
    main()
