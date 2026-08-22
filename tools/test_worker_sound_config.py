from __future__ import annotations

import csv
import tempfile
from pathlib import Path

from build_configs import build, validate_sound_cue_uniqueness


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "data" / "csv" / "建筑与工人系统" \
    / "worker_sound_definitions.csv"


def write_rows(path: Path, rows: list[list[str]]) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        csv.writer(handle).writerows(rows)


def expect_invalid(rows: list[list[str]], message: str) -> None:
    with tempfile.TemporaryDirectory() as folder:
        source = Path(folder) / SOURCE.name
        output = Path(folder) / "sound.lua"
        write_rows(source, rows)
        try:
            build(source, output)
        except ValueError:
            return
        raise AssertionError(message)


with SOURCE.open("r", encoding="utf-8-sig", newline="") as handle:
    authoritative = list(csv.reader(handle))

with tempfile.TemporaryDirectory() as folder:
    generated = Path(folder) / "worker_sound_definitions.lua"
    build(SOURCE, generated)
    production = ROOT / "scripts" / "vscripts" / "config" / "generated" \
        / "worker_sound_definitions.lua"
    assert generated.read_bytes() == production.read_bytes(), \
        "generated worker sound config is stale"

duplicate = [row[:] for row in authoritative]
duplicate.append(duplicate[3][:])
expect_invalid(duplicate, "duplicate worker cue_id was accepted")

missing_worker = [row[:] for row in authoritative]
missing_worker[3][1] = ""
expect_invalid(missing_worker, "missing worker_id was accepted")

invalid_mode = [row[:] for row in authoritative]
invalid_mode[3][5] = "ambient"
expect_invalid(invalid_mode, "invalid worker playback mode was accepted")

invalid_concurrency = [row[:] for row in authoritative]
invalid_concurrency[3][14] = ""
expect_invalid(invalid_concurrency, "partial worker concurrency fields were accepted")

negative_limit = [row[:] for row in authoritative]
negative_limit[3][8] = "-1"
expect_invalid(negative_limit, "negative worker cooldown was accepted")

hero_source = ROOT / "data" / "csv" / "英雄系统" \
    / "hero_skill_sound_definitions.csv"
with hero_source.open("r", encoding="utf-8-sig", newline="") as handle:
    hero_rows = list(csv.reader(handle))
cross_table_duplicate = [row[:] for row in authoritative]
cross_table_duplicate[3][0] = hero_rows[3][0]
with tempfile.TemporaryDirectory() as folder:
    temporary_root = Path(folder)
    temporary_hero = temporary_root / hero_source.name
    temporary_worker = temporary_root / SOURCE.name
    write_rows(temporary_hero, hero_rows)
    write_rows(temporary_worker, cross_table_duplicate)
    try:
        validate_sound_cue_uniqueness([temporary_hero, temporary_worker])
    except ValueError:
        pass
    else:
        raise AssertionError("cross-table duplicate sound cue_id was accepted")

print("WORKER_SOUND_CONFIG_PASS")