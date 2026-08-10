local M = {}

local LUMBERJACK_MODIFIER = "modifier_lumberjack_ai"

local function valid_entity(entity)
    return entity and not entity:IsNull()
end

local function entity(entindex)
    entindex = tonumber(entindex)
    if not entindex or type(EntIndexToHScript) ~= "function" then return nil end
    local ok, result = pcall(EntIndexToHScript, entindex)
    if not ok or not valid_entity(result) then return nil end
    return result
end

local function ordered_units(keys)
    local result = {}
    for _, entindex in pairs(keys.units or {}) do
        local unit = entity(entindex)
        if unit then result[#result + 1] = unit end
    end
    return result
end

local function lumberjack_modifier(unit)
    if not valid_entity(unit) or not unit.FindModifierByName then return nil end
    local modifier = unit:FindModifierByName(LUMBERJACK_MODIFIER)
    if modifier and modifier.OnPlayerOrder then return modifier end
    return nil
end

-- Observe player orders without consuming them. The modifier owns the idle
-- timer; this service only keeps the single global order filter composed.
function M.process(keys)
    keys = keys or {}
    local order_type = tonumber(keys.order_type)
    local target = entity(keys.entindex_target)
    for _, unit in ipairs(ordered_units(keys)) do
        if unit.survival_lumberjack_internal_order ~= true then
            local modifier = lumberjack_modifier(unit)
            if modifier then modifier:OnPlayerOrder(order_type, target) end
        end
    end
    return false
end

M._ordered_units_for_test = ordered_units

return M