local tree_damage_rules = require("systems/tree_damage_rules")
local repair_order_service = require("systems/repair_order_service")

local M = {}
local registered = false

local function entity(entindex)
    entindex = tonumber(entindex)
    if not entindex or not EntIndexToHScript then return nil end
    return EntIndexToHScript(entindex)
end

local function ordered_units(keys)
    local result = {}
    for _, entindex in pairs(keys.units or {}) do
        local unit = entity(entindex)
        if unit then result[#result + 1] = unit end
    end
    return result
end

local function filter(_, keys)
    if repair_order_service.process(keys) then return false end
    if tonumber(keys.order_type) ~= tonumber(DOTA_UNIT_ORDER_ATTACK_TARGET) then
        return true
    end
    local target = entity(keys.entindex_target)
    if not tree_damage_rules.is_tree(target) then return true end
    for _, unit in ipairs(ordered_units(keys)) do
        if tree_damage_rules.is_arrow_tower(unit) then return false end
    end
    return true
end

function M.register()
    if registered then return true end
    local mode = GameRules:GetGameModeEntity()
    if not mode or not mode.SetExecuteOrderFilter then return false end
    mode:SetExecuteOrderFilter(filter, M)
    registered = true
    return true
end

function M.reset_for_test()
    registered = false
end

M._filter_for_test = filter
M._ordered_units_for_test = ordered_units

return M