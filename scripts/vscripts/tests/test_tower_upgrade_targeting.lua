package.path = "scripts/vscripts/?.lua;" .. package.path
local bus = require("core/event_bus")
local events = require("core/events")
local config = require("config/buildings_config")
local noop = function() end
-- Keep construction, upgrade events, combat range policy and targeting real.
-- Only unrelated visual/persistent/skill systems and engine entities are mocked.
for _, name in ipairs({"tower_skill_runtime", "tower_ability_sync", "building_population_service",
    "building_visual_service", "asset_preload_service", "building_sound_service", "tower_utility_ability_sync",
    "wall_destruction_visual", "building_construction_visual_service", "war3_armor_target",
    "wall_collision_barrier_service", "online_time_service"}) do
    package.loaded["systems/" .. name] = {reset = noop, apply = noop, sync = noop, grant_level = noop,
        construction_started = noop, construction_completed = noop, upgrade_completed = noop,
        queue_particle = noop, complete = noop, cancel = noop, start = function() return {} end}
end
package.loaded["systems/building_relocation"] = {bind = noop}
package.loaded["debug/dev_wall_stats"] = {apply = noop, reset = noop}
package.loaded["core/team_alignment"] = {enforce = noop}
package.loaded["systems/rogue_effect_state_service"] = {numeric = function() return 0 end, wall_health_flat = function() return 0 end}
local technology, permanent = {tower = {}}, {}
package.loaded["systems/technology_stat_manager"] = {get = function() return {final = technology} end}
package.loaded["systems/player_profile_service"] = {get_profile = function() return nil end}
local pending
package.loaded["systems/building_upgrade_process"] = {
    reset = function() pending = nil end,
    is_active = function(unit) return pending ~= nil and pending.unit == unit end,
    begin = function(unit, options)
        pending = {unit = unit, options = options}; options.on_start(); return {ok = true, pending = true}
    end,
}

class = function(value) return value end
LinkLuaModifier = noop
IsServer = function() return true end
LUA_MODIFIER_MOTION_NONE, MODIFIER_ATTRIBUTE_PERMANENT, MODIFIER_EVENT_ON_ATTACK_START = 0, 1, 2
DOTA_UNIT_CAP_RANGED_ATTACK, DOTA_UNIT_CAP_MOVE_NONE, DOTA_TEAM_GOODGUYS = 2, 0, 2
DOTA_UNIT_TARGET_TEAM_ENEMY, DOTA_UNIT_TARGET_HERO, DOTA_UNIT_TARGET_BASIC = 1, 2, 4
DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES, FIND_CLOSEST, ACT_DOTA_ATTACK = 8, 1, 3
DOTA_UNIT_ORDER_MOVE_TO_POSITION = 1
local vector_mt = {}
Vector = function(x, y, z) return setmetatable({x = x, y = y, z = z or 0}, vector_mt) end
vector_mt.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
vector_mt.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
vector_mt.__mul = function(a, b) return Vector(a.x * b, a.y * b, a.z * b) end
vector_mt.__index = {
    Length2D = function(v) return math.sqrt(v.x * v.x + v.y * v.y) end,
    Normalized = function(v) local length = v:Length2D(); return Vector(v.x / length, v.y / length, 0) end,
}
local time, next_index, units, candidates = 0, 0, {}, {}
GameRules = {GetGameTime = function() return time end}
GetGroundHeight = function() return 0 end
GridNav = {IsTraversable = function() return true end, IsBlocked = function() return false end}
PlayerResource = {GetTeam = function() return 2 end}
Entities = {FindAllByClassname = function() return units end}
FindUnitsInRadius = function() return candidates end
local modifier_class = require("modifiers/modifier_tower_auto_attack")
local function create_unit(name, position, team)
    next_index = next_index + 1
    local u = {name = name, index = next_index, position = position, team = team or 2,
        max_health = 100, health = 100, modifiers = {}, abilities = {}, acquisition = 1000, attack_range = 1000,
        acquisition_writes = {}, survival_player_id = 0, base_damage = 1}
    function u:IsNull() return false end
    function u:IsAlive() return true end
    function u:entindex() return self.index end
    function u:GetUnitName() return self.name end
    function u:GetAbsOrigin() return self.position end
    function u:SetAbsOrigin(value) self.position = value end
    function u:GetForwardVector() return Vector(1, 0, 0) end
    function u:GetHullRadius() return 0 end
    function u:GetTeamNumber() return self.team end
    function u:GetPlayerOwnerID() return 0 end
    function u:GetMaxHealth() return self.max_health end
    function u:SetMaxHealth(value) self.max_health = value end
    function u:GetHealth() return self.health end
    function u:SetHealth(value) self.health = value end
    function u:GetBaseDamageMin() return self.base_damage end
    function u:SetBaseDamageMin(value) self.base_damage = value end
    function u:GetPhysicalArmorBaseValue() return self.armor or 0 end
    function u:SetPhysicalArmorBaseValue(value) self.armor = value end
    function u:Script_SetAttackRange(value) self.attack_range = value end
    function u:Script_GetAttackRange() return self.attack_range end
    -- Simulate a stale fallback getter: the script range remains authoritative
    -- even when another getter returns a different value in this mock.
    function u:GetAttackRange() return self.acquisition end
    function u:GetAcquisitionRange() return self.acquisition end
    function u:SetAcquisitionRange(value)
        self.acquisition = value; self.acquisition_writes[#self.acquisition_writes + 1] = value
    end
    function u:GetAttackTarget() return self.target end
    function u:SetForceAttackTarget(target) self.target = target end
    function u:Stop() self.target = nil end
    function u:HasModifier(name) return self.modifiers[name] ~= nil end
    function u:FindModifierByName(name) return self.modifiers[name] end
    function u:RemoveModifierByName(name) self.modifiers[name] = nil end
    function u:AddNewModifier(_, _, name)
        local modifier = {}
        if name == "modifier_tower_auto_attack" then
            modifier = setmetatable({GetParent = function() return self end,
                GetStackCount = function(m) return m.stack or 0 end,
                SetStackCount = function(m, value) m.stack = value end,
                ForceRefresh = noop,
                StartIntervalThink = function(m, interval) m.interval = interval end}, {__index = modifier_class})
            modifier:OnCreated()
        end
        self.modifiers[name] = modifier; return modifier
    end
    function u:FindAbilityByName(name) return self.abilities[name] end
    function u:AddAbility(name)
        local a = {SetLevel = noop, GetLevel = function() return 1 end, SetHidden = noop,
            SetActivated = function(self, value) self.active = value end, IsActivated = function(self) return self.active end,
            GetAbilityIndex = function() return 0 end, IsNull = function() return false end,
            entindex = function() return 100 + self.index end}
        self.abilities[name] = a; return a
    end
    for _, method in ipairs({"SetOwner", "SetMoveCapability", "SetHullRadius", "SetBaseMaxHealth",
        "SetBaseDamageMax", "SetBaseAttackTime", "SetRangedProjectileName", "SetProjectileSpeed", "SetModel",
        "SetOriginalModel", "SetModelScale", "SetAngles", "SetAttackCapability", "SetControllableByPlayer",
        "StartGesture", "RemoveGesture"}) do u[method] = noop end
    units[#units + 1] = u
    return u
end
local last_created
CreateUnitByName = function(name, position, _, _, _, team)
    last_created = create_unit(name, position, team); return last_created
end
ExecuteOrderFromTable = function(order) units[order.UnitIndex]:SetAbsOrigin(order.Position) end
local scheduler = require("core/scheduler")
local building = require("systems/building_system")
local upgrade = require("systems/building_upgrade_system")
local builder = create_unit("npc_survival_builder", Vector(300, 0, 0))
local city = create_unit("building_main_city", Vector(1000, 1000, 0))
city.survival_is_building, city.survival_building_id, city.survival_level = true, "main_city", 1
city.survival_grid_x, city.survival_grid_y = 16, 16
city.survival_grid_footprint = config.main_city.footprint
building.init(); upgrade.init()
bus.handle_request(events.BUILDER_GET_REQUEST, function() return {ok = true, builder = builder, player_id = 0} end)
bus.handle_request(events.GRID_CAN_PLACE_REQUEST, function(payload)
    return {ok = true, grid_x = 0, grid_y = 0, world_position = payload.position}
end)
bus.handle_request(events.GRID_OCCUPY_REQUEST, function() return {ok = true} end)
bus.handle_request(events.RESOURCE_TRY_SPEND_REQUEST, function() return {ok = true} end)
bus.handle_request(events.PERMANENT_REWARD_EFFECTS_GET_REQUEST, function() return {totals = permanent} end)
local created_events = 0
bus.subscribe(events.BUILDING_CREATED, function(payload) if payload.building_id == "arrow_tower" then created_events = created_events + 1 end end)
local result = bus.request(events.BUILD_REQUEST, {caster = builder, player_id = 0, building_id = "arrow_tower", position = Vector(0, 0, 0)})
assert(result and result.ok, "real construction request starts: " .. tostring(result and result.error))
for step = 1, math.ceil(((config.arrow_tower.build_time or 3) + 2) * 10) do
    time = step * 0.1; scheduler.think()
end
local tower = assert(last_created)
assert(created_events == 1 and not tower:HasModifier("modifier_building_under_construction"), "actual scheduled construction completes and publishes BUILDING_CREATED once")
local auto = assert(tower:FindModifierByName("modifier_tower_auto_attack"), "construction installs targeting")
assert(tower:HasModifier("modifier_tower_attack_effects"))
local base_range = require("config/tower_combat_rules").attack_range()
local tree = create_unit("enemy_tree", Vector(50, 0, 0), 3)
local enemy = create_unit("npc_survival_enemy", Vector(200, 0, 0), 3)
local function check_targeting(expected_range)
    assert(tower.acquisition == 0 and tower:Script_GetAttackRange() == expected_range)
    auto:ResetTarget(); candidates = {tree, enemy}; auto:OnIntervalThink()
    assert(tower.target == enemy, "ordinary enemy remains attackable while nearer tree is skipped")
    auto:ResetTarget(); candidates = {tree}; auto:OnIntervalThink()
    assert(tower.target == nil, "tree alone never becomes a tower target")
end
check_targeting(base_range)
result = bus.request(events.BUILDING_UPGRADE_REQUEST, {building = tower, upgrade_mode = "one", silent_notification = true})
assert(result and result.ok and pending)
local action = pending; pending = nil; action.options.on_complete()
assert(tower.survival_level == 2, "real upgrade event advances the tower level")
check_targeting(base_range)

technology.tower.attack_range_bonus = 250
bus.emit(events.TECHNOLOGY_STATS_CHANGED, {player_id = 0, reason = "technology_test"})
assert(tower:FindModifierByName("modifier_tower_auto_attack") == auto, "technology keeps existing targeting modifier")
enemy.position = Vector(base_range + 180, 0, 0)
check_targeting(base_range + 250)
permanent.tower_attack_range = 100
bus.emit(events.PERMANENT_REWARD_EFFECTS_CHANGED, {player_id = 0, reason = "lottery_test"})
enemy.position = Vector(base_range + 300, 0, 0)
check_targeting(base_range + 350)

-- A hot-reloaded upgrade subsystem may recover a tower solely from a technology
-- event, without building_system recovery or any BUILDING_CREATED notification.
tower.modifiers.modifier_tower_auto_attack = nil
tower.acquisition = 1000
bus.reset(); upgrade.init()
bus.handle_request(events.PERMANENT_REWARD_EFFECTS_GET_REQUEST, function() return {totals = permanent} end)
bus.emit(events.TECHNOLOGY_STATS_CHANGED, {player_id = 0, reason = "technology_recovery_test"})
auto = assert(tower:FindModifierByName("modifier_tower_auto_attack"), "technology-only recovery reinstalls missing targeting")
check_targeting(base_range + 350)

-- Recover a live legacy tower whose targeting modifiers were absent.
tower.modifiers.modifier_tower_auto_attack = nil
tower.modifiers.modifier_tower_attack_effects = nil
tower.acquisition = 1000
bus.reset(); building.init()
auto = assert(tower:FindModifierByName("modifier_tower_auto_attack"), "recovery reinstalls missing targeting")
assert(tower:HasModifier("modifier_tower_attack_effects") and tower.acquisition == 0)
check_targeting(base_range + 350)
for _, value in ipairs(tower.acquisition_writes) do assert(value == 0, "no construction/upgrade/technology/recovery path re-enables native acquisition even transiently") end
print("TOWER_UPGRADE_TARGETING_PASS: actual construction, upgrade completion, technology/permanent range changes, technology-only and building recovery, zero native acquisition and ordinary-enemy targeting")
