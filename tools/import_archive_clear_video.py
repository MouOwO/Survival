"""Import reviewed video rewards without dropping unsupported difficulties."""
from __future__ import annotations
import csv
import io
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REFERENCE = ROOT / "data/references/archive_clear_rewards_20261020.json"
TARGET = ROOT / "data/csv/存档系统/archive_achievements.csv"


def read(path):
    return list(csv.DictReader(line for line in path.read_text(encoding="utf-8-sig").splitlines()
                              if not line.startswith("#")))


def build():
    original = read(TARGET)
    columns = list(original[0])
    extra = {"mode_id": "string", "reward_mode": "string", "reward_start": "number",
             "reward_limit": "number", "source_video_seconds": "number", "source_target": "number"}
    for column in extra:
        if column not in columns:
            columns.append(column)
    types = next(line[7:].split(",") for line in TARGET.read_text(encoding="utf-8-sig").splitlines()
                 if line.startswith("#types:"))
    old_types = dict(zip(list(original[0]), types))
    types = [extra.get(column, old_types.get(column)) for column in columns]
    rows = []
    for item in original:
        if item.get("mode_id", "standard") not in ("", "standard"):
            continue
        item = dict(item, mode_id="standard", reward_mode="milestone", reward_start=0, reward_limit=1)
        if not item["display_name"].startswith("常规"):
            item["display_name"] = "常规 " + item["display_name"]
        rows.append(item)
    # Pure-mode counters have no reward specification in the recording. Show
    # their own progress without copying normal bonuses or mixed legacy wins.
    for number in range(1, 11):
        rows.append(dict(achievement_id=f"clear_pure_n{number}", category_id="clear", mode_id="pure",
            difficulty_id=f"n{number}", required_count=1, display_name=f"纯净 N{number}",
            description="纯净模式独立通关次数", effect_ids="", effect_values="", icon_style="scroll",
            enabled="1", source_row=0, notes="仅计数；录像未指定纯净模式奖励", reward_mode="counter",
            reward_start=0, reward_limit=1))
    fields = {row["field_id"] for row in read(ROOT / "data/csv/玩家档案系统/player_gameplay_stats.csv")}
    source = json.loads(REFERENCE.read_text(encoding="utf-8"))
    for item in source["rows"]:
        assert item["verified"] is True and item["effect_id"] in fields
        limit = item["reward_limit"]
        assert type(limit) is int and limit > 0
        rows.append(dict(achievement_id=f"clear_{item['mode_id']}_{item['difficulty_id']}",
            category_id="clear", mode_id=item["mode_id"], difficulty_id=item["difficulty_id"],
            required_count=limit, display_name=item["name"],
            description=f"{item['description']}（每次通关获得，最多{limit}次）",
            effect_ids=item["effect_id"], effect_values=item["effect_value"], icon_style="scroll", enabled="1",
            source_row=0, notes="录像悬停核对；未开放模式/难度由运行时隐藏", reward_mode="per_clear",
            reward_start=0, reward_limit=limit, source_video_seconds=item["seconds"], source_target=item["source_target"]))
    assert len({item["achievement_id"] for item in rows}) == len(rows)
    stream = io.StringIO(newline="")
    writer = csv.DictWriter(stream, columns, lineterminator="\n")
    writer.writeheader()
    stream.write("# 每种模式独立计数；旧常规ID保留；尚未开放的奖励配置不删除。\n")
    stream.write("#types:" + ",".join(types) + "\n")
    writer.writerows(rows)
    TARGET.write_text(stream.getvalue(), encoding="utf-8", newline="\n")
    return len(rows)


if __name__ == "__main__":
    print("ARCHIVE_VIDEO_IMPORTED", build())
