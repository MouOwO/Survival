from __future__ import annotations

import csv
import tempfile
from pathlib import Path

from build_configs import build


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "data" / "csv" / "英雄系统" / "hero_skill_sound_definitions.csv"


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
    generated = Path(folder) / "hero_skill_sound_definitions.lua"
    build(SOURCE, generated)
    production = ROOT / "scripts" / "vscripts" / "config" / "generated" \
        / "hero_skill_sound_definitions.lua"
    assert generated.read_bytes() == production.read_bytes(), \
        "generated hero sound config is stale"

duplicate = [row[:] for row in authoritative]
duplicate.append(duplicate[3][:])
expect_invalid(duplicate, "duplicate cue_id was accepted")

invalid_mode = [row[:] for row in authoritative]
invalid_mode[3][5] = "ambient"
expect_invalid(invalid_mode, "invalid playback mode was accepted")

invalid_concurrency = [row[:] for row in authoritative]
invalid_concurrency[3].extend(
    [""] * (len(authoritative[0]) - len(invalid_concurrency[3]))
)
invalid_concurrency[3][13] = "2"
invalid_concurrency[3][14] = ""
expect_invalid(invalid_concurrency, "partial concurrency fields were accepted")

negative_limit = [row[:] for row in authoritative]
negative_limit[3][8] = "-1"
expect_invalid(negative_limit, "negative cooldown was accepted")

print("HERO_SKILL_SOUND_CONFIG_PASS")