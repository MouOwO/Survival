-- Run from the addon root with Lua 5.1+; no game or engine connection is used.
package.path = "scripts/vscripts/?.lua;" .. package.path
class = function(value) return value end
LinkLuaModifier = function() end
local server = true
IsServer = function() return server end
LUA_MODIFIER_MOTION_NONE = 0
MODIFIER_ATTRIBUTE_PERMANENT = 1
MODIFIER_EVENT_ON_ATTACK_START = 10
MODIFIER_EVENT_ON_DEATH = 11
MODIFIER_PROPERTY_DISABLE_AUTOATTACK = 12
MODIFIER_STATE_DISARMED = 13
ACT_DOTA_ATTACK, ACT_DOTA_ATTACK2 = 20, 21
DOTA_UNIT_TARGET_TEAM_ENEMY = 1
DOTA_UNIT_TARGET_HERO, DOTA_UNIT_TARGET_BASIC = 1, 2
DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES = 4
DOTA_DAMAGE_CATEGORY_ATTACK = 1
DOTA_UNIT_ORDER_ATTACK_TARGET = 4
FIND_CLOSEST = 0

local auto = require("modifiers/modifier_tower_auto_attack")
local tree_rules = require("systems/tree_damage_rules")
local candidates = {}
local radius_queries = 0
FindUnitsInRadius = function() radius_queries = radius_queries + 1; return candidates end
local next_index = 0
local entities = {}
EntIndexToHScript = function(index) return entities[tonumber(index)] end
local vector = {}
vector.__sub = function(a, b)
    return { Length2D = function() return math.abs(a.x - b.x) end }
end
local function unit(name, distance, team)
    next_index = next_index + 1
    local value = { name = name, alive = true, team = team or 3, index = next_index,
        position = setmetatable({ x = distance or 0 }, vector) }
    function value:IsNull() return false end
    function value:IsAlive() return self.alive end
    function value:entindex() return self.index end
    function value:GetUnitName() return self.name end
    function value:GetTeamNumber() return self.team end
    function value:GetAbsOrigin() return self.position end
    function value:IsRealHero() return self.real_hero == true end
    function value:IsIllusion() return false end
    entities[next_index] = value
    return value
end

local function tower_fixture(class_id)
    local tower = unit("building_arrow_tower", 0, 2)
    tower.survival_building_id = "arrow_tower"
    tower.survival_tower_class = class_id
    tower.range, tower.acquisition, tower.idle_acquire = 1000, 1000, true
    local calls = { stop = 0, force = 0, fade = 0, stack = 0, refresh = 0,
        acquisition_writes = 0, idle_acquire_writes = 0, order = {} }
    local modifier = setmetatable({ stack_count = 0 }, { __index = auto })
    local function record(event) calls.order[#calls.order + 1] = event end
    function modifier:GetParent() return tower end
    function modifier:GetStackCount() return self.stack_count end
    function modifier:SetStackCount(count)
        self.stack_count = count
        calls.stack = calls.stack + 1
        record("stack:" .. count)
    end
    function modifier:ForceRefresh()
        calls.refresh = calls.refresh + 1
        record("refresh:" .. self.stack_count)
    end
    function modifier:StartIntervalThink(interval) self.interval = interval end
    function tower:Script_GetAttackRange() return self.range end
    function tower:GetAttackRange() return self.range end
    function tower:SetAcquisitionRange(value)
        self.acquisition = value
        calls.acquisition_writes = calls.acquisition_writes + 1
    end
    function tower:GetAcquisitionRange() return self.acquisition end
    function tower:SetIdleAcquire(value)
        self.idle_acquire = value
        calls.idle_acquire_writes = calls.idle_acquire_writes + 1
    end
    function tower:GetAttackTarget() return self.target end
    function tower:GetForceAttackTarget() return self.forced end
    function tower:SetForceAttackTarget(target)
        if target then
            assert(not tree_rules.is_tree(target), "resource tree received a forced attack")
            assert(modifier:GetStackCount() == 1,
                "legal target must unlock attack permission before the engine order")
            assert(modifier:CheckState()[MODIFIER_STATE_DISARMED] ~= true,
                "forced attack was issued while the tower was still disarmed")
            assert(modifier:GetDisableAutoAttack() == 0,
                "disable-autoattack property must also unlock before the forced order")
            record("force:" .. target:entindex())
        else
            record("force:nil")
        end
        self.forced = target
        calls.force = calls.force + 1
    end
    function tower:Stop()
        self.target = nil
        calls.stop = calls.stop + 1
        record("stop")
    end
    function tower:FadeGesture(activity)
        assert(activity == ACT_DOTA_ATTACK or activity == ACT_DOTA_ATTACK2)
        calls.fade = calls.fade + 1
        record("fade:" .. activity)
    end
    modifier:OnCreated()
    return tower, modifier, calls
end
local function idle(tower, modifier, message)
    assert(modifier:GetStackCount() == 0, message .. ": attack permission still enabled")
    assert(modifier:CheckState()[MODIFIER_STATE_DISARMED] == true,
        message .. ": engine must prevent the attack before its start callback")
    assert(modifier:GetDisableAutoAttack() == 1, message .. ": native autoattack enabled")
    assert(tower.acquisition == 0 and tower.idle_acquire == false,
        message .. ": native idle acquisition enabled")
    assert(tower.forced == nil and tower.target == nil, message .. ": stale engine target")
end
local function snapshot(calls)
    return table.concat({ calls.stop, calls.force, calls.fade, calls.stack, calls.refresh,
        calls.acquisition_writes, calls.idle_acquire_writes }, ":")
end
local function unchanged(calls, before, message)
    assert(snapshot(calls) == before, message .. ": redundant engine state/order/gesture work")
end
local function contains(list, expected)
    for _, item in ipairs(list) do if item == expected then return true end end
    return false
end

local tree = unit("enemy_tree", 20)
local tree_team = tree:GetTeamNumber()
local enemy = unit("enemy_wave", 500)
local unrelated = unit("enemy_wave", 600)
candidates = { tree }
local tower, modifier, calls = tower_fixture()
local declared = modifier:DeclareFunctions()
assert(contains(declared, MODIFIER_EVENT_ON_DEATH), "target death must be handled immediately")
assert(contains(declared, MODIFIER_PROPERTY_DISABLE_AUTOATTACK), "disable-autoattack property not declared")
idle(tower, modifier, "initial tree-only frame")
local before = snapshot(calls)
for _ = 1, 8 do modifier:OnIntervalThink() end
unchanged(calls, before, "stable tree-only idle")
modifier:SetManualTarget(tree)
idle(tower, modifier, "manual tree request")
assert(tree:GetTeamNumber() == tree_team, "tree hostility must not be changed to hide it from towers")

-- The idle flag is an engine-replicated stack, so client CheckState must agree.
server = false
assert(modifier:CheckState()[MODIFIER_STATE_DISARMED] == true)
server = true

candidates = { tree, enemy }
local offset = #calls.order
modifier:OnIntervalThink()
assert(tower.forced == enemy and modifier:GetStackCount() == 1)
local unlocked, refreshed, ordered
for index = offset + 1, #calls.order do
    local event = calls.order[index]
    if event == "stack:1" then unlocked = index end
    if event == "refresh:1" then refreshed = index end
    if event == "force:" .. enemy:entindex() then ordered = index end
end
assert(unlocked and refreshed and ordered and unlocked < ordered and refreshed < ordered,
    "state/engine refresh must precede the first legal attack order")
tower.target = enemy
before = snapshot(calls)
for _ = 1, 8 do modifier:OnIntervalThink() end
unchanged(calls, before, "stable legal target")
modifier:OnDeath({ unit = unrelated })
unchanged(calls, before, "unrelated unit death")

-- No interval is allowed between death and idle: the engine could otherwise
-- retarget a hostile resource tree during the quarter-second polling gap.
enemy.alive = false
candidates = { tree }
local stops, fades = calls.stop, calls.fade
modifier:OnDeath({ unit = enemy })
idle(tower, modifier, "target death callback")
assert(calls.stop == stops + 1 and calls.fade > fades,
    "entering idle must stop the attack and fade its old gesture once")
before = snapshot(calls)
modifier:OnDeath({ unit = enemy })
for _ = 1, 4 do modifier:OnIntervalThink() end
unchanged(calls, before, "repeated death and idle polling")

-- Manual targeting must use the same unlock-before-order transition; resetting
-- after an upgrade restores idle even if the old target is still alive.
enemy.alive = true
candidates = { tree, enemy }
modifier:SetManualTarget(enemy)
assert(tower.forced == enemy and modifier:GetStackCount() == 1)
tower.target = enemy
modifier:ResetTarget()
idle(tower, modifier, "upgrade reset")

-- Death detection covers a manual selection, forced-only pursuit, and the
-- engine's actual target even if its Lua bookkeeping was stale after reload.
for _, target_source in ipairs({ "manual", "forced", "actual" }) do
    local target = unit("enemy_wave", 400)
    candidates = { target }
    local t, m = tower_fixture()
    m:SetManualTarget(target)
    if target_source ~= "manual" then m.manual_target = nil end
    if target_source == "actual" then
        m.forced_target, t.forced = nil, nil
        t.target = target
    end
    target.alive = false
    m:OnDeath({ unit = target })
    idle(t, m, target_source .. " target death")
end

local flying = unit("enemy_flying", 400)
flying.survival_movement_type = "flying"
tree.survival_movement_type = "flying"
candidates = { tree, enemy }
local air_tower, air_modifier = tower_fixture("class_7")
air_modifier:OnIntervalThink()
air_modifier:SetManualTarget(enemy)
idle(air_tower, air_modifier, "anti-air with only ground enemies and trees")
candidates = { tree, enemy, flying }
air_modifier:OnIntervalThink()
assert(air_tower.forced == flying and air_modifier:GetStackCount() == 1)
air_tower.target = flying
flying.survival_movement_type = "ground"
candidates = { tree, enemy, flying }
air_modifier:OnIntervalThink()
idle(air_tower, air_modifier, "anti-air target lost flying eligibility")

-- Tree combat remains available to the two intended actor types. No team
-- rewrite or global disarm is used to silence the towers.
local hero = unit("npc_dota_hero_sven", 0, 2)
hero.real_hero = true
local lumberjack = unit("npc_survival_lumberjack", 0, 2)
for _, attacker in ipairs({ hero, lumberjack }) do
    assert(tree_rules.is_allowed_tree_attacker(attacker))
    assert(tree_rules.allows_damage(attacker, tree, DOTA_DAMAGE_CATEGORY_ATTACK, false))
end
assert(not tree_rules.is_allowed_tree_attacker(tower))
assert(tree:GetTeamNumber() == tree_team)

-- Exercise the real execute-order filter with an engine-shaped stalled-order
-- fixture. Merely recording a forced target must not count as having started
-- an attack while native idle acquisition is disabled.
package.loaded["systems/repair_order_service"] = { process = function() return false end }
package.loaded["systems/lumberjack_order_service"] = { process = function() end }
package.loaded["systems/destination_validation_service"] = { is_constrained_hero = function() return false end }
package.loaded["systems/player_context_service"] = { owner_player_id = function() return 0 end }
local order_filter = require("systems/tree_attack_order_filter")
local wave_monster = unit("npc_survival_wave_monster", 700)
wave_monster.survival_is_wave_monster = true
local recovery_tower, recovery_modifier, recovery_calls = tower_fixture()
local explicit_orders = 0
local drop_next_order = false
function recovery_tower:FindModifierByName(name)
    if name == "modifier_tower_auto_attack" then return recovery_modifier end
end
function recovery_tower:MoveToTargetToAttack(target)
    explicit_orders = explicit_orders + 1
    assert(order_filter._filter_for_test(nil, {
        order_type = DOTA_UNIT_ORDER_ATTACK_TARGET,
        units = { [0] = self:entindex() }, entindex_target = target:entindex(),
        issuer_player_id_const = -1,
    }), "legitimate automatic recovery order was rejected")
    if drop_next_order then drop_next_order = false else self.target = target end
end
candidates = { tree, wave_monster }
recovery_modifier:OnIntervalThink()
assert(explicit_orders == 1 and recovery_tower.target == wave_monster,
    "first acquired monster must receive a real attack order immediately")
assert(recovery_modifier.manual_target == nil,
    "execute-order-filter reentry must not convert auto selection to a manual target")
before = snapshot(recovery_calls)
for _ = 1, 12 do recovery_modifier:OnIntervalThink() end
unchanged(recovery_calls, before, "recovered ongoing attack")
assert(explicit_orders == 1)

-- An external Stop keeps the Lua forced-target cache. It must not leave this
-- immobile tower permanently passive, nor cause healthy attacks to restart.
recovery_tower:Stop()
assert(recovery_modifier.forced_target == wave_monster and recovery_tower.target == nil)
recovery_modifier:OnIntervalThink()
assert(explicit_orders == 2 and recovery_tower.target == wave_monster)
assert(recovery_tower.acquisition == 0 and recovery_tower.idle_acquire == false)

-- The target dies while more monsters are available. Retarget in the death
-- callback with no intermediate Stop/disarm/gesture reset and no polling delay.
local second_monster = unit("npc_survival_wave_monster", 750)
local third_monster = unit("npc_survival_wave_monster", 800)
local stops_before_kill, stacks_before_kill = recovery_calls.stop, recovery_calls.stack
wave_monster.alive = false
candidates = { tree, wave_monster, second_monster, third_monster }
recovery_modifier:OnDeath({ unit = wave_monster })
assert(recovery_tower.target == second_monster and explicit_orders == 3,
    "kill must issue the next valid attack before returning from OnDeath")
assert(recovery_calls.stop == stops_before_kill and recovery_calls.stack == stacks_before_kill,
    "continuous combat must not pass through Stop or disarm between victims")
before = snapshot(recovery_calls)
recovery_modifier:OnDeath({ unit = wave_monster })
for _ = 1, 8 do recovery_modifier:OnIntervalThink() end
unchanged(recovery_calls, before, "kill retarget remains stable")
assert(explicit_orders == 3)

-- A projectile from an old victim can land after an engine/manual target
-- switch. Repairing stale Lua bookkeeping must not restart that healthy attack.
recovery_modifier.forced_target = wave_monster
recovery_modifier:OnDeath({ unit = wave_monster })
assert(recovery_modifier.forced_target == second_monster and explicit_orders == 3,
    "an old projectile kill must preserve the ongoing next-target attack")
assert(recovery_calls.stop == stops_before_kill and recovery_calls.stack == stacks_before_kill)

-- OnDeath can run before the engine has removed the deceased unit from radius
-- results/IsAlive state. Its explicit event identity must exclude it regardless.
drop_next_order = true
candidates = { tree, second_monster, third_monster }
recovery_modifier:OnDeath({ unit = second_monster })
second_monster.alive = false
assert(recovery_modifier.forced_target == third_monster and explicit_orders == 4,
    "the death callback must not select its deceased unit from stale engine data")
recovery_tower.target = nil -- emulate an engine clear after a rejected command
assert(recovery_modifier.interval == 0.25)
recovery_modifier:OnIntervalThink()
assert(recovery_tower.target == third_monster and explicit_orders == 5,
    "dropped retarget order must recover on the next 0.25s tick, not after 1s")

-- Tree-only idle retains its pre-attack disarm and gesture protections, and
-- no remembered command survives a final target death before recovery.
recovery_tower:Stop()
third_monster.alive = false
candidates = { tree }
recovery_modifier:OnDeath({ unit = third_monster })
for _ = 1, 8 do recovery_modifier:OnIntervalThink() end
idle(recovery_tower, recovery_modifier, "stalled target died before retry")
assert(explicit_orders == 5, "no delayed order may be issued at a dead monster or resource tree")

-- Dummy priority is evaluated by target selection, not an extra radius search
-- for every attack animation. An approaching real enemy still wins next tick.
local dummy = unit("training_dummy", 100)
dummy.survival_is_training_dummy = true
local dummy_tower, dummy_modifier = tower_fixture()
candidates = { tree, dummy }
dummy_modifier:OnIntervalThink()
dummy_tower.target = dummy
local searches_before = radius_queries
for _ = 1, 100 do dummy_modifier:OnAttackStart({ attacker = dummy_tower, target = dummy }) end
assert(radius_queries == searches_before, "approved dummy attacks must not trigger per-attack radius scans")
assert(dummy_modifier.forced_target == dummy and dummy_modifier:GetStackCount() == 1)
local approaching = unit("enemy_wave", 400)
candidates = { tree, dummy, approaching }
dummy_modifier:OnIntervalThink()
assert(dummy_modifier.forced_target == approaching, "real enemies must still preempt the training dummy")

print("TOWER_HOTPATH_PASS: stable acquisition writes=0; 100 approved dummy attacks radius scans=0")

print("TOWER_IDLE_STATE_PASS: immediate first/kill attack, no Stop/disarm between victims, next-tick dropped-order recovery, stable attacks, real order-filter reentry, tree-only idle")
