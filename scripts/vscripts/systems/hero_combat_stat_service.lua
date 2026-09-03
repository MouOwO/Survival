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
local hero_stat_adapter = require("systems/hero_stat_adapter")
local monkey_runtime = require("config/generated/monkey_king_exclusive_runtime")
local blademaster_runtime = require("config/generated/blademaster_exclusive_runtime")
local armor_balance = require("config/armor_balance")

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
        if key ~= "reason" and key ~= "refresh_version"
            and right[key] ~= value then return false end
    end
    for key, value in pairs(right) do
        if key ~= "reason" and key ~= "refresh_version"
            and left[key] ~= value then return false end
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

local function has_skill(player_id, skill_id)
    local result = event_bus.request(
        events.HERO_SKILL_STATE_GET_REQUEST,
        { player_id = player_id }
    )
    for _, skill in ipairs(result and result.snapshot
            and result.snapshot.skills or {}) do
        if skill.skill_id == skill_id and skill.locked ~= 1
            and (tonumber(skill.level) or 0) > 0 then
            return true
        end
    end
    return false
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
        local multiplier = tonumber(state.exclusive_attack_multiplier) or 1
        local attribute_attack_bonus = tonumber(state.attribute_attack_bonus) or 0
        local minimum = math.max(0,
            (state.engine_base_attack_min
                + attribute_attack_bonus * state.damage_multiplier)
                * multiplier)
        local maximum = math.max(minimum,
            (state.engine_base_attack_max
                + attribute_attack_bonus * state.damage_multiplier)
                * multiplier)
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
    local current_max_health = state.unit.IsAlive and state.unit:IsAlive()
        and safe_get(state.unit, "GetMaxHealth", nil) or nil
    local equipment, growth = weapon_snapshot(player_id)
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
    local hero_technology = technology_stat_manager.get(player_id).final.hero or {}
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
    local monkey_w = state.hero_id == "hero_monkey_king"
        and has_skill(player_id, "skill_monkey_king_fury")
    local monkey_e = state.hero_id == "hero_monkey_king"
        and has_skill(player_id, "skill_monkey_king_swiftness")
    local blademaster_q = state.hero_id == "hero_blademaster"
        and has_skill(player_id, "skill_blademaster_exclusive")
    local blademaster_r = state.hero_id == "hero_blademaster"
        and has_skill(player_id, "skill_blademaster_mobility")
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
    local engine_research_attack_bonus = (((state.engine_base_attack_min
        + state.engine_base_attack_max
        + weapon_attack_min + weapon_attack_max)
        * 0.5) * total_attack_pct / 100
        + flat_panel_attack * total_attack_pct / 100
        + researcher_attack_flat
        + progression_attack_flat) * exclusive_attack_multiplier
    local engine_weapon_attack_bonus = (debug_attack
        and (debug_attack
            - ((state.engine_base_attack_min
                + state.engine_base_attack_max) * 0.5)
            - equipment_stats.attack_flat)
        or ((weapon_attack_min + weapon_attack_max) * 0.5))
            * exclusive_attack_multiplier
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
    local attribute_attack_bonus = hero_combat_stat_math.intellect_attack_bonus(
        final_intellect,
        global_rules.hero_intellect_attack_per_point
    )
    hero_health_guard.preserve_missing(state.unit, function()
        hero_stat_adapter.apply_configured_health(
            state.unit,
            state.definition,
            attribute_health_bonus
        )
    end, "attribute_health_refresh")
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
        attack_min = (debug_attack or ((state.base.attack_min + weapon_attack_min
            + attribute_attack_bonus + flat_panel_attack)
            * (1 + total_attack_pct / 100))) * exclusive_attack_multiplier,
        attack_max = (debug_attack or ((state.base.attack_max + weapon_attack_max
            + attribute_attack_bonus + flat_panel_attack)
            * (1 + total_attack_pct / 100))) * exclusive_attack_multiplier,
        health = current_health or safe_get(state.unit, "GetMaxHealth", 1),
        max_health = safe_get(state.unit, "GetMaxHealth", 1),
        attribute_health_bonus = attribute_health_bonus,
        attribute_attack_bonus = attribute_attack_bonus,
        researcher_attack_pct = researcher_attack_pct,
        hero_attack_bonus_pct = tonumber(permanent.hero_attack_bonus_pct) or 0,
        hero_health_bonus_pct = tonumber(permanent.hero_health_bonus_pct) or 0,
        hero_armor_bonus_pct = tonumber(permanent.hero_armor_bonus_pct) or 0,
        researcher_final_damage_pct = researcher_final_damage_pct,
        researcher_armor_reduction = researcher_armor_reduction,
        researcher_critical_chance_pct = researcher_critical_chance_pct,
        critical_chance_pct = researcher_critical_chance_pct
            + monkey_critical_chance_pct
            + (blademaster_q and math.max(0,
                tonumber(blademaster_config.q_critical_chance_pct) or 0) or 0),
        critical_damage_pct = (monkey_w
            and (tonumber(monkey_config.w_critical_damage_pct) or 200) or 200)
            + (blademaster_q and math.max(0,
                tonumber(blademaster_config.q_critical_damage_bonus_pct) or 0) or 0)
            + (tonumber(permanent.hero_critical_damage_bonus_pct) or 0),
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
        hero_damage_multiplier = hero_damage_multiplier,
        engine_attack_min = (state.engine_base_attack_min
            + attribute_attack_bonus * state.damage_multiplier)
                * exclusive_attack_multiplier + engine_bonus_attack,
        engine_attack_max = (state.engine_base_attack_max
            + attribute_attack_bonus * state.damage_multiplier)
                * exclusive_attack_multiplier + engine_bonus_attack,
        debug_attack_override = debug_attack or 0,
        -- The equipment aggregation snapshot already owns the authoritative
        -- War3/CSV armor value. Do not derive the HUD value from this frame's
        -- engine armor: ForceRefresh/CalculateStatBonus may not have exposed the
        -- new modifier value yet, which previously froze a real 850 bonus at 0.
        armor = authoritative_war3_armor,
        armor_unit = "war3_display",
        stat_units_version = 2,
        -- Keep the engine value separately for runtime mitigation diagnostics.
        runtime_armor = safe_get(state.unit, "GetPhysicalArmorValue", 0),
        -- 配置值使用“每秒攻击次数”。由配置 BAT、固定间隔变化和装备
        -- 攻速百分比直接投影，避免读取引擎当前帧临时攻击间隔。
        attack_speed = hero_combat_stat_math.attacks_per_second(
            base_attack_time,
            equipment_stats.attack_speed_pct + researcher_attack_speed_pct
        ),
        attack_speed_stat = safe_get(state.unit, "GetAttackSpeed", 100),
        strength = final_strength,
        agility = unscaled_agility + agility_bonus,
        intellect = final_intellect,
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
        engine_research_attack_bonus = engine_research_attack_bonus,
        engine_weapon_attack_bonus = engine_weapon_attack_bonus,
        equipment_attack_speed_pct = equipment_stats.attack_speed_pct,
        equipment_health = equipment_stats.health_flat,
        equipment_armor = equipment_stats.armor_flat,
        equipment_all_attributes = equipment_stats.all_attributes_flat,
        equipment_lifesteal_pct = equipment_stats.lifesteal_pct,
        reason = reason or "changed",
        refresh_version = tonumber(state.refresh_version) or 0,
    }
    local changed = not snapshot_equal(state.snapshot, next_snapshot)
    if changed then
        state.refresh_version = (tonumber(state.refresh_version) or 0) + 1
    end
    next_snapshot.refresh_version = tonumber(state.refresh_version) or 0
    state.snapshot = next_snapshot
    state.exclusive_attack_multiplier = exclusive_attack_multiplier
    state.attribute_attack_bonus = attribute_attack_bonus
    apply_base_projection(state)
    safe_call(state.unit, "SetBaseAttackTime", base_attack_time
        / math.max(0.01, 1 + researcher_attack_speed_pct / 100))
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
        safe_call(state.unit, "Script_SetAttackRange", attack_range)
        safe_call(state.unit, "SetAcquisitionRange", attack_range + 200)
        state.unit.survival_attack_range = attack_range
        local range_modifier = state.unit:FindModifierByName(
            "modifier_survival_hero_attack_range"
        )
        if range_modifier and range_modifier.SetAttackRange then
            range_modifier:SetAttackRange(attack_range)
        end
    end
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
            researcher_critical_chance_pct,
            gameplay_armor_bonus
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
    hero_health_guard.preserve_missing(payload.unit, function()
        ensure_modifier("modifier_equipment_effects")
        safe_call(payload.unit, "CalculateStatBonus", true)
    end, "hero_summoned_equipment_health")
    hero_stat_adapter.reapply_projectile_stats(payload.unit, definition)
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
        end, "equipment_refresh:" .. tostring(payload.reason or "changed"))
        hero_stat_adapter.reapply_projectile_stats(state.unit, state.definition)
    end
    recalculate(player_id, payload.reason)
end

local function on_progression_changed(payload)
    -- Progression attributes are logical data only. They do not change native
    -- attributes or equipment health, so only the combat snapshot is rebuilt.
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
