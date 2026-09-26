package.path = "scripts/vscripts/?.lua;" .. package.path

GetMapName = function() return "template_map" end
DOTA_TEAM_GOODGUYS = 2
DOTA_UNIT_TARGET_TEAM_BOTH = 3
DOTA_UNIT_TARGET_HERO = 1
DOTA_UNIT_TARGET_BASIC = 2
DOTA_UNIT_TARGET_BUILDING = 4
DOTA_UNIT_TARGET_FLAG_INVULNERABLE = 0
FIND_ANY_ORDER = 0

local vector_mt = {}
vector_mt.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
Vector = function(x, y, z) return setmetatable({x = x, y = y, z = z}, vector_mt) end

local height = 384
GetGroundHeight = function() return height end
GetGroundPosition = function(position) return Vector(position.x, position.y, height) end
GridNav = {
    IsTraversable = function() return true end,
    IsBlocked = function() return false end,
    IsNearbyTree = function() return false end,
}
FindUnitsInRadius = function() return {} end

local regions = require("systems/forbidden_region_service")
regions.init()
local grid = require("systems/grid_placement_system")
local position = Vector(400, 5200, 0)

local function check(z, expected, reason)
    height = z
    local result = grid._can_place_for_test({position = position, footprint = {x = 2, y = 2}})
    assert(result.ok == expected and (expected or result.error == reason),
        string.format("unexpected placement at Z=%d: %s", z, tostring(result.error)))
end

check(384, true)
check(368, true)
check(367, false, "terrain_not_build_level")
check(128, false, "terrain_not_build_level")

print("BUILD_GROUND_HEIGHT_PASS: upper lawn allowed, stair/lower route denied")
