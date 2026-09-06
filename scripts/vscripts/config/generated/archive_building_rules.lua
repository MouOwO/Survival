-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: archive_building_rules.csv
local M = {}
M.rows = {
    { rule_id = "default", faith_per_clear = 400, faith_daily_cap = 4000, day_timezone_offset = 28800 },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["rule_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
