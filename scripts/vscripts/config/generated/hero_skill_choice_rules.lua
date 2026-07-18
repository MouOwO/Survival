-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: hero_skill_choice_rules.csv
local M = {}
M.rows = {
    { rule_id = "rebirth_random_skill", trigger_type = "rebirth_complete", min_trigger_level = 2, max_trigger_level = 10, pool_id = "public_pool", choice_count = 3, allow_owned_skill = true, owned_skill_action = "upgrade", exclude_max_level = true, unique_within_offer = true, skill_capacity = 10, enabled = true, notes = "二转到十转的随机三选一；已有技能再次选择时升级。" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["rule_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
