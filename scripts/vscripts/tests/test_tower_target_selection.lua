package.path = "scripts/vscripts/?.lua;" .. package.path

class = function(t) return t end
LinkLuaModifier = function() end
IsServer = function() return true end
DOTA_UNIT_TARGET_TEAM_ENEMY = 1
DOTA_UNIT_TARGET_HERO = 1
DOTA_UNIT_TARGET_BASIC = 2
DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES = 1
FIND_CLOSEST = 0

local rules = require("config/tower_combat_rules")
local auto = require("modifiers/modifier_tower_auto_attack")
local vector_meta = {}
vector_meta.__sub = function(a, b)
    return { Length2D = function() return math.abs(a.x - b.x) end }
end
local function unit(name, distance, team)
    return {
        name = name, alive = true, team = team or 3,
        pos = setmetatable({ x = distance or 0 }, vector_meta),
        IsNull = function() return false end,
        IsAlive = function(self) return self.alive end,
        GetUnitName = function(self) return self.name end,
        GetTeamNumber = function(self) return self.team end,
        GetAbsOrigin = function(self) return self.pos end,
        entindex = function() return 101 end,
    }
end
local tower = unit("building_arrow_tower", 0, 2)
tower.range, tower.acquisition, tower.stops, tower.orders = 1000, 1000, 0, 0
tower.survival_building_id = "arrow_tower"
function tower:Script_SetAttackRange(n) self.range = n end
function tower:Script_GetAttackRange() return self.range end
function tower:GetAttackRange() return 300 end -- stale native fallback must lose to the script range
function tower:SetAcquisitionRange(n) self.acquisition = n end
function tower:GetAcquisitionRange() return self.acquisition end
function tower:GetAttackTarget() return self.target end
function tower:SetForceAttackTarget(target) self.forced = target self.orders = self.orders + 1 end
function tower:Stop() self.target = nil self.stops = self.stops + 1 end
local modifier = setmetatable({ GetParent = function() return tower end,
    GetStackCount = function(self) return self.stack or 0 end,
    SetStackCount = function(self, value) self.stack = value end,
    ForceRefresh = function() end,
    StartIntervalThink = function() end }, { __index = auto })
modifier:OnCreated()
assert(tower.acquisition == 0, "construction must disable native tree acquisition")

local tree = unit("enemy_tree", 30)
local enemy = unit("enemy_wave", 900)
local dummy = unit("training_dummy", 80)
dummy.survival_is_training_dummy = true
local second_dummy = unit("training_dummy", 90)
second_dummy.survival_is_training_dummy = true
local units, queried_radius = {}, 0
FindUnitsInRadius = function(_, _, _, radius)
    queried_radius = radius
    return units
end
units = { tree, dummy, second_dummy, enemy }
assert(auto._find_target_for_test(tower) == enemy,
    "skip a closer tree and prioritize a combat enemy over the training dummy")
assert(queried_radius >= 1000, "script attack range must not shrink to native fallback or acquisition=0")
units = { tree, dummy }
assert(auto._find_target_for_test(tower) == dummy, "training dummy remains a legal fallback")
units = { tree }
assert(auto._find_target_for_test(tower) == nil, "idle towers must not use trees as fallback")
tree.survival_is_training_dummy = true
assert(auto._find_target_for_test(tower) == nil, "dummy metadata cannot turn resource trees into targets")
tree.survival_is_training_dummy = nil

modifier:SetManualTarget(tree)
assert(modifier.manual_target == nil and tower.forced == nil, "manual tree targets are rejected")
modifier:SetManualTarget(enemy)
assert(modifier.manual_target == enemy and tower.forced == enemy, "manual enemy target remains supported")
units = { tree, dummy, enemy }
modifier:OnIntervalThink()
assert(tower.forced == enemy, "manual target is preserved while legal")

-- Model an already upgraded tower carrying a stale native attack from old code.
tower.acquisition, tower.target = 1000, tree
modifier.manual_target, modifier.forced_target, tower.forced = nil, tree, tree
local stops_before_stale_attack = tower.stops
modifier:OnIntervalThink()
assert(tower.acquisition == 0 and tower.stops == stops_before_stale_attack + 1,
    "legacy native acquisition and a running tree attack are both stopped")
assert(tower.forced == enemy, "the tower retargets to a legal enemy in the same interval")
local orders = tower.orders
tower.target = enemy
modifier:OnIntervalThink()
assert(tower.orders == orders, "a stable valid target must not receive repeated attack orders")

units, tower.target, tower.forced = { tree }, tree, tree
modifier.forced_target = tree
modifier:OnIntervalThink()
assert(tower.target == nil and tower.forced == nil, "with only trees nearby the tower becomes idle")
tower.target, tower.forced = tree, tree
modifier:OnAttackStart({ attacker = tower, target = tree })
assert(tower.target == nil and tower.forced == nil, "engine attack-start also cancels tree attacks")

-- Upgrade/research range changes preserve custom targeting, including bonus range.
for _, range in ipairs({ 1000, 1250, 1600 }) do
    tower.acquisition = 1000
    rules.set_attack_range(tower, range)
    assert(tower.acquisition == 0 and rules.current_attack_range(tower) == range,
        "stat refresh must retain range bonuses without re-enabling native AI")
end
tower.acquisition, tower.target = 1000, tree
modifier:ResetTarget()
assert(tower.acquisition == 0 and tower.target == nil, "upgrade/reset cancels stale tree attack")
local fallback = { GetAttackRange = function() return 1400 end }
assert(rules.current_attack_range(fallback) == 1400, "native getter is a valid compatibility fallback")
fallback.GetAttackRange = function() return 0 end
assert(rules.current_attack_range(fallback) == rules.attack_range(), "missing range falls back to game configuration")

tower.survival_tower_class = "class_7"
local flying = unit("enemy_flying", 600)
flying.survival_movement_type = "flying"
tree.survival_movement_type = "flying"
units = { tree, enemy, flying }
assert(auto._find_target_for_test(tower) == flying, "anti-air constraints still apply, including flying tree rejection")
print("TOWER_TARGET_SELECTION_PASS: native/stale/manual trees rejected; enemy, dummy, anti-air and upgraded ranges preserved")
