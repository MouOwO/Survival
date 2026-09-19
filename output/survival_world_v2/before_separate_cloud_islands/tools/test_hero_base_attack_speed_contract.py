from __future__ import annotations

import csv
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CSV_PATH = ROOT / "data/csv/英雄系统/hero_definitions.csv"
GENERATED_PATH = ROOT / "scripts/vscripts/config/generated/hero_definitions.lua"

EXPECTED_ATTACK_SPEED = "0.7"
EXPECTED_HEROES = {
    "hero_shadow_fiend",
    "hero_drow_ranger",
    "hero_monkey_king",
    "hero_blademaster",
}


raw_csv = CSV_PATH.read_bytes()
try:
    csv_text = raw_csv.decode("utf-8-sig")
except UnicodeDecodeError:
    csv_text = raw_csv.decode("gb18030")
rows = list(csv.DictReader(
    line for line in csv_text.splitlines() if not line.startswith("#")
))

selected = {row["hero_id"]: row for row in rows if row["hero_id"] in EXPECTED_HEROES}
assert set(selected) == EXPECTED_HEROES, "expected hero roster is incomplete"
for hero_id, row in selected.items():
    assert row["attack_speed"] == EXPECTED_ATTACK_SPEED, (
        f"{hero_id} base attack speed is {row['attack_speed']}, "
        f"expected {EXPECTED_ATTACK_SPEED}"
    )

generated = GENERATED_PATH.read_text(encoding="utf-8-sig")
for hero_id in EXPECTED_HEROES:
    pattern = (
        rf'hero_id = "{re.escape(hero_id)}".*?'
        rf'attack_speed = {re.escape(EXPECTED_ATTACK_SPEED)}'
    )
    assert re.search(pattern, generated, re.S), (
        f"generated attack speed is stale for {hero_id}"
    )

print("HERO_BASE_ATTACK_SPEED_CONTRACT_PASS heroes=4 attack_speed=0.7")