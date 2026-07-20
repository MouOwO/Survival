local event_bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")
local team_alignment = require("core/team_alignment")
local wave_rows = require("config/generated/wave_definitions")
local archetypes = require("config/generated/monster_archetypes")

local M = {}
local state = {}
local enemies = {}
local wall_entindex = -1
local generation_token = 0
local difficulty_id = "N1"
local waves = {}
local dev_mode = false

local function valid(entity)
    return entity and not entity:IsNull()
end

local function reset()
    state = { current_wave = 0, total_waves = 0, status = "waiting", timer = 0,
        planned = 0, pending = 0, spawned = 0, alive = 0, killed = 0,
        failed_spawn = 0, boss_alive = false, difficulty_id = difficulty_id }
end

local function publish(reason)
    local data = {}
    for key, value in pairs(state) do data[key] = value end
    data.reason = reason
    event_bus.emit(events.WAVE_CHANGED, data)
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
    for _, row in ipairs(wave_rows.rows or {}) do
        if row.enabled ~= false and row.difficulty_id == difficulty_id then
            local wave = waves[row.wave_number]
            if not wave then
                wave = { wave_number = row.wave_number, wait_seconds = row.wait_seconds or 30, batches = {} }
                waves[row.wave_number] = wave
            end
            table.insert(wave.batches, row)
        end
    end
    for _, wave in pairs(waves) do
        table.sort(wave.batches, function(a, b) return (a.spawn_order or 0) < (b.spawn_order or 0) end)
    end
    local total = 0
    for number in pairs(waves) do if number > total then total = number end end
    state.total_waves = total
end

local function apply_stats(unit, row, definition)
    unit:SetBaseMaxHealth(row.health)
    unit:SetMaxHealth(row.health)
    unit:SetHealth(row.health)
    unit:SetBaseDamageMin(row.attack)
    unit:SetBaseDamageMax(row.attack)
    unit:SetPhysicalArmorBaseValue(row.armor)
    unit:SetBaseMoveSpeed(definition.move_speed or 250)
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
    if definition.movement_type == "flying" then
        unit:SetMoveCapability(DOTA_UNIT_CAP_MOVE_FLY)
    else
        unit:SetMoveCapability(DOTA_UNIT_CAP_MOVE_GROUND)
    end
    unit:SetModelScale(definition.model_scale or 1.0)
    if unit.SetModel and definition.model_path then unit:SetModel(definition.model_path) end
    if unit.SetOriginalModel and definition.model_path then unit:SetOriginalModel(definition.model_path) end
    if unit.SetAttackCapability then
        unit:SetAttackCapability(definition.attack_type == "ranged"
            and DOTA_UNIT_CAP_RANGED_ATTACK or DOTA_UNIT_CAP_MELEE_ATTACK)
    end
    if unit.SetMoveCapability then
        unit:SetMoveCapability(definition.movement_type == "flying"
            and DOTA_UNIT_CAP_MOVE_FLY or DOTA_UNIT_CAP_MOVE_GROUND)
    end
    for _, ability_name in ipairs(definition.passive_skill_ids or {}) do
        if ability_name ~= "" and not unit:FindAbilityByName(ability_name) then
            unit:AddAbility(ability_name)
        end
    end
end

local function spawn_one(row, token)
    if token ~= generation_token then return end
    state.pending = math.max(0, state.pending - 1)
    local definition = archetypes.by_id[row.archetype_id]
    if not definition then state.failed_spawn = state.failed_spawn + 1; publish("archetype_missing"); return end
    local point = { x = 0, y = 1600, z = 128 }
    local position = Vector(point.x, point.y, point.z) + RandomVector(100)
    position.z = GetGroundHeight(position, nil) + 32
    local unit = CreateUnitByName(definition.unit_name, position, true, nil, nil, DOTA_TEAM_BADGUYS)
    if not valid(unit) then state.failed_spawn = state.failed_spawn + 1; publish("unit_create_failed"); return end
    team_alignment.enforce(unit, DOTA_TEAM_BADGUYS, "wave_enemy")
    apply_stats(unit, row, definition)
    unit:AddNewModifier(unit, nil, "modifier_enemy_wall_ai", { wall_entindex = wall_entindex })
    enemies[unit:entindex()] = { unit = unit, is_boss = row.is_boss == true }
    state.spawned = state.spawned + 1
    state.alive = state.alive + 1
    if row.is_boss == true then state.boss_alive = true end
    publish("enemy_spawned")
end

local function start_countdown(seconds)
    if dev_mode then return end
    state.status = "countdown"
    state.timer = seconds
    publish("countdown_started")
    scheduler.cancel("wave_countdown")
    scheduler.every(1.0, function()
        state.timer = math.max(0, state.timer - 1)
        publish("countdown_tick")
        if state.timer <= 0 then event_bus.emit(events.WAVE_START_NEXT, {}); return false end
        return true
    end, "wave_countdown")
end

local function start_next_wave()
    if dev_mode then return end
    if state.current_wave >= state.total_waves then state.status = "all_waves_spawned"; publish("all_waves_spawned"); return end
    state.current_wave = state.current_wave + 1
    local wave = waves[state.current_wave]
    if not wave then return start_next_wave() end
    state.status, state.timer = "spawning", 0
    state.planned, state.pending, state.spawned, state.killed, state.failed_spawn = 0, 0, 0, 0, 0
    for _, row in ipairs(wave.batches) do state.planned = state.planned + (row.monster_count or 0) end
    state.pending = state.planned
    generation_token = generation_token + 1
    local token = generation_token
    publish("wave_started")
    local sequence, last_delay = 0, 0
    for _, row in ipairs(wave.batches) do
        for _ = 1, (row.monster_count or 0) do
            local delay = sequence * 1.0
            sequence = sequence + 1
            last_delay = delay
            scheduler.after(delay, function() spawn_one(row, token) end)
        end
    end
    scheduler.after(last_delay + 0.05, function()
        if token ~= generation_token then return end
        state.pending, state.status = 0, "active"
        publish("wave_generation_completed")
        if state.current_wave < state.total_waves then start_countdown(wave.wait_seconds or 30)
        else state.status = "all_waves_spawned"; publish("all_waves_spawned") end
    end, "wave_generation_complete")
end

local function on_killed(payload)
    local victim = payload.victim
    if not valid(victim) then return end
    local entindex = victim:entindex()
    local meta = enemies[entindex]
    if not meta then return end
    enemies[entindex] = nil
    state.alive = math.max(0, state.alive - 1)
    state.killed = state.killed + 1
    if meta.is_boss then state.boss_alive = false end
    publish("enemy_killed")
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
    for _, row in ipairs(wave.batches) do
        for _ = 1, (row.monster_count or 0) do
            local delay = sequence * (row.spawn_interval or 1.0)
            sequence = sequence + 1
            scheduler.after(delay, function() spawn_one(row, token) end)
        end
    end
    scheduler.after(math.max(0, (sequence - 1) * 1.0) + 0.05, function()
        if token == generation_token then state.status = "dev_mode"; publish("dev_wave_completed") end
    end, "dev_wave_complete")
    publish("dev_wave_started")
    return true
end

function M.set_difficulty(id)
    if type(id) ~= "string" or id == "" then return false end
    difficulty_id = id
    rebuild_waves()
    state.difficulty_id = id
    state.current_wave = 0
    publish("difficulty_changed")
    return state.total_waves > 0
end

local function set_difficulty_request(payload)
    local id = tostring(payload and payload.difficulty_id or "")
    if not M.set_difficulty(id) then
        return { ok = false, error = "difficulty_not_found" }
    end
    return { ok = true, difficulty_id = difficulty_id, total_waves = state.total_waves }
end

function M.get_difficulty() return difficulty_id end

function M.init()
    reset(); enemies = {}; wall_entindex = -1; generation_token = 0; dev_mode = false
    rebuild_waves()
    event_bus.handle_request(events.WAVE_DIFFICULTY_SET_REQUEST, set_difficulty_request)
    event_bus.subscribe(events.GAME_STARTED, function() start_countdown(30) end)
    event_bus.subscribe(events.WAVE_START_NEXT, start_next_wave)
    event_bus.subscribe(events.ENGINE_ENTITY_KILLED, on_killed)
    event_bus.subscribe(events.BUILDING_CREATED, function(payload) if payload.building_id == "wall" then wall_entindex = payload.entindex; update_targets() end end)
    event_bus.subscribe(events.BUILDING_DESTROYED, function(payload) if payload.building_id == "wall" and wall_entindex == payload.entindex then wall_entindex = -1; update_targets() end end)
    publish("initial")
end

return M
