"""Contract checks for monster default hero wearable CSV and generated data."""
from __future__ import annotations

import csv
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CSV_ROOT = ROOT / "data" / "csv"
GENERATED_ROOT = ROOT / "scripts" / "vscripts" / "config" / "generated"

DEFAULT_EXPECTED = {
    "skeleton_melee": "monster_default_wraith_king",
    "skeleton_bone": "monster_default_wraith_king",
    "undead_red_mage_large": "monster_default_lich",
    "undead_red_mage_small": "monster_default_lich",
    "golem_green_fire": "monster_default_warlock",
    "dwarf_white_rifle": "monster_default_sniper",
    "humanoid_red_sword": "monster_default_juggernaut",
}
DEFAULT_COMPONENT_COUNTS = {
    "monster_default_wraith_king": 6,
    "monster_default_lich": 4,
    "monster_default_warlock": 7,
    "monster_default_sniper": 5,
    "monster_default_juggernaut": 5,
}
BOSS_EXPECTED = {
    "rebirth_boss_01": "monster_boss_rebirth_01_phalanx",
    "rebirth_boss_02": "monster_boss_rebirth_02_bloodforge",
    "rebirth_boss_03": "monster_boss_rebirth_03_silverwurm",
    "rebirth_boss_04": "monster_boss_rebirth_04_stormwrought",
    "rebirth_boss_05": "monster_boss_rebirth_05_lucid_torment",
    "rebirth_boss_06": "monster_boss_rebirth_06_obsidian_atrocity",
    "rebirth_boss_07": "monster_boss_rebirth_07_fairy_godmummer",
    "rebirth_boss_08": "monster_boss_rebirth_08_reaper_elegy",
    "rebirth_boss_09": "monster_boss_rebirth_09_phantom_advent",
    "rebirth_boss_10": "monster_boss_rebirth_10_darkness_foretold",
    "ten_sin_01": "monster_boss_ten_sin_01_murid_divine",
    "ten_sin_02": "monster_boss_ten_sin_02_howling_wilds",
    "ten_sin_03": "monster_boss_ten_sin_03_potion_radiance_midas",
    "ten_sin_04": "monster_boss_ten_sin_04_tears",
    "ten_sin_05": "monster_boss_ten_sin_05_feast_damned",
    "ten_sin_06": "monster_boss_ten_sin_06_abscession",
    "ten_sin_07": "monster_boss_ten_sin_07_one_true_king",
    "ten_sin_08": "monster_boss_ten_sin_08_impossible_realm",
    "ten_sin_09": "monster_boss_ten_sin_09_eminence_ristul",
    "ten_sin_10": "monster_boss_ten_sin_10_worldsend",
}
BOSS_COMPONENT_COUNTS = {
    "monster_boss_rebirth_01_phalanx": 3,
    "monster_boss_rebirth_02_bloodforge": 7,
    "monster_boss_rebirth_03_silverwurm": 6,
    "monster_boss_rebirth_04_stormwrought": 6,
    "monster_boss_rebirth_05_lucid_torment": 4,
    "monster_boss_rebirth_06_obsidian_atrocity": 4,
    "monster_boss_rebirth_07_fairy_godmummer": 5,
    "monster_boss_rebirth_08_reaper_elegy": 4,
    "monster_boss_rebirth_09_phantom_advent": 5,
    "monster_boss_rebirth_10_darkness_foretold": 7,
    "monster_boss_ten_sin_01_murid_divine": 5,
    "monster_boss_ten_sin_02_howling_wilds": 6,
    "monster_boss_ten_sin_03_potion_radiance_midas": 7,
    "monster_boss_ten_sin_04_tears": 2,
    "monster_boss_ten_sin_05_feast_damned": 4,
    "monster_boss_ten_sin_06_abscession": 1,
    "monster_boss_ten_sin_07_one_true_king": 6,
    "monster_boss_ten_sin_08_impossible_realm": 4,
    "monster_boss_ten_sin_09_eminence_ristul": 4,
    "monster_boss_ten_sin_10_worldsend": 4,
}
BOSS_MODELS = {
    "rebirth_boss_01": "models/heroes/undying/undying.vmdl",
    "rebirth_boss_02": "models/heroes/blood_seeker/blood_seeker.vmdl",
    "rebirth_boss_03": "models/heroes/dragon_knight/dragon_knight.vmdl",
    "rebirth_boss_04": "models/heroes/sven/sven.vmdl",
    "rebirth_boss_05": "models/heroes/bane/bane.vmdl",
    "rebirth_boss_06": "models/heroes/life_stealer/life_stealer.vmdl",
    "rebirth_boss_07": "models/heroes/dark_willow/dark_willow.vmdl",
    "rebirth_boss_08": "models/heroes/grimstroke/grimstroke.vmdl",
    "rebirth_boss_09": "models/items/spectre/spectre_arcana/spectre_arcana_base.vmdl",
    "rebirth_boss_10": "models/heroes/doom/doom.vmdl",
    "ten_sin_01": "models/heroes/necrolyte/necrolyte.vmdl",
    "ten_sin_02": "models/heroes/rikimaru/rikimaru.vmdl",
    "ten_sin_03": "models/heroes/alchemist/alchemist.vmdl",
    "ten_sin_04": "models/heroes/morphling/morphling.vmdl",
    "ten_sin_05": "models/heroes/ursa/ursa.vmdl",
    "ten_sin_06": "models/items/pudge/arcana/pudge_arcana_base.vmdl",
    "ten_sin_07": "models/items/wraith_king/arcana/wraith_king_arcana.vmdl",
    "ten_sin_08": "models/heroes/rubick/rubick.vmdl",
    "ten_sin_09": "models/items/queenofpain/queenofpain_arcana/queenofpain_arcana.vmdl",
    "ten_sin_10": "models/heroes/mars/mars.vmdl",
}
BOSS_PORTRAITS = {
    "rebirth_boss_01": "npc_dota_hero_undying",
    "rebirth_boss_02": "npc_dota_hero_bloodseeker",
    "rebirth_boss_03": "npc_dota_hero_dragon_knight",
    "rebirth_boss_04": "npc_dota_hero_sven",
    "rebirth_boss_05": "npc_dota_hero_bane",
    "rebirth_boss_06": "npc_dota_hero_life_stealer",
    "rebirth_boss_07": "npc_dota_hero_dark_willow",
    "rebirth_boss_08": "npc_dota_hero_grimstroke",
    "rebirth_boss_09": "npc_dota_hero_spectre",
    "rebirth_boss_10": "npc_dota_hero_doom",
    "ten_sin_01": "npc_dota_hero_necrolyte",
    "ten_sin_02": "npc_dota_hero_riki",
    "ten_sin_03": "npc_dota_hero_alchemist",
    "ten_sin_04": "npc_dota_hero_morphling",
    "ten_sin_05": "npc_dota_hero_ursa",
    "ten_sin_06": "npc_dota_hero_pudge",
    "ten_sin_07": "npc_dota_hero_skeleton_king",
    "ten_sin_08": "npc_dota_hero_rubick",
    "ten_sin_09": "npc_dota_hero_queenofpain",
    "ten_sin_10": "npc_dota_hero_mars",
}
BOSS_BUNDLES = dict(zip(BOSS_EXPECTED.values(), (
    "21184", "21411", "21718", "20809", "23213",
    "23450", "34390", "28272", "21361", "25144",
    "21195", "21589", "30833+7627+9568", "7603+6833", "23335",
    "21188", "21402", "21376", "21416", "36244",
)))
EXPECTED = {**DEFAULT_EXPECTED, **BOSS_EXPECTED}
EXPECTED_COMPONENT_COUNTS = {
    **DEFAULT_COMPONENT_COUNTS,
    **BOSS_COMPONENT_COUNTS,
}
EXPECTED_CHALLENGES = {
    "challenge_monster_04": "monster_default_juggernaut",
}
EXCLUDED = {
    "boss_dreadlord",
    "golem_gray_small",
    "golem_gray_large",
    "flying_green_head",
    "flying_black_bone",
    "carpet_red_large",
    "carpet_red_small",
}


def read_csv(relative: str) -> tuple[list[str], list[dict[str, str]]]:
    path = CSV_ROOT / relative
    with path.open(encoding="utf-8-sig", newline="") as handle:
        rows = list(csv.reader(handle))
    assert rows, f"empty CSV: {path}"
    header = rows[0]
    result = []
    for line_number, row in enumerate(rows[1:], 2):
        if not row or not row[0].strip() or row[0].strip().startswith("#"):
            continue
        assert len(row) == len(header), (
            f"CSV width mismatch: {path}:{line_number} "
            f"has {len(row)}, expected {len(header)}"
        )
        result.append(dict(zip(header, row)))
    return header, result


def main() -> int:
    archetype_header, archetype_rows = read_csv(
        "怪物与波次系统/monster_archetypes.csv"
    )
    challenge_header, challenge_rows = read_csv(
        "挑战与奖励系统/building_challenge_definitions.csv"
    )
    catalog_header, catalog_rows = read_csv("资源系统/asset_catalog.csv")
    component_header, components = read_csv("资源系统/asset_components.csv")
    _, wave_rows = read_csv("怪物与波次系统/wave_definitions.csv")
    assert len(archetype_header) == 26
    assert archetype_header[-1] == "default_wearable_asset_id"
    assert len(challenge_header) == 20
    assert challenge_header[-1] == "default_wearable_asset_id"
    assert len(catalog_header) == 27
    assert len(component_header) == 15

    archetypes = {
        row["archetype_id"]: row
        for row in archetype_rows
    }
    catalog = {
        row["asset_id"]: row
        for row in catalog_rows
    }
    challenges = {row["challenge_id"]: row for row in challenge_rows}
    component_counts: dict[str, int] = {}
    for row in components:
        if row["asset_id"].startswith(("monster_default_", "monster_boss_")):
            assert row["entity_class"] == "prop_dynamic"
            assert row["attach_mode"] == "bone_merge"
            component_counts[row["asset_id"]] = component_counts.get(
                row["asset_id"], 0
            ) + 1

    assert {
        asset_id
        for asset_id in catalog
        if asset_id.startswith("monster_default_")
    } == set(DEFAULT_EXPECTED.values())
    assert {
        asset_id
        for asset_id in catalog
        if asset_id.startswith("monster_boss_")
    } == set(BOSS_EXPECTED.values())
    for archetype_id, asset_id in EXPECTED.items():
        row = archetypes[archetype_id]
        asset = catalog[asset_id]
        assert row["default_wearable_asset_id"] == asset_id
        assert row["model_path"] == asset["primary_model"]
        assert component_counts[asset_id] == EXPECTED_COMPONENT_COUNTS[asset_id]
        assert asset["load_group"] == "monster_default_wearables"
        assert not asset["attachment_models"]

    for archetype_id, asset_id in BOSS_EXPECTED.items():
        archetype = archetypes[archetype_id]
        asset = catalog[asset_id]
        assert archetype["model_path"] == BOSS_MODELS[archetype_id]
        assert not archetype["model_asset_id"]
        assert asset["portrait_unit_name"] == BOSS_PORTRAITS[archetype_id]
        assert not asset["portrait_item_def"]
        assert f"bundle/item证据={BOSS_BUNDLES[asset_id]}" in asset["notes"]

    alchemist_notes = {
        row["notes"] for row in components
        if row["asset_id"] == BOSS_EXPECTED["ten_sin_03"]
    }
    assert any("ItemDef 7627" in note for note in alchemist_notes)
    assert any("ItemDef 9568" in note for note in alchemist_notes)

    assert {
        challenge_id: row["default_wearable_asset_id"]
        for challenge_id, row in challenges.items()
        if row["default_wearable_asset_id"]
    } == EXPECTED_CHALLENGES
    for challenge_id, asset_id in EXPECTED_CHALLENGES.items():
        assert challenges[challenge_id]["model_path"] == catalog[asset_id]["primary_model"]

    for archetype_id in EXCLUDED:
        assert not archetypes[archetype_id]["default_wearable_asset_id"]
    for row in archetypes.values():
        assert not (
            row["default_wearable_asset_id"] and row["model_asset_id"]
        ), f"special asset precedence conflict: {row['archetype_id']}"

    wave_assets: dict[int, set[str]] = {}
    for row in wave_rows:
        archetype = archetypes[row["archetype_id"]]
        asset_id = archetype["default_wearable_asset_id"]
        if asset_id:
            wave_assets.setdefault(int(row["wave_number"]), set()).add(asset_id)
    assert wave_assets.get(3) == {"monster_default_wraith_king"}
    formal_preload_assets = set().union(
        *(assets for wave, assets in wave_assets.items() if 6 <= wave <= 30)
    )
    assert formal_preload_assets == set(DEFAULT_COMPONENT_COUNTS)

    generated_archetypes = (
        GENERATED_ROOT / "monster_archetypes.lua"
    ).read_text(encoding="utf-8-sig")
    generated_catalog = (
        GENERATED_ROOT / "asset_catalog.lua"
    ).read_text(encoding="utf-8-sig")
    generated_components = (
        GENERATED_ROOT / "asset_components.lua"
    ).read_text(encoding="utf-8-sig")
    generated_challenges = (
        GENERATED_ROOT / "building_challenge_definitions.lua"
    ).read_text(encoding="utf-8-sig")
    for archetype_id, asset_id in EXPECTED.items():
        assert f'archetype_id = "{archetype_id}"' in generated_archetypes
        assert f'default_wearable_asset_id = "{asset_id}"' in generated_archetypes
    for asset_id in EXPECTED.values():
        assert f'asset_id = "{asset_id}"' in generated_catalog
        assert f'asset_id = "{asset_id}"' in generated_components
    for challenge_id, asset_id in EXPECTED_CHALLENGES.items():
        assert f'challenge_id = "{challenge_id}"' in generated_challenges
        assert f'default_wearable_asset_id = "{asset_id}"' in generated_challenges

    wave_system = (
        ROOT / "scripts" / "vscripts" / "systems" / "wave_system.lua"
    ).read_text(encoding="utf-8-sig")
    addon_game_mode = (
        ROOT / "scripts" / "vscripts" / "addon_game_mode.lua"
    ).read_text(encoding="utf-8-sig")
    assert "resources_for_assets(" in wave_system
    assert "number < 6 or number > 30" in wave_system
    assert 'precache_group(context, "monster_default_wearables")' in addon_game_mode

    print(
        "MONSTER_HERO_WEARABLE_CONTRACT_PASS "
        f"assets={len(set(EXPECTED.values()))} mappings={len(EXPECTED)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
