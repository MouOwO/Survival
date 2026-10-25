"""Extract a reference snapshot from an original map, without executing its code.

Example:
  python tools/extract_original_monsters.py --source original.w3x --output output/original

The detailed rule adapters deliberately accept only the reviewed JASS revision.
No runtime configuration, model, icon, archive or gameplay file is written.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
from collections import Counter
from decimal import Decimal, ROUND_FLOOR
from pathlib import Path

import war3_extract_units as units_parser
from war3_extract import mpq, nonwave, waves
from war3_extract.workbook import write_workbook

EXPECTED_JASS = "52e54249dbe147fbcb042636fe991ac493ed9eb96afee56403b9e0ba413448e3"
EXTRA_MEMBERS = [r"Units\ItemData.slk", "war3mapMisc.txt", "war3map.w3i",
                 r"Units\AbilityData.slk", r"Units\UpgradeData.slk",
                 "war3map.w3a", "war3map.w3q", "war3map.w3t"]
UNIT_FIELDS = ["raw_id", "name_plain", "hp", "armor", "hp_regen", "movement_speed",
    "collision_size", "level", "primary_attribute", "strength", "agility", "intelligence",
    "strength_growth", "agility_growth", "intelligence_growth", "model", "model_scale", "icon",
    "movement_type", "armor_type", "armor_per_upgrade", "upgrade_ids", "attack_enabled_mask", "acquisition_range",
    "attack1_base", "attack1_dice", "attack1_sides", "attack1_min", "attack1_max",
    "attack1_interval", "attack1_range", "attack1_type", "attack2_base", "attack2_dice",
    "attack2_sides", "attack2_interval", "attack2_min", "attack2_max", "attack2_range", "attack2_type",
    "attack1_upgrade_bonus", "attack2_upgrade_bonus", "ability_ids", "hero_ability_ids", "source_rows"]
NOTES = [
    "只读原图参考提取：未载入游戏配置，也未执行原图脚本或原生 DLL。",
    "原图缓存的发行版本未知；文件名、SHA256 和 JASS 导出时间只用于确定本次快照。",
    "全部单位包含英雄、建筑和辅助物；分类页只列已通过脚本确认的出生用途，不能把1370条全部视为怪物。",
    "SLK HP、攻击基数组件、含骰子武器区间、出生后 setter 乘积分别列出；攻击基数不等于面板攻击或最终实伤。",
    "英雄 HP 预测包含 Misc.StrHitPointBonus 和初始 STR；原生取整、英雄升级、技能、装备、光环和伤害事件仍需实机验证。",
    "217项菜单模式相容的难度不代表账号全部解锁；另有18项公式分支不与该模式选择入口相容。",
    "主难度公式235条；另存64条旧按钮或未绑定分支，不能将其覆盖主分支或当作新增难度。",
    "名义波次组合假设全局波次未被下一波改写且未使用终局快捷道具；极寒部分难度会存在计时器重叠。",
    "前三波首次计时回调只扣剩余数、不出生；天灾普通/精英为随机试验次数，不能把概率换算为固定怪物数量。",
    "存档挑战的 SLK 乘积已经乘过入场物品 scale；不可再次乘 scale 或难度倍率，也不可冒充原生面板最终值。",
    "现有 human_spec 与用户修正版继续作为游戏契约；原图差异只登记，不自动覆盖。",
    "十戒后四只原图 HP 比用户修正版多4960；保留现有游戏修正。首次生成与重生分支差别按原图分别记录。",
    "属性赋值索引是静态调用清单，不代表所有技能、升级、装备及事件已完成语义还原。",
]
HEADERS = {"raw_id": "单位ID", "rawid": "单位ID", "name": "名称", "name_plain": "名称",
    "class": "类别", "category": "类别", "key": "条目", "field": "字段", "current": "现配置",
    "original": "原图", "reason": "说明", "decision": "处理", "source": "来源", "stat_sources": "基础属性来源",
    "mode_id": "模式ID", "mode_name": "模式", "difficulty": "难度N", "wave": "波次", "role": "怪物角色",
    "hp": "基础HP", "armor": "基础护甲", "hp_slk": "基础HP", "armor_slk": "基础护甲",
    "attack_base_slk": "基础攻击组件", "attack1_base": "攻击1基数组件", "attack1_dice": "攻击1骰子个数",
    "attack1_sides": "攻击1骰子面数", "attack1_min": "攻击1武器下限", "attack1_max": "攻击1武器上限",
    "attack1_interval": "攻击1间隔秒", "attack1_range": "攻击1距离", "attack1_type": "攻击1类型",
    "hp_slk_product": "HP原表乘积", "hp_native_prediction": "HP含初始力量预测",
    "attack_base_setter_prediction": "攻击基数预测非面板", "attack_base_slk_product": "攻击基数组件乘积",
    "armor_slk_product": "护甲原表乘积", "armor_native_prediction": "护甲预测", "armor_floor": "护甲向下取整",
    "hp_regen": "基础回血", "movement_speed": "移速", "collision_size": "碰撞体积", "level": "原表等级",
    "primary_attribute": "主属性", "strength": "力量", "agility": "敏捷", "intelligence": "智力",
    "strength_growth": "力量成长", "agility_growth": "敏捷成长", "intelligence_growth": "智力成长",
    "model": "模型路径", "model_scale": "模型比例", "icon": "图标路径", "upgrade_ids": "升级ID",
    "armor_per_upgrade": "每级升级护甲", "armor_type": "护甲类型", "movement_type": "移动类型",
    "attack2_base": "攻击2基数组件", "attack2_dice": "攻击2骰子个数", "attack2_sides": "攻击2骰子面数",
    "attack2_min": "攻击2武器下限", "attack2_max": "攻击2武器上限", "attack2_interval": "攻击2间隔秒",
    "attack2_range": "攻击2距离", "attack2_type": "攻击2类型",
    "count": "数量", "initial_count": "初始数量", "count_scope": "数量范围", "spawn_trials": "随机试验次数",
    "probability_percent": "分支概率百分比", "formula_ref": "公式引用", "source_refs": "来源索引",
    "selector_mode_compatible": "模式入口相容", "classification": "难度分支分类",
    "multiplier_exact_decimal": "精确倍率", "hp_multiplier": "HP总倍率", "attack_base_multiplier": "攻击基数总倍率",
    "armor_multiplier": "护甲总倍率", "rule_id": "公式条目", "status": "参考状态"}
ROLE_LABELS = {"ordinary": "普通", "ordinary_scourge": "天灾普通", "elite_scourge": "天灾精英",
    "leader_non_scourge": "首怪", "leader_scourge": "天灾首怪", "leader": "首怪", "assault_boss": "进攻BOSS"}


def read_json(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def save_json(path, payload):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2, allow_nan=False) + "\n", encoding="utf-8")


def stat_write_inventory(text):
    """Index anchored native calls; do not execute or guess dynamic targets."""
    native = re.compile(r"^call\s+(SetUnitState|EXSetUnitState|SetHeroStr|SetHeroAgi|SetHeroInt|"
        r"SetHeroLevel|SetUnitAbilityLevel|UnitAddAbility|SetPlayerTechResearched|"
        r"SetPlayerTechMaxAllowed|SetUnitMoveSpeed|SetUnitScale)\((.*)\)\s*$")
    function, result = None, []
    for line, original in enumerate(text.splitlines(), 1):
        value = original.strip()
        match = re.match(r"^function\s+(\w+)\s+takes\b", value)
        if match:
            function = match[1]
        match = native.fullmatch(value)
        if match:
            result.append({"line": line, "function": function, "native": match[1],
                "arguments": match[2], "scope": "static call; target/guards not resolved by this index"})
        if value == "endfunction":
            function = None
    return result


def compact_units(data):
    return [{**{field: row.get(field) for field in UNIT_FIELDS},
        "stat_sources": {key: row["provenance"].get(key) for key in
            ["hp", "armor", "attack1_base", "attack1_dice", "attack1_sides", "attack1_interval", "strength",
             "model", "model_scale", "icon", "upgrade_ids", "armor_per_upgrade", "strength_growth", "agility_growth", "intelligence_growth"]}}
        for row in data["units"]]


def classified_rows(units, wave_rules, challenge_rules):
    index = {u["raw_id"]: u for u in units["units"]}
    rows = []
    for r in wave_rules["wave_unit_arrays"]:
        unit = index[r["rawid"]]
        rows.append({"class": r["array"], "key": r["wave"], "raw_id": r["rawid"],
            "name": unit["name_plain"], "hp_slk": unit["hp"], "armor_slk": unit["armor"],
            "attack_base_slk": unit["attack1_base"], "source": r["source"]})
    for r in challenge_rules["units"]:
        unit = index[r["raw_id"]]
        rows.append({"class": r["class"], "key": r["key"], "raw_id": r["raw_id"],
            "name": r["name"], "hp_slk": unit["hp"], "armor_slk": unit["armor"],
            "attack_base_slk": unit["attack1_base"], "count": r.get("initial_count"),
            "count_scope": r.get("count_scope"), "formula_ref": r.get("formula_ref"),
            "source": r.get("source")})
    return rows


def standard_n2_challenges(units, challenge_rules, difficulties):
    """Transparent SLK products for one auditable tier, never panel claims."""
    index = {u["raw_id"]: u for u in units["units"]}
    row = next(r for r in difficulties["rows"] if r["mode_id"] == 1 and r["difficulty"] == 2
        and r.get("classification", "primary_dialog_row") == "primary_dialog_row")
    mult = {k: Decimal(v) for k, v in row["multiplier_exact_decimal"].items()}
    result = []
    for record in challenge_rules["units"]:
        if record["class"] not in {"rebirth", "ten_commandments", "wild_material", "four_rooms"}:
            continue
        unit = index[record["raw_id"]]
        hp = Decimal(str(unit["hp"])) * mult["xgdg_oBAA"]
        armor = Decimal(str(unit["armor"])) * mult["xgdg_MBAA"]
        attack = Decimal(str(unit["attack1_base"])) * Decimal("2.2")
        result.append({"class": record["class"], "key": record["key"], "raw_id": record["raw_id"],
            "name": record["name"], "mode": "常规", "difficulty": 2,
            "hp_slk_product": str(hp), "armor_slk_product": str(armor),
            "armor_floor": str(armor.to_integral_value(rounding=ROUND_FLOOR)),
            "attack_base_slk_product": str(attack), "attack_interval_slk": unit["attack1_interval"],
            "hp_factor": str(mult["xgdg_oBAA"]), "armor_factor": str(mult["xgdg_MBAA"]),
            "attack_factor": "2.2", "scope": "initial spawn, SLK component product; not native panel validation"})
    return result


def compact_difficulties(data, primary=True):
    fields = ["mode_id", "mode_name", "difficulty", "selector_mode_compatible",
        "multiplier_exact_decimal", "source", "button_key", "classification"]
    return [{k: row.get(k) for k in fields} for row in data["rows"]
        if (row.get("classification") == "primary_dialog_row") == primary]


def workbook_rows(rows):
    return [{HEADERS.get(k, k): ROLE_LABELS.get(v, v) if k == "role" else v for k, v in r.items()} for r in rows]


def plain_csv(path, rows):
    columns = list(dict.fromkeys(k for row in rows for k in row))
    def cell(value):
        if isinstance(value, (list, dict)):
            value = json.dumps(value, ensure_ascii=False, separators=(",", ":"))
        if isinstance(value, str) and value[:1] in "=+-@" and value:
            return "'" + value
        return value
    with Path(path).open("w", encoding="utf-8-sig", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=columns)
        writer.writeheader()
        writer.writerows({k: cell(v) for k, v in row.items()} for row in rows)


def extract(source, output, current_spec=None, reference_output=None):
    from war3_extract.comparison import compare_current
    from war3_extract.wave_reference import build_reference
    source, output = Path(source).resolve(), Path(output).resolve()
    blobs, manifest = units_parser.read_members(source, [])
    jass_blob = blobs.get("war3map.j") or blobs.get(r"scripts\war3map.j")
    if not jass_blob or hashlib.sha256(jass_blob).hexdigest() != EXPECTED_JASS:
        raise ValueError("unsupported_source_revision: reviewed JASS SHA256 does not match")
    consumed = manifest["consumed_bytes"]
    with source.open("rb") as stream:
        archive = mpq.MPQ(stream, source.stat().st_size)
        for member in EXTRA_MEMBERS:
            found = archive.lookup(member)
            if not found:
                manifest["members"].append({"member": member, "present": False})
                continue
            blob = archive.extract(member, archive.blocks[found[0]["block_index"]], mpq.LIMIT - consumed)
            consumed += len(blob)
            blobs[member] = blob
            manifest["members"].append({"member": member, "present": True,
                "bytes": len(blob), "sha256": hashlib.sha256(blob).hexdigest()})
    manifest["consumed_bytes"] = consumed
    if consumed > mpq.LIMIT:
        raise ValueError("aggregate extracted data exceeds 32 MiB")
    raw = output / "raw"
    for member, blob in blobs.items():
        target = raw.joinpath(*member.split("\\"))
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(blob)
    jass = raw / "war3map.j"
    if not jass.is_file():
        jass = raw / "scripts" / "war3map.j"
    data, units_manifest, unknowns, patches = units_parser.build_units(blobs)
    units_manifest["extraction"] = manifest
    units_parser.write_outputs(output / "units", data, units_manifest, unknowns, patches)
    waves.extract(jass, output / "waves", raw / "war3mapMisc.txt")
    nonwave.run(jass, raw, output / "units" / "units_base.json", output / "challenges")
    wave_rules = read_json(output / "waves" / "wave_rules.json")
    difficulty = read_json(output / "waves" / "difficulty_table.json")
    compositions = read_json(output / "waves" / "nominal_wave_compositions.json")
    schedules = read_json(output / "waves" / "schedule_profiles.json")
    challenge = read_json(output / "challenges" / "challenge_rules.json")
    misc = (raw / "war3mapMisc.txt").read_text(encoding="utf-8-sig")
    wave_reference = build_reference(data, wave_rules, difficulty, compositions, misc)
    comparison = compare_current(data, wave_rules, challenge, read_json(current_spec)) if current_spec else {
        "reference_only": True, "differences": [], "limits": ["current spec not supplied"]}
    writes = stat_write_inventory(jass_blob.decode("utf-8-sig"))
    units_compact = compact_units(data)
    classified = classified_rows(data, wave_rules, challenge)
    n2 = standard_n2_challenges(data, challenge, difficulty)
    diff_compact = compact_difficulties(difficulty)
    alternate_difficulties = compact_difficulties(difficulty, primary=False)
    archive = [u for u in challenge["units"] if u["class"].startswith("archive_")]
    summary = {"schema": "original_monster_snapshot/v1", "reference_only": True,
        "game_data_modified": False, "map_code_executed": False,
        "source_archive": source.name, "source_sha256": manifest["source_sha256"],
        "jass_sha256": EXPECTED_JASS, "jass_export_header": jass_blob.decode("utf-8-sig").splitlines()[0],
        "release_version": None, "counts": {"all_units": len(data["units"]),
            "classified_bindings": len(classified), "classified_distinct_rawids": len({u["raw_id"] for u in classified}),
            "difficulty_formula_rows": len(diff_compact),
            "alternate_difficulty_branches": len(alternate_difficulties),
            "selector_mode_compatible_rows": sum(bool(d["selector_mode_compatible"]) for d in diff_compact),
            "nominal_wave_rows": len(compositions["rows"]), "nonwave_bindings": len(challenge["units"]),
            "archive_challenges": len(archive), "wave_reference_rows": len(wave_reference["rows"]),
            "stat_native_call_index": len(writes), "differences": len(comparison["differences"])},
        "nonwave_classes": dict(Counter(u["class"] for u in challenge["units"])),
        "notes": NOTES,
        "limits": {"waves": wave_rules["unresolved"],
            "wave_reference": wave_reference["limitations"] + wave_reference["unresolved"] + wave_reference["coverage_issues"],
            "challenges": challenge["unresolved_or_original_inconsistencies"],
            "unit_parse_issues": unknowns["issues"],
            "dynamic_creation_calls": len(unknowns["dynamic_creation_calls"])}}
    # A compact, functional-facts snapshot may be checked in; raw script/assets stay in output.
    reference = {"summary": summary, "units": units_compact, "classified": classified,
        "difficulty": diff_compact, "wave_unit_arrays": wave_rules["wave_unit_arrays"],
        "difficulty_alternate_branches": alternate_difficulties,
        "wave_formulas": wave_rules["derived_rules"], "schedule_profiles": schedules["profiles"],
        "nonwave_shared_rules": challenge["shared_rules"], "nonwave_units": challenge["units"],
        "standard_n2_challenges": n2}
    save_json(output / "reference.json", reference)
    save_json(output / "summary.json", summary)
    save_json(output / "comparison.json", comparison)
    save_json(output / "wave_reference.json", wave_reference)
    save_json(output / "stat_write_inventory.json", {"source_sha256": EXPECTED_JASS, "rows": writes})
    save_json(output / "source_manifest.json", manifest)
    # Exclude extensive raw script guards and repeated source snippets from worksheets.
    composition_rows = [{k: v for k, v in row.items() if k not in {"rule_sources", "rule_sources_refs", "array_sources"}}
                        for row in compositions["rows"]]
    timer_rows = [{**{k: profile[k] for k in ["mode_id", "mode_name", "difficulty", "total_waves",
        "assault_boss_waves", "wave_period_seconds"]}, **band}
        for profile in schedules["profiles"] for band in profile["bands"]]
    sheets = [("分类与基础", classified), ("全部单位基础", units_compact), ("难度倍率", diff_compact),
        ("旧按钮与未绑定分支", alternate_difficulties),
        ("波次单位绑定", wave_rules["wave_unit_arrays"]), ("名义波次组合", composition_rows),
        ("波次公式", [{"rule_id": k, "definition": v} for k, v in wave_rules["derived_rules"].items()]),
        ("波次计时", timer_rows),
        ("出生属性参考", wave_reference["rows"]), ("非波次规则", challenge["units"]),
        ("非波次共用公式", [{"rule": k, **v} for k, v in challenge["shared_rules"].items()]),
        ("存档挑战29项", archive), ("常规N2非波次", n2),
        ("与当前配置差异", comparison["differences"]),
        ("未对应条目", comparison.get("unmatched", [])),
        ("原图行为与未确认", [{"category": k, "detail": v} for k, values in summary["limits"].items()
            for v in (values if isinstance(values, list) else [values])]),
        ("属性调用索引", writes)]
    tables = output / "tables"
    tables.mkdir(exist_ok=True)
    for name, rows in sheets:
        plain_csv(tables / (name + ".csv"), rows)
    book = write_workbook(output / "原图怪物提取与差异对照.xlsx",
        [(name, workbook_rows(rows)) for name, rows in sheets], NOTES)
    save_json(output / "workbook_manifest.json", book)
    if reference_output:
        destination = Path(reference_output)
        save_json(destination / "reference.json", reference)
        save_json(destination / "comparison.json", {k: v for k, v in comparison.items() if k != "matches"})
        # Machine-independent member evidence; no local directory or raw original code.
        save_json(destination / "source_manifest.json", {"source_archive": source.name,
            "source_sha256": manifest["source_sha256"], "jass_sha256": EXPECTED_JASS,
            "members": [{k: v for k, v in r.items() if k != "input"} for r in manifest["members"]]})
    return summary


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--current-spec", type=Path)
    parser.add_argument("--reference-output", type=Path,
        help="optional destination for compact reference facts; never used by the runtime loader")
    args = parser.parse_args(argv)
    try:
        result = extract(args.source, args.output, args.current_spec, args.reference_output)
    except (ValueError, OSError, KeyError) as error:
        print(json.dumps({"error": str(error)}, ensure_ascii=True))
        return 1
    print(json.dumps({"counts": result["counts"], "reference_only": True}, ensure_ascii=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
