package.path = "scripts/vscripts/?.lua;" .. package.path
local bus = require("core/event_bus")
local events = require("core/events")
local config = require("config/idle_fishing_config")
local mode = "fishing"
package.loaded["systems/match_setup_service"] = { get_mode = function() return mode end }
Vector = function(x, y, z) return { x = x, y = y, z = z } end
DOTA_TEAM_GOODGUYS, DOTA_UNIT_CAP_NO_ATTACK = 2, 0
local markers, ground_calls, nav_calls = {}, 0, 0
local block = function() return false end
local function marker(position)
    return { IsNull = function() return false end, GetAbsOrigin = function() return position end }
end
local entry = Vector(12416, -3072, 152)
markers.v4_east_mode_entry = marker(entry)
Entities = { FindByName = function(_, _, name) return markers[name] end }
GetGroundPosition = function(position)
    ground_calls = ground_calls + 1
    return Vector(position.x, position.y, position.x > entry.x and 144 or 128)
end
GridNav = {
    IsTraversable = function(_, position) nav_calls = nav_calls + 1; return not block(position) end,
    IsBlocked = function(_, position) return block(position) end,
}
local players = {}
for id = 0, 3 do players[id] = { id = id } end
PlayerResource = {
    GetPlayer = function(_, id) return players[id] end,
    GetTeam = function() return 2 end,
    IsValidPlayerID = function(_, id) return players[id] ~= nil end,
}
local context = require("systems/player_context_service")
context.init()
local positions, unique = {}, {}
for id = 0, 3 do
    local spawn = assert(context.resolve_builder_spawn(id))
    assert(spawn.mode == "fishing" and spawn.source == "fishing_marker" and spawn.marker == "v4_east_mode_entry")
    assert(spawn.position.x == entry.x + config.player_offsets[id].x)
    assert(spawn.position.y == entry.y + config.player_offsets[id].y)
    assert(spawn.position.z == (spawn.position.x > entry.x and 144 or 128), "each slot follows its local terrain")
    local key = spawn.position.x .. ":" .. spawn.position.y
    assert(not unique[key], "four players must never share a landing point")
    unique[key], positions[id] = true, spawn.position
end
assert(ground_calls == 4 and nav_calls == 4)
block = function(position) return position.x == positions[0].x and position.y == positions[0].y end
local moved = assert(context.resolve_builder_spawn(0))
assert(moved.position.x == positions[0].x + 64 and moved.position.y == positions[0].y)
block = function() return false end
markers.v4_east_mode_entry = nil
markers.v4_east_mode_field_1_center = marker(Vector(12544, -3008, 200))
assert(context.resolve_builder_spawn(0).marker == "v4_east_mode_field_1_center")
markers.v4_east_mode_field_1_center = nil
local fallback = assert(context.resolve_builder_spawn(3))
assert(fallback.source == "fishing_coordinates" and fallback.position.x == positions[3].x
    and fallback.position.y == positions[3].y, "missing markers use only the configured court")
block = function() return true end
local absent, reason = context.resolve_builder_spawn(0)
assert(not absent and reason == "fishing_spawn_not_traversable", "blocked court cannot fall back to normal spawn")
block = function() return false end
local saved_nav, saved_ground = GridNav, GetGroundPosition
GridNav = nil
assert(select(2, context.resolve_builder_spawn(0)) == "fishing_navigation_unavailable")
GridNav, GetGroundPosition = saved_nav, nil
assert(select(2, context.resolve_builder_spawn(0)) == "fishing_ground_unavailable")
GetGroundPosition = function() error("ground query unavailable") end
assert(not context.resolve_builder_spawn(0))
GetGroundPosition = saved_ground
assert(not context.resolve_builder_spawn(4))
for _, regular in ipairs({ "pure", "standard" }) do
    mode = regular
    for id = 0, 3 do
        local original = Vector(id * 1000, id * 500, 384)
        markers["player_" .. id .. "_builder_spawn"] = marker(original)
        local spawn = assert(context.resolve_builder_spawn(id))
        assert(spawn.position == original and spawn.source == "hammer_marker" and spawn.mode == nil)
    end
end
markers.player_1_builder_spawn = nil
assert(select(2, context.resolve_builder_spawn(1)) == "builder_spawn_marker_missing:player_1_builder_spawn")
markers.player_0_builder_spawn = nil
assert(context.resolve_builder_spawn(0).source == "legacy_coordinates", "normal legacy policy stays intact")

-- Exercise the real builder event/ownership chain. Fishing lands once, rests
-- without an update loop, and focuses the visible proxy rather than its hero.
local created, messages, identities, ready_events = {}, {}, {}, 0
local clear_space_calls = 0
package.loaded["visual/model_scale"] = { apply = function(unit, scale) unit.scale = scale end }
package.loaded["systems/builder_presentation_service"] = { init = function() end, apply = function() end, clear = function() end }
package.loaded["core/modifier_registry"] = { ensure = function(unit, name) unit.phase = name; return true end }
CustomGameEventManager = { Send_ServerToPlayer = function(_, player, name, payload)
    messages[#messages + 1] = { player = player.id, name = name, data = payload }
end }
CustomNetTables = { SetTableValue = function(_, name, key, data) identities[key] = data end }
local function unit(id, origin, owner)
    local value = { id = id, origin = origin, owner = owner }
    function value:IsNull() return self.removed == true end
    function value:entindex() return self.id end
    function value:GetAbsOrigin() return self.origin end
    function value:SetAbsOrigin(position) self.origin = position end
    function value:GetTeamNumber() return 2 end
    function value:GetPlayerOwnerID() return self.owner end
    function value:GetUnitName() return self.name or "npc_dota_hero_undying" end
    function value:SetPlayerID(player) self.owner = player end
    function value:SetOwner(player) self.player = player end
    function value:SetControllableByPlayer(player) self.control = player end
    function value:SetBaseMoveSpeed(speed) self.speed = speed end
    function value:SetModel(model) self.model = model end
    function value:SetOriginalModel(model) self.original = model end
    function value:SetHullRadius(radius) self.hull = radius end
    function value:Stop() self.stops = (self.stops or 0) + 1 end
    function value:SetAttackCapability(capability) self.attack = capability end
    function value:SetGold() end
    return value
end
CreateUnitByName = function(name, position, _, _, _, team)
    assert(team == 2)
    local builder = unit(100 + #created, position)
    builder.name = name
    created[#created + 1] = builder
    return builder
end
FindClearSpaceForUnit = function(value, position) clear_space_calls = clear_space_calls + 1; value.origin = position end
UTIL_Remove = function(value) value.removed = true end
local builders = require("systems/builder_service")
bus.reset(); context.init(); builders.init()
bus.subscribe(events.BUILDER_READY, function(payload)
    ready_events = ready_events + 1
    assert(context.is_owned_by(payload.player_id, payload.builder))
    assert(payload.spawn_source == "fishing_coordinates")
end)
mode = "fishing"
for id = 0, 3 do
    local payload = { player_id = id, hero = unit(id + 1, Vector(0, 0, -10000), id), team = 2 }
    bus.emit(events.HERO_READY, payload)
    bus.emit(events.HERO_READY, payload)
end
assert(#created == 4 and ready_events == 4 and clear_space_calls == 0)
local focus_count = 0
for _, message in ipairs(messages) do
    if message.name == "ui_camera_follow_hero" then
        focus_count = focus_count + 1
        local builder = created[message.player + 1]
        assert(message.data.entindex == builder.id and message.data.target_z == builder.origin.z)
        assert(message.data.target_x == positions[message.player].x and message.data.target_y == positions[message.player].y)
    end
end
assert(focus_count == 4, "one non-locking focus per player's visible builder")
for id = 0, 3 do
    local builder = created[id + 1]
    assert(builder.stops == 1 and builder.hull == 0 and builder.control == id)
    assert(identities["player_" .. id].entindex == builder.id)
    assert(bus.request(events.BUILDER_GET_REQUEST, { player_id = id }).builder == builder)
end

-- Run the actual addon startup and no-wall callbacks in a minimal engine
-- environment, keeping the existing HERO_READY -> online session signal.
local file = assert(io.open("scripts/vscripts/addon_game_mode.lua", "rb"))
local source = file:read("*a"); file:close()
local first = assert(source:find("local function is_fishing_mode()", 1, true))
local last = assert(source:find("local function on_hero_picked", first, true))
local pending, scheduled, defeats, placeholder, hero_ready = nil, 0, 0, 0, 0
local resumed, closed, connects, disconnects, ownership_cleanup = 0, 0, 0, 0, 0
local base_require = require
local env = setmetatable({
    scheduler = { after = function(_, callback) scheduled = scheduled + 1; pending = callback end },
    require = function(name)
        if name == "systems/player_context_service" then return {
            unregister_player = function(id)
                ownership_cleanup = ownership_cleanup + 1
                return context.unregister_player(id)
            end,
        } end
        if name == "systems/online_time_service" then return {
            resume_fishing = function(id) assert(id == 0); resumed = resumed + 1 end,
            disconnect = function(id) assert(id == 0); closed = closed + 1 end,
        } end
        if name == "systems/fishing_reward_service" then return {
            connect = function() end, disconnect = function() end,
        } end
        if name == "systems/building_system" then return { wall_for_player = function() return nil end } end
        if name == "systems/archive_endless_service" then return { can_rebuild_wall = function() return false end } end
        if name == "systems/startup_loading_service" then return {
            is_gameplay_ready = function() return true end, is_player_ready = function() return true end,
        } end
        return base_require(name)
    end,
    multiplayer_player_service = {
        resolve_player_id = function(keys) return keys.PlayerID, "fixture", 0 end,
        assign_to_survival_team = function() return true end,
        mark_connected = function() connects = connects + 1 end,
        mark_disconnected = function() disconnects = disconnects + 1 end,
        participating_player_ids = function() return { 0, 1, 2, 3 } end,
        defeat = function() defeats = defeats + 1 end,
        reject_defeated_unit = function() return false end,
    },
    hero_anchor_service = { register_placeholder = function(_, value) placeholder = placeholder + 1; value.hidden = true end },
    event_bus = { emit = function(name) assert(name == events.HERO_READY); hero_ready = hero_ready + 1 end },
    events = events, pending_loading_heroes = {}, ready_hero_entindex_by_player = {},
    replacing_forced_hero = {}, unit_display_names = { by_id = {} },
    ui_snapshot_service = { publish_player = function() end },
}, { __index = _G })
local chunk = assert(loadstring(source:sub(first, last - 1)
    .. "\nreturn schedule_unbuilt_wall_defeat_check,initialize_survival_hero,on_player_connected,on_player_disconnected"))
setfenv(chunk, env)
local schedule, initialize, connect, disconnect = chunk()
mode = "fishing"; disconnect({PlayerID = 0}); connect({PlayerID = 0})
assert(closed == 1 and resumed == 1 and connects == 1 and disconnects == 1)
assert(ownership_cleanup == 0, "fishing reconnect grace retains registered assets")
assert(context.owner_player_id(created[1], true) == 0, "fishing reconnect grace preserves the existing builder's authoritative ownership")
mode = "standard"; connect({PlayerID = 0}); disconnect({PlayerID = 0})
assert(resumed == 1 and closed == 2 and connects == 2 and disconnects == 2)
assert(ownership_cleanup == 1, "ordinary disconnect cleanup is unchanged")
mode = "fishing"; schedule(); assert(scheduled == 0)
local before = clear_space_calls
initialize(unit(500, Vector(100, 200, 384), 0))
assert(clear_space_calls == before and placeholder == 1 and hero_ready == 1,
    "fishing preserves readiness/online hooks without teleporting the hidden carrier through 0,0")
mode = "standard"; schedule(); assert(scheduled == 1)
mode = "fishing"; pending(); assert(defeats == 0, "queued normal callback must recheck shared mode")
mode = "pure"; schedule(); pending(); assert(defeats == 4, "regular no-wall defeat stays unchanged")
initialize(unit(501, Vector(100, 200, 384), 1))
assert(clear_space_calls == before + 1 and hero_ready == 2)
print("IDLE_FISHING_SPAWN_PASS: four safe slots, terrain/navigation guards, bounded marker fallback, normal spawns, builder ownership/idle/focus, hidden-hero readiness, reconnect hooks and no-wall guard")
