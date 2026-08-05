-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: global_rules.csv
local M = {}
M.rows = {
    { rule_id = "tower_attack_range", value = 1000, description = "所有防御塔统一基础攻击距离", enabled = true },
    { rule_id = "tower_acquisition_range", value = 1000, description = "所有防御塔统一基础索敌距离", enabled = true },
    { rule_id = "tower_base_projectile_speed", value = 5000, description = "基础箭塔原始弹道速度", enabled = true },
    { rule_id = "tower_route_default_projectile_speed", value = 1250, description = "无独立配置转职塔的原始弹道速度", enabled = true },
    { rule_id = "tower_projectile_speed_multiplier", value = 1, description = "所有防御塔弹道速度倍率", enabled = true },
    { rule_id = "repair_detection_range", value = 99999, description = "修理师自动感知受损建筑的范围", enabled = true },
    { rule_id = "initial_gold", value = 0, description = "队伍开局金币", enabled = true },
    { rule_id = "initial_wood", value = 10, description = "队伍开局木材", enabled = true },
    { rule_id = "initial_population", value = 0, description = "队伍开局已用人口", enabled = true },
    { rule_id = "initial_max_population", value = 0, description = "队伍开局人口上限", enabled = true },
    { rule_id = "tree_lumber_efficiency_buff_per_level", value = 1, description = "资源树从LV2起每级增加的伐木效率", enabled = true },
    { rule_id = "hero_base_lumber_efficiency", value = 13, description = "英雄每次攻击资源树的基础木材收益", enabled = true },
    { rule_id = "hero_meta_all_attributes_bonus", value = 0, description = "全体英雄局外全属性加成", enabled = true },
    { rule_id = "hero_meta_damage_multiplier", value = 1, description = "全体英雄局外伤害倍率", enabled = true },
    { rule_id = "hero_meta_max_health_multiplier", value = 1, description = "全体英雄局外最大生命倍率", enabled = true },
    { rule_id = "hero_meta_max_mana_multiplier", value = 1, description = "全体英雄局外最大魔法倍率", enabled = true },
    { rule_id = "hero_meta_move_speed_bonus", value = 0, description = "全体英雄局外移动速度加成", enabled = true },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["rule_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
