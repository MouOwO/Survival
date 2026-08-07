-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: hero_initial_skills.csv
local M = {}
M.rows = {
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["initial_entry_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
