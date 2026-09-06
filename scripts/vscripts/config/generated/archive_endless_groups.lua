-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: archive_endless_groups.csv
local M = {}
M.rows = {
    { group_id = "tier1", min_difficulty = 1, max_difficulty = 10, wave_group = "tier1", enabled = true, notes = "工作簿N1-N10完整1000波" },
    { group_id = "tier2", min_difficulty = 11, max_difficulty = 20, wave_group = "tier1", enabled = true, notes = "用户确认所有难度统一使用无尽波次属性" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["group_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
