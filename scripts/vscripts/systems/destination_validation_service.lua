local regions = require("systems/forbidden_region_service")

local M = {}

local function constrained_hero(unit)
    return unit and not unit:IsNull() and unit.survival_hero_id ~= nil
end

local function navigation_valid(position)
    if not position then return false, "invalid_destination" end
    if not GridNav then return false, "navigation_unavailable" end
    local traversable_ok, traversable = pcall(function()
        return GridNav:IsTraversable(position)
    end)
    if not traversable_ok or traversable ~= true then
        return false, "destination_not_traversable"
    end
    local blocked_ok, blocked = pcall(function()
        return GridNav:IsBlocked(position)
    end)
    if not blocked_ok or blocked ~= false then
        return false, "destination_blocked"
    end
    return true, nil
end

function M.validate(position, unit)
    local valid, reason = navigation_valid(position)
    if not valid then return false, reason end
    if constrained_hero(unit) then
        return regions.validate_hero_position(position)
    end
    return true, nil
end

function M.validate_hero_position(position)
    local valid, reason = navigation_valid(position)
    if not valid then return false, reason end
    return regions.validate_hero_position(position)
end

function M.teleport(unit, position, clear_space)
    if not unit or unit:IsNull() then return false, "unit_invalid" end
    local valid, reason = M.validate(position, unit)
    local origin = unit:GetAbsOrigin()
    if not valid then return false, reason end
    unit:SetAbsOrigin(position)
    if clear_space ~= false then FindClearSpaceForUnit(unit, position, true) end
    local final_position = unit:GetAbsOrigin()
    valid, reason = M.validate(final_position, unit)
    if valid then return true, nil, final_position end
    unit:SetAbsOrigin(origin)
    return false, "final_" .. tostring(reason)
end

M.is_constrained_hero = constrained_hero
M._navigation_valid_for_test = navigation_valid

return M