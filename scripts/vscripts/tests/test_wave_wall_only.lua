-- Run from the addon root with Lua 5.1. Exercise the real order filter,
-- damage filter and enemy AI; native entities/events are represented below.
package.path = "scripts/vscripts/?.lua;" .. package.path
local noop = function() end
local entities, orders, emitted = {}, {}, {}
local consumed, pending = 0, nil
IsServer = function() return true end
class = function(value) return value end
LinkLuaModifier = noop
Vector = function(x, y, z) return {x=x, y=y, z=z or 0} end
GameRules = {GetGameTime=function() return 0 end}
EntIndexToHScript = function(index) return entities[index] end
DOTA_TEAM_GOODGUYS, DOTA_TEAM_BADGUYS = 2, 3
DOTA_UNIT_ORDER_ATTACK_TARGET, DOTA_UNIT_ORDER_MOVE_TO_POSITION, DOTA_UNIT_ORDER_ATTACK_MOVE = 4, 1, 3
DAMAGE_TYPE_PHYSICAL = 1
ExecuteOrderFromTable = function(order)
    orders[#orders+1] = order
    entities[order.UnitIndex].target = entities[order.TargetIndex]
end
local function unit(index, building)
    local value = {survival_building_id=building, alive=true, idle=true, acquire=600, stops=0}
    function value:IsNull() return self.removed == true end
    function value:IsAlive() return self.alive end
    function value:entindex() return index end
    function value:GetTeamNumber() return self.survival_is_wave_monster and 3 or 2 end
    function value:GetAbsOrigin() return Vector(0, 0) end
    function value:IsInvulnerable() return false end
    function value:HasModifier() return false end
    function value:FindAllModifiersByName() return {} end
    function value:IsRealHero() return false end
    function value:GetHealth() return 1000 end
    function value:GetMaxHealth() return 1000 end
    function value:SetIdleAcquire(enabled) self.idle=enabled end
    function value:SetAcquisitionRange(radius) self.acquire=radius end
    function value:SetForceAttackTarget(target) self.forced=target end
    function value:GetForceAttackTarget() return self.forced end
    function value:Stop() self.stops=self.stops+1; self.target=nil end
    entities[index] = value
    return value
end
local wall, tower, hero = unit(1, "wall"), unit(2, "arrow_tower"), unit(3)
local other_targets = {tower, hero, unit(4, "main_city"), unit(5, "building_farm"), unit(6, "tree")}
local wave, boss, ranged, challenge = unit(10), unit(11), unit(12), unit(13)
wave.survival_is_wave_monster, boss.survival_is_wave_monster, ranged.survival_is_wave_monster = true, true, true
boss.survival_is_boss, challenge.survival_is_challenge_monster = true, true
local wave_units = {wave, boss, ranged}
local trees = {
    is_tree=function() return false end,
    is_arrow_tower=function(u) return u == tower end,
    is_allowed_tree_attacker=function() return false end,
    is_basic_attack_category=function(category) return category == 1 end,
    allows_damage=function() return true end,
    reset_pending_attacks=noop,
}
package.loaded["systems/tree_damage_rules"] = trees
package.loaded["systems/repair_order_service"] = {process=function() return false end}
package.loaded["systems/lumberjack_order_service"] = {process=noop}
package.loaded["systems/destination_validation_service"] = {is_constrained_hero=function() return false end}
package.loaded["systems/player_context_service"] = {is_defeated=function() return false end}
package.loaded["systems/rich_region_service"] = {validate_order=function() return true end}
package.loaded["config/generated/global_rules"] = {by_id={}}
package.loaded["systems/rogue_effect_state_service"] = {
    numeric=function() return 0 end, has_effect=function() return false end,
    wall_damage_cap=function() return 0 end,
}
package.loaded["systems/commerce_effects"] = {owned=function() return false end}
local rules = require("systems/wave_attack_rules")
local order_filter = require("systems/tree_attack_order_filter")._filter_for_test
local damage_service = require("combat/damage_filter_service")
damage_service.init({
    event_bus={emit=function(event, payload) emitted[#emitted+1]={event=event, payload=payload} end},
    events={DAMAGE_BLOCKED="blocked", DAMAGE_FILTERED="filtered", DAMAGE_RESOLVED="resolved"},
    repository={consume_pending=function()
        consumed=consumed+1; local value=pending; pending=nil; return value
    end},
    config={global_post_bonus_pct=0, minimum_post_multiplier=0, boss_rules={enabled=false}},
})
local function attack_order(attacker, target)
    return order_filter(nil, {units={tostring(attacker:entindex())},
        order_type=DOTA_UNIT_ORDER_ATTACK_TARGET, entindex_target=target and target:entindex()})
end
local function damage(attacker, target, category, record)
    pending=record
    local keys={entindex_attacker_const=attacker:entindex(), entindex_victim_const=target:entindex(),
        damage=100, damagetype_const=DAMAGE_TYPE_PHYSICAL, damage_category_const=category}
    if category == 0 then keys.entindex_inflictor_const=100 end
    local accepted=damage_service._filter_for_test(nil, keys)
    assert(pending == nil, "even rejected damage must consume the pending transaction")
    return accepted, keys.damage
end
for _, attacker in ipairs(wave_units) do
    assert(rules.can_attack(attacker, wall) and attack_order(attacker, wall))
    local accepted, amount=damage(attacker, wall, 1)
    assert(accepted and amount == 100, "wall damage must keep the existing calculation")
    for _, target in ipairs(other_targets) do
        assert(not rules.can_attack(attacker, target) and not attack_order(attacker, target))
        for _, category in ipairs({0, 1}) do
            assert(not damage(attacker, target, category), "native attacks/projectiles/spells must reject non-walls")
            assert(emitted[#emitted].payload.reason == "wave_requires_wall_target")
        end
        assert(not damage(attacker, target, 0, {transaction_id=42, source_kind="splash"}))
        assert(emitted[#emitted].payload.transaction_id == 42)
    end
    assert(not attack_order(attacker, nil))
end
assert(not order_filter(nil, {units={"13", "10"}, order_type=4, entindex_target=2}),
    "a grouped order must check every unit")
wall.alive=false
assert(not rules.can_attack(wave, wall) and not attack_order(wave, wall))
wall.alive=true; wall.removed=true
assert(not rules.can_attack(wave, wall))
wall.removed=false
for _, attacker in ipairs({hero, tower, challenge}) do
    assert(attack_order(attacker, wall), "other attackers keep their order rules")
    assert(damage(attacker, tower, 1), "the tower itself must not become globally invulnerable")
    assert(damage(attacker, wave, 1), "defenders must still damage wave enemies")
end

-- Existing AI owns wall orders. Disable idle acquisition at spawn, then test
-- both its fallback event handler and the shared observer's handler entry.
package.loaded["core/team_alignment"] = {}
package.loaded["systems/wall_melee_contact"] = {release=noop}
package.loaded["systems/wall_navigation_service"] = {}
package.loaded["systems/wall_target_service"] = {}
package.loaded["systems/enemy_attack_observer"] = {is_ready=function() return false end}
package.loaded["systems/enemy_ranged_stationary"] = {}
local AI = require("modifiers/modifier_enemy_wall_ai")
for _, attacker in ipairs(wave_units) do
    local ai=setmetatable({GetParent=function() return attacker end, StartIntervalThink=noop}, {__index=AI})
    ai:OnCreated({wall_entindex=wall:entindex()})
    assert(attacker.idle == false and attacker.acquire == 0, "no automatic nearby targeting, including before a wall is available")
    ai.ai_state="chase"
    ai:IssueStateOrder(attacker, wall)
    assert(attacker.forced == wall and orders[#orders].TargetIndex == wall:entindex())
    local before=#orders
    ai:HandleAttackStart({attacker=attacker})
    assert(attacker.stops == 0 and attacker.forced == wall, "an incomplete event must not interrupt a valid wall order")
    for pass=1,20 do ai:HandleAttackStart({attacker=attacker, target=wall}) end
    assert(#orders == before and attacker.stops == 0, "legal wall attacks must not restart the attack clock")
    ai:OnAttackStart({attacker=attacker, target=tower})
    assert(attacker.stops == 1 and attacker.forced == nil and ai.order_pending)
    ai:IssueStateOrder(attacker, wall)
    assert(not ai.order_pending and attacker.forced == wall and attacker.target == wall)
    ai.shared_attack_observer=true
    ai:HandleAttackStart({attacker=attacker, target=hero})
    assert(attacker.stops == 2 and ai.order_pending, "shared observer must also cancel retaliation")
end
local ai=setmetatable({GetParent=function() return challenge end, StartIntervalThink=noop}, {__index=AI})
ai:OnCreated({wall_entindex=1})
assert(challenge.idle and challenge.acquire == 600, "shared AI must not change separate challenge acquisition")
ai:HandleAttackStart({attacker=challenge, target=tower})
assert(challenge.stops == 0)
local waiting=unit(20)
waiting.survival_is_wave_monster=true
local idle_ai=setmetatable({GetParent=function() return waiting end, StartIntervalThink=noop}, {__index=AI})
local before=#orders
idle_ai:OnCreated({wall_entindex=-1})
idle_ai:OnIntervalThink()
assert(#orders == before and not waiting.idle and waiting.acquire == 0,
    "without a wall, wait instead of acquiring a tower or hero")
print("WAVE_WALL_ONLY_PASS: normal/boss/ranged orders, damage, splash, transaction cleanup, AI recovery, defender/challenge isolation; damage checks="..consumed)
