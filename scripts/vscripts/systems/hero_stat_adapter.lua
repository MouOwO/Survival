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
        unit.survival_base_war3_armor = base_war3_armor
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
    local attack_capability = projectile.attack_capability
    if attack_capability == "melee" then
        safe_call(unit, "SetRangedProjectileName", "")
        safe_call(unit, "SetAttackCapability", DOTA_UNIT_CAP_MELEE_ATTACK)
    elseif projectile_speed and projectile_speed > 0 then
        safe_call(unit, "SetProjectileSpeed", projectile_speed)
        if projectile_model and projectile_model ~= "" then
            safe_call(unit, "SetRangedProjectileName", projectile_model)
        end
        safe_call(unit, "SetAttackCapability", DOTA_UNIT_CAP_RANGED_ATTACK)
    else
        safe_call(unit, "SetProjectileSpeed", 3000)
        safe_call(unit, "SetRangedProjectileName", "")
        safe_call(unit, "SetAttackCapability", DOTA_UNIT_CAP_RANGED_ATTACK)
    end
    unit.survival_attack_capability = attack_capability or "ranged"
end

local function apply_range(unit, definition)
    local attack_range = number(definition, "attack_range")
    if attack_range and attack_range > 0 then
        safe_call(unit, "Script_SetAttackRange", attack_range)
        unit.survival_attack_range = attack_range
        local modifier_name = "modifier_survival_hero_attack_range"
        local modifier = unit.FindModifierByName
            and unit:FindModifierByName(modifier_name) or nil
        if not modifier then
            modifier = unit:AddNewModifier(unit, nil, modifier_name, {
                attack_range = attack_range,
            })
        elseif modifier.SetAttackRange then
            modifier:SetAttackRange(attack_range)
        end
        safe_call(unit, "CalculateStatBonus", true)
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

    -- The configured mana standard is projected by a permanent modifier after
    -- every native stat calculation. Keep native regeneration neutral so the
    -- modifier can provide an exact, attribute-independent value.
    if number(definition, "base_mana") ~= nil then
        safe_call(unit, "SetBaseManaRegen", 0)
    end
end

local function apply_misc(unit, definition)
    set_if_present(unit, definition, "turn_rate", "SetTurnRate")
end

local function apply_multipliers(unit, definition)
    local move_bonus = (number(definition, "move_speed_bonus") or 0)
        + global_rules.number("hero_meta_move_speed_bonus", 0)
    if move_bonus ~= 0 then
        local base = safe_get(unit, "GetBaseMoveSpeed")
        if base then
            safe_call(unit, "SetBaseMoveSpeed", base + move_bonus)
        end
    end
end

function M.configured_max_mana(definition)
    local base = number(definition, "base_mana")
    if not base or base < 0 then return nil end
    local multiplier = number(definition, "max_mana_multiplier") or 1
    return math.max(0, math.floor(base * multiplier))
end

function M.apply_configured_mana(unit, definition, fill_to_maximum)
    local target = M.configured_max_mana(definition)
    if target == nil or not unit or unit:IsNull() then return nil end

    local modifier_name = "modifier_survival_hero_mana_standard"
    local modifier = unit.FindModifierByName
        and unit:FindModifierByName(modifier_name) or nil
    local first_application = modifier == nil
    local old_adjustment = modifier and modifier.GetManaAdjustment
        and (tonumber(modifier:GetManaAdjustment()) or 0) or 0
    local current_maximum = safe_get(unit, "GetMaxMana") or 0
    local native_maximum = current_maximum - old_adjustment
    local adjustment = target - native_maximum
    local regeneration = math.max(
        0,
        number(definition, "base_mana_regen") or 0
    )
    local current_mana = math.max(0, safe_get(unit, "GetMana") or 0)

    if not modifier then
        modifier = unit:AddNewModifier(unit, nil, modifier_name, {
            mana_adjustment = adjustment,
            mana_regen = regeneration,
        })
    elseif modifier.SetManaStandard then
        modifier:SetManaStandard(adjustment, regeneration)
    end
    safe_call(unit, "CalculateStatBonus", true)
    safe_call(unit, "SetMana", fill_to_maximum == true and first_application
        and target or math.min(current_mana, target))

    unit.survival_base_max_mana = target
    unit.survival_native_max_mana = native_maximum
    unit.survival_mana_adjustment = adjustment
    unit.survival_base_mana_regen = regeneration
    return target, adjustment, native_maximum, regeneration
end

function M.configured_max_health(definition, attribute_health_bonus)
    local base = number(definition, "base_health")
    if not base or base <= 0 then return nil end
    local multiplier = number(definition, "max_health_multiplier") or 1
    local global_multiplier = global_rules.number(
        "hero_meta_max_health_multiplier", 1
    )
    return math.max(1, math.floor(
        base * multiplier * global_multiplier
            + (tonumber(attribute_health_bonus) or 0)
    ))
end

function M.apply_configured_health(unit, definition, attribute_health_bonus)
    local target = M.configured_max_health(definition, attribute_health_bonus)
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
    local configured_mana = M.apply_configured_mana(unit, definition, true)

    logger.info(
        "HeroStat",
        tostring(definition.hero_id) .. " data applied max_health="
            .. tostring(configured_health)
            .. " max_mana=" .. tostring(configured_mana)
    )
end

return M
