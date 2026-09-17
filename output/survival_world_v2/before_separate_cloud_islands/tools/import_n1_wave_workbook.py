"""Import the authoritative 25-wave N1 layout without changing other difficulties."""
from __future__ import annotations

import argparse
import csv
import io
import math
from pathlib import Path

from audit_n1_n5_workbook import audit
from import_n3_wave_workbook import FLYING_ARCHETYPES, FLYING_FALLBACK_ARCHETYPE


ROOT = Path(__file__).resolve().parents[1]
CSV_PATH = ROOT / "data" / "csv" / "怪物与波次系统" / "wave_definitions.csv"
ASSAULT_WAVES = {5, 10, 15, 20, 25}
SPECIAL_MIXED_WAVES = {11, 13, 24}


def dedupe_by_wave_id(rows: list[dict[str, str]]) -> list[dict[str, str]]:
    """Keep the final definition for an ID after interrupted/manual merges."""
    last_index = {row["wave_id"]: index for index, row in enumerate(rows)}
    return [
        row for index, row in enumerate(rows)
        if last_index[row["wave_id"]] == index
    ]


def read_csv() -> tuple[list[str], list[list[str]]]:
    rows = list(csv.reader(io.StringIO(CSV_PATH.read_bytes().decode("utf-8-sig"))))
    return rows[0], rows[1:]


def workbook_rows(path: Path) -> dict[int, dict[str, str]]:
    report, errors = audit(path)
    if errors:
        raise ValueError("workbook audit failed: " + ",".join(errors))
    sheet = next(item for item in report["sheets"] if item["name"] == "N1波次总表")
    result = {}
    for row in sheet["rows"]:
        values = row["values"]
        if values.get("A", "").isdigit():
            result[int(values["A"])] = values
    if sorted(result) != list(range(1, 26)):
        raise ValueError("N1 workbook must contain waves 1-25")
    return result


def allocate(total: int, templates: list[dict[str, str]]) -> list[int]:
    if not templates:
        if total:
            raise ValueError(f"cannot allocate {total} units without templates")
        return []
    weights = [max(1, int(row["monster_count"])) for row in templates]
    exact = [total * weight / sum(weights) for weight in weights]
    allocated = [math.floor(value) for value in exact]
    remaining = total - sum(allocated)
    order = sorted(
        range(len(templates)),
        key=lambda index: (-(exact[index] - allocated[index]), int(templates[index]["spawn_order"])),
    )
    for index in order[:remaining]:
        allocated[index] += 1
    return allocated


def updated_row(
    headers: list[str], template: dict[str, str], wave: int, batch_id: str,
    spawn_order: int, count: int, role: str, stats: tuple[str, str, str],
    notes: str, wave_id: str | None = None, movement: str = "",
    scale: str = "1",
) -> list[str]:
    row = dict(template)
    row.update({
        "wave_id": wave_id or template["wave_id"],
        "difficulty_id": "N1",
        "wave_number": str(wave),
        "batch_id": batch_id,
        "spawn_order": str(spawn_order),
        "monster_count": str(count),
        "wait_seconds": "90",
        "spawn_interval": "1",
        "health": stats[0],
        "attack": stats[1],
        "armor": stats[2],
        "is_boss": "1" if role == "assault_boss" else "0",
        "boss_warning": "1" if role == "assault_boss" else "0",
        "enabled": "1",
        "member_role": role,
        "movement_type_override": movement,
        "model_scale_multiplier": scale,
        "notes": notes,
    })
    return [row.get(header, "") for header in headers]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("workbook", type=Path)
    args = parser.parse_args()
    headers, rows = read_csv()
    metadata = []
    other = []
    current = []
    for fields in rows:
        if not fields:
            continue
        fields = fields + [""] * (len(headers) - len(fields))
        if fields[0].startswith("#"):
            metadata.append(fields)
            continue
        row = dict(zip(headers, fields))
        (current if row["difficulty_id"] == "N1" else other).append(row)

    by_wave = {}
    for row in current:
        by_wave.setdefault(int(row["wave_number"]), []).append(row)
    by_wave = {
        wave: dedupe_by_wave_id(rows)
        for wave, rows in by_wave.items()
    }
    fallback_flying = next(row for row in current if row["archetype_id"] == FLYING_FALLBACK_ARCHETYPE)
    fallback_boss = next(row for row in by_wave[25] if row["is_boss"] == "1")
    book = workbook_rows(args.workbook)
    generated = []
    order = 1
    totals = {"normal": 0, "wave_leader": 0, "assault_boss": 0}

    for wave in range(1, 26):
        values = book[wave]
        templates = sorted(by_wave[wave], key=lambda row: int(row["spawn_order"]))
        normals = [
            row for row in templates
            if row["member_role"] == "normal"
            or (wave not in SPECIAL_MIXED_WAVES and row["is_boss"] != "1")
        ]
        flying = [row for row in normals if row["archetype_id"] in FLYING_ARCHETYPES]
        ground = [row for row in normals if row["archetype_id"] not in FLYING_ARCHETYPES]
        flying_count = 19 if wave in SPECIAL_MIXED_WAVES else int(values.get("AD", "0") or 0)
        normal_count = 59 if wave in SPECIAL_MIXED_WAVES else int(values["D"])
        if flying_count > normal_count:
            raise ValueError(f"wave {wave}: flying count exceeds normal count")
        if flying_count and not flying:
            flying = [fallback_flying]
        ground_count = normal_count - flying_count
        if ground_count and not ground:
            ground = flying

        if int(values["E"]):
            leader_template = flying[0] if int(values.get("AE", "0") or 0) else normals[0]
            generated.append(updated_row(
                headers, leader_template, wave, f"{wave}L", order, 1,
                "wave_leader", (values["O"], values["P"], values["Q"]),
                "N1工作簿首怪Boss；独立wave_leader身份；模型略大；证据：" + values["R"],
                f"n1_wave_{wave:02d}_{wave}l",
                "flying" if int(values.get("AE", "0") or 0) else "", "1.15",
            ))
            order += 1
            totals["wave_leader"] += 1

        member_index = 0
        stats = (values["J"], values["K"], values["L"])
        flying_stats = (str(int(values["O"]) // 10), str(int(values["K"]) // 2), values["L"])
        for group, count, is_flying in ((ground, ground_count, False), (flying, flying_count, True)):
            for template, allocated in zip(group, allocate(count, group)):
                if allocated <= 0:
                    continue
                member_index += 1
                generated.append(updated_row(
                    headers, template, wave, f"{wave}N{member_index}", order,
                    allocated, "normal", flying_stats if is_flying and wave in SPECIAL_MIXED_WAVES else stats,
                    ("N1 W" + str(wave) + "混合波；普通怪每2只走地后1只飞行；"
                     "飞行怪生命为首怪1/10、攻击为普通怪1/2")
                    if wave in SPECIAL_MIXED_WAVES else
                    "N1工作簿数量与同波最低属性；保留现有模型映射；证据："
                    + values["M"] + "；" + values["AJ"],
                    template["wave_id"] if template in normals
                    else f"n1_wave_{wave:02d}_{wave}n{member_index}",
                    "flying" if is_flying and wave in SPECIAL_MIXED_WAVES else "",
                ))
                order += 1
                totals["normal"] += allocated

        if wave in ASSAULT_WAVES:
            boss_template = next((row for row in templates if row["is_boss"] == "1"), fallback_boss)
            generated.append(updated_row(
                headers, boss_template, wave, f"{wave}B", order, 1,
                "assault_boss", (values["T"], values["U"], values["V"]),
                "N1工作簿进攻Boss；独立assault_boss身份；证据：" + values["W"],
                boss_template["wave_id"] if boss_template in templates
                else f"n1_wave_{wave:02d}_{wave}b",
                "flying" if int(values.get("AF", "0") or 0) else "",
            ))
            order += 1
            totals["assault_boss"] += 1

    expected = {
        "normal": sum(
            59 if wave in SPECIAL_MIXED_WAVES else int(book[wave]["D"])
            for wave in range(1, 26)
        ),
        "wave_leader": sum(int(book[wave]["E"]) for wave in range(1, 26)),
        "assault_boss": len(ASSAULT_WAVES),
    }
    if totals != expected:
        raise ValueError(f"N1 totals mismatch: {totals}")

    role_order = {"assault_boss": 1, "wave_leader": 2, "normal": 3}
    role_index = headers.index("member_role")
    spawn_index = headers.index("spawn_order")
    wave_index = headers.index("wave_number")
    generated.sort(key=lambda row: (
        int(row[wave_index]),
        role_order.get(row[role_index], 99),
        int(row[spawn_index]),
    ))
    for spawn_order, row in enumerate(generated, 1):
        row[spawn_index] = str(spawn_order)

    buffer = io.StringIO(newline="")
    writer = csv.writer(buffer, lineterminator="\n")
    writer.writerow(headers)
    writer.writerows(metadata)
    writer.writerows(generated)
    writer.writerows([[row.get(header, "") for header in headers] for row in other])
    CSV_PATH.write_bytes(b"\xef\xbb\xbf" + buffer.getvalue().encode("utf-8"))
    print(
        "N1_WAVE_CSV_IMPORT_PASS "
        f"normal={totals['normal']} wave_leader={totals['wave_leader']} "
        f"assault_boss={totals['assault_boss']} total={sum(totals.values())}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())