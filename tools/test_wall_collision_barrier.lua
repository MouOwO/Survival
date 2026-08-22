package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path

local function vector(x, y, z)
    local value = { x = x, y = y, z = z or 0 }
    local mt = {}
    function mt.__add(a, b) return vector(a.x + b.x, a.y + b.y, a.z + b.z) end
    function mt.__mul(a, b)
        if type(a) == "number" then a, b = b, a end
        return vector(a.x * b, a.y * b, a.z * b)
    end
    return setmetatable(value, mt)
end

Vector = vector
package.preload["config/global_rules"] = function()
    error("wall collision barriers must not load global_rules")
end
function GetGroundHeight(position) return position.z end
function UTIL_Remove(entity) entity.removed = true end

local next_index = 200
local entities = {}
local function entity(position)
    next_index = next_index + 1
    local unit = { position = position, index = next_index, alive = true }
    function unit:IsNull() return false end
    function unit:IsAlive() return self.alive end
    function unit:entindex() return self.index end
    function unit:GetAbsOrigin() return self.position end
    function unit:GetForwardVector() return vector(1, 0, 0) end
    function unit:GetTeamNumber() return 2 end
    function unit:SetHullRadius(radius) self.hull_radius = radius end
    function unit:SetAbsOrigin(value) self.position = value end
    function unit:AddNoDraw() self.no_draw = true end
    function unit:AddNewModifier() self.modifier_added = true end
    entities[unit.index] = unit
    return unit
end

function CreateUnitByName(_, position) return entity(position) end
local wall = entity(vector(100, 200, 0))

local service = require("systems/wall_collision_barrier_service")
local barriers = assert(service.create(wall), "barrier creation failed")
assert(#barriers == 120, "four directions must create 120 barrier spheres")
local by_side = { up = 0, down = 0, left = 0, right = 0 }
local positions_by_side = { up = {}, down = {}, left = {}, right = {} }
for _, barrier in ipairs(barriers) do
    assert(barrier.no_draw and barrier.modifier_added, "barrier was not isolated")
    assert(barrier.hull_radius == 8, "barrier Hull radius changed")
    by_side[barrier.survival_wall_collision_side] =
        by_side[barrier.survival_wall_collision_side] + 1
    local side_positions = positions_by_side[barrier.survival_wall_collision_side]
    side_positions[#side_positions + 1] = barrier.position
end
for side, count in pairs(by_side) do
    assert(count == 30, side .. " must contain three columns of ten spheres")
end
local function bounds(points, axis)
    local minimum, maximum
    for _, point in ipairs(points) do
        local value = point[axis]
        minimum = minimum and math.min(minimum, value) or value
        maximum = maximum and math.max(maximum, value) or value
    end
    return minimum, maximum
end
local up_min_x, up_max_x = bounds(positions_by_side.up, "x")
local up_min_y, up_max_y = bounds(positions_by_side.up, "y")
assert(up_min_x == 243 and up_max_x == 333,
    "up barriers changed their fixed normal offset or segment spacing")
assert(up_min_y == 162 and up_max_y == 238,
    "up barriers changed their fixed column spacing")
local down_min_x, down_max_x = bounds(positions_by_side.down, "x")
local down_min_y, down_max_y = bounds(positions_by_side.down, "y")
assert(down_min_x == -233 and down_max_x == -143
        and down_min_y == 62 and down_max_y == 138,
    "down barriers changed their accepted side offsets")
assert(service.count(wall) == 120, "barrier registry count mismatch")
service.clear(wall)
assert(service.count(wall) == 0, "barriers were not cleared with the wall")

print("WALL_COLLISION_BARRIER_LUA51_PASS")