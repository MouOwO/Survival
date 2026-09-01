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
STRICT_CSV_SHAPE_FILES = {
    "asset_catalog.csv",
    "asset_components.csv",
    "building_challenge_definitions.csv",
    "monster_archetypes.csv",
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

# Tower CSVs describe the population required by a design row, while runtime
# code stores the population currently occupied by the resulting tower. Keep
# that distinction explicit at the generated-config boundary.
TOWER_POPULATION_FILES = {
    "arrow_tower_base.csv",
    "tower_class_anti_air.csv",
    "tower_class_death.csv",
    "tower_class_frost.csv",
    "tower_class_lightning.csv",
    "tower_class_machine_gun.csv",
    "tower_class_multi.csv",
    "tower_class_mystery.csv",
}
LUA_FIELD_ALIASES = {
    name: {"population_cost": "population_occupied"}
    for name in TOWER_POPULATION_FILES
}
WAR3_ARMOR_EFFECT_TYPES = {
    "super_wall_armor_flat",
    "lumberjack_attack_armor_reduction",
    "hero_attack_armor_reduction",
}

ROGUE_ENUM_FIELDS = {
    "effect_type": "rogue_effect_type",
    "execution_mode": "rogue_execution_mode",
    "owner_scope": "rogue_owner_scope",
    "target_selector": "rogue_target_selector",
    "stack_policy": "rogue_stack_policy",
}
ROGUE_LIFECYCLE_ENUM_FIELDS = {
    "rule_role": "rogue_rule_role",
    "event_type": "rogue_event_type",
    "predicate": "rogue_predicate",
    "transition": "rogue_transition",
}
ROGUE_REQUIRED_PARAMS = {
    "grant_gold_flat": {"value"},
    "grant_current_wood_pct": {"value"},
    "tower_attack_speed_bonus_pct": {"value"},
    "base_tower_attack_bonus_pct": {
        "value", "level_exclusive_max", "target_record_ids",
    },
    "wall_attacker_attack_speed_pct": {"value", "target_group"},
    "wall_hit_damage_cap_pct": {"value"},
    "training_capacity_flat": {
        "value", "training_id", "wood_cost_override", "gold_cost_override",
    },
    "next_boss_attack_pct": {"value", "boss_role", "elite_role"},
    "grant_random_cards": {"count"},
    "tower_upgrade_attack_bonus_pct": {"value"},
    "random_building_upgrade_count": {"count"},
    "ballista_damage_bonus_pct": {"value", "target_stage_ids"},
    "slowed_target_damage_taken_pct": {"value"},
    "max_tower_count_attack_bonus_pct": {"value_per_target", "max_value"},
    "owned_target_attacker_armor_reduction": {"value"},
    "grant_nuclear_bomb_action": {"batch_size", "batch_interval_seconds"},
    "wall_health_multiplier": {"multiplier"},
    "lumberjack_attack_speed_bonus_pct": {"value", "duration_seconds"},
    "hero_lifesteal_pct": {"burst.duration_seconds"},
    "timed_state": {"duration_seconds"},
    "event_counter": {"count"},
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


def csv_dict_rows(source: Path) -> list[tuple[int, dict[str, str]]]:
    with source.open("r", encoding="utf-8-sig", newline="") as handle:
        rows = list(csv.reader(handle))
    if not rows:
        return []
    headers = rows[0]
    result = []
    for line, fields in enumerate(rows[1:], start=2):
        if not fields or not fields[0].strip() or fields[0].strip().startswith("#"):
            continue
        fields = fields + [""] * (len(headers) - len(fields))
        result.append((line, dict(zip(headers, fields))))
    return result


def validate_strict_csv_shapes(sources: list[Path]) -> None:
    """Reject shifted or truncated rows in the asset/wearable source CSVs."""
    for source in sources:
        if source.name not in STRICT_CSV_SHAPE_FILES:
            continue
        with source.open("r", encoding="utf-8-sig", newline="") as handle:
            rows = list(csv.reader(handle))
        if not rows:
            raise ValueError(f"empty CSV: {source}")
        expected = len(rows[0])
        for line_number, fields in enumerate(rows[1:], 2):
            if not fields or not fields[0].strip() or fields[0].strip().startswith("#"):
                continue
            if len(fields) != expected:
                raise ValueError(
                    f"CSV column count mismatch: {source}"
                    f" (line {line_number} has {len(fields)} columns;"
                    f" expected {expected})\nrow: {fields}"
                )


def validate_rogue_reward_definitions(files: list[Path]) -> None:
    by_name = {source.name: source for source in files}
    required_files = {
        "enums.csv", "rogue_reward_cards.csv", "rogue_reward_effects.csv",
        "rogue_reward_effect_params.csv", "rogue_reward_effect_lifecycle.csv",
    }
    missing_files = required_files.difference(by_name)
    if missing_files:
        raise ValueError(f"rogue reward CSV files missing: {sorted(missing_files)}")

    enum_values: dict[str, set[str]] = {}
    for _, row in csv_dict_rows(by_name["enums.csv"]):
        if row.get("enabled", "").strip().lower() not in {"0", "false", "no", "off"}:
            enum_values.setdefault(row["enum_name"].strip(), set()).add(
                row["enum_value"].strip()
            )

    def unique_rows(name: str, key: str) -> dict[str, tuple[int, dict[str, str]]]:
        result = {}
        for line, row in csv_dict_rows(by_name[name]):
            identity = row.get(key, "").strip()
            if not identity:
                raise ValueError(f"empty {key}: {by_name[name]} line {line}")
            if identity in result:
                raise ValueError(f"duplicate {key} {identity!r}: {by_name[name]} line {line}")
            result[identity] = (line, row)
        return result

    cards = unique_rows("rogue_reward_cards.csv", "card_id")
    effects = unique_rows("rogue_reward_effects.csv", "effect_id")
    params = unique_rows("rogue_reward_effect_params.csv", "param_id")
    lifecycles = unique_rows("rogue_reward_effect_lifecycle.csv", "lifecycle_id")
    params_by_effect: dict[str, dict[str, str]] = {}
    lifecycle_by_effect: dict[str, list[dict[str, str]]] = {}
    enabled_effects_by_card: dict[str, int] = {}

    for effect_id, (line, row) in effects.items():
        card_id = row.get("card_id", "").strip()
        if card_id not in cards:
            raise ValueError(f"rogue effect {effect_id!r} has unknown card_id {card_id!r}")
        for field, enum_name in ROGUE_ENUM_FIELDS.items():
            raw = row.get(field, "").strip()
            if raw not in enum_values.get(enum_name, set()):
                raise ValueError(
                    f"rogue effect {effect_id!r} has invalid {field} {raw!r} at line {line}"
                )
        if row.get("enabled", "").strip().lower() not in {"0", "false", "no", "off"}:
            enabled_effects_by_card[card_id] = enabled_effects_by_card.get(card_id, 0) + 1

    for param_id, (line, row) in params.items():
        effect_id = row.get("effect_id", "").strip()
        if effect_id not in effects:
            raise ValueError(f"rogue param {param_id!r} has unknown effect_id {effect_id!r}")
        name = row.get("param_name", "").strip()
        effect_params = params_by_effect.setdefault(effect_id, {})
        if name in effect_params:
            raise ValueError(f"duplicate rogue param name {name!r} for {effect_id!r}")
        kind = row.get("value_type", "").strip()
        if kind not in {"number", "string", "boolean"}:
            raise ValueError(f"rogue param {param_id!r} has invalid value_type {kind!r}")
        value_fields = {
            "number": row.get("number_value", "").strip(),
            "string": row.get("string_value", "").strip(),
            "boolean": row.get("boolean_value", "").strip(),
        }
        if not value_fields[kind] or any(value_fields[other] for other in value_fields if other != kind):
            raise ValueError(f"rogue param {param_id!r} does not match value_type at line {line}")
        if kind == "number" and not re.fullmatch(r"[-+]?\d+(?:\.\d+)?", value_fields[kind]):
            raise ValueError(f"rogue param {param_id!r} has invalid number")
        if kind == "boolean" and value_fields[kind].lower() not in {
            "0", "1", "true", "false", "yes", "no", "on", "off",
        }:
            raise ValueError(f"rogue param {param_id!r} has invalid boolean")
        effect_params[name] = value_fields[kind]

    for lifecycle_id, (line, row) in lifecycles.items():
        effect_id = row.get("effect_id", "").strip()
        if effect_id not in effects:
            raise ValueError(
                f"rogue lifecycle {lifecycle_id!r} has unknown effect_id {effect_id!r}"
            )
        for field, enum_name in ROGUE_LIFECYCLE_ENUM_FIELDS.items():
            raw = row.get(field, "").strip()
            if raw not in enum_values.get(enum_name, set()):
                raise ValueError(
                    f"rogue lifecycle {lifecycle_id!r} has invalid {field} {raw!r} at line {line}"
                )
        lifecycle_by_effect.setdefault(effect_id, []).append(row)

    for effect_id, (_, effect) in effects.items():
        required = set(ROGUE_REQUIRED_PARAMS.get(effect["effect_type"].strip(), set()))
        required.update(ROGUE_REQUIRED_PARAMS.get(effect["execution_mode"].strip(), set()))
        available_params = params_by_effect.get(effect_id, {})
        missing = required.difference(available_params)
        if missing:
            raise ValueError(f"rogue effect {effect_id!r} missing params: {sorted(missing)}")
        if effect.get("enabled", "").strip().lower() not in {"0", "false", "no", "off"}:
            rules = lifecycle_by_effect.get(effect_id, [])
            if not any(rule.get("rule_role", "").strip() == "activate" for rule in rules):
                raise ValueError(f"enabled rogue effect {effect_id!r} has no activate lifecycle")

    for card_id, (_, card) in cards.items():
        if card.get("enabled", "").strip().lower() not in {"0", "false", "no", "off"} \
                and enabled_effects_by_card.get(card_id, 0) == 0:
            raise ValueError(f"enabled rogue card {card_id!r} has no enabled effect")


def validate_build_regions(
    source: Path, headers: list[str], data_rows: list[tuple[int, list[str]]]
) -> None:
    if source.name != "build_forbidden_regions.csv":
        return
    required = {
        "region_id", "region_type", "shape", "p1_x", "p1_y", "p2_x",
        "p2_y", "p3_x", "p3_y", "p4_x", "p4_y", "center_x",
        "center_y", "radius", "enabled",
    }
    missing = required.difference(headers)
    if missing:
        raise ValueError(f"build region columns missing: {sorted(missing)}")
    index = {name: position for position, name in enumerate(headers)}
    seen: set[str] = set()

    def text(fields: list[str], name: str) -> str:
        return fields[index[name]].strip()

    def coordinate(fields: list[str], name: str, line: int) -> float:
        raw = text(fields, name)
        if not raw:
            raise ValueError(f"missing {name}: {source} line {line}")
        try:
            return float(raw)
        except ValueError as error:
            raise ValueError(
                f"invalid {name}: {source} line {line}: {raw}"
            ) from error

    for line, fields in data_rows:
        region_id = text(fields, "region_id")
        if not region_id or region_id in seen:
            raise ValueError(f"duplicate or empty region_id: {source} line {line}")
        seen.add(region_id)
        region_type = text(fields, "region_type")
        if region_type not in {"hero_movable", "building_forbidden"}:
            raise ValueError(
                f"invalid region_type: {source} line {line}: {region_type}"
            )
        shape = text(fields, "shape")
        if shape == "circle":
            coordinate(fields, "center_x", line)
            coordinate(fields, "center_y", line)
            if coordinate(fields, "radius", line) <= 0:
                raise ValueError(f"circle radius must be positive: {source} line {line}")
            continue
        if shape != "quadrilateral":
            raise ValueError(f"invalid region shape: {source} line {line}: {shape}")
        points = [
            (coordinate(fields, f"p{i}_x", line),
             coordinate(fields, f"p{i}_y", line))
            for i in range(1, 5)
        ]
        direction = 0
        for i in range(4):
            a, b, c = points[i], points[(i + 1) % 4], points[(i + 2) % 4]
            cross = (b[0] - a[0]) * (c[1] - a[1]) \
                - (b[1] - a[1]) * (c[0] - a[0])
            if abs(cross) <= 0.000001:
                raise ValueError(
                    f"degenerate quadrilateral: {source} line {line}"
                )
            sign = 1 if cross > 0 else -1
            if direction and direction != sign:
                raise ValueError(
                    f"non-convex quadrilateral: {source} line {line}"
                )
            direction = sign


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


def validate_wave_definitions(
    source: Path, headers: list[str], data_rows: list[tuple[int, list[str]]]
) -> None:
    if source.name != "wave_definitions.csv":
        return
    seen_ids: dict[str, int] = {}
    normal_totals: dict[tuple[str, int], int] = {}
    present_groups: set[tuple[str, int]] = set()
    for row_number, fields in data_rows:
        row = dict(zip(headers, fields))
        wave_id = row.get("wave_id", "").strip()
        if not wave_id:
            raise ValueError(f"wave definition has empty wave_id: {source} line {row_number}")
        if wave_id in seen_ids:
            raise ValueError(
                f"duplicate wave_id {wave_id}: {source} lines"
                f" {seen_ids[wave_id]} and {row_number}"
            )
        seen_ids[wave_id] = row_number
        if row.get("enabled", "").strip().lower() in {"0", "false", "no", "n", "off"}:
            continue
        difficulty_id = row.get("difficulty_id", "").strip()
        wave_number = int(row.get("wave_number", "0") or 0)
        group = (difficulty_id, wave_number)
        present_groups.add(group)
        if row.get("member_role", "").strip() in {"", "normal"}:
            normal_totals[group] = normal_totals.get(group, 0) + int(
                row.get("monster_count", "0") or 0
            )
    for difficulty_id in ("N1", "N2", "N3", "N4", "N5"):
        for wave_number in range(11, 31):
            group = (difficulty_id, wave_number)
            if group in present_groups and normal_totals.get(group, 0) != 59:
                raise ValueError(
                    f"{difficulty_id} W{wave_number} requires exactly 59 normal monsters:"
                    f" found {normal_totals.get(group, 0)}"
                )


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


def validate_monster_default_wearables(sources: list[Path]) -> None:
    """Validate monster default wearable references before generating Lua."""
    by_name = {source.name: source for source in sources}
    catalog_source = by_name.get("asset_catalog.csv")
    archetype_source = by_name.get("monster_archetypes.csv")
    building_source = by_name.get("building_challenge_definitions.csv")
    if not catalog_source:
        return

    catalog = {
        row.get("asset_id", "").strip(): row
        for row in read_data_rows(catalog_source)
        if row.get("asset_id", "").strip()
    }
    components_by_asset: dict[str, list[dict[str, str]]] = {}
    component_source = by_name.get("asset_components.csv")
    if component_source:
        for row in read_data_rows(component_source):
            components_by_asset.setdefault(
                row.get("asset_id", "").strip(), []
            ).append(row)

    references: list[tuple[str, dict[str, str]]] = []
    for source in (archetype_source, building_source):
        if not source:
            continue
        for row in read_data_rows(source):
            asset_id = row.get("default_wearable_asset_id", "").strip()
            if asset_id:
                references.append((source.name, row))

    for source_name, row in references:
        asset_id = row["default_wearable_asset_id"].strip()
        asset = catalog.get(asset_id)
        identity = row.get("archetype_id", row.get("challenge_id", "")).strip()
        if not asset:
            raise ValueError(
                f"{source_name} {identity} references missing default wearable "
                f"asset: {asset_id}"
            )
        if asset.get("asset_type", "").strip() != "model_bundle":
            raise ValueError(
                f"{source_name} {identity} default wearable is not a model bundle: "
                f"{asset_id}"
            )
        model_path = row.get("model_path", "").strip()
        if model_path and asset.get("primary_model", "").strip() != model_path:
            raise ValueError(
                f"{source_name} {identity} model does not match default wearable: "
                f"{asset_id}"
            )
        if asset.get("load_group", "").strip() != "monster_default_wearables":
            raise ValueError(
                f"default wearable asset has invalid load_group: {asset_id}"
            )
        if asset.get("attachment_models", "").strip():
            raise ValueError(
                f"default wearable asset must declare models as components: {asset_id}"
            )
        if row.get("model_asset_id", "").strip():
            raise ValueError(
                f"{source_name} {identity} cannot combine model_asset_id and "
                f"default_wearable_asset_id"
            )
        components = [
            component for component in components_by_asset.get(asset_id, [])
            if component.get("enabled", "").strip().lower()
            not in {"0", "false", "no", "n", "off"}
        ]
        if not components:
            raise ValueError(f"default wearable asset has no components: {asset_id}")
        for component in components:
            if component.get("entity_class", "").strip() != "prop_dynamic":
                raise ValueError(
                    f"default wearable component must use prop_dynamic: "
                    f"{component.get('component_key', '')}"
                )
            if component.get("attach_mode", "").strip() != "bone_merge":
                raise ValueError(
                    f"default wearable component must use bone_merge: "
                    f"{component.get('component_key', '')}"
                )


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
    aliases = dict(WAR3_FIELD_ALIASES.get(source.name, {}))
    aliases.update(LUA_FIELD_ALIASES.get(source.name, {}))
    output_headers = [aliases.get(header, header) for header in headers]
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
    validate_build_regions(source, headers, data_rows)
    validate_wave_definitions(source, headers, data_rows)
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


def build_index(files: list[Path], output: Path) -> None:
    names = sorted(source.stem for source in files)
    index = ["-- AUTO-GENERATED CONFIG REGISTRY.", "local M = {}", ""]
    index += [
        f'M["{name}"] = require("config/generated/{name}")'
        for name in names
    ]
    index += ["", "return M", ""]
    output.write_text("\n".join(index), encoding="utf-8", newline="\n")


def main() -> int:
    files = sorted(CSV_ROOT.rglob("*.csv"))
    if not files:
        print(f"ERROR: no CSV files under {CSV_ROOT}", file=sys.stderr)
        return 11
    validate_strict_csv_shapes(files)
    validate_sound_cue_uniqueness(files)
    validate_monster_visual_definitions(files)
    validate_monster_default_wearables(files)
    validate_rogue_reward_definitions(files)

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
    build_index(files, OUT_ROOT / "index.lua")
    print(f"SUCCESS: generated {len(names)} Lua config modules")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
