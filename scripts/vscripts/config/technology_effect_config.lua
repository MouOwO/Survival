local definitions = require("config/generated/technology_definitions")

local M = {}
local rows_by_group = {}

for _, row in ipairs(definitions.rows or {}) do
    if row.enabled ~= false then
        local group = tostring(row.technology_group or "")
        local level = tonumber(row.level) or 0
        if group ~= "" and level > 0 then
            rows_by_group[group] = rows_by_group[group] or {}
            rows_by_group[group][level] = row
        end
    end
end

local function matching_row(group, level, effect_type)
    local row = (rows_by_group[group] or {})[tonumber(level) or 0]
    if not row then return nil end
    if effect_type and row.effect_type ~= effect_type then return nil end
    return row
end

-- Most technology rows store the total effect at the purchased level.
function M.value(group, level, effect_type)
    local row = matching_row(group, level, effect_type)
    return tonumber(row and row.effect_value) or 0
end

-- Incremental technologies store one contribution per row. Sum every
-- purchased row instead of assuming that the contribution never changes.
function M.accumulated_value(group, level, effect_type)
    local total = 0
    for current = 1, math.max(0, tonumber(level) or 0) do
        local row = matching_row(group, current, effect_type)
        total = total + (tonumber(row and row.effect_value) or 0)
    end
    return total
end

return M