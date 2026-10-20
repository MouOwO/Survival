"""Build isolated cold/scourge combat tables through the standard CSV generator."""
from __future__ import annotations
import argparse
import csv
import importlib.util
import json
import math
import tempfile
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TABLES = (
    "data/csv/怪物与波次系统/recorded_mode_wave_definitions.csv",
    "data/csv/挑战与奖励系统/recorded_mode_challenge_combat_profiles.csv",
    "data/csv/怪物与波次系统/recorded_mode_wave_stat_variants.csv",
)
DIFFICULTIES = {"cold": ("N1", "N2", "N3", "N4"), "scourge": ("N1", "N2")}
SOURCE = "data/balance/mode_monsters_20261020.json"
FIELDS = ("health", "attack", "war3_armor")

def read_rows(file):
    with Path(file).open(encoding="utf-8-sig", newline="") as stream:
        reader = csv.DictReader(stream)
        assert len(reader.fieldnames) == len(set(reader.fieldnames)), f"Duplicate CSV headers: {file}"
        result = []
        for row in reader:
            assert None not in row and None not in row.values(), f"Malformed CSV row: {file}"
            if not next(iter(row.values())).startswith("#"): result.append(row)
        return result

def active(row): return row.get("enabled", "").lower() in ("1", "true")

def validate_tables(root=ROOT):
    root = Path(root)
    tables = [read_rows(root / relative) for relative in TABLES]
    observations = {r["record_id"]: r for r in json.loads((root / SOURCE).read_text(encoding="utf-8"))["observations"]}
    for rows in tables:
        seen = set()
        for row in rows:
            identity = next(iter(row.values()))
            assert identity and identity not in seen, f"Duplicate identity: {identity}"
            seen.add(identity)
            assert row["mode_id"] in DIFFICULTIES
            assert row["difficulty_id"] in DIFFICULTIES[row["mode_id"]]
            assert row["enabled"].lower() in ("0", "1", "true", "false")
            assert row["data_status"] in ("video_observed", "mixed", "estimated")
            origins = json.loads(row.get("field_sources") or row["rich_field_sources"])
            for field in FIELDS:
                number = float(row[field])
                assert math.isfinite(number) and (number >= 0 if field == "war3_armor" else number > 0), (identity, field)
                origin = origins[field]
                assert origin.get("method") and origin.get("explanation"), (identity, field)
                if origin["method"] == "video_panel":
                    observed = observations[origin["record_id"]]
                    assert observed["mode_id"] == row["mode_id"] and observed["difficulty_id"] == row["difficulty_id"]
                    assert number == observed["stats"][field], (identity, field, "changed observed value")
                else:
                    assert row["data_status"] != "video_observed", (identity, "estimate marked observed")
                    if "input_value" in origin and "factor" in origin:
                        additive = origin.get("additive", 0)
                        quantum = origin.get("rounding_quantum", 1)
                        expected = math.floor(((origin["input_value"] - additive) * origin["factor"] + additive) / quantum + .5) * quantum
                        assert number == expected, (identity, field, "estimate formula mismatch")
                for ref in origin.get("reference_record_ids", []): assert ref in observations, ref
    waves, members, variants = tables
    batches, groups = {}, defaultdict(list)
    template = {(r["difficulty_id"], int(r["wave_number"]), r["batch_id"]): r
                for r in read_rows(root / "data/csv/怪物与波次系统/rich_wave_definitions.csv")}
    for row in waves:
        if not active(row): continue
        key = row["mode_id"], row["difficulty_id"], int(row["wave_number"]), row["batch_id"]
        assert key not in batches, key
        batches[key] = row
        groups[key[:3]].append(row)
        source = template[key[1:]]
        for field in ("archetype_id", "member_role", "monster_count", "spawn_order", "attack_speed", "movement_type_override", "model_scale_multiplier"):
            assert row[field] == source[field], (key, "changed model/count/timing", field)
    expected_groups = {(mode, difficulty, number) for mode, difficulties in DIFFICULTIES.items()
                       for difficulty in difficulties for number in range(1, 26 if difficulty == "N1" else 31)}
    assert set(groups) == expected_groups, "Missing mode/difficulty/wave"
    for key, rows in groups.items():
        assert sum(int(r["monster_count"]) for r in rows) == 60, key
        assert len({r["spawn_order"] for r in rows}) == len(rows), key
    expected_members = {r["member_id"] for r in read_rows(root / "data/csv/挑战与奖励系统/rich_challenge_combat_profiles.csv") if r["difficulty_id"] == "N1"}
    member_groups = defaultdict(set)
    for row in members:
        if not active(row): continue
        key = row["mode_id"], row["difficulty_id"]
        assert row["member_id"] not in member_groups[key]
        member_groups[key].add(row["member_id"])
    assert set(member_groups) == {(m,d) for m, ds in DIFFICULTIES.items() for d in ds}
    assert all(ids == expected_members for ids in member_groups.values()), "Missing room/wilderness member"
    variant_groups = defaultdict(list)
    for row in variants:
        if not active(row): continue
        key = row["mode_id"], row["difficulty_id"], int(row["wave_number"]), row["batch_id"]
        assert key in batches, (key, "orphan variant")
        variant_groups[key].append(int(row["variant_index"]))
    for key, indices in variant_groups.items(): assert sorted(indices) == list(range(1, len(indices)+1)), key
    return tables

def build(root=ROOT, check=False):
    root = Path(root)
    validate_tables(root)
    spec = importlib.util.spec_from_file_location("recorded_standard_csv", root / "tools/build_configs.py")
    generator = importlib.util.module_from_spec(spec); spec.loader.exec_module(generator)
    outputs = {}
    with tempfile.TemporaryDirectory(prefix="recorded_modes_") as folder:
        for relative in TABLES:
            source = root / relative
            temporary = Path(folder) / (source.stem + ".lua")
            generator.build(source, temporary)
            outputs["scripts/vscripts/config/generated/"+temporary.name] = temporary.read_text(encoding="utf-8")
    registry = root / "scripts/vscripts/config/generated/index.lua"
    text = registry.read_text(encoding="utf-8")
    lines = text.splitlines()
    for relative in TABLES:
        name = Path(relative).stem
        entry = f'M["{name}"] = require("config/generated/{name}")'
        if entry not in lines:
            at = next((i for i,line in enumerate(lines) if line.startswith('M["') and line > entry), lines.index("return M")-1)
            lines.insert(at, entry)
    outputs["scripts/vscripts/config/generated/index.lua"] = "\n".join(lines)+"\n"
    for relative, rendered in outputs.items():
        target = root / relative
        if check: assert target.read_text(encoding="utf-8") == rendered, f"Stale generated table: {relative}"
        else: target.write_text(rendered, encoding="utf-8", newline="\n")
    return outputs

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__);parser.add_argument("--check", action="store_true")
    args = parser.parse_args();outputs = build(check=args.check)
    print(f"RECORDED_MODE_CSV_{'CHECK' if args.check else 'BUILD'}_PASS: {len(outputs)} outputs")
