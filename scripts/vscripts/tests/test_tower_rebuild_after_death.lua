package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;"
    .. package.path

DOTA_TEAM_GOODGUYS = 2
DOTA_TEAM_BADGUYS = 3
DOTA_UNIT_TARGET_HERO = 1
DOTA_UNIT_TARGET_BASIC = 2
DOTA_UNIT_TARGET_BUILDING = 4
DOTA_UNIT_TARGET_TEAM_BOTH = 3
DOTA_UNIT_TARGET_FLAG_INVULNERABLE = 8
FIND_ANY_ORDER = 0

local vector_mt = {
    __add = function(left, right)
        return Vector(left.x + right.x, left.y + right.y, left.z + right.z)
    end,
    __sub = function(left, right)
        return Vector(left.x - right.x, left.y - right.y, left.z - right.z)
    end,
}
Vector = function(x, y, z)
    return setmetatable({ x = x, y = y, z = z }, vector_mt)
end

package.loaded["core/event_bus"] = {
    handle_request = function() end,
    request = function() return nil end,
}
package.loaded["core/events"] = require("core/events")
package.loaded["systems/forbidden_region_service"] = {
    validate_building_footprint = function() return true end,
}
package.loaded["config/grid_placement_config"] = {
    cell_size = 64,
    minimum_footprint = { x = 2, y = 2 },
    footprint_subdivision = 1,
    max_height_delta = 48,
    max_unit_hull_radius = 512,
    tree_block_radius_scale = 0.72,
    build_bounds = { min_x = -1800, max_x = 1800, min_y = -1200, max_y = 1200 },
    forbidden_markers = {},
}

GridNav = {
    IsTraversable = function() return true end,
    IsBlocked = function() return false end,
    IsNearbyTree = function() return false end,
}
GetGroundHeight = function() return 0 end
GetGroundPosition = function(position) return position end
FindUnitsInRadius = function() return {} end
local entities = {}
EntIndexToHScript = function(entindex) return entities[entindex] end

package.loaded["systems/grid_placement_system"] = nil
local grid = require("systems/grid_placement_system")
local has_unit = assert(grid._has_unit_for_test)
local occupied = assert(grid._occupied_for_test)
local can_place = assert(grid._can_place_for_test)

local function unit(entindex, alive)
    return {
        IsNull = function() return false end,
        IsAlive = function() return alive end,
        entindex = function() return entindex end,
        GetAbsOrigin = function() return Vector(32, 32, 0) end,
        GetHullRadius = function() return 1 end,
        survival_is_building = true,
        survival_building_id = "arrow_tower",
    }
end

local payload = {
    team = DOTA_TEAM_GOODGUYS,
    nearby_units = { unit(101, false) },
}
assert(has_unit(Vector(32, 32, 0), payload) == false,
    "dead tower entity must not block rebuilding its released cell")

entities[101] = unit(101, false)
occupied()[0] = { [0] = 101 }
local placement = can_place({
    position = Vector(0, 0, 0),
    footprint = { x = 2, y = 2 },
    compact = true,
})
assert(placement.ok == true,
    "preview validation must reconcile dead tower occupancy before checking cells")
assert(occupied()[0] == nil,
    "dead tower occupancy must be removed during preview validation")

entities[102] = unit(102, true)
occupied()[1] = { [1] = 102 }
can_place({ position = Vector(64, 64, 0), footprint = { x = 2, y = 2 }, compact = true })
assert(occupied()[1][1] == 102,
    "alive tower occupancy must remain reserved during preview validation")

entities[103] = {
    IsNull = function() return false end,
    IsAlive = function() return true end,
}
occupied()[2] = { [2] = 103 }
can_place({ position = Vector(128, 128, 0), footprint = { x = 2, y = 2 }, compact = true })
assert(occupied()[2] == nil,
    "non-building occupancy must be removed during preview validation")

payload.nearby_units = { unit(101, true) }
assert(has_unit(Vector(32, 32, 0), payload) == true,
    "alive tower entity must continue blocking its cell")

payload.ignore_entindex = 101
assert(has_unit(Vector(32, 32, 0), payload) == false,
    "explicitly ignored tower entity must not block the cell")

print("TOWER_REBUILD_AFTER_DEATH_PASS")