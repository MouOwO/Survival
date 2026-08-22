"""Validate enabled wave-monster models against catalog, proxies, and Dota VPK."""
from __future__ import annotations

import csv
import re
import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
VPK = ROOT.parent.parent / "dota" / "pak01_dir.vpk"
MONSTER_ROOT = ROOT / "data" / "csv" / "怪物与波次系统"
ASSET_CATALOG = ROOT / "data" / "csv" / "资源系统" / "asset_catalog.csv"
UNIT_KV = ROOT / "scripts" / "npc" / "npc_units_custom.txt"
PROBLEM_WAVES = {8, 11, 13, 22, 27, 30}
REMOVED_MODEL_PATHS = {
    "models/heroes/abyssal_underlord/abyssal_underlord.vmdl",
    "models/heroes/tusk/tusk.vmdl",
    "models/heroes/vengefulspirit/vengefulspirit.vmdl",
}
SHARED_NON_WAVE_ARCHETYPES = {"rebirth_boss_06", "ten_sin_05"}


def read_cstring(handle) -> str:
    data = bytearray()
    while True:
        value = handle.read(1)
        if not value:
            raise EOFError("unexpected end of VPK tree")
        if value == b"\0":
            return data.decode("utf-8", errors="replace")
        data.extend(value)


def vpk_paths() -> set[str]:
    with VPK.open("rb") as handle:
        signature, version, tree_size = struct.unpack("<III", handle.read(12))
        assert signature == 0x55AA1234, "invalid VPK signature"
        if version == 2:
            handle.read(16)
        else:
            assert version == 1, f"unsupported VPK version: {version}"
        tree_end = handle.tell() + tree_size
        result = set()
        while handle.tell() < tree_end:
            extension = read_cstring(handle)
            if not extension:
                break
            while True:
                directory = read_cstring(handle)
                if not directory:
                    break
                while True:
                    filename = read_cstring(handle)
                    if not filename:
                        break
                    entry = struct.unpack("<IHHIIH", handle.read(18))
                    preload_bytes, terminator = entry[1], entry[5]
                    assert terminator == 0xFFFF, "invalid VPK entry terminator"
                    if preload_bytes:
                        handle.read(preload_bytes)
                    prefix = "" if directory == " " else directory + "/"
                    result.add(f"{prefix}{filename}.{extension}")
        return result


def decoded(path: Path) -> str:
    raw = path.read_bytes()
    for encoding in ("utf-8-sig", "utf-8", "gb18030", "gbk"):
        try:
            return raw.decode(encoding)
        except UnicodeDecodeError:
            continue
    raise AssertionError(f"unsupported CSV encoding: {path}")


def rows(path: Path) -> list[dict[str, str]]:
    lines = [line for line in decoded(path).splitlines()
             if not line.startswith("#")]
    return list(csv.DictReader(lines))


def enabled(row: dict[str, str]) -> bool:
    return row.get("enabled", "").strip().lower() in {
        "1", "true", "yes", "y", "on"
    }


archetypes = {
    row["archetype_id"]: row
    for row in rows(MONSTER_ROOT / "monster_archetypes.csv")
}
waves = [
    row for row in rows(MONSTER_ROOT / "wave_definitions.csv")
    if enabled(row)
]
NORMAL_FLYING_MODEL = "models/heroes/visage/visage.vmdl"
catalog_rows = [row for row in rows(ASSET_CATALOG) if enabled(row)]
catalog_by_id = {row["asset_id"]: row for row in catalog_rows}
visage_asset = catalog_by_id.get("monster_visage")
assert visage_asset is not None, "monster_visage asset is missing"
assert visage_asset.get("first_use_wave") == "8", (
    "monster_visage first_use_wave must match the earliest formal normal-flying use"
)
monster_catalog_by_model: dict[str, list[dict[str, str]]] = {}
for row in catalog_rows:
    if row["asset_id"].startswith("monster_") and row.get("primary_model", ""):
        monster_catalog_by_model.setdefault(row["primary_model"], []).append(row)

source_text = "\n".join((
    decoded(MONSTER_ROOT / "monster_archetypes.csv"),
    decoded(ASSET_CATALOG),
    UNIT_KV.read_text(encoding="utf-8"),
))
for removed_path in sorted(REMOVED_MODEL_PATHS):
    assert removed_path not in source_text, (
        f"removed Dota model path returned to monster configuration: {removed_path}"
    )

referenced_ids = {row["archetype_id"] for row in waves}
assert len(referenced_ids) == 41, (
    f"enabled wave archetype coverage changed: {len(referenced_ids)}"
)
missing_archetypes = sorted(referenced_ids.difference(archetypes))
assert not missing_archetypes, (
    "enabled waves reference missing archetypes: " + ", ".join(missing_archetypes)
)

normal_flying_rows = [
    row for row in waves
    if row.get("member_role", "") in {"", "normal"}
    and (
        row.get("movement_type_override", "") == "flying"
        or archetypes[row["archetype_id"]].get("movement_type", "") == "flying"
    )
]
normal_flying_ids = {row["archetype_id"] for row in normal_flying_rows}
assert len(normal_flying_ids) == 12, (
    f"normal flying archetype coverage changed: {len(normal_flying_ids)}"
)
wrong_normal_flying_models = {
    archetype_id: archetypes[archetype_id].get("normal_flying_model_path", "")
    for archetype_id in normal_flying_ids
    if archetypes[archetype_id].get("normal_flying_model_path", "")
    != NORMAL_FLYING_MODEL
}
assert not wrong_normal_flying_models, (
    "normal flying archetypes do not use the approved flying model: "
    f"{wrong_normal_flying_models}"
)
assert archetypes["flying_red_gargoyle"]["model_path"] != NORMAL_FLYING_MODEL, (
    "shared flying archetype base model changed; flying leaders/Bosses must remain unchanged"
)

audited_ids = referenced_ids.union(SHARED_NON_WAVE_ARCHETYPES)
missing_shared = sorted(audited_ids.difference(archetypes))
assert not missing_shared, (
    "shared monster archetypes are missing: " + ", ".join(missing_shared)
)

model_paths = {
    archetypes[archetype_id]["model_path"] for archetype_id in audited_ids
}
model_paths.add(NORMAL_FLYING_MODEL)
assert len(model_paths) == 22, (
    f"enabled wave model coverage changed: {len(model_paths)}"
)
returned_paths = REMOVED_MODEL_PATHS.intersection(model_paths)
assert not returned_paths, (
    "removed Dota model paths returned: "
    + ", ".join(sorted(returned_paths))
)

available = vpk_paths()
missing_vpk = sorted(
    path for path in model_paths
    if path.replace(".vmdl", ".vmdl_c") not in available
)
assert not missing_vpk, (
    "wave monster models missing from local VPK:\n" + "\n".join(missing_vpk)
)

missing_catalog = sorted(model_paths.difference(monster_catalog_by_model))
assert not missing_catalog, (
    "wave monster models missing from asset catalog:\n"
    + "\n".join(missing_catalog)
)
duplicate_catalog = {
    path: [row["asset_id"] for row in monster_catalog_by_model[path]]
    for path in model_paths
    if len(monster_catalog_by_model[path]) != 1
}
assert not duplicate_catalog, (
    f"wave monster models require one monster catalog row each: {duplicate_catalog}"
)

unit_kv = UNIT_KV.read_text(encoding="utf-8")
for model_path in sorted(model_paths):
    asset = monster_catalog_by_model[model_path][0]
    async_unit_name = asset.get("async_unit_name", "").strip()
    assert async_unit_name or asset.get("load_group") == "initial_required", (
        f"wave monster asset has no preload route: {asset['asset_id']}"
    )
    if async_unit_name.startswith("asset_proxy_"):
        proxy_pattern = re.compile(
            r'"' + re.escape(async_unit_name) + r'"\s*\{[^{}]*'
            r'"Model"\s*"' + re.escape(model_path) + r'"[^{}]*\}',
            re.DOTALL,
        )
        assert proxy_pattern.search(unit_kv), (
            f"wave monster proxy/model mismatch: {asset['asset_id']}"
        )
    elif async_unit_name:
        assert async_unit_name.startswith("npc_dota_hero_"), (
            f"unsupported built-in wave monster proxy: {async_unit_name}"
        )

covered_problem_waves = {
    int(row["wave_number"])
    for row in waves
    if int(row["wave_number"]) in PROBLEM_WAVES
}
assert covered_problem_waves == PROBLEM_WAVES, (
    "problem-wave coverage changed: "
    + ", ".join(str(number) for number in sorted(covered_problem_waves))
)

print(
    "WAVE_MONSTER_MODEL_RESOURCES_PASS "
    f"wave_archetypes={len(referenced_ids)} audited_archetypes={len(audited_ids)} "
    f"models={len(model_paths)} "
    f"problem_waves={len(covered_problem_waves)}"
)