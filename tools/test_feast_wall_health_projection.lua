package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path

local projection = require("systems/building_health_projection")
local effect_state = require("systems/rogue_effect_state_service")

effect_state.reset()
assert(effect_state.add_wall_health_flat(0, 1000),
    "feast fixed health increase was not stored")

local fixed = effect_state.wall_health_flat(0)
assert(projection.maximum_with_flat_bonus(1500, 0, fixed) == 2500,
    "wall upgrade did not preserve feast fixed health increase")
assert(projection.maximum_with_flat_bonus(1500, 20, fixed) == 2800,
    "technology percentage incorrectly multiplied feast fixed health increase")
assert(projection.maximum_with_flat_bonus(2000, 20, fixed) == 3400,
    "later wall level did not carry the original fixed health increase")
assert(projection.maximum_with_flat_bonus(2000, 20, fixed) == 3400,
    "repeated wall recompute accumulated feast more than once")
assert(effect_state.wall_health_flat(1) == 0,
    "feast fixed health increase leaked to another player")

print("FEAST_WALL_HEALTH_PROJECTION_LUA51_PASS")