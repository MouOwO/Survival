from __future__ import annotations

import csv
import re
import subprocess
import tempfile
from pathlib import Path

from build_configs import build, validate_sound_cue_uniqueness


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "data" / "csv" / "建筑与工人系统" / "防御塔" \
    / "tower_skill_sound_definitions.csv"
GENERATED = ROOT / "scripts" / "vscripts" / "config" / "generated" \
    / "tower_skill_sound_definitions.lua"
SKILLS = SOURCE.with_name("tower_skill_definitions.csv")
DOTA_ROOT = ROOT.parents[1] / "dota"
RESOURCEINFO = ROOT.parents[1] / "bin" / "win64" / "resourceinfo.exe"
VPK = DOTA_ROOT / "pak01_dir.vpk"


def write_rows(path: Path, rows: list[list[str]]) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        csv.writer(handle).writerows(rows)


def expect_invalid(rows: list[list[str]], message: str) -> None:
    with tempfile.TemporaryDirectory() as folder:
        source = Path(folder) / SOURCE.name
        output = Path(folder) / "tower_sound.lua"
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

assert len(rows) == 22, "tower sound config must contain 21 skill and 1 attack cue"
assert len({row["cue_id"] for row in rows}) == 22, "tower cue IDs are not unique"
assert len({row["skill_family"] for row in rows}) == 22, \
    "tower sound families are not unique"

skill_bytes = SKILLS.read_bytes()
skill_text = None
for encoding in ("utf-8-sig", "utf-8", "gb18030", "gbk"):
    try:
        skill_text = skill_bytes.decode(encoding)
        break
    except UnicodeDecodeError:
        continue
assert skill_text is not None, "tower skill definitions use an unsupported encoding"
skill_rows = list(csv.reader(skill_text.splitlines()))[3:]
skill_families = {
    re.sub(r"_lv\d+$", "", row[0]) for row in skill_rows if row and row[0]
}
configured_families = {row["skill_family"] for row in rows}
assert configured_families == skill_families | {"basic_attack"}, \
    "tower sounds must cover every skill plus the basic attack family"
basic_attack = next(row for row in rows if row["skill_family"] == "basic_attack")
assert basic_attack["cue_id"] == "tower_basic_attack" \
    and basic_attack["phase"] == "launch" \
    and basic_attack["sound_event"] == "Creep_Good_Range.Attack", \
    "tower basic attack must use the native ranged launch cue"

disabled = [row for row in rows if row["enabled"].strip().lower() in {"0", "false"}]
assert len(disabled) == 1 and disabled[0]["skill_family"] == "machine_gun", \
    "machine_gun must be the only explicitly silent family"

with tempfile.TemporaryDirectory() as folder:
    generated = Path(folder) / GENERATED.name
    build(SOURCE, generated)
    assert generated.read_bytes() == GENERATED.read_bytes(), \
        "generated tower sound config is stale"

missing_owner = [row[:] for row in authoritative]
missing_owner[3][1] = ""
expect_invalid(missing_owner, "missing tower skill family was accepted")

missing_enabled_event = [row[:] for row in authoritative]
missing_enabled_event[3][3] = ""
expect_invalid(missing_enabled_event, "enabled tower cue without an event was accepted")

for other in (
    ROOT / "data" / "csv" / "英雄系统" / "hero_skill_sound_definitions.csv",
    ROOT / "data" / "csv" / "建筑与工人系统" / "worker_sound_definitions.csv",
):
    validate_sound_cue_uniqueness([SOURCE, other])

assert RESOURCEINFO.is_file() and VPK.is_file(), \
    "local Dota resource tools are required for native event validation"
events_by_resource: dict[str, set[str]] = {}
for row in rows:
    if row in disabled:
        continue
    resource = row["sound_resource"]
    if resource not in events_by_resource:
        internal = resource + "_c"
        result = subprocess.run(
            [str(RESOURCEINFO), "-i", f"{VPK}\\{internal}", "-strings"],
            check=True,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
        events_by_resource[resource] = set(result.stdout.splitlines())
    assert row["sound_event"] in events_by_resource[resource], \
        f"native event missing from {resource}: {row['sound_event']}"

index = (GENERATED.parent / "index.lua").read_text(encoding="utf-8")
assert 'M["tower_skill_sound_definitions"]' in index, \
    "generated config registry does not expose tower sounds"

print("TOWER_SKILL_SOUND_CONFIG_PASS")
