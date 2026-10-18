"""Generate or check rich-mode configs from the three authoritative CSV tables."""
from __future__ import annotations

import argparse
import csv
import importlib.util
import math
import tempfile
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TABLES = (
    "data/csv/怪物与波次系统/rich_wave_definitions.csv",
    "data/csv/挑战与奖励系统/rich_challenge_combat_profiles.csv",
    "data/csv/怪物与波次系统/rich_wave_stat_variants.csv",
)
GENERATED = "scripts/vscripts/config/generated"


def configs(root: Path):
    spec = importlib.util.spec_from_file_location("rich_csv_standard_generator", root / "tools/build_configs.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def read_rows(path: Path):
    with path.open(encoding="utf-8-sig", newline="") as stream:
        return [row for row in csv.DictReader(stream)
                if row and not str(next(iter(row.values())) or "").startswith("#")]


def enabled(row):
    return row.get("enabled", "").strip().lower() in {"1", "true", "yes", "y", "on"}


def validate_tables(root: Path = ROOT):
    """Reject missing batches/members, duplicate identities and invalid stats."""
    root = Path(root)
    generator = configs(root)
    paths = [root / relative for relative in TABLES]
    generator.validate_strict_csv_shapes(paths)
    tables = [read_rows(path) for path in paths]
    for path, rows in zip(paths, tables):
        assert rows, f"Empty rich CSV: {path.name}"
        identities = set()
        for row in rows:
            key = next(iter(row.values()))
            assert key and key not in identities, f"Duplicate rich identity: {path.name}:{key}"
            identities.add(key)
            # An omitted generated field is enabled at runtime (nil ~= false).
            # Require an explicit CSV flag so validation and spawning agree.
            assert row.get("enabled", "").strip().lower() in {"0", "1", "false", "true", "no", "yes", "n", "y", "off", "on"}, \
                f"Rich enabled flag must be explicit: {key}"
            assert row["difficulty_id"] in {f"N{i}" for i in range(1, 11)}, "Invalid rich difficulty"
            for field in ("health", "attack", "war3_armor"):
                number = float(row[field])
                assert math.isfinite(number) and (number >= 0 if field == "war3_armor" else number > 0), \
                    f"Invalid rich stat: {key}:{field}"

    waves, encounters, variants = tables
    wave_groups = defaultdict(list)
    batch_keys = set()
    for row in waves:
        if not enabled(row):
            continue
        wave = int(row["wave_number"])
        key = (row["difficulty_id"], wave, row["batch_id"])
        assert key not in batch_keys, f"Duplicate rich batch: {key}"
        batch_keys.add(key)
        wave_groups[key[:2]].append(row)
        assert int(row["monster_count"]) > 0, f"Invalid rich count: {key}"
        for field in ("attack_speed", "model_scale_multiplier"):
            number = float(row[field])
            assert math.isfinite(number) and number > 0, f"Invalid rich {field}: {key}"
        for field in ("wait_seconds", "spawn_interval"):
            number = float(row[field])
            assert math.isfinite(number) and number >= 0, f"Invalid rich {field}: {key}"
    expected_waves = {(f"N{i}", wave) for i in range(1, 11)
                      for wave in range(1, 26 if i == 1 else 31)}
    assert set(wave_groups) == expected_waves, "Incomplete rich wave coverage"
    for key, rows in wave_groups.items():
        assert sum(int(row["monster_count"]) for row in rows) == 60, f"Rich count must total 60: {key}"
        orders = [int(row["spawn_order"]) for row in rows]
        assert len(orders) == len(set(orders)), f"Duplicate rich spawn order: {key}"

    members = defaultdict(set)
    for row in encounters:
        if not enabled(row):
            continue
        difficulty, member = row["difficulty_id"], row["member_id"]
        assert member and member not in members[difficulty], f"Duplicate rich encounter: {difficulty}:{member}"
        members[difficulty].add(member)
    assert set(members) == {f"N{i}" for i in range(1, 11)}, "Incomplete rich encounter difficulties"
    assert len(members["N1"]) == 30, "Rich encounter catalog must contain 30 members"
    for difficulty, member_ids in members.items():
        assert member_ids == members["N1"], f"Incomplete rich encounter coverage: {difficulty}"

    variant_groups = defaultdict(list)
    for row in variants:
        if not enabled(row):
            continue
        key = (row["difficulty_id"], int(row["wave_number"]), row["batch_id"])
        assert key in batch_keys, f"Orphan rich variant: {key}"
        variant_groups[key].append(int(row["variant_index"]))
    for key, indices in variant_groups.items():
        assert sorted(indices) == list(range(1, len(indices) + 1)), f"Invalid rich variant sequence: {key}"
    return tables


def build(root: Path = ROOT, check: bool = False) -> dict[str, str]:
    root = Path(root)
    validate_tables(root)
    generator = configs(root)
    result = {}
    with tempfile.TemporaryDirectory(prefix="rich_csv_") as directory:
        for relative in TABLES:
            source = root / relative
            temporary = Path(directory) / (source.stem + ".lua")
            generator.build(source, temporary)
            result[f"{GENERATED}/{temporary.name}"] = temporary.read_text(encoding="utf-8")
    # Render everything before writing anything so malformed input cannot leave
    # a partially generated rich table set.
    for relative, rendered in result.items():
        target = root / relative
        if check:
            assert target.is_file() and target.read_text(encoding="utf-8") == rendered, \
                f"Stale rich CSV output: {relative}"
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(rendered, encoding="utf-8", newline="\n")
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Check generated files without writing")
    args = parser.parse_args()
    outputs = build(check=args.check)
    print(f"Rich CSV {'check' if args.check else 'build'} passed: {len(outputs)} tables")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
