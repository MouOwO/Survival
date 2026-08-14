local event_bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")
local definitions = require("config/generated/building_challenge_definitions")
local wave_rows = require("config/generated/building_challenge_waves")
local wave_system = require("systems/wave_system")

local M = {}
local TASK_ID = "building_challenge_auto_summon"
local states = {}
local monster_meta = {}
local alive_by_team = {}
local challenge_count_by_team = {}
local ordered_definitions = {}
local waves_by_key = {}

local function valid(entity)
    return entity and not entity:IsNull()
end

local function notify(state, message, level)
    if not state or state.player_id < 0 then return end
    event_bus.emit(events.UI_NOTIFICATION, {
        player_id = state.player_id,
        message = message,
        level = level or "error",
    })
end

local function key(challenge_id, wave_number)
    return tostring(challenge_id) .. ":" .. tostring(wave_number)
end

local function challenge_count(state, challenge_id)
    challenge_count_by_team[state.team] = challenge_count_by_team[state.team] or {}
    return tonumber(challenge_count_by_team[state.team][challenge_id]) or 0
end

local function main_city_level(state)
    local result = event_bus.request(events.BUILDING_LIST_REQUEST, {
        player_id = state.player_id,
    })
    local level = 0
    for _, building in ipairs(result and result.buildings or result or {}) do
        if building.building_id == "main_city" then
            level = math.max(level, tonumber(building.level) or 0)
        end
    end
    return level
end

local function state_for(payload)
    local entindex = tonumber(payload and payload.building_entindex)
    local state = entindex and states[entindex] or nil
    if not state or not valid(state.building)
        or state.building.survival_building_id ~= "building_challenge" then
        return nil
    end
    if payload.building and payload.building ~= state.building then return nil end
    return state
end

local function living_unit(state, challenge_id)
    alive_by_team[state.team] = alive_by_team[state.team] or {}
    local unit = alive_by_team[state.team][challenge_id]
    if valid(unit) and unit:IsAlive() then return unit end
    alive_by_team[state.team][challenge_id] = nil
    return nil
end

local function summon(state, definition, source_ability)
    if living_unit(state, definition.challenge_id) then
        return { ok = false, error = "challenge_monster_already_alive" }
    end
    local required_level = tonumber(definition.required_main_city_level) or 0
    if required_level > 0 and main_city_level(state) < required_level then
        return { ok = false, error = "challenge_main_city_level_required" }
    end
    local wave_number = challenge_count(state, definition.challenge_id) + 1
    local maximum = tonumber(definition.max_challenge_waves) or 20
    if wave_number > maximum then
        return { ok = false, error = "challenge_wave_limit_reached" }
    end
    local row = waves_by_key[key(definition.challenge_id, wave_number)]
    if not row or row.enabled == false then
        return { ok = false, error = "challenge_wave_missing" }
    end
    local unit, spawn_error = wave_system.spawn_challenge_monster(
        row,
        definition
    )
    if not unit then return { ok = false, error = spawn_error } end

    unit.survival_challenge_id = definition.challenge_id
    unit.survival_challenge_owner_player_id = state.player_id
    unit.survival_challenge_owner_team = state.team
    unit.survival_challenge_reward_profile_id = definition.reward_profile_id
    unit.survival_challenge_wave_number = wave_number
    challenge_count_by_team[state.team][definition.challenge_id] = wave_number
    alive_by_team[state.team][definition.challenge_id] = unit
    monster_meta[unit:entindex()] = {
        unit = unit,
        building_entindex = state.entindex,
        challenge_id = definition.challenge_id,
        player_id = state.player_id,
        team = state.team,
        reward_profile_id = definition.reward_profile_id,
        challenge_wave_number = wave_number,
    }
    if source_ability then
        source_ability:StartCooldown(tonumber(definition.cooldown_seconds) or 150)
    end
    return { ok = true, unit = unit, wave_number = wave_number }
end

local function summon_request(payload)
    local state = state_for(payload)
    local definition = definitions.by_id[tostring(payload and payload.challenge_id or "")]
    local source_ability = payload and payload.source_ability or nil
    if not state or not definition or definition.enabled == false
        or not source_ability or source_ability:IsNull() then
        return { ok = false, error = "challenge_request_invalid" }
    end
    if source_ability:GetCaster() ~= state.building
        or definition.ability_name ~= source_ability:GetAbilityName() then
        return { ok = false, error = "challenge_ability_mismatch" }
    end
    return summon(state, definition, nil)
end

local function auto_request(payload)
    local state = state_for(payload)
    if not state then return { ok = false, error = "challenge_building_invalid" } end
    state.auto_enabled = payload.enabled == true
    return { ok = true, enabled = state.auto_enabled }
end

local function auto_tick()
    for _, state in pairs(states) do
        if state.auto_enabled and valid(state.building) and state.building:IsAlive() then
            for _, definition in ipairs(ordered_definitions) do
                local ability = state.building:FindAbilityByName(definition.ability_name)
                if ability and ability:GetCooldownTimeRemaining() <= 0
                    and not living_unit(state, definition.challenge_id) then
                    local result = summon(state, definition, ability)
                    if result.ok then break end
                    if result.error ~= "challenge_wave_limit_reached"
                        and result.error ~= "challenge_main_city_level_required" then
                        notify(state, "自动召唤失败：" .. tostring(result.error))
                        break
                    end
                end
            end
        end
    end
end

local function on_building_created(payload)
    if not payload or payload.building_id ~= "building_challenge"
        or not valid(payload.unit) then return end
    local state = {
        entindex = payload.entindex,
        building = payload.unit,
        player_id = tonumber(payload.player_id) or -1,
        team = tonumber(payload.team) or payload.unit:GetTeamNumber(),
        auto_enabled = false,
    }
    states[state.entindex] = state
    for _, definition in ipairs(ordered_definitions) do
        local ability = state.building:FindAbilityByName(definition.ability_name)
        if ability then
            ability:StartCooldown(tonumber(definition.cooldown_seconds) or 150)
        end
    end
end

local function on_building_destroyed(payload)
    if payload and payload.building_id == "building_challenge" then
        states[tonumber(payload.entindex)] = nil
    end
end

local function on_entity_killed(payload)
    local entindex = tonumber(payload and payload.victim_entindex)
    local meta = entindex and monster_meta[entindex] or nil
    if not meta then return end
    monster_meta[entindex] = nil
    local state = states[meta.building_entindex]
    local team_alive = alive_by_team[meta.team]
    if team_alive and team_alive[meta.challenge_id] == meta.unit then
        team_alive[meta.challenge_id] = nil
    end
    event_bus.request(events.MONSTER_REWARD_GRANT_REQUEST, {
        player_id = meta.player_id,
        team = meta.team,
        reward_profile_id = meta.reward_profile_id,
        encounter_id = "building_challenge:" .. meta.challenge_id,
        challenge_wave_number = meta.challenge_wave_number,
    })
end

function M.init()
    scheduler.cancel(TASK_ID)
    states = {}
    monster_meta = {}
    alive_by_team = {}
    challenge_count_by_team = {}
    ordered_definitions = {}
    waves_by_key = {}
    for _, definition in ipairs(definitions.rows or {}) do
        if definition.enabled ~= false then
            ordered_definitions[#ordered_definitions + 1] = definition
        end
    end
    table.sort(ordered_definitions, function(a, b)
        return (tonumber(a.sort_order) or 0) < (tonumber(b.sort_order) or 0)
    end)
    for _, row in ipairs(wave_rows.rows or {}) do
        waves_by_key[key(row.challenge_id, row.wave_number)] = row
    end
    event_bus.handle_request(events.BUILDING_CHALLENGE_SUMMON_REQUEST, summon_request)
    event_bus.handle_request(events.BUILDING_CHALLENGE_AUTO_REQUEST, auto_request)
    event_bus.subscribe(events.BUILDING_CREATED, on_building_created)
    event_bus.subscribe(events.BUILDING_DESTROYED, on_building_destroyed)
    event_bus.subscribe(events.ENGINE_ENTITY_KILLED, on_entity_killed)
    scheduler.every(1, auto_tick, TASK_ID)
end

return M