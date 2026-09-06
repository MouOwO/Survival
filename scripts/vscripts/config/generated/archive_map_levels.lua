-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: archive_map_levels.csv
local M = {}
M.rows = {
    { level_id = "map_01", level = 1, display_name = "地图等级1", required_seconds = 3600, description = "地图等级每提升1级提升属性；墙初始生命+100，每秒回血+5", effect_ids = {"map_level"}, effect_values = {"1"}, enabled = true },
    { level_id = "map_02", level = 2, display_name = "地图等级2", required_seconds = 7200, description = "木材+10", effect_ids = {"initial_wood", "map_level"}, effect_values = {"10", "1"}, enabled = true },
    { level_id = "map_03", level = 3, display_name = "地图等级3", required_seconds = 21600, description = "木材+10", effect_ids = {"initial_wood", "map_level"}, effect_values = {"10", "1"}, enabled = true },
    { level_id = "map_04", level = 4, display_name = "地图等级4", required_seconds = 43200, description = "木材+20", effect_ids = {"initial_wood", "map_level"}, effect_values = {"20", "1"}, enabled = true },
    { level_id = "map_05", level = 5, display_name = "地图等级5", required_seconds = 72000, description = "木材+20；人口+1", effect_ids = {"initial_wood", "initial_population_cap", "map_level"}, effect_values = {"20", "1", "1"}, enabled = true },
    { level_id = "map_06", level = 6, display_name = "地图等级6", required_seconds = 108000, description = "木材+30 金币+10", effect_ids = {"initial_wood", "initial_gold", "map_level"}, effect_values = {"30", "10", "1"}, enabled = true },
    { level_id = "map_07", level = 7, display_name = "地图等级7", required_seconds = 151200, description = "木材+30；伐木效率+1", effect_ids = {"initial_wood", "lumberjack_attack_efficiency", "map_level"}, effect_values = {"30", "1", "1"}, enabled = true },
    { level_id = "map_08", level = 8, display_name = "地图等级8", required_seconds = 201600, description = "木材+50；墙护甲加成+2%", effect_ids = {"initial_wood", "wall_armor_bonus_pct", "map_level"}, effect_values = {"50", "2", "1"}, enabled = true },
    { level_id = "map_09", level = 9, display_name = "地图等级9", required_seconds = 259200, description = "木材+100；金币+20", effect_ids = {"initial_wood", "initial_gold", "map_level"}, effect_values = {"100", "20", "1"}, enabled = true },
    { level_id = "map_10", level = 10, display_name = "地图等级10", required_seconds = 324000, description = "伐木效率+1；人口+1", effect_ids = {"lumberjack_attack_efficiency", "initial_population_cap", "map_level"}, effect_values = {"1", "1", "1"}, enabled = true },
    { level_id = "map_11", level = 11, display_name = "地图等级11", required_seconds = 396000, description = "木材+100；金币+20", effect_ids = {"initial_wood", "initial_gold", "map_level"}, effect_values = {"100", "20", "1"}, enabled = true },
    { level_id = "map_12", level = 12, display_name = "地图等级12", required_seconds = 475200, description = "木材+100；伐木效率+1", effect_ids = {"initial_wood", "lumberjack_attack_efficiency", "map_level"}, effect_values = {"100", "1", "1"}, enabled = true },
    { level_id = "map_13", level = 13, display_name = "地图等级13", required_seconds = 561600, description = "木材+100；墙生命加成+2%", effect_ids = {"initial_wood", "wall_health_bonus_pct", "map_level"}, effect_values = {"100", "2", "1"}, enabled = true },
    { level_id = "map_14", level = 14, display_name = "地图等级14", required_seconds = 655200, description = "木材+200；金币+30", effect_ids = {"initial_wood", "initial_gold", "map_level"}, effect_values = {"200", "30", "1"}, enabled = true },
    { level_id = "map_15", level = 15, display_name = "地图等级15", required_seconds = 756000, description = "木材+300；金币+40", effect_ids = {"initial_wood", "initial_gold", "map_level"}, effect_values = {"300", "40", "1"}, enabled = true },
    { level_id = "map_16", level = 16, display_name = "地图等级16", required_seconds = 864000, description = "每秒木材+3", effect_ids = {"wood_per_second", "map_level"}, effect_values = {"3", "1"}, enabled = true },
    { level_id = "map_17", level = 17, display_name = "地图等级17", required_seconds = 979200, description = "墙每秒护甲+0.05", effect_ids = {"wall_armor_per_second", "map_level"}, effect_values = {"0.05", "1"}, enabled = true },
    { level_id = "map_18", level = 18, display_name = "地图等级18", required_seconds = 1101600, description = "墙生命加成+5%", effect_ids = {"wall_health_bonus_pct", "map_level"}, effect_values = {"5", "1"}, enabled = true },
    { level_id = "map_19", level = 19, display_name = "地图等级19", required_seconds = 1231200, description = "墙护甲加成+5%", effect_ids = {"wall_armor_bonus_pct", "map_level"}, effect_values = {"5", "1"}, enabled = true },
    { level_id = "map_20", level = 20, display_name = "地图等级20", required_seconds = 1368000, description = "人口+1  伐木效率+1", effect_ids = {"initial_population_cap", "lumberjack_attack_efficiency", "map_level"}, effect_values = {"1", "1", "1"}, enabled = true },
    { level_id = "map_21", level = 21, display_name = "地图等级21", required_seconds = 1512000, description = "木材+1000 金币+50", effect_ids = {"initial_wood", "initial_gold", "map_level"}, effect_values = {"1000", "50", "1"}, enabled = true },
    { level_id = "map_22", level = 22, display_name = "地图等级22", required_seconds = 1663200, description = "人口+1 伐木效率+1", effect_ids = {"initial_population_cap", "lumberjack_attack_efficiency", "map_level"}, effect_values = {"1", "1", "1"}, enabled = true },
    { level_id = "map_23", level = 23, display_name = "地图等级23", required_seconds = 1821600, description = "人口+1  伐木效率+1", effect_ids = {"initial_population_cap", "lumberjack_attack_efficiency", "map_level"}, effect_values = {"1", "1", "1"}, enabled = true },
    { level_id = "map_24", level = 24, display_name = "地图等级24", required_seconds = 1987200, description = "英雄最终伤害+5%", effect_ids = {"hero_final_damage_bonus_pct", "map_level"}, effect_values = {"5", "1"}, enabled = true },
    { level_id = "map_25", level = 25, display_name = "地图等级25", required_seconds = 2160000, description = "英雄全属性加成+5%", effect_ids = {"hero_attribute_bonus_pct", "map_level"}, effect_values = {"5", "1"}, enabled = true },
    { level_id = "map_26", level = 26, display_name = "地图等级26", required_seconds = 2340000, description = "英雄攻击减甲+5", effect_ids = {"hero_attack_armor_reduction", "map_level"}, effect_values = {"5", "1"}, enabled = true },
    { level_id = "map_27", level = 27, display_name = "地图等级27", required_seconds = 2527200, description = "英雄攻击全属性+5", effect_ids = {"hero_attribute_growth", "map_level"}, effect_values = {"5", "1"}, enabled = true },
    { level_id = "map_28", level = 28, display_name = "地图等级28", required_seconds = 2721600, description = "英雄造成伤害加攻击+10", effect_ids = {"hero_damage_attack_growth", "map_level"}, effect_values = {"10", "1"}, enabled = true },
    { level_id = "map_29", level = 29, display_name = "地图等级29", required_seconds = 2923200, description = "英雄攻击全属性+10", effect_ids = {"hero_attribute_growth", "map_level"}, effect_values = {"10", "1"}, enabled = true },
    { level_id = "map_30", level = 30, display_name = "地图等级30", required_seconds = 3132000, description = "英雄最终伤害+10%", effect_ids = {"hero_final_damage_bonus_pct", "map_level"}, effect_values = {"10", "1"}, enabled = true },
    { level_id = "map_31", level = 31, display_name = "地图等级31", required_seconds = 3348000, description = "英雄全属性加成+10%", effect_ids = {"hero_attribute_bonus_pct", "map_level"}, effect_values = {"10", "1"}, enabled = true },
    { level_id = "map_32", level = 32, display_name = "地图等级32", required_seconds = 3571200, description = "英雄攻击减甲+15", effect_ids = {"hero_attack_armor_reduction", "map_level"}, effect_values = {"15", "1"}, enabled = true },
    { level_id = "map_33", level = 33, display_name = "地图等级33", required_seconds = 3801600, description = "英雄攻击全属性+15", effect_ids = {"hero_attribute_growth", "map_level"}, effect_values = {"15", "1"}, enabled = true },
    { level_id = "map_34", level = 34, display_name = "地图等级34", required_seconds = 4003200, description = "英雄最终伤害+15%", effect_ids = {"hero_final_damage_bonus_pct", "map_level"}, effect_values = {"15", "1"}, enabled = true },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["level_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
