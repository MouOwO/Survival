local event_bus = require("core/event_bus")
local events = require("core/events")
local config = require("config/workers_config")

local M = {}
local workers = {}
local current_tree_entindex = -1

local function valid_entity(entity)
    return entity and not entity:IsNull()
end

local function candidate_is_traversable(position)
    local ok_traversable, traversable = pcall(function()
        return GridNav:IsTraversable(position)
    end)
    if ok_traversable and not traversable then return false end

    local ok_blocked, blocked = pcall(function()
        return GridNav:IsBlocked(position)
    end)
    if ok_blocked and blocked then return false end
    return true
end

local function candidate_has_clearance(city, position)
    local units = FindUnitsInRadius(
        city:GetTeamNumber(),
        position,
        nil,
        config.nearby_unit_clearance or 128,
        DOTA_UNIT_TARGET_TEAM_BOTH,
        DOTA_UNIT_TARGET_ALL,
        DOTA_UNIT_TARGET_FLAG_NONE,
        FIND_ANY_ORDER,
        false
    )
    return #units == 0
end

local function find_worker_spawn_position(city)
    local origin = city:GetAbsOrigin()
    local min_radius = config.spawn_radius_min or 420
    if city.GetHullRadius then
        min_radius = math.max(
            min_radius,
            (city:GetHullRadius() or 0) + (config.spawn_clearance or 160)
        )
    end

    local max_radius = math.max(min_radius, config.spawn_radius_max or 640)
    local attempts = math.max(1, config.spawn_attempts or 24)

    for index = 1, attempts do
        local ratio = attempts == 1 and 0 or (index - 1) / (attempts - 1)
        local radius = min_radius + (max_radius - min_radius) * ratio
        local angle = RandomFloat(0, math.pi * 2)
        local candidate = origin + Vector(
            math.cos(angle) * radius,
            math.sin(angle) * radius,
            0
        )
        candidate.z = GetGroundHeight(candidate, city)

        if candidate_is_traversable(candidate)
            and candidate_has_clearance(city, candidate) then
            return candidate
        end
    end

    local fallback = origin + Vector(max_radius, 0, 0)
    fallback.z = GetGroundHeight(fallback, city)
    return fallback
end

local function notify(player_id, message, level)
    event_bus.emit(events.UI_NOTIFICATION, {
        player_id = player_id,
        message = message,
        level = level or "info",
    })
end

local function update_worker_targets()
    for entindex, state in pairs(workers) do
        if valid_entity(state.unit) then
            local modifier = state.unit:FindModifierByName("modifier_lumberjack_ai")
            if modifier and modifier.SetTreeEntIndex then
                modifier:SetTreeEntIndex(current_tree_entindex)
            end
        else
            workers[entindex] = nil
        end
    end
end

local function train_worker(payload)
    local city = payload.city
    if not valid_entity(city) then return { ok = false, error = "invalid_city" } end

    local city_state = event_bus.request(events.BUILDING_QUERY_REQUEST, {
        entindex = city:entindex(),
    })
    if not city_state or city_state.building_id ~= "main_city" then
        return { ok = false, error = "not_main_city" }
    end

    local spend = event_bus.request(events.RESOURCE_TRY_SPEND_REQUEST, {
        team = city_state.team,
        wood = config.cost.wood,
        gold = config.cost.gold,
        population = config.cost.population,
        reason = "train_lumberjack",
    })
    if not spend or not spend.ok then
        notify(city_state.player_id, spend and spend.error or "resource_error", "error")
        return spend
    end

    local spawn_position = find_worker_spawn_position(city)
    local worker = CreateUnitByName(
        config.unit_name,
        spawn_position,
        true,
        city,
        city,
        city_state.team
    )
    if not worker then
        event_bus.request(events.RESOURCE_ADD_REQUEST, {
            team = city_state.team,
            wood = config.cost.wood,
            gold = config.cost.gold,
            reason = "train_lumberjack_refund",
        })
        event_bus.request(events.RESOURCE_RELEASE_POP_REQUEST, {
            team = city_state.team,
            population = config.cost.population,
            reason = "train_lumberjack_refund",
        })
        return { ok = false, error = "worker_create_failed" }
    end

    FindClearSpaceForUnit(worker, spawn_position, true)
    worker:SetControllableByPlayer(city_state.player_id, true)
    worker:SetBaseMaxHealth(config.health)
    worker:SetMaxHealth(config.health)
    worker:SetHealth(config.health)
    worker:SetPhysicalArmorBaseValue(config.armor)
    worker:SetBaseDamageMin(config.damage_min)
    worker:SetBaseDamageMax(config.damage_max)
    worker:SetBaseAttackTime(config.attack_rate)
    worker:SetBaseMoveSpeed(config.move_speed)
    worker:AddNewModifier(worker, nil, "modifier_lumberjack_ai", {
        tree_entindex = current_tree_entindex,
    })

    workers[worker:entindex()] = {
        unit = worker,
        team = city_state.team,
        player_id = city_state.player_id,
        population = config.cost.population,
    }
    notify(city_state.player_id, "伐木工训练完成")
    event_bus.emit(events.WORKER_CHANGED, {
        team = city_state.team,
        count_delta = 1,
    })
    return { ok = true, entindex = worker:entindex() }
end

local function on_tree_spawned(payload)
    current_tree_entindex = payload.entindex or -1
    update_worker_targets()
end

local function on_tree_destroyed()
    current_tree_entindex = -1
    update_worker_targets()
end

local function on_entity_killed(payload)
    local victim = payload.victim
    if not valid_entity(victim) then return end
    local state = workers[victim:entindex()]
    if not state then return end

    workers[victim:entindex()] = nil
    event_bus.request(events.RESOURCE_RELEASE_POP_REQUEST, {
        team = state.team,
        population = state.population,
        reason = "lumberjack_died",
    })
    event_bus.emit(events.WORKER_CHANGED, {
        team = state.team,
        count_delta = -1,
    })
end

function M.init()
    workers = {}
    current_tree_entindex = -1
    event_bus.subscribe(events.WORKER_TRAIN_REQUEST, train_worker)
    event_bus.subscribe(events.TREE_SPAWNED, on_tree_spawned)
    event_bus.subscribe(events.TREE_DESTROYED, on_tree_destroyed)
    event_bus.subscribe(events.ENGINE_ENTITY_KILLED, on_entity_killed)
end

return M
