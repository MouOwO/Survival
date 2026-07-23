local levels = require("config/generated/building_levels")
local rules = require("config/generated/gold_mine_rules")
local technologies = require("config/generated/technology_definitions")
local rule = (rules.by_id or {}).default or {}

local level_by_number = {}
local max_mine_level = 0
for _, row in ipairs(levels.rows or {}) do
    if row.enabled ~= false and row.building_id == "building_gold_mine" then
        level_by_number[row.level] = row
        max_mine_level = math.max(max_mine_level, row.level)
    end
end
assert(max_mine_level > 0, "building_levels.csv must define enabled gold mine levels")
for level = 1, max_mine_level do
    assert(
        level_by_number[level] ~= nil,
        "building_levels.csv is missing enabled gold mine level " .. tostring(level)
    )
end

local technology_effects = {}
local technology_rows = {}
local technology_max_levels = {}
for _, row in ipairs(technologies.rows or {}) do
    if row.enabled ~= false then
        local group = row.technology_group
        technology_effects[group] = technology_effects[group] or {}
        technology_effects[group][row.level] = tonumber(row.effect_value) or 0
        technology_rows[group] = technology_rows[group] or {}
        technology_rows[group][row.level] = row
        technology_max_levels[group] = math.max(
            technology_max_levels[group] or 0,
            tonumber(row.level) or 0
        )
    end
end

local M = {
    max_mine_level = max_mine_level,
    production_interval = tonumber(rule.production_interval) or 1.0,

    max_efficiency_level = technology_max_levels.gold_mine_efficiency or 0,
    max_crit_level = technology_max_levels.gold_mine_crit or 0,
}

function M.mine_upgrade_cost(current_level)
    local target = level_by_number[(tonumber(current_level) or 0) + 1]
    if not target or target.wood_cost == nil then return nil end
    return {
        wood = tonumber(target.wood_cost) or 0,
        gold = tonumber(target.gold_cost) or 0,
    }
end

function M.technology_upgrade_cost(group, current_level)
    local row = (technology_rows[group] or {})[(tonumber(current_level) or 0) + 1]
    if not row then return nil end
    return {
        wood = tonumber(row.wood_cost) or 0,
        gold = tonumber(row.gold_cost) or 0,
    }
end

function M.efficiency_upgrade_cost(current_level)
    return M.technology_upgrade_cost("gold_mine_efficiency", current_level)
end

function M.crit_upgrade_cost(current_level)
    return M.technology_upgrade_cost("gold_mine_crit", current_level)
end

function M.efficiency_percent(efficiency_level)
    local level = math.max(0, tonumber(efficiency_level) or 0)
    return (technology_effects.gold_mine_efficiency or {})[level] or 0
end

function M.income_amount(mine_level, efficiency_level, critical)
    local level = math.max(1, math.min(M.max_mine_level, mine_level or 1))
    local row = level_by_number[level]
    local base_income = tonumber(row and row.base_income) or 0
    local amount = base_income * (1 + M.efficiency_percent(efficiency_level) / 100)
    if critical then
        amount = amount * M.crit_multiplier(level)
    end
    return math.floor(amount)
end

function M.normal_income(mine_level, efficiency_level)
    return M.income_amount(mine_level, efficiency_level, false)
end

function M.crit_multiplier(mine_level)
    return tonumber(rule.crit_multiplier) or 1.30
end

function M.crit_chance(crit_level)
    local level = math.max(0, tonumber(crit_level) or 0)
    return (technology_effects.gold_mine_crit or {})[level] or 0
end

function M.level_data(level)
    return level_by_number[level]
end

return M
