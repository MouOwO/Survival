package.path = "scripts/vscripts/?.lua;" .. package.path

-- Invoke the real fusion request and real targeting modifier with small engine
-- mocks. This catches an omitted modifier at the actual creation boundary.
local bus = require("core/event_bus")
local events = require("core/events")
local rules = require("systems/tree_damage_rules")
package.loaded["config/tower_route_config"] = {
    get_route = function() return {{level = 10, base_attack_damage = 10}} end,
}
package.loaded["systems/tower_skill_runtime"] = {apply = function() end}
package.loaded["systems/tower_ability_sync"] = {sync = function() end}
class = function(value) return value end
LinkLuaModifier = function() end
IsServer = function() return true end
LUA_MODIFIER_MOTION_NONE, MODIFIER_ATTRIBUTE_PERMANENT, MODIFIER_EVENT_ON_ATTACK_START = 0, 1, 2
DOTA_UNIT_CAP_RANGED_ATTACK = 2
DOTA_UNIT_TARGET_TEAM_ENEMY, DOTA_UNIT_TARGET_HERO, DOTA_UNIT_TARGET_BASIC = 1, 2, 4
DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES, FIND_CLOSEST = 8, 1
DOTA_UNIT_ORDER_MOVE_TO_POSITION, DOTA_UNIT_ORDER_ATTACK_MOVE, DOTA_UNIT_ORDER_ATTACK_TARGET = 1, 2, 3
local vector_mt = {}
Vector = function(x, y, z) return setmetatable({x = x, y = y, z = z or 0}, vector_mt) end
vector_mt.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
vector_mt.__index = {Length2D = function(v) return math.sqrt(v.x * v.x + v.y * v.y) end}
local auto_attack = require("modifiers/modifier_tower_auto_attack")
local entities, created, candidate_units, consumed, fail_modifier = {}, nil, {}, 0, false
local function unit(name, index, team, position)
    local result = {name = name, index = index, team = team, position = position,
        health = 100, max_health = 100, armor = 2, modifiers = {}, abilities = {}, survival_player_id = 0}
    function result:IsNull() return self.removed == true end
    function result:IsAlive() return not self.removed end
    function result:entindex() return self.index end
    function result:GetUnitName() return self.name end
    function result:GetTeamNumber() return self.team end
    function result:GetPlayerOwnerID() return 0 end
    function result:GetAbsOrigin() return self.position end
    function result:SetAbsOrigin(value) self.position = value end
    function result:GetMaxHealth() return self.max_health end
    function result:GetHealth() return self.health end
    function result:GetPhysicalArmorBaseValue() return self.armor end
    function result:GetAverageTrueAttackDamage() return 12 end
    function result:GetAttackRange() return 1000 end
    function result:GetAttackTarget() return self.target end
    function result:SetForceAttackTarget(target) self.target = target end
    function result:Stop() self.target = nil self.stopped = true end
    function result:SetAcquisitionRange(value) self.acquisition = value end
    function result:SetMaxHealth(value) self.max_health = value end
    function result:SetHealth(value) self.health = value end
    function result:AddAbility(name)
        local ability = {SetLevel = function() end, SetHidden = function() end, SetActivated = function() end}
        self.abilities[name] = ability
        return ability
    end
    function result:AddNewModifier(_, _, name)
        if name == "modifier_tower_auto_attack" and fail_modifier then return nil end
        local modifier = {}
        if name == "modifier_tower_auto_attack" then
            modifier = setmetatable({GetParent = function() return self end,
                GetStackCount = function(m) return m.stack or 0 end,
                SetStackCount = function(m, value) m.stack = value end,
                ForceRefresh = function() end,
                StartIntervalThink = function(m, seconds) m.interval = seconds end}, {__index = auto_attack})
            modifier:OnCreated()
        end
        self.modifiers[name] = modifier
        return modifier
    end
    function result:FindModifierByName(name) return self.modifiers[name] end
    function result:RemoveSelf() self.removed = true end
    for _, name in ipairs({"SetPlayerID", "SetOwner", "SetControllableByPlayer", "SetAttackCapability",
        "SetModel", "SetOriginalModel", "SetBaseMaxHealth", "SetPhysicalArmorBaseValue", "SetBaseDamageMin",
        "SetBaseDamageMax", "SetBaseAttackTime"}) do result[name] = function() end end
    entities[index] = result
    return result
end
CreateUnitByName = function(name, position, _, _, _, team)
    created = unit(name, 200, team, position)
    return created
end
PlayerResource = {GetPlayer = function() return {} end}
EntIndexToHScript = function(index) return entities[index] end
FindUnitsInRadius = function() return candidate_units end
local material = {}
for index = 1, 7 do
    local tower = unit("building_arrow_tower", index, 2, Vector(index * 20, 0, 0))
    material[#material + 1] = {unit = tower, entindex = index, player_id = 0, building_id = "arrow_tower",
        tower_class = "class_" .. index, route_level = 10, level = 10, definition = {footprint = {x = 2, y = 2}}}
end
local fusion = require("systems/tower_fusion_service")
local function initialize()
    bus.reset(); fusion.init(); consumed = 0
    bus.handle_request(events.BUILDING_LIST_REQUEST, function() return {buildings = material} end)
    bus.handle_request(events.GRID_CAN_PLACE_REQUEST, function(payload)
        return {ok = true, grid_x = 0, grid_y = 0, world_position = payload.position}
    end)
    bus.handle_request(events.GRID_OCCUPY_REQUEST, function() return {ok = true} end)
    bus.handle_request(events.BUILDING_FUSION_CONSUME_REQUEST, function(payload)
        assert(#payload.entindexes == 7); consumed = consumed + 1; return {ok = true}
    end)
end
initialize()
local result = bus.request(events.TOWER_FUSION_REQUEST, {caster = material[1].unit})
assert(result and result.ok and consumed == 1, "all seven routes fuse through the real request handler")
local tower = result.unit
assert(tower.survival_ultimate_tower and tower.survival_building_id == nil, "preserve ultimate business identity")
assert(rules.is_arrow_tower(tower) and not rules.is_allowed_tree_attacker(tower))
assert(tower.acquisition == 0, "native acquisition stays disabled")
local modifier = assert(tower:FindModifierByName("modifier_tower_auto_attack"), "fusion installs shared targeting")
assert(modifier.interval > 0)
local tree = unit("enemy_tree", 301, 3, Vector(30, 0, 0))
local enemy = unit("npc_survival_enemy", 302, 3, Vector(100, 0, 0))
candidate_units = {tree, enemy}
modifier:OnIntervalThink()
assert(tower.target == enemy, "fusion tower skips closer resource tree and attacks ordinary enemy")
modifier:ResetTarget(); candidate_units = {tree}; tower.target = nil
modifier:OnIntervalThink()
assert(tower.target == nil, "only a tree nearby yields no tower attack")
modifier:SetManualTarget(tree)
assert(tower.target == nil, "manual selection cannot target the tree")

package.loaded["systems/repair_order_service"] = {process = function() return false end}
package.loaded["systems/lumberjack_order_service"] = {process = function() end}
package.loaded["systems/destination_validation_service"] = {is_constrained_hero = function() return false end}
package.loaded["systems/player_context_service"] = {owner_player_id = function() return 0 end}
package.loaded["systems/startup_loading_service"] = {is_ready = function() return true end,
    is_player_ready = function(id) return id == 0 end}
local filter = require("systems/tree_attack_order_filter")._filter_for_test
local keys = {issuer_player_id_const = 0, units = {["0"] = tower:entindex()},
    order_type = DOTA_UNIT_ORDER_ATTACK_TARGET, entindex_target = tree:entindex()}
assert(filter(nil, keys) == false, "real order filter denies ultimate tower orders against the tree")
keys.entindex_target = enemy:entindex()
assert(filter(nil, keys) == true and tower.target == enemy, "normal enemy orders still acquire the target")

fail_modifier = true; initialize()
result = bus.request(events.TOWER_FUSION_REQUEST, {caster = material[1].unit})
assert(result and not result.ok and created.removed and consumed == 0,
    "targeting initialization failure discards the new tower without consuming materials")
print("ULTIMATE_TOWER_TREE_TARGETING_PASS: real fusion, modifier installation, ordinary targets, automatic/manual tree rejection, order filter and failed-init rollback")
