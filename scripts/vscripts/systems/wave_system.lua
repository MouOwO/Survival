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
local monster_visual_config = require("config/monster_visual_config")
local monster_visual_service = require("systems/monster_visual_service")
local monster_hull_scale = require("systems/monster_hull_scale")

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
local EARLY_FINAL_UNLOCK_SECONDS = 15 * 60
local FINAL_WAVE_NUMBER = 30

local function queue_wave_assets(number)
    local wave = waves[number]
    if not wave then return end
    local seen = {}
    for _, row in ipairs(wave.batches or {}) do
        local definition = archetypes.by_id[row.archetype_id]
        local model_path = definition and definition.model_path or nil
        if model_path and not seen[model_path] then
            asset_preload.queue_model(model_path, {
                urgent = true,
                priority = 2000 - (tonumber(number) or 0),
            })
            seen[model_path] = true
        end
    end
    monster_visual_service.queue_wave(number, {
        urgent = true,
        priority = 3000 - (tonumber(number) or 0),
    })
end

local function valid(entity)
    return entity and not entity:IsNull()
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

local function apply_stats(unit, row, definition)
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
    local movement_type = row.movement_type_override or definition.movement_type
    if movement_type == "flying" then
        unit:SetMoveCapability(DOTA_UNIT_CAP_MOVE_FLY)
    else
        unit:SetMoveCapability(DOTA_UNIT_CAP_MOVE_GROUND)
    end
    unit:SetModelScale((definition.model_scale or 1.0)
        * (tonumber(row.model_scale_multiplier) or 1.0))
    if unit.SetModel and definition.model_path then unit:SetModel(definition.model_path) end
    if unit.SetOriginalModel and definition.model_path then unit:SetOriginalModel(definition.model_path) end
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

local function spawn_one(row, token, wave_number, normal_instance_index)
    if token ~= generation_token then return end
    state.pending = math.max(0, state.pending - 1)
    local definition = archetypes.by_id[row.archetype_id]
    if not definition then
        state.failed_spawn = state.failed_spawn + 1
        publish("archetype_missing")
        check_final_victory()
        return
    end
    local marker = monster_spawn_marker or find_monster_spawn_marker()
    if not marker then
        state.failed_spawn = state.failed_spawn + 1
        publish("monster_spawn_marker_missing")
        check_final_victory()
        return
    end
    monster_spawn_marker = marker
    local position = marker:GetAbsOrigin() + RandomVector(100)
    position.z = GetGroundHeight(position, nil) + 32
    local unit = CreateUnitByName(definition.unit_name, position, true, nil, nil, DOTA_TEAM_BADGUYS)
    if not valid(unit) then
        state.failed_spawn = state.failed_spawn + 1
        publish("unit_create_failed")
        check_final_victory()
        return
    end
    team_alignment.enforce(unit, DOTA_TEAM_BADGUYS, "wave_enemy")
    apply_stats(unit, row, definition)
    local resolved_visual = monster_visual_config.resolve(
        wave_number,
        row.member_role or "normal",
        normal_instance_index
    )
    if resolved_visual then
        pcall(monster_visual_service.apply, unit, resolved_visual)
    end
    local base_hull_radius = 29
    if row.member_role == "assault_boss" or definition.rank == "boss"
        or row.is_boss == true then
        base_hull_radius = 0
    elseif definition.rank == "elite" or row.member_role == "wave_leader" then
        base_hull_radius = 58
    end
    local hull_ok, hull_error = monster_hull_scale.apply(
        unit,
        monster_hull_multiplier,
        base_hull_radius
    )
    if not hull_ok then
        print("[WaveSystem] monster hull apply failed: " .. tostring(hull_error))
    end
    unit:AddNewModifier(unit, nil, "modifier_enemy_wall_ai", { wall_entindex = wall_entindex })
    local is_assault_boss = row.member_role == "assault_boss"
        or (row.member_role == nil and row.is_boss == true)
    enemies[unit:entindex()] = {
        unit = unit,
        is_boss = is_assault_boss,
        base_hull_radius = base_hull_radius,
    }
    state.spawned = state.spawned + 1
    state.alive = state.alive + 1
    if is_assault_boss then state.boss_alive = true end
    publish("enemy_spawned")
end

local function spawn_callback(row, token, wave_number, normal_instance_index)
    return function()
        spawn_one(row, token, wave_number, normal_instance_index)
    end
end

local function start_countdown(seconds)
    if dev_mode then return end
    state.status = "countdown"
    state.timer = seconds
    queue_wave_assets((state.current_wave or 0) + 1)
    publish("countdown_started")
    scheduler.cancel("wave_countdown")
    scheduler.every(1.0, function()
        state.timer = math.max(0, state.timer - 1)
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
    state.status, state.timer = "spawning", 0
    state.planned, state.pending, state.spawned, state.killed, state.failed_spawn = 0, 0, 0, 0, 0
    state.final_wave_generation_completed = false
    for _, row in ipairs(wave.batches) do state.planned = state.planned + (row.monster_count or 0) end
    state.pending = state.planned
    local token = generation_token
    publish(reason or "wave_started")
    if number < state.total_waves then
        start_countdown(wave_timing_config.interval_after_wave(number))
        queue_wave_assets(number + 1)
    end
    local next_delay, last_delay = 0, 0
    local normal_instance_index = 0
    for _, row in ipairs(wave.batches) do
        for _ = 1, (row.monster_count or 0) do
            local visual_instance_index = nil
            if row.member_role == nil or row.member_role == "normal" then
                normal_instance_index = normal_instance_index + 1
                visual_instance_index = normal_instance_index
            end
            local delay = next_delay
            last_delay = delay
            scheduler.after(delay, spawn_callback(
                row,
                token,
                number,
                visual_instance_index
            ))
            next_delay = next_delay + (tonumber(row.spawn_interval) or 1.0)
        end
    end
    scheduler.after(last_delay + 0.05, function()
        if token ~= generation_token then return end
        state.pending = 0
        if state.current_wave == FINAL_WAVE_NUMBER
            or (state.early_final_used ~= true
                and state.current_wave == state.total_waves) then
            state.final_wave_generation_completed = true
        end
        publish("wave_generation_completed")
        if state.current_wave >= state.total_waves then
            state.status = "all_waves_spawned"
            publish("all_waves_spawned")
            check_final_victory()
        end
    end, "wave_generation_complete")
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
    local number = state.current_wave + 1
    while number <= state.total_waves and not waves[number] do
        number = number + 1
    end
    if number > state.total_waves then return end
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
    state.killed = state.killed + 1
    if meta.is_boss then state.boss_alive = false end
    publish("enemy_killed")
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
    if dev_mode then
        state.status = "dev_mode"
        state.pending = 0
        publish("dev_mode_enabled")
    end
    return dev_mode
end

function M.is_dev_mode() return dev_mode end

function M.debug_spawn_wave(number)
    number = tonumber(number)
    local wave = number and waves[number] or nil
    if not wave then return false, "wave_not_found" end
    dev_mode = true
    generation_token = generation_token + 1
    local token = generation_token
    state.current_wave = number
    state.status = "dev_spawn"
    state.planned, state.pending, state.spawned, state.killed, state.failed_spawn = 0, 0, 0, 0, 0
    state.boss_alive = false
    for _, row in ipairs(wave.batches) do state.planned = state.planned + (row.monster_count or 0) end
    state.pending = state.planned
    local sequence = 0
    local normal_instance_index = 0
    for _, row in ipairs(wave.batches) do
        for _ = 1, (row.monster_count or 0) do
            local visual_instance_index = nil
            if row.member_role == nil or row.member_role == "normal" then
                normal_instance_index = normal_instance_index + 1
                visual_instance_index = normal_instance_index
            end
            local delay = sequence * (row.spawn_interval or 1.0)
            sequence = sequence + 1
            scheduler.after(delay, spawn_callback(
                row,
                token,
                number,
                visual_instance_index
            ))
        end
    end
    scheduler.after(math.max(0, (sequence - 1) * 1.0) + 0.05, function()
        if token == generation_token then state.status = "dev_mode"; publish("dev_wave_completed") end
    end, "dev_wave_complete")
    publish("dev_wave_started")
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

function M.init()
    monster_spawn_marker = nil
    difficulty_id = difficulty_config.default_id
    difficulty_selected = false
    game_started = false
    game_started_at = nil
    monster_hull_multiplier = 1
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
