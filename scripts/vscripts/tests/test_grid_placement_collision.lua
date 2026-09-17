package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path

local events = require("core/events")
local handlers = {}

local function vector(x, y, z)
    return { x = x, y = y, z = z or 0 }
end

Vector = vector
DOTA_TEAM_GOODGUYS = 2
DOTA_UNIT_TARGET_TEAM_BOTH = 3
DOTA_UNIT_TARGET_HERO = 1
DOTA_UNIT_TARGET_BASIC = 2
DOTA_UNIT_TARGET_BUILDING = 4
DOTA_UNIT_TARGET_FLAG_INVULNERABLE = 8
FIND_ANY_ORDER = 0

GridNav = {
    IsTraversable = function() return true end,
    IsBlocked = function() return false end,
    IsNearbyTree = function() return false end,
}
GetGroundPosition = function(position) return position end
GetGroundHeight = function(_, _) return 0 end
FindUnitsInRadius = function() return {} end

package.loaded["core/event_bus"] = {
    handle_request = function(event_name, handler)
        handlers[event_name] = handler
    end,
    request = function() return nil end,
}
package.loaded["config/grid_placement_config"] = {
    cell_size = 64,
    footprint_subdivision = 1,
    minimum_footprint = { x = 2, y = 2 },
    max_unit_hull_radius = 512,
    build_bounds = {
        min_x = -1800, max_x = 1800,
        min_y = -1200, max_y = 1200,
    },
    forbidden_regions = {},
    forbidden_markers = {},
}

package.loaded["systems/grid_placement_system"] = nil
local grid = require("systems/grid_placement_system")
grid.init()

local function unit(entindex, x, y, hull, constructing)
    local result = {
        origin = vector(x, y, 0),
        hull = hull,
        constructing = constructing,
        survival_is_building = constructing ~= nil,
    }
    function result:IsNull() return false end
    function result:entindex() return entindex end
    function result:GetAbsOrigin() return self.origin end
    function result:GetHullRadius() return self.hull end
    function result:GetTeamNumber() return 2 end
    function result:HasModifier(name)
        return name == "modifier_building_under_construction"
            and self.constructing == true
    end
    return result
end

local cell = vector(64, 64, 0)
assert(grid._unit_overlaps_cell_for_test(
    unit(1, 105, 64, 10, false), cell, 32
), "Hull edge contact was not treated as a collision")
assert(not grid._unit_overlaps_cell_for_test(
    unit(2, 110, 64, 10, false), cell, 32
), "A unit outside its Hull overlap was incorrectly blocked")

local constructing = unit(3, 64, 64, 512, true)
assert(not grid._has_unit_for_test(cell, {
    team = 2,
    nearby_units = { constructing },
}), "Construction-only building still caused physical blocking")

local live_building = unit(4, 64, 64, 20, false)
assert(grid._has_unit_for_test(cell, {
    team = 2,
    nearby_units = { live_building },
}), "Completed building Hull did not block its cell")

local occupy = handlers[events.GRID_OCCUPY_REQUEST]
local release = handlers[events.GRID_RELEASE_REQUEST]
assert(occupy and release, "Grid occupancy handlers were not registered")
occupy({ grid_x = 0, grid_y = 0, footprint = { x = 2, y = 2 }, entindex = 10 })
occupy({ grid_x = 1, grid_y = 0, footprint = { x = 2, y = 2 }, entindex = 11 })
release({ grid_x = 0, grid_y = 0, footprint = { x = 2, y = 2 }, entindex = 10 })
local occupied = grid._occupied_for_test()
assert(occupied[1] and occupied[1][0] == 11,
    "Releasing one building removed another building's overlapping claim")

print("GRID_PLACEMENT_COLLISION_PASS")