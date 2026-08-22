local root = assert(arg[1], "workspace root argument is required")
package.path = root .. "/scripts/vscripts/?.lua;"
    .. root .. "/scripts/vscripts/?/init.lua;"
    .. package.path

DOTA_UNIT_ORDER_MOVE_TO_POSITION = 1
DOTA_UNIT_ORDER_MOVE_TO_TARGET = 2
DOTA_UNIT_ORDER_ATTACK_TARGET = 3
DOTA_UNIT_ORDER_STOP = 4
DOTA_UNIT_TARGET_TEAM_FRIENDLY = 1
DOTA_UNIT_TARGET_BASIC = 2
DOTA_UNIT_TARGET_HERO = 4
DOTA_UNIT_TARGET_FLAG_INVULNERABLE = 8
FIND_CLOSEST = 1
FIND_UNITS_EVERYWHERE = 99999
MODIFIER_ATTRIBUTE_PERMANENT = 1
ACT_DOTA_ATTACK = 1
DOTA_DAMAGE_CATEGORY_ATTACK = 1

function class(definition) return definition end
function IsServer() return true end

local vector_meta = {}
vector_meta.__index = vector_meta
function vector_meta.__sub(left, right)
    return Vector(left.x - right.x, left.y - right.y, left.z - right.z)
end
function vector_meta:Length2D()
    return math.sqrt(self.x * self.x + self.y * self.y)
end
function Vector(x, y, z)
    return setmetatable({ x = x, y = y, z = z or 0 }, vector_meta)
end

local entities = {}
function EntIndexToHScript(entindex) return entities[tonumber(entindex)] end

local issued_orders = {}
function ExecuteOrderFromTable(order)
    issued_orders[#issued_orders + 1] = order
end

local auto_candidates = {}
function FindUnitsInRadius() return auto_candidates end

local function make_building(index, x, health, player_id)
    local unit = {
        index = index,
        position = Vector(x, 0, 0),
        health = health,
        max_health = 1000,
        alive = true,
        team = 2,
        survival_player_id = player_id or 0,
        survival_is_building = true,
        modifiers = {},
    }
    function unit:IsNull() return false end
    function unit:IsAlive() return self.alive end
    function unit:entindex() return self.index end
    function unit:GetTeamNumber() return self.team end
    function unit:GetAbsOrigin() return self.position end
    function unit:GetHullRadius() return 100 end
    function unit:GetHealth() return self.health end
    function unit:GetMaxHealth() return self.max_health end
    function unit:SetHealth(value) self.health = value end
    function unit:HasModifier(name) return self.modifiers[name] == true end
    entities[index] = unit
    return unit
end

local repair_class = require("modifiers/modifier_repair_worker_ai")

local function make_repair_unit(index, unit_type)
    local unit = {
        index = index,
        position = Vector(0, 0, 0),
        alive = true,
        team = 2,
        survival_player_id = 0,
        survival_worker_type = unit_type == "repairer" and "repairer" or nil,
        survival_builder_id = unit_type == "builder" and "default_builder" or nil,
        idle = false,
        gestures = 0,
    }
    function unit:IsNull() return false end
    function unit:IsAlive() return self.alive end
    function unit:entindex() return self.index end
    function unit:GetTeamNumber() return self.team end
    function unit:GetAbsOrigin() return self.position end
    function unit:GetHullRadius() return 24 end
    function unit:IsIdle() return self.idle end
    function unit:IsChanneling() return false end
    function unit:GetCurrentActiveAbility() return nil end
    function unit:FaceTowards(position) self.facing = position end
    function unit:StartGesture() self.gestures = self.gestures + 1 end
    function unit:FindModifierByName(name)
        if name == "modifier_repair_worker_ai" then return self.repair_modifier end
        return nil
    end

    local modifier = setmetatable({ parent = unit }, { __index = repair_class })
    function modifier:GetParent() return self.parent end
    function modifier:StartIntervalThink(interval) self.interval = interval end
    unit.repair_modifier = modifier
    entities[index] = unit
    modifier:OnCreated({
        repair_max_health_pct_per_second = 2,
        repair_range = 600,
        detection_range = 5000,
    })
    return unit, modifier
end

local repairer, repairer_modifier = make_repair_unit(10, "repairer")
local builder, builder_modifier = make_repair_unit(11, "builder")
local selected_wall = make_building(20, 2000, 500, 0)
local nearby_wall = make_building(21, 100, 400, 0)

local repair_orders = require("systems/repair_order_service")
local tree_filter = require("systems/tree_attack_order_filter")

local right_click = {
    order_type = DOTA_UNIT_ORDER_MOVE_TO_TARGET,
    entindex_target = selected_wall:entindex(),
    units = { repairer:entindex(), builder:entindex() },
}
builder.survival_build_task = { building_id = "arrow_tower" }
assert(tree_filter._filter_for_test(nil, right_click) == false,
    "repair right click was not consumed")
assert(repairer_modifier.manual_repair_target_entindex == selected_wall:entindex(),
    "repairer did not retain the clicked wall")
assert(builder_modifier.manual_repair_target_entindex == selected_wall:entindex(),
    "builder did not retain the clicked wall")
assert(builder.survival_build_task == nil,
    "builder right-click repair did not cancel its pending build task")
assert(#issued_orders == 2
    and issued_orders[1].OrderType == DOTA_UNIT_ORDER_STOP
    and issued_orders[2].OrderType == DOTA_UNIT_ORDER_STOP,
    "right-click repair did not interrupt previous unit movement")

auto_candidates = { nearby_wall }
issued_orders = {}
repairer_modifier:OnIntervalThink()
assert(#issued_orders == 1
    and issued_orders[1].OrderType == DOTA_UNIT_ORDER_MOVE_TO_POSITION,
    "out-of-range repair did not issue a move order")
assert(selected_wall.health == 500 and nearby_wall.health == 400,
    "out-of-range repair changed health or selected the automatic target")

repairer.position = Vector(1300, 0, 0)
repairer_modifier:OnIntervalThink()
assert(#issued_orders == 2 and issued_orders[2].OrderType == DOTA_UNIT_ORDER_STOP,
    "entering repair range did not stop movement")
assert(selected_wall.health == 505,
    "in-range manual target was not repaired at two percent per second")
assert(nearby_wall.health == 400,
    "nearby automatic target overrode the clicked wall")

local orders_before_builder = #issued_orders
builder.position = Vector(1300, 0, 0)
builder_modifier:OnIntervalThink()
assert(#issued_orders == orders_before_builder,
    "builder already in range issued an unnecessary movement order")
assert(selected_wall.health == 510,
    "builder did not use the same right-click repair behavior")

selected_wall.health = 995
repairer_modifier:OnIntervalThink()
assert(selected_wall.health == 1000,
    "repair did not clamp health at maximum")
assert(repairer_modifier.manual_repair_target_entindex == nil,
    "full-health target did not clear manual repair state")

selected_wall.health = 500
assert(repair_orders.process(right_click) == true,
    "damaged wall could not be selected again")
repairer.survival_repair_internal_order = true
assert(repair_orders.process({
    order_type = DOTA_UNIT_ORDER_MOVE_TO_POSITION,
    units = { repairer:entindex() },
}) == false, "internal movement order was consumed")
repairer.survival_repair_internal_order = nil
assert(repairer_modifier.manual_repair_target_entindex == selected_wall:entindex(),
    "internal movement order cleared the manual target")

assert(repair_orders.process({
    order_type = DOTA_UNIT_ORDER_MOVE_TO_POSITION,
    units = { repairer:entindex() },
}) == false, "ordinary movement order was unexpectedly consumed")
assert(repairer_modifier.manual_repair_target_entindex == nil,
    "ordinary player order did not cancel manual repair")

selected_wall.health = 500
repairer.position = Vector(0, 0, 0)
assert(repair_orders.process({
    order_type = DOTA_UNIT_ORDER_MOVE_TO_TARGET,
    entindex_target = selected_wall:entindex(),
    units = { repairer:entindex() },
}) == true, "invalid-target cleanup setup failed")
repairer_modifier:OnIntervalThink()
local invalid_cleanup_order_count = #issued_orders
selected_wall.alive = false
repairer_modifier:OnIntervalThink()
assert(#issued_orders == invalid_cleanup_order_count + 1
    and issued_orders[#issued_orders].OrderType == DOTA_UNIT_ORDER_STOP,
    "invalid target did not stop an approaching repair unit")
assert(repairer_modifier.manual_repair_target_entindex == nil,
    "invalid target did not clear manual repair state")
selected_wall.alive = true

local foreign_wall = make_building(22, 100, 500, 1)
assert(repair_orders.process({
    order_type = DOTA_UNIT_ORDER_MOVE_TO_TARGET,
    entindex_target = foreign_wall:entindex(),
    units = { repairer:entindex() },
}) == false, "another player's wall was accepted for repair")

selected_wall.modifiers.modifier_building_under_construction = true
assert(repair_orders.process(right_click) == false,
    "building under construction was accepted for repair")
selected_wall.modifiers.modifier_building_under_construction = nil

local tree = {
    index = 30,
    IsNull = function() return false end,
    GetUnitName = function() return "enemy_tree" end,
}
local arrow_tower = {
    index = 31,
    survival_building_id = "arrow_tower",
    IsNull = function() return false end,
    entindex = function(self) return self.index end,
}
entities[30] = tree
entities[31] = arrow_tower
assert(tree_filter._filter_for_test(nil, {
    order_type = DOTA_UNIT_ORDER_ATTACK_TARGET,
    entindex_target = 30,
    units = { 31 },
}) == false, "repair integration broke the arrow-tower tree restriction")
assert(tree_filter._filter_for_test(nil, {
    order_type = DOTA_UNIT_ORDER_MOVE_TO_POSITION,
    units = { 31 },
}) == true, "repair integration rejected an unrelated order")

print("REPAIR_RIGHT_CLICK_LUA_PASS")