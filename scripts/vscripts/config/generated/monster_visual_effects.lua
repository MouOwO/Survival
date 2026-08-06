-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: monster_visual_effects.csv
local M = {}
M.rows = {
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["effect_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
