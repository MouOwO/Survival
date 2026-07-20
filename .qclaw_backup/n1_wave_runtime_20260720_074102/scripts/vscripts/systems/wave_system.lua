local event_bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")
local wave_config = require("config/waves_config")
local enemy_config = require("config/enemies_config")

local M = {}
local state = {}
local enemies = {}
local wall_entindex = -1
local generation_token = 0

local function reset_state()
    state = {
        current_wave = 0,
        total_waves = wave_config.total_waves,
        status = "waiting",
        timer = wave_config.initial_delay,
        planned = 0,
        pending = 0,
        spawned = 0,
        alive = 0,
        killed = 0,
        failed_spawn = 0,
        boss_alive = false,
    }
end

local function snapshot()
    local result = {}
    for key, value in pairs(state) do result[key] = value end
    return result
end

local function publish(reason)
    local data = snapshot()
    data.reason = reason
    event_bus.emit(events.WAVE_CHANGED, data)
end

local function valid_entity(entity)
    return entity and not entity:IsNull()
end

local function set_wall_for_enemy(enemy, entindex)
    if not valid_entity(enemy) then return end
    local modifier = enemy:FindModifierByName("modifier_enemy_wall_ai")
    if modifier and modifier.SetWallEntIndex then
        modifier:SetWallEntIndex(entindex)
    end
end

local function update_all_enemy_targets()
    for entindex, meta in pairs(enemies) do
        local enemy = meta.unit
        if valid_entity(enemy) and enemy:IsAlive() then
            set_wall_for_enemy(enemy, wall_entindex)
        else
            enemies[entindex] = nil
        end
    end
end

local function scaled_stats(definition, wave_number)
    local growth = definition.wave_growth or {}
    local factor = math.max(0, wave_number - 1)
    return {
        health = math.floor(definition.health + (growth.health_per_wave or 0) * factor),
        damage_min = math.floor(definition.damage_min + (growth.damage_per_wave or 0) * factor),
        damage_max = math.floor(definition.damage_max + (growth.damage_per_wave or 0) * factor),
        armor = definition.armor + (growth.armor_per_wave or 0) * factor,
        move_speed = definition.move_speed + (growth.move_speed_per_wave or 0) * factor,
    }
end

local function apply_enemy_stats(enemy, definition, wave_number)
    local stats = scaled_stats(definition, wave_number)
    enemy:SetBaseMaxHealth(stats.health)
    enemy:SetMaxHealth(stats.health)
    enemy:SetHealth(stats.health)
    enemy:SetBaseDamageMin(stats.damage_min)
    enemy:SetBaseDamageMax(stats.damage_max)
    enemy:SetPhysicalArmorBaseValue(stats.armor)
    enemy:SetBaseMoveSpeed(stats.move_speed)
    enemy:SetBaseAttackTime(definition.attack_rate)
    if enemy.Script_SetAttackRange then enemy:Script_SetAttackRange(definition.attack_range)
    elseif enemy.SetAttackRange then enemy:SetAttackRange(definition.attack_range) end
    enemy:SetAcquisitionRange(definition.acquisition_range or 0)
    if enemy.SetDayTimeVisionRange then enemy:SetDayTimeVisionRange(definition.day_vision) end
    if enemy.SetNightTimeVisionRange then enemy:SetNightTimeVisionRange(definition.night_vision) end
    enemy:SetModelScale(definition.model_scale)
end

local function spawn_enemy(enemy_id, wave_number, token, is_boss)
    if token ~= generation_token then return end
    state.pending = math.max(0, state.pending - 1)

    local definition = enemy_config[enemy_id]
    if not definition then
        state.failed_spawn = state.failed_spawn + 1
        publish("enemy_definition_missing")
        return
    end

    local point = wave_config.spawn_point
    local position = Vector(point.x, point.y, point.z) + RandomVector(100)
    position.z = GetGroundHeight(position, nil) + 32
    local enemy = CreateUnitByName(definition.unit_name, position, true, nil, nil, DOTA_TEAM_BADGUYS)
    if not enemy then
        state.failed_spawn = state.failed_spawn + 1
        publish("enemy_create_failed")
        return
    end

    apply_enemy_stats(enemy, definition, wave_number)
    enemy:AddNewModifier(enemy, nil, "modifier_enemy_wall_ai", {
        wall_entindex = wall_entindex,
    })
    enemies[enemy:entindex()] = { unit = enemy, is_boss = is_boss == true }
    state.spawned = state.spawned + 1
    state.alive = state.alive + 1
    if is_boss then state.boss_alive = true end
    publish("enemy_spawned")
end

local function begin_countdown(delay)
    state.status = "countdown"
    state.timer = delay
    publish("countdown_started")
    scheduler.cancel("wave_countdown")
    scheduler.every(1.0, function()
        state.timer = math.max(0, state.timer - 1)
        publish("countdown_tick")
        if state.timer <= 0 then
            event_bus.emit(events.WAVE_START_NEXT, {})
            return false
        end
        return true
    end, "wave_countdown")
end

local function schedule_next_after_generation()
    if state.current_wave >= state.total_waves then
        state.status = "all_waves_spawned"
        state.timer = 0
        publish("all_waves_spawned")
        return
    end
    begin_countdown(wave_config.interval_after_spawn_complete)
end

local function start_next_wave()
    if state.current_wave >= state.total_waves then return end
    state.current_wave = state.current_wave + 1
    state.status = "spawning"
    state.timer = 0
    state.pending = 0
    state.planned = 0
    state.spawned = 0
    state.killed = 0
    state.failed_spawn = 0

    generation_token = generation_token + 1
    local token = generation_token
    local definition = wave_config.waves[state.current_wave]
    local basic_count = definition.count or 0
    local boss_count = definition.boss_count or 0
    state.planned = basic_count + boss_count
    state.pending = state.planned
    publish("wave_started")

    local last_delay = 0
    for index = 1, basic_count do
        local delay = (index - 1) * definition.spawn_interval
        last_delay = math.max(last_delay, delay)
        scheduler.after(delay, function()
            spawn_enemy(definition.enemy_id, state.current_wave, token, false)
        end)
    end

    for index = 1, boss_count do
        local delay = basic_count * definition.spawn_interval + (index - 1) * definition.spawn_interval
        last_delay = math.max(last_delay, delay)
        scheduler.after(delay, function()
            spawn_enemy(definition.boss_id, state.current_wave, token, true)
        end)
    end

    scheduler.after(last_delay + 0.05, function()
        if token ~= generation_token then return end
        state.pending = 0
        state.status = "active"
        publish("wave_generation_completed")
        schedule_next_after_generation()
    end, "wave_generation_complete")
end

local function on_entity_killed(payload)
    local victim = payload.victim
    if not valid_entity(victim) then return end
    local meta = enemies[victim:entindex()]
    if not meta then return end
    enemies[victim:entindex()] = nil
    state.alive = math.max(0, state.alive - 1)
    state.killed = state.killed + 1
    if meta.is_boss then state.boss_alive = false end
    publish("enemy_killed")
end

local function on_building_created(payload)
    if payload.building_id ~= "wall" then return end
    wall_entindex = payload.entindex
    update_all_enemy_targets()
end

local function on_building_destroyed(payload)
    if payload.building_id ~= "wall" then return end
    if wall_entindex == payload.entindex then wall_entindex = -1 end
    update_all_enemy_targets()
end

function M.init()
    reset_state()
    enemies = {}
    wall_entindex = -1
    generation_token = 0
    event_bus.subscribe(events.GAME_STARTED, function()
        begin_countdown(wave_config.initial_delay)
    end)
    event_bus.subscribe(events.WAVE_START_NEXT, start_next_wave)
    event_bus.subscribe(events.ENGINE_ENTITY_KILLED, on_entity_killed)
    event_bus.subscribe(events.BUILDING_CREATED, on_building_created)
    event_bus.subscribe(events.BUILDING_DESTROYED, on_building_destroyed)
    publish("initial")
end

return M
