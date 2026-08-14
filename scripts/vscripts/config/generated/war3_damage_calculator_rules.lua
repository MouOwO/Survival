-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: war3_damage_calculator_rules.csv
local M = {}
M.rows = {
    { rule_id = "war3_positive_armor_factor", value = 0.02, display_name = "项目怪物正护甲系数", description = "明确项目怪物物理伤害的War3目标承伤曲线系数" },
    { rule_id = "war3_to_dota_ratio", value = 0.3333333333333333, display_name = "War3护甲运行时换算率", description = "War3显示护甲投影为Dota运行时护甲的线性倍率" },
    { rule_id = "dota_positive_armor_numerator", value = 0.06, display_name = "Dota护甲分子系数", description = "当前Dota运行时护甲曲线分子系数" },
    { rule_id = "dota_positive_armor_base", value = 1, display_name = "Dota护甲基础常数", description = "当前Dota运行时护甲曲线基础常数" },
    { rule_id = "dota_positive_armor_denominator", value = 0.06, display_name = "Dota护甲分母系数", description = "当前Dota运行时护甲曲线分母系数" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["rule_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
