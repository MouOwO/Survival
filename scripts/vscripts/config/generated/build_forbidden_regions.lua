-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: build_forbidden_regions.csv
local M = {}
M.rows = {
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["region_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
