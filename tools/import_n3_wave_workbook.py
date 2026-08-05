"""Import approved N3-N5 wave members from an authoritative OOXML workbook.

The workbook supplies totals and stats. Models come from the approved N1
mapping; waves 26-30 map to N1 waves 21-25. This tool only rewrites the target
difficulty rows in the authoritative wave CSV and never edits generated Lua.
"""
from __future__ import annotations

import argparse
import csv
import io
import math
from pathlib import Path

from audit_n1_n5_workbook import audit


ROOT = Path(__file__).resolve().parents[1]
CSV_PATH = ROOT / "data" / "csv" / "怪物与波次系统" / "wave_definitions.csv"
FLYING_ARCHETYPES = {
    "flying_red_gargoyle", "dragon_red_large", "dragon_red_small",
    "flying_green_head", "dragon_purple_large", "dragon_purple_small",
    "flying_carpet_mage", "dragon_black_red_large",
    "dragon_black_red_small", "flying_black_bone",
}
FLYING_FALLBACK_ARCHETYPE = "flying_red_gargoyle"
ASSAULT_SOURCE_WAVES = {5, 10, 15, 20, 25, 30}


def read_csv(path: Path) -> tuple[list[list[str]], list[str]]:
    text = path.read_bytes().decode("utf-8-sig")
    rows = list(csv.reader(io.StringIO(text)))
    return rows, rows[0]


def workbook_rows(path: Path, difficulty_id: str = "N3") -> dict[int, dict[str, str]]:
    report, _ = audit(path)
    sheet_name = f"{difficulty_id}波次总表"
    sheet = next(item for item in report["sheets"] if item["name"] == sheet_name)
    result = {}
    for row in sheet["rows"]:
        values = row["values"]
        if values.get("A", "").isdigit():
            result[int(values["A"])] = values
    if sorted(result) != list(range(1, 31)):
        raise ValueError(f"{difficulty_id} workbook must contain waves 1-30")
    return result


def allocate(total: int, templates: list[dict[str, str]]) -> list[int]:
    if not templates:
        if total:
            raise ValueError(f"cannot allocate {total} units without templates")
        return []
    weights = [int(row["monster_count"]) for row in templates]
    weight_total = sum(weights)
    exact = [total * weight / weight_total for weight in weights]
    allocated = [math.floor(value) for value in exact]
    remaining = total - sum(allocated)
    order = sorted(
        range(len(templates)),
        key=lambda index: (-(exact[index] - allocated[index]), int(templates[index]["spawn_order"])),
    )
    for index in order[:remaining]:
        allocated[index] += 1
    return allocated


def source_wave(number: int) -> int:
    return number if number <= 25 else number - 5


def make_row(
    headers: list[str], template: dict[str, str], wave: int, batch: str,
    order: int, count: int, role: str, stats: tuple[str, str, str], notes: str,
    movement_type_override: str = "", model_scale_multiplier: str = "1",
    difficulty_id: str = "N3",
) -> list[str]:
    row = dict(template)
    row.update({
        "wave_id": f"{difficulty_id.lower()}_wave_{wave:02d}_{batch.lower()}",
        "difficulty_id": difficulty_id,
        "wave_number": str(wave),
        "batch_id": batch,
        "spawn_order": str(order),
        "monster_count": str(count),
        "wait_seconds": "0",
        "spawn_interval": "1",
        "health": stats[0],
        "attack": stats[1],
        "armor": stats[2],
        "is_boss": "1" if role == "assault_boss" else "0",
        "boss_warning": "1" if role == "assault_boss" else "0",
        "enabled": "1",
        "member_role": role,
        "movement_type_override": movement_type_override,
        "model_scale_multiplier": model_scale_multiplier,
        "notes": notes,
    })
    return [row.get(header, "") for header in headers]


def evidence_note(values: dict[str, str], *columns: str) -> str:
    parts = []
    for column in columns:
        value = values.get(column, "").strip()
        if value and value not in parts:
            parts.append(value)
    return "；".join(parts)


def build_difficulty(
    existing: list[list[str]], headers: list[str],
    book: dict[int, dict[str, str]], difficulty_id: str,
) -> list[list[str]]:
    data = [dict(zip(headers, row)) for row in existing if row and not row[0].startswith("#")]
    n1 = {}
    for row in data:
        if row.get("difficulty_id") == "N1":
            n1.setdefault(int(row["wave_number"]), []).append(row)
    for rows in n1.values():
        rows.sort(key=lambda row: int(row["spawn_order"]))
    fallback_flying = next(
        row for row in data if row.get("archetype_id") == FLYING_FALLBACK_ARCHETYPE
    )

    output = []
    order = 1000
    totals = {"normal": 0, "wave_leader": 0, "assault_boss": 0}
    for wave in range(1, 31):
        values = book[wave]
        templates = n1[source_wave(wave)]
        normal_templates = [row for row in templates if row["is_boss"] != "1"]
        flying = [row for row in normal_templates if row["archetype_id"] in FLYING_ARCHETYPES]
        ground = [row for row in normal_templates if row["archetype_id"] not in FLYING_ARCHETYPES]
        flying_count = int(values.get("AD", "0") or 0)
        normal_count = int(values["D"])
        if flying_count > normal_count:
            raise ValueError(f"wave {wave}: flying count exceeds normal count")
        if flying_count and not flying:
            flying = [fallback_flying]
        ground_count = normal_count - flying_count
        ground_uses_flying_models = ground_count > 0 and not ground
        if ground_uses_flying_models:
            ground = flying

        normal_stats = (values["J"], values["K"], values["L"])
        member_index = 0
        for group, count, is_flying in ((ground, ground_count, False), (flying, flying_count, True)):
            for template, allocated in zip(group, allocate(count, group)):
                if allocated <= 0:
                    continue
                member_index += 1
                armor = str(float(values["L"]) * 3).rstrip("0").rstrip(".") if is_flying else values["L"]
                note = f"{difficulty_id}工作簿数量；沿用N1模型映射"
                if is_flying:
                    note += "；飞行高护甲怪；护甲为本波基准War3护甲3倍"
                evidence = evidence_note(values, "M", "AI", "AJ")
                if evidence:
                    note += "；证据：" + evidence
                output.append(make_row(
                    headers, template, wave, f"{wave}N{member_index}", order,
                    allocated, "normal", (values["J"], values["K"], armor), note,
                    "ground" if ground_uses_flying_models and not is_flying else "",
                    difficulty_id=difficulty_id,
                ))
                order += 1
                totals["normal"] += allocated

        leader_count = int(values["E"])
        if leader_count:
            leader_is_flying = int(values.get("AE", "0") or 0) > 0
            leader_template = fallback_flying if leader_is_flying else normal_templates[0]
            output.append(make_row(
                headers, leader_template, wave, f"{wave}L", order, leader_count,
                "wave_leader", (values["O"], values["P"], values["Q"]),
                f"{difficulty_id}工作簿首怪Boss；独立wave_leader身份；模型略大"
                + ("；证据：" + evidence_note(values, "R", "AI", "AJ")
                   if evidence_note(values, "R", "AI", "AJ") else ""),
                "flying" if leader_is_flying else "", "1.15", difficulty_id,
            ))
            order += 1
            totals["wave_leader"] += leader_count

        assault_count = int(values["F"])
        if assault_count:
            boss_template = next((row for row in templates if row["is_boss"] == "1"), None)
            if boss_template is None:
                boss_template = next(row for row in n1[25] if row["is_boss"] == "1")
            output.append(make_row(
                headers, boss_template, wave, f"{wave}B", order, assault_count,
                "assault_boss", (values["T"], values["U"], values["V"]),
                f"{difficulty_id}工作簿进攻Boss；独立assault_boss身份"
                + ("；证据：" + evidence_note(values, "W", "AI", "AJ")
                   if evidence_note(values, "W", "AI", "AJ") else ""),
                "flying" if int(values.get("AF", "0") or 0) > 0 else "", "1",
                difficulty_id,
            ))
            order += 1
            totals["assault_boss"] += assault_count

    expected = {"normal": 1270, "wave_leader": 27, "assault_boss": 6}
    if totals != expected or sum(totals.values()) != 1303:
        raise ValueError(f"{difficulty_id} totals mismatch: {totals}")
    return output


def build_n3(
    existing: list[list[str]], headers: list[str], book: dict[int, dict[str, str]],
) -> list[list[str]]:
    return build_difficulty(existing, headers, book, "N3")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("workbook", type=Path)
    parser.add_argument("--difficulty", choices=("N3", "N4", "N5"), default="N3")
    args = parser.parse_args()
    rows, old_headers = read_csv(CSV_PATH)
    headers = list(old_headers)
    new_columns = (
        ("member_role", "成员角色", "enum"),
        ("movement_type_override", "移动类型覆盖", "enum"),
        ("model_scale_multiplier", "模型缩放倍率", "number"),
    )
    notes_index = headers.index("notes")
    for name, _, _ in reversed(new_columns):
        if name not in headers:
            headers.insert(notes_index, name)
    metadata = []
    existing = []
    for row in rows[1:]:
        if not row:
            continue
        if row[0].startswith("#"):
            mapped = dict(zip(old_headers, row))
            if row[0].startswith("#中文名:"):
                mapped.update({name: chinese for name, chinese, _ in new_columns})
            elif row[0].startswith("#types:"):
                mapped.update({name: kind for name, _, kind in new_columns})
            metadata.append([mapped.get(header, "") for header in headers])
            continue
        mapped = dict(zip(old_headers, row))
        if mapped.get("difficulty_id") != args.difficulty:
            existing.append([mapped.get(header, "") for header in headers])
    generated = build_difficulty(
        existing, headers, workbook_rows(args.workbook, args.difficulty), args.difficulty,
    )
    buffer = io.StringIO(newline="")
    writer = csv.writer(buffer, lineterminator="\n")
    writer.writerow(headers)
    writer.writerows(metadata)
    writer.writerows(existing)
    writer.writerows(generated)
    CSV_PATH.write_bytes(b"\xef\xbb\xbf" + buffer.getvalue().encode("utf-8"))
    print(
        f"{args.difficulty}_WAVE_CSV_IMPORT_PASS "
        "normal=1270 wave_leader=27 assault_boss=6 total=1303"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())