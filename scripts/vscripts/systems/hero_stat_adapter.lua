local logger = require("core/logger")
local projectile_config = require(
    "config/generated/hero_attack_projectiles"
)
local global_rules = require("config/global_rules")
local armor_balance = require("config/armor_balance")
local hero_health_guard = require("core/hero_health_guard")

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
    -- Survival attributes are logical combat values. Keeping native attributes
    -- at zero prevents agility/strength/intellect from changing attack speed,
    -- armor, health, mana, or primary-attribute damage behind the data model.
    safe_call(unit, "SetBaseStrength", 0)
    safe_call(unit, "SetStrengthGain", 0)
    safe_call(unit, "SetBaseAgility", 0)
    safe_call(unit, "SetAgilityGain", 0)
    safe_call(unit, "SetBaseIntellect", 0)
    safe_call(unit, "SetIntellectGain", 0)
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
    local base_war3_armor = number(definition, "base_war3_armor")
        or number(definition, "base_armor")
    if base_war3_armor ~= nil then
        safe_call(unit, "SetPhysicalArmorBaseValue",
            armor_balance.from_war3(base_war3_armor))
    end
    set_if_present(
        unit,
        definition,
        "magic_resistance",
        "SetBaseMagicalResistanceValue"
    )
    set_if_present(unit, definition, "move_speed", "SetBaseMoveSpeed")
    local projectile = (projectile_config.by_id or {})[definition.hero_id]
    if projectile and projectile.enabled == false then projectile = nil end
    projectile = projectile or definition
    local projectile_speed = number(projectile, "projectile_speed")
    local projectile_model = projectile.projectile_model
    if projectile_speed and projectile_speed > 0 then
        safe_call(unit, "SetProjectileSpeed", projectile_speed)
        if projectile_model and projectile_model ~= "" then
            safe_call(unit, "SetRangedProjectileName", projectile_model)
        end
        safe_call(unit, "SetAttackCapability", DOTA_UNIT_CAP_RANGED_ATTACK)
    else
        safe_call(unit, "SetRangedProjectileName", "")
        safe_call(unit, "SetAttackCapability", DOTA_UNIT_CAP_MELEE_ATTACK)
    end
end

local function apply_range(unit, definition)
    local attack_range = number(definition, "attack_range")
    if attack_range and attack_range > 0 then
        safe_call(unit, "Script_SetAttackRange", attack_range)
        unit.survival_attack_range = attack_range
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

local function apply_multipliers(unit, definition)
    local mana = (number(definition, "max_mana_multiplier") or 1)
        * global_rules.number("hero_meta_max_mana_multiplier", 1)
    if mana ~= 1 then
        local maximum = safe_get(unit, "GetMaxMana")
        if maximum then
            maximum = math.max(0, maximum * mana)
            safe_call(unit, "SetMaxMana", maximum)
            safe_call(unit, "SetMana", maximum)
        end
    end

    local move_bonus = (number(definition, "move_speed_bonus") or 0)
        + global_rules.number("hero_meta_move_speed_bonus", 0)
    if move_bonus ~= 0 then
        local base = safe_get(unit, "GetBaseMoveSpeed")
        if base then
            safe_call(unit, "SetBaseMoveSpeed", base + move_bonus)
        end
    end
end

function M.configured_max_health(definition)
    local base = number(definition, "base_health")
    if not base or base <= 0 then return nil end
    local multiplier = number(definition, "max_health_multiplier") or 1
    local global_multiplier = global_rules.number(
        "hero_meta_max_health_multiplier", 1
    )
    return math.max(1, math.floor(base * multiplier * global_multiplier))
end

function M.apply_configured_health(unit, definition)
    local target = M.configured_max_health(definition)
    if not target or not unit or unit:IsNull() then return nil end
    local modifier_name = "modifier_survival_hero_base_health"
    local modifier = unit.FindModifierByName
        and unit:FindModifierByName(modifier_name) or nil
    local old_bonus = modifier and modifier.GetStackCount
        and math.max(0, tonumber(modifier:GetStackCount()) or 0) or 0
    local current_maximum = safe_get(unit, "GetMaxHealth") or 0
    local native_maximum = math.max(1, current_maximum - old_bonus)
    local health_bonus = math.max(0, math.floor(target - native_maximum))

    hero_health_guard.preserve_missing(unit, function()
        if not modifier then
            modifier = unit:AddNewModifier(unit, nil, modifier_name, {
                health_bonus = health_bonus,
            })
        elseif modifier.SetHealthBonus then
            modifier:SetHealthBonus(health_bonus)
        else
            modifier:SetStackCount(health_bonus)
        end
        safe_call(unit, "CalculateStatBonus", true)
    end, "configured_base_health")

    unit.survival_base_max_health = target
    unit.survival_native_max_health = native_maximum
    unit.survival_base_health_bonus = health_bonus
    return target, health_bonus, native_maximum
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

    -- Keep native attributes neutral before applying data-driven combat stats.
    apply_primary_stats(unit, definition)
    apply_combat_stats(unit, definition)
    apply_range(unit, definition)
    apply_resource_stats(unit, definition)
    apply_misc(unit, definition)
    safe_call(unit, "CalculateStatBonus", true)
    apply_multipliers(unit, definition)
    apply_level(unit, definition)
    local configured_health = M.apply_configured_health(unit, definition)

    logger.info(
        "HeroStat",
        tostring(definition.hero_id) .. " data applied max_health="
            .. tostring(configured_health)
    )
end

return M
