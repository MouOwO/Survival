-- Real HERO_READY -> builder/context -> authored cold courts. Only native
-- entities, terrain availability, presentation and scheduling are fixtures.
package.path = "scripts/vscripts/?.lua;" .. package.path
Vector = function(x, y, z) return {x = x, y = y, z = z or 0} end
GetMapName = function() return "template_map" end
DOTA_TEAM_GOODGUYS = 2
package.loaded["systems/match_setup_service"] = {get_mode = function() return "cold" end}
package.loaded["core/test_access_policy"] = {enabled = function() return false end}
package.loaded["visual/model_scale"] = {apply = function() end}
package.loaded["systems/builder_presentation_service"] = {init = function() end,
    apply = function() end, clear = function() end}
package.loaded["core/modifier_registry"] = {ensure = function() end}
local tasks, created, ready, messages, identity = {}, {}, {}, {}, {}
package.loaded["core/scheduler"] = {every = function(interval, callback, key)
    assert(interval == 1 or interval == 0.1)
    assert(not tasks[key], "a player owns only one pending spawn retry")
    tasks[key] = callback
end, cancel = function(key) tasks[key] = nil end}
PlayerResource = {GetPlayer = function(_, id) return {id = id} end}
CustomGameEventManager = {Send_ServerToPlayer = function(_, player, name, payload)
    messages[#messages + 1] = {player = player.id, name = name, payload = payload}
end}
CustomNetTables = {SetTableValue = function(_, _, key, value) identity[key] = value end}
local serial = 0
CreateUnitByName = function(name, point, _, _, _, team)
    serial = serial + 1
    local unit = {id = serial, position = point, team = team, name = name}
    function unit:IsNull() return self.removed == true end
    function unit:entindex() return self.id end
    function unit:GetAbsOrigin() return self.position end
    function unit:GetUnitName() return self.name end
    function unit:GetTeamNumber() return self.team end
    function unit:SetPlayerID(id) self.player_id = id end
    function unit:SetOwner(owner) self.owner = owner end
    function unit:SetControllableByPlayer(id) self.controller = id end
    function unit:SetHullRadius(radius) self.hull = radius end
    function unit:SetAbsOrigin(position) self.position = position end
    function unit:Stop() end
    for _, method in ipairs({"SetBaseMoveSpeed", "SetModel", "SetOriginalModel"}) do
        unit[method] = function() end
    end
    created[#created + 1] = unit
    return unit
end
UTIL_Remove = function(unit) unit.removed = true end
FindClearSpaceForUnit = function() error("dedicated builder must not escape through clear-space") end
local config = require("config/mode_spawn_config").modes.cold
local player_points = {{14336, 13056}, {10752, 10496}, {14336, 7936}, {10752, 5376}}
local marker_positions = {[config.center_marker] = Vector(12672, 9472, 16)}
for id = 0, 3 do
    local point = player_points[id + 1]
    marker_positions[config.player_markers[id]] = Vector(point[1], point[2], 144)
end
local terrain_ready, blocked, missing = false, false, nil
Entities = {FindByName = function(_, _, name)
    if name == missing then return nil end
    local point = marker_positions[name]
    return point and {IsNull = function() return false end, GetAbsOrigin = function() return point end}
end}
local function player_marker(point)
    for _, coordinate in ipairs(player_points) do
        if point.x == coordinate[1] and point.y == coordinate[2] then return true end
    end
    return false
end
GetGroundPosition = function(point)
    -- The marker can resolve before the sampled construction terrain becomes
    -- available. This yields the exact observed landing-outside-cells error.
    -- Native read-only probe: the actual cold snow surface is Z=256 for
    -- input Z=0/128/384/1024. Keep this independent of the configured value
    -- so the old 128-height configuration really fails the regression.
    local z = (terrain_ready or player_marker(point)) and 256 or 0
    return Vector(point.x, point.y, z)
end
GridNav = {IsTraversable = function() return true end,
    IsBlocked = function(_, point) return blocked and player_marker(point) end}
local bus, events = require("core/event_bus"), require("core/events")
local context = require("systems/player_context_service")
local regions = require("systems/rich_region_service")
local builder = require("systems/builder_service")
local function hero()
    return {IsNull = function() return false end}
end
local function begin()
    tasks, created, ready, messages, identity = {}, {}, {}, {}, {}
    terrain_ready, blocked, missing = false, false, nil
    bus.reset(); context.init(); regions.init(); builder.init()
    bus.subscribe(events.BUILDER_READY, function(payload) ready[#ready + 1] = payload end)
end
local function request(id)
    bus.emit(events.HERO_READY, {player_id = id, hero = hero(), team = 2})
end
local function run(id)
    local key = "builder_spawn_retry:" .. id
    local callback = assert(tasks[key], "missing bounded cold spawn retry")
    local again = callback()
    if again == false and tasks[key] == callback then tasks[key] = nil end
    return again
end
local function get(id) return bus.request(events.BUILDER_GET_REQUEST, {player_id = id}) end

-- Native receipt confirms stable 256-height snow. A 128-height config must
-- fail here even when terrain/navigation are already fully available.
begin()
terrain_ready = true
for id = 0, 3 do
    request(id)
    local result = get(id)
    assert(result.ok and result.builder.position.z == 256,
        "native 256-height cold snow must admit the player's builder")
    assert(not tasks["builder_spawn_retry:" .. id], "steady valid terrain needs no retry")
end
assert(#created == 4 and #ready == 4)

begin()
for id = 0, 3 do request(id) end
assert(#created == 0 and #ready == 0)
for id = 0, 3 do
    assert(not get(id).ok and tasks["builder_spawn_retry:" .. id],
        "transient cold setup must schedule a bounded retry")
end
terrain_ready = true
for id = 0, 3 do
    assert(run(id) == false)
    local result = get(id)
    local expected = player_points[id + 1]
    assert(result.ok and result.builder.controller == id and result.builder.hull == 0)
    assert(context.owner_player_id(result.builder) == id)
    assert(result.builder.position.x == expected[1] and result.builder.position.y == expected[2]
        and result.builder.position.z == 256)
    request(id)
    assert(get(id).builder == result.builder, "duplicate readiness must not replace a registered builder")
end
assert(#created == 4 and #ready == 4)
assert(not regions.retry_failed_initialization("mode_player_landing_outside_cells:" .. config.player_markers[0]),
    "a stale retry must not reset existing regions or attached owners")
assert(regions.validate_building_footprint(0, 14208, 12928, 14464, 13184))
assert(not regions.validate_building_footprint(0, 12608, 9408, 12736, 9536),
    "retrying builders never admits the central road as a court")

begin()
request(0)
for attempt = 1, 4 do
    assert(run(0) == (attempt < 4), "failed spawn retries have a finite four-second budget")
end
assert(not tasks["builder_spawn_retry:0"] and #created == 0 and not get(0).ok,
    "persistent invalid terrain cannot produce a builder at an unchecked fallback")

begin()
terrain_ready, blocked = true, true
request(0)
assert(#created == 0)
blocked = false
assert(run(0) == false and get(0).ok, "temporary marker obstruction can recover without a second HERO_READY")

begin()
request(0)
local abandoned = assert(tasks["builder_spawn_retry:0"])
bus.emit(events.PLAYER_DISCONNECTED, {player_id = 0})
terrain_ready = true
assert(not tasks["builder_spawn_retry:0"] and abandoned() == false and #created == 0,
    "disconnect cancels late builder births")

begin()
request(0)
local previous_world = assert(tasks["builder_spawn_retry:0"])
begin()
terrain_ready = true
assert(previous_world() == false and #created == 0,
    "world initialization invalidates a previous world's pending spawn")

begin()
missing = config.player_markers[0]
request(0)
assert(#created == 0 and not tasks["builder_spawn_retry:0"] and not get(0).ok,
    "a structurally missing cold marker still rejects ordinary/legacy fallbacks")
print("COLD_BUILDER_SPAWN_PASS: real four-player HERO_READY/ownership chain, transient cell/nav recovery, bounded permanent failure, idempotency, disconnect cancellation, no road/legacy fallback")
