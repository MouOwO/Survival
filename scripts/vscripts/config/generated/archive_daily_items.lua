-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: archive_daily_items.csv
local M = {}
M.rows = {
    { item_id = "daily_growth_gem", display_name = "成长宝石", description = "英雄每秒攻击+1", effect_ids = {"hero_attack_per_second"}, effect_values = {"1"}, max_owned = 999999, quality = "R", enabled = true },
    { item_id = "daily_regen_shard", display_name = "回血碎片", description = "墙每秒回血+2", effect_ids = {"wall_health_regen_per_second"}, effect_values = {"2"}, max_owned = 999999, quality = "R", enabled = true },
    { item_id = "daily_attribute_gem", display_name = "攻击宝石", description = "英雄每秒三围+1", effect_ids = {"hero_attributes_per_second"}, effect_values = {"1"}, max_owned = 999999, quality = "R", enabled = true },
    { item_id = "daily_attack_shard", display_name = "攻击碎片", description = "塔攻击+5", effect_ids = {"tower_attack_flat"}, effect_values = {"5"}, max_owned = 999999, quality = "R", enabled = true },
    { item_id = "daily_health_gem", display_name = "生命宝石", description = "墙生命+50", effect_ids = {"wall_initial_health"}, effect_values = {"50"}, max_owned = 999999, quality = "R", enabled = true },
    { item_id = "daily_wood_gem", display_name = "木材宝石", description = "开局木材+3", effect_ids = {"initial_wood"}, effect_values = {"3"}, max_owned = 999999, quality = "R", enabled = true },
    { item_id = "daily_block_shard", display_name = "格挡碎片", description = "墙格挡+3", effect_ids = {"wall_damage_block"}, effect_values = {"3"}, max_owned = 999999, quality = "R", enabled = true },
    { item_id = "daily_attribute_shard", display_name = "属性碎片", description = "英雄全属性+10", effect_ids = {"hero_initial_attributes"}, effect_values = {"10"}, max_owned = 999999, quality = "R", enabled = true },
    { item_id = "daily_gold_gem", display_name = "金币宝石", description = "开局金币+1", effect_ids = {"initial_gold"}, effect_values = {"1"}, max_owned = 999999, quality = "R", enabled = true },
    { item_id = "daily_wealth_talisman", display_name = "聚财古符", description = "开局木材+50；开局金币+50；伐木工攻速+3%；伐木效率+1；金矿收益+5%；人口+1", effect_ids = {"initial_wood", "initial_gold", "lumberjack_attack_speed_bonus_pct", "lumberjack_attack_efficiency", "gold_mine_efficiency_pct", "initial_population_cap"}, effect_values = {"50", "50", "3", "1", "5", "1"}, max_owned = 1, quality = "SSR", enabled = true },
    { item_id = "daily_ancient_tree", display_name = "古树眷顾", description = "开局木材+300；开局金币+300；伐木效率+3；金矿收益+5%；英雄全属性加成+9%；星悦积分+128", effect_ids = {"initial_wood", "initial_gold", "lumberjack_attack_efficiency", "gold_mine_efficiency_pct", "hero_attribute_bonus_pct", "starjoy_points"}, effect_values = {"300", "300", "3", "5", "9", "128"}, max_owned = 1, quality = "SSR", enabled = true },
    { item_id = "daily_forest_origin", display_name = "森罗本源", description = "开局木材+200；开局金币+200；伐木效率+1；金矿收益+5%；人口+1；英雄全属性加成+8%；星悦积分+88", effect_ids = {"initial_wood", "initial_gold", "lumberjack_attack_efficiency", "gold_mine_efficiency_pct", "initial_population_cap", "hero_attribute_bonus_pct", "starjoy_points"}, effect_values = {"200", "200", "1", "5", "1", "8", "88"}, max_owned = 1, quality = "SSR", enabled = true },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["item_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
