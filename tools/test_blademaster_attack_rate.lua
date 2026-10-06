-- Real clone service + shared attack-rate service + native modifier definition.
-- Verify both fixed-rate properties and the carrier's original animation BAT.
-- GetAttacksPerSecond alone can report 10 while rewriting BAT to 0.1 leaves
-- native attack animations too slow (confirmed by in-game ON_ATTACK counts).
package.path = "scripts/vscripts/?.lua;" .. package.path
class = function(value) return value end
IsServer = function() return true end
LUA_MODIFIER_MOTION_NONE = 0
MODIFIER_PROPERTY_FIXED_ATTACK_RATE = 1
MODIFIER_PROPERTY_DAMAGEOUTGOING_PERCENTAGE = 2
MODIFIER_EVENT_ON_ATTACK_RECORD, MODIFIER_EVENT_ON_TAKEDAMAGE = 3, 4
MODIFIER_EVENT_ON_ATTACK_RECORD_DESTROY, MODIFIER_EVENT_ON_DEATH = 5, 6
DOTA_DAMAGE_CATEGORY_ATTACK, DOTA_DAMAGE_CATEGORY_SPELL = 1, 2
DAMAGE_TYPE_PHYSICAL, DAMAGE_TYPE_PURE = 1, 4
OVERHEAD_ALERT_CRITICAL, OVERHEAD_ALERT_BONUS_SPELL_DAMAGE, OVERHEAD_ALERT_DAMAGE = 10, 11, 12
DOTA_UNIT_CAP_MELEE_ATTACK, DOTA_UNIT_CAP_MOVE_GROUND = 1, 1
DOTA_UNIT_TARGET_TEAM_ENEMY, DOTA_UNIT_TARGET_HERO, DOTA_UNIT_TARGET_BASIC = 2, 4, 8
DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES, FIND_CLOSEST = 16, 0
DOTA_UNIT_ORDER_ATTACK_TARGET, DOTA_UNIT_ORDER_MOVE_TO_POSITION = 4, 1
GameRules = { GetGameTime = function() return 0 end }
Vector = function(x, y, z) return { x = x, y = y, z = z or 0 } end
LinkLuaModifier = function(name, path)
    local module = require(path)
    assert(_G[name] == module, "engine and require must share the modifier definition")
end
local bus = require("core/event_bus")
local events = require("core/events")
local jobs, heroes, snapshots, created, entities, enemies, orders = {}, {}, {}, {}, {}, {}, {}
local rate_name = "modifier_hero_exclusive_summon_attack_rate"
local rate_class = require("modifiers/" .. rate_name)
local clone_class = require("modifiers/modifier_blademaster_clone")
local q_enabled = false
local next_index = 10
package.loaded["core/scheduler"] = {
    after = function(_, callback, id) jobs[id] = callback; return id end,
    every = function(_, callback, id) jobs[id] = callback; return id end,
    cancel = function(id) jobs[id] = nil end,
}
package.loaded["systems/gameplay_phase_guard"] = { post_clear_frozen = function() return false end }
package.loaded["systems/destination_validation_service"] = {
    validate = function(position) return not position.forbidden end,
}
package.loaded["systems/hero_cosmetic_service"] = {
    sync_appearance = function() return true end, clear = function() end,
}
local function near(actual, expected, message)
    assert(math.abs(actual - expected) < 1e-8,
        message .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local function unit(player_id)
    next_index = next_index + 1
    local entity = { id = next_index, player_id = player_id, modifiers = {}, bat = 1.4,
        native_bat = 1.4,
        ias = 1, damage_writes = 0, rate_adds = 0, bat_writes = 0,
        health = 1000, maximum = 1000, armor = 6, attack_range = 800, move_speed = 500,
        position = Vector(player_id * 10000, 0, 0), team = 2, idle = true, abilities = {} }
    entities[entity.id] = entity
    function entity:IsNull() return self.null == true end
    function entity:IsAlive() return not self.null and not self.dead end
    function entity:entindex() return self.id end
    function entity:GetUnitName() return "npc_dota_hero_juggernaut" end
    function entity:GetTeamNumber() return self.team end
    function entity:GetPlayerOwnerID() return self.player_id end
    function entity:GetAbsOrigin() return self.position end
    function entity:SetPlayerID(id) self.player_id = id end
    function entity:SetControllableByPlayer() end
    function entity:GetOwner() return self.owner end
    function entity:FindModifierByName(name) return self.modifiers[name] end
    function entity:SetBaseDamageMin(value) self.damage_min = value; self.damage_writes = self.damage_writes + 1 end
    function entity:SetBaseDamageMax(value) self.damage_max = value; self.damage_writes = self.damage_writes + 1 end
    function entity:SetBaseAttackTime(value) self.bat = value; self.bat_writes = self.bat_writes + 1 end
    function entity:GetBaseAttackTime() return self.bat end
    function entity:AddAbility(name)
        local ability = { name = name, level = 0 }
        function ability:IsNull() return false end
        function ability:GetAbilityName() return self.name end
        function ability:SetLevel(value) self.level = value end
        function ability:SetHidden(value) self.hidden = value end
        function ability:SetActivated(value) self.active = value end
        self.abilities[#self.abilities + 1] = ability
        return ability
    end
    function entity:GetAbilityCount() return #self.abilities end
    function entity:GetAbilityByIndex(index) return self.abilities[index + 1] end
    function entity:FindAbilityByName(name)
        for _, ability in ipairs(self.abilities) do if ability.name == name then return ability end end
    end
    function entity:RemoveAbility(name)
        for i, ability in ipairs(self.abilities) do if ability.name == name then table.remove(self.abilities, i); return end end
    end
    for _, name in ipairs({ "juggernaut_blade_fury", "juggernaut_blade_dance", "juggernaut_omni_slash" }) do
        entity:AddAbility(name)
    end
    function entity:SetAttackCapability(value) self.attack_capability = value end
    function entity:SetMoveCapability(value) self.move_capability = value end
    function entity:SetIdleAcquire(value) self.idle_acquire = value end
    function entity:SetAcquisitionRange(value) self.acquisition_range = value end
    -- Engine-compatible fallback: the setter alone may leave the native
    -- carrier's range unchanged, so the range override must carry the value.
    function entity:Script_SetAttackRange(value) self.requested_range = value end
    function entity:Script_GetAttackRange()
        local modifier = self.modifiers.modifier_survival_hero_attack_range
        return modifier and modifier.range or self.attack_range
    end
    function entity:SetBaseMoveSpeed(value) self.move_speed = value end
    function entity:GetIdealSpeed() return self.move_speed end
    function entity:SetPhysicalArmorBaseValue(value) self.armor = value end
    function entity:GetPhysicalArmorValue() return self.armor end
    function entity:GetMaxHealth() return self.maximum end
    function entity:GetHealth() return self.health end
    function entity:SetMaxHealth(value) self.maximum = value end
    function entity:SetBaseMaxHealth(value) self.base_maximum = value end
    function entity:SetHealth(value) self.health = value end
    function entity:GetAttackTarget() return self.attack_target end
    function entity:IsIdle() return self.idle end
    function entity:Stop()
        self.attack_target, self.idle = nil, true
        self.stops = (self.stops or 0) + 1
    end
    for _, method in ipairs({ "SetBaseStrength", "SetBaseAgility", "SetBaseIntellect",
        "SetStrengthGain", "SetAgilityGain", "SetIntellectGain" }) do
        entity[method] = function(self, value) self[method .. "_value"] = value end
    end
    function entity:CalculateStatBonus() end
    function entity:AddNoDraw() self.hidden = true end
    function entity:AddNewModifier(_, _, name, params)
        if name == "modifier_survival_hero_attack_range" then
            local modifier = { range = params.attack_range,
                SetAttackRange = function(self, value) self.range = value end }
            self.modifiers[name] = modifier
            return modifier
        end
        if name == "modifier_blademaster_clone" then
            local modifier = setmetatable({}, {__index = clone_class})
            function modifier:GetParent() return entity end
            modifier:OnCreated(params)
            self.modifiers[name] = modifier
            return modifier
        end
        assert(name == rate_name, "actual cadence must use the registered fixed-rate modifier")
        self.rate_adds = self.rate_adds + 1
        local modifier = setmetatable({ transmissions = 0, refreshes = 0 }, { __index = rate_class })
        function modifier:SetHasCustomTransmitterData(value) self.transmitter = value end
        function modifier:SendBuffRefreshToClients() self.transmissions = self.transmissions + 1 end
        function modifier:ForceRefresh()
            self.refreshes = self.refreshes + 1
            self:OnRefresh({})
            self.native_interval = self:GetModifierFixedAttackRate()
        end
        function modifier:GetParent() return entity end
        modifier:OnCreated(params)
        modifier.native_interval = modifier:GetModifierFixedAttackRate()
        self.modifiers[name] = modifier
        return modifier
    end
    function entity:GetAttacksPerSecond(ignore_temporary)
        assert(ignore_temporary == false, "inherit effective speed including temporary effects")
        if self.runtime_aps then return self.runtime_aps end
        local fixed = self.modifiers[rate_name]
        return fixed and 1 / fixed.native_interval or self.ias / self.bat
    end
    return entity
end
local function native_bat_retained(entity, phase)
    near(entity:GetBaseAttackTime(), entity.native_bat,
        phase .. ": fixed-rate inheritance must retain the native animation BAT")
    assert(entity.bat_writes == 0,
        phase .. ": do not reset or shorten carrier BAT while applying fixed attack rate")
end
CreateUnitByName = function(_, position, _, owner)
    local clone = unit(owner.player_id)
    clone.owner = owner
    clone.position = position
    created[#created + 1] = clone
    return clone
end
UTIL_Remove = function(entity) entity.null = true end
FindClearSpaceForUnit = function(entity, position) entity.position = position; entity.cleared_space = true end
FindUnitsInRadius = function() return enemies end
ExecuteOrderFromTable = function(order)
    orders[#orders + 1] = order
    local entity = entities[order.UnitIndex]
    entity.attack_target = order.TargetIndex and entities[order.TargetIndex]
    entity.idle = false
end
local function fixed(hero, interval)
    hero.modifiers.modifier_debug_fixed_attack_rate = interval and {
        GetModifierFixedAttackRate = function() return interval end,
    } or nil
end
local function source(player_id, rate)
    local hero = unit(player_id)
    hero.survival_hero_id = "hero_blademaster"
    hero.runtime_aps = 0.7 -- stale frame from native getter while addspeed owns cadence
    fixed(hero, 1 / rate)
    heroes[player_id] = hero
    snapshots[player_id] = { entindex = hero.id, attack_min = 112, attack_max = 120,
        base_attack_time = 1 / 0.7, attack_speed = 0.7, max_health = 1000,
        strength = 100, agility = 200, intellect = 300, critical_chance_pct = 25, critical_damage_pct = 1500 }
    return hero
end
bus.handle_request(events.HERO_SUMMON_GET_REQUEST, function(payload)
    return { ok = heroes[payload.player_id] ~= nil, unit = heroes[payload.player_id] }
end)
bus.handle_request(events.HERO_COMBAT_STATS_GET_REQUEST, function(payload)
    return { ok = true, snapshot = snapshots[payload.player_id] }
end)
bus.handle_request(events.HERO_SKILL_STATE_GET_REQUEST, function()
    return { ok = true, snapshot = { skills = {
        { skill_id = "skill_blademaster_agility", level = 1 },
        { skill_id = "skill_blademaster_exclusive", level = q_enabled and 1 or 0, locked = q_enabled and 0 or 1 },
    } } }
end)
local service = require("systems/blademaster_exclusive_service")
service.init()
local hero0, hero1 = source(0, 10), source(1, 3)
bus.emit(events.HERO_SKILL_CHANGED, { player_id = 0 })
local clone0 = assert(created[#created])
bus.emit(events.HERO_SKILL_CHANGED, { player_id = 1 })
local clone1 = assert(created[#created])
near(clone0:GetAttacksPerSecond(false), 10, "new clone attacks ten times/s despite old snapshot BAT")
near(clone1:GetAttacksPerSecond(false), 3, "second player inherits only its source")
native_bat_retained(clone0, "birth")
native_bat_retained(clone1, "second player birth")
near(clone0.survival_attack_speed, 10, "HUD cache follows actual modifier cadence")
local modifier = clone0:FindModifierByName(rate_name)
assert(modifier and modifier.transmitter, "native attack property must be client synchronized")
local transmissions, bat_writes, refreshes = modifier.transmissions, clone0.bat_writes, modifier.refreshes
for i = 1, 100 do jobs.blademaster_growth() end
assert(clone0.rate_adds == 1 and modifier.transmissions == transmissions
    and clone0.bat_writes == bat_writes and modifier.refreshes == refreshes,
    "idle polling must not re-add or restart attacks")
assert(clone0.damage_writes == 2, "speed sync does not alter established damage inheritance")
native_bat_retained(clone0, "repeated unchanged ticks")

fixed(hero0, 0.2)
bus.emit(events.HERO_COMBAT_STATS_CHANGED, { player_id = 0, snapshot = snapshots[0] })
near(clone0:GetAttacksPerSecond(false), 5, "addspeed update synchronizes immediately")
native_bat_retained(clone0, "changed-rate event")
assert(modifier.refreshes == refreshes + 1, "changed rate invalidates the native property cache exactly once")
near(clone1:GetAttacksPerSecond(false), 3, "speed event is player scoped")
fixed(hero0, 0.25)
bus.emit(events.HERO_COMBAT_STATS_CHANGED, { player_id = 0, snapshot = snapshots[1] })
near(clone0:GetAttacksPerSecond(false), 5, "wrong hero identity must not update clone")
jobs.blademaster_growth()
near(clone0:GetAttacksPerSecond(false), 4, "poll catches fixed rate changes without events")
native_bat_retained(clone0, "changed-rate poll")
fixed(hero0, nil)
hero0.runtime_aps = 2.5
jobs.blademaster_growth()
clone0.ias = 7
near(clone0:GetAttacksPerSecond(false), 2.5, "clone IAS must not multiply the inherited fixed interval")
native_bat_retained(clone0, "fixed-rate removal and source runtime fallback")
clone0.modifiers[rate_name] = nil
jobs.blademaster_growth()
near(clone0:GetAttacksPerSecond(false), 2.5, "missing native modifier is repaired")
assert(clone0.rate_adds == 2)
native_bat_retained(clone0, "missing modifier repair")

clone0.dead = true
bus.emit(events.ENGINE_ENTITY_KILLED, { victim = clone0 })
fixed(hero0, 0.05)
assert(jobs["blademaster_clone_respawn:0"])()
local respawned = created[#created]
assert(respawned ~= clone0)
near(respawned:GetAttacksPerSecond(false), 20, "respawn uses the latest source rate")
native_bat_retained(respawned, "respawn")
bus.emit(events.HERO_REMOVED, { player_id = 0, unit = hero0 })
heroes[0] = nil
assert(respawned.null)
jobs.blademaster_growth()
assert(not clone1.null)
local replacement = source(0, 8)
bus.emit(events.HERO_SKILL_CHANGED, { player_id = 0 })
local replacement_clone = created[#created]
near(replacement_clone:GetAttacksPerSecond(false), 8, "delete then summon restores runtime synchronization")
native_bat_retained(replacement_clone, "delete then resummon")
fixed(hero0, 0.01)
bus.emit(events.HERO_COMBAT_STATS_CHANGED, { player_id = 0, snapshot = { entindex = hero0.id } })
near(replacement_clone:GetAttacksPerSecond(false), 8, "old-source callbacks cannot change replacement")
assert(replacement_clone.survival_exclusive_summon and replacement_clone.survival_permanent_summon)
assert(replacement_clone.attack_capability == DOTA_UNIT_CAP_MELEE_ATTACK
    and replacement_clone.move_capability == DOTA_UNIT_CAP_MOVE_GROUND
    and replacement_clone.idle_acquire and replacement_clone.cleared_space,
    "W must be a movable normal attacker, not the E no-attack visual caster")
assert(replacement_clone:GetAbilityCount() == 1
    and replacement_clone:FindAbilityByName("ability_survival_blademaster_exclusive")
    and not replacement_clone:FindAbilityByName("juggernaut_blade_fury"),
    "combat clone retains only its custom Q, never native rotating abilities")
for _, method in ipairs({ "SetBaseStrength", "SetBaseAgility", "SetBaseIntellect",
    "SetStrengthGain", "SetAgilityGain", "SetIntellectGain" }) do
    assert(replacement_clone[method .. "_value"] == 0, "native attributes must not double logical stats")
end
local clone_modifier = replacement_clone.modifiers.modifier_blademaster_clone
near(clone_modifier.combat_snapshot.critical_damage_pct, 2250, "source final crit plus W 750 percent bonus")
near(snapshots[0].critical_damage_pct, 1500, "inherited modifier snapshot must not mutate the source")
near(replacement_clone.survival_exclusive_stat_snapshot.strength, 100, "selected clone logical attributes")
replacement_clone.health = 250
jobs.blademaster_growth()
near(replacement_clone.health, 250, "unchanged polling cannot heal")
snapshots[0].attack_min, snapshots[0].attack_max = 1e12, 2e12
snapshots[0].max_health = 2000
snapshots[0].strength, snapshots[0].agility, snapshots[0].intellect = 700, 800, 900
replacement.armor, replacement.attack_range, replacement.move_speed = 12, 1100, 600
bus.emit(events.HERO_COMBAT_STATS_CHANGED, { player_id = 0, snapshot = snapshots[0] })
near(replacement_clone.damage_min, 5e7, "safe native attack min")
near(replacement_clone.damage_max, 1e8, "safe native attack max")
near(require("combat/endless_stat_projection").outgoing(replacement_clone,
    replacement_clone.damage_max, true), 2e12, "one existing damage-filter projection restores huge attack")
near(replacement_clone.health, 500, "increased maximum preserves wounded health fraction")
near(replacement_clone.armor, 12, "clone inherits source effective armor")
near(replacement_clone:Script_GetAttackRange(), 1100, "native override inherits source range when setter is ineffective")
near(replacement_clone.move_speed, 600, "clone inherits actual source speed")
near(replacement_clone.survival_exclusive_stat_snapshot.attack_max, 2e12, "logical damage for HUD")
near(replacement_clone.survival_exclusive_stat_snapshot.intellect, 900, "logical attributes refresh")
local writes = replacement_clone.damage_writes
jobs.blademaster_growth()
assert(replacement_clone.damage_writes == writes, "stable full-stat sync must avoid redundant damage writes")
near(replacement_clone.health, 500, "stable updated stats still cannot refill health")
native_bat_retained(replacement_clone, "full stat and visual inheritance")

local wall = unit(0)
wall.position = Vector(400, 0, 0)
bus.emit(events.BUILDING_CREATED, { player_id = 0, building_id = "wall", unit = wall })
local enemy = unit(-1)
enemy.team, enemy.position = 3, Vector(500, 0, 0)
enemies = { enemy }
local order_count = #orders
service._test.guard_clone(0)
assert(#orders == order_count + 1 and orders[#orders].OrderType == DOTA_UNIT_ORDER_ATTACK_TARGET
    and orders[#orders].TargetIndex == enemy.id, "idle W acquires an enemy near its own wall")
for _ = 1, 20 do service._test.guard_clone(0) end
assert(#orders == order_count + 1, "guard ticks must not restart an effective attack order")
replacement_clone.attack_target = nil -- native getter may disappear between attack records
for _ = 1, 5 do service._test.guard_clone(0) end
assert(#orders == order_count + 1, "pending target prevents transient getter gaps restarting rapid attacks")
enemy.dead = true
replacement_clone.position = Vector(6000, 0, 0)
service._test.guard_clone(0)
assert(orders[#orders].OrderType == DOTA_UNIT_ORDER_MOVE_TO_POSITION
    and orders[#orders].Position.x < 1000, "guardian returns to its own home after losing a distant target")
order_count = #orders
service._test.guard_clone(0)
assert(#orders == order_count, "return order is not resent on stable ticks")
local home = orders[#orders].Position
replacement_clone.position, replacement_clone.idle = home, true
replacement.position = Vector(12000, 0, 0)
service._test.guard_clone(0)
assert(#orders == order_count, "moving the source hero must not drag the permanent home anchor")
enemy.dead, enemy.position = false, Vector(8000, 0, 0)
service._test.guard_clone(0)
assert(#orders == order_count, "guardian cannot chase an enemy beyond its leash")
enemy.position = { x = 1800, y = 0, z = 0, forbidden = true }
service._test.guard_clone(0)
assert(#orders == order_count, "guardian cannot chase through a forbidden boundary")
bus.emit(events.BUILDING_DESTROYED, { player_id = 0, building_id = "wall", unit = wall })
enemy.position = Vector(300, 0, 0)
service._test.guard_clone(0)
assert(orders[#orders].TargetIndex == enemy.id, "destroyed wall falls back to the fixed birth home")
replacement_clone.position = Vector(0, 0, 0)
enemy.position = Vector(8000, 0, 0)
local stops = replacement_clone.stops or 0
service._test.guard_clone(0)
assert(replacement_clone.stops == stops + 1 and replacement_clone.attack_target == nil,
    "an invalid target cannot leave a native chase running while the clone is already home")
service._test.guard_clone(0)
assert(replacement_clone.stops == stops + 1, "idle guarding must not repeatedly Stop")
local other_order_count = #orders
service._test.guard_clone(1)
assert(#orders == other_order_count, "other player's guardian cannot acquire targets at this home")
enemies = {}
replacement.dead = true
replacement_clone.dead = true
bus.emit(events.ENGINE_ENTITY_KILLED, { victim = replacement_clone })
jobs["blademaster_clone_respawn:0"]()
local clone_count = #created
replacement.dead = false
jobs.blademaster_growth()
assert(#created == clone_count + 1, "if source was dead at respawn time, periodic retry restores the permanent clone")
local recovered = created[#created]
assert(recovered.owner == replacement and recovered.position.x < 1000,
    "resummon stays at original home even after source moved")
near(recovered:GetAttacksPerSecond(false), 8, "recovered guardian retains source cadence")
native_bat_retained(recovered, "guard lifecycle recovery")

-- Joint service + actual clone modifier: inherited Q uses the source's one
-- critical roll, including lethal ordinary hits, and never rolls a second proc.
local combat_events = require("combat/combat_events")
local random_values, copies, damage_numbers, q_positions = {}, {}, {}, {}
local critical_calls = 0
RandomFloat = function(low, high)
    assert(low == 0 and high == 100)
    critical_calls = critical_calls + 1
    return assert(table.remove(random_values, 1), "Q must not consume a second probability roll")
end
PlayerResource = {GetPlayer = function(_, player_id) return player_id end}
SendOverheadEventMessage = function(player_id, style, target, damage)
    damage_numbers[#damage_numbers + 1] = {player_id = player_id, style = style, target = target, damage = damage}
end
local ordinary_events = 0
for _, event in ipairs({events.HERO_MAIN_ATTACK_LANDED, events.HERO_MAIN_ATTACK_FIRED,
        events.HERO_FINAL_CRITICAL_ATTACK_DAMAGE}) do
    bus.subscribe(event, function() ordinary_events = ordinary_events + 1 end)
end
local create_combat_unit = CreateUnitByName
CreateUnitByName = function(name, position, clear, owner, ...)
    if name == "npc_dota_hero_legion_commander" then
        q_positions[#q_positions + 1] = position
        return nil -- Native rendering is outside this Lua integration test.
    end
    return create_combat_unit(name, position, clear, owner, ...)
end
local q_modifier = recovered:FindModifierByName("modifier_blademaster_clone")
local q_ability = recovered:FindAbilityByName("ability_survival_blademaster_exclusive")
bus.handle_request(combat_events.DEAL_REQUEST, function(payload)
    assert(payload.source_kind == "ability" and payload.damage_type == DAMAGE_TYPE_PURE
        and payload.can_crit == false and payload.tags.non_recursive == true)
    copies[#copies + 1] = payload
    if payload.attacker == recovered then
        assert(payload.ability == q_ability)
        assert(q_modifier:GetModifierDamageOutgoing_Percentage({inflictor = q_ability,
            damage_category = DOTA_DAMAGE_CATEGORY_SPELL}) == 0)
        q_modifier:OnTakeDamage({attacker = recovered, unit = payload.victim,
            damage = payload.base_damage, inflictor = q_ability,
            damage_category = DOTA_DAMAGE_CATEGORY_SPELL})
    end
    return {ok = true}
end)
local primary, nearby, distant = unit(-1), unit(-1), unit(-1)
primary.team, nearby.team, distant.team = 3, 3, 3
primary.position, nearby.position, distant.position = Vector(500, 20, 0), Vector(600, 20, 0), Vector(2000, 20, 0)
FindUnitsInRadius = function(team, center, _, radius, team_filter, types, flags)
    assert(team == 2 and center.x == primary.position.x and center.y == primary.position.y
        and radius == 600 and team_filter == DOTA_UNIT_TARGET_TEAM_ENEMY
        and types == DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC
        and flags == DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES)
    return {primary, nearby} -- Spatial query excludes the distant unit.
end
local function attack(id, random, damage, options)
    options = options or {}
    local record_params = {attacker = recovered, target = primary, record = id,
        is_multishot_secondary = options.secondary}
    if random ~= nil then random_values[#random_values + 1] = random end
    q_modifier:OnAttackRecord(record_params)
    if options.kill_primary then primary.dead = true end
    local before = #copies
    q_modifier:OnTakeDamage({attacker = recovered, unit = primary, record = id,
        damage = damage, damage_category = DOTA_DAMAGE_CATEGORY_ATTACK})
    q_modifier:OnTakeDamage({attacker = recovered, unit = primary, record = id,
        damage = damage, damage_category = DOTA_DAMAGE_CATEGORY_ATTACK})
    q_modifier:OnAttackRecordDestroy(record_params)
    assert(#random_values == 0)
    return #copies - before
end
q_enabled = true
snapshots[0].critical_chance_pct = 30
bus.emit(events.HERO_COMBAT_STATS_CHANGED, {player_id = 0, snapshot = snapshots[0]})
near(q_modifier.combat_snapshot.critical_chance_pct, 30, "clone receives the source Q's exact current critical chance")
assert(attack(10001, 29.99, 321) == 2,
    "one confirmed 30-percent ordinary crit copies Q damage to primary and nearby enemy")
assert(critical_calls == 1 and ordinary_events == 0 and copies[1].base_damage == 321
    and copies[2].victim == nearby and copies[2].base_damage == 321)
assert(attack(10002, 30, 321) == 0, "the exact same source critical threshold rejects noncritical hits")
assert(attack(10003, 0, 765, {kill_primary = true}) == 1 and copies[#copies].victim == nearby
    and copies[#copies].base_damage == 765,
    "a killed primary remains the Q impact center; only its living neighbours take copied pure damage")
assert(q_positions[#q_positions] == primary.position and ordinary_events == 0)
local before_main = #copies
replacement:AddAbility("ability_survival_blademaster_exclusive")
assert(service._test.q_replicate({player_id = 0, attacker = replacement, target = primary,
    critical = true, is_main_attack = true, final_damage = 765}))
assert(#copies == before_main + 1 and copies[#copies].victim == nearby
    and copies[#copies].base_damage == 765,
    "main hero and VIP defender use the same lethal-hit Q rule and area implementation")
primary.dead = false
snapshots[0].critical_chance_pct = 60
bus.emit(events.HERO_COMBAT_STATS_CHANGED, {player_id = 0, snapshot = snapshots[0]})
assert(attack(10004, 50, 88) == 2, "a live source critical-chance upgrade applies to the very next clone attack")
snapshots[0].critical_chance_pct = 0
bus.emit(events.HERO_COMBAT_STATS_CHANGED, {player_id = 0, snapshot = snapshots[0]})
assert(attack(10005, nil, 88) == 0, "zero source critical chance never rolls or triggers Q")
snapshots[0].critical_chance_pct = 100
bus.emit(events.HERO_COMBAT_STATS_CHANGED, {player_id = 0, snapshot = snapshots[0]})
assert(attack(10006, nil, 88, {secondary = true}) == 0, "secondary attacks neither roll nor trigger the inherited Q")
assert(attack(10007, 0, 0) == 0, "blocked zero-damage attacks cannot trigger Q")
q_enabled = false
assert(attack(10008, 0, 88) == 0, "a locked source Q remains unavailable to its clone even if another stat gives crit")
q_enabled = true
assert(not service.trigger_clone_q(1, recovered, primary, 88)
    and not service.trigger_clone_q(0, replacement_clone, primary, 88),
    "foreign-player and replaced/dead clones cannot invoke Q")
primary.null = true
assert(not service.trigger_clone_q(0, recovered, primary, 88), "a deleted target has no usable impact point")
primary.null, primary.team = false, 2
assert(not service.trigger_clone_q(0, recovered, primary, 88))
assert(not service._test.q_replicate({player_id = 0, attacker = replacement, target = primary,
    critical = true, is_main_attack = true, final_damage = 88}), "main and clone both reject friendly targets")
assert(ordinary_events == 0)
print("BLADEMASTER_ATTACK_RATE_PASS fixed cadence/BAT, safe full stats, guard lifecycle; actual clone modifier/source crit parity, once-only Q, lethal-hit pure-area copy and no secondary recursion")
