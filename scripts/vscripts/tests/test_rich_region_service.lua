package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path

Vector = function(x, y, z) return { x = x, y = y, z = z or 0 } end
local mode, marker_enabled = "standard", true
package.loaded["systems/match_setup_service"] = { get_mode = function() return mode end }
local slot_by_player = { [0] = "east", [3] = "south", [7] = "west", [11] = "north" }
package.loaded["systems/player_context_service"] = { slot = function(id)
    return slot_by_player[id] and { slot_id = slot_by_player[id] } or nil
end }
local tasks, schedules = {}, 0
package.loaded["core/scheduler"] = {
    every = function(interval, callback, id)
        assert(interval == 0.10 and not tasks[id], "one shared builder guard")
        tasks[id], schedules = callback, schedules + 1
    end,
    cancel = function(id) tasks[id] = nil end,
}
local marker = { IsNull = function() return false end, GetAbsOrigin = function() return Vector(-2752, -9984, 171) end }
Entities = { FindByName = function(_, _, name) assert(name == "rich_start"); return marker_enabled and marker or nil end }
local cells = {}
local function key(x, y) return x .. ":" .. y end
local function rect(x1, y1, x2, y2)
    for x = x1, x2 do for y = y1, y2 do cells[key(x, y)] = true end end
end
local function four_islands()
    cells = {}
    rect(-17, -177, 16, -138) -- east
    rect(-63, -224, -26, -187) -- south
    rect(-106, -178, -71, -138) -- west
    rect(-64, -129, -26, -94) -- north
    cells[key(0, -157)] = nil -- one red hole inside the eastern lawn
end
four_islands()
local calls, live_blocked = 0, {}
local function nav_id(position) return key(math.floor(position.x / 64), math.floor(position.y / 64)) end
GridNav = {
    IsTraversable = function(_, position) calls = calls + 1; return cells[nav_id(position)] == true end,
    IsBlocked = function(_, position) return live_blocked[nav_id(position)] == true end,
}
GetGroundPosition = function(position) return Vector(position.x, position.y, 128 + math.floor(position.x / 1024) % 2 * 8) end
local service = require("systems/rich_region_service")
service.init()
assert(service.validate_position(99, nil) and service.validate_building_footprint(nil), "legacy modes are unaffected")
assert(service.validate_order({ order_type = 1 }, {}))
assert(service.attach_builder(0, nil) and calls == 0 and schedules == 0, "no legacy navigation scans or guards")

mode = "rich"
local spawns, all_cells = {}, 0
for _, id in ipairs({ 0, 3, 7, 11 }) do
    local spawn = assert(service.resolve_spawn(id, slot_by_player[id]))
    assert(spawn.mode == "rich" and spawn.marker == "rich_start" and spawn.slot_id == slot_by_player[id])
    assert(spawn.source == "rich_region_navigation" and spawn.position.z >= 128)
    assert(service.validate_position(id, spawn.position))
    assert(not service.validate_position(id, marker:GetAbsOrigin()), "red central hub cannot be entered by builders")
    all_cells = all_cells + service.region(id).cell_count
    spawns[id] = spawn.position
end
assert(all_cells == 1360 - 1 + 1444 + 1476 + 1404)
assert(calls < 7000, "discover only the four local components once, including their boundary")
assert(not service.resolve_spawn(1), "player identifiers do not select regions by modulo")
assert(select(2, service.resolve_spawn(0, "north")) == "rich_player_slot_changed")
assert(not service.resolve_spawn(-1, "east"))
assert(service.center().x == -2752 and service.center().y == -9984)
local wave_spawns = {}
for _, id in ipairs({ 0, 3, 7, 11 }) do
    local spawn = assert(service.wave_spawn(id))
    wave_spawns[id] = spawn
    assert(service.validate_position(id, spawn))
    assert((spawn.x - spawns[id].x)^2 + (spawn.y - spawns[id].y)^2 >= 512^2)
    assert(service.validate_building_footprint(id, spawn.x - 128, spawn.y - 128, spawn.x + 128, spawn.y + 128),
        "wave landing stays at least two native cells inside its own island")
    local center = service.center()
    assert((spawn.x-center.x)^2 + (spawn.y-center.y)^2 < (spawns[id].x-center.x)^2 + (spawns[id].y-center.y)^2,
        "waves enter from the inner edge facing the central hub")
end
local cached_wave_calls = calls
assert(service.wave_spawn(0).x == wave_spawns[0].x and calls == cached_wave_calls + 1,
    "subsequent waves check one cached landing instead of scanning the island")
live_blocked[nav_id(wave_spawns[0])] = true
local alternate_wave = assert(service.wave_spawn(0))
assert(nav_id(alternate_wave) ~= nav_id(wave_spawns[0]) and service.validate_position(0, alternate_wave))
live_blocked = {}
for id, position in pairs(spawns) do
    for other_id, other in pairs(spawns) do
        assert(service.validate_position(id, other) == (id == other_id), "four non-contiguous player ids remain isolated")
    end
end

assert(service.validate_building_footprint(0, -640, -10624, -512, -10496))
assert(not service.validate_building_footprint(0, -64, -10112, 128, -9920), "interior red hole fails even when corners are legal")
assert(not service.validate_building_footprint(0, -2800, -10000, -2700, -9900), "red center cannot be built")
assert(not service.validate_building_footprint(0, -4400, -11000, -4300, -10900), "wrong-region cells cannot be built")
assert(not service.validate_building_footprint(0, 0/0, 0, 64, 64))

local entities = {}
EntIndexToHScript = function(id) return entities[id] end
DOTA_UNIT_ORDER_MOVE_TO_POSITION, DOTA_UNIT_ORDER_MOVE_TO_TARGET = 1, 2
DOTA_UNIT_ORDER_ATTACK_MOVE, DOTA_UNIT_ORDER_ATTACK_TARGET = 3, 4
DOTA_UNIT_ORDER_CAST_POSITION, DOTA_UNIT_ORDER_CAST_TARGET = 5, 6
DOTA_UNIT_ORDER_CAST_TARGET_TREE, DOTA_UNIT_ORDER_PICKUP_ITEM = 8, 16
DOTA_UNIT_ORDER_PICKUP_RUNE, DOTA_UNIT_ORDER_PATROL = 17, 31
local function builder(id)
    local unit = { survival_builder_id = "default_builder", survival_player_id = id, origin = spawns[id], stops = 0 }
    function unit:IsNull() return self.removed == true end
    function unit:GetAbsOrigin() return self.origin end
    function unit:SetOrigin(position) self.origin = position end
    function unit:Stop() self.stops = self.stops + 1 end
    return unit
end
local units = {}
for _, id in ipairs({ 0, 3, 7, 11 }) do
    units[id] = builder(id)
    assert(service.attach_builder(id, units[id]))
end
assert(schedules == 1, "four builders share one 10 Hz guard")
assert(not service.attach_builder(3, units[0]), "ownership must match")
local monster = { IsNull = function() return false end }
local outside = spawns[3]
assert(service.validate_order({ order_type = 1, position_x = outside.x, position_y = outside.y }, { monster }))
for _, order in ipairs({ 1, 3, 5, 31 }) do
    assert(not service.validate_order({ order_type = order, position_x = outside.x, position_y = outside.y }, { units[0] }))
    assert(service.validate_order({ order_type = order, position_x = spawns[0].x, position_y = spawns[0].y }, { units[0] }))
end
entities[90] = { IsNull = function() return false end, GetAbsOrigin = function(self) return self.origin end, origin = outside }
for _, order in ipairs({ 2, 4, 6, 8, 16, 17 }) do
    assert(not service.validate_order({ order_type = order, entindex_target = 90 }, { units[0] }))
end
entities[90].origin = spawns[0]
assert(service.validate_order({ order_type = 2, entindex_target = 90 }, { units[0] }))
entities[90].origin = outside
local before = calls
assert(service.guard() and units[0].stops == 1, "moving follow target is stopped before the builder crosses")
units[0].origin = spawns[3] -- scripted teleport / displacement bypassing an order
assert(service.guard() and units[0].stops == 2 and units[0].origin.x == spawns[0].x)
for i = 1, 100 do
    assert(service.guard())
    assert(service.validate_cell(7, spawns[7]))
    assert(service.validate_building_footprint(0, -640, -10624, -512, -10496))
end
assert(calls == before, "steady-state membership, orders, building checks and guards never rescan navigation")

-- New buildings change live navigation but must not shrink or reassign the
-- authored island. A blocked relanding can choose another cached island cell.
live_blocked[nav_id(spawns[0])] = true
local moved = assert(service.resolve_spawn(0))
assert(nav_id(moved.position) ~= nav_id(spawns[0]) and service.validate_position(0, moved.position))
assert(service.region(0).cell_count == 1359)
live_blocked = {}
for id, unit in pairs(units) do service.detach_builder(id, unit) end
assert(service.guard() == false)

local function reset() service.init(); four_islands(); marker_enabled = true; mode = "rich" end
reset(); marker_enabled = false
assert(select(2, service.resolve_spawn(0, "east")) == "rich_start_missing")
marker_enabled = true
assert(select(2, service.resolve_spawn(0, "east")) == "rich_start_missing", "failed map contract is stable until world reset")
reset(); local saved_nav = GridNav; GridNav = nil
assert(select(2, service.resolve_spawn(0, "east")) == "rich_navigation_unavailable")
GridNav = saved_nav
reset(); rect(-71, -156, -17, -156) -- accidentally open center connects east/west
assert(select(2, service.resolve_spawn(0, "east")) == "rich_regions_connected:west")
reset(); for x = -64, -26 do for y = -129, -94 do cells[key(x, y)] = nil end end
assert(select(2, service.resolve_spawn(0, "east")) == "rich_region_missing:north")
reset(); local saved_ground = GetGroundPosition; GetGroundPosition = function() return Vector(0, 0, 0/0) end
assert(select(2, service.resolve_spawn(0, "east")) == "rich_ground_invalid:east")
GetGroundPosition = saved_ground
reset(); mode = "pure"
assert(service.guard() == false and service.validate_position(0, nil))
assert(next(tasks) == nil)

print("rich region service: PASS (four native regions, sparse players, full footprints, follow orders, teleport guard, cached cost)")
