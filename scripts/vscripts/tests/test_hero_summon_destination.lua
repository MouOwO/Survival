package.path = "scripts/vscripts/?.lua;" .. package.path
local definitions = {rows = {}}
package.loaded["config/generated/build_forbidden_regions"] = definitions
Vector = function(x, y, z) return {x = x, y = y, z = z or 0} end
DOTA_TEAM_GOODGUYS, DOTA_UNIT_TARGET_TEAM_BOTH = 2, 3
DOTA_UNIT_TARGET_HERO, DOTA_UNIT_TARGET_BASIC, DOTA_UNIT_TARGET_BUILDING = 1, 2, 4
DOTA_UNIT_TARGET_FLAG_INVULNERABLE, FIND_ANY_ORDER = 16, 0
local queries, ground_calls, navigation_calls, obstacles, listed
local height, traversable, blocked
Entities = {FindByName = function() error("fixed hero/training-room markers must not determine a summon destination") end}
GridNav = {
    IsTraversable = function(_, position) navigation_calls = navigation_calls + 1; return traversable(position) end,
    IsBlocked = function(_, position) return blocked(position) end,
}
GetGroundHeight = function(position, ignored_entity)
    assert(ignored_entity == nil)
    ground_calls = ground_calls + 1; return height(position)
end
FindClearSpaceForUnit = function() error("summon resolver must never relocate outside its checked search") end
FindUnitsInRadius = function(_, position, _, radius, team, kinds, flags)
    queries = queries + 1
    assert(radius <= 1200 and team == 3 and kinds == 7 and flags == 16,
        "bounded query includes hidden invulnerable wall barriers")
    local found = {}
    for _, unit in ipairs(obstacles) do
        local p = unit:GetAbsOrigin()
        if (p.x - position.x)^2 + (p.y - position.y)^2 <= radius^2 then found[#found + 1] = unit end
    end
    return found
end
local regions = require("systems/forbidden_region_service")
local validation = require("systems/destination_validation_service")
local resolver = require("systems/hero_summon_destination")
local bus, events = require("core/event_bus"), require("core/events")
local function entity(x, y, z, hull)
    local unit = {origin = Vector(x, y, z), forward = Vector(1, 0, 0)}
    function unit:IsNull() return false end
    function unit:IsAlive() return true end
    function unit:GetAbsOrigin() return self.origin end
    function unit:GetForwardVector() return self.forward end
    function unit:GetTeamNumber() return 2 end
    function unit:GetHullRadius() return hull or 0 end
    return unit
end
local altar, city
local function reset()
    queries, ground_calls, navigation_calls, obstacles = 0, 0, 0, {}
    altar, city = entity(-4000, 0, 384), entity(2000, 0, 152, 48)
    height = function(p) return p.x < 1000 and 384 or 128 end
    traversable, blocked = function() return true end, function() return false end
    definitions.rows = {}; regions.init(); bus.reset()
    listed = {{player_id = 0, building_id = "main_city", unit = city}}
    bus.handle_request(events.BUILDING_LIST_REQUEST, function(payload)
        assert(payload.player_id == 0, "query must be limited to the summoning player")
        return {ok = true, buildings = listed}
    end)
end
local function resolve() return resolver.resolve(altar, {spawn_offset = 260}, 0) end

reset()
local position, reason, info = resolve()
assert(position and not reason and position.x == 2256 and position.y == 0 and position.z == 128)
assert(city:GetAbsOrigin().z == 152, "grounding must not mutate the city origin")
assert(info.source == "main_city" and info.distance == 256 and info.grounded and info.attempts == 1)
assert(queries == 1 and ground_calls == 9 and navigation_calls == 9,
    "center and all eight clearance samples validated once")
local before_ground = ground_calls
local hero = {IsNull = function() return false end, survival_hero_id = "hero_test",
    GetAbsOrigin = function() return position end, SetAbsOrigin = function(_, p) position = p end}
assert(validation.teleport(hero, position, false))
assert(position.z == 128 and ground_calls == before_ground, "teleport uses the validated grounded vector")

-- Relocated/upgraded city and its facing are read afresh; same-team buildings
-- from another player can never become the summoning player's home.
reset()
table.insert(listed, 1, {player_id = 1, building_id = "main_city", unit = entity(5000, 0, 152)})
city.origin, city.forward = Vector(3200, 400, 152), Vector(0, -2, 0)
position, reason, info = resolve()
assert(position and position.x == 3200 and position.y == 144 and info.source == "main_city")
city.origin = Vector(3600, 700, 152)
position = resolve()
assert(position and position.x == 3600 and position.y == 444, "new summon attempts use the current city position")

reset()
traversable = function(p) return (p.x - 2256)^2 + p.y^2 > 1 end
position, reason, info = resolve()
assert(position and info.source == "main_city" and info.distance == 256 and info.attempts == 2)
assert(info.rejected.destination_not_traversable == 1 and queries == 1)

reset()
blocked = function() return true end
position, reason, info = resolve()
assert(not position and reason:find("主城周围没有安全落点", 1, true))
assert(queries == 1 and info.attempts == 112, "seven rings of sixteen positions are bounded")
assert(info.rejected.destination_blocked == info.attempts)

reset()
height = function(p) return p.x < 1000 and 384 or 0 end
position, reason, info = resolve()
assert(not position and info.rejected.destination_height_mismatch == info.attempts,
    "cannot descend into water or fall back to a remote, otherwise valid altar")

reset()
definitions.rows = {{enabled = true, region_id = "safe_strip", region_type = "hero_movable",
    shape = "circle", center_x = 2320, center_y = 0, radius = 65}}
regions.init()
position, reason, info = resolve()
assert(position and position.x == 2320 and position.y == 0 and info.distance == 320)
assert(info.rejected.hero_destination_outside_movable_region > 0
    and info.rejected.clearance_hero_destination_outside_movable_region > 0,
    "center and full hero radius must stay inside permitted regions")

reset()
blocked = function(p) return math.abs(p.x - 2288) < 0.1 and math.abs(p.y) < 0.1 end
position, reason, info = resolve()
assert(position and info.attempts == 2 and info.rejected.clearance_destination_blocked == 1,
    "walkable center does not bypass an obstructed hull edge")

reset()
obstacles = {entity(2256, 0, 128, 8)}
obstacles[1].survival_wall_collision_barrier = true
position, reason, info = resolve()
assert(position and info.attempts == 2 and info.rejected.destination_occupied == 1,
    "small hidden wall barriers still reject a centered spawn")

reset()
local alive = entity(2256, 0, 128, 64); alive.IsPhased = function() return true end
local dead = entity(2256, 0, 128, 64); dead.IsAlive = function() return false end
local preview = entity(2256, 0, 128, 64); preview.survival_is_grid_preview = true
local placeholder = entity(2256, 0, 128, 64)
placeholder.HasModifier = function(_, name) return name == "modifier_survival_placeholder_anchor" end
obstacles = {alive, dead, preview, placeholder, entity(2256, 0, 128, 0), entity(2256, 0, -128, 64)}
position, reason, info = resolve()
assert(position and info.attempts == 1, "noncolliding, dead, preview and other-level units do not occupy the landing")

reset()
obstacles = {entity(2256, 0, 128, 400)}
position, reason, info = resolve()
assert(position and info.source == "main_city" and position.x < 2000,
    "an obstructed front can search behind the city rather than move to another room")

for _, invalid in ipairs({"missing", "other_player", "constructing", "dead"}) do
    reset()
    if invalid == "missing" then listed = {}
    elseif invalid == "other_player" then listed[1].player_id = 1
    elseif invalid == "constructing" then listed[1].constructing = true
    else city.IsAlive = function() return false end end
    position, reason, info = resolve()
    assert(not position and reason:find("主城尚未建造", 1, true) and info.last_reason == "main_city_not_found")
    assert(queries == 0 and info.attempts == 0, "invalid own city cannot trigger a fallback spawn")
end

reset()
city.survival_hull_radius = 300; obstacles = {city}
position, reason, info = resolve()
assert(position and info.distance == 448, "large city hull expands the first spawn radius")
reset()
city.survival_hull_radius = 700
position, reason, info = resolve()
assert(not position and info.attempts == 0 and info.last_reason == "main_city_clearance_exceeds_search",
    "oversized hull must fail instead of expanding indefinitely into another player's base")

reset()
GetGroundHeight = function() return 0/0 end
position, reason, info = resolve()
assert(not position and info.rejected.ground_height_unavailable == info.attempts, "invalid terrain response fails closed")
print("HERO_SUMMON_DESTINATION_PASS: own live city, moving origin/facing, bounded rings, eight-point clearance, regions/heights, occupancy and no remote fallback")
