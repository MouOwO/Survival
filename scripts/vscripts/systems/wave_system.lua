local event_bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")
local team_alignment = require("core/team_alignment")
local wave_rows = require("config/generated/wave_definitions")
local archetypes = require("config/generated/monster_archetypes")
local spawn_points = require("config/generated/monster_spawn_points")
local monster_spawn_marker_service = require("systems/monster_spawn_marker")
local armor_balance = require("config/armor_balance")
local asset_preload = require("systems/asset_preload_service")
local difficulty_config = require("config/difficulty_config")
local wave_difficulty_builder = require("systems/wave_difficulty_builder")
local wave_timing_config = require("config/wave_timing_config")
local asset_catalog = require("config/asset_catalog")
local monster_visual_config = require("config/monster_visual_config")
local monster_visual_service = require("systems/monster_visual_service")
local monster_hull_scale = require("systems/monster_hull_scale")
local monster_corpse_lifecycle_service = require(
    "systems/monster_corpse_lifecycle_service"
)
local wave_spawn_sequence = require("systems/wave_spawn_sequence")
local wave_monster_collision = require("systems/wave_monster_collision")
local global_rules = require("config/global_rules")

local M = {}
local state = {}
local enemies = {}
local wall_entindex = -1
local generation_token = 0
local difficulty_id = difficulty_config.default_id
local difficulty_selected = false
local game_started = false
local waves = {}
local dev_mode = false
local monster_spawn_marker = nil
local monster_hull_multiplier = 1
local game_started_at = nil
local memory_cleared_wave = -1
local EARLY_FINAL_UNLOCK_SECONDS = 15 * 60
local FINAL_WAVE_NUMBER = 30
local DEV_PRELOAD_POLL_INTERVAL = 0.05
local DEV_PRELOAD_TASK_ID = "dev_wave_preload"
local DEV_WAVE_COMPLETE_TASK_ID = "dev_wave_complete"
local wave_resource_sessions = {}
local wave_model_leases = {}
local dev_resident_models = {}
local next_wave_resource_session_id = 0

local function movement_type_for(row)
    local definition = archetypes.by_id[row.archetype_id] or {}
    return row.movement_type_override or definition.movement_type or "ground"
end

local function model_path_for(row, definition)
    definition = definition or {}
    -- TODO(FINAL_WAVE_MODELS): Remove this shared flying compatibility override
    -- after every formal wave member has an approved unique final model.
    if wave_spawn_sequence.is_normal(row)
        and movement_type_for(row) == "flying"
        and type(definition.normal_flying_model_path) == "string"
        and definition.normal_flying_model_path ~= "" then
        return definition.normal_flying_model_path
    end
    return definition.model_path
end

local function wave_model_paths(wave)
    local model_paths = {}
    local seen_models = {}
    for _, row in ipairs((wave and wave.batches) or {}) do
        local definition = archetypes.by_id[row.archetype_id]
        local model_path = definition and model_path_for(row, definition) or nil
        if model_path and model_path ~= "" and not seen_models[model_path] then
            seen_models[model_path] = true
            model_paths[#model_paths + 1] = model_path
        end
    end
    table.sort(model_paths)
    return model_paths
end

local function acquire_wave_model_resources(number, wave, token, is_dev)
    next_wave_resource_session_id = next_wave_resource_session_id + 1
    local session_id = string.format(
        "%s:%d:%d",
        is_dev and "dev" or "formal",
        tonumber(number) or 0,
        next_wave_resource_session_id
    )
    local planned = 0
    for _, row in ipairs((wave and wave.batches) or {}) do
        planned = planned + (tonumber(row.monster_count) or 0)
    end
    local session = {
        session_id = session_id,
        wave_number = number,
        generation_token = token,
        dev_mode = is_dev == true,
        model_paths = wave_model_paths(wave),
        planned = planned,
        pending = planned,
        alive = 0,
        generation_completed = false,
        released = false,
    }
    wave_resource_sessions[session_id] = session
    for _, model_path in ipairs(session.model_paths) do
        local lease = wave_model_leases[model_path] or {
            session_count = 0,
            sessions = {},
            dev_resident = dev_resident_models[model_path] == true,
        }
        if not lease.sessions[session_id] then
            lease.sessions[session_id] = true
            lease.session_count = lease.session_count + 1
        end
        wave_model_leases[model_path] = lease
    end
    return session
end

local function release_wave_model_resources(session, reason, force)
    if not session or session.released then return false end
    if not force and (session.pending > 0 or session.alive > 0
            or not session.generation_completed) then
        return false
    end
    session.released = true
    session.release_reason = reason or "wave_complete"
    for _, model_path in ipairs(session.model_paths or {}) do
        local lease = wave_model_leases[model_path]
        if lease and lease.sessions[session.session_id] then
            lease.sessions[session.session_id] = nil
            lease.session_count = math.max(0, lease.session_count - 1)
        end
        if session.dev_mode then
            -- Dev jumps intentionally keep exact models resident for repeated
            -- inspection while still releasing the per-session Lua identity.
            dev_resident_models[model_path] = true
            lease = lease or { session_count = 0, sessions = {} }
            lease.dev_resident = true
            wave_model_leases[model_path] = lease
        elseif lease and lease.session_count <= 0 and not lease.dev_resident then
            -- TODO(SOURCE2_MODEL_UNLOAD): Workshop Lua exposes no confirmed safe
            -- model-unload API. This releases only project Lua leases; never call
            -- asset_preload.retire(), which would block a later reload.
            wave_model_leases[model_path] = nil
        end
    end
    wave_resource_sessions[session.session_id] = nil
    return true
end

local function settle_wave_resource_session(session, reason, force)
    if not session or session.released then return false end
    if force then
        session.pending = 0
        session.alive = 0
        session.generation_completed = true
    end
    return release_wave_model_resources(session, reason, force)
end

local function cancel_pending_wave_resource_sessions(reason, keep_models_resident)
    local sessions = {}
    for _, session in pairs(wave_resource_sessions) do
        sessions[#sessions + 1] = session
    end
    for _, session in ipairs(sessions) do
        session.pending = 0
        session.generation_completed = true
        if keep_models_resident then session.dev_mode = true end
        release_wave_model_resources(session, reason or "generation_cancelled")
    end
end

local function force_release_all_wave_resource_sessions(reason)
    local sessions = {}
    for _, session in pairs(wave_resource_sessions) do
        sessions[#sessions + 1] = session
    end
    for _, session in ipairs(sessions) do
        settle_wave_resource_session(session, reason, true)
    end
end

local function spawn_sequence(batches)
    return wave_spawn_sequence.build(batches, {
        enabled = global_rules.wave_monster_round_robin_enabled ~= 0,
        movement_type = movement_type_for,
    })
end

local function next_wave_number_after(number)
    local next_number = (tonumber(number) or 0) + 1
    while next_number <= (tonumber(state.total_waves) or 0)
        and not waves[next_number] do
        next_number = next_number + 1
    end
    if next_number > (tonumber(state.total_waves) or 0) then return nil end
    return next_number
end

local function queue_wave_assets(number)
    local wave = waves[number]
    if not wave then return false, "wave_not_found", 0, 0 end
    local model_paths = wave_model_paths(wave)
    local visual_resources = monster_visual_config.resources_for_wave(number)
    local resources = asset_preload.resources_for_models(
        model_paths,
        visual_resources
    )
    local ok, status, queued_count, failed_count = asset_preload.queue_resources(
        resources,
        {
            urgent = true,
            priority = 3000 - (tonumber(number) or 0),
            retry = true,
        }
    )
    return ok, status, queued_count or 0, failed_count or 0, #resources
end

local function valid(entity)
    return entity and not entity:IsNull()
end

local function count_entries(values)
    local count = 0
    for _ in pairs(values or {}) do count = count + 1 end
    return count
end

local function report_memory(phase)
    local lua_kib = type(collectgarbage) == "function"
        and tonumber(collectgarbage("count")) or -1
    local scheduler_count = type(scheduler.task_count) == "function"
        and scheduler.task_count() or -1
    local visual_count = type(monster_visual_service.active_state_count) == "function"
        and monster_visual_service.active_state_count() or -1
    local game_time = GameRules and GameRules.GetGameTime
        and tonumber(GameRules:GetGameTime()) or -1
    print(string.format(
        "[SURVIVAL_MEMORY][LUA] phase=%s wave=%d game_time=%.1f lua_kib=%.1f alive=%d pending=%d enemies=%d scheduler=%d visuals=%d",
        tostring(phase),
        tonumber(state.current_wave) or 0,
        game_time,
        lua_kib or -1,
        tonumber(state.alive) or 0,
        tonumber(state.pending) or 0,
        count_entries(enemies),
        scheduler_count,
        visual_count
    ))
end

local function find_monster_spawn_marker()
    return monster_spawn_marker_service.find()
end

local function reset()
    state = { current_wave = 0, total_waves = 0, status = "waiting", timer = 0,
        planned = 0, pending = 0, spawned = 0, alive = 0, killed = 0,
        failed_spawn = 0, boss_alive = false, difficulty_id = difficulty_id,
        difficulty_selected = difficulty_selected,
        difficulty_options = difficulty_config.client_options(),
        final_wave_generation_completed = false,
        early_final_used = false,
        victory_settled = false }
end

local function publish(reason)
    local data = {}
    for key, value in pairs(state) do data[key] = value end
    data.reason = reason
    event_bus.emit(events.WAVE_CHANGED, data)
end

local function current_game_time()
    return GameRules and GameRules.GetGameTime
        and tonumber(GameRules:GetGameTime()) or 0
end

local function early_final_remaining()
    if not game_started or game_started_at == nil then
        return EARLY_FINAL_UNLOCK_SECONDS
    end
    return math.max(0,
        EARLY_FINAL_UNLOCK_SECONDS - (current_game_time() - game_started_at))
end

local function settle_victory_once()
    if state.victory_settled then return false end
    state.victory_settled = true
    state.status = "victory"
    state.timer = 0
    publish("final_wave_cleared")
    if GameRules and GameRules.SetGameWinner then
        GameRules:SetGameWinner(DOTA_TEAM_GOODGUYS)
    end
    return true
end

local function check_final_victory()
    local terminal_wave = state.current_wave == FINAL_WAVE_NUMBER
        or (state.early_final_used ~= true
            and state.current_wave == state.total_waves)
    if terminal_wave
        and state.final_wave_generation_completed == true
        and state.failed_spawn <= 0
        and state.pending <= 0 and state.alive <= 0 then
        settle_victory_once()
    end
end

local function set_wall(enemy)
    if not valid(enemy) then return end
    local modifier = enemy:FindModifierByName("modifier_enemy_wall_ai")
    if modifier and modifier.SetWallEntIndex then modifier:SetWallEntIndex(wall_entindex) end
end

local function update_targets()
    for entindex, meta in pairs(enemies) do
        if valid(meta.unit) and meta.unit:IsAlive() then
            set_wall(meta.unit)
        else
            enemies[entindex] = nil
        end
    end
end

local function rebuild_waves()
    waves = {}
    local built, build_error = wave_difficulty_builder.build(
        wave_rows.rows,
        difficulty_id
    )
    if not built then
        state.total_waves = 0
        return false, build_error
    end
    for wave_number, batches in pairs(built.waves) do
        waves[wave_number] = {
            wave_number = wave_number,
            wait_seconds = batches[1] and batches[1].wait_seconds or 30,
            batches = batches,
        }
    end
    if not waves[FINAL_WAVE_NUMBER] then
        local final_source = wave_difficulty_builder.build(wave_rows.rows, "N2")
        local final_batches = final_source
            and final_source.waves[FINAL_WAVE_NUMBER] or nil
        if final_batches then
            waves[FINAL_WAVE_NUMBER] = {
                wave_number = FINAL_WAVE_NUMBER,
                wait_seconds = final_batches[1]
                    and final_batches[1].wait_seconds or 30,
                batches = final_batches,
            }
        end
    end
    state.total_waves = built.total_waves
    return true
end

local function apply_stats(unit, row, definition, movement_type)
    unit:SetBaseMaxHealth(row.health)
    unit:SetMaxHealth(row.health)
    unit:SetHealth(row.health)
    unit:SetBaseDamageMin(row.attack)
    unit:SetBaseDamageMax(row.attack)
    local war3_armor = tonumber(row.war3_armor or row.armor) or 0
    local runtime_armor = armor_balance.from_war3(war3_armor)
    unit.survival_war3_armor = war3_armor
    unit.survival_armor = runtime_armor
    unit:SetPhysicalArmorBaseValue(runtime_armor)
    local minimum_war3_armor = tonumber(
        definition.minimum_war3_armor or definition.minimum_armor
    )
    -- Normal wave definitions generally omit minimum_armor and must remain
    -- reducible. Explicit floors (for specially configured enemies) remain.
    unit.survival_minimum_armor = minimum_war3_armor ~= nil
        and armor_balance.from_war3(minimum_war3_armor) or nil
    unit:SetBaseMoveSpeed(definition.move_speed or 500)
    -- attack_speed 表示每秒攻击次数；Dota 引擎需要基础攻击间隔。
    local attack_speed = tonumber(row.attack_speed) or 0.5
    attack_speed = math.max(0.01, attack_speed)
    unit.survival_attack_speed = attack_speed
    unit:SetBaseAttackTime(1 / attack_speed)
    if not unit:HasModifier("modifier_debug_attack_cap") then
        unit:AddNewModifier(unit, nil, "modifier_debug_attack_cap", {})
    end
    if unit.Script_SetAttackRange then unit:Script_SetAttackRange(definition.attack_range or 128)
    elseif unit.SetAttackRange then unit:SetAttackRange(definition.attack_range or 128) end
    if definition.attack_type == "ranged" then
        unit:SetAttackCapability(DOTA_UNIT_CAP_RANGED_ATTACK)
    else
        unit:SetAttackCapability(DOTA_UNIT_CAP_MELEE_ATTACK)
    end
    if movement_type == "flying" then
        unit:SetMoveCapability(DOTA_UNIT_CAP_MOVE_FLY)
    else
        unit:SetMoveCapability(DOTA_UNIT_CAP_MOVE_GROUND)
    end
    unit:SetModelScale((definition.model_scale or 1.0)
        * (tonumber(row.model_scale_multiplier) or 1.0))
    local model_path = model_path_for(row, definition)
    if unit.SetModel and model_path then unit:SetModel(model_path) end
    if unit.SetOriginalModel and model_path then unit:SetOriginalModel(model_path) end
    if unit.SetAttackCapability then
        unit:SetAttackCapability(definition.attack_type == "ranged"
            and DOTA_UNIT_CAP_RANGED_ATTACK or DOTA_UNIT_CAP_MELEE_ATTACK)
    end
    if unit.SetMoveCapability then
        unit:SetMoveCapability(movement_type == "flying"
            and DOTA_UNIT_CAP_MOVE_FLY or DOTA_UNIT_CAP_MOVE_GROUND)
    end
    for _, ability_name in ipairs(definition.passive_skill_ids or {}) do
        if ability_name ~= "" and not unit:FindAbilityByName(ability_name) then
            unit:AddAbility(ability_name)
        end
    end
end

local function spawn_one(row, token, wave_number, normal_instance_index, session)
    if token ~= generation_token then return end
    state.pending = math.max(0, state.pending - 1)
    if session and not session.released then
        session.pending = math.max(0, session.pending - 1)
    end
    local definition = archetypes.by_id[row.archetype_id]
    if not definition then
        state.failed_spawn = state.failed_spawn + 1
        publish("archetype_missing")
        release_wave_model_resources(session, "spawn_failed")
        check_final_victory()
        return
    end
    local marker = monster_spawn_marker or find_monster_spawn_marker()
    if not marker then
        state.failed_spawn = state.failed_spawn + 1
        publish("monster_spawn_marker_missing")
        release_wave_model_resources(session, "spawn_marker_missing")
        check_final_victory()
        return
    end
    monster_spawn_marker = marker
    local position = marker:GetAbsOrigin()
    position.z = GetGroundHeight(position, nil) + 32
    local unit = CreateUnitByName(definition.unit_name, position, true, nil, nil, DOTA_TEAM_BADGUYS)
    if not valid(unit) then
        state.failed_spawn = state.failed_spawn + 1
        publish("unit_create_failed")
        release_wave_model_resources(session, "unit_create_failed")
        check_final_victory()
        return
    end
    team_alignment.enforce(unit, DOTA_TEAM_BADGUYS, "wave_enemy")
    monster_corpse_lifecycle_service.track(unit, "wave")
    local collision_profile = wave_monster_collision.profile(row, definition)
    apply_stats(unit, row, definition, collision_profile.movement_type)
    local resolved_visual = monster_visual_config.resolve(
        wave_number,
        row.member_role or "normal",
        normal_instance_index
    )
    if resolved_visual then
        pcall(monster_visual_service.apply, unit, resolved_visual)
    end
    local base_hull_radius = collision_profile.base_hull_radius
    local hull_ok, hull_error = monster_hull_scale.apply(
        unit,
        monster_hull_multiplier,
        base_hull_radius
    )
    if not hull_ok then
        print("[WaveSystem] monster hull apply failed: " .. tostring(hull_error))
    end
    unit.survival_wave_movement_type = collision_profile.movement_type
    unit.survival_wave_no_unit_collision = collision_profile.no_unit_collision
    unit:AddNewModifier(unit, nil, "modifier_enemy_wall_ai", {
        wall_entindex = wall_entindex,
        no_unit_collision = collision_profile.no_unit_collision and 1 or 0,
    })
    local is_assault_boss = row.member_role == "assault_boss"
        or (row.member_role == nil and row.is_boss == true)
    enemies[unit:entindex()] = {
        unit = unit,
        is_boss = is_assault_boss,
        base_hull_radius = base_hull_radius,
        wave_resource_session_id = session and session.session_id or nil,
    }
    state.spawned = state.spawned + 1
    state.alive = state.alive + 1
    if session and not session.released then
        session.alive = session.alive + 1
    end
    if is_assault_boss then state.boss_alive = true end
    publish("enemy_spawned")
end

local function spawn_callback(row, token, wave_number, normal_instance_index, session)
    return function()
        spawn_one(row, token, wave_number, normal_instance_index, session)
    end
end

local function start_countdown(seconds)
    if dev_mode then return end
    state.status = "countdown"
    state.timer = seconds
    local target_wave = next_wave_number_after(state.current_wave)
    local preload_lead = wave_timing_config.formal_wave_preload_lead_seconds
    local preload_reviewed = target_wave == nil or target_wave <= 1
    local function queue_target_wave(phase)
        if target_wave == nil or target_wave <= 1 then return end
        local ok, status, queued_count, failed_count, resource_count =
            queue_wave_assets(target_wave)
        print(string.format(
            "[WaveSystem] formal wave assets queued target_wave=%d phase=%s remaining=%.1f resources=%d queued=%d failed=%d status=%s ok=%s",
            tonumber(target_wave) or 0,
            tostring(phase),
            tonumber(state.timer) or 0,
            tonumber(resource_count) or 0,
            tonumber(queued_count) or 0,
            tonumber(failed_count) or 0,
            tostring(status),
            tostring(ok)
        ))
    end
    queue_target_wave("countdown_start")
    if state.timer <= preload_lead and not preload_reviewed then
        preload_reviewed = true
        queue_target_wave("lead_review")
    end
    publish("countdown_started")
    scheduler.cancel("wave_countdown")
    scheduler.every(1.0, function()
        state.timer = math.max(0, state.timer - 1)
        if state.timer <= preload_lead and not preload_reviewed then
            preload_reviewed = true
            queue_target_wave("lead_review")
        end
        publish("countdown_tick")
        if state.timer <= 0 then event_bus.emit(events.WAVE_START_NEXT, {}); return false end
        return true
    end, "wave_countdown")
end

local function start_wave(number, reason)
    local wave = waves[number]
    if not wave then return false, "wave_not_found" end
    scheduler.cancel("wave_countdown")
    generation_token = generation_token + 1
    state.current_wave = number
    memory_cleared_wave = -1
    state.status, state.timer = "spawning", 0
    state.planned, state.pending, state.spawned, state.killed, state.failed_spawn = 0, 0, 0, 0, 0
    state.final_wave_generation_completed = false
    for _, row in ipairs(wave.batches) do state.planned = state.planned + (row.monster_count or 0) end
    state.pending = state.planned
    local token = generation_token
    local resource_session = acquire_wave_model_resources(
        number,
        wave,
        token,
        false
    )
    publish(reason or "wave_started")
    if number < state.total_waves then
        start_countdown(wave_timing_config.interval_after_wave(number))
    end
    local next_delay, last_delay = 0, 0
    local normal_instance_index = 0
    for _, row in ipairs(spawn_sequence(wave.batches)) do
        local visual_instance_index = nil
        if wave_spawn_sequence.is_normal(row) then
            normal_instance_index = normal_instance_index + 1
            visual_instance_index = normal_instance_index
        end
        local delay = next_delay
        last_delay = delay
        scheduler.after(delay, spawn_callback(
            row,
            token,
            number,
            visual_instance_index,
            resource_session
        ))
        next_delay = next_delay + (tonumber(row.spawn_interval) or 1.0)
    end
    scheduler.after(last_delay + 0.05, function()
        if token ~= generation_token then return end
        state.pending = 0
        resource_session.pending = 0
        resource_session.generation_completed = true
        release_wave_model_resources(resource_session, "generation_completed")
        if state.current_wave == FINAL_WAVE_NUMBER
            or (state.early_final_used ~= true
                and state.current_wave == state.total_waves) then
            state.final_wave_generation_completed = true
        end
        publish("wave_generation_completed")
        report_memory("generation_completed")
        if state.current_wave >= state.total_waves then
            state.status = "all_waves_spawned"
            publish("all_waves_spawned")
            check_final_victory()
        end
    end, "wave_generation_complete")
    report_memory("wave_started")
    return true
end

local function start_next_wave()
    if dev_mode then return end
    if state.current_wave >= state.total_waves then
        state.status = "all_waves_spawned"
        publish("all_waves_spawned")
        check_final_victory()
        return
    end
    local number = next_wave_number_after(state.current_wave)
    if not number then return end
    start_wave(number, "wave_started")
end

local function on_killed(payload)
    local victim = payload.victim
    if not valid(victim) then return end
    local entindex = victim:entindex()
    local meta = enemies[entindex]
    if not meta then return end
    monster_visual_service.cleanup(victim)
    enemies[entindex] = nil
    state.alive = math.max(0, state.alive - 1)
    local resource_session = meta.wave_resource_session_id
        and wave_resource_sessions[meta.wave_resource_session_id] or nil
    if resource_session then
        resource_session.alive = math.max(0, resource_session.alive - 1)
        release_wave_model_resources(resource_session, "all_monsters_finished")
    end
    state.killed = state.killed + 1
    if meta.is_boss then state.boss_alive = false end
    publish("enemy_killed")
    if state.alive == 0 and state.pending == 0
        and memory_cleared_wave ~= state.current_wave then
        memory_cleared_wave = state.current_wave
        report_memory("wave_cleared")
    end
    check_final_victory()
end

local function clear_normal_wave_enemies()
    generation_token = generation_token + 1
    scheduler.cancel("wave_countdown")
    scheduler.cancel("wave_generation_complete")
    local removed = 0
    for entindex, meta in pairs(enemies) do
        enemies[entindex] = nil
        local unit = meta and meta.unit
        if valid(unit) then
            unit.survival_wave_cleanup = true
            monster_visual_service.cleanup(unit)
            UTIL_Remove(unit)
            removed = removed + 1
        end
    end
    state.alive = 0
    state.pending = 0
    state.boss_alive = false
    force_release_all_wave_resource_sessions("forced_wave_cleanup")
    return removed
end

local function get_wave_state()
    return {
        ok = true,
        difficulty_id = difficulty_id,
        current_wave = state.current_wave,
        total_waves = state.total_waves,
        status = state.status,
        game_started = game_started == true,
        early_final_used = state.early_final_used == true,
        early_final_remaining = early_final_remaining(),
        victory_settled = state.victory_settled == true,
    }
end

local function request_early_final()
    if not game_started then
        return { ok = false, error = "游戏尚未开始" }
    end
    if state.early_final_used then
        return { ok = false, error = "本局已购买提前通关" }
    end
    if state.victory_settled or state.current_wave >= FINAL_WAVE_NUMBER then
        return { ok = false, error = "最终波已经开始" }
    end
    local remaining = early_final_remaining()
    if remaining > 0 then
        return {
            ok = false,
            error = "开局15分钟后可用",
            remaining_seconds = remaining,
        }
    end
    if not waves[FINAL_WAVE_NUMBER] then
        return { ok = false, error = "最终波配置缺失" }
    end
    state.early_final_used = true
    local removed = clear_normal_wave_enemies()
    state.total_waves = math.max(state.total_waves, FINAL_WAVE_NUMBER)
    local ok, error_code = start_wave(
        FINAL_WAVE_NUMBER,
        "early_final_wave_started"
    )
    if not ok then
        state.early_final_used = false
        return { ok = false, error = error_code or "最终波启动失败" }
    end
    return {
        ok = true,
        final_wave = FINAL_WAVE_NUMBER,
        removed_normal_enemies = removed,
    }
end

function M.set_dev_mode(enabled)
    dev_mode = enabled == true
    generation_token = generation_token + 1
    scheduler.cancel("wave_countdown")
    scheduler.cancel(DEV_PRELOAD_TASK_ID)
    scheduler.cancel(DEV_WAVE_COMPLETE_TASK_ID)
    if dev_mode then
        state.status = "dev_mode"
        state.pending = 0
        cancel_pending_wave_resource_sessions("dev_mode_enabled", true)
        publish("dev_mode_enabled")
    end
    return dev_mode
end

function M.is_dev_mode() return dev_mode end

local function begin_debug_wave_spawn(number, wave, token, preload_reason)
    if token ~= generation_token then return false end
    state.current_wave = number
    state.status = "dev_spawn"
    state.planned, state.pending, state.spawned, state.killed, state.failed_spawn = 0, 0, 0, 0, 0
    state.boss_alive = false
    for _, row in ipairs(wave.batches) do state.planned = state.planned + (row.monster_count or 0) end
    state.pending = state.planned
    local resource_session = acquire_wave_model_resources(
        number,
        wave,
        token,
        true
    )
    local next_delay, last_delay = 0, 0
    local normal_instance_index = 0
    for _, row in ipairs(spawn_sequence(wave.batches)) do
        local visual_instance_index = nil
        if wave_spawn_sequence.is_normal(row) then
            normal_instance_index = normal_instance_index + 1
            visual_instance_index = normal_instance_index
        end
        local delay = next_delay
        last_delay = delay
        scheduler.after(delay, spawn_callback(
            row,
            token,
            number,
            visual_instance_index,
            resource_session
        ))
        next_delay = next_delay + (tonumber(row.spawn_interval) or 1.0)
    end
    scheduler.after(last_delay + 0.05, function()
        if token == generation_token then
            resource_session.pending = 0
            resource_session.generation_completed = true
            release_wave_model_resources(resource_session, "dev_generation_completed")
            state.status = "dev_mode"
            publish("dev_wave_completed")
        end
    end, DEV_WAVE_COMPLETE_TASK_ID)
    print("[WaveSystem] dev wave spawn started wave=" .. tostring(number)
        .. " preload=" .. tostring(preload_reason))
    publish("dev_wave_started")
    return true
end

local function debug_wave_model_asset_ids(wave)
    local asset_ids = {}
    local seen = {}
    local failed = 0
    for _, row in ipairs(wave.batches or {}) do
        local definition = archetypes.by_id[row.archetype_id]
        local model_path = definition and model_path_for(row, definition) or nil
        local asset = model_path and asset_catalog.for_model(model_path)
            or nil
        local asset_id = asset and asset.asset_id or nil
        if asset_id and not seen[asset_id] then
            seen[asset_id] = true
            asset_ids[#asset_ids + 1] = asset_id
        elseif model_path and not asset_id and not seen[model_path] then
            seen[model_path] = true
            failed = failed + 1
        end
    end
    return asset_ids, failed
end

function M.debug_spawn_wave(number)
    number = tonumber(number)
    local wave = number and waves[number] or nil
    if not wave then return false, "wave_not_found" end
    dev_mode = true
    generation_token = generation_token + 1
    local token = generation_token
    scheduler.cancel("wave_countdown")
    scheduler.cancel(DEV_PRELOAD_TASK_ID)
    scheduler.cancel(DEV_WAVE_COMPLETE_TASK_ID)
    cancel_pending_wave_resource_sessions("dev_wave_replaced", true)
    state.current_wave = number
    state.status = "dev_preloading"
    state.timer = wave_timing_config.dev_wave_preload_timeout_seconds
    state.pending = 0
    publish("dev_wave_preload_started")

    local asset_ids, missing_count = debug_wave_model_asset_ids(wave)
    local preload_failed = missing_count > 0
    for _, asset_id in ipairs(asset_ids) do
        local ok = asset_preload.queue(asset_id, {
            urgent = true,
            priority = 4000 - number,
            retry = true,
        })
        if not ok then preload_failed = true end
    end
    monster_visual_service.queue_wave(number, {
        urgent = true,
        priority = 5000 - number,
    })

    local started_at = current_game_time()
    local timeout = wave_timing_config.dev_wave_preload_timeout_seconds
    local preload_settled = false
    local function check_preload()
        if token ~= generation_token or preload_settled then return false end
        local pending = 0
        for _, asset_id in ipairs(asset_ids) do
            local status = asset_preload.status(asset_id).status
            if status == asset_preload.STATE.FAILED
                or status == asset_preload.STATE.RETIRED then
                preload_failed = true
            elseif status ~= asset_preload.STATE.READY then
                pending = pending + 1
            end
        end
        local elapsed = math.max(0, current_game_time() - started_at)
        state.timer = math.max(0, timeout - elapsed)
        if elapsed >= timeout then
            preload_settled = true
            local reason = pending <= 0 and not preload_failed
                and "ready_after_buffer"
                or (preload_failed and "failed_open_after_buffer"
                    or "timeout_after_buffer")
            print("[WaveSystem] dev wave preload finished wave=" .. tostring(number)
                .. " reason=" .. reason .. " pending=" .. tostring(pending)
                .. " failed=" .. tostring(preload_failed)
                .. " elapsed=" .. string.format("%.2f", elapsed))
            begin_debug_wave_spawn(number, wave, token, reason)
            return false
        end
        return DEV_PRELOAD_POLL_INTERVAL
    end

    if check_preload() ~= false then
        scheduler.after(DEV_PRELOAD_POLL_INTERVAL, check_preload, DEV_PRELOAD_TASK_ID)
    end
    return true
end

function M.set_difficulty(id)
    if type(id) ~= "string" or id == "" then
        return false, "difficulty_not_found"
    end
    if difficulty_selected then
        if id == difficulty_id then return true end
        return false, "difficulty_locked"
    end
    if not difficulty_config.get(id) then
        return false, "difficulty_not_found"
    end
    difficulty_id = id
    local built, build_error = rebuild_waves()
    if not built then
        difficulty_id = difficulty_config.default_id
        rebuild_waves()
        return false, build_error or "difficulty_build_failed"
    end
    difficulty_selected = true
    state.difficulty_id = id
    state.difficulty_selected = true
    state.current_wave = 0
    publish("difficulty_changed")
    if game_started then
        start_countdown(wave_timing_config.initial_delay_seconds)
    end
    return true
end

local function set_difficulty_request(payload)
    local id = tostring(payload and payload.difficulty_id or "")
    local ok, error_code = M.set_difficulty(id)
    if not ok then
        return { ok = false, error = error_code or "difficulty_not_found" }
    end
    return { ok = true, difficulty_id = difficulty_id, total_waves = state.total_waves }
end

function M.get_difficulty() return difficulty_id end

function M.set_monster_hull_scale(multiplier)
    local ok, result_or_error = monster_hull_scale.apply_all(
        enemies,
        multiplier
    )
    if not ok then return false, result_or_error end
    monster_hull_multiplier = result_or_error.multiplier
    return true, result_or_error
end

function M._resource_snapshot_for_test()
    local sessions = {}
    for session_id, session in pairs(wave_resource_sessions) do
        sessions[session_id] = {
            wave_number = session.wave_number,
            dev_mode = session.dev_mode,
            planned = session.planned,
            pending = session.pending,
            alive = session.alive,
            generation_completed = session.generation_completed,
        }
    end
    local leases = {}
    for model_path, lease in pairs(wave_model_leases) do
        leases[model_path] = {
            session_count = lease.session_count,
            dev_resident = lease.dev_resident == true,
        }
    end
    local residents = {}
    for model_path in pairs(dev_resident_models) do residents[model_path] = true end
    return {
        sessions = sessions,
        leases = leases,
        dev_resident_models = residents,
        session_count = count_entries(wave_resource_sessions),
        lease_count = count_entries(wave_model_leases),
    }
end

function M.init()
    monster_spawn_marker = nil
    difficulty_id = difficulty_config.default_id
    difficulty_selected = false
    game_started = false
    game_started_at = nil
    monster_hull_multiplier = 1
    memory_cleared_wave = -1
    force_release_all_wave_resource_sessions("wave_system_init")
    wave_resource_sessions = {}
    wave_model_leases = {}
    dev_resident_models = {}
    next_wave_resource_session_id = 0
    scheduler.cancel(DEV_PRELOAD_TASK_ID)
    scheduler.cancel(DEV_WAVE_COMPLETE_TASK_ID)
    reset(); enemies = {}; wall_entindex = -1; generation_token = 0; dev_mode = false
    rebuild_waves()
    event_bus.handle_request(events.WAVE_DIFFICULTY_SET_REQUEST, set_difficulty_request)
    event_bus.handle_request(events.WAVE_STATE_GET_REQUEST, get_wave_state)
    event_bus.handle_request(events.WAVE_EARLY_FINAL_REQUEST, request_early_final)
    event_bus.subscribe(events.GAME_STARTED, function()
        game_started = true
        game_started_at = current_game_time()
        if difficulty_selected then
            start_countdown(wave_timing_config.initial_delay_seconds)
            return
        end
        state.status = "selecting_difficulty"
        state.timer = 0
        publish("difficulty_selection_started")
    end)
    event_bus.subscribe(events.WAVE_START_NEXT, start_next_wave)
    event_bus.subscribe(events.ENGINE_ENTITY_KILLED, on_killed)
    event_bus.subscribe(events.BUILDING_CREATED, function(payload) if payload.building_id == "wall" then wall_entindex = payload.entindex; update_targets() end end)
    event_bus.subscribe(events.BUILDING_DESTROYED, function(payload) if payload.building_id == "wall" and wall_entindex == payload.entindex then wall_entindex = -1; update_targets() end end)
    publish("initial")
end

return M
