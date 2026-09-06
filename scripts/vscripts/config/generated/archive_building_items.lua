-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: archive_building_items.csv
local M = {}
M.rows = {
    { item_id = "building_01", display_name = "玲珑心", max_level = 5, cost = 3000, description = "科技木材费用减免5% × 等级", effect_ids = {"technology_wood_cost_refund_pct"}, effect_values = {"5"}, enabled = true },
    { item_id = "building_02", display_name = "圣剑", max_level = 5, cost = 3000, description = "英雄攻击减甲+3 × 等级", effect_ids = {"hero_attack_armor_reduction"}, effect_values = {"3"}, enabled = true },
    { item_id = "building_03", display_name = "赤红甲", max_level = 5, cost = 3000, description = "墙减伤+1% × 等级", effect_ids = {"wall_damage_reduction_pct"}, effect_values = {"1"}, enabled = true },
    { item_id = "building_04", display_name = "大剑", max_level = 5, cost = 3000, description = "英雄与箭塔每次造成伤害攻击+10 × 等级", effect_ids = {"hero_damage_attack_growth", "tower_damage_attack_growth"}, effect_values = {"10", "10"}, enabled = true },
    { item_id = "building_05", display_name = "深渊之刃", max_level = 5, cost = 3000, description = "每波BOSS攻击城墙时被击晕2秒 × 等级", effect_ids = {"wall_wave_boss_stun_seconds"}, effect_values = {"2"}, enabled = true },
    { item_id = "building_06", display_name = "板甲", max_level = 5, cost = 3000, description = "墙护甲+1% × 等级", effect_ids = {"wall_armor_bonus_pct"}, effect_values = {"1"}, enabled = true },
    { item_id = "building_07", display_name = "秘法鞋", max_level = 5, cost = 3000, description = "科技金币费用减免5% × 等级", effect_ids = {"technology_gold_cost_refund_pct"}, effect_values = {"5"}, enabled = true },
    { item_id = "building_08", display_name = "狂战斧", max_level = 5, cost = 3000, description = "每60秒英雄与箭塔攻击加成+1% × 等级", effect_ids = {"hero_attack_pct_per_minute", "tower_attack_pct_per_minute"}, effect_values = {"1", "1"}, enabled = true },
    { item_id = "building_09", display_name = "雷神之锤", max_level = 5, cost = 3000, description = "每60秒英雄三围加成+2% × 等级", effect_ids = {"hero_attributes_pct_per_minute"}, effect_values = {"2"}, enabled = true },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["item_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
