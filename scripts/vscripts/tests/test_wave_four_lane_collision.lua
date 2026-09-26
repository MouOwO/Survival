package.path = "scripts/vscripts/?.lua;" .. package.path

local vector_mt = {}
vector_mt.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
vector_mt.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
vector_mt.__mul = function(a, scale) return Vector(a.x * scale, a.y * scale, a.z * scale) end
Vector = function(x, y, z) return setmetatable({x = x, y = y, z = z}, vector_mt) end

local entities = {}
EntIndexToHScript = function(index) return entities[index] end
local function entity(index, position)
    local result = {
        entindex = function() return index end,
        IsNull = function() return false end,
        IsAlive = function() return true end,
        GetAbsOrigin = function() return position end,
    }
    entities[index] = result
    return result
end

local slots = require("systems/wall_engagement_slots")
local wall = entity(1, Vector(0, 0, 0))
wall.GetForwardVector = function() return Vector(0, 1, 0) end

local claimed = {}
for index = 1, 4 do
    local unit = entity(index + 1, Vector(0, -500, 0))
    local slot = slots.claim(wall, unit)
    assert(slot and not claimed[slot], "four wave monsters need four distinct attack slots")
    claimed[slot] = true
end

local positions = {}
for slot = 1, 4 do
    assert(claimed[slot], "missing attack slot " .. slot)
    positions[#positions + 1] = slots.position(wall, slot, 0)
end
table.sort(positions, function(a, b) return a.x < b.x end)
for index = 2, 4 do
    assert(positions[index].x - positions[index - 1].x >= 64,
        "Hull 32 monsters would overlap in the attack row")
end
for _, position in ipairs(positions) do
    assert(math.abs(position.x) + 32 <= 224 and math.abs(position.y) == 288,
        "four monster hulls must fit within the 448-wide passage")
end

local fifth = entity(6, Vector(0, -500, 0))
assert(slots.claim(wall, fifth) == nil, "fifth monster must wait for an attack slot")
local waiting = slots.queue_position(wall, fifth)
assert(waiting and math.abs(waiting.y) == 448,
    "waiting row must remain behind the four attack positions")

print("WAVE_FOUR_LANE_COLLISION_PASS: four non-overlapping Hull 32 slots in 448 passage; fifth queues")
