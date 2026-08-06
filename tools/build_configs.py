"""Build generated Lua config modules from categorized CSV files."""
from __future__ import annotations
import csv
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CSV_ROOT = ROOT / "data" / "csv"
OUT_ROOT = ROOT / "scripts" / "vscripts" / "config" / "generated"
IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
SOUND_OWNER_FIELDS = {
    "building_sound_definitions.csv": "building_scope",
    "hero_skill_sound_definitions.csv": "skill_id",
    "tower_skill_sound_definitions.csv": "skill_family",
    "worker_sound_definitions.csv": "worker_id",
}
MONSTER_VISUAL_FILES = {
    "monster_visual_assets.csv",
    "monster_visual_components.csv",
    "monster_visual_effects.csv",
    "wave_visual_definitions.csv",
}

# These CSVs preserve values extracted from the original War3 map. Generated
# Lua names the unit explicitly so runtime code cannot confuse source armor
# with Dota 2's actual armor. Values are converted exactly once by
# config/armor_balance.lua at a configuration or spawn boundary.
WAR3_FIELD_ALIASES = {
    "wave_definitions.csv": {
        "armor": "war3_armor",
    },
    "monster_archetypes.csv": {
        "armor": "war3_armor",
        "minimum_armor": "minimum_war3_armor",
    },
    "building_levels.csv": {
        "armor": "war3_armor",
    },
    "gold_mine_levels.csv": {
        "armor": "war3_armor",
    },
    "training_definitions.csv": {
        "armor": "war3_armor",
    },
    "weapon_definitions.csv": {
        "base_armor": "base_war3_armor",
    },
    "hero_definitions.csv": {
        "base_armor": "base_war3_armor",
    },
}
WAR3_ARMOR_EFFECT_TYPES = {
    "super_wall_armor_flat",
    "lumberjack_attack_armor_reduction",
    "hero_attack_armor_reduction",
}


def lua_escape(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"').replace("\r", "\\r").replace("\n", "\\n")


def value(raw: str, kind: str) -> str:
    raw = raw.strip()
    if not raw:
        return ""
    if kind == "number":
        if not re.fullmatch(r"[-+]?\d+(?:\.\d+)?", raw):
            raise ValueError(f"invalid number: {raw}")
        return raw
    if kind == "boolean":
        return "true" if raw.lower() in {"1", "true", "yes", "y", "on"} else "false"
    if kind == "list":
        separator = "," if "," in raw and "|" not in raw else "|"
        return "{" + ", ".join(f'"{lua_escape(x.strip())}"' for x in raw.split(separator) if x.strip()) + "}"
    return f'"{lua_escape(raw)}"'


def validate_sound_definitions(
    source: Path, headers: list[str], data_rows: list[tuple[int, list[str]]]
) -> None:
    """Validate lifecycle and limiter fields that generic CSV types cannot."""
    owner_field = SOUND_OWNER_FIELDS.get(source.name)
    if owner_field is None:
        return
    required = {
        "cue_id", owner_field, "phase",
        "playback_mode", "attach_scope", "cooldown_seconds",
        "max_plays_per_window", "window_seconds", "max_concurrent",
        "concurrency_seconds",
    }
    missing = sorted(required.difference(headers))
    if missing:
        raise ValueError(f"sound config missing columns {missing}: {source}")
    event_fields = {"sound_event", "sound_events"}.intersection(headers)
    resource_fields = {"sound_resource", "sound_resources"}.intersection(headers)
    if not event_fields or not resource_fields:
        raise ValueError(
            f"sound config requires event and resource columns: {source}"
        )
    phases = {
        "cast", "launch", "hit", "impact", "persistent_start",
        "persistent_end", "spawn_secondary", "construction_start",
        "construction_complete", "upgrade_complete",
    }
    playback_modes = {"oneshot", "loop"}
    attach_scopes = {"unit", "position"}
    seen: set[str] = set()
    for row_number, fields in data_rows:
        row = dict(zip(headers, fields))
        cue_id = row["cue_id"].strip()
        if not cue_id or cue_id in seen:
            raise ValueError(
                f"missing or duplicate sound cue_id {cue_id!r}:"
                f" {source} line {row_number}"
            )
        seen.add(cue_id)
        for key in (owner_field,):
            if not row[key].strip():
                raise ValueError(
                    f"sound cue {cue_id} requires {key}:"
                    f" {source} line {row_number}"
                )
        # Runtime rows default to enabled when the optional boolean cell is
        # blank; only explicit false-like values disable a cue.
        enabled = row.get("enabled", "").strip().lower() \
            not in {"0", "false", "no", "n", "off"}
        configured_events = [row[key].strip() for key in event_fields if row[key].strip()]
        configured_resources = [
            row[key].strip() for key in resource_fields if row[key].strip()
        ]
        if enabled:
            if not configured_events or not configured_resources:
                raise ValueError(
                    f"enabled sound cue {cue_id} requires events and resources:"
                    f" {source} line {row_number}"
                )
            if "sound_events" in row and "sound_resources" in row:
                events = [part.strip() for part in re.split(r"[|,]", row["sound_events"])
                          if part.strip()]
                resources = [part.strip() for part in re.split(r"[|,]", row["sound_resources"])
                             if part.strip()]
                if events and len(events) != len(resources):
                    raise ValueError(
                        f"sound cue {cue_id} layer event/resource counts differ:"
                        f" {source} line {row_number}"
                    )
        elif not configured_events and not configured_resources:
            # Disabled policy rows may intentionally document that a family
            # has no sound. Lifecycle fields are irrelevant when no event can
            # be resolved by the runtime service.
            continue
        for key, allowed in (
            ("phase", phases),
            ("playback_mode", playback_modes),
            ("attach_scope", attach_scopes),
        ):
            if row[key].strip() not in allowed:
                raise ValueError(
                    f"invalid {key} for sound cue {cue_id}: {row[key]!r}"
                )
        if row["playback_mode"].strip() == "loop" \
                and row["attach_scope"].strip() != "unit":
            raise ValueError(
                f"loop sound cue {cue_id} must attach to a unit lifecycle"
            )
        for key in (
            "cooldown_seconds", "max_plays_per_window", "window_seconds",
            "max_concurrent", "concurrency_seconds",
        ):
            raw = row[key].strip()
            if raw and float(raw) < 0:
                raise ValueError(f"sound cue {cue_id} has negative {key}")
        maximum = float(row["max_concurrent"].strip() or 0)
        lifetime = float(row["concurrency_seconds"].strip() or 0)
        if (maximum > 0) != (lifetime > 0):
            raise ValueError(
                f"sound cue {cue_id} concurrency fields must both be positive"
            )


def validate_sound_cue_uniqueness(sources: list[Path]) -> None:
    """Reject cue IDs shared by independently owned sound definition tables."""
    seen: dict[str, tuple[Path, int]] = {}
    for source in sources:
        if source.name not in SOUND_OWNER_FIELDS:
            continue
        with source.open("r", encoding="utf-8-sig", newline="") as handle:
            rows = list(csv.reader(handle))
        if not rows or "cue_id" not in rows[0]:
            continue
        cue_index = rows[0].index("cue_id")
        for row_number, fields in enumerate(rows[1:], start=2):
            if cue_index >= len(fields):
                continue
            cue_id = fields[cue_index].strip()
            if not cue_id or cue_id.startswith("#"):
                continue
            previous = seen.get(cue_id)
            if previous is not None:
                previous_source, previous_line = previous
                raise ValueError(
                    f"duplicate sound cue_id {cue_id!r} across definitions:"
                    f" {previous_source} line {previous_line};"
                    f" {source} line {row_number}"
                )
            seen[cue_id] = (source, row_number)


def read_data_rows(source: Path) -> list[dict[str, str]]:
    with source.open("r", encoding="utf-8-sig", newline="") as handle:
        rows = list(csv.reader(handle))
    if not rows:
        return []
    headers = rows[0]
    return [
        dict(zip(headers, fields))
        for fields in rows[1:]
        if fields and fields[0].strip()
        and not fields[0].strip().startswith("#")
    ]


def validate_monster_visual_definitions(sources: list[Path]) -> None:
    by_name = {source.name: source for source in sources}
    if not MONSTER_VISUAL_FILES.issubset(by_name):
        missing = sorted(MONSTER_VISUAL_FILES.difference(by_name))
        raise ValueError(f"monster visual config missing files: {missing}")

    assets = read_data_rows(by_name["monster_visual_assets.csv"])
    asset_ids: set[str] = set()
    for row in assets:
        asset_id = row.get("visual_asset_id", "").strip()
        if not asset_id or asset_id in asset_ids:
            raise ValueError(f"invalid or duplicate monster visual asset: {asset_id!r}")
        asset_ids.add(asset_id)
        if not row.get("model_path", "").strip():
            raise ValueError(f"monster visual asset requires model_path: {asset_id}")
        if not row.get("async_unit_name", "").strip():
            raise ValueError(f"monster visual asset requires async_unit_name: {asset_id}")
    for row in assets:
        fallback_id = row.get("fallback_visual_asset_id", "").strip()
        if fallback_id and fallback_id not in asset_ids:
            raise ValueError(f"monster visual fallback not found: {fallback_id}")

    for filename, id_field, resource_field in (
        ("monster_visual_components.csv", "component_id", "model_path"),
        ("monster_visual_effects.csv", "effect_id", "particle_path"),
    ):
        seen: set[str] = set()
        for row in read_data_rows(by_name[filename]):
            row_id = row.get(id_field, "").strip()
            asset_id = row.get("visual_asset_id", "").strip()
            if not row_id or row_id in seen:
                raise ValueError(f"invalid or duplicate {id_field}: {row_id!r}")
            seen.add(row_id)
            if asset_id not in asset_ids:
                raise ValueError(f"{id_field} references missing visual asset: {asset_id}")
            if not row.get(resource_field, "").strip():
                raise ValueError(f"{id_field} requires {resource_field}: {row_id}")
            if filename == "monster_visual_effects.csv":
                limit = float(row.get("max_per_unit", "0") or 0)
                if limit < 0:
                    raise ValueError(f"effect has negative max_per_unit: {row_id}")

    seen_waves: set[int] = set()
    role_fields = (
        "main_visual_asset_id", "support_visual_asset_id",
        "mini_boss_visual_asset_id", "stage_boss_visual_asset_id",
    )
    for row in read_data_rows(by_name["wave_visual_definitions.csv"]):
        wave_number = int(row.get("wave_number", "0") or 0)
        if wave_number < 1 or wave_number > 30 or wave_number in seen_waves:
            raise ValueError(f"invalid or duplicate monster visual wave: {wave_number}")
        seen_waves.add(wave_number)
        if not row.get("main_visual_asset_id", "").strip():
            raise ValueError(f"wave visual requires main asset: {wave_number}")
        for field in role_fields:
            asset_id = row.get(field, "").strip()
            if asset_id and asset_id not in asset_ids:
                raise ValueError(
                    f"wave {wave_number} {field} references missing asset: {asset_id}"
                )
        support_every = float(row.get("support_every_nth", "0") or 0)
        if support_every < 0 or not support_every.is_integer():
            raise ValueError(f"wave has invalid support_every_nth: {wave_number}")


def build(source: Path, output: Path) -> None:
    raw = source.read_bytes()
    for encoding in ("utf-8-sig", "utf-8", "gb18030", "gbk"):
        try:
            text = raw.decode(encoding)
            break
        except UnicodeDecodeError:
            text = None
    if text is None:
        raise UnicodeDecodeError("unknown", raw, 0, 1, f"unsupported CSV encoding: {source}")
    rows = list(csv.reader(text.splitlines(keepends=True)))
    if len(rows) < 2:
        raise ValueError(f"CSV requires header and #types row: {source}")
    headers = rows[0]
    output_headers = [
        WAR3_FIELD_ALIASES.get(source.name, {}).get(header, header)
        for header in headers
    ]
    type_index = next(
        (i for i, row in enumerate(rows[1:], 1)
         if row and row[0].startswith("#types:")),
        None,
    )
    if type_index is None:
        raise ValueError(f"CSV requires #types row: {source}")
    types = rows[type_index]
    if len(types) == 1 and types[0].startswith("#types:"):
        types = [item.strip() for item in types[0][7:].split(",")]
    else:
        types[0] = types[0][7:]
    if len(headers) != len(types):
        raise ValueError(
            f"header/type count mismatch: {source}"
            f" (header line 1 has {len(headers)} columns;"
            f" #types line {type_index + 1} has {len(types)} columns)\n"
            f"header: {headers}\n"
            f"types: {types}"
        )
    data_rows = []
    for row_number, fields in enumerate(rows[type_index + 1:], type_index + 2):
        if not fields or (len(fields) == 1 and not fields[0].strip()):
            continue
        if fields[0].strip().startswith("#"):
            continue
        if len(fields) < len(headers):
            # CSV schemas may add optional columns at the end. Older rows are
            # equivalent to leaving those trailing cells empty, so normalize
            # them without accepting missing or shifted columns in the middle.
            fields.extend([""] * (len(headers) - len(fields)))
        if len(fields) != len(headers):
            raise ValueError(
                f"CSV column count mismatch: {source}"
                f" (line {row_number} has {len(fields)} columns;"
                f" expected {len(headers)})\n"
                f"row: {fields}"
            )
        data_rows.append((row_number, fields))
    validate_sound_definitions(source, headers, data_rows)
    lines = [
        "-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.",
        f"-- Source: {source.name}",
        "local M = {}",
        "M.rows = {",
    ]
    for fields in rows[type_index + 1:]:
        if not fields or (len(fields) == 1 and not fields[0].strip()):
            continue
        if fields[0].strip().startswith("#"):
            continue
        parts = []
        source_values = dict(zip(headers, fields))
        armor_effect = (
            source.name == "technology_definitions.csv"
            and source_values.get("effect_type", "").strip()
            in WAR3_ARMOR_EFFECT_TYPES
        )
        for key, raw, kind in zip(output_headers, fields, types):
            converted = value(raw, kind)
            if not converted:
                continue
            if armor_effect and key in {"value_per_level", "effect_value"}:
                parts.append(f"war3_{key} = {converted}")
                parts.append(f"{key} = ({converted} / 3)")
                continue
            lua_key = key if IDENT.fullmatch(key) else f'["{lua_escape(key)}"]'
            parts.append(f"{lua_key} = {converted}")
        lines.append("    { " + ", ".join(parts) + " },")
    lines += [
        "}",
        "M.by_id = {}",
        "for _, row in ipairs(M.rows) do",
        f'    local key = row["{headers[0]}"]',
        "    if key ~= nil then M.by_id[key] = row end",
        "end",
        "return M",
        "",
    ]
    output.write_text("\n".join(lines), encoding="utf-8", newline="\n")


def main() -> int:
    files = sorted(CSV_ROOT.rglob("*.csv"))
    if not files:
        print(f"ERROR: no CSV files under {CSV_ROOT}", file=sys.stderr)
        return 11
    validate_sound_cue_uniqueness(files)
    validate_monster_visual_definitions(files)

    tooltip_builder = ROOT / "tools" / "build_tooltip_definitions.py"
    tooltip_built_separately = False
    if tooltip_builder.exists():
        result = subprocess.run([sys.executable, str(tooltip_builder)], cwd=ROOT)
        if result.returncode != 0:
            return result.returncode
        tooltip_built_separately = True
    OUT_ROOT.mkdir(parents=True, exist_ok=True)
    for source in files:
        if tooltip_built_separately and source.name == "tooltip_definitions.csv":
            print(
                f"[CSV -> Lua] {source.relative_to(CSV_ROOT)}"
                " (already generated by build_tooltip_definitions.py)"
            )
            continue
        print(f"[CSV -> Lua] {source.relative_to(CSV_ROOT)}")
        build(source, OUT_ROOT / f"{source.stem}.lua")
    names = sorted(source.stem for source in files)
    expected_outputs = {f"{name}.lua" for name in names}
    expected_outputs.add("index.lua")
    for old in OUT_ROOT.glob("*.lua"):
        if old.name not in expected_outputs:
            old.unlink()
    index = ["-- AUTO-GENERATED CONFIG REGISTRY.", "local M = {}", ""]
    index += [f'M["{name}"] = require("config/generated/{name}")' for name in names]
    index += ["", "return M", ""]
    (OUT_ROOT / "index.lua").write_text("\n".join(index), encoding="utf-8", newline="\n")
    print(f"SUCCESS: generated {len(names)} Lua config modules")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
