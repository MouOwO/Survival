local event_bus = require("core/event_bus")
local events = require("core/events")
local definitions = require("config/generated/technology_definitions")

local M = {}
local state_by_player = {}
local ACCUMULATED_GROUPS = {
    advanced_lumberjack_speed = true,
}

local function number(value, fallback)
    local result = tonumber(value)
    return result ~= nil and result or (fallback or 0)
end

local function fresh_values()
    return {
        wall = {
            health_bonus_pct = 0,
            technology_health_bonus_pct = 0,
            technology_armor_bonus = 0,
        },
        tower = {
            critical_chance_pct = 0,
            attack_flat = 0,
            attack_bonus_pct = 0,
            critical_damage_multiplier = 2,
            attack_speed_bonus_pct = 0,
            attacks_per_second_bonus = 0,
            attack_range_bonus = 0,
        },
        lumberjack = {
            attack_flat = 0,
            attack_gain_per_attack = 0,
            wood_per_hit_bonus = 0,
            attack_speed_bonus_pct = 0,
            attack_interval_flat = 0,
            critical_chance_pct = 0,
            armor_reduction_per_attack = 0,
        },
        hero = {
            attack_gain_per_second = 0,
            attributes_gain_per_second = 0,
            attack_flat = 0,
            damage_multiplier_bonus = 0,
            final_damage_bonus_pct = 0,
            attack_bonus_pct = 0,
            armor_reduction_per_attack = 0,
        },
    }
end

local function fresh_growth()
    return {
        lumberjack = {
            attack = 0,
            wood_per_hit = 0,
        },
        hero = {
            attack = 0,
            attributes = 0,
        },
    }
end

local function fresh_state()
    return {
        levels = {},
        technology = fresh_values(),
        growth = fresh_growth(),
        snapshot = nil,
    }
end

local function add_effect(values, effect_type, effect_value)
    local value = number(effect_value)
    if effect_type == "wall_health_pct" then
        values.wall.health_bonus_pct = values.wall.health_bonus_pct + value
    elseif effect_type == "wall_health_pct_advanced"
        or effect_type == "super_wall_health_pct" then
        values.wall.technology_health_bonus_pct =
            values.wall.technology_health_bonus_pct + value
    elseif effect_type == "super_wall_armor_flat" then
        values.wall.technology_armor_bonus =
            values.wall.technology_armor_bonus + value
    elseif effect_type == "super_tower_crit_pct" then
        values.tower.critical_chance_pct =
            values.tower.critical_chance_pct + value
    elseif effect_type == "tower_attack_flat"
        or effect_type == "tower_attack_flat_advanced"
        or effect_type == "super_tower_attack_flat" then
        values.tower.attack_flat = values.tower.attack_flat + value
    elseif effect_type == "super_tower_attack_range" then
        values.tower.attack_range_bonus = values.tower.attack_range_bonus + value
    elseif effect_type == "lumberjack_attack_growth" then
        values.lumberjack.attack_gain_per_attack =
            values.lumberjack.attack_gain_per_attack + value
    elseif effect_type == "lumberjack_attack_speed_pct" then
        values.lumberjack.attack_speed_bonus_pct =
            values.lumberjack.attack_speed_bonus_pct + value
    elseif effect_type == "lumberjack_attack_interval_flat" then
        values.lumberjack.attack_interval_flat =
            values.lumberjack.attack_interval_flat + value
    elseif effect_type == "lumberjack_wood_per_hit"
        or effect_type == "lumberjack_wood_per_hit_advanced" then
        values.lumberjack.wood_per_hit_bonus =
            values.lumberjack.wood_per_hit_bonus + value
    elseif effect_type == "lumberjack_critical_chance_pct" then
        values.lumberjack.critical_chance_pct =
            values.lumberjack.critical_chance_pct + value
    elseif effect_type == "lumberjack_attack_armor_reduction" then
        values.lumberjack.armor_reduction_per_attack =
            values.lumberjack.armor_reduction_per_attack + value
    elseif effect_type == "hero_final_damage_pct" then
        values.hero.final_damage_bonus_pct =
            values.hero.final_damage_bonus_pct + value
    elseif effect_type == "hero_attack_flat" then
        values.hero.attack_flat = values.hero.attack_flat + value
    elseif effect_type == "hero_attack_armor_reduction" then
        values.hero.armor_reduction_per_attack =
            values.hero.armor_reduction_per_attack + value
    end
end

local function rebuild(player_id, levels)
    local state = state_by_player[player_id] or fresh_state()
    state.levels = levels or state.levels or {}
    state.technology = fresh_values()
    local rows_by_group = {}
    for _, row in ipairs(definitions.rows or {}) do
        local group = tostring(row.technology_group or "")
        local level = number(row.level)
        if row.enabled ~= false and group ~= "" and level > 0 then
            rows_by_group[group] = rows_by_group[group] or {}
            rows_by_group[group][level] = row
        end
    end
    for group, purchased_level in pairs(state.levels) do
        local level = number(purchased_level)
        local rows = rows_by_group[group] or {}
        if ACCUMULATED_GROUPS[group] then
            for current = 1, level do
                local row = rows[current]
                if row then add_effect(state.technology, row.effect_type, row.effect_value) end
            end
        else
            local row = rows[level]
            if row then add_effect(state.technology, row.effect_type, row.effect_value) end
        end
    end
    state.snapshot = nil
    state_by_player[player_id] = state
    return state
end

local function copy_values(source)
    local result = {}
    for section, fields in pairs(source or {}) do
        result[section] = {}
        for key, value in pairs(fields) do result[section][key] = value end
    end
    return result
end

local function snapshot(state)
    if state.snapshot then return state.snapshot end
    local result = {
        levels = {},
        technology = copy_values(state.technology),
        growth = copy_values(state.growth),
        final = copy_values(state.technology),
    }
    for group, level in pairs(state.levels or {}) do
        result.levels[group] = level
    end
    result.final.lumberjack.attack_flat = result.final.lumberjack.attack_flat
        + number(state.growth.lumberjack.attack)
    result.final.lumberjack.wood_per_hit_bonus =
        result.final.lumberjack.wood_per_hit_bonus
        + number(state.growth.lumberjack.wood_per_hit)
    result.final.hero.attack_flat = result.final.hero.attack_flat
        + number(state.growth.hero.attack)
    result.final.hero.attributes_gain_per_second =
        result.final.hero.attributes_gain_per_second
        + number(state.growth.hero.attributes)
    state.snapshot = result
    return result
end

local function ensure_state(player_id)
    player_id = tonumber(player_id)
    if player_id == nil then return fresh_state() end
    if state_by_player[player_id] then return state_by_player[player_id] end
    local response = event_bus.request(
        events.TECHNOLOGY_STATE_GET_REQUEST,
        { player_id = player_id }
    )
    return rebuild(player_id, response and response.levels or {})
end

local function publish(player_id, reason)
    local state = ensure_state(player_id)
    event_bus.emit(events.TECHNOLOGY_STATS_CHANGED, {
        player_id = player_id,
        snapshot = snapshot(state),
        reason = reason or "technology_changed",
    })
end

local function on_technology_changed(payload)
    local player_id = tonumber(payload and payload.player_id)
    if player_id == nil then return end
    rebuild(player_id, payload.levels or {})
    publish(player_id, payload.reason or "technology_changed")
end

local function get_stats(payload)
    local player_id = tonumber(payload and payload.player_id)
    if player_id == nil then return { ok = false, error = "player_id_invalid" } end
    return { ok = true, snapshot = snapshot(ensure_state(player_id)) }
end

local function add_growth(payload)
    local player_id = tonumber(payload and payload.player_id)
    if player_id == nil then
        return { ok = false, error = "player_id_invalid" }
    end
    local section = tostring(payload and payload.section or "")
    local field = tostring(payload and payload.field or "")
    local amount = number(payload and payload.amount)
    local state = ensure_state(player_id)
    if not state.growth[section] or state.growth[section][field] == nil then
        return { ok = false, error = "growth_field_invalid" }
    end
    state.growth[section][field] = state.growth[section][field] + amount
    state.snapshot = nil
    publish(player_id, payload.reason or "runtime_growth")
    return { ok = true, snapshot = snapshot(state) }
end

function M.get(player_id)
    return snapshot(ensure_state(player_id))
end

function M.init()
    state_by_player = {}
    event_bus.handle_request(events.TECHNOLOGY_STATS_GET_REQUEST, get_stats)
    event_bus.handle_request(events.TECHNOLOGY_STATS_GROWTH_ADD_REQUEST, add_growth)
    event_bus.subscribe(events.TECHNOLOGY_CHANGED, on_technology_changed)
end

return M