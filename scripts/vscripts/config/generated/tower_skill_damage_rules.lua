-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: tower_skill_damage_rules.csv
local M = {}
M.rows = {
    { skill_id = "multi_attack_lv01", ground_damage_multiplier = 1.8, enabled = true, notes = "基础伤害倍率读取tower_skill_definitions.csv；地面目标在基础倍率上再乘1.8。" },
    { skill_id = "multi_attack_lv02", ground_damage_multiplier = 1.8, enabled = true, notes = "基础伤害倍率读取tower_skill_definitions.csv；地面目标在基础倍率上再乘1.8。" },
    { skill_id = "multi_attack_lv03", ground_damage_multiplier = 1.8, enabled = true, notes = "基础伤害倍率读取tower_skill_definitions.csv；地面目标在基础倍率上再乘1.8。" },
    { skill_id = "multi_attack_lv04", ground_damage_multiplier = 1.8, enabled = true, notes = "基础伤害倍率读取tower_skill_definitions.csv；地面目标在基础倍率上再乘1.8。" },
    { skill_id = "multi_attack_lv05", ground_damage_multiplier = 1.8, enabled = true, notes = "基础伤害倍率读取tower_skill_definitions.csv；地面目标在基础倍率上再乘1.8。" },
    { skill_id = "burning_great_arrow_lv01", ground_damage_multiplier = 1, penetration_decay = 0.8, enabled = true, notes = "第n个有效新目标从n=0开始，伤害倍率为技能基础倍率×0.8^n；地面与飞行目标一致。" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["skill_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
