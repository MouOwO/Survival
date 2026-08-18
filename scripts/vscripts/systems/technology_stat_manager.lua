local event_bus = require("core/event_bus")
local events = require("core/events")
local definitions = require("config/generated/technology_definitions")
local research_events = require("research/research_event_names")

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
            critical_chance_pct = 0,
            armor_reduction_per_attack = 0,
            attack_speed_bonus_pct = 0,
            attack_interval_flat = 0,
            all_attributes_flat = 0,
        },
        gold_mine = { income_bonus_pct = 0 },
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
        runtime = {
            training_room_active = false,
            training_room_action_id = "",
            training_room_income_multiplier = 1,
        },
        challenge = fresh_values(),
        rogue = fresh_values(),
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
        values.tower.attack_bonus_pct =
            values.tower.attack_bonus_pct + value
        values.hero.critical_chance_pct =
            values.hero.critical_chance_pct + value
        values.hero.attack_bonus_pct =
            values.hero.attack_bonus_pct + value
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
        challenge = copy_values(state.challenge or fresh_values()),
        rogue = copy_values(state.rogue or fresh_values()),
        final = copy_values(state.technology),
        runtime = {
            training_room_active = state.runtime.training_room_active == true,
            training_room_action_id = state.runtime.training_room_action_id or "",
            training_room_income_multiplier =
                number(state.runtime.training_room_income_multiplier, 1),
        },
    }
    for section, fields in pairs(state.challenge or fresh_values()) do
        result.challenge[section] = result.challenge[section] or {}
        result.final[section] = result.final[section] or {}
        for field, value in pairs(fields) do
            result.final[section][field] = number(result.final[section][field])
                + number(value)
        end
    end
    for section, fields in pairs(state.rogue or fresh_values()) do
        result.rogue[section] = result.rogue[section] or {}
        result.final[section] = result.final[section] or {}
        for field, value in pairs(fields) do
            result.final[section][field] = number(result.final[section][field])
                + number(value)
        end
    end
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
        research_events.EFFECTS_GET_REQUESTED,
        { player_id = player_id }
    )
    local state = fresh_state()
    if response and response.snapshot then
        state.levels = response.snapshot.levels or {}
        state.technology = response.snapshot.legacy or fresh_values()
    end
    state_by_player[player_id] = state
    return state
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
    -- Generated technology purchases already carry the authoritative levels
    -- from shop_system. Do not replace them with the separate legacy research
    -- repository: cheat_addtechnology and non-legacy shop grants do not write
    -- that repository, so querying it here would rebuild every generated
    -- technology effect as zero.
    if type(payload.levels) == "table" then
        rebuild(player_id, payload.levels)
        publish(player_id, payload.reason or "technology_changed")
        return
    end
    local response = event_bus.request(
        research_events.EFFECTS_GET_REQUESTED,
        { player_id = player_id }
    )
    local state = state_by_player[player_id] or fresh_state()
    if response and response.snapshot then
        state.levels = response.snapshot.levels or {}
        state.technology = response.snapshot.legacy or fresh_values()
        state.snapshot = nil
        state_by_player[player_id] = state
    end
    publish(player_id, payload.reason or "technology_changed")
end

local function on_research_effects_changed(payload)
    local player_id = tonumber(payload and payload.player_id)
    local projection = payload and payload.snapshot
    if player_id == nil or not projection then return end
    local state = state_by_player[player_id] or fresh_state()
    state.levels = projection.levels or {}
    state.technology = projection.legacy or fresh_values()
    state.snapshot = nil
    state_by_player[player_id] = state
    publish(player_id, "research_effects_changed")
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

local CHALLENGE_EFFECT_FIELDS = {
    challenge_wall_armor_flat = { "wall", "technology_armor_bonus", 1 / 3 },
    challenge_wall_health_pct = { "wall", "health_bonus_pct", 1 },
    challenge_tower_attack_flat = { "tower", "attack_flat", 1 },
    challenge_tower_attack_pct = { "tower", "attack_bonus_pct", 1 },
    challenge_lumber_efficiency_flat = { "lumberjack", "wood_per_hit_bonus", 1 },
    challenge_gold_mine_income_pct = { "gold_mine", "income_bonus_pct", 1 },
}

local ROGUE_EFFECT_FIELDS = {
    wall_armor_flat = { "wall", "technology_armor_bonus", 1 / 3 },
    tower_attack_speed_bonus_pct = { "tower", "attack_speed_bonus_pct", 1 },
    tower_attack_flat = { "tower", "attack_flat", 1 },
    tower_attack_range_flat = { "tower", "attack_range_bonus", 1 },
    lumberjack_attack_speed_pct = { "lumberjack", "attack_speed_bonus_pct", 1 },
    lumberjack_wood_per_hit = { "lumberjack", "wood_per_hit_bonus", 1 },
    hero_attack_speed_pct = { "hero", "attack_speed_bonus_pct", 1 },
    hero_attack_interval_flat = { "hero", "attack_interval_flat", 1 },
    hero_all_attributes_flat = { "hero", "all_attributes_flat", 1 },
    gold_mine_income_pct = { "gold_mine", "income_bonus_pct", 1 },
}

local function add_rogue_effects(payload)
    local player_id = tonumber(payload and payload.player_id)
    if player_id == nil or player_id < 0 then
        return { ok = false, error = "player_id_invalid" }
    end
    local state = ensure_state(player_id)
    state.rogue = state.rogue or fresh_values()
    local additions = {}
    for _, effect in ipairs(payload.effects or {}) do
        local field = ROGUE_EFFECT_FIELDS[effect.effect_type]
        if not field then return { ok = false, error = "rogue_effect_invalid" } end
        additions[#additions + 1] = {
            section = field[1], field = field[2],
            amount = number(effect.value) * field[3],
        }
    end
    for _, addition in ipairs(additions) do
        local section = addition.section
        state.rogue[section] = state.rogue[section] or {}
        state.rogue[section][addition.field] =
            number(state.rogue[section][addition.field]) + addition.amount
    end
    state.snapshot = nil
    publish(player_id, payload.reason or "rogue_reward")
    return { ok = true, snapshot = snapshot(state) }
end

local function add_challenge_effects(payload)
    local player_id = tonumber(payload and payload.player_id)
    if player_id == nil or player_id < 0 then
        return { ok = false, error = "player_id_invalid" }
    end
    local state = ensure_state(player_id)
    state.challenge = state.challenge or fresh_values()
    state.challenge.gold_mine = state.challenge.gold_mine or { income_bonus_pct = 0 }
    local additions = {}
    for _, effect in ipairs(payload.effects or {}) do
        local field = CHALLENGE_EFFECT_FIELDS[effect.effect_type]
        if not field then
            return { ok = false, error = "challenge_effect_invalid" }
        end
        additions[#additions + 1] = {
            section = field[1],
            field = field[2],
            amount = number(effect.value) * field[3],
        }
    end
    for _, addition in ipairs(additions) do
        local section = addition.section
        local field = addition.field
        state.challenge[section] = state.challenge[section] or {}
        state.challenge[section][field] = number(state.challenge[section][field])
            + addition.amount
    end
    state.snapshot = nil
    publish(player_id, payload.reason or "building_challenge_reward")
    return { ok = true, snapshot = snapshot(state) }
end

function M.get(player_id)
    return snapshot(ensure_state(player_id))
end

function M.set_training_room_state(player_id, active, multiplier, action_id, reason)
    player_id = tonumber(player_id)
    if player_id == nil then return { ok = false, error = "player_id_invalid" } end
    local state = ensure_state(player_id)
    state.runtime = state.runtime or {}
    state.runtime.training_room_active = active == true
    state.runtime.training_room_action_id = active == true
        and tostring(action_id or "") or ""
    state.runtime.training_room_income_multiplier = active == true
        and math.max(1, number(multiplier, 1)) or 1
    state.snapshot = nil
    publish(player_id, reason or "training_room_state_changed")
    event_bus.emit(events.TRAINING_ROOM_STATE_CHANGED, {
        player_id = player_id,
        active = state.runtime.training_room_active,
        action_id = state.runtime.training_room_action_id,
        income_multiplier = state.runtime.training_room_income_multiplier,
        reason = reason or "training_room_state_changed",
    })
    return { ok = true, snapshot = snapshot(state) }
end

function M.training_room_multiplier(player_id, target)
    local runtime = snapshot(ensure_state(player_id)).runtime or {}
    if runtime.training_room_active ~= true then return 1 end
    if not target or target:IsNull()
        or tonumber(target.survival_training_owner_player_id) ~= tonumber(player_id) then
        return 1
    end
    return math.max(1, number(runtime.training_room_income_multiplier, 1))
end

function M.init()
    state_by_player = {}
    event_bus.handle_request(events.TECHNOLOGY_STATS_GET_REQUEST, get_stats)
    event_bus.handle_request(events.TECHNOLOGY_STATS_GROWTH_ADD_REQUEST, add_growth)
    event_bus.handle_request(
        events.TECHNOLOGY_STATS_CHALLENGE_ADD_REQUEST,
        add_challenge_effects
    )
    event_bus.handle_request(events.TECHNOLOGY_STATS_ROGUE_ADD_REQUEST, add_rogue_effects)
    event_bus.subscribe(events.TECHNOLOGY_CHANGED, on_technology_changed)
    event_bus.subscribe(research_events.EFFECTS_CHANGED, on_research_effects_changed)
end

return M