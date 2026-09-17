"""Reorder authoritative wave CSV rows so the strongest role spawns first."""
from __future__ import annotations

import csv
import io
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CSV_PATH = ROOT / "data" / "csv" / "怪物与波次系统" / "wave_definitions.csv"
ROLE_ORDER = {"assault_boss": 1, "wave_leader": 2, "normal": 3}


def role_rank(row: dict[str, str]) -> int:
    role = row.get("member_role", "").strip() or "normal"
    return ROLE_ORDER.get(role, 3)


def main() -> int:
    rows = list(csv.reader(io.StringIO(CSV_PATH.read_bytes().decode("utf-8-sig"))))
    headers = rows[0]
    data = [dict(zip(headers, row)) for row in rows[3:] if row]
    groups = {}
    for row in data:
        groups.setdefault(
            (row["difficulty_id"], int(row["wave_number"])), []
        ).append(row)
    for group in groups.values():
        existing_orders = sorted(int(row["spawn_order"]) for row in group)
        strongest_first = sorted(group, key=lambda row: (
            role_rank(row),
            int(row["spawn_order"]),
        ))
        for order, row in zip(existing_orders, strongest_first):
            row["spawn_order"] = str(order)
    buffer = io.StringIO(newline="")
    writer = csv.writer(buffer, lineterminator="\r\n")
    writer.writerow(headers)
    writer.writerows(rows[1:3])
    for row in data:
        writer.writerow([row.get(header, "") for header in headers])
    CSV_PATH.write_bytes(b"\xef\xbb\xbf" + buffer.getvalue().encode("utf-8"))
    print(f"WAVE_SPAWN_ORDER_CSV_PASS rows={len(data)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())