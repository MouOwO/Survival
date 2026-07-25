-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: altar_actions.csv
local M = {}
M.rows = {
    { action_id = "altar_endless_training", name = "无尽年轮圣殿", ability_name = "ability_enter_endless_training", ability_texture = "faceless_void_time_walk", location_id = "endless_cycle_sanctum", fallback_target_name = "challenge_04_entry", wood_cost = 0, gold_cost = 50000, gold_cost_per_second = 50000, required_rebirth_level = 6, training_room_income_multiplier = 15, target_unit_name = "building_endless_training_target", target_health = 1000000000, target_armor = 100000, target_health_regen = 100000000, prerequisite_text = "英雄6转", visible_condition = "hero_summoned==true", description = "传送至无尽年轮圣殿。每秒消耗50000金币；攻击练功建筑时攻击力与力量、敏捷、智力成长收益均为15倍。", enabled = true, source = "英雄祭坛传送" },
    { action_id = "altar_shadow_realm", name = "暗影界前庭", ability_name = "ability_enter_shadow_realm", ability_texture = "spectre_reality", location_id = "shadow_realm_forecourt", fallback_target_name = "challenge_09_entry", wood_cost = 0, gold_cost = 50000, gold_cost_per_second = 0, required_rebirth_level = 10, training_room_income_multiplier = 1, prerequisite_text = "英雄10转", visible_condition = "hero_summoned==true", description = "传送至暗影界前庭。当前版本仅开放传送，怪物与掉落逻辑暂不启用。", enabled = true, source = "英雄祭坛传送" },
    { action_id = "altar_select_hero", name = "选择英雄", wood_cost = 0, gold_cost = 0, gold_cost_per_second = 0, required_rebirth_level = 0, training_room_income_multiplier = 1, visible_condition = "altar_used==true", description = "根据设置的英雄，一个英雄一个选项框", enabled = true, source = "英雄相关建筑/行5" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["action_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
