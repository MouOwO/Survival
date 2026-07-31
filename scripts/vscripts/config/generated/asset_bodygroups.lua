-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: asset_bodygroups.csv
local M = {}
M.rows = {
    { bodygroup_key = "tower_death_nevermore_sundered_souls:rocks", asset_id = "tower_death_nevermore_sundered_souls", bodygroup_name = "rocks", value = 1, sort_order = 1, enabled = true, notes = "Lord of the Sundered Souls肩部物品33210要求Shadow Fiend主体启用rocks bodygroup，避免原生部位与套装重叠。" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["bodygroup_key"]
    if key ~= nil then M.by_id[key] = row end
end
return M
