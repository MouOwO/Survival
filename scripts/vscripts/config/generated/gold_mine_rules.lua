-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: gold_mine_rules.csv
local M = {}
M.rows = {
    { rule_id = "default", production_interval = 1.0, crit_multiplier = 3.0, enabled = true, notes = "暴击时获得正常采集金币的3倍" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["rule_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
