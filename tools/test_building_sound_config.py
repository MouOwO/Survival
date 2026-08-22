from __future__ import annotations

import csv
import subprocess
import tempfile
from pathlib import Path

from build_configs import build, validate_sound_cue_uniqueness


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "data" / "csv" / "建筑与工人系统" \
    / "building_sound_definitions.csv"
GENERATED = ROOT / "scripts" / "vscripts" / "config" / "generated" \
    / "building_sound_definitions.lua"
DOTA_ROOT = ROOT.parents[1] / "dota"
RESOURCEINFO = ROOT.parents[1] / "bin" / "win64" / "resourceinfo.exe"
VPK = DOTA_ROOT / "pak01_dir.vpk"


def write_rows(path: Path, rows: list[list[str]]) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        csv.writer(handle).writerows(rows)


def expect_invalid(rows: list[list[str]], message: str) -> None:
    with tempfile.TemporaryDirectory() as folder:
        source = Path(folder) / SOURCE.name
        output = Path(folder) / "building_sound.lua"
        write_rows(source, rows)
        try:
            build(source, output)
        except ValueError:
            return
        raise AssertionError(message)


with SOURCE.open("r", encoding="utf-8-sig", newline="") as handle:
    authoritative = list(csv.reader(handle))
header = authoritative[0]
rows = [dict(zip(header, row)) for row in authoritative[3:]]

assert len(rows) == 20, "building sound config must contain 19 lifecycle and 1 combat cue"
assert len({row["cue_id"] for row in rows}) == 20, "building cue IDs are not unique"
assert all(row["enabled"].strip().lower() not in {"0", "false"} for row in rows), \
    "all approved building sound cues must be enabled"
assert all("|" not in row["sound_events"] for row in rows), \
    "building lifecycle cues must remain single-layer and restrained"
assert rows[0]["sound_events"] == "General.SelectAction", \
    "construction start must use the lightweight selection cue"
assert rows[1]["sound_events"] == "DOTA_Item.Buckler.Activate", \
    "construction completion must use the soft buckler cue"
upgrade_rows = [row for row in rows if row["phase"] == "upgrade_complete"]
assert len(upgrade_rows) == 17, "building sound config must retain 17 upgrade cues"
assert all(row["sound_events"] == "General.LevelUp.Bonus" for row in upgrade_rows), \
    "building upgrades must use the lightweight level-up cue"
assert next(row for row in rows if row["cue_id"] == "building_wall_damage")[
    "sound_events"
] == "Building_Generic.PartialDestruction", "wall damage must use the native building hit"

ordinary_routes = {
    row["tower_class"] for row in rows
    if row["transition_type"] == "route_upgrade"
}
major_routes = {
    row["tower_class"] for row in rows
    if row["transition_type"] == "major_upgrade"
}
expected_routes = {f"class_{index}" for index in range(1, 8)}
assert ordinary_routes == expected_routes, "ordinary tower upgrades miss a route"
assert major_routes == expected_routes, "major tower upgrades miss a route"

with tempfile.TemporaryDirectory() as folder:
    generated = Path(folder) / GENERATED.name
    build(SOURCE, generated)
    assert generated.read_bytes() == GENERATED.read_bytes(), \
        "generated building sound config is stale"

layer_mismatch = [row[:] for row in authoritative]
layer_mismatch[3][5] += "|General.SelectAction"
expect_invalid(layer_mismatch, "mismatched building sound layers were accepted")

invalid_phase = [row[:] for row in authoritative]
invalid_phase[3][2] = "walking"
expect_invalid(invalid_phase, "invalid building sound phase was accepted")

missing_scope = [row[:] for row in authoritative]
missing_scope[3][1] = ""
expect_invalid(missing_scope, "missing building scope was accepted")

other_sources = [
    ROOT / "data" / "csv" / "英雄系统" / "hero_skill_sound_definitions.csv",
    ROOT / "data" / "csv" / "建筑与工人系统" / "防御塔"
    / "tower_skill_sound_definitions.csv",
    ROOT / "data" / "csv" / "建筑与工人系统" / "worker_sound_definitions.csv",
]
validate_sound_cue_uniqueness([SOURCE, *other_sources])

assert RESOURCEINFO.is_file() and VPK.is_file(), \
    "local Dota resource tools are required for native event validation"
events_by_resource: dict[str, set[str]] = {}
for row in rows:
    events = [part.strip() for part in row["sound_events"].split("|") if part.strip()]
    resources = [
        part.strip() for part in row["sound_resources"].split("|") if part.strip()
    ]
    assert len(events) == len(resources), f"layer count mismatch: {row['cue_id']}"
    for event, resource in zip(events, resources):
        if resource not in events_by_resource:
            result = subprocess.run(
                [str(RESOURCEINFO), "-i", f"{VPK}\\{resource}_c", "-strings"],
                check=True,
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
            )
            events_by_resource[resource] = set(result.stdout.splitlines())
        assert event in events_by_resource[resource], \
            f"native event missing from {resource}: {event}"

index = (GENERATED.parent / "index.lua").read_text(encoding="utf-8")
assert 'M["building_sound_definitions"]' in index, \
    "generated config registry does not expose building sounds"

print("BUILDING_SOUND_CONFIG_PASS")