from __future__ import annotations

import csv
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CSV_PATH = ROOT / "data/csv/建筑与工人系统/防御塔/tower_skill_definitions.csv"
MODIFIER_PATH = ROOT / "scripts/vscripts/modifiers/modifier_tower_attack_effects.lua"
SPECIAL_PATH = ROOT / "scripts/vscripts/systems/tower_special_skill_system.lua"


with CSV_PATH.open("r", encoding="utf-8-sig", newline="") as handle:
    rows = {row["skill_id"].strip(): row for row in csv.DictReader(handle)}

families = {
    "lightning_strike": 5,
    "lightning_storm": 5,
    "frost_attack": 5,
    "ice_blizzard": 5,
}
for prefix, levels in families.items():
    for level in range(1, levels + 1):
        skill_id = f"{prefix}_lv{level:02d}"
        row = rows[skill_id]
        assert "物理伤害" in row["description"], f"{skill_id} is not physical in CSV"
assert "物理伤害" in rows["lightning_diffusion_lv01"]["description"]

modifier = MODIFIER_PATH.read_text(encoding="utf-8-sig")
special = SPECIAL_PATH.read_text(encoding="utf-8-sig")

assert "params.damage_category == DOTA_DAMAGE_CATEGORY_ATTACK" in modifier
assert "DAMAGE_TYPE_MAGICAL" not in modifier
assert "if target ~= primary then" in modifier
assert modifier.count("event_bus.emit(events.TOWER_LIGHTNING_HIT") == 1
assert 'source = "lightning_storm"' in modifier
assert 'source = "chain_lightning"' not in modifier
assert "trigger_chain_kill_storm(caster, primary)" in modifier
assert "trigger_chain_kill_storm(caster, next_target)" in modifier
assert "target:IsAlive()" in modifier

assert 'payload.source ~= "lightning_storm"' in special
assert 'deal(payload.tower, enemy, damage, "lightning_diffusion")' in special
assert "damage_type = damage_type or DAMAGE_TYPE_PHYSICAL" in special

print("LIGHTNING_FROST_PHYSICAL_CONTRACT_PASS")