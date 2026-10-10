-- Run from the addon root: lua tools/test_archive_hub_placement.lua
package.path = "scripts/vscripts/?.lua;" .. package.path

local vector = function(x, y, z) return {x = x, y = y, z = z} end
Vector = vector
local function entity(x, y, z)
    return {IsNull = function() return false end,
        GetAbsOrigin = function() return vector(x, y, z) end}
end
package.loaded["core/event_bus"] = {request = function() return {ok = true} end}
package.loaded["core/events"] = {GRID_CAN_PLACE_REQUEST = "can_place"}
local placement = require("systems/archive_hub_placement")
local markers, walls, marker_lookups, portal_lookups, nav_queries
local rule = {building_anchor = "player_wall", building_spacing = 240, building_offset_y = 360}
local context = {slot = function(id) return {builder_spawn_marker = "player_" .. id .. "_builder_spawn"} end}
local wave = {get_player_spawn_marker = function(id)
    portal_lookups = portal_lookups + 1
    return entity(id * 10000, -5000, 384)
end}
local function reset()
    markers, walls, marker_lookups = {}, {}, {}
    portal_lookups, nav_queries = 0, 0
    rule.building_anchor = "player_wall"
    package.loaded["core/event_bus"].request = function() return {ok = true} end
    package.loaded["systems/building_system"] = {wall_for_player = function(id) return walls[id] end}
    Entities = {FindByName = function(_, _, name)
        marker_lookups[#marker_lookups + 1] = name
        return markers[name]
    end}
    GetGroundPosition = function(p) return vector(p.x, p.y, 384) end
    GridNav = {IsTraversable = function() nav_queries = nav_queries + 1; return true end,
        IsBlocked = function() return false end}
end
local function same(p, x, y, z)
    assert(p and p.x == x and p.y == y and p.z == z, "unexpected hub position")
end

-- Each player's three hubs use their own live wall and never query old
-- platform/portal markers, even when those markers exist and are walkable.
reset()
for id = 0, 3 do
    walls[id] = entity(id * 3000, 1000, 384)
    markers["player_" .. id .. "_builder_spawn"] = entity(id * 3000, 0, 384)
    for index = 1, 3 do
        markers["player_" .. id .. "_archive_hub_" .. index] = entity(id * 10000, -4500, 384)
        local position, source = placement.resolve(id, index, rule, context, wave, {})
        same(position, id * 3000 + (index - 2) * 240, 1360, 384)
        assert(source == "player_wall")
    end
end
assert(portal_lookups == 0 and #marker_lookups == 0)

-- A removed, unbuilt, or missing wall can use only this player's builder
-- lawn. No other player's marker can become a fallback.
reset()
walls[2] = {IsNull = function() return true end}
markers.player_0_builder_spawn = entity(-800, -900, 384)
markers.player_2_builder_spawn = entity(800, 900, 22)
for index = 1, 3 do
    local position, source = placement.resolve(2, index, rule, context, wave, {})
    same(position, 800 + (index - 2) * 240, 1260, 384)
    assert(source == "builder_spawn")
end
assert(portal_lookups == 0 and #marker_lookups == 3)
for _, name in ipairs(marker_lookups) do assert(name == "player_2_builder_spawn") end

-- This was the portal-spawn bug: both base anchors fail, but stale platform
-- markers and the wave portal remain usable. Wait instead of spawning there.
for _, failure in ipairs({"missing", "blocked", "occupied"}) do
    reset()
    for id = 0, 3 do
        markers["player_" .. id .. "_archive_hub_1"] = entity(id * 10000, -4500, 384)
        if failure ~= "missing" then
            walls[id] = entity(id * 3000, 1000, 384)
            markers["player_" .. id .. "_builder_spawn"] = entity(id * 3000, 0, 384)
        end
    end
    GridNav.IsTraversable = function(_, p) nav_queries = nav_queries + 1; return p.y < -4000 end
    package.loaded["core/event_bus"].request = function(_, payload)
        return {ok = failure ~= "occupied" or payload.position.y < -4000}
    end
    for id = 0, 3 do
        local position, reason = placement.resolve(id, 1, rule, context, wave, {})
        assert(position == nil and reason == "safe_hub_position_missing")
    end
    assert(portal_lookups == 0 and #marker_lookups == 4)
    for id = 0, 3 do assert(marker_lookups[id + 1] == "player_" .. id .. "_builder_spawn") end
    if failure == "blocked" then assert(nav_queries == 4 * 50, "base search must remain bounded") end
end

-- An absent slot API also cannot open the portal fallback in wall mode.
reset()
local position, reason = placement.resolve(1, 1, rule, {}, wave, {})
assert(position == nil and reason == "safe_hub_position_missing")
assert(portal_lookups == 0 and #marker_lookups == 0)

-- Legacy configs retain their dedicated placement contract. With no nav API,
-- their old wave offsets also remain unchanged.
reset()
rule.building_anchor = nil
markers.player_3_archive_hub_2 = entity(200, 300, 400)
position, reason = placement.resolve(3, 2, rule, context, wave, {})
same(position, 200, 300, 384)
assert(reason == "archive_marker" and portal_lookups == 0)
GridNav = nil
position, reason = placement.resolve(3, 1, rule, context, wave, {})
same(position, 29760, -4640, 384)
assert(reason == "legacy_wave_marker" and portal_lookups == 1)

print("PASS archive hub placement: four-player wall/builder ownership, missing/blocked/occupied base refuses portals, bounded search, legacy compatibility")
