"""Build the unified tooltip CSV and Lua index from existing CSV sources."""
from __future__ import annotations
import csv
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CSV_ROOT = ROOT / "data" / "csv"
OUT_CSV = CSV_ROOT / "公共规则" / "tooltip_definitions.csv"
OUT_LUA = ROOT / "scripts" / "vscripts" / "config" / "generated" / "tooltip_definitions.lua"

FIELDS = ["tooltip_id", "tooltip_type", "id", "name", "needwood", "needgold", "desc", "icon", "source_id"]

def read_csv(path: Path):
    raw = path.read_bytes()
    for encoding in ("utf-8-sig", "utf-8", "gb18030", "gbk"):
        try:
            text = raw.decode(encoding)
            break
        except UnicodeDecodeError:
            text = None
    if text is None:
        raise RuntimeError(f"无法读取 CSV: {path}")
    rows = list(csv.DictReader(text.splitlines()))
    return [r for r in rows if r and r.get(next(iter(r), ""), "").strip() and not next(iter(r.values()), "").startswith("#")]

def clean(value):
    return (value or "").strip()

def add(out, tooltip_id, tooltip_type, item_id, name, wood, gold, desc, icon, source_id):
    if not tooltip_id:
        return
    out[tooltip_id] = {
        "tooltip_id": tooltip_id,
        "tooltip_type": tooltip_type,
        "id": item_id,
        "name": clean(name) or item_id,
        "needwood": clean(wood) or "0",
        "needgold": clean(gold) or "0",
        "desc": clean(desc),
        "icon": clean(icon),
        "source_id": source_id,
    }

def lua_string(value):
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"').replace("\r", "\\r").replace("\n", "\\n") + '"'

def main():
    out = {}
    existing_tooltips = {
        clean(row.get("tooltip_id")): row
        for row in read_csv(OUT_CSV)
        if clean(row.get("tooltip_id")).startswith("ability:ability_build_")
        or clean(row.get("tooltip_id")).startswith("ability:ultimate_tower_passive_")
        or clean(row.get("tooltip_id")) == "ability:ability_survival_rogue_reward"
    }
    for row in existing_tooltips.values():
        add(
            out,
            clean(row.get("tooltip_id")),
            clean(row.get("tooltip_type")),
            clean(row.get("id")),
            row.get("name"),
            row.get("needwood"),
            row.get("needgold"),
            row.get("desc"),
            row.get("icon"),
            row.get("source_id"),
        )
    hero = read_csv(CSV_ROOT / "英雄系统" / "hero_skill_definitions.csv")
    for row in hero:
        if clean(row.get("enabled", "1")).lower() in {"0", "false", "no"}:
            continue
        ability = clean(row.get("ability_name"))
        add(out, "ability:" + ability, "ability", ability, row.get("display_name"), "0", "0", row.get("description"), row.get("icon_name"), row.get("skill_id"))

    tower = read_csv(CSV_ROOT / "建筑与工人系统" / "防御塔" / "tower_skill_definitions.csv")
    for row in tower:
        if clean(row.get("enabled", "1")).lower() in {"0", "false", "no"}:
            continue
        skill_id = clean(row.get("skill_id"))
        add(out, "ability:" + skill_id, "ability", skill_id, row.get("skill_name"), "0", "0", row.get("description"), "", skill_id)

    worker_skills = read_csv(
        CSV_ROOT / "建筑与工人系统" / "worker_skill_definitions.csv"
    )
    for row in worker_skills:
        if clean(row.get("enabled", "1")).lower() in {"0", "false", "no"}:
            continue
        skill_id = clean(row.get("skill_id"))
        add(
            out,
            "ability:" + skill_id,
            "ability",
            skill_id,
            row.get("name"),
            "0",
            "0",
            row.get("description"),
            row.get("icon"),
            row.get("source") or skill_id,
        )

    lumberjack_fusions = read_csv(
        CSV_ROOT / "建筑与工人系统" / "lumberjack_fusion_definitions.csv"
    )
    for row in lumberjack_fusions:
        if clean(row.get("enabled", "1")).lower() in {"0", "false", "no"}:
            continue
        ability = clean(row.get("ability_id"))
        if not ability:
            continue
        add(
            out,
            "ability:" + ability,
            "ability",
            ability,
            row.get("display_name"),
            row.get("wood_cost"),
            row.get("gold_cost"),
            row.get("notes"),
            "furion_force_of_nature",
            row.get("fusion_id") or ability,
        )

    lumberjack_personalities = read_csv(
        CSV_ROOT / "建筑与工人系统" / "lumberjack_personality_definitions.csv"
    )
    for row in lumberjack_personalities:
        if clean(row.get("enabled", "1")).lower() in {"0", "false", "no"}:
            continue
        ability = clean(row.get("ability_name"))
        if not ability:
            continue
        add(
            out,
            "ability:" + ability,
            "ability",
            ability,
            row.get("name"),
            "0",
            "0",
            row.get("description"),
            "",
            row.get("skill_id") or ability,
        )

    altar_actions = read_csv(CSV_ROOT / "商店系统" / "altar_actions.csv")
    for row in altar_actions:
        if clean(row.get("enabled", "1")).lower() in {"0", "false", "no"}:
            continue
        ability = clean(row.get("ability_name"))
        if not ability:
            continue
        add(out, "ability:" + ability, "ability", ability,
            row.get("name"), row.get("wood_cost"), row.get("gold_cost"),
            row.get("description"), row.get("ability_texture"),
            row.get("action_id"))

    building_definitions = read_csv(
        CSV_ROOT / "建筑与工人系统" / "building_definitions.csv"
    )
    building_levels = read_csv(
        CSV_ROOT / "建筑与工人系统" / "building_levels.csv"
    )
    level_one_by_unit = {
        clean(row.get("building_id")): row
        for row in building_levels
        if clean(row.get("level")) == "1"
    }
    for row in building_definitions:
        ability = clean(row.get("builder_ability"))
        unit_name = clean(row.get("unit_name"))
        if not ability or not unit_name:
            continue
        level_one = level_one_by_unit.get(unit_name, {})
        existing = existing_tooltips.get("ability:" + ability)
        if not existing:
            continue
        add(
            out, "ability:" + ability, "ability", ability,
            existing.get("name"),
            level_one.get("wood_cost"), level_one.get("gold_cost"),
            existing.get("desc"), existing.get("icon"), row.get("building_id"),
        )

    rogue_rules = read_csv(CSV_ROOT / "肉鸽奖励系统" / "rogue_reward_rules.csv")
    rogue_reward = next(
        (row for row in rogue_rules
         if clean(row.get("rule_id")) == "default_rogue_reward"
         and clean(row.get("enabled", "1")).lower() not in {"0", "false", "no"}),
        None,
    )
    if rogue_reward:
        add(
            out,
            "ability:ability_survival_rogue_reward",
            "ability",
            "ability_survival_rogue_reward",
            rogue_reward.get("tooltip_name"),
            "0",
            "0",
            rogue_reward.get("tooltip_desc"),
            rogue_reward.get("tooltip_icon"),
            "builder_rogue_reward",
        )

    catalog = read_csv(CSV_ROOT / "物品系统" / "content_catalog.csv")
    catalog_by_id = {clean(row.get("content_id")): row for row in catalog}
    for row in catalog:
        content_id = clean(row.get("content_id"))
        if clean(row.get("enabled", "1")).lower() in {"0", "false", "no"}:
            continue
        add(out, "inventory_item:" + content_id, "inventory_item", content_id, row.get("name"), "0", "0", row.get("description"), row.get("icon"), content_id)

    weapons = read_csv(CSV_ROOT / "物品系统" / "weapon_definitions.csv")
    for row in weapons:
        content_id = clean(row.get("content_id"))
        if clean(row.get("enabled", "1")).lower() in {"0", "false", "no"}:
            continue
        catalog_row = catalog_by_id.get(content_id, {})
        descriptions = []
        for field in ("description", "listed_stats", "recipe_summary"):
            text = clean(row.get(field))
            if text and text not in descriptions:
                descriptions.append(text)
        add(out, "inventory_item:" + content_id, "inventory_item", content_id,
            row.get("display_name") or catalog_row.get("name"), "0", "0",
            "\n".join(descriptions),
            row.get("icon_name") or catalog_row.get("icon"), content_id)

    items = read_csv(CSV_ROOT / "物品系统" / "item_definitions.csv")
    for row in items:
        content_id = clean(row.get("content_id"))
        if clean(row.get("enabled", "1")).lower() in {"0", "false", "no"}:
            continue
        catalog_row = catalog_by_id.get(content_id, {})
        add(out, "inventory_item:" + content_id, "inventory_item", content_id,
            catalog_row.get("name"), "0", "0", row.get("description"),
            row.get("icon_name") or catalog_row.get("icon"), content_id)

    OUT_CSV.parent.mkdir(parents=True, exist_ok=True)
    with OUT_CSV.open("w", encoding="utf-8-sig", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(FIELDS)
        writer.writerow(["#中文名:提示ID,提示分类,业务ID,名称,所需木材,所需金币,描述,图标,来源ID"])
        writer.writerow(["#types:string,enum,string,string,number,number,string,string,string"])
        for key in sorted(out):
            writer.writerow([out[key][field] for field in FIELDS])

    OUT_LUA.parent.mkdir(parents=True, exist_ok=True)
    lines = ["-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.", "local M = {}", "M.rows = {"]
    for key in sorted(out):
        row = out[key]
        lines.append("    { " + ", ".join(f"{field} = {lua_string(row[field])}" for field in FIELDS) + " },")
    lines += ["}", "M.by_id = {}", "for _, row in ipairs(M.rows) do M.by_id[row.tooltip_id] = row end", "return M", ""]
    OUT_LUA.write_text("\n".join(lines), encoding="utf-8", newline="\n")
    print(f"TOOLTIP_BUILD_PASS rows={len(out)} csv={OUT_CSV} lua={OUT_LUA}")

if __name__ == "__main__":
    main()
