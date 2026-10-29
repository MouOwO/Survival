-- Actual tree lifecycle, region discovery and grid collision/occupancy code;
-- only engine entities/navigation and rendering/feedback are doubled.
package.path = "scripts/vscripts/?.lua;" .. package.path
-- The placement fixture begins after admission; it does not test account gates.
package.loaded["core/test_access_policy"] = {enabled = function() return false end}
local vector_meta = { __add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end }
Vector = function(x, y, z) return setmetatable({x = x, y = y, z = z or 0}, vector_meta) end
DOTA_TEAM_GOODGUYS, DOTA_TEAM_BADGUYS, DOTA_UNIT_CAP_NO_ATTACK = 2, 3, 0
DOTA_UNIT_TARGET_TEAM_BOTH, DOTA_UNIT_TARGET_HERO, DOTA_UNIT_TARGET_BASIC = 3, 1, 2
DOTA_UNIT_TARGET_BUILDING, DOTA_UNIT_TARGET_FLAG_INVULNERABLE, FIND_ANY_ORDER = 4, 1, 0
local mode, blocked_all, entities, next_id, ground_height = nil, false, {}, 100, 128
package.loaded["systems/match_setup_service"] = {get_mode = function() return mode end}
local slots = {[0] = "east", [1] = "south", [2] = "west", [3] = "north"}
package.loaded["systems/player_context_service"] = {slot = function(id) return slots[id] and {slot_id = slots[id]} end}
package.loaded["visual/model_scale"] = {apply = function() end}
package.loaded["core/particle_manager"] = {show_green_number = function() end}
package.loaded["core/modifier_registry"] = {ensure = function() end}
package.loaded["systems/rogue_effect_state_service"] = {numeric = function() return 0 end}
package.loaded["systems/harvest_feedback_service"] = {reset = function() end, add = function() end}
package.loaded["systems/registered_wave_lane_view"] = {append = function(rows) return rows end}
package.loaded["systems/wall_navigation_service"] = {original_nav = function() end}
package.loaded["systems/forbidden_region_service"] = {validate_building_footprint = function() return true end}
package.loaded["config/grid_placement_config"] = {cell_size = 64, minimum_footprint = {x = 2, y = 2},
    build_bounds = {min_x = -20000, min_y = -20000, max_x = 20000, max_y = 20000},
    forbidden_markers = {}, max_height_delta = 48, build_ground_height = 384, build_ground_height_tolerance = 16}
local marker = {IsNull = function() return false end, GetAbsOrigin = function() return Vector(-2752, -9984, 128) end}
Entities = {FindByName = function(_, _, name) assert(name == "rich_start"); return marker end}
local function in_rect(x, y, x1, y1, x2, y2) return x >= x1 and x <= x2 and y >= y1 and y <= y2 end
GridNav = {
    IsTraversable = function(_, position)
        if mode ~= "rich" then return true end
        local x, y = math.floor(position.x / 64), math.floor(position.y / 64)
        if x == 0 and y == -157 then return false end -- An interior red navigation hole.
        return in_rect(x, y, -17, -177, 16, -138) or in_rect(x, y, -63, -224, -26, -187)
            or in_rect(x, y, -106, -178, -71, -138) or in_rect(x, y, -64, -129, -26, -94)
    end,
    IsBlocked = function() return blocked_all end,
    IsNearbyTree = function() return false end,
}
GetGroundHeight = function() return ground_height end
GetGroundPosition = function(position) return Vector(position.x, position.y, ground_height) end
FindUnitsInRadius = function()
    local result = {}; for _, unit in pairs(entities) do if not unit.removed then result[#result + 1] = unit end end
    return result
end
EntIndexToHScript = function(index) return entities[index] end
GameRules = {GetGameTime = function() return 1 end}
RandomFloat = function() return 100 end
UTIL_Remove = function(unit) unit.removed = true end
local function unit(position, name, hull)
    next_id = next_id + 1
    local value = {index = next_id, position = position, name = name, health = 100, hull = hull or 0, moves = 0}
    function value:IsNull() return self.removed == true end
    function value:IsAlive() return not self.removed end
    function value:entindex() return self.index end
    function value:GetAbsOrigin() return self.position end
    function value:SetAbsOrigin(point) self.position = point; self.moves = self.moves + 1 end
    function value:GetTeamNumber() return 2 end
    function value:GetHullRadius() return self.hull end
    function value:GetUnitName() return self.name end
    function value:IsRealHero() return false end
    function value:HasModifier() return false end
    function value:SetHealth(amount) self.health = amount end
    function value:GetHealth() return self.health end
    function value:SetMaxHealth(amount) self.maximum = amount end
    function value:GetMaxHealth() return self.maximum end
    for _, setter in ipairs({"SetBaseMaxHealth", "SetPhysicalArmorBaseValue", "SetModel", "SetOriginalModel", "SetAttackCapability"}) do
        value[setter] = function() end
    end
    entities[value.index] = value
    return value
end
local created = {}
CreateUnitByName = function(name, position)
    local value = unit(position, name); created[#created + 1] = value; return value
end
local original_print = print
print = function(message) if tostring(message):find("handler error") then error(message) end end
local bus, events = require("core/event_bus"), require("core/events")
local grid, regions = require("systems/grid_placement_system"), require("systems/rich_region_service")
local trees, config = require("systems/tree_system"), require("config/tree_config")
local edge_anchors = {east = {832, -10048}, south = {-2816, -14080},
    west = {-6528, -10048}, north = {-2816, -6208}}
for id, point in pairs(edge_anchors) do
    assert(config.rich_spawn_regions[id][1].x == point[1] and config.rich_spawn_regions[id][1].y == point[2],
        "rich tree anchors stay at the approved outer-edge locations")
end
local fixed_points = {}
for id, points in pairs(config.spawn_regions) do
    fixed_points[id] = {}; for index, point in ipairs(points) do fixed_points[id][index] = {point.x, point.y, point.z} end
end
local queries, wood, by_player = 0, 0, {}
local original_request = bus.request
bus.request = function(name, payload)
    if name == events.GRID_CAN_PLACE_REQUEST then
        queries = queries + 1
        assert(payload.footprint.x == 2 and payload.footprint.y == 2 and payload.player_id ~= nil)
    end
    return original_request(name, payload)
end
local function init()
    bus.reset(); grid.init(); regions.init(); trees.init()
    bus.handle_request(events.RESOURCE_ADD_REQUEST, function(payload) wood = wood + payload.wood; return {ok = true} end)
    bus.subscribe(events.TREE_SPAWNED, function(payload) by_player[payload.player_id] = entities[payload.entindex] end)
end
local function cell_occupants(point, expected)
    local footprint = trees._tree_grid_for_test(point)
    for x = footprint.grid_x, footprint.grid_x + 1 do
        for y = footprint.grid_y, footprint.grid_y + 1 do
            assert(grid.occupant_at_position(Vector((x + 0.5) * 64, (y + 0.5) * 64, 128)) == expected)
        end
    end
end
local function build_city(id, position)
    local city = unit(position, "main_city", 128); city.survival_player_id = id; city.survival_is_building = true
    bus.emit(events.BUILDING_CREATED, {building_id = "main_city", player_id = id, unit = city})
    return city
end
init() -- Real startup initializes before the mode is selected.
for _, points in pairs(config.spawn_regions) do cell_occupants(points[1], "survival_tree_reserved") end
mode = "rich"
local cities, blocker = {}, nil
for id = 0, 3 do
    local spawn = assert(regions.resolve_spawn(id, slots[id]))
    if id == 0 then
        local point = config.rich_spawn_regions.east[1]
        blocker = unit(Vector(point.x, point.y, ground_height), "standing_unit", 32)
    end
    cities[id] = build_city(id, spawn.position)
    local tree = assert(by_player[id], "each rich city gets one resource tree")
    assert(tree.survival_tree_owner_id == id)
    assert(regions.validate_position(id, tree:GetAbsOrigin()))
    local footprint = trees._tree_grid_for_test(tree:GetAbsOrigin())
    assert(regions.validate_building_footprint(id, footprint.grid_x * 64, footprint.grid_y * 64,
        (footprint.grid_x + 2) * 64, (footprint.grid_y + 2) * 64))
    local point = tree:GetAbsOrigin()
    local expected = config.rich_spawn_regions[slots[id]][id == 0 and 2 or 1]
    assert(point.x == expected.x and point.y == expected.y, "trees use fixed outer-edge sockets, not city-relative positions")
    cell_occupants(point, tree:entindex())
    local old_queries, old_created = queries, #created
    bus.emit(events.BUILDING_CREATED, {building_id = "main_city", player_id = id, unit = cities[id]})
    assert(queries == old_queries and #created == old_created, "duplicate city events cannot relocate or duplicate a tree")
end
assert(#created == 4 and queries > 4 and wood == 0, "placement does not create resource income")
for _, points in pairs(config.spawn_regions) do cell_occupants(points[1], nil) end
local function placement(point, owner, policy_only)
    return bus.request(events.GRID_CAN_PLACE_REQUEST, {player_id = owner, position = point,
        footprint = {x = 2, y = 2}, policy_only = policy_only, team = 2})
end
for _, policy_only in ipairs({false, true}) do
    assert(not placement(cities[1]:GetAbsOrigin(), 0, policy_only).ok, "real grid rejects another player's component, including policy-only queries")
    assert(not placement(Vector(-17 * 64, -150 * 64, 128), 0, policy_only).ok, "a footprint crossing the own-component boundary is rejected")
    assert(not placement(Vector(64, -156 * 64, 128), 0, policy_only).ok, "a footprint touching an interior red hole is rejected")
end
assert(placement(Vector(12 * 64, -142 * 64, 128), 0).ok, "rich ground at height 128 remains buildable")
ground_height = 171
assert(placement(Vector(12 * 64, -142 * 64, 171), 0).ok, "rich ground does not inherit the ordinary height-384 whitelist")
ground_height = 128
local tree = by_player[0]
local position, moves = tree:GetAbsOrigin(), tree.moves
tree.survival_tree_depleted_callback(tree)
assert(tree.survival_tree_level == 2 and tree:GetAbsOrigin() == position and tree.moves == moves, "level progression never moves the tree")
local worker = unit(cities[0]:GetAbsOrigin(), "npc_survival_lumberjack")
bus.emit(events.TREE_HIT, {player_id = 0, attacker = worker, target = tree, source = "lumberjack", base_lumber_efficiency = 10})
assert(wood == 10 + trees._lumber_efficiency_buff_for_test(2) + config.rich_level2_reward.lumber_efficiency,
    "normal per-level harvest and the existing rich Lv2 reward are unchanged")
local income = wood
bus.emit(events.TREE_HIT, {player_id = 0, attacker = cities[0], target = tree, source = "lumberjack", base_lumber_efficiency = 100})
assert(wood == income, "a building does not gain a new harvest bypass")
bus.emit(events.PLAYER_DISCONNECTED, {player_id = 0})
assert(tree.removed)
cell_occupants(position, nil) -- Rich slot 1 does not become an ordinary permanent reservation.
bus.emit(events.TREE_HIT, {player_id = 0, attacker = worker, target = tree, source = "lumberjack", base_lumber_efficiency = 100})
assert(wood == income, "a retired tree cannot pay out")
blocked_all = true
local count = #created
bus.emit(events.BUILDING_CREATED, {building_id = "main_city", player_id = 0, unit = cities[0]})
assert(#created == count, "cached membership cannot bypass newly blocked navigation or fall back to ordinary sockets")
blocked_all = false; blocker.removed = true
bus.emit(events.BUILDING_CREATED, {building_id = "main_city", player_id = 0, unit = cities[0]})
assert(#created == count + 1 and by_player[0] ~= tree and by_player[0].survival_tree_level == 1)

-- A different city location cannot move the patch. Shared courts use each of
-- its four authored sockets once and reuse only the released owner's slot.
entities = {}; created = {}; by_player = {}; queries = 0
slots = {[0] = "east", [1] = "east", [2] = "east", [3] = "east"}
init()
for id = 0, 3 do
    build_city(id, Vector(-640 + id * 128, -9408, 128))
    local tree = assert(by_player[id], "four players in one court each retain their own tree")
    local expected = config.rich_spawn_regions.east[id + 1]
    assert(tree:GetAbsOrigin().x == expected.x and tree:GetAbsOrigin().y == expected.y)
    cell_occupants(tree:GetAbsOrigin(), tree:entindex())
end
local freed = by_player[1]:GetAbsOrigin()
bus.emit(events.PLAYER_DISCONNECTED, {player_id = 1})
cell_occupants(freed, nil)
build_city(1, Vector(0, -10880, 128))
assert(by_player[1]:GetAbsOrigin().x == freed.x and by_player[1]:GetAbsOrigin().y == freed.y)

-- The ordinary mode keeps its authored sockets and primary reservation policy.
mode = "standard"; entities = {}; created = {}; by_player = {}; queries = 0
init()
local point = config.spawn_regions.northeast[1]
build_city(0, Vector(math.max(1, config.region_center.x + 100), math.max(1, config.region_center.y + 100), 128))
local ordinary = assert(by_player[0])
assert(ordinary:GetAbsOrigin().x == point.x and ordinary:GetAbsOrigin().y == point.y and queries == 0)
bus.emit(events.PLAYER_DISCONNECTED, {player_id = 0})
cell_occupants(point, "survival_tree_reserved")
local legacy = placement(Vector(1024, 1024, 128), 0)
assert(not legacy.ok and legacy.error == "terrain_not_build_level", "ordinary mode retains its height-384 restriction")
ground_height = 384
assert(placement(Vector(1024, 1024, 384), 0).ok)
for id, points in pairs(config.spawn_regions) do
    for index, fixed in ipairs(fixed_points[id]) do
        assert(points[index].x == fixed[1] and points[index].y == fixed[2] and points[index].z == fixed[3], "rich mode must not mutate global ordinary sockets")
    end
end
print = original_print
print("RICH_TREE_SPAWN_PASS: fixed outer-edge patches, city-independent positions, four shared-court slots, live collision/full footprint, release/rejoin, unchanged income and ordinary reservations")
