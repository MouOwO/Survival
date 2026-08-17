local event_bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")
local definitions = require("config/generated/building_challenge_definitions")
local wave_rows = require("config/generated/building_challenge_waves")
local global_rules = require("config/global_rules")
local wave_system = require("systems/wave_system")

local M = {}
local TASK_ID = "building_challenge_auto_summon"
local LIFETIME_SECONDS = math.max(
    0,
    tonumber(global_rules.building_challenge_lifetime_seconds) or 60
)
local WALL_FAILURE_HEALTH_PCT = math.max(
    0,
    tonumber(global_rules.building_challenge_wall_failure_health_pct) or 50
)
local FAILURE_CHECK_INTERVAL_SECONDS = math.max(
    0.05,
    tonumber(global_rules.building_challenge_failure_check_interval_seconds) or 0.1
)
local states = {}
local monster_meta = {}
local alive_by_team = {}
local challenge_count_by_team = {}
local ordered_definitions = {}
local waves_by_key = {}
local next_lifecycle_id = 0

local function valid(entity)
    return entity and not entity:IsNull()
end

local function game_time()
    if GameRules and type(GameRules.GetGameTime) == "function" then
        return tonumber(GameRules:GetGameTime()) or 0
    end
    return 0
end

local function notify(state, message, level)
    if not state or state.player_id < 0 then return end
    event_bus.emit(events.UI_NOTIFICATION, {
        player_id = state.player_id,
        message = message,
        level = level or "error",
    })
end

local function key(difficulty_id, challenge_id, wave_number)
    return tostring(difficulty_id) .. ":" .. tostring(challenge_id)
        .. ":" .. tostring(wave_number)
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

local function wall_health_below_threshold(meta)
    local result = event_bus.request(events.BUILDING_LIST_REQUEST, {
        player_id = meta.player_id,
    })
    for _, building in ipairs(result and result.buildings or result or {}) do
        local wall = building.building_id == "wall" and building.unit or nil
        if valid(wall) and type(wall.GetHealth) == "function"
            and type(wall.GetMaxHealth) == "function" then
            local maximum = tonumber(wall:GetMaxHealth()) or 0
            local current = tonumber(wall:GetHealth()) or 0
            if maximum > 0 then
                return current * 100 < maximum * WALL_FAILURE_HEALTH_PCT
            end
        end
    end
    return false
end

local function cancel_lifecycle_tasks(meta)
    if not meta then return end
    if meta.wall_task_id then scheduler.cancel(meta.wall_task_id) end
    if meta.timeout_task_id then scheduler.cancel(meta.timeout_task_id) end
    meta.wall_task_id = nil
    meta.timeout_task_id = nil
end

local function settle(meta, status)
    if not meta or meta.status ~= "active" then return false end
    meta.status = status
    cancel_lifecycle_tasks(meta)
    if monster_meta[meta.entindex] == meta then
        monster_meta[meta.entindex] = nil
    end
    local team_alive = alive_by_team[meta.team]
    if team_alive and team_alive[meta.challenge_id] == meta.unit then
        team_alive[meta.challenge_id] = nil
    end
    return true
end

local function fail_challenge(meta, reason, remove_unit)
    if not settle(meta, "failed") then return false end
    local message = reason == "wall_health"
        and ("挑战失败：城墙生命低于"
            .. tostring(WALL_FAILURE_HEALTH_PCT) .. "%")
        or ("挑战失败：挑战怪存活已满"
            .. tostring(LIFETIME_SECONDS) .. "秒")
    notify(meta, message, "error")
    if remove_unit ~= false and valid(meta.unit) then
        UTIL_Remove(meta.unit)
    end
    return true
end

local function start_lifecycle(meta)
    local task_prefix = "building_challenge_lifecycle_" .. tostring(meta.lifecycle_id)
    meta.wall_task_id = scheduler.every(
        FAILURE_CHECK_INTERVAL_SECONDS,
        function()
            if meta.status ~= "active" or monster_meta[meta.entindex] ~= meta then
                return false
            end
            if wall_health_below_threshold(meta) then
                fail_challenge(meta, "wall_health")
                return false
            end
            return true
        end,
        task_prefix .. "_wall"
    )
    meta.timeout_task_id = scheduler.after(
        LIFETIME_SECONDS,
        function()
            fail_challenge(meta, "timeout")
        end,
        task_prefix .. "_timeout"
    )
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
    local difficulty_id = wave_system.get_difficulty()
    local maximum = tonumber(definition.max_challenge_waves) or 20
    if wave_number > maximum then
        return { ok = false, error = "challenge_wave_limit_reached" }
    end
    local row = waves_by_key[key(difficulty_id, definition.challenge_id, wave_number)]
    if not row or row.enabled == false then
        return { ok = false, error = "challenge_wave_missing" }
    end
    local unit, spawn_error = wave_system.spawn_challenge_monster(
        row,
        definition
    )
    if not unit then return { ok = false, error = spawn_error } end

    unit.survival_challenge_id = definition.challenge_id
    unit.survival_challenge_difficulty_id = difficulty_id
    unit.survival_display_name = row.display_name or definition.display_name
    unit.survival_challenge_owner_player_id = state.player_id
    unit.survival_challenge_owner_team = state.team
    unit.survival_challenge_reward_profile_id = definition.reward_profile_id
    unit.survival_challenge_wave_number = wave_number
    alive_by_team[state.team][definition.challenge_id] = unit
    next_lifecycle_id = next_lifecycle_id + 1
    local meta = {
        entindex = unit:entindex(),
        unit = unit,
        building_entindex = state.entindex,
        challenge_id = definition.challenge_id,
        player_id = state.player_id,
        team = state.team,
        reward_profile_id = definition.reward_profile_id,
        challenge_wave_number = wave_number,
        lifecycle_id = next_lifecycle_id,
        started_at = game_time(),
        status = "active",
    }
    monster_meta[meta.entindex] = meta
    if source_ability then
        source_ability:StartCooldown(tonumber(definition.cooldown_seconds) or 150)
    end
    start_lifecycle(meta)
    if wall_health_below_threshold(meta) then
        fail_challenge(meta, "wall_health")
        return {
            ok = false,
            error = "challenge_failed_wall_health",
            cast_consumed = true,
            wave_number = wave_number,
        }
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
                    if result.cast_consumed then break end
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
    if payload.victim and payload.victim ~= meta.unit then return end
    if game_time() - meta.started_at >= LIFETIME_SECONDS then
        fail_challenge(meta, "timeout", false)
        return
    end
    if wall_health_below_threshold(meta) then
        fail_challenge(meta, "wall_health", false)
        return
    end
    if not settle(meta, "killed") then return end
    challenge_count_by_team[meta.team] = challenge_count_by_team[meta.team] or {}
    challenge_count_by_team[meta.team][meta.challenge_id]
        = meta.challenge_wave_number
    local reward = event_bus.request(events.MONSTER_REWARD_GRANT_REQUEST, {
        player_id = meta.player_id,
        team = meta.team,
        reward_profile_id = meta.reward_profile_id,
        encounter_id = "building_challenge:" .. meta.challenge_id,
        challenge_wave_number = meta.challenge_wave_number,
    })
    local effect_state = require("systems/rogue_effect_state_service")
    if reward and reward.ok and reward.idempotent ~= true
        and effect_state.numeric(meta.player_id,
            "building_challenge_reward_doubles") > 0 then
        local copy_result = event_bus.request(events.MONSTER_REWARD_GRANT_REQUEST, {
            player_id = meta.player_id,
            team = meta.team,
            reward_profile_id = meta.reward_profile_id,
            encounter_id = "building_challenge:" .. meta.challenge_id .. ":reward_copy",
            reward_transaction_id = "bounty_order:" .. tostring(meta.lifecycle_id),
            challenge_wave_number = meta.challenge_wave_number,
        })
        if copy_result and copy_result.ok and copy_result.idempotent ~= true then
            effect_state.consume_numeric(meta.player_id,
                "building_challenge_reward_doubles", 1)
        end
    end
end

function M.init()
    scheduler.cancel(TASK_ID)
    for _, meta in pairs(monster_meta) do cancel_lifecycle_tasks(meta) end
    states = {}
    monster_meta = {}
    alive_by_team = {}
    challenge_count_by_team = {}
    ordered_definitions = {}
    waves_by_key = {}
    next_lifecycle_id = 0
    for _, definition in ipairs(definitions.rows or {}) do
        if definition.enabled ~= false then
            ordered_definitions[#ordered_definitions + 1] = definition
        end
    end
    table.sort(ordered_definitions, function(a, b)
        return (tonumber(a.sort_order) or 0) < (tonumber(b.sort_order) or 0)
    end)
    for _, row in ipairs(wave_rows.rows or {}) do
        waves_by_key[key(row.difficulty_id, row.challenge_id, row.wave_number)] = row
    end
    event_bus.handle_request(events.BUILDING_CHALLENGE_SUMMON_REQUEST, summon_request)
    event_bus.handle_request(events.BUILDING_CHALLENGE_AUTO_REQUEST, auto_request)
    event_bus.subscribe(events.BUILDING_CREATED, on_building_created)
    event_bus.subscribe(events.BUILDING_DESTROYED, on_building_destroyed)
    event_bus.subscribe(events.ENGINE_ENTITY_KILLED, on_entity_killed)
    scheduler.every(1, auto_tick, TASK_ID)
end

return M