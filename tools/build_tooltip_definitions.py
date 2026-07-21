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

    catalog = read_csv(CSV_ROOT / "物品系统" / "content_catalog.csv")
    for row in catalog:
        content_id = clean(row.get("content_id"))
        if clean(row.get("enabled", "1")).lower() in {"0", "false", "no"}:
            continue
        add(out, "inventory_item:" + content_id, "inventory_item", content_id, row.get("name"), "0", "0", row.get("description"), row.get("icon"), content_id)

    shops = read_csv(CSV_ROOT / "商店系统" / "shop_entries.csv")
    for row in shops:
        if clean(row.get("enabled", "1")).lower() in {"0", "false", "no"}:
            continue
        entry_id = clean(row.get("shop_entry_id"))
        add(out, "shop_item:" + entry_id, "shop_item", clean(row.get("content_id")), row.get("display_name"), row.get("wood_cost"), row.get("gold_cost"), row.get("notes"), "", entry_id)

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
