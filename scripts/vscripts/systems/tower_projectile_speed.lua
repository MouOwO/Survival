local rules = require("config/tower_combat_rules")
local MODIFIER = "modifier_tower_projectile_speed"
if LinkLuaModifier then
    LinkLuaModifier(MODIFIER, "modifiers/modifier_tower_projectile_speed", LUA_MODIFIER_MOTION_NONE)
end

local M = {}

function M.apply(unit, base_speed, tower_class)
    local speed = rules.projectile_speed(base_speed, tower_class)
    if not speed then return nil end
    -- Custom arrows and their hit timers need this even on engines without
    -- SetProjectileSpeed. Native attacks must use the same effective value.
    unit.survival_projectile_speed = speed
    if type(unit.SetProjectileSpeed) == "function" then
        unit:SetProjectileSpeed(speed)
        return speed
    end
    if not unit.GetProjectileSpeed or not unit.AddNewModifier then return speed end

    local modifier = unit.FindModifierByName and unit:FindModifierByName(MODIFIER)
    local native = tonumber(unit.survival_native_tower_projectile_speed)
    if not native then
        local previous = modifier and modifier:GetStackCount() or 0
        native = unit:GetProjectileSpeed() - previous
        unit.survival_native_tower_projectile_speed = native
    end
    local bonus = speed - native
    if modifier then
        modifier:SetProjectileSpeedBonus(bonus)
    else
        unit:AddNewModifier(unit, nil, MODIFIER, { projectile_speed_bonus = bonus })
    end
    if unit.CalculateStatBonus then unit:CalculateStatBonus(true) end
    return speed
end

return M
