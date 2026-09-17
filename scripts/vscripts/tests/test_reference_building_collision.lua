-- Exercise the server setter: SetModelScale does not scale SetHullRadius.
package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path
local config = require("config/buildings_config")
local system = require("systems/building_system")
local unit = { IsNull = function() return false end }
function unit:SetHullRadius(radius) self.hull_radius = radius end
assert(system._apply_hull_radius_for_test(unit, config.main_city))
assert(unit.hull_radius == 48 and unit.survival_hull_radius == 48)
assert(system._apply_hull_radius_for_test(unit, config.building_farm))
assert(unit.hull_radius == 0, "farm gained an unintended navigation blocker")
assert(system._apply_hull_radius_for_test(unit, config.wall))
assert(unit.hull_radius == config.wall.hull_radius, "wall collision changed")
print("REFERENCE_BUILDING_COLLISION_PASS city=48 farm=0 wall=unchanged")
