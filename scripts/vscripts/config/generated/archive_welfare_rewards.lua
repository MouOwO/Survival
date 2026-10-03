-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: archive_welfare_rewards.csv
local M = {}
M.rows = {
    { achievement_id = "welfare_victory_01", display_name = "走向胜利1", required_wins = 1, description = "木材+10", effect_ids = {"initial_wood"}, effect_values = {"10"}, enabled = true, progress_kind = "victory" },
    { achievement_id = "welfare_victory_02", display_name = "走向胜利2", required_wins = 2, description = "墙生命+5%", effect_ids = {"wall_health_bonus_pct"}, effect_values = {"5"}, enabled = true, progress_kind = "victory" },
    { achievement_id = "welfare_victory_03", display_name = "走向胜利3", required_wins = 3, description = "每秒木材+1", effect_ids = {"wood_per_second"}, effect_values = {"1"}, enabled = true, progress_kind = "victory" },
    { achievement_id = "welfare_victory_04", display_name = "走向胜利4", required_wins = 4, description = "箭塔攻击力+100", effect_ids = {"tower_attack_flat"}, effect_values = {"100"}, enabled = true, progress_kind = "victory" },
    { achievement_id = "welfare_victory_05", display_name = "走向胜利5", required_wins = 5, description = "人口+3", effect_ids = {"initial_population_cap"}, effect_values = {"3"}, enabled = true, progress_kind = "victory" },
    { achievement_id = "welfare_victory_06", display_name = "走向胜利6", required_wins = 6, description = "木材+50；人口+1", effect_ids = {"initial_wood", "initial_population_cap"}, effect_values = {"50", "1"}, enabled = true, progress_kind = "victory" },
    { achievement_id = "welfare_victory_07", display_name = "走向胜利7", required_wins = 7, description = "英雄全属性+5000", effect_ids = {"hero_initial_attributes"}, effect_values = {"5000"}, enabled = true, progress_kind = "victory" },
    { achievement_id = "welfare_victory_08", display_name = "走向胜利8", required_wins = 8, description = "箭塔攻击+200；人口+1", effect_ids = {"tower_attack_flat", "initial_population_cap"}, effect_values = {"200", "1"}, enabled = true, progress_kind = "victory" },
    { achievement_id = "welfare_victory_09", display_name = "走向胜利9", required_wins = 9, description = "金矿收益+2%", effect_ids = {"gold_mine_efficiency_pct"}, effect_values = {"2"}, enabled = true, progress_kind = "victory" },
    { achievement_id = "welfare_victory_10", display_name = "走向胜利10", required_wins = 10, description = "人口+1；伐木效率+1；防御塔攻速+5%", effect_ids = {"initial_population_cap", "lumberjack_efficiency", "tower_attack_speed_bonus_pct"}, effect_values = {"1", "1", "5"}, enabled = true, progress_kind = "victory" },
    { achievement_id = "welfare_victory_11", display_name = "走向胜利11", required_wins = 11, description = "英雄造成伤害攻击+1", effect_ids = {"hero_damage_attack_growth"}, effect_values = {"1"}, enabled = true, progress_kind = "victory" },
    { achievement_id = "welfare_victory_12", display_name = "走向胜利12", required_wins = 12, description = "伐木工攻速+5%；人口+1；木材+500", effect_ids = {"lumberjack_attack_speed_bonus_pct", "initial_population_cap", "initial_wood"}, effect_values = {"5", "1", "500"}, enabled = true, progress_kind = "victory" },
    { achievement_id = "welfare_victory_13", display_name = "走向胜利13", required_wins = 13, description = "伐木效率+1；箭塔攻速+5%；人口+1", effect_ids = {"lumberjack_efficiency", "tower_attack_speed_bonus_pct", "initial_population_cap"}, effect_values = {"1", "5", "1"}, enabled = true, progress_kind = "victory" },
    { achievement_id = "welfare_coop_01", display_name = "合作共赢1", required_wins = 5, description = "金矿效率+5%", effect_ids = {"gold_mine_efficiency_pct"}, effect_values = {"5"}, enabled = true, progress_kind = "cooperative" },
    { achievement_id = "welfare_coop_02", display_name = "合作共赢2", required_wins = 10, description = "英雄攻击攻击+3", effect_ids = {"hero_basic_attack_growth"}, effect_values = {"3"}, enabled = true, progress_kind = "cooperative" },
    { achievement_id = "welfare_coop_03", display_name = "合作共赢3", required_wins = 15, description = "每秒木材+20", effect_ids = {"wood_per_second"}, effect_values = {"20"}, enabled = true, progress_kind = "cooperative" },
    { achievement_id = "welfare_coop_04", display_name = "合作共赢4", required_wins = 20, description = "每秒金币+20", effect_ids = {"gold_per_second"}, effect_values = {"20"}, enabled = true, progress_kind = "cooperative" },
    { achievement_id = "welfare_coop_05", display_name = "合作共赢5", required_wins = 25, description = "英雄攻击减甲+2", effect_ids = {"hero_attack_armor_reduction"}, effect_values = {"2"}, enabled = true, progress_kind = "cooperative" },
    { achievement_id = "welfare_coop_06", display_name = "合作共赢6", required_wins = 30, description = "人口+3", effect_ids = {"initial_population_cap"}, effect_values = {"3"}, enabled = true, progress_kind = "cooperative" },
    { achievement_id = "welfare_coop_07", display_name = "合作共赢7", required_wins = 35, description = "墙生命加成+8%", effect_ids = {"wall_health_bonus_pct"}, effect_values = {"8"}, enabled = true, progress_kind = "cooperative" },
    { achievement_id = "welfare_coop_08", display_name = "合作共赢8", required_wins = 40, description = "英雄攻击属性+3", effect_ids = {"hero_attribute_growth"}, effect_values = {"3"}, enabled = true, progress_kind = "cooperative" },
    { achievement_id = "welfare_coop_09", display_name = "合作共赢9", required_wins = 45, description = "英雄攻击减甲+5", effect_ids = {"hero_attack_armor_reduction"}, effect_values = {"5"}, enabled = true, progress_kind = "cooperative" },
    { achievement_id = "welfare_coop_10", display_name = "合作共赢10", required_wins = 50, description = "英雄最终伤害+5%", effect_ids = {"hero_final_damage_bonus_pct"}, effect_values = {"5"}, enabled = true, progress_kind = "cooperative" },
    { achievement_id = "welfare_finish_01", display_name = "终结比赛礼包1", required_wins = 10, description = "英雄全属性加成+5%", effect_ids = {"hero_attribute_bonus_pct"}, effect_values = {"5"}, enabled = true, progress_kind = "victory" },
    { achievement_id = "welfare_finish_02", display_name = "终结比赛礼包2", required_wins = 20, description = "英雄攻击加成+8%", effect_ids = {"hero_attack_bonus_pct"}, effect_values = {"8"}, enabled = true, progress_kind = "victory" },
    { achievement_id = "welfare_finish_03", display_name = "终结比赛礼包3", required_wins = 30, description = "英雄攻击属性+5", effect_ids = {"hero_attribute_growth"}, effect_values = {"5"}, enabled = true, progress_kind = "victory" },
    { achievement_id = "welfare_finish_04", display_name = "终结比赛礼包4", required_wins = 40, description = "英雄攻击减甲+6", effect_ids = {"hero_attack_armor_reduction"}, effect_values = {"6"}, enabled = true, progress_kind = "victory" },
    { achievement_id = "welfare_finish_05", display_name = "终结比赛礼包5", required_wins = 50, description = "英雄攻击属性+6", effect_ids = {"hero_attribute_growth"}, effect_values = {"6"}, enabled = true, progress_kind = "victory" },
    { achievement_id = "welfare_finish_06", display_name = "终结比赛礼包6", required_wins = 60, description = "英雄攻击减甲+6", effect_ids = {"hero_attack_armor_reduction"}, effect_values = {"6"}, enabled = true, progress_kind = "victory" },
    { achievement_id = "welfare_finish_07", display_name = "终结比赛礼包7", required_wins = 70, description = "英雄最终伤害+6%", effect_ids = {"hero_final_damage_bonus_pct"}, effect_values = {"6"}, enabled = true, progress_kind = "victory" },
    { achievement_id = "welfare_finish_08", display_name = "终结比赛礼包8", required_wins = 80, description = "英雄全属性加成+6%", effect_ids = {"hero_attribute_bonus_pct"}, effect_values = {"6"}, enabled = true, progress_kind = "victory" },
    { achievement_id = "welfare_finish_09", display_name = "终结比赛礼包9", required_wins = 90, description = "英雄攻击加成+9%", effect_ids = {"hero_attack_bonus_pct"}, effect_values = {"9"}, enabled = true, progress_kind = "victory" },
    { achievement_id = "welfare_finish_10", display_name = "终结比赛礼包10", required_wins = 100, description = "英雄攻击攻击+9", effect_ids = {"hero_basic_attack_growth"}, effect_values = {"9"}, enabled = true, progress_kind = "victory" },
    { achievement_id = "welfare_finish_11", display_name = "终结比赛礼包11", required_wins = 110, description = "英雄攻击属性+9", effect_ids = {"hero_attribute_growth"}, effect_values = {"9"}, enabled = true, progress_kind = "victory" },
    { achievement_id = "welfare_finish_12", display_name = "终结比赛礼包12", required_wins = 120, description = "英雄最终伤害+8%", effect_ids = {"hero_final_damage_bonus_pct"}, effect_values = {"8"}, enabled = true, progress_kind = "victory" },
    { achievement_id = "welfare_finish_13", display_name = "终结比赛礼包13", required_wins = 130, description = "英雄攻击减甲+9", effect_ids = {"hero_attack_armor_reduction"}, effect_values = {"9"}, enabled = true, progress_kind = "victory" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["achievement_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
