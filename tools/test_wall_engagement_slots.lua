package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path

local function vector(x, y, z)
    local value = { x = x, y = y, z = z or 0 }
    local mt = {}
    function mt.__sub(a, b) return vector(a.x - b.x, a.y - b.y, a.z - b.z) end
    function mt.__add(a, b) return vector(a.x + b.x, a.y + b.y, a.z + b.z) end
    function mt.__mul(a, b)
        if type(a) == "number" then a, b = b, a end
        return vector(a.x * b, a.y * b, a.z * b)
    end
    return setmetatable(value, mt)
end

Vector = vector
package.preload["config/global_rules"] = function()
    error("wall engagement must not load global_rules")
end

local entities = {}
function EntIndexToHScript(index) return entities[index] end

local function entity(index, x, y, forward_x, forward_y)
    local unit = {
        index = index,
        position = vector(x, y, 0),
        forward = vector(forward_x or 1, forward_y or 0, 0),
        alive = true,
    }
    function unit:IsNull() return false end
    function unit:IsAlive() return self.alive end
    function unit:entindex() return self.index end
    function unit:GetAbsOrigin() return self.position end
    function unit:GetForwardVector() return self.forward end
    entities[index] = unit
    return unit
end

local slots = require("systems/wall_engagement_slots")
local wall = entity(100, 0, 0, 1, 0)
local monsters = {}
for index = 1, 10 do monsters[index] = entity(index, 600, index * 5) end

local claimed = {}
for index = 1, 4 do
    local slot = assert(slots.claim(wall, monsters[index]), "first four must claim")
    assert(not claimed[slot], "engagement slot claimed twice")
    claimed[slot] = true
end
assert(slots.claim(wall, monsters[5]) == nil, "fifth monster claimed a slot")

local positions = {}
for slot = 1, 4 do
    local point = slots.position(wall, slot, 0)
    positions[slot] = point
    assert(math.abs(point.x - 288) < 0.001, "slots must stay on one wall side")
end
for slot = 2, 4 do
    assert(math.abs(positions[slot].y - positions[slot - 1].y - 80) < 0.001,
        "engagement slots are not uniformly spaced")
end
assert(math.abs(positions[1].y + 120) < 0.001
        and math.abs(positions[4].y - 120) < 0.001,
    "engagement slots are not centered across four positions")

local queue_one, queue_slot_one, queue_row_one = slots.queue_position(wall, monsters[5])
assert(queue_row_one == 1 and math.abs(queue_one.x - 448) < 0.001,
    "first waiting row position changed")
assert(math.abs(queue_one.x - positions[1].x) >= 160,
    "first waiting row is too close to the engagement row")
for index = 6, 9 do
    assert(slots.claim(wall, monsters[index]) == nil, "waiting monster claimed full wall")
    slots.queue_position(wall, monsters[index])
end
local queue_two, _, queue_row_two = slots.queue_position(wall, monsters[9])
assert(queue_row_two == 2 and math.abs(queue_two.x - 608) < 0.001,
    "second waiting row overlaps first row")

monsters[2].alive = false
local replacement_slot = assert(slots.claim(wall, monsters[5]), "released slot not reused")
assert(replacement_slot >= 1 and replacement_slot <= 3, "replacement slot invalid")
local replacement = slots.position(wall, replacement_slot, 0)
assert(math.abs(replacement.x - 288) < 0.001, "replacement changed engagement side")

slots.release(wall:entindex(), monsters[5]:entindex())
assert(slots.claim(wall, monsters[10]) ~= nil, "explicit release did not free slot")
slots.reset()

LUA_MODIFIER_MOTION_NONE = 0
MODIFIER_ATTRIBUTE_PERMANENT = 1
MODIFIER_STATE_NO_UNIT_COLLISION = 2
DOTA_TEAM_BADGUYS = 3
DOTA_TEAM_GOODGUYS = 2
DOTA_UNIT_ORDER_MOVE_TO_POSITION = 1
DOTA_UNIT_ORDER_ATTACK_TARGET = 2
LinkLuaModifier = function() end
class = function(value) return value end
IsServer = function() return true end
package.loaded["core/team_alignment"] = {
    enforce = function() return true end,
    are_enemies = function() return true end,
}
local orders = {}
function ExecuteOrderFromTable(order) orders[#orders + 1] = order end

local function combat_unit(index, movement_type, x, y)
    local unit = entity(index, x, y)
    unit.survival_wave_movement_type = movement_type
    unit.force_target = nil
    function unit:SetForceAttackTarget(target) self.force_target = target end
    function unit:GetAttackTarget() return self.force_target end
    function unit:Stop() end
    return unit
end

package.loaded["modifiers/modifier_enemy_wall_ai"] = nil
local modifier_class = require("modifiers/modifier_enemy_wall_ai")
local function modifier_for(parent)
    local modifier = setmetatable({ wall_entindex = wall:entindex() }, {
        __index = modifier_class,
    })
    function modifier:GetParent() return parent end
    return modifier
end

local ground = combat_unit(201, "ground", 600, 0)
local ground_modifier = modifier_for(ground)
orders = {}
ground_modifier:OnIntervalThink()
assert(#orders == 1 and orders[1].OrderType == DOTA_UNIT_ORDER_MOVE_TO_POSITION,
    "ground monster did not approach its engagement slot first")
ground_modifier:OnIntervalThink()
assert(#orders == 1,
    "ground monster repeated an unchanged movement order")
local ground_slot = assert(ground_modifier.engagement_slot)
local ground_position = assert(slots.position(wall, ground_slot, 0))
ground.position = ground_position
orders = {}
ground_modifier:OnIntervalThink()
assert(ground.force_target == wall and #orders == 0,
    "ground monster did not attack after reaching its slot")
ground.position = ground_position + vector(40, 0, 0)
ground_modifier:OnIntervalThink()
assert(ground.force_target == wall and #orders == 0,
    "minor slot drift interrupted the ground monster attack")
ground.position = ground_position + vector(60, 0, 0)
ground_modifier:OnIntervalThink()
assert(ground.force_target == wall and #orders == 1
        and orders[1].OrderType == DOTA_UNIT_ORDER_MOVE_TO_POSITION,
    "ground monster did not resume movement while keeping the wall target")
ground_modifier:OnIntervalThink()
assert(#orders == 1,
    "ground monster repeated movement while returning to its slot")

local waiting = combat_unit(203, "ground", 600, 0)
local waiting_modifier = modifier_for(waiting)
for index = 204, 206 do
    local blocker = combat_unit(index, "ground", 600, index)
    assert(slots.claim(wall, blocker), "test blocker did not claim an open slot")
end
orders = {}
waiting_modifier:OnIntervalThink()
assert(waiting_modifier.engagement_slot == nil and #orders == 1,
    "waiting monster did not receive its initial queue movement")
assert(waiting.force_target == wall,
    "waiting monster lost the wall as its forced attack target")
waiting_modifier:OnIntervalThink()
assert(#orders == 1,
    "waiting monster repeated an unchanged queue movement")
assert(waiting.force_target == wall,
    "waiting monster changed its target while queued")
ground.alive = false
waiting_modifier:OnIntervalThink()
assert(waiting_modifier.engagement_slot ~= nil and #orders == 2,
    "waiting monster did not receive one new movement after slot promotion")
waiting_modifier:OnIntervalThink()
assert(#orders == 2,
    "promoted monster repeated its slot movement")

local flying = combat_unit(202, "flying", 600, 0)
local flying_modifier = modifier_for(flying)
orders = {}
flying_modifier:OnIntervalThink()
assert(flying.force_target == wall and #orders == 0,
    "flying monster incorrectly entered ground slot pathing")
ground_modifier:OnDestroy()
waiting_modifier:OnDestroy()
flying_modifier:OnDestroy()
slots.reset()

print("WALL_ENGAGEMENT_SLOTS_LUA51_PASS")