-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: fishing_reward_definitions.csv
local M = {}
M.rows = {
    { reward_id = "pending_reward_body", definition_version = 1, display_name = "奖励正文待复核", weight = 0, effect_key = "pending_reward_body", effect_scope = "permanent", value_min = 0, value_max = 0, stacking_rule = "add", cap_value = 0, enabled = false, notes = "原始奖励正文未恢复；禁止进入随机池。" },
    { reward_id = "pending_lumberjack_speed_x4", definition_version = 1, display_name = "增加伐木工攻速4倍（待复核）", weight = 0, effect_key = "lumberjack_attack_speed_multiplier", effect_scope = "permanent", value_min = 0, value_max = 0, stacking_rule = "add", cap_value = 0, enabled = false, notes = "倍数是乘4还是增加400%尚未确认；禁止进入随机池。" },
    { reward_id = "pending_lumberjack_speed_5pct", definition_version = 1, display_name = "伐木工攻速5%（待复核）", weight = 0, effect_key = "lumberjack_attack_speed_pct", effect_scope = "permanent", value_min = 0, value_max = 0, stacking_rule = "add", cap_value = 0, enabled = false, notes = "增加或减少以及数值单位尚未确认；禁止进入随机池。" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["reward_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
