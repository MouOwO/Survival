-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: fishing_reward_definitions.csv
local M = {}
M.rows = {
    { reward_id = "test_hero_attack_flat", definition_version = 9001, display_name = "测试攻击奖励", weight = 1, effect_key = "hero_attack_flat", effect_scope = "permanent", value_min = 5, value_max = 5, stacking_rule = "add", cap_value = 0, enabled = true, notes = "仅用于自动化测试。" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["reward_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
