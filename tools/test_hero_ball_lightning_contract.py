from __future__ import annotations

import csv
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CONTENT = ROOT.parents[2] / "content" / "dota_addons" / "survival"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8-sig")


with (ROOT / "data/csv/英雄系统/hero_definitions.csv").open(
    "r", encoding="utf-8-sig", newline=""
) as handle:
    rows = [row for row in csv.DictReader(
        line for line in handle if not line.startswith("#")
    )]

assert len(rows) == 6, "summoned hero roster changed unexpectedly"
for row in rows:
    assert row["base_mana"] == "100", f'{row["hero_id"]} base mana is not 100'
    assert row["base_mana_regen"] == "10", \
        f'{row["hero_id"]} mana regeneration is not 10'
    assert row["max_mana_multiplier"] == "1", \
        f'{row["hero_id"]} mana multiplier is not 1'

generated = read(ROOT / "scripts/vscripts/config/generated/hero_definitions.lua")
assert generated.count("base_mana = 100") == 6, "generated mana values are stale"
assert generated.count("base_mana_regen = 10") == 6, \
    "generated mana regeneration values are stale"

kv = read(ROOT / "scripts/npc/npc_abilities_custom.txt")
block_match = re.search(
    r'"ability_survival_hero_ball_lightning"\s*\{(?P<body>.*?)\n\s*\}',
    kv,
    re.S,
)
assert block_match, "ball lightning ability KV is missing"
block = block_match.group("body")
for key, expected in (
    ("AbilityCastRange", "800"),
    ("AbilityCooldown", "0.0"),
    ("AbilityManaCost", "20"),
):
    assert re.search(rf'"{key}"\s+"{re.escape(expected)}"', block), \
        f"ball lightning {key} contract changed"

ability = read(
    ROOT / "scripts/vscripts/abilities/ability_survival_hero_ball_lightning.lua"
)
motion = read(
    ROOT / "scripts/vscripts/modifiers/modifier_survival_hero_ball_lightning.lua"
)
combined = ability + motion
assert "local MAX_DISTANCE = 800" in ability, "server range cap is missing"
assert "local TRAVEL_SPEED = 7000" in ability, \
    "travel speed is not five times the original 1400"
assert "tonumber(kv.speed) or 7000" in motion, \
    "motion fallback speed is stale"
assert "ApplyHorizontalMotionController" in motion, "horizontal motion is missing"
assert "MODIFIER_STATE_FLYING_FOR_PATHING_PURPOSES_ONLY" in motion, \
    "flight pathing state is missing"
assert "RefundManaCost" in combined, "failure/interruption mana refund is missing"
assert "ApplyDamage" not in combined and "FindUnitsInRadius" not in combined, \
    "movement utility must not search for or damage enemies"

game_mode = read(ROOT / "scripts/vscripts/addon_game_mode.lua")
particle = "particles/units/heroes/hero_stormspirit/stormspirit_ball_lightning.vpcf"
sound = "soundevents/game_sounds_heroes/game_sounds_stormspirit.vsndevts"
assert particle in motion and particle in game_mode, "ball lightning particle is not precached"
assert sound in game_mode, "Storm Spirit sound resource is not precached"

skills = read(ROOT / "scripts/vscripts/systems/hero_skill_system.lua")
assert 'BALL_LIGHTNING_ABILITY = "ability_survival_hero_ball_lightning"' in skills
ball_index = skills.index("ball_lightning:SetAbilityIndex(#state.order)")
return_index = skills.index("return_ability:SetAbilityIndex(#state.order + 1)")
pickup_index = skills.index("pickup_ability:SetAbilityIndex(#state.order + 2)")
assert ball_index < return_index < pickup_index, "hero utility slot order changed"

combat = read(CONTENT / "panorama/scripts/custom_game/combat_stats.js")
hud = read(CONTENT / "panorama/scripts/custom_game/hud_takeover.js")
assert 'ability_survival_hero_ball_lightning: "D"' in combat
assert 'ability_survival_hero_ball_lightning: "D"' in hud
assert re.search(
    r'D:\s*\[\s*"ability_survival_hero_ball_lightning",\s*'
    r'"ability_survival_builder_blink"\s*\]',
    combat,
), "D key does not resolve utility by selected unit"
assert "function quickCastPositionAtCursor" in combat, \
    "cursor quick-cast helper is missing"
assert re.search(
    r'if \(abilityName === "ability_survival_hero_ball_lightning"\)\s*\{\s*'
    r'return quickCastPositionAtCursor\(abilityIndex, unit, source\);',
    combat,
), "hero D does not quick-cast at the cursor"
assert "GameUI.GetCursorPosition()" in combat
assert "GameUI.GetScreenWorldPosition(screen)" in combat
assert 'cancelPointTarget("quick_cast")' in combat
assert 'SendCustomGameEventToServer("ui_ability_cast_position_request"' in combat
assert re.search(
    r'if \(abilityName === "ability_survival_builder_blink"\).*?'
    r'Abilities\.ExecuteAbility\(abilityIndex, unit, false\);',
    combat,
    re.S,
), "Builder D no longer uses its native targeting behavior"

router = read(ROOT / "scripts/vscripts/ui/ui_request_router.lua")
assert re.search(
    r'hero_quickcast\s*=\s*ability_name\s*==\s*'
    r'"ability_survival_hero_ball_lightning"',
    router,
), "server hero point-cast whitelist is missing"
assert "unit:FindAbilityByName(ability_name) == ability" in router
assert "owner_id == player_id" in router
assert "if distance > 800 then" in router and \
    "target = origin + delta:Normalized() * 800" in router, \
    "quick-cast cursor position is not clamped to 800 range"
assert "unit:CastAbilityOnPosition(target, ability, player_id)" in router, \
    "quick-cast does not use the engine position-cast path"

print("HERO_BALL_LIGHTNING_CONTRACT_PASS")