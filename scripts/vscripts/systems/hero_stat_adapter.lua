local logger = require("core/logger")

local M = {}

local function number(definition, key)
    local value = definition and definition[key]
    if value == nil or value == "" then
        return nil
    end
    return tonumber(value)
end

local function safe_call(target, method_name, ...)
    local method = target and target[method_name]
    if type(method) ~= "function" then
        return false
    end
    return pcall(method, target, ...)
end

local function safe_get(target, method_name)
    local method = target and target[method_name]
    if type(method) ~= "function" then
        return nil
    end
    local ok, result = pcall(method, target)
    return ok and result or nil
end

local function set_if_present(unit, definition, key, method_name)
    local value = number(definition, key)
    if value ~= nil then
        safe_call(unit, method_name, value)
    end
end

local function apply_primary_stats(unit, definition)
    set_if_present(unit, definition, "base_strength", "SetBaseStrength")
    set_if_present(unit, definition, "strength_gain", "SetStrengthGain")
    set_if_present(unit, definition, "base_agility", "SetBaseAgility")
    set_if_present(unit, definition, "agility_gain", "SetAgilityGain")
    set_if_present(unit, definition, "base_intellect", "SetBaseIntellect")
    set_if_present(unit, definition, "intellect_gain", "SetIntellectGain")
end

local function apply_combat_stats(unit, definition)
    set_if_present(unit, definition, "base_damage_min", "SetBaseDamageMin")
    set_if_present(unit, definition, "base_damage_max", "SetBaseDamageMax")

    local attack_speed = number(definition, "attack_speed")
    if attack_speed and attack_speed > 0 then
        safe_call(unit, "SetBaseAttackTime", 1 / attack_speed)
        unit.survival_attack_speed = attack_speed
        if not unit:HasModifier("modifier_debug_attack_cap") then
            unit:AddNewModifier(unit, nil, "modifier_debug_attack_cap", {})
        end
    end
    set_if_present(
        unit,
        definition,
        "base_armor",
        "SetPhysicalArmorBaseValue"
    )
    set_if_present(
        unit,
        definition,
        "magic_resistance",
        "SetBaseMagicalResistanceValue"
    )
    set_if_present(unit, definition, "move_speed", "SetBaseMoveSpeed")
    set_if_present(
        unit,
        definition,
        "projectile_speed",
        "SetProjectileSpeed"
    )
end

local function apply_range(unit, definition)
    local attack_range = number(definition, "attack_range")
    if attack_range and attack_range > 0 then
        safe_call(unit, "Script_SetAttackRange", attack_range)
    end

    local acquisition = number(definition, "acquisition_range")
    if not acquisition and attack_range then
        acquisition = attack_range + 200
    end
    if acquisition and acquisition > 0 then
        safe_call(unit, "SetAcquisitionRange", acquisition)
    end
end

local function apply_resource_stats(unit, definition)
    local health = number(definition, "base_health")
    if health and health > 0 then
        safe_call(unit, "SetBaseMaxHealth", health)
        safe_call(unit, "SetMaxHealth", health)
        safe_call(unit, "SetHealth", health)
    end
    set_if_present(
        unit,
        definition,
        "base_health_regen",
        "SetBaseHealthRegen"
    )

    local mana = number(definition, "base_mana")
    if mana and mana >= 0 then
        safe_call(unit, "SetMaxMana", mana)
        safe_call(unit, "SetMana", mana)
    end
    set_if_present(
        unit,
        definition,
        "base_mana_regen",
        "SetBaseManaRegen"
    )
end

local function apply_misc(unit, definition)
    set_if_present(unit, definition, "turn_rate", "SetTurnRate")
end

local function apply_all_attributes(unit, amount)
    if not amount or amount == 0 then
        return
    end
    safe_call(unit, "ModifyStrength", amount)
    safe_call(unit, "ModifyAgility", amount)
    safe_call(unit, "ModifyIntellect", amount)
end

local function apply_multipliers(unit, definition)
    local health = number(definition, "max_health_multiplier") or 1
    if health ~= 1 then
        local maximum = safe_get(unit, "GetMaxHealth")
        if maximum then
            maximum = math.max(1, math.floor(maximum * health))
            safe_call(unit, "SetBaseMaxHealth", maximum)
            safe_call(unit, "SetMaxHealth", maximum)
            safe_call(unit, "SetHealth", maximum)
        end
    end

    local mana = number(definition, "max_mana_multiplier") or 1
    if mana ~= 1 then
        local maximum = safe_get(unit, "GetMaxMana")
        if maximum then
            maximum = math.max(0, maximum * mana)
            safe_call(unit, "SetMaxMana", maximum)
            safe_call(unit, "SetMana", maximum)
        end
    end

    local move_bonus = number(definition, "move_speed_bonus") or 0
    if move_bonus ~= 0 then
        local base = safe_get(unit, "GetBaseMoveSpeed")
        if base then
            safe_call(unit, "SetBaseMoveSpeed", base + move_bonus)
        end
    end
end

local function apply_level(unit, definition)
    local level = math.max(
        1,
        number(definition, "initial_level") or 1
    )
    while unit:GetLevel() < level do
        unit:HeroLevelUp(false)
    end

    local xp = number(definition, "initial_xp") or 0
    if xp > 0 then
        local reason = rawget(_G, "DOTA_ModifyXP_Unspecified") or 0
        safe_call(unit, "AddExperience", xp, reason, false, true)
    end
end

function M.apply(unit, definition)
    if not unit or unit:IsNull() or not definition then
        return
    end

    -- 先写入 CSV 中的基础属性与成长；此前漏掉这一层，导致英雄部分回退到引擎默认值。
    apply_primary_stats(unit, definition)
    apply_combat_stats(unit, definition)
    apply_range(unit, definition)
    apply_resource_stats(unit, definition)
    apply_misc(unit, definition)
    apply_all_attributes(
        unit,
        number(definition, "all_attributes_bonus") or 0
    )
    safe_call(unit, "CalculateStatBonus", true)
    apply_multipliers(unit, definition)
    apply_level(unit, definition)

    logger.info(
        "HeroStat",
        tostring(definition.hero_id) .. " data applied"
    )
end

return M
