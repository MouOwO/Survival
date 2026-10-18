"""Compatibility entry point for rich CSV configs and historical evidence audit.

CSV tables are the runtime authority. The archived JSON remains available to
generate() for evidence/provenance checks and the historical coverage ledger;
it never generates operational Lua modules.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import importlib.util
import io
import json
import math
import re
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = "data/balance/rich_n2_n3_monsters.json"
LEDGER = "docs/balance/rich_n2_n3_monster_coverage.csv"
FIELDS = ("health", "attack", "war3_armor")


def read_csv(root, relative):
    with (root / relative).open(encoding="utf-8-sig", newline="") as stream:
        return [row for row in csv.DictReader(stream)
                if row and not str(next(iter(row.values())) or "").startswith("#")]


def validate_profile(profile, observations):
    estimated = False
    recorded = 0
    for field in FIELDS:
        value = profile[field]
        assert isinstance(value, (int, float)) and math.isfinite(value), (field, value)
        assert value > 0 if field != "war3_armor" else value >= 0
        origin = profile["field_sources"][field]
        method = origin["method"]
        assert method and method != "unknown", "Every final field needs an explicit source"
        if method == "video_panel":
            ref = origin["record_id"]
            assert ref in observations, "Unknown observation: " + ref
            observed = observations[ref]["stats"][field]
            assert observed is not None and value == observed, "Observed value changed: " + ref + "/" + field
            recorded += 1
        else:
            estimated = True
            assert origin.get("explanation"), "Estimates need a reproducible explanation"
            if method == "nonwave_cross_difficulty_estimate":
                quantum = origin["rounding_quantum"]
                expected = math.floor(origin["input_value"] * origin["factor"] / quantum + 0.5) * quantum
                assert value == expected, "Estimate operands do not reproduce the final value"
                base = observations[origin["reference_record_ids"][0]]["stats"][field]
                assert base == origin["input_value"], "Estimate input differs from its observation"
        for ref in origin.get("reference_record_ids", []):
            assert ref in observations, "Unknown estimate reference: " + ref
    assert profile["estimated"] == estimated, "Estimated flag contradicts field provenance"
    assert profile["stats_source"] == ("video" if recorded == 3 else "mixed" if recorded else "estimated")


def generate(root=ROOT):
    """Validate archived observations and render only the historical ledger."""
    raw = (root / SOURCE).read_bytes()
    source = json.loads(raw)
    assert source["mode_id"] == "rich" and source["schema_version"] == 1
    observations = {row["record_id"]: row for row in source["observations"]}
    assert len(observations) == len(source["observations"]), "Duplicate observation identity"
    for row in observations.values():
        if row["difficulty_id"] == "N1":
            continue
        evidence = row["evidence"]
        path = (root / evidence["frame"]).resolve()
        assert path.is_relative_to(root.resolve()), "Evidence path escaped the repository"
        png = path.read_bytes()
        assert png[:8] == b"\x89PNG\r\n\x1a\n"
        assert list(struct.unpack_from(">II", png, 16)) == evidence["crop_size"]
        assert hashlib.sha256(png).hexdigest() == evidence["frame_sha256"], "Evidence changed: " + row["record_id"]
        maximum = str(row["health_display"]).split("/")[-1].strip()
        shown = re.fullmatch(r"([\d.]+)\s*([万亿]?)", maximum)
        assert shown, "Missing readable maximum-health text: " + row["record_id"]
        scaled = float(shown[1]) * {"万": 10000, "亿": 100000000, "": 1}[shown[2]]
        assert abs(scaled - row["stats"]["health"]) < 0.5, "Maximum-health unit conversion: " + row["record_id"]
    waves = read_csv(root, "data/csv/怪物与波次系统/wave_definitions.csv")
    encounters = read_csv(root, "data/csv/挑战与奖励系统/challenge_combat_profiles.csv")
    assert set(source["difficulties"]) == {"N2", "N3"}
    for difficulty_id in ("N2", "N3"):
        selected = source["difficulties"][difficulty_id]
        expected = {(int(row["wave_number"]), row["batch_id"]) for row in waves
                    if row["difficulty_id"] == difficulty_id and row.get("enabled") != "0"}
        actual = {(int(number), batch) for number, wave in selected["waves"].items() for batch in wave["batches"]}
        assert expected == actual, "Missing or unexpected wave batches: " + difficulty_id
        for row in waves:
            if row["difficulty_id"] != difficulty_id or row.get("enabled") == "0":
                continue
            profile = selected["waves"][row["wave_number"]]["batches"][row["batch_id"]]
            assert profile["archetype_id"] == row["archetype_id"], "Wave archetype mapping changed"
            assert profile["member_role"] == row["member_role"], "Wave role mapping changed"
        assert {int(number) for number in selected["waves"]} == set(range(1, 31))
        expected_members = {row["member_id"] for row in encounters
                            if row["difficulty_id"] == difficulty_id and row.get("enabled") != "0"}
        assert set(selected["encounters"]) == expected_members, "Incomplete encounter matrix: " + difficulty_id
        for wave in selected["waves"].values():
            for profile in wave["batches"].values():
                validate_profile(profile, observations)
                for variant in profile.get("variants", []):
                    validate_profile(variant, observations)
        for profile in selected["encounters"].values():
            validate_profile(profile, observations)
    all_profiles = {}
    for difficulty in source["difficulties"].values():
        profiles = [p for wave in difficulty["waves"].values() for p in wave["batches"].values()]
        profiles += [variant for p in list(profiles) for variant in p.get("variants", [])]
        profiles += list(difficulty["encounters"].values())
        for profile in profiles:
            all_profiles[profile["profile_id"]] = profile
    expected_observations = {key for key, row in observations.items() if row["difficulty_id"] in ("N2", "N3")}
    assert set(source["observation_coverage"]) == expected_observations
    for ref, targets in source["observation_coverage"].items():
        assert targets and all(target in all_profiles for target in targets), "Unrepresented observation: " + ref
        assert all(all(all_profiles[target][field] == observations[ref]["stats"][field]
                       for field in FIELDS) for target in targets), "Observation mapping mismatch: " + ref
    stream = io.StringIO(newline="")
    headers = ["difficulty_id", "category", "profile_id", "name", "wave_number", "batch_id", "member_role",
               "archetype_id", "health", "attack", "war3_armor", "attack_speed", "attack_range", "move_speed",
               "monster_count", "health_source", "attack_source", "armor_source", "source_record_ids", "policy", "source_file"]
    writer = csv.DictWriter(stream, fieldnames=headers, lineterminator="\n", extrasaction="ignore")
    writer.writeheader()
    for row in source["coverage"]:
        writer.writerow(row)
    return {LEDGER: stream.getvalue()}


def build(root=ROOT, check=False):
    if check:
        generate(root)
    spec = importlib.util.spec_from_file_location(
        "rich_csv_configs", root / "tools/build_rich_configs.py"
    )
    builder = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(builder)
    return builder.build(root=root, check=check)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    build(check=args.check)
    print("RICH_N2_N3_CSV_COMPAT_" + ("CHECK_" if args.check else "") + "PASS")


if __name__ == "__main__":
    main()
