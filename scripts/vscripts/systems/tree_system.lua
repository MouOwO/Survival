local event_bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")
local config = require("config/tree_config")
local particle_manager = require("core/particle_manager")

local M = {}
local current_tree = nil
local main_city = nil
local tree_level = 0

local function valid_entity(entity)
    return entity and not entity:IsNull()
end

local function level_health(level)
    local base = math.max(1, tonumber(config.health) or 1)
    local fixed = math.max(0, tonumber(config.health_per_level) or 0)
    local percent = math.max(0, tonumber(config.health_percent_per_level) or 0)
    local fixed_health = base + fixed * level
    return math.max(1, math.floor(fixed_health * math.pow(1 + percent, level)))
end

local function tree_snapshot()
    local health = level_health(tree_level)
    return {
        level = tree_level,
        health = health,
        health_per_level = config.health_per_level or 0,
        health_percent_per_level = config.health_percent_per_level or 0,
        lumber_efficiency_buff = math.max(
            0,
            tonumber(config.lumber_efficiency_buff_per_level) or 0
        ) * tree_level,
    }
end

local function publish_changed(reason)
    local snapshot = tree_snapshot()
    snapshot.reason = reason or "unknown"
    snapshot.entindex = valid_entity(current_tree)
        and current_tree:entindex() or -1
    event_bus.emit(events.TREE_CHANGED, snapshot)
end

local function spawn_tree(payload)
    local city = payload and payload.unit or main_city
    if not valid_entity(city) then
        print("[TreeSystem] main city entity is unavailable")
        return
    end
    local offset = config.spawn_offset or { x = 520, y = 0, z = 0 }
    local position = city:GetAbsOrigin() + Vector(
        tonumber(offset.x) or 520,
        tonumber(offset.y) or 0,
        tonumber(offset.z) or 0
    )
    position.z = GetGroundHeight(position, city) + 32
    local tree = CreateUnitByName(
        config.unit_name,
        position,
        true,
        nil,
        nil,
        DOTA_TEAM_BADGUYS
    )
    if not tree then
        print("[TreeSystem] failed to create tree")
        return
    end

    local health = level_health(tree_level)
    tree:SetBaseMaxHealth(health)
    tree:SetMaxHealth(health)
    tree:SetHealth(health)
    tree:SetPhysicalArmorBaseValue(config.armor)
    tree:SetAttackCapability(DOTA_UNIT_CAP_NO_ATTACK)
    current_tree = tree

    event_bus.emit(events.TREE_SPAWNED, {
        entindex = tree:entindex(),
        level = tree_level,
        health = health,
        lumber_efficiency_buff = tree_snapshot().lumber_efficiency_buff,
    })
    publish_changed("tree_spawned")
end

local function on_tree_hit(payload)
    if not valid_entity(current_tree) then return end
    if not payload.target
        or payload.target:entindex() ~= current_tree:entindex() then
        return
    end
    local attacker = payload.attacker
    if not valid_entity(attacker) then return end
    local base_efficiency = payload.source == "hero"
        and config.hero_base_lumber_efficiency
        or payload.base_lumber_efficiency
    local efficiency = math.max(0, math.floor(
        (tonumber(base_efficiency) or 0)
        + tree_snapshot().lumber_efficiency_buff
    ))
    if efficiency <= 0 then return end
    local result = event_bus.request(events.RESOURCE_ADD_REQUEST, {
        team = payload.team,
        wood = efficiency,
        reason = payload.source == "hero"
            and "hero_tree_hit" or "lumberjack_hit",
    })
    if not result or result.ok ~= true then return end
    local player = payload.player_id ~= nil
        and PlayerResource:GetPlayer(payload.player_id) or nil
    particle_manager.show_green_number(attacker, efficiency, player)
end

local function on_entity_killed(payload)
    local victim = payload.victim
    if not valid_entity(victim) or not valid_entity(current_tree) then return end
    if victim:entindex() ~= current_tree:entindex() then return end

    local old_entindex = current_tree:entindex()
    tree_level = tree_level + 1
    current_tree = nil
    event_bus.emit(events.TREE_DESTROYED, {
        entindex = old_entindex,
        level = tree_level,
        lumber_efficiency_buff = tree_snapshot().lumber_efficiency_buff,
    })
    publish_changed("tree_destroyed_level_up")
    scheduler.after(config.respawn_time, spawn_tree, "tree_respawn")
end

local function on_building_created(payload)
    if not payload or payload.building_id ~= "main_city" then return end
    if not valid_entity(payload.unit) then return end
    main_city = payload.unit
    if valid_entity(current_tree) then return end
    spawn_tree(payload)
end

function M.init()
    current_tree = nil
    main_city = nil
    tree_level = 0
    event_bus.subscribe(events.BUILDING_CREATED, on_building_created)
    event_bus.subscribe(events.TREE_HIT, on_tree_hit)
    event_bus.subscribe(events.ENGINE_ENTITY_KILLED, on_entity_killed)
end

return M
