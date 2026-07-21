local event_bus = require("core/event_bus")
local events = require("core/events")
local heroes = require("config/generated/hero_definitions")
local weapons = require("config/generated/weapon_definitions")
local number_config = require("config/combat_number_config")
-- Composition-only bootstrap: services communicate exclusively through event_bus.
local effect_handler_registry = require("systems/effect_handler_registry")
local equipment_effect_service = require("systems/equipment_effect_service")
local equipment_stat_aggregation_service =
    require("systems/equipment_stat_aggregation_service")
local triggered_proc_service = require("systems/triggered_proc_service")

local M = {}
local state_by_player = {}

local function on_damage(payload)
    local player_id = tonumber(payload.player_id)
    local state = state_by_player[player_id]
    if not state or not state.snapshot then return end
    state.snapshot.last_damage = payload
    event_bus.emit(events.HERO_COMBAT_STATS_CHANGED, {
        player_id = player_id, snapshot = state.snapshot,
    })
end

local function value(definition, key, fallback)
    local number = tonumber(definition and definition[key])
    return number ~= nil and number or fallback or 0
end

local function safe_get(unit, method_name, fallback)
    local method = unit and unit[method_name]
    if type(method) ~= "function" then
        return fallback or 0
    end
    local ok, result = pcall(method, unit)
    return ok and tonumber(result) or fallback or 0
end

local function safe_call(unit, method_name, ...)
    local method = unit and unit[method_name]
    if type(method) ~= "function" then
        return false
    end
    return pcall(method, unit, ...)
end

local function current(player_id)
    return state_by_player[player_id]
end

local function weapon_snapshot(player_id)
    local equipment = event_bus.request(
        events.WEAPON_EQUIPMENT_GET_REQUEST,
        { player_id = player_id }
    )
    local growth = event_bus.request(
        events.WEAPON_GROWTH_GET_REQUEST,
        { player_id = player_id }
    )
    return equipment and equipment.snapshot or {},
        growth and growth.snapshot or {}
end

local function primary_logical_attribute(unit, definition, stats)
    local name = tostring(definition.primary_attribute or "")
    if name == "strength" then return stats.strength end
    if name == "agility" then return stats.agility end
    if name == "intellect" then return stats.intellect end
    local attribute = safe_get(unit, "GetPrimaryAttribute", -1)
    if attribute == 0 then return stats.strength end
    if attribute == 1 then return stats.agility end
    if attribute == 2 then return stats.intellect end
    return 0
end

local function base_snapshot(unit, definition)
    local all_bonus = value(definition, "all_attributes_bonus", 0)
    local stats = {
        strength = value(
            definition,
            "base_strength",
            safe_get(unit, "GetBaseStrength", safe_get(unit, "GetStrength", 0))
        ) + all_bonus,
        agility = value(
            definition,
            "base_agility",
            safe_get(unit, "GetBaseAgility", safe_get(unit, "GetAgility", 0))
        ) + all_bonus,
        intellect = value(
            definition,
            "base_intellect",
            safe_get(unit, "GetBaseIntellect", safe_get(unit, "GetIntellect", 0))
        ) + all_bonus,
    }
    local primary = primary_logical_attribute(unit, definition, stats)
    local damage_multiplier = value(definition, "damage_multiplier", 1)
    local fallback_min = safe_get(unit, "GetBaseDamageMin", 0) + primary
    local fallback_max = safe_get(unit, "GetBaseDamageMax", 0) + primary
    stats.attack_min = value(
        definition,
        "base_damage_min",
        fallback_min
    ) * damage_multiplier
    stats.attack_max = value(
        definition,
        "base_damage_max",
        fallback_max
    ) * damage_multiplier
    return stats
end

local function primary_engine_attribute(unit, projected)
    local attribute = safe_get(unit, "GetPrimaryAttribute", -1)
    if attribute == 0 then return projected.strength end
    if attribute == 1 then return projected.agility end
    if attribute == 2 then return projected.intellect end
    return 0
end

local function apply_base_projection(state)
    local unit = state.unit
    local scale = 1
    local projected = {
        strength = state.base.strength / scale,
        agility = state.base.agility / scale,
        intellect = state.base.intellect / scale,
    }
    safe_call(unit, "SetBaseStrength", projected.strength)
    safe_call(unit, "SetBaseAgility", projected.agility)
    safe_call(unit, "SetBaseIntellect", projected.intellect)
    safe_call(unit, "CalculateStatBonus", true)
    local primary = primary_engine_attribute(unit, projected)
    local minimum = state.base.attack_min / scale - primary
    local maximum = state.base.attack_max / scale - primary
    safe_call(unit, "SetBaseDamageMin", minimum)
    safe_call(unit, "SetBaseDamageMax", maximum)
    safe_call(unit, "CalculateStatBonus", true)
end

local function recalculate(player_id, reason)
    local state = current(player_id)
    if not state or not state.unit or state.unit:IsNull() then
        return nil
    end
    local equipment, growth = weapon_snapshot(player_id)
    local equipment_stats = event_bus.request(
        events.EQUIPMENT_STATS_GET_REQUEST,
        { player_id = player_id }
    )
    local effect_values = equipment_stats and equipment_stats.snapshot
        and equipment_stats.snapshot.values or {}
    local definition = weapons.by_id[equipment.main_hand_content_id] or {}
    local weapon_attack_min = value(definition, "base_attack_min", 0)
        + value(growth, "growth_attack", 0)
    local weapon_attack_max = value(definition, "base_attack_max", 0)
        + value(growth, "growth_attack", 0)
    local weapon_strength = value(definition, "base_strength", 0)
        + value(growth, "growth_strength", 0)
    local weapon_agility = value(definition, "base_agility", 0)
        + value(growth, "growth_agility", 0)
    local weapon_intellect = value(definition, "base_intellect", 0)
        + value(growth, "growth_intellect", 0)
    local scale = 1
    local debug_attack = tonumber(state.debug_attack_override)
    state.snapshot = {
        player_id = player_id,
        hero_id = state.hero_id,
        entindex = state.unit:entindex(),
        scale = scale,
        weapon_content_id = equipment.main_hand_content_id or "",
        weapon_name = equipment.main_hand_name ~= ""
            and equipment.main_hand_name or "未装备武器",
        attack_min = debug_attack or (state.base.attack_min + weapon_attack_min),
        attack_max = debug_attack or (state.base.attack_max + weapon_attack_max),
        debug_attack_override = debug_attack or 0,
        armor = safe_get(state.unit, "GetPhysicalArmorValue", 0),
        -- attack_speed 表示每秒攻击次数；引擎保存的是基础攻击间隔。
        attack_speed = tonumber(state.unit.survival_attack_speed)
            or (1 / math.max(0.01, safe_get(state.unit, "GetBaseAttackTime", 0.5))),
        attack_speed_stat = safe_get(state.unit, "GetAttackSpeed", 100),
        strength = state.base.strength + weapon_strength,
        agility = state.base.agility + weapon_agility,
        intellect = state.base.intellect + weapon_intellect,
        hero_base_attack_min = state.base.attack_min,
        hero_base_attack_max = state.base.attack_max,
        weapon_base_attack_min = value(definition, "base_attack_min", 0),
        weapon_base_attack_max = value(definition, "base_attack_max", 0),
        weapon_growth_attack = value(growth, "growth_attack", 0),
        stage_attack_count = value(growth, "stage_attack_count", 0),
        stage_attack_target = value(growth, "stage_attack_target", 0),
        stage_attack_remaining = value(growth, "stage_attack_remaining", 0),
        forging_hammer_count = value(growth, "forging_hammer_count", 0),
        progress_per_attack = value(growth, "progress_per_attack", 1),
        attack_gain_per_attack = value(growth, "attack_gain_per_attack", 0),
        equipment_attack = value(effect_values, "attack_flat", 0),
        engine_weapon_attack_bonus = debug_attack
            and (debug_attack
                - ((state.base.attack_min + state.base.attack_max) * 0.5)
                - value(effect_values, "attack_flat", 0))
            or (((weapon_attack_min + weapon_attack_max) * 0.5)
                - primary_logical_attribute(state.unit, state.definition, {
                    strength = weapon_strength,
                    agility = weapon_agility,
                    intellect = weapon_intellect,
                })),
        engine_weapon_strength_bonus = weapon_strength / scale,
        engine_weapon_agility_bonus = weapon_agility / scale,
        engine_weapon_intellect_bonus = weapon_intellect / scale,
        equipment_attack_speed_pct = value(effect_values, "attack_speed_pct", 0),
        equipment_health = value(effect_values, "health_flat", 0),
        equipment_armor = value(effect_values, "armor_flat", 0),
        equipment_all_attributes = value(effect_values, "all_attributes_flat", 0),
        equipment_lifesteal_pct = value(effect_values, "lifesteal_pct", 0),
        reason = reason or "changed",
    }
    local modifier = state.unit:FindModifierByName(
        "modifier_weapon_stat_projection"
    )
    if modifier and modifier.ForceRefresh then
        modifier:ForceRefresh()
    end
    event_bus.emit(events.HERO_COMBAT_STATS_CHANGED, {
        player_id = player_id,
        snapshot = state.snapshot,
    })
    return state.snapshot
end

local function on_hero_summoned(payload)
    local definition = heroes.by_id[payload.hero_id] or {}
    local state = {
        unit = payload.unit,
        hero_id = payload.hero_id,
        definition = definition,
        base = base_snapshot(payload.unit, definition),
        snapshot = nil,
    }
    state_by_player[payload.player_id] = state
    apply_base_projection(state)
    local function ensure_modifier(name)
        local existing = payload.unit:FindModifierByName(name)
        if existing then return existing end
        local created = payload.unit:AddNewModifier(
            payload.unit, nil, name, { player_id = payload.player_id }
        )
        print(string.format(
            "[SURVIVAL_MODIFIER_CREATE] name=%s entindex=%s created=%s",
            name, tostring(payload.unit:entindex()), tostring(created ~= nil)
        ))
        return created
    end
    ensure_modifier("modifier_weapon_stat_projection")
    ensure_modifier("modifier_equipment_effects")
    recalculate(payload.player_id, "hero_summoned")
end

local function on_changed(payload)
    local player_id = tonumber(payload.player_id)
    local state = current(player_id)
    local modifier = state and state.unit and state.unit:FindModifierByName(
        "modifier_equipment_effects"
    )
    if modifier and modifier.ForceRefresh then modifier:ForceRefresh() end
    recalculate(player_id, payload.reason)
    if state and state.unit then
        safe_call(state.unit, "CalculateStatBonus", true)
    end
end

local function debug_set_attack(payload)
    local player_id = tonumber(payload.player_id)
    local state = current(player_id)
    if not state or not state.unit or state.unit:IsNull() then
        return { ok = false, error = "hero_not_summoned" }
    end
    if payload.reset == true then
        state.debug_attack_override = nil
    else
        local attack = tonumber(payload.attack)
        if not attack or attack < 0 or attack > 9000000000000000 then
            return { ok = false, error = "debug_attack_invalid" }
        end
        state.debug_attack_override = attack
    end
    local snapshot = recalculate(player_id, payload.reset == true
        and "debug_attack_reset" or "debug_attack_override")
    return { ok = true, snapshot = snapshot }
end

local function get_stats(payload)
    local player_id = tonumber(payload.player_id)
    local state = current(player_id)
    if not state then
        return { ok = false, error = "hero_not_summoned" }
    end
    return {
        ok = true,
        snapshot = state.snapshot or recalculate(player_id, "request"),
    }
end

function M.init()
    state_by_player = {}
    effect_handler_registry.init()
    equipment_stat_aggregation_service.init()
    equipment_effect_service.init()
    triggered_proc_service.init()
    event_bus.handle_request(events.HERO_COMBAT_STATS_GET_REQUEST, get_stats)
    event_bus.handle_request(
        events.HERO_COMBAT_STATS_DEBUG_ATTACK_REQUEST,
        debug_set_attack
    )
    event_bus.subscribe(events.COMBAT_DAMAGE_RESOLVED, on_damage)
    event_bus.subscribe(events.HERO_SUMMONED, on_hero_summoned)
    event_bus.subscribe(events.WEAPON_EQUIPPED_CHANGED, on_changed)
    event_bus.subscribe(events.WEAPON_GROWTH_CHANGED, on_changed)
    event_bus.subscribe(events.EQUIPMENT_STATS_CHANGED, on_changed)
end

return M
