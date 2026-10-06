-- Real critical-record helpers and the real damage filter; no native rendering.
package.path = "scripts/vscripts/?.lua;" .. package.path
local server, rolls, overheads, emitted, copies = true, {}, {}, {}, {}
function IsServer() return server end
function class(value) value.__index = value; return value end
function RandomFloat(low, high)
    assert(low == 0 and high == 100)
    local value = table.remove(rolls, 1)
    assert(value ~= nil, "an attack record may only roll once")
    return value
end
MODIFIER_PROPERTY_DAMAGEOUTGOING_PERCENTAGE = 1
MODIFIER_EVENT_ON_ATTACK_RECORD = 2
MODIFIER_EVENT_ON_TAKEDAMAGE = 3
MODIFIER_EVENT_ON_ATTACK_RECORD_DESTROY = 4
MODIFIER_EVENT_ON_DEATH = 5
DOTA_DAMAGE_CATEGORY_ATTACK, DOTA_DAMAGE_CATEGORY_SPELL = 1, 2
DAMAGE_TYPE_PHYSICAL, DAMAGE_TYPE_PURE = 1, 4
OVERHEAD_ALERT_CRITICAL, OVERHEAD_ALERT_BONUS_SPELL_DAMAGE, OVERHEAD_ALERT_DAMAGE = 10, 11, 12
PlayerResource = {GetPlayer = function(_, id) assert(id == 2); return "player2" end}
function SendOverheadEventMessage(player, style, victim, damage)
    assert(player == "player2")
    overheads[#overheads + 1] = {style = style, victim = victim, damage = damage}
end
local bus = {emit = function(event, payload) emitted[#emitted + 1] = {event, payload} end}
package.loaded["core/event_bus"] = bus
package.loaded["systems/tree_damage_rules"] = {
    is_tree = function() return false end, allows_damage = function() return true end,
    is_basic_attack_category = function(category) return tonumber(category) == DOTA_DAMAGE_CATEGORY_ATTACK end,
    reset_pending_attacks = function() end,
}
package.loaded["systems/anti_air_rules"] = {
    can_attack = function() return true end, has_damage_taken_aura = function() return false end,
}
package.loaded["systems/rogue_effect_state_service"] = {
    has_effect = function() return false end, numeric = function() return 0 end,
}
local secondary_records = {}
modifier_weapon_attack_tracker = {
    IsSecondaryAttackRecord = function(record) return secondary_records[record] == true end,
}
local entities = {}
local function unit(id, team)
    local result = {id = id, team = team, living = true}
    function result:IsNull() return self.null == true end
    function result:entindex() return self.id end
    function result:IsAlive() return self.living end
    function result:GetTeamNumber() return self.team end
    function result:GetPlayerOwnerID() return 2 end
    function result:IsInvulnerable() return false end
    function result:IsRealHero() return false end
    function result:HasModifier() return false end
    entities[id] = result
    return result
end
function EntIndexToHScript(id) return entities[id] end
local parent, victim, other = unit(100, 2), unit(200, 3), unit(201, 3)
local ability = {IsNull = function() return false end}
local clone_class = require("modifiers/modifier_blademaster_clone")
local modifier = setmetatable({GetParent = function() return parent end}, clone_class)
modifier:OnCreated({player_id = 2})
local q_active, q_failure = true, false
package.loaded["systems/blademaster_exclusive_service"] = {
    trigger_clone_q = function(player_id, clone, target, final_damage)
        assert(player_id == 2 and clone == parent)
        assert(modifier:GetModifierDamageOutgoing_Percentage() == 0,
            "Q copies may not inherit a pending attack's outgoing critical modifier")
        if q_failure then error("injected Q failure") end
        if not q_active then return false end
        copies[#copies + 1] = {target = target, damage = final_damage}
        -- A nested ability event and a duplicate ordinary-damage callback must
        -- neither reroll nor recursively generate another Q.
        modifier:OnTakeDamage({attacker = parent, unit = target,
            record = 1, damage = final_damage / (target.survival_endless_health_scale or 1),
            damage_category = DOTA_DAMAGE_CATEGORY_SPELL, inflictor = ability})
        modifier:OnTakeDamage({attacker = parent, unit = target,
            record = 1, damage = 99, damage_category = DOTA_DAMAGE_CATEGORY_ATTACK})
        return true
    end,
}
local filter = require("combat/damage_filter_service")
local combat_events = require("combat/combat_events")
filter.init({event_bus = bus, events = combat_events,
    repository = {consume_pending = function() return nil end},
    config = {global_post_bonus_pct = 0, minimum_post_multiplier = 0,
        boss_rules = {enabled = false}}})
local function near(a, b) return math.abs(a - b) <= math.max(1, math.abs(b)) * 1e-12 end
local function record(id, extras)
    local params = {attacker = parent, target = victim, record = id}
    for key, value in pairs(extras or {}) do params[key] = value end
    modifier:OnAttackRecord(params)
    return params
end
local function damage(id, amount, extras)
    local params = {attacker = parent, unit = victim, record = id,
        damage = amount, damage_category = DOTA_DAMAGE_CATEGORY_ATTACK}
    for key, value in pairs(extras or {}) do params[key] = value end
    modifier:OnTakeDamage(params)
end
local function destroy_record(id)
    modifier:OnAttackRecordDestroy({attacker = parent, record = id})
    assert(not modifier_weapon_stat_projection.PeekCriticalAttackRecord(parent, id))
end

-- Normal inherited attack, one 950% crit (hero 200 + clone 750), safe engine
-- damage -> source projection -> victim projection -> final logical Q damage.
modifier:SetCombatSnapshot({critical_chance_pct = 50, critical_damage_pct = 950})
rolls = {10}
record(1); record(1)
assert(#rolls == 0 and modifier_weapon_stat_projection.PeekCriticalAttackRecord(parent, 1))
local critical_bonus = modifier:GetModifierDamageOutgoing_Percentage({record = 1})
assert(critical_bonus == 850 and modifier:GetModifierDamageOutgoing_Percentage({record = 1}) == 850,
    "multiple native queries of one record use its one critical roll")
modifier:SetCombatSnapshot({critical_chance_pct = 0, critical_damage_pct = 200})
assert(modifier:GetModifierDamageOutgoing_Percentage({record = 1}) == 850,
    "live stat updates do not alter an already-recorded critical attack")
parent.survival_endless_attack_scale, victim.survival_endless_health_scale = 10000, 100
local keys = {entindex_attacker_const = parent.id, entindex_victim_const = victim.id,
    damage = 100000000 * (1 + critical_bonus / 100),
    damage_category_const = DOTA_DAMAGE_CATEGORY_ATTACK, damagetype_const = DAMAGE_TYPE_PHYSICAL}
assert(filter._filter_for_test(nil, keys))
assert(near(keys.damage, 95000000000), "the real filter restores huge source damage exactly once")
damage(1, keys.damage)
assert(#copies == 1 and near(copies[1].damage, 9500000000000),
    "Q receives post-filter logical damage, restoring victim health but not source attack twice")
assert(overheads[1].style == OVERHEAD_ALERT_CRITICAL and near(overheads[1].damage, copies[1].damage))
assert(overheads[2].style == OVERHEAD_ALERT_DAMAGE)
damage(1, keys.damage)
assert(#copies == 1 and #overheads == 2, "duplicate actual-damage callbacks cannot duplicate Q or damage numbers")
assert(modifier:GetModifierDamageOutgoing_Percentage() == 0)
destroy_record(1)
parent.survival_endless_attack_scale, victim.survival_endless_health_scale = nil, nil

-- Noncritical damage, unconfirmed rolls, blocked hits, spells and non-primary
-- targets do not masquerade as confirmed ordinary critical attacks.
modifier:SetCombatSnapshot({critical_chance_pct = 50, critical_damage_pct = 950})
rolls = {80, 10, 10, 10}
record(2); damage(2, 100)
assert(#copies == 1 and overheads[#overheads].style == OVERHEAD_ALERT_BONUS_SPELL_DAMAGE)
record(3); damage(3, 0); assert(#copies == 1)
record(4); damage(4, 30, {inflictor = ability, damage_category = DOTA_DAMAGE_CATEGORY_SPELL})
assert(#copies == 1 and modifier:GetModifierDamageOutgoing_Percentage({record = 4, inflictor = ability}) == 0)
record(5); damage(5, 70, {unit = other}); assert(#copies == 1)
damage(5, 70); assert(#copies == 2 and copies[2].damage == 70)
for id = 2, 5 do destroy_record(id) end

-- Interleaved records keep their own rolls; secondary attacks never roll or Q.
rolls = {10, 80}
record(6); record(7)
assert(modifier:GetModifierDamageOutgoing_Percentage({record = 6}) == 850)
assert(modifier:GetModifierDamageOutgoing_Percentage({record = 7}) == 0)
for id = 6, 7 do destroy_record(id) end
local secondary_cases = {
    {is_multishot_secondary = true}, {no_attack_cooldown = 1}, {is_main_attack = false}, {}, {},
}
local before_copies = #copies
for index, flags in ipairs(secondary_cases) do
    local id = 10 + index
    if index == 4 then secondary_records[id] = true end
    if index == 5 then parent.survival_next_multishot_secondary = true end
    record(id, flags)
    parent.survival_next_multishot_secondary = nil
    assert(modifier:GetModifierDamageOutgoing_Percentage({record = id}) == 0)
    damage(id, 40)
    assert(#copies == before_copies and not modifier_weapon_stat_projection.PeekCriticalAttackRecord(parent, id))
    destroy_record(id)
end

-- Only the service decides whether this unit still owns an active Q. A failed
-- or disabled Q is attempted once and cannot strand the reentry guard.
rolls = {10, 10, 10}
q_active = false; record(20); damage(20, 99); damage(20, 99)
assert(#copies == before_copies and modifier.resolving_clone_q == false)
q_active, q_failure = true, true; record(21); damage(21, 100)
assert(modifier.resolving_clone_q == false and #copies == before_copies)
q_failure = false; damage(21, 100); assert(#copies == before_copies)
record(22); damage(22, 101); assert(#copies == before_copies + 1)
for id = 20, 22 do destroy_record(id) end

-- Damage without the native attack record must never borrow the last roll.
-- A later correctly identified callback can still confirm that attack once.
rolls = {10}
record(24)
local before_unidentified = #copies
modifier:OnTakeDamage({attacker = parent, unit = victim, damage = 123,
    damage_category = DOTA_DAMAGE_CATEGORY_ATTACK})
assert(#copies == before_unidentified)
damage(24, 123)
assert(#copies == before_unidentified + 1 and copies[#copies].damage == 123)
destroy_record(24)

-- Death and modifier teardown revoke all owned shared critical records; late
-- callbacks are harmless and client-side property evaluation never rolls.
rolls = {10, 10, 10}
record(30); record(31)
parent.living = false
modifier:OnDeath({unit = parent})
assert(next(modifier.records) == nil and not modifier_weapon_stat_projection.PeekCriticalAttackRecord(parent, 30)
    and not modifier_weapon_stat_projection.PeekCriticalAttackRecord(parent, 31))
local before_overheads = #overheads
damage(30, 100)
assert(#overheads == before_overheads)
parent.living = true; record(32); modifier:OnDestroy()
assert(next(modifier.records) == nil and not modifier_weapon_stat_projection.PeekCriticalAttackRecord(parent, 32))
damage(32, 100); record(33)
assert(#overheads == before_overheads and #rolls == 0)
server = false
assert(modifier:GetModifierDamageOutgoing_Percentage({record = 32}) == 0)
for _, event in ipairs(emitted) do
    assert(event[1] ~= require("core/events").HERO_MAIN_ATTACK_LANDED
        and event[1] ~= require("core/events").HERO_MAIN_ATTACK_FIRED
        and event[1] ~= require("core/events").HERO_FINAL_CRITICAL_ATTACK_DAMAGE,
        "clone attacks never publish main-hero proc events")
end
assert(not modifier:IsPurgable() and not modifier:RemoveOnDeath())
print("BLADEMASTER_CLONE_PASS: real critical records, once-only confirmed Q, secondary isolation, huge damage filter restoration, live snapshots and death cleanup")
