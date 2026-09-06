-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: archive_boss_achievements.csv
local M = {}
M.rows = {
    { achievement_id = "boss_1", display_name = "BOSS存档1", required_kills = 10, pass_required_kills = 5, description = "墙生命值+500", effect_ids = {"wall_initial_health"}, effect_values = {"500"}, enabled = true },
    { achievement_id = "boss_2", display_name = "BOSS存档2", required_kills = 30, pass_required_kills = 15, description = "墙生命值+500", effect_ids = {"wall_initial_health"}, effect_values = {"500"}, enabled = true },
    { achievement_id = "boss_3", display_name = "BOSS存档3", required_kills = 50, pass_required_kills = 25, description = "伐木效率+1", effect_ids = {"lumberjack_attack_efficiency"}, effect_values = {"1"}, enabled = true },
    { achievement_id = "boss_4", display_name = "BOSS存档4", required_kills = 70, pass_required_kills = 35, description = "箭塔攻击+3%", effect_ids = {"tower_attack_bonus_pct"}, effect_values = {"3"}, enabled = true },
    { achievement_id = "boss_5", display_name = "BOSS存档5", required_kills = 100, pass_required_kills = 50, description = "英雄造成伤害加属性+1", effect_ids = {"hero_attributes_per_damage"}, effect_values = {"1"}, enabled = true },
    { achievement_id = "boss_6", display_name = "BOSS存档6", required_kills = 150, pass_required_kills = 75, description = "初始木材+50", effect_ids = {"initial_wood"}, effect_values = {"50"}, enabled = true },
    { achievement_id = "boss_7", display_name = "BOSS存档7", required_kills = 200, pass_required_kills = 100, description = "墙生命加成+3%", effect_ids = {"wall_health_bonus_pct"}, effect_values = {"3"}, enabled = true },
    { achievement_id = "boss_8", display_name = "BOSS存档8", required_kills = 250, pass_required_kills = 125, description = "墙护甲加成+3%", effect_ids = {"wall_armor_bonus_pct"}, effect_values = {"3"}, enabled = true },
    { achievement_id = "boss_9", display_name = "BOSS存档9", required_kills = 300, pass_required_kills = 150, description = "初始金币+30", effect_ids = {"initial_gold"}, effect_values = {"30"}, enabled = true },
    { achievement_id = "boss_10", display_name = "BOSS存档10", required_kills = 400, pass_required_kills = 200, description = "伐木效率+1", effect_ids = {"lumberjack_attack_efficiency"}, effect_values = {"1"}, enabled = true },
    { achievement_id = "boss_11", display_name = "BOSS存档11", required_kills = 500, pass_required_kills = 250, description = "英雄初始属性+100", effect_ids = {"hero_initial_attributes"}, effect_values = {"100"}, enabled = true },
    { achievement_id = "boss_12", display_name = "BOSS存档12", required_kills = 600, pass_required_kills = 300, description = "墙生命+2000", effect_ids = {"wall_initial_health"}, effect_values = {"2000"}, enabled = true },
    { achievement_id = "boss_13", display_name = "BOSS存档13", required_kills = 700, pass_required_kills = 350, description = "箭塔攻击+5%", effect_ids = {"tower_attack_bonus_pct"}, effect_values = {"5"}, enabled = true },
    { achievement_id = "boss_14", display_name = "BOSS存档14", required_kills = 800, pass_required_kills = 400, description = "伐木效率+1", effect_ids = {"lumberjack_attack_efficiency"}, effect_values = {"1"}, enabled = true },
    { achievement_id = "boss_15", display_name = "BOSS存档15", required_kills = 1000, pass_required_kills = 500, description = "英雄造成伤害黄金+1", effect_ids = {"hero_damage_gold_flat"}, effect_values = {"1"}, enabled = true },
    { achievement_id = "boss_16", display_name = "BOSS存档16", required_kills = 1200, pass_required_kills = 600, description = "初始人口+1", effect_ids = {"initial_population_cap"}, effect_values = {"1"}, enabled = true },
    { achievement_id = "boss_17", display_name = "BOSS存档17", required_kills = 1400, pass_required_kills = 700, description = "初始木材+100", effect_ids = {"initial_wood"}, effect_values = {"100"}, enabled = true },
    { achievement_id = "boss_18", display_name = "BOSS存档18", required_kills = 1600, pass_required_kills = 800, description = "伐木工攻速+5%", effect_ids = {"lumberjack_attack_speed_bonus_pct"}, effect_values = {"5"}, enabled = true },
    { achievement_id = "boss_19", display_name = "BOSS存档19", required_kills = 1800, pass_required_kills = 900, description = "伐木工攻击成长+1", effect_ids = {"lumberjack_attack_growth"}, effect_values = {"1"}, enabled = true },
    { achievement_id = "boss_20", display_name = "BOSS存档20", required_kills = 2000, pass_required_kills = 1000, description = "每秒金币+1", effect_ids = {"gold_per_second"}, effect_values = {"1"}, enabled = true },
    { achievement_id = "boss_21", display_name = "BOSS存档21", required_kills = 2400, pass_required_kills = 1200, description = "初始木材+150", effect_ids = {"initial_wood"}, effect_values = {"150"}, enabled = true },
    { achievement_id = "boss_22", display_name = "BOSS存档22", required_kills = 2800, pass_required_kills = 1400, description = "英雄每秒全属性+3", effect_ids = {"hero_attributes_per_second"}, effect_values = {"3"}, enabled = true },
    { achievement_id = "boss_23", display_name = "BOSS存档23", required_kills = 3200, pass_required_kills = 1600, description = "英雄生命加成+5%", effect_ids = {"hero_health_bonus_pct"}, effect_values = {"5"}, enabled = true },
    { achievement_id = "boss_24", display_name = "BOSS存档24", required_kills = 3600, pass_required_kills = 1800, description = "英雄护甲加成+5%", effect_ids = {"hero_armor_bonus_pct"}, effect_values = {"5"}, enabled = true },
    { achievement_id = "boss_25", display_name = "BOSS存档25", required_kills = 4000, pass_required_kills = 2000, description = "英雄攻击减甲+1", effect_ids = {"hero_attack_armor_reduction"}, effect_values = {"1"}, enabled = true },
    { achievement_id = "boss_26", display_name = "BOSS存档26", required_kills = 4500, pass_required_kills = 2250, description = "英雄三围加成+3%", effect_ids = {"hero_attribute_bonus_pct"}, effect_values = {"3"}, enabled = true },
    { achievement_id = "boss_27", display_name = "BOSS存档27", required_kills = 5000, pass_required_kills = 2500, description = "英雄攻速+5%", effect_ids = {"hero_attack_speed_bonus_pct"}, effect_values = {"5"}, enabled = true },
    { achievement_id = "boss_28", display_name = "BOSS存档28", required_kills = 5500, pass_required_kills = 2750, description = "英雄伤害减免+1%", effect_ids = {"hero_damage_reduction_pct"}, effect_values = {"1"}, enabled = true },
    { achievement_id = "boss_29", display_name = "BOSS存档29", required_kills = 6000, pass_required_kills = 3000, description = "英雄最终伤害+5%", effect_ids = {"hero_final_damage_bonus_pct"}, effect_values = {"5"}, enabled = true },
    { achievement_id = "boss_30", display_name = "BOSS存档30", required_kills = 7000, pass_required_kills = 3500, description = "英雄三围加成+5%", effect_ids = {"hero_attribute_bonus_pct"}, effect_values = {"5"}, enabled = true },
    { achievement_id = "boss_31", display_name = "BOSS存档31", required_kills = 8000, pass_required_kills = 4000, description = "英雄最终伤害+5%", effect_ids = {"hero_final_damage_bonus_pct"}, effect_values = {"5"}, enabled = true },
    { achievement_id = "boss_32", display_name = "BOSS存档32", required_kills = 9000, pass_required_kills = 4500, description = "英雄每秒全属性+5", effect_ids = {"hero_attributes_per_second"}, effect_values = {"5"}, enabled = true },
    { achievement_id = "boss_33", display_name = "BOSS存档33", required_kills = 10000, pass_required_kills = 5000, description = "英雄三围加成+10%", effect_ids = {"hero_attribute_bonus_pct"}, effect_values = {"10"}, enabled = true },
    { achievement_id = "boss_34", display_name = "BOSS存档34", required_kills = 11000, pass_required_kills = 5500, description = "英雄最终伤害+10%", effect_ids = {"hero_final_damage_bonus_pct"}, effect_values = {"10"}, enabled = true },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["achievement_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
