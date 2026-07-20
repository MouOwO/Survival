local event_bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")
local config = require("config/tree_config")

local M = {}
local current_tree = nil
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

local function spawn_tree()
    local point = config.spawn_point
    local position = Vector(point.x, point.y, point.z)
    position.z = GetGroundHeight(position, nil) + 32
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
    local worker = payload.worker
    if not valid_entity(worker) then return end
    local modifier = worker:FindModifierByName("modifier_lumberjack_ai")
    if not modifier or not modifier.GetLumberEfficiency then return end
    local efficiency = math.max(
        0, math.floor(tonumber(modifier:GetLumberEfficiency()) or 0)
    )
    if efficiency <= 0 then return end
    event_bus.request(events.RESOURCE_ADD_REQUEST, {
        team = payload.team,
        wood = efficiency,
        reason = "lumberjack_hit",
    })
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

function M.init()
    current_tree = nil
    tree_level = 0
    event_bus.subscribe(events.GAME_STARTED, spawn_tree)
    event_bus.subscribe(events.TREE_HIT, on_tree_hit)
    event_bus.subscribe(events.ENGINE_ENTITY_KILLED, on_entity_killed)
end

return M
