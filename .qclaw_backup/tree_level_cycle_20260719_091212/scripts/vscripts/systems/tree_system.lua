local event_bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")
local config = require("config/tree_config")

local M = {}
local current_tree = nil

local function valid_entity(entity)
    return entity and not entity:IsNull()
end

local function spawn_tree()
    local point = config.spawn_point
    local position = Vector(point.x, point.y, point.z)
    position.z = GetGroundHeight(position, nil) + 32
    local tree = CreateUnitByName(config.unit_name, position, true, nil, nil, DOTA_TEAM_BADGUYS)
    if not tree then
        print("[TreeSystem] failed to create tree")
        return
    end

    tree:SetBaseMaxHealth(config.health)
    tree:SetMaxHealth(config.health)
    tree:SetHealth(config.health)
    tree:SetPhysicalArmorBaseValue(config.armor)
    tree:SetAttackCapability(DOTA_UNIT_CAP_NO_ATTACK)
    current_tree = tree

    event_bus.emit(events.TREE_SPAWNED, { entindex = tree:entindex() })
end

local function on_tree_hit(payload)
    if not valid_entity(current_tree) then return end
    if not payload.target or payload.target:entindex() ~= current_tree:entindex() then return end
    event_bus.request(events.RESOURCE_ADD_REQUEST, {
        team = payload.team,
        wood = config.wood_per_hit,
        reason = "tree_hit",
    })
end

local function on_entity_killed(payload)
    local victim = payload.victim
    if not valid_entity(victim) or not valid_entity(current_tree) then return end
    if victim:entindex() ~= current_tree:entindex() then return end

    local old_entindex = current_tree:entindex()
    current_tree = nil
    event_bus.emit(events.TREE_DESTROYED, { entindex = old_entindex })
    scheduler.after(config.respawn_time, spawn_tree, "tree_respawn")
end

function M.init()
    current_tree = nil
    event_bus.subscribe(events.GAME_STARTED, spawn_tree)
    event_bus.subscribe(events.TREE_HIT, on_tree_hit)
    event_bus.subscribe(events.ENGINE_ENTITY_KILLED, on_entity_killed)
end

return M
