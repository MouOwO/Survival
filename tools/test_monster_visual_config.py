from __future__ import annotations

import csv
import hashlib
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from tools import build_configs
from tools.test_challenge_monster_visual_resources import vpk_paths


CSV_ROOT = ROOT / "data" / "csv" / "怪物与波次系统"


def rows(name: str) -> list[dict[str, str]]:
    with (CSV_ROOT / name).open("r", encoding="utf-8-sig", newline="") as handle:
        return [
            row for row in csv.DictReader(
                line for line in handle if not line.startswith("#")
            )
        ]


sources = sorted(build_configs.CSV_ROOT.rglob("*.csv"))
build_configs.validate_monster_visual_definitions(sources)

assets = rows("monster_visual_assets.csv")
waves = rows("wave_visual_definitions.csv")
assert len(assets) == 11, "wave 1-5 visual asset count changed"
assert [int(row["wave_number"]) for row in waves] == [1, 2, 3, 4, 5]
assert all(int(row["support_every_nth"]) == 0 for row in waves), (
    "unapproved normal/support mix was enabled"
)

available = vpk_paths()
missing = []
for row in assets:
    compiled = row["model_path"].replace(".vmdl", ".vmdl_c")
    if compiled not in available:
        missing.append((row["visual_asset_id"], compiled))
assert not missing, f"monster visual models missing from local VPK: {missing}"

unit_kv = (ROOT / "scripts" / "npc" / "npc_units_custom.txt").read_text(
    encoding="utf-8"
)
for row in assets:
    proxy = row["async_unit_name"]
    assert f'"{proxy}"' in unit_kv, f"monster visual proxy missing from unit KV: {proxy}"
    assert f'"Model" "{row["model_path"]}"' in unit_kv, (
        f"monster visual proxy model missing from unit KV: {row['visual_asset_id']}"
    )

wave_csv = CSV_ROOT / "wave_definitions.csv"
archetype_csv = CSV_ROOT / "monster_archetypes.csv"
combat_fingerprint = hashlib.sha256(
    wave_csv.read_bytes() + b"\0" + archetype_csv.read_bytes()
).hexdigest()
assert len(combat_fingerprint) == 64

print(
    "MONSTER_VISUAL_CONFIG_PASS "
    f"assets={len(assets)} waves={len(waves)} combat_sha256={combat_fingerprint}"
)