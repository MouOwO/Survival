local global_rules = require("config/global_rules")

local M = {}

local BASE_ARROW_TOWER_CANNOT_MISS =
    global_rules.number("base_arrow_tower_cannot_miss", 1) > 0

function M.attack_range(technology_bonus)
    return (tonumber(global_rules.tower_attack_range) or 800)
        + (tonumber(technology_bonus) or 0)
end

-- Acquisition stays disabled: the native AI cannot distinguish resource trees
-- from hostile creeps. Combat and visuals must use the actual attack range.
function M.current_attack_range(unit)
    for _, getter in ipairs({ "Script_GetAttackRange", "GetAttackRange" }) do
        if unit and unit[getter] then
            local ok, value = pcall(unit[getter], unit)
            local range = ok and tonumber(value)
            if range and range > 0 then return range end
        end
    end
    return tonumber(unit and unit.survival_attack_range) or M.attack_range()
end

function M.set_attack_range(unit, attack_range)
    attack_range = math.max(0, tonumber(attack_range) or M.attack_range())
    local changed = unit.survival_attack_range ~= attack_range
    -- Script_SetAttackRange is absent on live npc_dota_creature entities.
    -- Replicate the base override to the engine/client, as for heroes, rather
    -- than only changing the Lua target search radius.
    unit.survival_attack_range = attack_range
    unit.survival_attack_range_bonus = attack_range - M.attack_range()
    local modifier_name = "modifier_survival_hero_attack_range"
    local modifier = unit.FindModifierByName and unit:FindModifierByName(modifier_name)
    if not modifier and unit.AddNewModifier then
        modifier = unit:AddNewModifier(unit, nil, modifier_name, {attack_range = attack_range})
    elseif modifier and modifier.SetAttackRange
        and (not modifier.GetStackCount or modifier:GetStackCount() ~= math.floor(attack_range)) then
        modifier:SetAttackRange(attack_range)
    end
    -- Some development hosts expose a setter as well; never depend on it.
    if changed then
        if unit.Script_SetAttackRange then pcall(unit.Script_SetAttackRange, unit, attack_range)
        elseif unit.SetAttackRange then pcall(unit.SetAttackRange, unit, attack_range) end
    end
    if unit.SetAcquisitionRange then unit:SetAcquisitionRange(0) end
end

local native_speed_routes = {
    class_1 = true, -- critical
    class_2 = true, -- laser
    class_4 = true, -- machine gun
    class_5 = true, -- multi: primary and secondary arrows share the configured speed
    class_6 = true, -- frost
    class_7 = true, -- anti-air
}

function M.projectile_speed(base_speed, tower_class)
    base_speed = tonumber(base_speed)
    if not base_speed then return nil end
    if native_speed_routes[tower_class] then return base_speed end
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
