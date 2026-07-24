-- Compatibility API for older consumers. Technology rows and their costs and
-- effects are read exclusively from technology_definitions.csv.
local definitions = require("config/generated/technology_definitions")
local M = {
    EFFICIENCY_GROUP = "gold_mine_efficiency",
    CRIT_GROUP = "gold_mine_crit",
    rows = {},
    by_id = {},
}
local rows_by_group = {}

for _, row in ipairs(definitions.rows or {}) do
    local group = row.technology_group
    if group == M.EFFICIENCY_GROUP or group == M.CRIT_GROUP then
        M.rows[#M.rows + 1] = row
        M.by_id[row.technology_id] = row
        rows_by_group[group] = rows_by_group[group] or {}
        rows_by_group[group][tonumber(row.level) or 0] = row
    end
end

M.MAX_EFFICIENCY_LEVEL = #(rows_by_group[M.EFFICIENCY_GROUP] or {})
M.MAX_CRIT_LEVEL = #(rows_by_group[M.CRIT_GROUP] or {})

local function row_at(group, level)
    return (rows_by_group[group] or {})[tonumber(level) or 0]
end

local function effect(group, level, maximum)
    level = math.max(0, math.min(maximum, tonumber(level) or 0))
    local row = row_at(group, level)
    return tonumber(row and row.effect_value) or 0
end

local function cost(group, target_level)
    local row = row_at(group, target_level)
    if not row then return nil end
    return {
        wood = tonumber(row.wood_cost) or 0,
        gold = tonumber(row.gold_cost) or 0,
    }
end

function M.efficiency_percent(level)
    return effect(M.EFFICIENCY_GROUP, level, M.MAX_EFFICIENCY_LEVEL)
end

function M.efficiency_bonus(base_income, level)
    if (tonumber(level) or 0) <= 0 then return 0 end
    local bonus = math.floor(
        (tonumber(base_income) or 0) * M.efficiency_percent(level) / 100
    )
    return math.max(1, bonus)
end


function M.efficiency_cost(target_level)
    return cost(M.EFFICIENCY_GROUP, target_level)
end

function M.crit_percent(level)
    return effect(M.CRIT_GROUP, level, M.MAX_CRIT_LEVEL)
end

function M.crit_cost(target_level)
    return cost(M.CRIT_GROUP, target_level)
end

return M