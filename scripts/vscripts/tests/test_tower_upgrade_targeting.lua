package.path = "scripts/vscripts/?.lua;" .. package.path
require("tests/development_release_profile")
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
-- Movement/footprint behavior has its own integration tests. This fixture
-- places the builder at an already validated construction work position.
package.loaded["systems/builder_work_position_service"] = {
    find = function(caster) return caster:GetAbsOrigin() end,
    ready = function() return true end,
}
package.loaded["debug/dev_wall_stats"] = {apply = noop, reset = noop}
package.loaded["core/team_alignment"] = {enforce = noop}
package.loaded["systems/rogue_effect_state_service"] = {numeric = function() return 0 end, wall_health_flat = function() return 0 end}
local technology, permanent = {tower = {}}, {}
local technology_service = {get = function() return {final = technology} end}
package.loaded["systems/technology_stat_manager"] = technology_service
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
MODIFIER_PROPERTY_ATTACK_RANGE_BASE_OVERRIDE = 13
DOTA_UNIT_CAP_RANGED_ATTACK, DOTA_UNIT_CAP_MOVE_NONE, DOTA_TEAM_GOODGUYS = 2, 0, 2
DOTA_UNIT_TARGET_TEAM_ENEMY, DOTA_UNIT_TARGET_HERO, DOTA_UNIT_TARGET_BASIC = 1, 2, 4
DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES, FIND_CLOSEST, ACT_DOTA_ATTACK = 8, 1, 3
FIND_ANY_ORDER = 0
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
local range_class = require("modifiers/modifier_survival_hero_attack_range")
assert(range_class:DeclareFunctions()[1] == MODIFIER_PROPERTY_ATTACK_RANGE_BASE_OVERRIDE,
    "the engine must actually invoke the registered range callback")
local function create_unit(name, position, team)
    next_index = next_index + 1
    local u = {name = name, index = next_index, position = position, team = team or 2,
        max_health = 100, health = 100, modifiers = {}, abilities = {}, acquisition = 1000, attack_range = 1000,
        acquisition_writes = {}, survival_player_id = 0, base_damage = 1}
    function u:IsNull() return false end
    function u:IsAlive() return self.alive ~= false end
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
    -- Live creatures do not expose either range setter. The actual registered
    -- modifier callback must change the range, not a convenient mock setter.
    function u:Script_GetAttackRange()
        local modifier = self.modifiers.modifier_survival_hero_attack_range
        return modifier and modifier:GetModifierAttackRangeOverride() or self.attack_range
    end
    function u:GetAttackRange() return self:Script_GetAttackRange() end
    function u:GetAcquisitionRange() return self.acquisition end
    function u:SetAcquisitionRange(value)
        self.acquisition = value; self.acquisition_writes[#self.acquisition_writes + 1] = value
    end
    function u:GetAttackTarget() return self.target end
    function u:SetForceAttackTarget(target) self.forced = target end
    function u:MoveToTargetToAttack(target) self.target = target end
    function u:SetContextThink(_, callback) self.next_frame = callback end
    function u:Stop() self.target = nil end
    function u:HasModifier(name) return self.modifiers[name] ~= nil end
    function u:FindModifierByName(name) return self.modifiers[name] end
    function u:RemoveModifierByName(name) self.modifiers[name] = nil end
    function u:AddNewModifier(_, _, name, params)
        local modifier = {}
        if name == "modifier_survival_hero_attack_range" then
            modifier = setmetatable({
                GetStackCount = function(m) return m.stack or 0 end,
                SetStackCount = function(m, value) m.stack = value end,
            }, {__index = range_class})
            modifier:OnCreated(params or {})
        elseif name == "modifier_tower_auto_attack" then
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
local grid_owner_queries = 0
bus.handle_request(events.GRID_CAN_PLACE_REQUEST, function(payload)
    assert(payload.player_id==0,"construction/relocation grid receives the validated owner")
    grid_owner_queries = grid_owner_queries + 1
    return {ok = true, grid_x = 0, grid_y = 0, world_position = payload.position}
end)
bus.handle_request(events.GRID_OCCUPY_REQUEST, function() return {ok = true} end)
bus.handle_request(events.RESOURCE_CAN_SPEND_REQUEST, function() return {ok = true} end)
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
local nearest = create_unit("npc_survival_nearest", Vector(100, 0, 0), 3)
candidates = {tree, enemy, nearest}
auto:SetManualTarget(enemy);tower.target = enemy
result = bus.request(events.BUILDING_UPGRADE_REQUEST, {building = tower, upgrade_mode = "one", silent_notification = true})
assert(result and result.ok and pending)
local action = pending; pending = nil; action.options.on_complete()
assert(tower.survival_level == 2, "real upgrade event advances the tower level")
assert(tower.target == nearest and auto.manual_target == nil,
    "upgrade completion must acquire nearest immediately without waiting for an AI interval")
-- Simulate the engine clearing its attack order after stat/model changes.
tower.target = nil;tower.next_frame()
assert(tower.target == nearest, "upgrade next-frame recovery must restore the selected order")
auto:OnDeath({unit = nearest});nearest.alive = false
assert(tower.target == enemy, "after real upgrade, death reacquires the next in-range target")
local later = create_unit("npc_survival_later", Vector(20, 0, 0), 3)
candidates = {tree, enemy, later}
for i=1,100 do auto:OnIntervalThink() end
assert(tower.target == enemy, "after real upgrade a nearer arrival must not steal a living target")
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

local fusion_refreshes, growth_updates, full_publications = 0, 0, 0
bus.subscribe(events.TOWER_FUSION_STATE_CHANGED, function() fusion_refreshes=fusion_refreshes+1 end)
bus.subscribe(events.BUILDING_CHANGED, function() full_publications=full_publications+1 end)
bus.subscribe(events.UNIT_COMBAT_STATS_CHANGED, function(payload)
    if payload.unit == tower then growth_updates=growth_updates+1 end
end)
for i=1,50 do
    permanent.tower_attack_flat = i
    bus.emit(events.PERMANENT_REWARD_EFFECTS_CHANGED,
        {player_id=0, changed_section="tower", changed_field="attack",
            tower_attack_flat=i, reason="gameplay_stats_tower_attack_growth"})
end
assert(growth_updates==50 and fusion_refreshes==0 and full_publications==0,
    "50 combat growth hits must not trigger whole-group fusion/ability refreshes")
local listed = assert(bus.request(events.BUILDING_LIST_REQUEST,
    {player_id=0, building_id="arrow_tower", handles_only=true}))
assert(#listed.buildings==1 and listed.buildings[1].unit==tower
    and listed.buildings[1].definition==nil,
    "lightweight registry returns only owned completed tower handles")
assert(#bus.request(events.BUILDING_LIST_REQUEST,
    {player_id=1, building_id="arrow_tower", handles_only=true}).buildings==0)
print("TOWER_GROWTH_FANOUT_PASS: 50 hits, immediate stats, zero fusion refreshes, lightweight owner-isolated registry")

-- A hot-reloaded upgrade subsystem may recover a tower solely from a technology
-- event, without building_system recovery or any BUILDING_CREATED notification.
tower.modifiers.modifier_tower_auto_attack = nil
tower.acquisition = 1000
bus.reset(); upgrade.init()
bus.handle_request(events.BUILDING_LIST_REQUEST, function(payload)
    assert(payload.handles_only == true)
    return {ok=true, buildings={{unit=tower, player_id=0, building_id="arrow_tower"}}}
end)
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

-- Grant the real enabled card through its generated params and runtime. Keep
-- the production building projection/targeting and native range callback real.
package.loaded["systems/technology_stat_manager"] = nil
package.loaded["systems/rogue_effect_state_service"] = nil
package.loaded["systems/player_context_service"] = {
    is_defeated = function() return false end,
    owner_player_id = function(u) return u and u.survival_player_id end,
}
local real_technology = require("systems/technology_stat_manager")
local rogue = require("systems/rogue_effect_runtime_service")
-- building_upgrade_system captured this module reference when loaded above.
technology_service.get = real_technology.get
PlayerResource.GetPlayer = function() return {} end
bus.reset(); real_technology.init(); building.init(); upgrade.init(); rogue.init()
permanent = {}
bus.handle_request(events.PERMANENT_REWARD_EFFECTS_GET_REQUEST, function() return {totals = permanent} end)
-- Recover the existing tower and reset previous test-only technology bonuses.
bus.emit(events.TECHNOLOGY_STATS_CHANGED, {player_id = 0, reason = "rogue_baseline"})
assert(tower:GetAttackRange() == base_range)
enemy.position = Vector(base_range + 450, 0, 0)
local remote = create_unit("npc_survival_remote", Vector(base_range + 550, 0, 0), 3)
candidates = {tree, enemy, remote}; auto = tower:FindModifierByName("modifier_tower_auto_attack")
auto:ResetTarget(); auto:OnIntervalThink()
assert(tower.target == nil, "target outside base range must be unreachable before the card")
local before_attack = tower:GetBaseDamageMin()
assert(rogue.grant(0, "long_range_volley", "range-card", "builder_start").ok)
assert(real_technology.get(0).final.tower.attack_range_bonus == 500)
assert(tower:GetAttackRange() == base_range + 500, "native modifier must project card range")
assert(tower:GetBaseDamageMin() == before_attack + 800, "800 is the card attack bonus")
assert(tower.survival_attack_range == base_range + 500)
assert(require("systems/attack_range_display_service")._attack_range_for_test(tower) == base_range + 500)
assert(require("systems/tower_targeting").valid(tower, enemy))
assert(not require("systems/tower_targeting").valid(tower, remote))
auto:OnIntervalThink()
assert(tower.target == enemy, "the target in the new range must receive a real attack order")
assert(tower:GetAcquisitionRange() == 0, "range bonuses must not re-enable attacks on resource trees")
assert(rogue.grant(0, "long_range_volley", "range-card", "builder_start").idempotent)
assert(tower:GetAttackRange() == base_range + 500, "retry must not double the bonus")
local later_tower = create_unit("building_arrow_tower", Vector(0, 0, 0))
later_tower.survival_building_id, later_tower.survival_is_building = "arrow_tower", true
bus.emit(events.BUILDING_CREATED, {unit = later_tower, entindex = later_tower:entindex(),
    player_id = 0, team = 2, building_id = "arrow_tower", definition = config.arrow_tower,
    level = 1, base_attack_damage = 100})
assert(later_tower:GetAttackRange() == base_range + 500, "new towers inherit the claimed card")
assert(later_tower:GetBaseDamageMin() == 900)
local other = create_unit("building_arrow_tower", Vector(0, 0, 0))
other.survival_building_id, other.survival_player_id = "arrow_tower", 1
bus.emit(events.BUILDING_CREATED, {unit = other, entindex = other:entindex(),
    player_id = 1, team = 2, building_id = "arrow_tower", definition = config.arrow_tower,
    level = 1, base_attack_damage = 100})
assert(other:GetAttackRange() == base_range, "same-team players do not inherit another player's card")
bus.handle_request(events.RESOURCE_TRY_SPEND_REQUEST, function() return {ok = true} end)
local upgraded = bus.request(events.BUILDING_UPGRADE_REQUEST,
    {building = tower, upgrade_mode = "one", silent_notification = true})
assert(upgraded and upgraded.ok and pending, "upgrade must still be available after range grant")
local granted_upgrade = pending; pending = nil; granted_upgrade.options.on_complete()
assert(tower:GetAttackRange() == base_range + 500, "a later successful upgrade retains the bonus")
assert(tower:GetAcquisitionRange() == 0)
print("ROGUE_TOWER_RANGE_PASS: real grant, existing/new towers, native callback, extended target orders, display, ownership and idempotent retry")
-- Exercise the actual building entry point; unrelated movement is covered by
-- test_tower_visual_relocation. A rejected owner must never reach grid checks.
local original_relocate, moves = building.relocate_building, 0
building.relocate_building=function(unit) assert(unit==tower);moves=moves+1;return true end
bus.handle_request(events.GRID_CAN_PLACE_REQUEST,function(payload)
    assert(payload.player_id==0,"building move keeps its registered owner")
    grid_owner_queries=grid_owner_queries+1
    return {ok=true,grid_x=1,grid_y=1,world_position=payload.position}
end)
tower.abilities.ability_building_blink={IsNull=function() return false end,
    IsHidden=function() return false end,IsActivated=function() return true end}
assert(building.relocate_for_player(0,tower:entindex(),Vector(64,64,0)))
local queries_after_move=grid_owner_queries
assert(not building.relocate_for_player(1,tower:entindex(),Vector(128,128,0)))
assert(grid_owner_queries==queries_after_move and moves==1)
building.relocate_building=original_relocate
print("BUILDING_GRID_OWNER_PASS: registered builder and building owner, cross-owner request stops before grid")
