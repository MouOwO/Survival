"""Import one difficulty's existing encounter profiles from its workbook."""
from __future__ import annotations

import argparse
import csv
import io
from pathlib import Path

from audit_n1_n5_workbook import audit


ROOT = Path(__file__).resolve().parents[1]
PROFILE_PATH = ROOT / "data" / "csv" / "挑战与奖励系统" / "challenge_combat_profiles.csv"


def read_rows(path: Path) -> tuple[list[str], list[list[str]]]:
    rows = list(csv.reader(io.StringIO(path.read_bytes().decode("utf-8-sig"))))
    return rows[0], rows[1:]


def workbook_stats(path: Path, sheet_name: str) -> dict[int, tuple[str, str, str, str]]:
    report, _ = audit(path)
    sheet = next(item for item in report["sheets"] if item["name"] == sheet_name)
    result = {}
    for row in sheet["rows"]:
        values = row["values"]
        if values.get("A", "").isdigit():
            index = int(values["A"])
            result[index] = (
                values["C"], values["D"], values["E"], values.get("F", "")
            )
    if sorted(result) != list(range(1, 11)):
        raise ValueError(f"{sheet_name} must contain entries 1-10")
    return result


def existing_difficulty_stats(
    path: Path, difficulty_id: str,
) -> dict[str, tuple[str, str, str, str, str]]:
    report, _ = audit(path)
    sheets = {item["name"]: item for item in report["sheets"]}
    result = {}
    practice_members = (
        "practice_wood", "practice_gold", "practice_attribute",
        "practice_greater_attribute",
    )
    practice_rows = [
        row["values"] for row in sheets["四个练功房"]["rows"]
        if row["values"].get("A", "") in {
            "练功房1", "练功房2", "练功房3", "练功房4",
        }
    ]
    if len(practice_rows) != 4:
        raise ValueError("四个练功房 must contain exactly four data rows")
    for member_id, values in zip(practice_members, practice_rows):
        result[member_id] = (
            values["C"], values["D"], values["E"], values["F"],
            f"{difficulty_id}工作簿：四个练功房",
        )

    special_members = (
        "challenge_05_boss", "challenge_06_ice_wraith",
        "challenge_08_boss", "challenge_09_boss",
        "challenge_07_molten_minion", "seven_sins_minion",
    )
    special_rows = [
        row["values"] for row in sheets["特殊Boss与材料怪"]["rows"]
        if row["values"].get("C", "").isdigit()
    ]
    for member_id, values in zip(special_members, special_rows):
        result[member_id] = (
            values["C"], values["D"], values["E"], values["F"],
            f"{difficulty_id}工作簿：特殊Boss与材料怪",
        )
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("workbook", type=Path)
    parser.add_argument("--difficulty", choices=("N1", "N2"), default="N2")
    args = parser.parse_args()

    rebirth = workbook_stats(args.workbook, "转生Boss")
    ten_sins = workbook_stats(args.workbook, "十戒Boss")
    current_stats = existing_difficulty_stats(args.workbook, args.difficulty)
    headers, rows = read_rows(PROFILE_PATH)
    target_members = {
        *(f"encounter_rebirth_{index:02d}" for index in range(1, 11)),
        *(f"boss_ten_sin_{index:02d}" for index in range(1, 11)),
    }

    metadata = []
    existing = []
    for fields in rows:
        if not fields:
            continue
        fields += [""] * (len(headers) - len(fields))
        if fields[0].startswith("#"):
            metadata.append(fields)
            continue
        row = dict(zip(headers, fields))
        if row["member_id"] not in target_members:
            if row["difficulty_id"] == args.difficulty and row["member_id"] in current_stats:
                health, attack, armor, evidence, source = current_stats[row["member_id"]]
                row.update({
                    "health": health,
                    "attack": attack,
                    "war3_armor": armor,
                    "evidence_status": evidence,
                    "source": source,
                })
                fields = [row.get(header, "") for header in headers]
            existing.append(fields)
        elif row["difficulty_id"] != args.difficulty:
            existing.append(fields)

    added = []
    for workbook_rows, member_prefix, source_name in (
        (rebirth, "encounter_rebirth", f"{args.difficulty}转生Boss"),
        (ten_sins, "boss_ten_sin", f"{args.difficulty}十戒Boss"),
    ):
        for index in range(1, 11):
            member_id = f"{member_prefix}_{index:02d}"
            health, attack, armor, evidence = workbook_rows[index]
            row = {
                "profile_id": f"{args.difficulty}_{member_id}",
                "difficulty_id": args.difficulty,
                "member_id": member_id,
                "health": health,
                "attack": attack,
                "war3_armor": armor,
                "evidence_status": evidence,
                "source": source_name,
                "notes": f"{args.difficulty}工作簿独立目标；不计入波次",
                "enabled": "1",
            }
            added.append([row.get(header, "") for header in headers])

    buffer = io.StringIO(newline="")
    writer = csv.writer(buffer, lineterminator="\n")
    writer.writerow(headers)
    writer.writerows(metadata)
    writer.writerows(existing)
    writer.writerows(added)
    PROFILE_PATH.write_bytes(b"\xef\xbb\xbf" + buffer.getvalue().encode("utf-8"))
    print(
        f"{args.difficulty}_ENCOUNTER_PROFILE_IMPORT_PASS "
        "rebirth=10 ten_sins=10 total_replaced=20"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())