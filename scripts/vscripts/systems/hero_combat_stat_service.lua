local event_bus = require("core/event_bus")
local events = require("core/events")
local heroes = require("config/generated/hero_definitions")
local weapons = require("config/generated/weapon_definitions")
local number_config = require("config/combat_number_config")
local global_rules = require("config/global_rules")
-- Composition-only bootstrap: services communicate exclusively through event_bus.
local effect_handler_registry = require("systems/effect_handler_registry")
local equipment_effect_service = require("systems/equipment_effect_service")
local equipment_stat_aggregation_service =
    require("systems/equipment_stat_aggregation_service")
local triggered_proc_service = require("systems/triggered_proc_service")
local technology_stat_manager = require("systems/technology_stat_manager")

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
    local damage_multiplier = value(definition, "damage_multiplier", 1)
        * global_rules.number("hero_meta_damage_multiplier", 1)
    local fallback_min = safe_get(unit, "GetBaseDamageMin", 0)
    local fallback_max = safe_get(unit, "GetBaseDamageMax", 0)
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
    safe_call(unit, "SetBaseStrength", 0)
    safe_call(unit, "SetBaseAgility", 0)
    safe_call(unit, "SetBaseIntellect", 0)
    safe_call(unit, "CalculateStatBonus", true)
    -- CSV base_damage is engine base damage. Do not subtract the primary
    -- attribute here: doing so produced negative base damage for heroes such
    -- as Juggernaut (20 - 100 agility), which could resolve attacks as zero.
    local minimum = math.max(0, state.base.attack_min)
    local maximum = math.max(minimum, state.base.attack_max)
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
    local seconds_per_attack = safe_get(state.unit, "GetSecondsPerAttack", 0)
    if seconds_per_attack <= 0 then
        local base_attack_time = math.max(
            0.01, safe_get(state.unit, "GetBaseAttackTime", 2)
        )
        seconds_per_attack = base_attack_time
            / math.max(0.01, 1 + equipment_stats.attack_speed_pct / 100)
    end
    local next_snapshot = {
        player_id = player_id,
        hero_id = state.hero_id,
        entindex = state.unit:entindex(),
        scale = scale,
        weapon_content_id = equipment.main_hand_content_id or "",
        weapon_name = equipment.main_hand_name ~= ""
            and equipment.main_hand_name or "未装备武器",
        attack_min = debug_attack or ((state.base.attack_min + weapon_attack_min)
            * (1 + researcher_attack_pct / 100) + equipment_stats.attack_flat
            + researcher_attack_flat),
        attack_max = debug_attack or ((state.base.attack_max + weapon_attack_max)
            * (1 + researcher_attack_pct / 100) + equipment_stats.attack_flat
            + researcher_attack_flat),
        researcher_attack_pct = researcher_attack_pct,
        researcher_final_damage_pct = researcher_final_damage_pct,
        researcher_armor_reduction = researcher_armor_reduction,
        debug_attack_override = debug_attack or 0,
        armor = safe_get(state.unit, "GetPhysicalArmorValue", 0),
        -- attack_speed 表示每秒攻击次数，与装备攻速百分比使用同一权威数据。
        attack_speed = 1 / math.max(0.01, seconds_per_attack),
        attack_speed_stat = safe_get(state.unit, "GetAttackSpeed", 100),
        strength = state.base.strength + weapon_strength
            + equipment_stats.all_attributes_flat,
        agility = state.base.agility + weapon_agility
            + equipment_stats.all_attributes_flat,
        intellect = state.base.intellect + weapon_intellect
            + equipment_stats.all_attributes_flat,
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
        equipment_attack = equipment_stats.attack_flat,
        engine_research_attack_bonus = ((state.base.attack_min
            + state.base.attack_max + weapon_attack_min + weapon_attack_max)
            * 0.5) * researcher_attack_pct / 100 + researcher_attack_flat,
        engine_weapon_attack_bonus = debug_attack
            and (debug_attack
                - ((state.base.attack_min + state.base.attack_max) * 0.5)
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
    local research_modifier = state.unit:FindModifierByName(
        "modifier_research_technology"
    ) or state.unit:AddNewModifier(
        state.unit, nil, "modifier_research_technology", {}
    )
    if research_modifier and research_modifier.SetTechnologyValues then
        research_modifier:SetTechnologyValues(
            researcher_attack_pct,
            researcher_final_damage_pct,
            researcher_armor_reduction
        )
    end
    local modifier = state.unit:FindModifierByName(
        "modifier_weapon_stat_projection"
    )
    if modifier and modifier.ForceRefresh then
        modifier:ForceRefresh()
    end
    if changed then
        event_bus.emit(events.HERO_COMBAT_STATS_CHANGED, {
            player_id = player_id,
            snapshot = state.snapshot,
        })
    end
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
    if modifier and modifier.ForceRefresh then modifier:ForceRefresh() end
    if state and state.unit then
        safe_call(state.unit, "CalculateStatBonus", true)
    end
    recalculate(player_id, payload.reason)
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
    event_bus.subscribe(events.CONTENT_INVENTORY_CHANGED, on_changed)
    event_bus.subscribe(events.TECHNOLOGY_STATS_CHANGED, on_technology_stats_changed)
end

return M
