-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: global_rules.csv
local M = {}
M.rows = {
    { rule_id = "tower_attack_range", value = 2500, description = "所有防御塔统一攻击距离", enabled = true },
    { rule_id = "tower_acquisition_range", value = 2500, description = "所有防御塔统一索敌距离", enabled = true },
    { rule_id = "repair_detection_range", value = 99999, description = "修理师自动感知受损建筑的范围", enabled = true },
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
