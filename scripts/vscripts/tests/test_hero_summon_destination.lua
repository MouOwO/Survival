package.path = "scripts/vscripts/?.lua;" .. package.path
-- Standalone fake players must not depend on the production admission list.
package.loaded["config/test_access"] = {enabled=false}
local definitions = {rows = {}}
package.loaded["config/generated/build_forbidden_regions"] = definitions
Vector = function(x, y, z) return {x = x, y = y, z = z or 0} end
DOTA_TEAM_GOODGUYS, DOTA_UNIT_TARGET_TEAM_BOTH = 2, 3
DOTA_UNIT_TARGET_HERO, DOTA_UNIT_TARGET_BASIC, DOTA_UNIT_TARGET_BUILDING = 1, 2, 4
DOTA_UNIT_TARGET_FLAG_INVULNERABLE, FIND_ANY_ORDER = 16, 0
local queries, ground_calls, navigation_calls, grid_queries, obstacles, listed
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
    assert(radius <= 1408 and team == 3 and kinds == 7 and flags == 16,
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
local resolver = arg and arg[1] and assert(loadfile(arg[1]))()
    or require("systems/hero_summon_destination")
local bus, events = require("core/event_bus"), require("core/events")
local grid = require("systems/grid_placement_system")
local geometry = require("core/building_grid_geometry")
local grid_lookup = grid.is_position_occupied
grid.is_position_occupied = function(position)
    grid_queries=grid_queries+1
    return grid_lookup(position)
end
local serial = 0
local function entity(x, y, z, hull)
    serial = serial + 1
    local unit = {origin = Vector(x, y, z), forward = Vector(1, 0, 0), owner_id = 0, index = serial}
    function unit:IsNull() return false end
    function unit:IsAlive() return true end
    function unit:GetAbsOrigin() return self.origin end
    function unit:GetForwardVector() return self.forward end
    function unit:GetTeamNumber() return 2 end
    function unit:GetHullRadius() return hull or 0 end
    function unit:GetPlayerOwnerID() return self.owner_id end
    function unit:entindex() return self.index end
    return unit
end
local altar, city
local function reset()
    queries, ground_calls, navigation_calls, grid_queries, obstacles = 0, 0, 0, 0, {}
    altar, city = entity(-4000, 0, 384), entity(2000, 0, 152, 48)
    height = function(p) return p.x < 1000 and 384 or 128 end
    traversable, blocked = function() return true end, function() return false end
    definitions.rows = {}; regions.init(); bus.reset(); grid.init()
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
local first_grid_queries=grid_queries
local before_ground = ground_calls
local hero = {IsNull = function() return false end, survival_hero_id = "hero_test",
    GetAbsOrigin = function() return position end, SetOrigin = function(_, p) position = p end,
    SetAbsOrigin = function() error("summon relocation must use scripted teleport") end}
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
height = function() return 0/0 end
position, reason, info = resolve()
assert(not position and info.rejected.ground_height_unavailable == info.attempts, "invalid terrain response fails closed")
-- The summon service explicitly permits an early owned anchor. Return-home
-- callers omit the option and keep the existing completed-city requirement.
reset(); listed = {}
position, reason, info = resolver.resolve(altar, {}, 0, nil,
    {allow_without_city = true, anchor_source = "hero_altar"})
assert(position and not reason and info.source == "hero_altar")
assert(position.x == -3744 and position.z == 384 and info.attempts == 1)
assert(queries == 1 and ground_calls == 9 and navigation_calls == 9,
    "early summon checks terrain, navigation and all eight hull edges")

reset(); listed = {}; altar.origin = Vector(-3200, 100, 384)
position, reason, info = resolver.resolve(altar, {}, 0, nil,
    {allow_without_city = true, anchor_source = "builder"})
assert(position and info.source == "builder" and position.x == -2944 and position.y == 100,
    "a pre-altar summon follows the owner's live builder")

reset(); listed[1].player_id = 1
position, reason, info = resolver.resolve(altar, {}, 0, nil, {allow_without_city = true})
assert(position and info.source == "hero_altar" and position.x < -3000,
    "a teammate's city never replaces the early owner's anchor")

for _, invalid in ipairs({"foreign", "dead", "removed"}) do
    reset(); listed = {}
    if invalid == "foreign" then altar.owner_id = 1
    elseif invalid == "dead" then altar.IsAlive = function() return false end
    else altar.IsNull = function() return true end end
    position, reason, info = resolver.resolve(altar, {}, 0, nil, {allow_without_city = true})
    assert(not position and info.last_reason == "main_city_not_found" and queries == 0,
        "an early summon requires a live anchor owned by the summoning player")
end

reset(); listed = {}; blocked = function() return true end
position, reason, info = resolver.resolve(altar, {}, 0, nil, {allow_without_city = true})
assert(not position and info.source == "hero_altar" and info.attempts == 112
    and reason:find("召唤位置周围没有安全落点", 1, true), "early search remains bounded")

reset(); listed = {}; height = function() return 0 end
position, reason, info = resolver.resolve(altar, {}, 0, nil, {allow_without_city = true})
assert(not position and info.rejected.destination_height_mismatch == info.attempts,
    "early unlock cannot permit a fall into water")

reset(); height = function(p) return p.x < 1000 and 384 or 0 end
position, reason, info = resolver.resolve(altar, {}, 0, nil, {allow_without_city = true})
assert(not position and info.source == "main_city" and info.attempts == 112,
    "if the own city exists, a blocked city never falls back to a distant altar")

-- Use the REAL occupied grid/events, including its minimum footprint and zero
-- world origin. Native zero-hull entities intentionally do not block movement,
-- but their registered buildings must still not be chosen as hero landings.
local function reserve(x,y,index)
    local payload={grid_x=x,grid_y=y,footprint={x=2,y=2},entindex=index}
    assert(bus.request(events.GRID_OCCUPY_REQUEST,payload)==true)
    return payload
end
reset()
local zero_hull_altar=entity(2240,0,128,0)
zero_hull_altar.survival_hull_radius=0
zero_hull_altar.survival_is_building=true
zero_hull_altar.survival_building_id="hero_altar"
obstacles={zero_hull_altar}
local gx,gy=geometry.origin(zero_hull_altar:GetAbsOrigin(),{x=2,y=2})
local occupied_altar=reserve(gx,gy,zero_hull_altar:entindex())
position,reason,info=resolve()
assert(position and info.attempts>1 and info.rejected.destination_building_occupied,
    "a zero-hull altar's occupied footprint rejects the old first landing")
assert(first_grid_queries>0 and first_grid_queries<=9,"one ordinary landing uses at most nine indexed grid reads")
assert(queries==1 and grid_queries<=info.attempts*9,"grid checks do not add native radius scans")
local zero_hull_grid_queries,zero_hull_attempts=grid_queries,info.attempts
assert(bus.request(events.GRID_RELEASE_REQUEST,occupied_altar)==true)
position,reason,info=resolve()
assert(position and position.x==2256 and position.y==0 and info.attempts==1,
    "destroy/release makes the original landing available immediately, without a cache sweep")

reset();height=function()return 128 end;city.origin=Vector(-286,-10,152)
reserve(0,0,9000)
-- Circle center(-30,-10), radius32 intersects corner(0,0), but none of its
-- eight radial samples enters the positive quadrant. Sampling alone misses it.
for i=0,7 do
    local a=i*math.pi/4
    assert(-30+math.cos(a)*32<0 or -10+math.sin(a)*32<0,"fixture defeats eight-point sampling")
end
position,reason,info=resolve()
assert(position and info.attempts>1 and info.rejected.destination_building_occupied,
    "exact circle-AABB rejects a building corner between radial samples")

reset();height=function()return 128 end;city.origin=Vector(-288,32,152)
local touching=reserve(0,0,9001)
position,reason,info=resolve()
assert(position and info.attempts>1 and info.rejected.destination_building_occupied,
    "tangency is conservatively blocked on the left grid boundary")
city.origin=Vector(-288.01,32,152)
position,reason,info=resolve()
assert(position and math.abs(position.x+32.01)<.00001 and info.attempts==1,
    "a small real gap beyond the boundary is accepted")
assert(bus.request(events.GRID_RELEASE_REQUEST,touching)==true)
reserve(-2,-2,9002);city.origin=Vector(-224,-32,152)
position,reason,info=resolve()
assert(position and info.attempts>1 and info.rejected.destination_building_occupied,
    "negative cell coordinates and opposite tangent boundary use the same policy")

reset();height=function()return 128 end;city.origin=Vector(-316,32,152)
reserve(0,0,9003)
position,reason,info=resolve()
assert(position and info.attempts==1 and position.x==-60,"radius32 fits before the building")
local large_hero=entity(-500,0,128,64)
position,reason,info=resolver.resolve(altar,{},0,large_hero)
assert(position and info.attempts>1 and info.rejected.destination_building_occupied,
    "post-create actual hero radius64 cannot reuse the radius32 gap")
assert(queries==2,"each explicit resolve uses one bounded native occupancy query")

local max_grid_queries=0
for _,hull in ipairs({32,64,128,256})do
    reset();height=function()return 128 end
    position,reason,info=resolver.resolve(altar,{},0,entity(0,0,128,hull))
    assert(position and info.attempts==1 and queries==1,"supported actual hull finds bounded empty landing")
    local bound=hull==32 and 9 or 100
    assert(grid_queries>0 and grid_queries<=bound,"bounded circle grid lookup count")
    max_grid_queries=math.max(max_grid_queries,grid_queries)
end
for _,hull in ipairs({257,math.huge,0/0,-1})do
    reset()
    position,reason,info=resolver.resolve(altar,{},0,entity(0,0,128,hull))
    assert(not position and info.last_reason=="hero_hull_out_of_bounds"
        and info.attempts==0 and queries==0 and grid_queries==0,
        "abnormal hull fails before any unbounded native/grid search")
end

reset();height=function()return 128 end
local saved_grid_lookup=grid.is_position_occupied
grid.is_position_occupied=function()error("fixture unavailable grid")end
position,reason,info=resolve()
grid.is_position_occupied=saved_grid_lookup
assert(not position and info.rejected.occupancy_grid_unavailable==info.attempts,
    "an unavailable occupancy index cannot silently admit an occupied landing")
print("HERO_SUMMON_DESTINATION_PASS: original policy plus zero-hull footprint/corner/release/boundary/actual hull; first_grid_queries="
    ..first_grid_queries.." zero_hull_attempts="..zero_hull_attempts.." zero_hull_grid_queries="..zero_hull_grid_queries
    .." max_observed_grid_queries="..max_grid_queries.." native_queries_per_resolve=1; real grid/events, native boundary simulated")
