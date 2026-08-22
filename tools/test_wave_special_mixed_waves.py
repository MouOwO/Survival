"""Regression contract for the approved W11/W13/W24 mixed waves."""
from __future__ import annotations

import csv
import io
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "tools"
MONSTER_ROOT = ROOT / "data" / "csv" / "怪物与波次系统"
WAVE_CSV = MONSTER_ROOT / "wave_definitions.csv"
ARCHETYPE_CSV = MONSTER_ROOT / "monster_archetypes.csv"
GENERATED_WAVES = (
    ROOT / "scripts" / "vscripts" / "config" / "generated"
    / "wave_definitions.lua"
)
TARGET_DIFFICULTIES = ("N1", "N2", "N3", "N4", "N5")
TARGET_WAVES = {
    11: "flying_red_gargoyle",
    13: "flying_green_head",
    24: "flying_black_bone",
}


def rows(path: Path) -> list[dict[str, str]]:
    raw = path.read_bytes()
    for encoding in ("utf-8-sig", "utf-8", "gb18030", "gbk"):
        try:
            text = raw.decode(encoding)
            break
        except UnicodeDecodeError:
            continue
    else:
        raise AssertionError(f"unsupported CSV encoding: {path}")
    lines = [line for line in text.splitlines() if not line.startswith("#")]
    return list(csv.DictReader(io.StringIO("\n".join(lines))))


wave_rows = rows(WAVE_CSV)
archetypes = {row["archetype_id"]: row for row in rows(ARCHETYPE_CSV)}

wave_ids = [row["wave_id"] for row in wave_rows]
assert len(wave_ids) == len(set(wave_ids)), "wave_definitions contains duplicate wave_id values"
for difficulty_id in TARGET_DIFFICULTIES:
    for wave_number in range(11, 31):
        present = any(
            row["difficulty_id"] == difficulty_id
            and row["wave_number"] == str(wave_number)
            for row in wave_rows
        )
        if not present:
            continue
        normal_count = sum(
            int(row["monster_count"])
            for row in wave_rows
            if row["difficulty_id"] == difficulty_id
            and row["wave_number"] == str(wave_number)
            and row["member_role"] == "normal"
            and row["enabled"].lower() not in {"0", "false", "no", "n", "off"}
        )
        assert normal_count == 59, (
            f"{difficulty_id} W{wave_number} normal count is {normal_count}, expected 59"
        )

    wave_11_counts = {
        row["archetype_id"]: int(row["monster_count"])
        for row in wave_rows
        if row["difficulty_id"] == difficulty_id
        and row["wave_number"] == "11"
        and row["member_role"] == "normal"
    }
    assert wave_11_counts == {
        "beast_green_large": 10,
        "skeleton_bone": 30,
        "flying_red_gargoyle": 19,
    }, f"{difficulty_id} W11 composition changed: {wave_11_counts}"

for difficulty_id in TARGET_DIFFICULTIES:
    for wave_number, flying_archetype in TARGET_WAVES.items():
        target = [
            row for row in wave_rows
            if row["difficulty_id"] == difficulty_id
            and row["wave_number"] == str(wave_number)
        ]
        leaders = [row for row in target if row["member_role"] == "wave_leader"]
        normals = [row for row in target if row["member_role"] == "normal"]
        flying = [
            row for row in normals
            if row["archetype_id"] == flying_archetype
        ]
        ground = [row for row in normals if row not in flying]

        assert len(leaders) == 1, f"{difficulty_id} W{wave_number} leader changed"
        assert len(flying) == 1, f"{difficulty_id} W{wave_number} flying row changed"
        assert int(leaders[0]["spawn_order"]) < min(
            int(row["spawn_order"]) for row in normals
        ), f"{difficulty_id} W{wave_number} leader no longer spawns first"
        assert sum(int(row["monster_count"]) for row in normals) == 59
        assert sum(int(row["monster_count"]) for row in ground) == 40
        assert int(flying[0]["monster_count"]) == 19
        assert len({int(row["attack"]) for row in ground}) == 1, (
            f"{difficulty_id} W{wave_number} normal attack baseline is ambiguous"
        )
        assert all(
            archetypes[row["archetype_id"]]["movement_type"] == "ground"
            for row in ground
        ), f"{difficulty_id} W{wave_number} ground member movement changed"
        assert (
            flying[0]["movement_type_override"] == "flying"
            or archetypes[flying_archetype]["movement_type"] == "flying"
        ), f"{difficulty_id} W{wave_number} flying member lost flying identity"
        assert int(flying[0]["health"]) * 10 == int(leaders[0]["health"]), (
            f"{difficulty_id} W{wave_number} flying health is not leader health / 10"
        )
        assert int(flying[0]["attack"]) * 2 == int(ground[0]["attack"]), (
            f"{difficulty_id} W{wave_number} flying attack is not normal attack / 2"
        )

for difficulty_id in ("N2", "N3", "N4", "N5"):
    wave_12 = [
        row for row in wave_rows
        if row["difficulty_id"] == difficulty_id
        and row["wave_number"] == "12"
        and row["member_role"] == "normal"
    ]
    assert wave_12 and all(
        archetypes[row["archetype_id"]]["movement_type"] == "flying"
        for row in wave_12
    ), f"{difficulty_id} W12 legitimate flying composition changed"

generated = GENERATED_WAVES.read_text(encoding="utf-8")
for difficulty_id in TARGET_DIFFICULTIES:
    for wave_number, flying_archetype in TARGET_WAVES.items():
        generated_rows = re.findall(
            r'\{[^\n]*difficulty_id = "' + difficulty_id
            + r'"[^\n]*wave_number = ' + str(wave_number)
            + r'[^\n]*\}',
            generated,
        )
        assert (
            any(
                f'archetype_id = "{flying_archetype}"' in row
                and "monster_count = 19" in row
                for row in generated_rows
            )
        ), f"{difficulty_id} W{wave_number} generated flying row missing"

sys.path.insert(0, str(TOOLS))
from import_n3_wave_workbook import (  # noqa: E402
    allocate,
    approved_normal_flying_count,
    approved_normal_member_templates,
)

assert approved_normal_flying_count(11, 0) == 19
assert approved_normal_flying_count(13, 0) == 19
assert approved_normal_flying_count(24, 0) == 19
assert approved_normal_flying_count(12, 59) == 59
n1_wave_11 = [
    row for row in wave_rows
    if row["difficulty_id"] == "N1" and row["wave_number"] == "11"
]
n1_normal_templates = approved_normal_member_templates(11, n1_wave_11)
assert any(row["archetype_id"] == "flying_red_gargoyle"
           for row in n1_normal_templates)
assert sum(allocate(59, n1_normal_templates)) == 59

print("WAVE_SPECIAL_MIXED_WAVES_PASS")