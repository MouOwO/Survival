local global_rules = require("config/global_rules")

local M = {}

local BASE_ARROW_TOWER_CANNOT_MISS =
    global_rules.number("base_arrow_tower_cannot_miss", 1) > 0

function M.attack_range(technology_bonus)
    return (tonumber(global_rules.tower_attack_range) or 1000)
        + (tonumber(technology_bonus) or 0)
end

-- Acquisition stays disabled: the native AI cannot distinguish resource trees
-- from hostile creeps. Combat and visuals must use the actual attack range.
function M.current_attack_range(unit)
    for _, getter in ipairs({ "Script_GetAttackRange", "GetAttackRange" }) do
        if unit and unit[getter] then
            local range = tonumber(unit[getter](unit))
            if range and range > 0 then return range end
        end
    end
    return M.attack_range()
end

function M.set_attack_range(unit, attack_range)
    attack_range = tonumber(attack_range) or M.attack_range()
    if unit.Script_SetAttackRange then
        unit:Script_SetAttackRange(attack_range)
    elseif unit.SetAttackRange then
        unit:SetAttackRange(attack_range)
    end
    if unit.SetAcquisitionRange then unit:SetAcquisitionRange(0) end
end

function M.projectile_speed(base_speed)
    base_speed = tonumber(base_speed)
    if not base_speed then return nil end
    local multiplier = math.max(
        0,
        tonumber(global_rules.tower_projectile_speed_multiplier) or 1
    )
    return base_speed * multiplier
end

function M.cannot_miss(unit)
    return BASE_ARROW_TOWER_CANNOT_MISS
        and unit ~= nil
        and unit.survival_building_id == "arrow_tower"
        and tostring(unit.survival_tower_class or "") == ""
end

return M
