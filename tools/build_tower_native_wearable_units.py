"""Synchronize hero-body tower visuals from authoritative CSVs."""
from __future__ import annotations

import argparse
import csv
import io
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CSV_ROOT = ROOT / "data" / "csv"
TOWER_ROOT = CSV_ROOT / "建筑与工人系统" / "防御塔"
RESOURCE_ROOT = CSV_ROOT / "资源系统"
NPC_UNITS = ROOT / "scripts" / "npc" / "npc_units_custom.txt"


def csv_rows(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        return [
            row for row in csv.DictReader(handle)
            if row and not row.get(next(iter(row)), "").startswith("#")
        ]


def rewrite_csv(
    path: Path,
    update: callable,
    check: bool,
) -> bool:
    raw = path.read_bytes()
    bom = raw.startswith(b"\xef\xbb\xbf")
    text = raw.decode("utf-8-sig")
    newline = "\r\n" if "\r\n" in text else "\n"
    rows = list(csv.reader(io.StringIO(text, newline="")))
    if not rows:
        raise RuntimeError(f"empty CSV: {path}")
    headers = rows[0]
    changed = False
    for row in rows[1:]:
        if not row or row[0].startswith("#"):
            continue
        if len(row) < len(headers):
            row.extend([""] * (len(headers) - len(row)))
        changed = update(dict(zip(headers, row)), row, headers) or changed
    if changed and not check:
        output = io.StringIO(newline="")
        csv.writer(output, lineterminator=newline).writerows(rows)
        path.write_text(
            output.getvalue(),
            encoding="utf-8-sig" if bom else "utf-8",
            newline="",
        )
    return changed


def sync_component_csv(
    stages: dict[str, dict[str, str]],
    wearable_rows: list[dict[str, str]],
    check: bool,
) -> bool:
    path = RESOURCE_ROOT / "asset_components.csv"
    raw = path.read_bytes()
    bom = raw.startswith(b"\xef\xbb\xbf")
    text = raw.decode("utf-8-sig")
    newline = "\r\n" if "\r\n" in text else "\n"
    rows = list(csv.reader(io.StringIO(text, newline="")))
    if not rows:
        raise RuntimeError(f"empty CSV: {path}")
    headers = rows[0]
    asset_index = headers.index("asset_id")
    retained = [
        row for row in rows[1:]
        if not row or row[0].startswith("#")
        or len(row) <= asset_index or row[asset_index] not in stages
    ]

    component_rows: list[list[str]] = []
    counts = {asset_id: 0 for asset_id in stages}
    seen_component_keys: set[str] = set()
    seen_component_ids: dict[str, set[str]] = {
        asset_id: set() for asset_id in stages
    }
    for wearable in wearable_rows:
        asset_id = wearable.get("asset_id", "").strip()
        if asset_id not in stages or wearable.get("enabled", "1").strip() == "0":
            continue
        model_path = wearable.get("model_path", "").strip()
        if not model_path:
            continue
        wearable_key = wearable.get("wearable_key", "").strip()
        component_key = f"{asset_id}:{wearable_key}"
        component_id = wearable_key
        if component_key in seen_component_keys:
            raise RuntimeError(f"duplicate projected component key: {component_key}")
        if component_id in seen_component_ids[asset_id]:
            raise RuntimeError(
                f"duplicate projected component ID: {asset_id}:{component_id}"
            )
        seen_component_keys.add(component_key)
        seen_component_ids[asset_id].add(component_id)
        counts[asset_id] += 1
        metadata = "; ".join([
            "source=asset_native_wearables.csv",
            f"wearable_key={wearable_key}",
            f"item_def={wearable.get('item_def', '').strip()}",
            f"hero_unit_name={wearable.get('hero_unit_name', '').strip()}",
            f"slot={wearable.get('slot', '').strip()}",
        ])
        values = {
            "component_key": component_key,
            "asset_id": asset_id,
            "component_id": component_id,
            "model_path": model_path,
            "entity_class": "prop_dynamic",
            "parent_component_id": "",
            "attach_mode": "bone_merge",
            "attachment_point": "",
            "default_sequence": "idle",
            "model_scale": "1",
            "model_skin": "",
            "material_group": "",
            "sort_order": wearable.get("sort_order", "").strip(),
            "enabled": "1",
            "notes": metadata,
        }
        component_rows.append([values.get(header, "") for header in headers])

    if len(component_rows) != 97:
        raise RuntimeError(
            f"expected 97 projected world components, found {len(component_rows)}"
        )
    io_asset_id = "tower_laser_od_blackgate"
    if counts.get(io_asset_id) != 0:
        raise RuntimeError("Io must project zero world components")

    output = io.StringIO(newline="")
    csv.writer(output, lineterminator=newline).writerows(
        [headers] + retained + component_rows
    )
    expected = ("\ufeff" if bom else "") + output.getvalue()
    current = raw.decode("utf-8")
    changed = current != expected
    if changed and not check:
        path.write_text(expected, encoding="utf-8", newline="")
    return changed


def sync_csv_sources(check: bool) -> bool:
    stages = {
        row["asset_id"]: row
        for row in csv_rows(RESOURCE_ROOT / "asset_native_wearable_stages.csv")
    }
    if len(stages) != 21:
        raise RuntimeError(f"expected 21 native wearable stages, found {len(stages)}")

    def set_field(row: list[str], headers: list[str], key: str, value: str) -> bool:
        index = headers.index(key)
        if row[index] == value:
            return False
        row[index] = value
        return True

    def update_catalog(values, row, headers):
        stage = stages.get(values.get("asset_id", ""))
        if not stage:
            return False
        changed = False
        projections = {
            "display_name": stage["display_name"],
            "primary_model": stage["body_model"],
            "attachment_models": "",
            "environment_particles": "",
            "default_sequence": "idle",
            "model_scale": "1",
            "model_skin": "",
            "material_group": "",
            "notes": stage["notes"]
                + "；原Building承载英雄主体，CSV模型投影为prop_dynamic组件。",
            "attachment_entity_class": "",
            "attachment_ids": "",
            "environment_particle_owners": "",
            "portrait_unit_name": stage["hero_unit_name"],
            "portrait_item_def": "",
        }
        for key, value in projections.items():
            changed = set_field(row, headers, key, value) or changed
        return changed

    changed = rewrite_csv(
        RESOURCE_ROOT / "asset_catalog.csv",
        update_catalog,
        check,
    )

    def update_wearable(values, row, headers):
        model_path = values.get("model_path", "").strip()
        item_def = values.get("item_def", "").strip()
        if bool(model_path) != bool(item_def):
            raise RuntimeError(
                "native wearable model_path and item_def must be both present "
                f"or both empty: {values.get('wearable_key', '')}"
            )
        changed = False
        for key, value in {
            "entity_class": "prop_dynamic",
            "attach_mode": "bone_merge",
        }.items():
            changed = set_field(row, headers, key, value) or changed
        return changed

    changed = rewrite_csv(
        RESOURCE_ROOT / "asset_native_wearables.csv",
        update_wearable,
        check,
    ) or changed
    wearable_rows = csv_rows(RESOURCE_ROOT / "asset_native_wearables.csv")
    changed = sync_component_csv(stages, wearable_rows, check) or changed

    routed_assets: set[str] = set()
    for path in sorted(TOWER_ROOT.glob("tower_class_*.csv")):
        def update_route(values, row, headers):
            asset_id = values.get("model_asset_id", "")
            stage = stages.get(asset_id)
            if not stage:
                return False
            routed_assets.add(asset_id)
            return set_field(row, headers, "model_name", stage["body_model"])

        changed = rewrite_csv(path, update_route, check) or changed
    if routed_assets != set(stages):
        missing = sorted(set(stages).difference(routed_assets))
        extra = sorted(routed_assets.difference(stages))
        raise RuntimeError(
            f"native wearable route projection mismatch missing={missing} extra={extra}"
        )
    return changed


def tower_routes() -> tuple[list[str], dict[str, str]]:
    assets: list[str] = []
    projectiles: dict[str, str] = {}
    for path in sorted(TOWER_ROOT.glob("tower_class_*.csv")):
        for row in csv_rows(path):
            asset_id = row.get("model_asset_id", "").strip()
            if not asset_id:
                continue
            if asset_id not in assets:
                assets.append(asset_id)
            projectile = row.get("projectile_model", "").strip()
            if projectile and asset_id not in projectiles:
                projectiles[asset_id] = projectile
    if len(assets) != 21:
        raise RuntimeError(f"expected 21 tower stage assets, found {len(assets)}")
    return assets, projectiles


def block_end(text: str, unit_name: str) -> tuple[int, int]:
    match = re.search(rf'(?m)^[ \t]*"{re.escape(unit_name)}"[ \t]*', text)
    if not match:
        raise RuntimeError(f"unit block missing: {unit_name}")
    start = match.start()
    opening = text.find("{", match.end())
    if opening < 0:
        raise RuntimeError(f"unit block has no opening brace: {unit_name}")
    depth = 0
    for index in range(opening, len(text)):
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
            if depth == 0:
                end = index + 1
                while end < len(text) and text[end] in " \t":
                    end += 1
                if text.startswith("\r\n", end):
                    end += 2
                elif text.startswith("\n", end):
                    end += 1
                return start, end
    raise RuntimeError(f"unit block is unbalanced: {unit_name}")


def render_block(
    asset: dict[str, str],
    wearables: list[dict[str, str]],
    projectile: str,
    newline: str,
) -> str:
    unit_name = asset["async_unit_name"].strip()
    lines = [
        f'    "{unit_name}"',
        "    {",
        '        "BaseClass"              "npc_dota_creature"',
        f'        "Model"                  "{asset["primary_model"].strip()}"',
        '        "ModelScale"             "1"',
        '        "Level"                  "1"',
        '        "ConsideredHero"         "0"',
        '        "HasInventory"           "0"',
        '        "HealthBarOffset"        "-1"',
        '        "StatusHealth"           "1"',
        '        "StatusMana"             "0"',
        '        "MovementCapabilities"   "DOTA_UNIT_CAP_MOVE_NONE"',
        '        "AttackCapabilities"     "DOTA_UNIT_CAP_NO_ATTACK"',
        '        "BoundsHullName"         "DOTA_HULL_SIZE_SMALL"',
        '        "VisionDaytimeRange"     "0"',
        '        "VisionNighttimeRange"   "0"',
    ]
    if projectile:
        lines.append(f'        "ProjectileModel"        "{projectile}"')

    model_paths = [
        row["model_path"].strip()
        for row in wearables
        if row.get("model_path", "").strip()
    ]
    if model_paths:
        lines.extend(['        "precache"', "        {"])
        for model_path in model_paths:
            lines.append(f'            "model" "{model_path}"')
        lines.append("        }")

    # Native wearables are created at runtime as explicit bone-merged child
    # entities. The proxy KV only owns the body model and its precache list;
    # Creature.AttachWearables is not reliable for npc_dota_creature proxies.
    lines.append("    }")
    return newline.join(lines)


def expected_text() -> str:
    raw = NPC_UNITS.read_bytes()
    bom = raw.startswith(b"\xef\xbb\xbf")
    text = raw.decode("utf-8-sig")
    newline = "\r\n" if "\r\n" in text else "\n"

    route_assets, projectiles = tower_routes()
    catalog = {row["asset_id"]: row for row in csv_rows(RESOURCE_ROOT / "asset_catalog.csv")}
    wearable_rows = csv_rows(RESOURCE_ROOT / "asset_native_wearables.csv")
    wearables: dict[str, list[dict[str, str]]] = {}
    for row in wearable_rows:
        wearables.setdefault(row["asset_id"], []).append(row)
    for rows in wearables.values():
        rows.sort(key=lambda row: (int(row.get("sort_order") or 0), row["wearable_key"]))

    for asset_id in route_assets:
        asset = catalog.get(asset_id)
        if not asset:
            raise RuntimeError(f"tower stage references missing asset: {asset_id}")
        if not asset.get("async_unit_name", "").strip():
            raise RuntimeError(f"tower stage asset has no carrier unit: {asset_id}")
        rows = wearables.get(asset_id)
        if not rows:
            raise RuntimeError(f"tower stage has no native wearable declaration: {asset_id}")
        replacement = render_block(asset, rows, projectiles.get(asset_id, ""), newline)
        start, end = block_end(text, asset["async_unit_name"].strip())
        text = text[:start] + replacement + newline + text[end:]

    return ("\ufeff" if bom else "") + text


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    csv_changed = sync_csv_sources(args.check)
    expected = expected_text()
    current = NPC_UNITS.read_bytes().decode("utf-8")
    if args.check:
        if csv_changed or current != expected:
            print("TOWER_NATIVE_WEARABLE_UNITS_OUT_OF_DATE")
            return 1
        print("TOWER_NATIVE_WEARABLE_UNITS_CURRENT")
        return 0
    NPC_UNITS.write_text(expected, encoding="utf-8", newline="")
    print("TOWER_NATIVE_WEARABLE_UNITS_WRITTEN assets=21")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
