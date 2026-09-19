"""Synchronize the first rebirth/ten-sin boss cosmetic batch."""
from __future__ import annotations

import argparse
import csv
import io
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RESOURCE_ROOT = ROOT / "data" / "csv" / "资源系统"
ARCHETYPE_PATH = ROOT / "data" / "csv" / "怪物与波次系统" / "monster_archetypes.csv"
NPC_UNITS = ROOT / "scripts" / "npc" / "npc_units_custom.txt"
MARKER_BEGIN = "    // BEGIN BOSS_COSMETIC_BATCH"
MARKER_END = "    // END BOSS_COSMETIC_BATCH"

PORTRAIT_UNITS = {
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


def c(component_id: str, item_def: str, model_path: str, note: str = "") -> tuple[str, str, str, str]:
    return component_id, item_def, model_path, note


def fx(effect_id: str, path: str, owner: str = "") -> tuple[str, str, str]:
    return effect_id, path, owner


SPECS = {
    "rebirth_boss_01": {
        "asset_id": "monster_boss_rebirth_01_phalanx",
        "display": "一转Boss Phalanx of the Fallen Spear 失落战矛方阵",
        "body": "models/heroes/undying/undying.vmdl",
        "bundle": "21184",
        "components": [
            c("armor", "9718", "models/items/undying/deathmatch_dominator_armor/deathmatch_dominator_armor.vmdl"),
            c("head", "9717", "models/items/undying/deathmatch_dominator_head/deathmatch_dominator_head.vmdl"),
            c("arms", "9716", "models/items/undying/deathmatch_dominator_arms/deathmatch_dominator_arms.vmdl"),
        ],
    },
    "rebirth_boss_02": {
        "asset_id": "monster_boss_rebirth_02_bloodforge",
        "display": "二转Boss Fury of the Bloodforge 血锻狂怒",
        "body": "models/heroes/blood_seeker/blood_seeker.vmdl",
        "bundle": "21411",
        "components": [
            c("weapon", "13444", "models/items/blood_seeker/ti9_cache_bloodseeker_boiling_blood_weapon/ti9_cache_bloodseeker_boiling_blood_weapon.vmdl"),
            c("shoulder", "13445", "models/items/blood_seeker/ti9_cache_bloodseeker_boiling_blood_shoulder/ti9_cache_bloodseeker_boiling_blood_shoulder.vmdl"),
            c("offhand", "13443", "models/items/blood_seeker/ti9_cache_bloodseeker_boiling_blood_off_hand/ti9_cache_bloodseeker_boiling_blood_off_hand.vmdl"),
            c("head", "13446", "models/items/blood_seeker/ti9_cache_bloodseeker_boiling_blood_head/ti9_cache_bloodseeker_boiling_blood_head.vmdl"),
            c("belt", "13447", "models/items/blood_seeker/ti9_cache_bloodseeker_boiling_blood_belt/ti9_cache_bloodseeker_boiling_blood_belt.vmdl"),
            c("back", "13448", "models/items/blood_seeker/ti9_cache_bloodseeker_boiling_blood_back/ti9_cache_bloodseeker_boiling_blood_back.vmdl"),
            c("arms", "13449", "models/items/blood_seeker/ti9_cache_bloodseeker_boiling_blood_arms/ti9_cache_bloodseeker_boiling_blood_arms.vmdl"),
        ],
        "effects": [
            fx("ambient_weapon", "particles/econ/items/bloodseeker/ti9_bs_boiling_blood_weapon/ti9_bloodseeker_blood_weapon_ambient.vpcf", "weapon"),
            fx("ambient_shoulder", "particles/econ/items/bloodseeker/ti9_bs_boiling_blood_shoulders/ti9_bs_boiling_blood_shoulders_ambient.vpcf", "shoulder"),
            fx("ambient_offhand", "particles/econ/items/bloodseeker/ti9_bs_boiling_blood_off_hand/ti9_bloodseeker_blood_off_hand_ambient.vpcf", "offhand"),
            fx("ambient_head", "particles/econ/items/bloodseeker/ti9_bs_boiling_blood_head/ti9_bloodseeker_blood_head_ambient.vpcf", "head"),
        ],
    },
    "rebirth_boss_03": {
        "asset_id": "monster_boss_rebirth_03_silverwurm",
        "display": "三转Boss Silverwurm Sacrifice 银龙之祭",
        "body": "models/heroes/dragon_knight/dragon_knight.vmdl",
        "bundle": "21718",
        "components": [
            c("arms", "18001", "models/items/dragon_knight/silver_dragon_king_arms/silver_dragon_king_arms.vmdl"),
            c("back", "18000", "models/items/dragon_knight/silver_dragon_king_back/silver_dragon_king_back.vmdl"),
            c("head", "17998", "models/items/dragon_knight/silver_dragon_king_head/silver_dragon_king_head.vmdl"),
            c("offhand", "17969", "models/items/dragon_knight/silver_dragon_king_off_hand/silver_dragon_king_off_hand.vmdl"),
            c("shoulder", "17968", "models/items/dragon_knight/silver_dragon_king_shoulder/silver_dragon_king_shoulder.vmdl"),
            c("weapon", "17967", "models/items/dragon_knight/silver_dragon_king_weapon/silver_dragon_king_weapon.vmdl"),
        ],
    },
    "rebirth_boss_04": {
        "asset_id": "monster_boss_rebirth_04_stormwrought",
        "display": "四转Boss Stormwrought Arbiter 暴风之锻裁决者",
        "body": "models/heroes/sven/sven.vmdl",
        "bundle": "20809",
        "components": [
            c("belt", "7290", "models/items/sven/arbiter_belt/arbiter_belt.vmdl"),
            c("shoulder", "7284", "models/items/sven/arbiter_shoulder/arbiter_shoulder.vmdl"),
            c("back", "7283", "models/items/sven/arbiter_back/arbiter_back.vmdl"),
            c("head", "7282", "models/items/sven/arbiter_head/arbiter_head.vmdl"),
            c("weapon", "7281", "models/items/sven/arbiter_weapon/arbiter_weapon.vmdl"),
            c("arms", "7280", "models/items/sven/arbiter_arms/arbiter_arms.vmdl"),
        ],
    },
    "rebirth_boss_05": {
        "asset_id": "monster_boss_rebirth_05_lucid_torment",
        "display": "五转Boss Summer Lineage Lucid Torment 盛夏传世无休折磨",
        "body": "models/heroes/bane/bane.vmdl",
        "bundle": "23213",
        "components": [
            c("shoulder", "23214", "models/items/bane/bane_gear_shoulder/bane_gear_shoulder.vmdl"),
            c("arms", "23215", "models/items/bane/bane_gear_arms/bane_gear_arms.vmdl"),
            c("back", "23216", "models/items/bane/bane_gear_back/bane_gear_back.vmdl"),
            c("head", "23217", "models/items/bane/bane_gear_head/bane_gear_head.vmdl"),
        ],
    },
    "rebirth_boss_06": {
        "asset_id": "monster_boss_rebirth_06_obsidian_atrocity",
        "display": "六转Boss Obsidian Atrocity 黑曜恶行",
        "body": "models/heroes/life_stealer/life_stealer.vmdl",
        "bundle": "23450",
        "components": [
            c("head", "23451", "models/items/lifestealer/lavastealer_head/lavastealer_head.vmdl"),
            c("back", "23452", "models/items/lifestealer/lavastealer_back/lavastealer_back.vmdl"),
            c("arms", "23453", "models/items/lifestealer/lavastealer_arms/lavastealer_arms.vmdl"),
            c("belt", "23454", "models/items/lifestealer/lavastealer_belt/lavastealer_belt.vmdl"),
        ],
        "effects": [fx("ambient_back", "particles/econ/items/lifestealer/lifestealer_2022_themed/lifestealer_2022_themed_back_ambient.vpcf", "back")],
    },
    "rebirth_boss_07": {
        "asset_id": "monster_boss_rebirth_07_fairy_godmummer",
        "display": "七转Boss Fairy Godmummer 邪魅仙娘",
        "body": "models/heroes/dark_willow/dark_willow.vmdl",
        "bundle": "34390",
        "components": [
            c("armor", "34392", "models/items/dark_willow/dark_willow_dark_carnival/dark_willow_dark_carnival_armor.vmdl"),
            c("head", "34393", "models/items/dark_willow/dark_willow_dark_carnival/dark_willow_dark_carnival_head.vmdl"),
            c("offhand", "36267", "models/items/dark_willow/dark_willow_dark_carnival/dark_willow_dark_carnival_offhand.vmdl"),
            c("belt", "36268", "models/items/dark_willow/dark_willow_dark_carnival/dark_willow_dark_carnival_belt.vmdl"),
            c("back", "36269", "models/items/dark_willow/dark_willow_dark_carnival/dark_willow_dark_carnival_back.vmdl"),
        ],
        "effects": [fx("ambient_offhand", "particles/units/heroes/hero_dark_willow/dark_willow_lantern_ambient_fairy.vpcf", "offhand")],
    },
    "rebirth_boss_08": {
        "asset_id": "monster_boss_rebirth_08_reaper_elegy",
        "display": "八转Boss Elegy of the Reaper 收割者哀歌",
        "body": "models/heroes/grimstroke/grimstroke.vmdl",
        "bundle": "28272",
        "components": [
            c("weapon", "27490", "models/items/grimstroke/grimreaver_scythe/grimreaver_scythe.vmdl"),
            c("head", "27489", "models/items/grimstroke/grimreaver_hood/grimreaver_hood.vmdl"),
            c("belt", "27488", "models/items/grimstroke/grimreaver_belt/grimreaver_belt.vmdl"),
            c("armor", "27487", "models/items/grimstroke/grimreaver_armor/grimreaver_armor.vmdl"),
        ],
        "effects": [
            fx("ambient_weapon", "particles/econ/items/grimstroke/gs_cc_2024_grimreaver/gs_cc_2024_grimreaver_weapon_ambient.vpcf", "weapon"),
            fx("ambient_head", "particles/econ/items/grimstroke/gs_cc_2024_grimreaver/gs_cc_2024_grimreaver_head_ambient.vpcf", "head"),
            fx("ambient_belt", "particles/econ/items/grimstroke/gs_cc_2024_grimreaver/gs_cc_2024_grimreaver_belt_ambient.vpcf", "belt"),
        ],
    },
    "rebirth_boss_09": {
        "asset_id": "monster_boss_rebirth_09_phantom_advent",
        "display": "九转Boss Phantom Advent 幽鬼现世",
        "body": "models/items/spectre/spectre_arcana/spectre_arcana_base.vmdl",
        "bundle": "21361",
        "components": [
            c("head", "9662", "models/items/spectre/spectre_arcana/spectre_arcana_head.vmdl"),
            c("shoulder", "9663", "models/items/spectre/spectre_arcana/spectre_arcana_shoulder.vmdl"),
            c("weapon", "12312", "models/items/spectre/spectre_arcana/spectre_arcana_weapon.vmdl"),
            c("bracers", "12313", "models/items/spectre/spectre_arcana/spectre_arcana_misc.vmdl"),
            c("belt", "12314", "models/items/spectre/spectre_arcana/spectre_arcana_skirt.vmdl"),
        ],
        "effects": [
            fx("ambient_body", "particles/econ/items/spectre/spectre_arcana/spectre_arcana_ambient.vpcf"),
            fx("ambient_head", "particles/econ/items/spectre/spectre_arcana/spectre_arcana_ambient_head.vpcf", "head"),
            fx("ambient_shoulder", "particles/econ/items/spectre/spectre_arcana/spectre_arcana_ambient_shoulder.vpcf", "shoulder"),
            fx("ambient_weapon", "particles/econ/items/spectre/spectre_arcana/spectre_arcana_weapon_ambient.vpcf", "weapon"),
            fx("ambient_bracers", "particles/econ/items/spectre/spectre_arcana/spectre_arcana_ambient_bracers.vpcf", "bracers"),
            fx("ambient_belt", "particles/econ/items/spectre/spectre_arcana/spectre_arcana_ambient_skirt.vpcf", "belt"),
        ],
    },
    "rebirth_boss_10": {
        "asset_id": "monster_boss_rebirth_10_darkness_foretold",
        "display": "十转Boss Dawn of a Darkness Foretold 黑暗预言的黎明",
        "body": "models/heroes/doom/doom.vmdl",
        "bundle": "25144",
        "components": [
            c("arms", "25400", "models/items/doom/doom_cthulhu_arms/doom_cthulhu_arms.vmdl"),
            c("back", "25399", "models/items/doom/doom_cthulhu_back/doom_cthulhu_back.vmdl"),
            c("belt", "25401", "models/items/doom/doom_cthulhu_belt/doom_cthulhu_belt.vmdl"),
            c("head", "25314", "models/items/doom/doom_cthulhu_head/doom_cthulhu_head.vmdl"),
            c("shoulder", "25396", "models/items/doom/doom_cthulhu_shoulder/doom_cthulhu_shoulder.vmdl"),
            c("tail", "25398", "models/items/doom/doom_cthulhu_tail/doom_cthulhu_tail.vmdl"),
            c("weapon", "25397", "models/items/doom/doom_cthulhu_weapon/doom_cthulhu_weapon.vmdl"),
        ],
        "effects": [
            fx("ambient_back", "particles/econ/items/doom/doom_cthulhu_wings/doom_cthulhu_wings_cloth_ambient.vpcf", "back"),
            fx("ambient_belt", "particles/econ/items/doom/doom_cthulhu_belt/doom_cthulhu_belt_cloth_ambient.vpcf", "belt"),
            fx("ambient_head", "particles/econ/items/doom/doom_cthulhu_head/doom_cthulhu_head_ambient.vpcf", "head"),
            fx("ambient_shoulder", "particles/econ/items/doom/doom_cthulhu_shoulder/doom_cthulhu_shoulder_ambient.vpcf", "shoulder"),
            fx("ambient_tail", "particles/econ/items/doom/doom_cthulhu_tail/doom_cthulhu_tail_ambient.vpcf", "tail"),
        ],
    },
    "ten_sin_01": {
        "asset_id": "monster_boss_ten_sin_01_murid_divine",
        "display": "十宗罪一 The Murid Divine 鼠神",
        "body": "models/heroes/necrolyte/necrolyte.vmdl",
        "bundle": "21195",
        "components": [
            c("weapon", "9842", "models/items/necrolyte/ti8_necro_disaster_of_pestilence_weapon/ti8_necro_disaster_of_pestilence_weapon.vmdl"),
            c("shoulder", "9841", "models/items/necrolyte/ti8_necro_disaster_of_pestilence_robe/ti8_necro_disaster_of_pestilence_robe.vmdl"),
            c("legs", "9840", "models/items/necrolyte/ti8_necro_disaster_of_pestilence_legs/ti8_necro_disaster_of_pestilence_legs.vmdl"),
            c("head", "9839", "models/items/necrolyte/ti8_necro_disaster_of_pestilence_head/ti8_necro_disaster_of_pestilence_head.vmdl"),
            c("beard", "9838", "models/items/necrolyte/ti8_necro_disaster_of_pestilence_beard/ti8_necro_disaster_of_pestilence_beard.vmdl"),
        ],
    },
    "ten_sin_02": {
        "asset_id": "monster_boss_ten_sin_02_howling_wilds",
        "display": "十宗罪二 Hunger of the Howling Wilds 呼啸荒野的渴望",
        "body": "models/heroes/rikimaru/rikimaru.vmdl",
        "bundle": "21589",
        "components": [
            c("arms", "14776", "models/items/rikimaru/riki_killer_of_purple_smoke_arms/riki_killer_of_purple_smoke_arms.vmdl"),
            c("head", "14775", "models/items/rikimaru/riki_killer_of_purple_smoke_head/riki_killer_of_purple_smoke_head.vmdl"),
            c("offhand", "14774", "models/items/rikimaru/riki_killer_of_purple_smoke_off_hand/riki_killer_of_purple_smoke_off_hand.vmdl"),
            c("shoulder", "14773", "models/items/rikimaru/riki_killer_of_purple_smoke_shoulder/riki_killer_of_purple_smoke_shoulder.vmdl"),
            c("tail", "14772", "models/items/rikimaru/riki_killer_of_purple_smoke_tail/riki_killer_of_purple_smoke_tail.vmdl"),
            c("weapon", "14771", "models/items/rikimaru/riki_killer_of_purple_smoke_weapon/riki_killer_of_purple_smoke_weapon.vmdl"),
        ],
    },
    "ten_sin_03": {
        "asset_id": "monster_boss_ten_sin_03_potion_radiance_midas",
        "display": "十宗罪三 Potion Potentate + Eternal Radiance + Midas Knuckles",
        "body": "models/heroes/alchemist/alchemist.vmdl",
        "bundle": "30833+7627+9568",
        "components": [
            c("shoulder", "30797", "models/items/alchemist/royal_bartender_knight_shoulders/royal_bartender_knight_shoulders.vmdl"),
            c("offhand", "30796", "models/items/alchemist/royal_bartender_knight_offhand/royal_bartender_knight_offhand.vmdl"),
            c("neck", "30791", "models/items/alchemist/royal_bartender_knight_neck/royal_bartender_knight_neck.vmdl"),
            c("back", "30790", "models/items/alchemist/royal_bartender_knight_back/royal_bartender_knight_back.vmdl"),
            c("armor", "30781", "models/items/alchemist/royal_bartender_knight_armor/royal_bartender_knight_armor.vmdl"),
            c("weapon", "7627", "models/items/alchemist/twin_blades_aurelian/twin_blades_aurelian.vmdl", "永世之辉耀覆盖药剂之君武器槽"),
            c("arms", "9568", "models/items/alchemist/midasknuckles/midasknuckles.vmdl", "拉泽尔的迈达斯指套覆盖药剂之君手臂槽"),
        ],
        "effects": [
            fx("ambient_weapon_left", "particles/econ/items/alchemist/alchemist_aurelian_weapon/alchemist_ambient_aurelian_l.vpcf", "weapon"),
            fx("ambient_weapon_right", "particles/econ/items/alchemist/alchemist_aurelian_weapon/alchemist_ambient_aurelian_r.vpcf", "weapon"),
            fx("ambient_arms", "particles/econ/items/alchemist/alchemist_midas_knuckles/alch_ambient_knuckles.vpcf", "arms"),
        ],
    },
    "ten_sin_04": {
        "asset_id": "monster_boss_ten_sin_04_tears",
        "display": "十宗罪四 Crown of Tears + Blade of Tears",
        "body": "models/heroes/morphling/morphling.vmdl",
        "bundle": "7603+6833",
        "components": [
            c("head", "7603", "models/items/morphling/crown_of_tears/mesh/crown_of_tears_model.vmdl"),
            c("arms", "6833", "models/items/morphling/ethereal_blade/ethereal_blade.vmdl"),
        ],
        "effects": [
            fx("ambient_head", "particles/econ/items/morphling/morphling_crown_of_tears/morphling_crown_ambient.vpcf", "head"),
            fx("ambient_arms", "particles/econ/items/morphling/morphling_ethereal/morphling_ethereal_ambient.vpcf", "arms"),
        ],
    },
    "ten_sin_05": {
        "asset_id": "monster_boss_ten_sin_05_feast_damned",
        "display": "十宗罪五 Feast of the Damned 邪魇盛宴",
        "body": "models/heroes/ursa/ursa.vmdl",
        "bundle": "23335",
        "components": [
            c("belt", "23334", "models/items/ursa/deathlord_belt/deathlord_belt.vmdl"),
            c("arms", "23333", "models/items/ursa/deathlord_arms/deathlord_arms.vmdl"),
            c("head", "23332", "models/items/ursa/deathlord_head/deathlord_head.vmdl"),
            c("back", "23331", "models/items/ursa/deathlord_back/deathlord_back.vmdl"),
        ],
    },
    "ten_sin_06": {
        "asset_id": "monster_boss_ten_sin_06_abscession",
        "display": "十宗罪六 Feast of Abscession 千劫神屠",
        "body": "models/items/pudge/arcana/pudge_arcana_base.vmdl",
        "bundle": "21188",
        "components": [c("back", "29687", "models/items/pudge/arcana/pudge_arcana_back.vmdl")],
        "effects": [
            fx("ambient_body", "particles/econ/items/pudge/pudge_arcana/pudge_arcana_base_ambient.vpcf"),
            fx("ambient_back", "particles/econ/items/pudge/pudge_arcana/pudge_arcana_back_ambient.vpcf", "back"),
        ],
    },
    "ten_sin_07": {
        "asset_id": "monster_boss_ten_sin_07_one_true_king",
        "display": "十宗罪七 The One True King",
        "body": "models/items/wraith_king/arcana/wraith_king_arcana.vmdl",
        "bundle": "21402",
        "components": [
            c("weapon", "13760", "models/items/wraith_king/arcana/wraith_king_arcana_weapon.vmdl"),
            c("arms", "13743", "models/items/wraith_king/arcana/wraith_king_arcana_arms.vmdl"),
            c("shoulder", "13571", "models/items/wraith_king/arcana/wraith_king_arcana_shoulder.vmdl"),
            c("armor", "13569", "models/items/wraith_king/arcana/wraith_king_arcana_armor.vmdl"),
            c("back", "13473", "models/items/wraith_king/arcana/wraith_king_arcana_back.vmdl"),
            c("head", "13456", "models/items/wraith_king/arcana/wraith_king_arcana_head.vmdl"),
        ],
        "effects": [
            fx("ambient_body", "particles/econ/items/wraith_king/wraith_king_arcana/wk_arc_ambient.vpcf"),
            fx("ambient_head", "particles/econ/items/wraith_king/wraith_king_arcana/wk_arc_ambient_head.vpcf", "head"),
        ],
    },
    "ten_sin_08": {
        "asset_id": "monster_boss_ten_sin_08_impossible_realm",
        "display": "十宗罪八 Avatar of the Impossible Realm 虚幻之境的化身",
        "body": "models/heroes/rubick/rubick.vmdl",
        "bundle": "21376",
        "components": [
            c("shoulder", "13268", "models/items/rubick/ti9_cache_rubick_ancient_magus_shoulder/ti9_cache_rubick_ancient_magus_shoulder.vmdl"),
            c("head", "13267", "models/items/rubick/ti9_cache_rubick_ancient_magus_head/ti9_cache_rubick_ancient_magus_head.vmdl"),
            c("weapon", "13266", "models/items/rubick/ti9_cache_rubick_ancient_magus_weapon/ti9_cache_rubick_ancient_magus_weapon.vmdl"),
            c("back", "13265", "models/items/rubick/ti9_cache_rubick_ancient_magus_back/ti9_cache_rubick_ancient_magus_back.vmdl"),
        ],
        "effects": [
            fx("ambient_head", "particles/econ/items/rubick/rubick_ti9_cache_magus_head/rubick_ti9_cache_magus_head_ambient.vpcf", "head"),
            fx("ambient_weapon", "particles/econ/items/rubick/rubick_ti9_cache_magus_weapon/rubick_ti9_cache_magus_weapon_ambient.vpcf", "weapon"),
            fx("ambient_back", "particles/econ/items/rubick/rubick_ti9_cache_magus_back/rubick_ti9_cache_magus_back_ambient.vpcf", "back"),
        ],
    },
    "ten_sin_09": {
        "asset_id": "monster_boss_ten_sin_09_eminence_ristul",
        "display": "十宗罪九 The Eminence of Ristul 魔廷新尊",
        "body": "models/items/queenofpain/queenofpain_arcana/queenofpain_arcana.vmdl",
        "bundle": "21416",
        "components": [
            c("head", "13769", "models/items/queenofpain/queenofpain_arcana/queenofpain_arcana_head.vmdl"),
            c("shoulder", "13768", "models/items/queenofpain/queenofpain_arcana/queenofpain_arcana_armor.vmdl", "Arcana主体使用官方refit护甲"),
            c("weapon", "13770", "models/items/queenofpain/queenofpain_arcana/queenofpain_arcana_dagger.vmdl"),
            c("back", "12930", "models/items/queenofpain/queenofpain_arcana/queenofpain_arcana_wings.vmdl"),
        ],
        "effects": [
            fx("ambient_body", "particles/econ/items/queen_of_pain/qop_arcana/qop_arcana_feet_ambient.vpcf"),
            fx("ambient_head", "particles/econ/items/queen_of_pain/qop_arcana/qop_arcana_head_ambient.vpcf", "head"),
            fx("ambient_weapon", "particles/econ/items/queen_of_pain/qop_arcana/qop_arcana_blade_ambient.vpcf", "weapon"),
            fx("ambient_back", "particles/econ/items/queen_of_pain/qop_arcana/qop_arcana_wings_ambient.vpcf", "back"),
        ],
    },
    "ten_sin_10": {
        "asset_id": "monster_boss_ten_sin_10_worldsend",
        "display": "十宗罪十 WorldsEnd 绝世",
        "body": "models/heroes/mars/mars.vmdl",
        "bundle": "36244",
        "components": [
            c("weapon", "36247", "models/items/mars/mars_ragnarok_weapon_alt/mars_ragnarok_weapon_alt.vmdl"),
            c("legs", "36245", "models/items/mars/mars_ragnarok_legs_alt/mars_ragnarok_legs_alt.vmdl"),
            c("armor", "36243", "models/items/mars/mars_ragnarok_armor_alt/mars_ragnarok_armor_alt.vmdl"),
            c("offhand", "36246", "models/items/mars/mars_ragnarok_offhand_weapon_alt/mars_ragnarok_offhand_weapon_alt.vmdl"),
        ],
        "effects": [
            fx("ambient_weapon", "particles/econ/items/mars/mars_ragnarok/mars_ragnarok_weapon_alt_ambient.vpcf", "weapon"),
            fx("ambient_armor", "particles/econ/items/mars/mars_ragnarok/mars_ragnarok_armor_alt_ambient.vpcf", "armor"),
            fx("ambient_offhand", "particles/econ/items/mars/mars_ragnarok/mars_ragnarok_offhand_ambient.vpcf", "offhand"),
        ],
    },
}


def read_csv_document(path: Path):
    raw = path.read_bytes()
    bom = raw.startswith(b"\xef\xbb\xbf")
    text = raw.decode("utf-8-sig")
    newline = "\r\n" if "\r\n" in text else "\n"
    return list(csv.reader(io.StringIO(text, newline=""))), bom, newline, raw


def render_csv(rows: list[list[str]], bom: bool, newline: str) -> bytes:
    output = io.StringIO(newline="")
    csv.writer(output, lineterminator=newline).writerows(rows)
    return (("\ufeff" if bom else "") + output.getvalue()).encode("utf-8")


def replace_data_rows(path: Path, identity_header: str, identities: set[str], new_rows: list[dict[str, str]], check: bool) -> bool:
    rows, bom, newline, raw = read_csv_document(path)
    headers = rows[0]
    identity_index = headers.index(identity_header)
    retained = [rows[0]]
    for row in rows[1:]:
        if not row or row[0].startswith("#") or len(row) <= identity_index or row[identity_index] not in identities:
            retained.append(row)
    retained.extend([[values.get(header, "") for header in headers] for values in new_rows])
    expected = render_csv(retained, bom, newline)
    changed = expected != raw
    if changed and not check:
        path.write_bytes(expected)
    return changed


def sync_archetypes(check: bool) -> bool:
    rows, bom, newline, raw = read_csv_document(ARCHETYPE_PATH)
    headers = rows[0]
    index = {name: i for i, name in enumerate(headers)}
    found = set()
    for row in rows[1:]:
        if not row or row[0].startswith("#"):
            continue
        archetype_id = row[index["archetype_id"]]
        spec = SPECS.get(archetype_id)
        if not spec:
            continue
        found.add(archetype_id)
        row[index["model_path"]] = spec["body"]
        row[index["default_wearable_asset_id"]] = spec["asset_id"]
    missing = set(SPECS) - found
    if missing:
        raise RuntimeError("boss archetypes missing: " + ",".join(sorted(missing)))
    expected = render_csv(rows, bom, newline)
    changed = expected != raw
    if changed and not check:
        ARCHETYPE_PATH.write_bytes(expected)
    return changed


def catalog_rows() -> list[dict[str, str]]:
    result = []
    for order, (archetype_id, spec) in enumerate(SPECS.items(), 30):
        result.append({
            "asset_id": spec["asset_id"],
            "display_name": spec["display"],
            "asset_type": "model_bundle",
            "primary_model": spec["body"],
            "default_sequence": "idle",
            "model_scale": "1",
            "load_group": "monster_default_wearables",
            "load_order": str(order),
            "priority": str(690 - (order - 30)),
            "first_use_wave": "0",
            "resident_policy": "permanent",
            "async_unit_name": "asset_proxy_" + spec["asset_id"],
            "portrait_unit_name": PORTRAIT_UNITS[archetype_id],
            "enabled": "1",
            "notes": f"{archetype_id}世界饰品；bundle/item证据={spec['bundle']}；头像沿用Valve原生且不设置portrait_item_def。",
        })
    return result


def component_rows() -> list[dict[str, str]]:
    result = []
    for archetype_id, spec in SPECS.items():
        for order, (component_id, item_def, model_path, note) in enumerate(spec["components"], 1):
            result.append({
                "component_key": f"{spec['asset_id']}:{component_id}",
                "asset_id": spec["asset_id"],
                "component_id": component_id,
                "model_path": model_path,
                "entity_class": "prop_dynamic",
                "attach_mode": "bone_merge",
                "default_sequence": "idle",
                "model_scale": "1",
                "sort_order": str(order),
                "enabled": "1",
                "notes": f"{archetype_id}官方饰品 ItemDef {item_def}" + (f"；{note}" if note else ""),
            })
    return result


def effect_rows() -> list[dict[str, str]]:
    result = []
    for archetype_id, spec in SPECS.items():
        for order, (effect_id, path, owner) in enumerate(spec.get("effects", []), 1):
            result.append({
                "effect_key": f"{spec['asset_id']}:{effect_id}",
                "asset_id": spec["asset_id"],
                "effect_group_id": "ambient",
                "effect_id": effect_id,
                "effect_role": "ambient",
                "phase": "persistent",
                "particle_path": path,
                "owner_component_id": owner,
                "attach_type": "PATTACH_ABSORIGIN_FOLLOW",
                "sort_order": str(order),
                "enabled": "1",
                "notes": f"{archetype_id}官方particle_create常驻粒子。",
            })
    return result


def proxy_block() -> str:
    lines = [MARKER_BEGIN]
    for spec in SPECS.values():
        lines += [
            f'    "asset_proxy_{spec["asset_id"]}"',
            "    {",
            '        "BaseClass" "npc_dota_creature"',
            f'        "Model" "{spec["body"]}"',
            '        "precache"',
            "        {",
        ]
        for _, _, model_path, _ in spec["components"]:
            lines.append(f'            "model" "{model_path}"')
        for _, particle_path, _ in spec.get("effects", []):
            lines.append(f'            "particle" "{particle_path}"')
        lines += ["        }", "    }"]
    lines.append(MARKER_END)
    return "\n".join(lines)


def sync_proxies(check: bool) -> bool:
    raw = NPC_UNITS.read_bytes()
    text = raw.decode("utf-8-sig")
    newline = "\r\n" if "\r\n" in text else "\n"
    normalized = text.replace("\r\n", "\n")
    block = proxy_block()
    if MARKER_BEGIN in normalized:
        start = normalized.index(MARKER_BEGIN)
        end = normalized.index(MARKER_END, start) + len(MARKER_END)
        normalized = normalized[:start] + block + normalized[end:]
    else:
        close = normalized.rfind("\n}")
        if close < 0:
            raise RuntimeError("npc_units_custom.txt final brace missing")
        normalized = normalized[:close] + "\n" + block + normalized[close:]
    expected_text = normalized.replace("\n", newline)
    if raw.startswith(b"\xef\xbb\xbf"):
        expected_text = "\ufeff" + expected_text
    expected = expected_text.encode("utf-8")
    changed = expected != raw
    if changed and not check:
        NPC_UNITS.write_bytes(expected)
    return changed


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    asset_ids = {spec["asset_id"] for spec in SPECS.values()}
    changes = [
        sync_archetypes(args.check),
        replace_data_rows(RESOURCE_ROOT / "asset_catalog.csv", "asset_id", asset_ids, catalog_rows(), args.check),
        replace_data_rows(RESOURCE_ROOT / "asset_components.csv", "asset_id", asset_ids, component_rows(), args.check),
        replace_data_rows(RESOURCE_ROOT / "asset_effects.csv", "asset_id", asset_ids, effect_rows(), args.check),
        sync_proxies(args.check),
    ]
    component_count = sum(len(spec["components"]) for spec in SPECS.values())
    effect_count = sum(len(spec.get("effects", [])) for spec in SPECS.values())
    if args.check and any(changes):
        print("BOSS_COSMETIC_BATCH_STALE")
        return 1
    print(("BOSS_COSMETIC_BATCH_CURRENT" if args.check else "BOSS_COSMETIC_BATCH_WRITTEN")
          + f" bosses={len(SPECS)} components={component_count} effects={effect_count}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
