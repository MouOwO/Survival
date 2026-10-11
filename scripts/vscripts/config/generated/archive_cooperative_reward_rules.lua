-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: archive_cooperative_reward_rules.csv
local M = {}
M.rows = {
    { rule_id = "default", version = 1, enabled = true, shared_challenge_roll = true },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["rule_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
