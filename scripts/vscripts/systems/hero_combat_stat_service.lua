local event_bus = require("core/event_bus")
local events = require("core/events")
local heroes = require("config/generated/hero_definitions")
local weapons = require("config/generated/weapon_definitions")
local number_config = require("config/combat_number_config")
local global_rules = require("config/global_rules")
local hero_health_guard = require("core/hero_health_guard")
-- Composition-only bootstrap: services communicate exclusively through event_bus.
local effect_handler_registry = require("systems/effect_handler_registry")
local equipment_effect_service = require("systems/equipment_effect_service")
local equipment_stat_aggregation_service =
    require("systems/equipment_stat_aggregation_service")
local triggered_proc_service = require("systems/triggered_proc_service")
local technology_stat_manager = require("systems/technology_stat_manager")
local hero_combat_stat_math = require("systems/hero_combat_stat_math")

local M = {}
local state_by_player = {}

local function on_damage(payload)
    local player_id = tonumber(payload.player_id)
    local state = state_by_player[player_id]
    if not state then return end
    -- Damage telemetry is intentionally kept out of the combat-stat snapshot.
    -- Publishing the full snapshot for every hit caused network/UI work to
    -- scale with attack speed and proc count.
    state.last_damage = payload
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

local function snapshot_equal(left, right)
    if not left or not right then return false end
    for key, value in pairs(left) do
        if key ~= "reason" and right[key] ~= value then return false end
    end
    for key, value in pairs(right) do
        if key ~= "reason" and left[key] ~= value then return false end
    end
    return true
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

local function get_all_equipment_stats(player_id)
    local response = event_bus.request(
        events.EQUIPMENT_STATS_GET_REQUEST,
        { player_id = player_id }
    )
    local values = response and response.snapshot
        and response.snapshot.values or {}
    return {
        attack_flat = tonumber(values.attack_flat) or 0,
        health_flat = tonumber(values.health_flat) or 0,
        armor_flat = tonumber(values.armor_flat) or 0,
        attack_speed_pct = tonumber(values.attack_speed_pct) or 0,
        lifesteal_pct = tonumber(values.lifesteal_pct) or 0,
        all_attributes_flat = tonumber(values.all_attributes_flat) or 0,
    }
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
        + global_rules.number("hero_meta_all_attributes_bonus", 0)
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
    local fallback_min = safe_get(unit, "GetBaseDamageMin", 0)
    local fallback_max = safe_get(unit, "GetBaseDamageMax", 0)
    stats.attack_min = value(
        definition,
        "base_damage_min",
        fallback_min
    )
    stats.attack_max = value(
        definition,
        "base_damage_max",
        fallback_max
    )
    return stats
end

local function configured_damage_multiplier(definition)
    return hero_combat_stat_math.damage_multiplier(
        definition,
        global_rules.number("hero_meta_damage_multiplier", 1)
    )
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
    hero_health_guard.preserve_current(unit, function()
        safe_call(unit, "SetBaseStrength", 0)
        safe_call(unit, "SetBaseAgility", 0)
        safe_call(unit, "SetBaseIntellect", 0)
        safe_call(unit, "CalculateStatBonus", true)
        -- Keep the legacy damage multiplier on native basic attacks while the
        -- logical/UI attack remains the unmultiplied CSV value.
        local minimum = math.max(0, state.engine_base_attack_min)
        local maximum = math.max(minimum, state.engine_base_attack_max)
        safe_call(unit, "SetBaseDamageMin", minimum)
        safe_call(unit, "SetBaseDamageMax", maximum)
        safe_call(unit, "CalculateStatBonus", true)
    end)
end

local function recalculate(player_id, reason)
    local state = current(player_id)
    if not state or not state.unit or state.unit:IsNull() then
        return nil
    end
    local current_health = state.unit.IsAlive and state.unit:IsAlive()
        and safe_get(state.unit, "GetHealth", nil) or nil
    local equipment, growth = weapon_snapshot(player_id)
    local equipment_stats = get_all_equipment_stats(player_id)
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
    local hero_technology = technology_stat_manager.get(player_id).final.hero or {}
    local researcher_attack_flat = tonumber(hero_technology.attack_flat) or 0
    local researcher_attack_pct = tonumber(hero_technology.attack_bonus_pct) or 0
    local researcher_final_damage_pct =
        tonumber(hero_technology.final_damage_bonus_pct) or 0
    local researcher_armor_reduction =
        tonumber(hero_technology.armor_reduction_per_attack) or 0
    local researcher_critical_chance_pct =
        tonumber(hero_technology.critical_chance_pct) or 0
    local essence_result = event_bus.request(
        events.SEVEN_SINS_ESSENCE_STATS_GET_REQUEST,
        { player_id = player_id }
    )
    local essence = essence_result and essence_result.snapshot or {}
    local progression_result = event_bus.request(
        events.HERO_PROGRESSION_GET_REQUEST,
        { player_id = player_id }
    )
    local progression = progression_result and progression_result.snapshot or {}
    local progression_attributes = tonumber(progression.all_attributes) or 0
    local essence_attack_pct = tonumber(essence.attack_bonus_pct) or 0
    researcher_armor_reduction = researcher_armor_reduction
        + (tonumber(essence.armor_reduction_per_attack) or 0)
    local essence_attributes_pct = tonumber(essence.all_attributes_pct) or 0
    local unscaled_strength = state.base.strength + weapon_strength
        + progression_attributes
        + equipment_stats.all_attributes_flat
    local unscaled_agility = state.base.agility + weapon_agility
        + progression_attributes
        + equipment_stats.all_attributes_flat
    local unscaled_intellect = state.base.intellect + weapon_intellect
        + progression_attributes
        + equipment_stats.all_attributes_flat
    local strength_bonus = unscaled_strength * essence_attributes_pct / 100
    local agility_bonus = unscaled_agility * essence_attributes_pct / 100
    local intellect_bonus = unscaled_intellect * essence_attributes_pct / 100
    local base_attack_time = math.max(0.1,
        hero_combat_stat_math.configured_base_attack_time(
            state.definition,
            state.engine_base_attack_time
        ) - (tonumber(essence.attack_interval_flat) or 0))
    local hero_damage_multiplier = state.damage_multiplier
    local next_snapshot = {
        player_id = player_id,
        hero_id = state.hero_id,
        entindex = state.unit:entindex(),
        scale = scale,
        weapon_content_id = equipment.main_hand_content_id or "",
        weapon_name = equipment.main_hand_name ~= ""
            and equipment.main_hand_name or "未装备武器",
        attack_min = debug_attack or ((state.base.attack_min + weapon_attack_min)
            * (1 + (researcher_attack_pct + essence_attack_pct) / 100)
            + equipment_stats.attack_flat
            + researcher_attack_flat),
        attack_max = debug_attack or ((state.base.attack_max + weapon_attack_max)
            * (1 + (researcher_attack_pct + essence_attack_pct) / 100)
            + equipment_stats.attack_flat
            + researcher_attack_flat),
        researcher_attack_pct = researcher_attack_pct,
        researcher_final_damage_pct = researcher_final_damage_pct,
        researcher_armor_reduction = researcher_armor_reduction,
        researcher_critical_chance_pct = researcher_critical_chance_pct,
        seven_sins_attack_bonus_pct = essence_attack_pct,
        seven_sins_final_damage_pct = tonumber(essence.final_damage_pct) or 0,
        seven_sins_all_attributes_pct = essence_attributes_pct,
        seven_sins_strength_bonus = strength_bonus,
        seven_sins_agility_bonus = agility_bonus,
        seven_sins_intellect_bonus = intellect_bonus,
        seven_sins_attributes_per_kill = tonumber(essence.attributes_per_kill) or 0,
        seven_sins_attack_interval_flat = tonumber(essence.attack_interval_flat) or 0,
        seven_sins_attributes_per_attack = tonumber(essence.attributes_per_attack) or 0,
        seven_sins_armor_reduction_per_attack =
            tonumber(essence.armor_reduction_per_attack) or 0,
        progression_all_attributes = progression_attributes,
        base_attack_time = base_attack_time,
        hero_damage_multiplier = hero_damage_multiplier,
        debug_attack_override = debug_attack or 0,
        runtime_armor = safe_get(state.unit, "GetPhysicalArmorValue", 0),
        -- 配置值使用“每秒攻击次数”。由配置 BAT、固定间隔变化和装备
        -- 攻速百分比直接投影，避免读取引擎当前帧临时攻击间隔。
        attack_speed = hero_combat_stat_math.attacks_per_second(
            base_attack_time,
            equipment_stats.attack_speed_pct
        ),
        attack_speed_stat = safe_get(state.unit, "GetAttackSpeed", 100),
        strength = unscaled_strength + strength_bonus,
        agility = unscaled_agility + agility_bonus,
        intellect = unscaled_intellect + intellect_bonus,
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
        damage_gain_attack = value(growth, "damage_gain_attack", 0),
        damage_gain_all_attributes = value(
            growth,
            "damage_gain_all_attributes",
            0
        ),
        equipment_attack = equipment_stats.attack_flat,
        engine_research_attack_bonus = ((state.engine_base_attack_min
            + state.engine_base_attack_max
            + weapon_attack_min + weapon_attack_max)
            * 0.5) * (researcher_attack_pct + essence_attack_pct) / 100
            + researcher_attack_flat,
        engine_weapon_attack_bonus = debug_attack
            and (debug_attack
                - ((state.engine_base_attack_min
                    + state.engine_base_attack_max) * 0.5)
                - equipment_stats.attack_flat)
            or ((weapon_attack_min + weapon_attack_max) * 0.5),
        equipment_attack_speed_pct = equipment_stats.attack_speed_pct,
        equipment_health = equipment_stats.health_flat,
        equipment_armor = equipment_stats.armor_flat,
        equipment_all_attributes = equipment_stats.all_attributes_flat,
        equipment_lifesteal_pct = equipment_stats.lifesteal_pct,
        reason = reason or "changed",
    }
    local changed = not snapshot_equal(state.snapshot, next_snapshot)
    state.snapshot = next_snapshot
    state.unit.survival_seven_sins_final_damage_pct =
        tonumber(essence.final_damage_pct) or 0
    local research_modifier = state.unit:FindModifierByName(
        "modifier_research_technology"
    ) or state.unit:AddNewModifier(
        state.unit, nil, "modifier_research_technology", {}
    )
    if research_modifier and research_modifier.SetTechnologyValues then
        research_modifier:SetTechnologyValues(
            researcher_attack_pct,
            researcher_final_damage_pct,
            researcher_armor_reduction,
            researcher_critical_chance_pct
        )
    end
    local modifier = state.unit:FindModifierByName(
        "modifier_weapon_stat_projection"
    )
    local projection_refresh_required =
        tostring(reason or "") ~= "attack_all_attribute_growth"
        or essence_attributes_pct ~= 0
    if projection_refresh_required and modifier and modifier.ForceRefresh then
        modifier:ForceRefresh()
    end
    if changed then
        event_bus.emit(events.HERO_COMBAT_STATS_CHANGED, {
            player_id = player_id,
            snapshot = state.snapshot,
        })
    end
    if projection_refresh_required and current_health and current_health > 0
        and state.unit:IsAlive() then
        hero_health_guard.protect_value(
            state.unit,
            current_health,
            "combat_recalculate:" .. tostring(reason or "changed")
        )
    end
    return state.snapshot
end

local function on_hero_summoned(payload)
    local definition = heroes.by_id[payload.hero_id] or {}
    local base = base_snapshot(payload.unit, definition)
    local damage_multiplier = configured_damage_multiplier(definition)
    local state = {
        unit = payload.unit,
        hero_id = payload.hero_id,
        definition = definition,
        base = base,
        damage_multiplier = damage_multiplier,
        engine_base_attack_min = hero_combat_stat_math.engine_base_damage(
            base.attack_min,
            damage_multiplier
        ),
        engine_base_attack_max = hero_combat_stat_math.engine_base_damage(
            base.attack_max,
            damage_multiplier
        ),
        engine_base_attack_time = safe_get(payload.unit, "GetBaseAttackTime", 2),
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
    local snapshot = recalculate(payload.player_id, "hero_summoned") or {}
    print(string.format(
        "[HeroCombatReady] hero=%s entindex=%s base_damage=%.1f-%.1f "
            .. "engine_damage=%.1f-%.1f attack_range=%.1f move_capability=%s",
        tostring(payload.hero_id),
        tostring(payload.unit:entindex()),
        tonumber(state.base.attack_min) or 0,
        tonumber(state.base.attack_max) or 0,
        safe_get(payload.unit, "GetBaseDamageMin", 0),
        safe_get(payload.unit, "GetBaseDamageMax", 0),
        safe_get(payload.unit, "GetAttackRange", 0),
        tostring(safe_get(payload.unit, "GetMoveCapability", -1))
    ))
end

local function on_changed(payload)
    local player_id = tonumber(payload.player_id)
    local state = current(player_id)
    local modifier = state and state.unit and state.unit:FindModifierByName(
        "modifier_equipment_effects"
    )
    if state and state.unit then
        hero_health_guard.preserve_missing(state.unit, function()
            if modifier and modifier.ForceRefresh then modifier:ForceRefresh() end
            safe_call(state.unit, "CalculateStatBonus", true)
        end, "equipment_refresh:" .. tostring(payload.reason or "changed"))
    end
    recalculate(player_id, payload.reason)
end

local function on_progression_changed(payload)
    -- Per-attack attribute growth changes logical/native attributes, but it does
    -- not change equipment health. Refreshing the health-bonus modifier here
    -- made Dota recalculate maximum health on every landed attack.
    recalculate(tonumber(payload.player_id), payload.reason)
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

local function on_technology_stats_changed(payload)
    local player_id = tonumber(payload and payload.player_id)
    if player_id == nil then return end
    recalculate(player_id, "technology_stats_changed")
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
    -- CONTENT_INVENTORY_CHANGED subscribers are unordered. Refresh only after
    -- the equipment aggregator has published its completed snapshot; otherwise
    -- this service can read the previous armor value and leave the HUD stale.
    event_bus.subscribe(events.EQUIPMENT_STATS_CHANGED, on_changed)
    event_bus.subscribe(events.TECHNOLOGY_STATS_CHANGED, on_technology_stats_changed)
    event_bus.subscribe(events.SEVEN_SINS_ESSENCE_CHANGED, on_progression_changed)
    event_bus.subscribe(events.HERO_PROGRESSION_CHANGED, on_progression_changed)
end

M._test = {
    base_snapshot = base_snapshot,
    configured_damage_multiplier = configured_damage_multiplier,
}

return M
