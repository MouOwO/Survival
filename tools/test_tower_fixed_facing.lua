package.path = "scripts/vscripts/?.lua;" .. package.path
class = function(t) t.__index = t; return t end
LUA_MODIFIER_MOTION_NONE, MODIFIER_ATTRIBUTE_PERMANENT = 0, 1
MODIFIER_PROPERTY_DISABLE_TURNING, MODIFIER_PROPERTY_IGNORE_CAST_ANGLE = 2, 3
local links = {}
LinkLuaModifier = function(name, path) links[name] = path end
IsServer = function() return true end

local fixed_facing = require("systems/tower_fixed_facing")
local properties = require("modifiers/modifier_tower_fixed_facing")
local auto_attack = require("modifiers/modifier_tower_auto_attack")
local name = "modifier_tower_fixed_facing"
assert(links[name] == "modifiers/modifier_tower_fixed_facing")
assert(properties:GetModifierDisableTurning() == 1 and properties:GetModifierIgnoreCastAngle() == 1)
local declared = properties:DeclareFunctions()
assert(declared[1] == MODIFIER_PROPERTY_DISABLE_TURNING and declared[2] == MODIFIER_PROPERTY_IGNORE_CAST_ANGLE)
assert(properties:GetAttributes() == MODIFIER_ATTRIBUTE_PERMANENT and not properties:IsPurgable())
assert(properties.OnIntervalThink == nil and properties.OnCreated == nil, "fixed facing cannot add a polling loop")

local vector_mt = {__index = {Normalized = function(v)
    local length = math.sqrt(v.x * v.x + v.y * v.y)
    return {x = v.x / length, y = v.y / length, z = 0}
end}}
vector_mt.__sub = function(a, b)
    return setmetatable({x = a.x - b.x, y = a.y - b.y, z = a.z - b.z}, vector_mt)
end
local function position(x, y) return setmetatable({x = x, y = y, z = 0}, vector_mt) end
local function unit(unit_name)
    local tower = {modifiers = {}, facing = {x = 1, y = 0, z = 0}, facing_writes = 0,
        orders = 0, additions = 0, removals = 0, origin = position(0, 0)}
    function tower:IsNull() return self.removed == true end
    function tower:IsAlive() return true end
    function tower:GetUnitName() return unit_name or "building_arrow_tower" end
    function tower:GetAbsOrigin() return self.origin end
    function tower:HasModifier(id) return self.modifiers[id] ~= nil end
    function tower:AddNewModifier(caster, ability, id)
        assert(caster == self and ability == nil and id == name)
        self.modifiers[id] = properties; self.additions = self.additions + 1
    end
    function tower:RemoveModifierByName(id)
        assert(id == name and self.modifiers[id]); self.modifiers[id] = nil; self.removals = self.removals + 1
    end
    function tower:SetForwardVector(value) self.facing = value; self.facing_writes = self.facing_writes + 1 end
    function tower:SetForceAttackTarget(target) self.target = target end
    function tower:MoveToTargetToAttack(target) assert(target == self.target); self.orders = self.orders + 1 end
    return tower
end
local tower = unit()
for _ = 1, 100 do assert(fixed_facing.apply(tower, "")) end
assert(tower.additions == 1 and tower.removals == 0, "repeated configuration must reuse one modifier")
local ai = setmetatable({GetParent = function() return tower end}, auto_attack)
local target = unit("wave_monster")
for _, point in ipairs({position(0, 600), position(-600, 0), position(0, -600)}) do
    target.origin = point
    ai:IssueAttackTarget(target, true)
    assert(tower.target == target and ai.forced_target == target)
    assert(tower.facing.x == 1 and tower.facing.y == 0 and tower.facing_writes == 0,
        "side/back targets cannot rotate the base arrow model")
end
assert(tower.orders == 3, "fixed facing must retain native attack orders instead of granting synthetic hits")

-- A route change is applied before the entity's old class field is replaced.
assert(not fixed_facing.apply(tower, "class_1") and tower.removals == 1)
target.origin = position(0, 600)
ai:IssueAttackTarget(target, true)
assert(tower.facing_writes == 1 and tower.facing.y == 1 and tower.orders == 4,
    "hero route models retain their existing target-facing attack behavior")
tower.survival_tower_class = "class_1"
assert(not fixed_facing.apply(tower))
assert(fixed_facing.apply(tower, "") and tower.additions == 2,
    "explicit base class restoration overrides a stale route field")
assert(not fixed_facing.apply(unit("npc_dota_unit_ultimate_tower"), ""))
local ultimate = unit(); ultimate.survival_ultimate_tower = true
assert(not fixed_facing.apply(ultimate, ""))
local invalid = unit(); invalid.removed = true
assert(not fixed_facing.apply(invalid, ""))
IsServer = function() return false end
assert(properties:GetModifierDisableTurning() == 1 and properties:GetModifierIgnoreCastAngle() == 1,
    "client properties cannot depend on server-only custom unit fields")
print("TOWER_FIXED_FACING_PASS: replicated no-turn/angle properties, zero polling, reuse/removal, side/back native orders and hero route orientation")
