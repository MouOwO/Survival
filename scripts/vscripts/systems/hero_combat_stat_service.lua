local event_bus = require("core/event_bus")
local modifier_registry = require("core/modifier_registry")
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
local hero_stat_adapter = require("systems/hero_stat_adapter")
local monkey_runtime = require("config/generated/monkey_king_exclusive_runtime")
local blademaster_runtime = require("config/generated/blademaster_exclusive_runtime")
local armor_balance = require("config/armor_balance")
local endless_projection = require("combat/endless_stat_projection")

local M = {}
local state_by_player = {}
local pending_recalculations = {}
local flush_recalculation

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

local function fixed_attack_interval(unit)
    if not unit or type(unit.FindModifierByName) ~= "function" then return nil end
    local ok, modifier = pcall(unit.FindModifierByName, unit,
        "modifier_debug_fixed_attack_rate")
    if not ok or not modifier then return nil end
    local interval = safe_get(modifier, "GetModifierFixedAttackRate", 0)
    if interval ~= interval or interval <= 0 or interval == math.huge then return nil end
    return interval
end

local function field_equal(a,b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k,v in pairs(a) do if not field_equal(v,b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
local function snapshot_equal(left, right)
    if not left or not right then return false end
    for key, value in pairs(left) do
        if key ~= "reason" and key ~= "refresh_version"
            and not field_equal(right[key],value) then return false end
    end
    for key, value in pairs(right) do
        if key ~= "reason" and key ~= "refresh_version"
            and not field_equal(left[key],value) then return false end
    end
    return true
end

local function current(player_id)
    return state_by_player[player_id]
end

local function weapon_snapshot(player_id, growth_snapshot)
    local equipment = event_bus.request(
        events.WEAPON_EQUIPMENT_GET_REQUEST,
        { player_id = player_id }
    )
    local growth = not growth_snapshot and event_bus.request(
        events.WEAPON_GROWTH_GET_REQUEST, { player_id = player_id }
    )
    return equipment and equipment.snapshot or {},
        growth_snapshot or (growth and growth.snapshot) or {}
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

local function base_snapshot(unit, definition)
    local all_bonus = value(definition, "all_attributes_bonus", 0)
        + global_rules.number("hero_meta_all_attributes_bonus", 0)
    local stats = {
        strength = value(
            definition,
            "base_strength",
            0
        ) + all_bonus,
        agility = value(
            definition,
            "base_agility",
            0
        ) + all_bonus,
        intellect = value(
            definition,
            "base_intellect",
            0
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

local function active_skills(player_id)
    local result = event_bus.request(
        events.HERO_SKILL_STATE_GET_REQUEST,
        { player_id = player_id }
    )
    local active = {}
    for _, skill in ipairs(result and result.snapshot
            and result.snapshot.skills or {}) do
        if skill.locked ~= 1
            and (tonumber(skill.level) or 0) > 0 then
            active[skill.skill_id] = true
        end
    end
    return active
end

local function set_native_value(state, key, method, value)
    state.native_projection = state.native_projection or {}
    if state.native_projection[key] == value then return false end
    local ok, result = safe_call(state.unit, method, value)
    if not ok or result == false then return false end
    state.native_projection[key] = value
    return true
end

local function apply_base_projection(state)
    local unit = state.unit
    local debug_attack = tonumber(state.debug_attack_override)
    local multiplier = tonumber(state.exclusive_attack_multiplier) or 1
    local attribute_attack_bonus = tonumber(state.attribute_attack_bonus) or 0
    local minimum = debug_attack and 0 or math.max(0,
        (state.engine_base_attack_min + attribute_attack_bonus * state.damage_multiplier) * multiplier)
    local maximum = debug_attack and 0 or math.max(minimum,
        (state.engine_base_attack_max + attribute_attack_bonus * state.damage_multiplier) * multiplier)
    if state.snapshot and state.snapshot.native_base_attack_min ~= nil then
        minimum, maximum = state.snapshot.native_base_attack_min, state.snapshot.native_base_attack_max
    else
        local attack_scale = tonumber(state.unit.survival_endless_attack_scale) or 1
        minimum, maximum = math.floor(minimum / attack_scale), math.floor(maximum / attack_scale)
    end
    local previous = state.native_projection or {}
    if previous.strength == 0 and previous.agility == 0 and previous.intellect == 0
        and previous.damage_min == minimum and previous.damage_max == maximum then return false end
    hero_health_guard.preserve_current(unit, function()
        set_native_value(state, "strength", "SetBaseStrength", 0)
        set_native_value(state, "agility", "SetBaseAgility", 0)
        set_native_value(state, "intellect", "SetBaseIntellect", 0)
        -- Keep the legacy damage multiplier on native basic attacks while the
        -- logical/UI attack remains the unmultiplied CSV value.
        set_native_value(state, "damage_min", "SetBaseDamageMin", minimum)
        set_native_value(state, "damage_max", "SetBaseDamageMax", maximum)
        safe_call(unit, "CalculateStatBonus", true)
    end)
    return true
end

local function recalculate(player_id, reason, growth_snapshot)
    if player_id == nil then return nil end
    -- Structural changes also absorb any earlier growth in this dispatch.
    -- Read authoritative sources here rather than replaying an older payload.
    pending_recalculations[player_id] = nil
    local state = current(player_id)
    if not state or not state.unit or state.unit:IsNull() then
        return nil
    end
    local current_health = state.unit.IsAlive and state.unit:IsAlive()
        and safe_get(state.unit, "GetHealth", nil) or nil
    local current_max_health = state.unit.IsAlive and state.unit:IsAlive()
        and safe_get(state.unit, "GetMaxHealth", nil) or nil
    local equipment, growth = weapon_snapshot(player_id, growth_snapshot)
    local equipment_stats = get_all_equipment_stats(player_id)
    local definition = weapons.by_id[equipment.main_hand_content_id] or {}
    local configured_base_armor = value(
        state.definition,
        "base_war3_armor",
        value(state.definition, "base_armor", 0)
    )
    -- Equipment levels are complete armor snapshots, not additive deltas. When
    -- no equipped source supplies armor, retain the hero's configured base.
    local authoritative_war3_armor = equipment_stats.armor_flat ~= 0
        and equipment_stats.armor_flat or configured_base_armor
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
    local debug_attack_speed = tonumber(state.debug_attack_speed_override)
    local runtime_attack_interval = fixed_attack_interval(state.unit)
    local technology_snapshot = technology_stat_manager.get(player_id)
    local hero_technology = technology_snapshot.final.hero or {}
    local researcher_attack_flat = tonumber(hero_technology.attack_flat) or 0
    local researcher_attack_pct = tonumber(hero_technology.attack_bonus_pct) or 0
    local researcher_final_damage_pct =
        tonumber(hero_technology.final_damage_bonus_pct) or 0
    local researcher_armor_reduction =
        tonumber(hero_technology.armor_reduction_per_attack) or 0
    local researcher_critical_chance_pct =
        tonumber(hero_technology.critical_chance_pct) or 0
    local researcher_attack_speed_pct =
        tonumber(hero_technology.attack_speed_bonus_pct) or 0
    local researcher_attack_interval_flat =
        tonumber(hero_technology.attack_interval_flat) or 0
    local researcher_all_attributes =
        tonumber(hero_technology.all_attributes_flat) or 0
    local skill_flags = (state.hero_id == "hero_monkey_king" or state.hero_id == "hero_blademaster")
        and active_skills(player_id) or {}
    local monkey_w = state.hero_id == "hero_monkey_king"
        and skill_flags.skill_monkey_king_fury == true
    local monkey_e = state.hero_id == "hero_monkey_king"
        and skill_flags.skill_monkey_king_swiftness == true
    local blademaster_q = state.hero_id == "hero_blademaster"
        and skill_flags.skill_blademaster_exclusive == true
    local blademaster_r = state.hero_id == "hero_blademaster"
        and skill_flags.skill_blademaster_mobility == true
    local monkey_config = monkey_runtime.by_id.monkey_king_exclusive or {}
    local blademaster_config = blademaster_runtime.by_id.blademaster_exclusive or {}
    local monkey_critical_chance_pct = monkey_e
        and math.max(0, tonumber(monkey_config.e_critical_chance_pct) or 0)
        or 0
    local blademaster_bonus_result = event_bus.request(
        events.BLADEMASTER_BONUS_STATS_GET_REQUEST,
        { player_id = player_id }
    )
    local blademaster_bonus = blademaster_bonus_result
        and blademaster_bonus_result.snapshot or {}
    local blademaster_growth_multiplier = 1
        + math.max(0, tonumber(blademaster_bonus.attack_pct) or 0) / 100
    local exclusive_attack_multiplier = monkey_e
        and math.max(1, tonumber(monkey_config.e_attack_multiplier) or 1)
        or (blademaster_r and math.max(1,
            (tonumber(blademaster_config.r_attack_multiplier) or 1)
                * blademaster_growth_multiplier) or 1)
    local monkey_bonus_result = event_bus.request(
        events.MONKEY_KING_BONUS_STATS_GET_REQUEST,
        { player_id = player_id }
    )
    local monkey_bonus = monkey_bonus_result and monkey_bonus_result.snapshot or {}
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
    local permanent_result = event_bus.request(
        events.PERMANENT_REWARD_EFFECTS_GET_REQUEST,
        { player_id = player_id }
    )
    local permanent = permanent_result and permanent_result.totals or {}
    researcher_attack_pct = researcher_attack_pct
        + (tonumber(permanent.hero_attack_bonus_pct) or 0)
    researcher_armor_reduction = researcher_armor_reduction
        + armor_balance.from_war3_linear(
            tonumber(permanent.global_attack_armor_reduction) or 0
        )
    researcher_critical_chance_pct = researcher_critical_chance_pct
        + (tonumber(permanent.hero_critical_chance_pct) or 0)
    researcher_attack_speed_pct = researcher_attack_speed_pct
        + (tonumber(permanent.hero_attack_speed_bonus_pct) or 0)
    researcher_attack_interval_flat = researcher_attack_interval_flat
        + (tonumber(permanent.hero_attack_interval_reduction) or 0)
    local armor_flat_bonus = (tonumber(permanent.hero_initial_armor) or 0)
        + (tonumber(permanent.team_hero_wall_armor_bonus) or 0)
    -- Percentage armor bonuses use the current panel, including fused
    -- equipment armor and already-added flat hero/team armor.
    local panel_armor = authoritative_war3_armor + armor_flat_bonus
    local gameplay_armor_bonus = panel_armor
            * (tonumber(permanent.hero_armor_bonus_pct) or 0) / 100
        + armor_flat_bonus
    authoritative_war3_armor = authoritative_war3_armor
        + gameplay_armor_bonus
    local progression_attributes = (tonumber(progression.all_attributes) or 0)
        + (tonumber(permanent.hero_all_attributes_flat) or 0)
        + (tonumber(permanent.hero_attributes_per_level) or 0)
            * math.max(1, safe_get(state.unit, "GetLevel", 1))
    local progression_attack_flat = (tonumber(progression.attack_flat) or 0)
        + (tonumber(permanent.hero_attack_flat) or 0)
    local essence_attack_pct = tonumber(essence.attack_bonus_pct) or 0
    researcher_armor_reduction = researcher_armor_reduction
        + (tonumber(essence.armor_reduction_per_attack) or 0)
        + armor_balance.from_war3_linear(
            tonumber(permanent.hero_attack_armor_reduction) or 0
        )
    local essence_attributes_pct = tonumber(essence.all_attributes_pct) or 0
    -- Percentage attack bonuses use the current displayed panel. Include
    -- equipment and all flat attack already present before applying the
    -- percentage; equipment still contributes its flat value separately via
    -- modifier_equipment_effects.
    local total_attack_pct = researcher_attack_pct + essence_attack_pct
    local flat_panel_attack = equipment_stats.attack_flat
        + researcher_attack_flat + progression_attack_flat
    local engine_research_attack_bonus = debug_attack and 0 or (
        ((state.engine_base_attack_min
            + state.engine_base_attack_max
            + weapon_attack_min + weapon_attack_max)
            * 0.5) * total_attack_pct / 100
            + flat_panel_attack * total_attack_pct / 100
            + researcher_attack_flat
            + progression_attack_flat
    ) * exclusive_attack_multiplier
    local engine_weapon_attack_bonus = (debug_attack
        and (debug_attack - equipment_stats.attack_flat)
        or ((weapon_attack_min + weapon_attack_max) * 0.5)
            * exclusive_attack_multiplier)
    local engine_bonus_attack = engine_research_attack_bonus
        + engine_weapon_attack_bonus
    local raw_strength = state.base.strength + weapon_strength
        + progression_attributes
        + researcher_all_attributes
        + equipment_stats.all_attributes_flat
        + (tonumber(monkey_bonus.strength) or 0)
    local raw_agility = state.base.agility + weapon_agility
        + progression_attributes
        + researcher_all_attributes
        + equipment_stats.all_attributes_flat
        + (tonumber(monkey_bonus.agility) or 0)
    local raw_intellect = state.base.intellect + weapon_intellect
        + progression_attributes
        + researcher_all_attributes
        + equipment_stats.all_attributes_flat
        + (tonumber(monkey_bonus.intellect) or 0)
    local rebirth_level = math.max(0,
        tonumber(progression.rebirth_level) or 0)
    local gameplay_attribute_multiplier =
        (1 + (tonumber(permanent.hero_attribute_bonus_pct) or 0) / 100)
        * (1 + rebirth_level
            * (tonumber(permanent.hero_rebirth_attribute_bonus_pct) or 0)
                / 100)
    local unscaled_strength = raw_strength * gameplay_attribute_multiplier
    local unscaled_agility = raw_agility * gameplay_attribute_multiplier
    local unscaled_intellect = raw_intellect * gameplay_attribute_multiplier
    local strength_bonus = unscaled_strength * essence_attributes_pct / 100
    local agility_bonus = unscaled_agility * essence_attributes_pct / 100
    local intellect_bonus = unscaled_intellect * essence_attributes_pct / 100
    local final_strength = unscaled_strength + strength_bonus
    local final_intellect = unscaled_intellect + intellect_bonus
    local base_attribute_health_bonus = hero_combat_stat_math.strength_health_bonus(
        final_strength,
        global_rules.hero_strength_health_per_point
    ) + (tonumber(permanent.hero_initial_health) or 0)
    -- Health percentage uses the current panel, including fused equipment
    -- health and the configured/attribute health already on the hero.
    local configured_panel_health = hero_stat_adapter.configured_max_health(
        state.definition, base_attribute_health_bonus
    ) or value(state.definition, "base_health", 0)
    local panel_health = configured_panel_health + equipment_stats.health_flat
    local attribute_health_bonus = base_attribute_health_bonus
        + panel_health * (tonumber(permanent.hero_health_bonus_pct) or 0) / 100
    local health_regen_pct = (tonumber(permanent.health_regen_per_second) or 0)
        + (tonumber(permanent.hero_health_regen_per_second) or 0)
    local attribute_attack_bonus = hero_combat_stat_math.intellect_attack_bonus(
        final_intellect,
        global_rules.hero_intellect_attack_per_point
    )
    -- The adapter protects missing health itself, and skips unchanged health
    -- projections. A second guard here scheduled redundant work on every hit.
    local _, _, _, health_changed = hero_stat_adapter.apply_configured_health(
        state.unit, state.definition, attribute_health_bonus)
    local base_attack_time = math.max(0.1,
        hero_combat_stat_math.configured_base_attack_time(
            state.definition,
            state.engine_base_attack_time
        ) - (tonumber(essence.attack_interval_flat) or 0)
            - researcher_attack_interval_flat
            - (monkey_w
                and (tonumber(monkey_config.w_attack_interval_reduction) or 0)
                or 0)
            - (blademaster_r
                and (tonumber(blademaster_config.r_attack_interval_reduction) or 0)
                or 0))
    local hero_damage_multiplier = state.damage_multiplier
    local critical_damage_pct = (monkey_w
        and (tonumber(monkey_config.w_critical_damage_pct) or 200) or 200)
        + (blademaster_q and math.max(0,
            tonumber(blademaster_config.q_critical_damage_bonus_pct) or 0) or 0)
        + (tonumber(permanent.hero_critical_damage_bonus_pct) or 0)
    local engine_base_min = debug_attack and 0 or math.max(0,
        (state.engine_base_attack_min + attribute_attack_bonus * state.damage_multiplier)
            * exclusive_attack_multiplier)
    local engine_base_max = debug_attack and 0 or math.max(engine_base_min,
        (state.engine_base_attack_max + attribute_attack_bonus * state.damage_multiplier)
            * exclusive_attack_multiplier)
    local previous_attack_scale = tonumber(state.unit.survival_endless_attack_scale) or 1
    local native_attack = endless_projection.prepare_attack_components(state.unit,
        engine_base_min, engine_base_max, engine_weapon_attack_bonus,
        engine_research_attack_bonus, equipment_stats.attack_flat,
        math.max(1, critical_damage_pct / 100))
    local next_snapshot = {
        player_id = player_id,
        hero_id = state.hero_id,
        entindex = state.unit:entindex(),
        unit_name = tostring(state.definition.unit_name or ""),
        display_name = tostring(state.definition.display_name
            or state.definition.unit_name or ""),
        level = safe_get(state.unit, "GetLevel", 1),
        scale = scale,
        weapon_content_id = equipment.main_hand_content_id or "",
        weapon_name = equipment.main_hand_name ~= ""
            and equipment.main_hand_name or "未装备武器",
        attack_min = debug_attack or (((state.base.attack_min + weapon_attack_min
            + attribute_attack_bonus + flat_panel_attack)
            * (1 + total_attack_pct / 100)) * exclusive_attack_multiplier),
        attack_max = debug_attack or (((state.base.attack_max + weapon_attack_max
            + attribute_attack_bonus + flat_panel_attack)
            * (1 + total_attack_pct / 100)) * exclusive_attack_multiplier),
        health = current_health or safe_get(state.unit, "GetMaxHealth", 1),
        max_health = safe_get(state.unit, "GetMaxHealth", 1),
        attribute_health_bonus = attribute_health_bonus,
        attribute_attack_bonus = attribute_attack_bonus,
        researcher_attack_pct = researcher_attack_pct,
        hero_attack_bonus_pct = tonumber(permanent.hero_attack_bonus_pct) or 0,
        hero_health_bonus_pct = tonumber(permanent.hero_health_bonus_pct) or 0,
        hero_armor_bonus_pct = tonumber(permanent.hero_armor_bonus_pct) or 0,
        health_regen_pct = health_regen_pct,
        health_regen_per_second = safe_get(state.unit, "GetMaxHealth", 0)
            * health_regen_pct / 100,
        researcher_final_damage_pct = researcher_final_damage_pct,
        researcher_armor_reduction = researcher_armor_reduction,
        researcher_critical_chance_pct = researcher_critical_chance_pct,
        critical_chance_pct = researcher_critical_chance_pct
            + monkey_critical_chance_pct
            + (blademaster_q and math.max(0,
                tonumber(blademaster_config.q_critical_chance_pct) or 0) or 0),
        critical_damage_pct = critical_damage_pct,
        exclusive_attack_multiplier = exclusive_attack_multiplier,
        monkey_king_w_unlocked = monkey_w and 1 or 0,
        monkey_king_e_unlocked = monkey_e and 1 or 0,
        blademaster_q_unlocked = blademaster_q and 1 or 0,
        blademaster_r_unlocked = blademaster_r and 1 or 0,
        blademaster_attack_growth_pct = tonumber(blademaster_bonus.attack_pct) or 0,
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
        progression_attack_flat = progression_attack_flat,
        base_attack_time = base_attack_time,
        -- Equipment owns its own flat attack-speed projection. Research,
        -- roguelike and permanent bonuses add to it through the hero modifier,
        -- exactly as in the panel formula; they must not also divide BAT.
        hero_attack_speed_bonus_pct = researcher_attack_speed_pct,
        hero_damage_multiplier = hero_damage_multiplier,
        engine_attack_min = debug_attack or ((state.engine_base_attack_min
            + attribute_attack_bonus * state.damage_multiplier)
                * exclusive_attack_multiplier + engine_bonus_attack),
        engine_attack_max = debug_attack or ((state.engine_base_attack_max
            + attribute_attack_bonus * state.damage_multiplier)
                * exclusive_attack_multiplier + engine_bonus_attack),
        debug_attack_override = debug_attack or 0,
        -- Native heroes get this separately from modifier_equipment_effects;
        -- clones need the missing component, while a debug override is complete.
        engine_equipment_attack_bonus = debug_attack and 0 or equipment_stats.attack_flat,
        debug_attack_speed_override = debug_attack_speed or 0,
        -- The equipment aggregation snapshot already owns the authoritative
        -- War3/CSV armor value. Do not derive the HUD value from this frame's
        -- engine armor: ForceRefresh/CalculateStatBonus may not have exposed the
        -- new modifier value yet, which previously froze a real 850 bonus at 0.
        armor = authoritative_war3_armor,
        armor_unit = "war3_display",
        stat_units_version = 2,
        -- Keep the engine value separately for runtime mitigation diagnostics.
        runtime_armor = safe_get(state.unit, "GetPhysicalArmorValue", 0),
        -- A fixed-rate modifier owns the real interval (including addspeed).
        -- Otherwise project config/equipment directly, without reading a stale
        -- engine frame during native stat recalculation.
        attack_speed = runtime_attack_interval and 1 / runtime_attack_interval
            or debug_attack_speed
            or hero_combat_stat_math.attacks_per_second(
                base_attack_time,
                equipment_stats.attack_speed_pct
            ) * math.max(0.01,1+researcher_attack_speed_pct/100)
                * math.max(0.01,1+(tonumber(state.unit.survival_cheer_attack_speed_pct) or 0)/100),
        attack_cadence = {base_interval=hero_combat_stat_math.configured_base_attack_time(
            state.definition, state.engine_base_attack_time), reduced_interval=base_attack_time,
            percentage=(100+equipment_stats.attack_speed_pct)
                * math.max(0.01,1+researcher_attack_speed_pct/100)
                * math.max(0.01,1+(tonumber(state.unit.survival_cheer_attack_speed_pct) or 0)/100),
            engine_interval=base_attack_time/math.max(0.01,1+researcher_attack_speed_pct/100),
            cheer_bonus=tonumber(state.unit.survival_cheer_attack_speed_pct) or 0,
            interval_reductions={
                {label="七宗罪",value=tonumber(essence.attack_interval_flat) or 0},
                {label="科技与存档",value=researcher_attack_interval_flat},
                {label="英雄技能",value=(monkey_w and (tonumber(monkey_config.w_attack_interval_reduction) or 0) or 0)
                    +(blademaster_r and (tonumber(blademaster_config.r_attack_interval_reduction) or 0) or 0)}},
            speed_bonuses={{label="装备",value=equipment_stats.attack_speed_pct},
                {label="科技与存档",value=researcher_attack_speed_pct},
                {label="欢呼光环",value=tonumber(state.unit.survival_cheer_attack_speed_pct) or 0}}},
        attack_speed_stat = safe_get(state.unit, "GetAttackSpeed", 100),
        strength = final_strength,
        agility = unscaled_agility + agility_bonus,
        intellect = final_intellect,
        hero_base_attack_min = state.base.attack_min,
        hero_base_attack_max = state.base.attack_max,
        weapon_base_attack_min = value(definition, "base_attack_min", 0),
        weapon_base_attack_max = value(definition, "base_attack_max", 0),
        weapon_growth_attack = value(growth, "growth_attack", 0),
        is_max_level = value(growth, "is_max_level", 0),
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
        engine_research_attack_bonus = engine_research_attack_bonus,
        engine_weapon_attack_bonus = engine_weapon_attack_bonus,
        native_base_attack_min = native_attack.minimum,
        native_base_attack_max = native_attack.maximum,
        native_attack_min = native_attack.minimum + native_attack.weapon
            + native_attack.research + native_attack.equipment,
        native_attack_max = native_attack.maximum + native_attack.weapon
            + native_attack.research + native_attack.equipment,
        native_weapon_attack_bonus = native_attack.weapon,
        native_research_attack_bonus = native_attack.research,
        native_equipment_attack_bonus = native_attack.equipment,
        native_attack_scale = native_attack.scale,
        equipment_attack_speed_pct = equipment_stats.attack_speed_pct,
        equipment_health = equipment_stats.health_flat,
        equipment_armor = equipment_stats.armor_flat,
        equipment_all_attributes = equipment_stats.all_attributes_flat,
        equipment_lifesteal_pct = equipment_stats.lifesteal_pct,
        reason = reason or "changed",
        refresh_version = tonumber(state.refresh_version) or 0,
    }
    -- Display fixed sources separately. Gameplay totals and projection stay unchanged.
    local display = require("combat/hero_display_bonus").calculate({
        base=state.base, technology=require("combat/hero_display_bonus").static_technology(technology_snapshot),
        permanent=permanent_result and permanent_result.display_totals or {},
        equipment=equipment_stats, weapon=definition, progression=progression, essence=essence,
        level=next_snapshot.level, base_armor=configured_base_armor,
        intellect_attack_per_point=global_rules.hero_intellect_attack_per_point,
        configured_attack_time=hero_combat_stat_math.configured_base_attack_time(
            state.definition,state.engine_base_attack_time), final_attack_time=base_attack_time,
        fixed_exclusive_multiplier=monkey_e and math.max(1,tonumber(monkey_config.e_attack_multiplier) or 1)
            or (blademaster_r and math.max(1,tonumber(blademaster_config.r_attack_multiplier) or 1) or 1),
        debug_attack=debug_attack, debug_attack_speed=debug_attack_speed,
    })
    for key, amount in pairs(display) do next_snapshot[key]=amount end
    local changed = not snapshot_equal(state.snapshot, next_snapshot)
    if changed then
        state.refresh_version = (tonumber(state.refresh_version) or 0) + 1
    end
    next_snapshot.refresh_version = tonumber(state.refresh_version) or 0
    state.snapshot = next_snapshot
    state.unit.survival_attack_speed = next_snapshot.attack_speed
    -- Modifier ForceRefresh below can request this snapshot recursively.
    state.fixed_attack_interval = runtime_attack_interval
    state.exclusive_attack_multiplier = exclusive_attack_multiplier
    state.attribute_attack_bonus = attribute_attack_bonus
    local native_changed = apply_base_projection(state) or health_changed
    if previous_attack_scale ~= native_attack.scale then
        local equipment_modifier = state.unit:FindModifierByName("modifier_equipment_effects")
        if equipment_modifier and equipment_modifier.ForceRefresh then
            equipment_modifier:ForceRefresh()
            native_changed = true
        end
    end
    local bat_changed = set_native_value(state, "base_attack_time", "SetBaseAttackTime",
        base_attack_time)
    native_changed = native_changed or bat_changed
    state.unit.survival_seven_sins_final_damage_pct =
        tonumber(essence.final_damage_pct) or 0
    state.unit.survival_gameplay_final_damage_pct =
        (tonumber(permanent.hero_final_damage_bonus_pct) or 0)
        + (tonumber(permanent.global_final_damage_bonus_pct) or 0)
    state.unit.survival_gameplay_damage_bonus_flat =
        tonumber(permanent.hero_damage_bonus_flat) or 0
    state.unit.survival_gameplay_damage_reduction_pct = math.max(0,
        math.min(100, tonumber(permanent.hero_damage_reduction_pct) or 0))
    local attack_range = value(state.definition, "attack_range", 0)
        + (tonumber(permanent.hero_attack_range) or 0)
    if attack_range > 0 then
        set_native_value(state, "attack_range", "Script_SetAttackRange", attack_range)
        set_native_value(state, "acquisition_range", "SetAcquisitionRange", attack_range + 200)
        state.unit.survival_attack_range = attack_range
        local range_modifier = state.unit:FindModifierByName(
            "modifier_survival_hero_attack_range"
        )
        if range_modifier and range_modifier.SetAttackRange
            and (state.range_modifier ~= range_modifier or state.range_value ~= attack_range) then
            range_modifier:SetAttackRange(attack_range)
            state.range_modifier, state.range_value = range_modifier, attack_range
        end
    end
    local research_modifier = modifier_registry.ensure(
        state.unit, "modifier_research_technology", {}
    )
    local technology_values = {
        attack_pct = researcher_attack_pct, final_damage_pct = researcher_final_damage_pct,
        armor_reduction = researcher_armor_reduction, critical_chance_pct = researcher_critical_chance_pct,
        armor_bonus = gameplay_armor_bonus,
    }
    if research_modifier and research_modifier.SetTechnologyValues
        and (state.research_modifier ~= research_modifier
            or not snapshot_equal(state.technology_values, technology_values)) then
        research_modifier:SetTechnologyValues(
            researcher_attack_pct,
            researcher_final_damage_pct,
            researcher_armor_reduction,
            researcher_critical_chance_pct,
            gameplay_armor_bonus
        )
        state.research_modifier, state.technology_values = research_modifier, technology_values
        native_changed = true
    end
    local modifier = modifier_registry.ensure(
        state.unit, "modifier_weapon_stat_projection", {player_id = player_id}
    )
    -- Only these fields are consumed by the native attack modifier. Counters,
    -- UI metadata and unchanged growth events do not require ForceRefresh.
    local modifier_values = {
        base_attack_time = base_attack_time,
        hero_attack_speed_bonus_pct = researcher_attack_speed_pct,
        engine_weapon_attack_bonus = engine_weapon_attack_bonus,
        engine_research_attack_bonus = engine_research_attack_bonus,
        native_weapon_attack_bonus = native_attack.weapon,
        native_research_attack_bonus = native_attack.research,
        critical_chance_pct = next_snapshot.critical_chance_pct,
        critical_damage_pct = next_snapshot.critical_damage_pct,
    }
    local projection_refresh_required = state.attack_modifier ~= modifier
        or not snapshot_equal(state.modifier_values, modifier_values)
    if projection_refresh_required and modifier and modifier.ForceRefresh then
        modifier:ForceRefresh()
        state.attack_modifier, state.modifier_values = modifier, modifier_values
        native_changed = true
    end
    if changed then
        event_bus.emit(events.HERO_COMBAT_STATS_CHANGED, {
            player_id = player_id,
            snapshot = state.snapshot,
        })
    end
    if native_changed and current_health and current_health > 0
        and current_max_health and current_max_health > 0
        and state.unit:IsAlive() then
        local final_max_health = safe_get(
            state.unit, "GetMaxHealth", current_max_health
        )
        local expected_health = hero_health_guard.current_after_maximum_change(
            current_health,
            current_max_health,
            final_max_health
        )
        local actual_health = safe_get(state.unit, "GetHealth", 0)
        -- The health modifier projection normally applies this value during
        -- the refresh. If a native stat recalculation temporarily retained the
        -- old current health, restore the intended increase before scheduling
        -- the guard that protects against a later engine refill.
        if final_max_health > current_max_health
            and actual_health < expected_health then
            safe_call(state.unit, "SetHealth", expected_health)
        end
        hero_health_guard.protect_value(
            state.unit,
            expected_health,
            "combat_recalculate:" .. tostring(reason or "changed")
        )
    end
    return state.snapshot
end

flush_recalculation = function(player_id, expected)
    local pending = pending_recalculations[player_id]
    if not pending or (expected and pending ~= expected) then return end
    pending_recalculations[player_id] = nil
    if pending.generation ~= event_bus.get_generation()
        or current(player_id) ~= pending.state then return end
    return recalculate(player_id, pending.reason, pending.growth_snapshot)
end

local function queue_recalculation(player_id, reason, growth_snapshot)
    if player_id == nil then return end
    local state = current(player_id)
    if not state or not state.unit or state.unit:IsNull() then return end
    local pending = pending_recalculations[player_id]
    local generation = event_bus.get_generation()
    if not pending or pending.state ~= state or pending.generation ~= generation then
        pending = {state = state, generation = generation}
        pending_recalculations[player_id] = pending
    end
    pending.reason = reason
    if growth_snapshot then pending.growth_snapshot = growth_snapshot end
    event_bus.after_dispatch("hero_combat_recalculate:" .. tostring(player_id), function()
        flush_recalculation(player_id, pending)
    end)
end

local function on_hero_summoned(payload)
    pending_recalculations[tonumber(payload.player_id)] = nil
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
        refresh_version = 0,
        snapshot = nil,
    }
    state_by_player[payload.player_id] = state
    apply_base_projection(state)
    local configured_health, configured_bonus, native_health =
        hero_stat_adapter.apply_configured_health(payload.unit, definition)
    print(string.format(
        "[HERO_CONFIGURED_HEALTH] hero=%s entindex=%s configured=%s "
            .. "native=%s bonus=%s engine_max=%s engine_current=%s",
        tostring(payload.hero_id), tostring(payload.unit:entindex()),
        tostring(configured_health), tostring(native_health),
        tostring(configured_bonus),
        tostring(safe_get(payload.unit, "GetMaxHealth", 0)),
        tostring(safe_get(payload.unit, "GetHealth", 0))
    ))
    local function ensure_modifier(name)
        local existing = payload.unit:FindModifierByName(name)
        if existing then return existing end
        local created = modifier_registry.ensure(
            payload.unit, name, { player_id = payload.player_id }
        )
        print(string.format(
            "[SURVIVAL_MODIFIER_CREATE] name=%s entindex=%s created=%s",
            name, tostring(payload.unit:entindex()), tostring(created ~= nil)
        ))
        return created
    end
    ensure_modifier("modifier_weapon_stat_projection")
    hero_health_guard.preserve_missing(payload.unit, function()
        ensure_modifier("modifier_equipment_effects")
        safe_call(payload.unit, "CalculateStatBonus", true)
        hero_stat_adapter.reapply_projectile_stats(payload.unit, definition)
    end, "hero_summoned_equipment_health")
    ensure_modifier("modifier_weapon_attack_tracker")
    local snapshot = recalculate(payload.player_id, "hero_summoned") or {}
    print(string.format(
        "[HeroCombatReady] hero=%s entindex=%s base_damage=%.1f-%.1f "
            .. "engine_damage=%.1f-%.1f attack_range=%.1f "
            .. "attack_capability=%s projectile_speed=%s move_capability=%s",
        tostring(payload.hero_id),
        tostring(payload.unit:entindex()),
        tonumber(state.base.attack_min) or 0,
        tonumber(state.base.attack_max) or 0,
        safe_get(payload.unit, "GetBaseDamageMin", 0),
        safe_get(payload.unit, "GetBaseDamageMax", 0),
        safe_get(payload.unit, "GetAttackRange", 0),
        tostring(safe_get(payload.unit, "GetAttackCapability", -1)),
        tostring(safe_get(payload.unit, "GetProjectileSpeed", 0)),
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
            hero_stat_adapter.reapply_projectile_stats(state.unit, state.definition)
        end, "equipment_refresh:" .. tostring(payload.reason or "changed"))
    end
    recalculate(player_id, payload.reason)
end

local function on_progression_changed(payload)
    if payload.changed_section and payload.changed_section ~= "hero" then return end
    -- Progression attributes are logical data only. They do not change native
    -- attributes or equipment health, so only the combat snapshot is rebuilt.
    queue_recalculation(tonumber(payload.player_id), payload.reason)
end

local function debug_set_attack(payload)
    payload = payload or {}
    local player_id = tonumber(payload.player_id)
    local state = current(player_id)
    if not state or not state.unit or state.unit:IsNull() then
        return { ok = false, error = "hero_not_summoned" }
    end
    flush_recalculation(player_id)
    if payload.reset == true then
        state.debug_attack_override = nil
    else
        local has_delta = payload.attack_delta ~= nil
        local has_attack = payload.attack ~= nil or has_delta
        local has_attack_speed = payload.attack_speed ~= nil
        if not has_attack and not has_attack_speed then
            return { ok = false, error = "debug_combat_stats_missing" }
        end
        local attack = nil
        local attack_speed = nil
        if has_attack then
            attack = tonumber(payload.attack)
            if has_delta then
                local delta = tonumber(payload.attack_delta)
                if payload.attack ~= nil or not delta or delta ~= delta
                    or delta == math.huge or delta == -math.huge then
                    return { ok = false, error = "debug_attack_invalid" }
                end
                local snapshot = state.snapshot or recalculate(player_id, "debug_attack_read")
                attack = (tonumber(state.debug_attack_override)
                    or tonumber(snapshot and snapshot.attack_min) or 0) + delta
            end
            if not attack or attack ~= attack or attack < 0 or attack > 9000000000000000 then
                return { ok = false, error = "debug_attack_invalid" }
            end
        end
        if has_attack_speed then
            attack_speed = tonumber(payload.attack_speed)
            if not attack_speed or not endless_projection.is_finite(attack_speed)
                or attack_speed <= 0 or attack_speed > 100 then
                return { ok = false, error = "debug_attack_speed_invalid" }
            end
        end
        if has_attack then
            state.debug_attack_override = attack
            -- The debug projection now owns the final attack value. Remove
            -- legacy addattack bonuses so they cannot apply a second time.
            if state.unit.RemoveModifierByName then
                state.unit:RemoveModifierByName("modifier_debug_attack_bonus")
            end
        end
        if has_attack_speed then
            state.debug_attack_speed_override = attack_speed
        end
    end
    local snapshot = recalculate(player_id, payload.reset == true
        and "debug_attack_reset" or "debug_attack_override")
    return { ok = true, snapshot = snapshot }
end

local function get_stats(payload)
    local player_id = tonumber(payload.player_id)
    local state = current(player_id)
    if not state or not state.unit or state.unit:IsNull() then
        return { ok = false, error = "hero_not_summoned" }
    end
    if payload.entindex ~= nil
        and tonumber(payload.entindex) ~= state.unit:entindex() then
        return { ok = false, error = "hero_entity_mismatch" }
    end
    -- Attack procs can query attributes before the outer attack dispatch ends.
    -- Commit this player's growth before returning any combat snapshot.
    flush_recalculation(player_id)
    if state.snapshot
        and state.fixed_attack_interval ~= fixed_attack_interval(state.unit) then
        recalculate(player_id, "fixed_attack_rate_changed")
    elseif state.snapshot and state.snapshot.level ~= safe_get(state.unit, "GetLevel", 1) then
        recalculate(player_id, "hero_level_changed")
    end
    return {
        ok = true,
        snapshot = state.snapshot or recalculate(player_id, "request"),
    }
end

local function on_technology_stats_changed(payload)
    if payload and payload.changed_section == "lumberjack" then return end
    local player_id = tonumber(payload and payload.player_id)
    if player_id == nil then return end
    recalculate(player_id, "technology_stats_changed")
end

local function on_hero_removed(payload)
    local player_id = tonumber(payload and payload.player_id)
    local state = player_id and state_by_player[player_id]
    if not state or state.unit ~= payload.unit then return end
    pending_recalculations[player_id] = nil
    state_by_player[player_id] = nil
    event_bus.emit(events.HERO_COMBAT_STATS_CHANGED, {
        player_id = player_id,
        reason = "hero_removed",
        snapshot = { player_id = player_id, entindex = -1, hero_ready = 0,
            attack_min = 0, attack_max = 0, attack_speed = 0,
            strength = 0, agility = 0, intellect = 0,
            health = 0, max_health = 0, runtime_armor = 0 },
    })
end

local function on_growth_changed(payload)
    -- Attack growth changes combat numbers, not equipment or projectile setup.
    -- Use the committed snapshot rather than copying the inventory again.
    queue_recalculation(tonumber(payload.player_id), payload.reason, payload.snapshot)
end

function M.init()
    state_by_player = {}
    pending_recalculations = {}
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
    event_bus.subscribe(events.HERO_REMOVED, on_hero_removed)
    event_bus.subscribe(events.WEAPON_EQUIPPED_CHANGED, on_changed)
    event_bus.subscribe(events.WEAPON_GROWTH_CHANGED, on_growth_changed)
    -- CONTENT_INVENTORY_CHANGED subscribers are unordered. Refresh only after
    -- the equipment aggregator has published its completed snapshot; otherwise
    -- this service can read the previous armor value and leave the HUD stale.
    event_bus.subscribe(events.EQUIPMENT_STATS_CHANGED, on_changed)
    event_bus.subscribe(events.TECHNOLOGY_STATS_CHANGED, on_technology_stats_changed)
    event_bus.subscribe(events.SEVEN_SINS_ESSENCE_CHANGED, on_progression_changed)
    event_bus.subscribe(events.HERO_PROGRESSION_CHANGED, on_progression_changed)
    event_bus.subscribe(events.PERMANENT_REWARD_EFFECTS_CHANGED, on_progression_changed)
    event_bus.subscribe(events.HERO_SKILL_CHANGED, on_progression_changed)
    event_bus.subscribe(events.MONKEY_KING_BONUS_STATS_CHANGED, on_progression_changed)
    event_bus.subscribe(events.BLADEMASTER_BONUS_STATS_CHANGED, on_progression_changed)
end

M._test = {
    base_snapshot = base_snapshot,
    configured_damage_multiplier = configured_damage_multiplier,
}

return M
