package.path = "scripts/vscripts/?.lua;" .. package.path
local definitions = {rows = {}}
package.loaded["config/generated/build_forbidden_regions"] = definitions
Vector = function(x, y, z) return {x = x, y = y, z = z or 0} end
DOTA_TEAM_GOODGUYS, DOTA_UNIT_TARGET_TEAM_BOTH = 2, 3
DOTA_UNIT_TARGET_HERO, DOTA_UNIT_TARGET_BASIC, DOTA_UNIT_TARGET_BUILDING = 1, 2, 4
DOTA_UNIT_TARGET_FLAG_INVULNERABLE, FIND_ANY_ORDER = 16, 0
local marker, queries, ground_calls, navigation_calls, obstacles
local height, traversable, blocked
Entities = {FindByName = function(_, _, name)
    assert(name == "player_0_hero_spawn"); return marker
end}
GridNav = {
    IsTraversable = function(_, position) navigation_calls = navigation_calls + 1; return traversable(position) end,
    IsBlocked = function(_, position) return blocked(position) end,
    CanFindPath = function() error("marker may legitimately be on another island") end,
}
GetGroundHeight = function(position, ignored_entity)
    assert(ignored_entity == nil, "ground queries do not require a live entity for an authored anchor")
    ground_calls = ground_calls + 1; return height(position)
end
FindClearSpaceForUnit = function() error("summon resolver must never relocate outside its checked search") end
FindUnitsInRadius = function(_, position, _, radius, team, kinds, flags)
    queries = queries + 1
    assert(radius <= 1000 and team == 3 and kinds == 7 and flags == 16, "bounded query includes hidden invulnerable wall barriers")
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
local function entity(x, y, z, hull)
    local position = Vector(x, y, z)
    return {IsNull = function() return false end, IsAlive = function() return true end,
        GetAbsOrigin = function() return position end, GetForwardVector = function() return Vector(1, 0, 0) end,
        GetTeamNumber = function() return 2 end, GetHullRadius = function() return hull or 0 end}
end
local altar
local function reset()
    queries, ground_calls, navigation_calls, obstacles = 0, 0, 0, {}
    altar, marker = entity(2000, 0, 384), entity(0, 0, 152)
    height = function(p) return p.x < 1000 and 128 or 384 end
    traversable, blocked = function() return true end, function() return false end
    definitions.rows = {}; regions.init()
end
local function resolve() return resolver.resolve(altar, {}, 0) end
reset()
local position, reason, info = resolve()
assert(position and not reason and position.x == 0 and position.y == 0 and position.z == 128)
assert(position ~= marker:GetAbsOrigin() and marker:GetAbsOrigin().z == 152, "copy marker before grounding")
assert(info.source == "marker" and info.distance == 0 and info.grounded and info.attempts == 1)
assert(queries == 1 and ground_calls == 9 and navigation_calls == 9, "center and all eight clearance samples validated once")
local before_ground = ground_calls
local hero = {IsNull = function() return false end, survival_hero_id = "hero_test",
    GetAbsOrigin = function() return Vector(2000, 0, 384) end,
    SetAbsOrigin = function(_, p) position = p end}
hero.GetAbsOrigin = function() return position end
assert(validation.teleport(hero, position, false))
assert(position.z == 128 and ground_calls == before_ground, "validated grounded vector is directly usable without recomputing raw marker")

reset()
traversable = function(p) return p.x^2 + p.y^2 > 1 end
position, reason, info = resolve()
assert(position and info.source == "marker" and info.distance == 64 and info.attempts == 2)
assert(info.rejected.destination_not_traversable == 1 and queries == 1)

reset(); marker = nil
position, reason, info = resolve()
assert(position and position.x == 2260 and position.z == 384 and info.source == "altar" and queries == 1)

reset()
blocked = function() return true end
position, reason, info = resolve()
assert(not position and reason:find("没有安全落点", 1, true))
assert(queries == 2 and info.attempts > 100 and info.attempts < 300, "both searches are finite")
assert(info.rejected.destination_blocked == info.attempts)

reset()
height = function(p) return p.x < 1000 and 0 or 384 end
position, reason, info = resolve()
assert(position and info.source == "altar" and position.z == 384, "marker search cannot descend to lower water plane")
assert(info.rejected.destination_height_mismatch > 0)

reset()
definitions.rows = {{enabled = true, region_id = "safe_strip", region_type = "hero_movable",
    shape = "circle", center_x = 128, center_y = 0, radius = 65}}
regions.init()
position, reason, info = resolve()
assert(position and position.x == 128 and position.y == 0 and info.source == "marker")
assert(info.rejected.hero_destination_outside_movable_region > 0
    and info.rejected.clearance_hero_destination_outside_movable_region > 0,
    "center and full hero radius must stay inside permitted region")

reset()
blocked = function(p) return math.abs(p.x - 32) < 0.1 and math.abs(p.y) < 0.1 end
position, reason, info = resolve()
assert(position and info.distance == 64 and info.rejected.clearance_destination_blocked == 1,
    "walkable center does not bypass an obstructed hull edge")

reset()
obstacles = {entity(12, 0, 128, 8)}
obstacles[1].survival_wall_collision_barrier = true
position, reason, info = resolve()
assert(position and info.distance == 64 and info.rejected.destination_occupied == 1,
    "small hidden wall barriers still reject a centered spawn")

reset()
local alive = entity(0, 0, 128, 64)
alive.IsPhased = function() return true end
local dead = entity(0, 0, 128, 64); dead.IsAlive = function() return false end
local preview = entity(0, 0, 128, 64); preview.survival_is_grid_preview = true
local placeholder = entity(0, 0, 128, 64)
placeholder.HasModifier = function(_, name) return name == "modifier_survival_placeholder_anchor" end
obstacles = {alive, dead, preview, placeholder, entity(0, 0, 128, 0), entity(0, 0, -128, 64)}
position, reason, info = resolve()
assert(position and info.distance == 0, "noncolliding, dead, preview and other-level units do not occupy the landing")

reset()
obstacles = {entity(300, 0, 128, 300)}
position, reason, info = resolve()
assert(position and info.source == "marker" and position.x < 0, "large nearby building hull is checked precisely")

reset(); marker = nil
height = function() return 0 end
position, reason, info = resolve()
assert(not position and info.rejected.destination_height_mismatch > 0, "fallback preserves altar height too")
reset()
GetGroundHeight = function() return 0/0 end
position, reason, info = resolve()
assert(not position and info.rejected.ground_height_unavailable > 0, "invalid terrain response fails closed")
print("HERO_SUMMON_DESTINATION_PASS: grounded marker, bounded nearest fallback, eight-point hull clearance, regions/heights, dynamic occupancy and direct teleport")
