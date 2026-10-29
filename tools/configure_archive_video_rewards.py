"""Configure reviewed archive rewards; unseen expansion values are project authored.

Permanent IDs are preserved. Does not build configs, touch runtime bundles, or deploy.
"""
from __future__ import annotations
import copy
import csv
import io
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "data/csv/存档系统"


def read(name):
    lines = (BASE / (name + ".csv")).read_text(encoding="utf-8-sig").splitlines()
    header = next(csv.reader([lines[0]]))
    types = next(line[7:].split(",") for line in lines if line.startswith("#types:"))
    rows = list(csv.DictReader(io.StringIO("\n".join(line for line in lines if not line.startswith("#")))))
    return header, types, rows


def write(name, header, types, rows):
    assert len(header) == len(types)
    assert len({row[header[0]] for row in rows}) == len(rows), name
    with (BASE / (name + ".csv")).open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=header, lineterminator="\n")
        writer.writeheader()
        stream.write("#types:" + ",".join(types) + "\n")
        for row in rows:
            writer.writerow({key: row.get(key, "") or "" for key in header})


def main():
    names = ["霜之哀伤", "米奈希尔之力", "埃辛诺斯战刃", "灰烬使者", "血吼",
             "索利达尔群星之怒", "雷霆之怒逐风者的祝福之剑", "阿什坎迪兄弟会之剑",
             "星月湮灭战弓", "圣光裁决之锤", "泰蕾苟萨法杖", "萨格拉斯之杖",
             "黑暗撕裂者", "创世权柄", "万军崩裂", "守界圣辉"]
    h, t, rows = read("archive_fragment_definitions")
    rows = [row for row in rows if int(row["fragment_id"].split("_")[-1]) <= 12]
    for index, row in enumerate(rows):
        row["display_name"] = names[index]
        if index >= 8:
            row["challenge_building"], row["challenge_order"] = "3", str(index - 3)
    template = rows[-1]
    for index in range(13, 17):
        row = copy.deepcopy(template)
        row.update(fragment_id=f"fragment_{index:02d}", display_name=names[index-1],
                   challenge_building="4", challenge_order=str(index-8 if index < 16 else 4),
                   min_difficulty="10",
                   promotion_target="", source_boss=("萨格拉斯", "佐瓦尔", "阿克蒙德", "提尔")[index-13],
                   source_boss_stats="攻击显示5500002；血量和护甲沿用同类配置，非本次视频可见值",
                   source_method="project_authored_20261029：视频确认奖励名；成长沿用原fragment_12的18级同类规则")
        rows.append(row)
    _, _, challenge_rows = read("archive_challenge_definitions")
    challenge_by_reward = {row["reward_key"]: row for row in challenge_rows if row["reward_kind"] == "fragment"}
    _, _, stat_rows = read("archive_challenge_stats")
    stats_by_challenge = {row["challenge_id"]: row for row in stat_rows if row["difficulty_id"] == "N1"}
    for row in rows:
        definition = challenge_by_reward[row["fragment_id"]]
        fixed = stats_by_challenge[definition["challenge_id"]]
        row.update(challenge_building=definition["building_id"], challenge_order=definition["slot_order"],
                   min_difficulty=definition["min_difficulty"], source_boss=definition["display_name"].removeprefix("神兽狩猎-"),
                   source_boss_stats=f"固定生命{fixed['health']} / 攻击{fixed['attack']} / 魔兽护甲{fixed['war3_armor']}；HP/甲沿用项目同类，本次视频不可见")
        if int(row["fragment_id"].split("_")[-1]) <= 12:
            row["source_method"] = "视频确认奖励名称和挑战条件；保持旧永久ID及原成长属性，HP/甲沿用原项目配置，非本次视频可见值"
    write("archive_fragment_definitions", h, t, rows)
    h, t, levels = read("archive_fragment_levels")
    levels = [row for row in levels if int(row["fragment_id"].split("_")[-1]) <= 12]
    templates = [row for row in levels if row["fragment_id"] == "fragment_12"]
    for index in range(13, 17):
        for template in templates:
            row = copy.deepcopy(template)
            row.update(level_id=f"fragment_{index:02d}_lv{row['level']}", fragment_id=f"fragment_{index:02d}")
            levels.append(row)
    write("archive_fragment_levels", h, t, levels)

    h, t, rows = read("archive_cage_items")
    if "evidence_origin" not in h:
        h.append("evidence_origin"); t.append("string")
    rows = [row for row in rows if int(row["item_id"].split("_")[-1]) <= 54]
    templates = [row for row in rows if row["pool_id"] == "cage_6"]
    authored_names = [
        ["虚空龙之牙", "虚空龙之爪", "虚空沙漏", "虚空胸甲", "虚空之血", "虚空龙吟", "裂隙晶鳞", "深空回响", "虚空龙之魂"],
        ["暮光龙之牙", "暮光龙之爪", "暮光沙漏", "暮光胸甲", "暮光之血", "暮光龙吟", "暮色晶鳞", "暮光回响", "暮光龙之魂"],
        ["石英龙之牙", "石英龙之爪", "晶砂沙漏", "石英胸甲", "晶脉之血", "石英龙吟", "棱光晶鳞", "晶石回响", "石英龙之魂"],
    ]
    for pool in range(7, 10):
        for offset, template in enumerate(templates):
            row = copy.deepcopy(template)
            row.update(item_id=f"cage_{54+(pool-7)*9+offset+1:02d}", pool_id=f"cage_{pool}",
                       display_name=authored_names[pool-7][offset], evidence_origin="project_authored_20261029")
            rows.append(row)
    write("archive_cage_items", h, t, rows)

    h, t, rows = read("archive_social_rules")
    rows = [row for row in rows if row["pool_id"] != "concubine"]
    row = copy.deepcopy(next(row for row in rows if row["pool_id"] == "wife"))
    row.update(pool_id="concubine", display_name="我的侍妾", currency_id="salary", currency_name="工资",
               daily_limit="10", pass_daily_limit="10", pass_extra_count="0", unlock_count="0")
    rows.append(row)
    write("archive_social_rules", h, t, rows)
    h, t, rows = read("archive_social_items")
    rows = [row for row in rows if row["pool_id"] != "concubine"]
    originals = [
        ("灯火守望者", "N", "60", "初始金币+50", "initial_gold", "50"),
        ("林间药师", "R", "10", "英雄初始属性+2500", "hero_initial_attributes", "2500"),
        ("雾海旅人", "SR", "6", "英雄每秒属性+50", "hero_attributes_per_second", "50"),
        ("星辰咏者", "SSR", "5", "箭塔攻击加成+2%", "tower_attack_bonus_pct", "2"),
        ("长夜之誓", "UR", "1", "英雄最终伤害+10%", "hero_final_damage_bonus_pct", "10"),
    ]
    for index, values in enumerate(originals, 1):
        name, quality, maximum, description, effect, value = values
        rows.append(dict(item_id=f"concubine_{index:02d}", pool_id="concubine", display_name=name,
                         max_owned=maximum, quality=quality, description=description, effect_ids=effect,
                         effect_values=value, enabled="1", draw_enabled="1", availability_note=""))
    write("archive_social_items", h, t, rows)

    h, t, rows = read("archive_daily_limits")
    rows = [row for row in rows if row["limit_id"] != "endless_gear"]
    by_id = {row["limit_id"]: row for row in rows}
    for index, name in enumerate(names, 1):
        key = f"fragment_{index:02d}"
        if key not in by_id:
            row = copy.deepcopy(by_id["fragment_12"])
            row.update(limit_id=key, storage_key=key, sort_order=str(79+index))
            rows.append(row); by_id[key] = row
        by_id[key]["display_name"] = "每日" + name + "碎片"
    by_id["football"].update(implemented="1", notes="绿茵挑战实际获得积分；每日100；10点每次")
    by_id["salary"].update(implemented="1", notes="侍妾挑战工资；每日10；消费不返还名额")
    for key, name, daily, order in [("watermelon", "每日西瓜积分", 10, 111)]:
        if key in by_id: continue
        rows.append(dict(limit_id=key, display_name=name, storage_key=key+"_total", daily_limit=str(daily),
                         pass_daily_limit=str(daily), implemented="1", sort_order=str(order),
                         notes="西瓜挑战每日10；每次1点"))
    write("archive_daily_limits", h, t, rows)
    h, t, rows = read("archive_categories")
    if not any(row["category_id"] == "concubine" for row in rows):
        rows.append(dict(category_id="concubine", display_name="我的侍妾", renderer="collection", sort_order="67", enabled="1"))
    write("archive_categories", h, t, rows)

    print("ARCHIVE_VIDEO_REWARDS_CONFIGURED (no generated resources or deployment)")


if __name__ == "__main__":
    main()
