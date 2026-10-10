-- Native overflow regression with the production hero service, stat adapter,
-- attack/equipment modifiers, shared attack projection and damage filter.
-- Run from addon root with Lua 5.1; only native/bootstrap and stat-source
-- service boundaries are mocked. The generated hero/weapon/rules are real.
package.path = "scripts/vscripts/?.lua;" .. package.path

for _, name in ipairs({ "systems/effect_handler_registry", "systems/equipment_effect_service",
    "systems/equipment_stat_aggregation_service", "systems/triggered_proc_service" }) do
    package.loaded[name] = { init = function() end }
end
package.loaded["core/logger"] = { info = function() end, warn = function() end }
package.loaded["systems/tree_damage_rules"] = {
    is_tree = function() return false end,
    is_basic_attack_category = function(category) return tonumber(category) == 1 end,
    allows_damage = function() return true end,
    reset_pending_attacks = function() end,
}
package.loaded["systems/anti_air_rules"] = {
    can_attack = function() return true end,
    has_damage_taken_aura = function() return false end,
}
package.loaded["systems/rogue_effect_state_service"] = {
    has_effect = function() return false end, numeric = function() return 0 end,
}
local technology, equipment, equipment_stats, growth, progression, skills = {}, {}, {}, {}, {}, {}
package.loaded["systems/technology_stat_manager"] = {
    get = function(id) return { final = { hero = technology[id] or {} } } end,
}

local server, time = true, 0
IsServer = function() return server end
class = function(base) return base or {} end
RandomFloat = function() return 0 end
DOTA_UNIT_CAP_RANGED_ATTACK, DOTA_UNIT_CAP_MELEE_ATTACK = 2, 1
DAMAGE_TYPE_PHYSICAL, DAMAGE_TYPE_MAGICAL, DAMAGE_TYPE_PURE = 1, 2, 4
-- Native Dota values: SPELL is explicitly zero, not an unknown category.
DOTA_DAMAGE_CATEGORY_ATTACK, DOTA_DAMAGE_CATEGORY_SPELL = 1, 0
DOTA_DAMAGE_FLAG_IGNORES_PHYSICAL_ARMOR = 2
GameRules = { GetGameTime = function() return time end }

local bus = require("core/event_bus")
local events = require("core/events")
local damage_events = require("combat/combat_events")
local scheduler = require("core/scheduler")
local projection = require("combat/endless_stat_projection")
require("modifiers/modifier_weapon_stat_projection")
require("modifiers/modifier_equipment_effects")
require("modifiers/modifier_survival_hero_base_health")

local entities, counts, publications = {}, {}, {}
EntIndexToHScript = function(index) return entities[index] end
local function count(unit, key)
    local current = counts[unit]
    current[key] = (current[key] or 0) + 1
end
local function near(actual, expected, label)
    assert(type(actual) == "number" and actual == actual
        and math.abs(actual - expected) <= math.max(1e-7, math.abs(expected) * 1e-11),
        (label or "number") .. ": " .. tostring(actual) .. " != " .. tostring(expected))
end
local function stats(player_id)
    local result, problem = bus.request(events.HERO_COMBAT_STATS_GET_REQUEST, { player_id = player_id })
    assert(result and result.ok, tostring(problem or result and result.error))
    return result.snapshot
end
local function unit(index, player_id)
    local u = { index = index, player_id = player_id, modifiers = {},
        health = 230, maximum = 300, native_health = 300,
        damage_min = 558, damage_max = 558, bat = 1 / 0.7, team = 2 }
    entities[index], counts[u] = u, {}
    function u:IsNull() return self.null == true end
    function u:IsAlive() return not self.null and not self.dead end
    function u:IsRealHero() return self.player_id ~= nil end
    function u:IsInvulnerable() return false end
    function u:entindex() return self.index end
    function u:GetPlayerOwnerID() return self.player_id end
    function u:GetLevel() return 1 end
    function u:GetUnitName() return "npc_dota_hero_monkey_king" end
    function u:GetTeamNumber() return self.team end
    function u:GetHealth() return self.health end
    function u:GetMaxHealth() return self.maximum end
    function u:SetHealth(value) count(self, "health"); self.health = value end
    function u:GetBaseDamageMin() return self.damage_min end
    function u:GetBaseDamageMax() return self.damage_max end
    function u:SetBaseDamageMin(value) count(self, "damage_min"); self.damage_min = math.floor(value) end
    function u:SetBaseDamageMax(value) count(self, "damage_max"); self.damage_max = math.floor(value) end
    function u:SetBaseStrength(value) count(self, "strength"); self.strength = value end
    function u:SetBaseAgility(value) count(self, "agility"); self.agility = value end
    function u:SetBaseIntellect(value) count(self, "intellect"); self.intellect = value end
    function u:GetBaseAttackTime() return self.bat end
    function u:SetBaseAttackTime(value) count(self, "bat"); self.bat = value end
    function u:GetAttackSpeed() return 100 end
    function u:GetPhysicalArmorValue() return 0 end
    function u:GetAttackRange() return self.range or 150 end
    function u:Script_SetAttackRange(value) self.range = value end
    function u:SetAcquisitionRange(value) self.acquisition = value end
    function u:GetMoveCapability() return 1 end
    function u:GetAttackCapability() return self.capability or 2 end
    function u:SetAttackCapability(value) self.capability = value end
    function u:GetProjectileSpeed() return self.projectile_speed or 3000 end
    function u:SetProjectileSpeed(value) self.projectile_speed = value end
    function u:SetRangedProjectileName(value) self.projectile = value end
    function u:FindModifierByName(name) return self.modifiers[name] end
    function u:HasModifier(name) return self.modifiers[name] ~= nil end
    function u:RemoveModifierByName(name) self.modifiers[name] = nil end
    function u:CalculateStatBonus()
        count(self, "calculate")
        local bonus = self.modifiers.modifier_survival_hero_base_health
        local gear = self.modifiers.modifier_equipment_effects
        self.maximum = self.native_health + (bonus and bonus:GetStackCount() or 0)
            + (gear and gear:GetModifierHealthBonus() or 0)
        -- Reproduce native stat refresh's reported refill, so production
        -- health preservation is exercised by every projection change.
        self.health = self.maximum
    end
    function u:AddNewModifier(_, _, name, params)
        count(self, "add:" .. name)
        local m = setmetatable({ stack = 0 }, { __index = _G[name] or {} })
        function m:GetParent() return u end
        function m:GetStackCount() return self.stack end
        function m:SetStackCount(value) self.stack = value end
        function m:SetHasCustomTransmitterData() end
        function m:SendBuffRefreshToClients() self.transmitted = self:AddCustomTransmitterData() end
        function m:StartIntervalThink(interval) self.interval = interval end
        function m:ForceRefresh()
            count(u, "refresh:" .. name)
            if self.OnRefresh then self:OnRefresh({}) end
        end
        function m:SetAttackRange(value) self.range = value end
        function m:SetTechnologyValues(_, final_damage) u.survival_research_final_damage_pct = final_damage end
        function m:SetProjectileSpeedBonus(value) self.stack = value end
        self.modifiers[name] = m
        if m.OnCreated then m:OnCreated(params or {}) end
        return m
    end
    function u:GetAverageTrueAttackDamage()
        local weapon = self.modifiers.modifier_weapon_stat_projection
        local gear = self.modifiers.modifier_equipment_effects
        local amount = (self.damage_min + self.damage_max) * 0.5
            + (weapon and weapon:GetModifierPreAttack_BonusDamage() or 0)
            + (gear and gear:GetModifierPreAttack_BonusDamage() or 0)
        -- Native readback on the live hero produced exactly this signed int.
        return amount > 2147483647 and -2147483648 or amount
    end
    return u
end
package.loaded["core/modifier_registry"] = { ensure = function(u, name, params)
    return u:FindModifierByName(name) or u:AddNewModifier(u, nil, name, params)
end }
local output = print
print = function(message)
    if tostring(message):find("%[EventBus%] handler error")
        or tostring(message):find("%[Scheduler%] task failed") then error(message) end
end
local service = require("systems/hero_combat_stat_service")
service.init()
local function request_snapshot(event, source, key)
    bus.handle_request(event, function(payload)
        return { ok = true, snapshot = key and { [key] = source[payload.player_id] or {} }
            or source[payload.player_id] or {} }
    end)
end
request_snapshot(events.WEAPON_EQUIPMENT_GET_REQUEST, equipment)
request_snapshot(events.WEAPON_GROWTH_GET_REQUEST, growth)
request_snapshot(events.EQUIPMENT_STATS_GET_REQUEST, equipment_stats, "values")
request_snapshot(events.HERO_PROGRESSION_GET_REQUEST, progression)
request_snapshot(events.HERO_SKILL_STATE_GET_REQUEST, skills, "skills")
bus.subscribe(events.HERO_COMBAT_STATS_CHANGED, function(payload)
    publications[payload.player_id] = (publications[payload.player_id] or 0) + 1
end)
local function summon(index, player_id)
    equipment[player_id] = { main_hand_content_id = "weapon_growth_sword_01", main_hand_name = "Growth" }
    equipment_stats[player_id] = { attack_flat = 137, attack_speed_pct = 15 }
    growth[player_id], progression[player_id] = {}, {}
    skills[player_id] = { { skill_id = "skill_monkey_king_fury", level = 1, locked = 0 } }
    technology[player_id] = { critical_chance_pct = 100 }
    local hero = unit(index, player_id)
    bus.emit(events.HERO_SUMMONED, { player_id = player_id, hero_id = "hero_monkey_king", unit = hero })
    hero.health = hero.maximum - 777
    return hero
end
local first, second = summon(101, 0), summon(102, 1)
scheduler.clear()
local other_stats, other_publications = stats(1), publications[1]
local other_counts = {}
for key, value in pairs(counts[second]) do other_counts[key] = value end
local function owner_unchanged()
    assert(stats(1) == other_stats and publications[1] == other_publications,
        "other owner's snapshot or publication changed")
    for key, value in pairs(counts[second]) do assert(value == other_counts[key], "other owner native write: " .. key) end
    near(second.maximum - second.health, 777, "other owner's missing health")
end
local function check_native(hero, label)
    local current = stats(hero.player_id)
    local scale = tonumber(current.native_attack_scale)
    assert(scale and scale >= 1, label .. ": missing native_attack_scale")
    near(hero.survival_endless_attack_scale, scale, label .. ": filter shares scale")
    local native_attack = hero:GetAverageTrueAttackDamage()
    assert(native_attack >= 0, label .. ": native signed-int attack overflow")
    local logical = (current.engine_attack_min + current.engine_attack_max) * 0.5
        + current.engine_equipment_attack_bonus
    near(native_attack * scale, logical, label .. ": every flat component scales exactly once")
    local critical_factor = math.max(1, current.critical_damage_pct / 100)
    assert(native_attack * critical_factor <= 1e8 + 1e-5,
        label .. ": post-critical native attack exceeds 1e8")
    near(hero.damage_min, current.native_base_attack_min, label .. ": exact native minimum setter")
    near(hero.damage_max, current.native_base_attack_max, label .. ": exact native maximum setter")
    near(native_attack, (current.native_attack_min + current.native_attack_max) * 0.5,
        label .. ": snapshot includes all native components")
    local min_logical = current.engine_attack_min + current.engine_equipment_attack_bonus
    local max_logical = current.engine_attack_max + current.engine_equipment_attack_bonus
    assert(math.abs(current.native_attack_min * scale - min_logical) <= scale + 1e-6
        and math.abs(current.native_attack_max * scale - max_logical) <= scale + 1e-6,
        label .. ": integer native damage range exceeds one scaled unit error")
    near(first.maximum - first.health, 777, label .. ": projection cannot heal")
    -- Both engine VMs must return the same bounded modifier values.
    for _, name in ipairs({ "modifier_weapon_stat_projection", "modifier_equipment_effects" }) do
        local modifier = hero.modifiers[name]
        local native_bonus = modifier:GetModifierPreAttack_BonusDamage()
        local transmitted = modifier:AddCustomTransmitterData()
        modifier:HandleCustomTransmitterData(transmitted)
        server = false
        local client_bonus = modifier:GetModifierPreAttack_BonusDamage()
        server = true
        near(client_bonus, native_bonus, label .. ": client native bonus " .. name)
        assert(math.abs(client_bonus) <= 1e8, label .. ": transmitter bonus overflow")
    end
    owner_unchanged()
    return current, native_attack
end
local function debug_attack(value)
    local response, problem = bus.request(events.HERO_COMBAT_STATS_DEBUG_ATTACK_REQUEST,
        { player_id = 0, attack = value })
    assert(response and response.ok, tostring(problem or response and response.error))
    return response.snapshot
end

local ordinary = check_native(first, "ordinary")
near(ordinary.attack_min, 745, "ordinary production config and equipment formula")
near(ordinary.native_attack_scale, 1, "ordinary attack retains existing native value")
near(ordinary.critical_damage_pct, 2000, "production monkey W is 20x")
for _, amount in ipairs({ 1e12, 9e15 }) do
    local current = debug_attack(amount)
    near(current.attack_min, amount, "debug logical attack minimum")
    near(current.attack_max, amount, "debug logical attack maximum")
    check_native(first, "debug " .. tostring(amount))
end
debug_attack(0)
local zero, native_zero = check_native(first, "zero debug override")
near(zero.attack_max, 0, "zero logical override")
near(native_zero, 0, "zero override cancels separately owned equipment flat")
local reset = bus.request(events.HERO_COMBAT_STATS_DEBUG_ATTACK_REQUEST, { player_id = 0, reset = true })
assert(reset and reset.ok)
check_native(first, "reset ordinary")
near(stats(0).native_attack_scale, 1, "reset lowers attack scale")

-- Malformed console values must not replace a valid combat snapshot, mutate
-- the projection or trigger native writes.
local function copy_counts(hero)
    local copied = {}
    for key, value in pairs(counts[hero]) do copied[key] = value end
    return copied
end
local invalid_numbers = { 0 / 0, math.huge, -math.huge }
for _, invalid in ipairs(invalid_numbers) do
    for _, field in ipairs({ "attack", "attack_delta", "attack_speed" }) do
        local before, snapshot_before = copy_counts(first), stats(0)
        local response = bus.request(events.HERO_COMBAT_STATS_DEBUG_ATTACK_REQUEST,
            { player_id = 0, [field] = invalid })
        assert(response and response.ok == false, "invalid " .. field .. " accepted")
        assert(stats(0) == snapshot_before, "invalid " .. field .. " replaced snapshot")
        for key, value in pairs(counts[first]) do
            assert(value == before[key], "invalid " .. field .. " caused native write: " .. key)
        end
    end
end
local probe = {}
local ordinary_fractional = projection.prepare_attack_components({}, 10.2, 20.8, 3.1, 4.2, 5.3, 20)
near(ordinary_fractional.scale, 1, "ordinary fractional base remains unscaled")
near(ordinary_fractional.minimum, 10, "ordinary minimum retains native integer truncation")
near(ordinary_fractional.maximum, 20, "ordinary maximum retains native integer truncation")
near(ordinary_fractional.weapon, 3.1, "ordinary weapon gets no new midpoint compensation")
near(ordinary_fractional.research, 4.2, "ordinary research bonus remains unchanged")
near(ordinary_fractional.equipment, 5.3, "ordinary equipment bonus remains unchanged")
near((ordinary_fractional.minimum + ordinary_fractional.maximum) * 0.5
    + ordinary_fractional.weapon + ordinary_fractional.research + ordinary_fractional.equipment,
    27.6, "ordinary average retains the existing native damage semantics")
local clone_minimum, clone_maximum = projection.prepare_attack(probe, 9e15, 9e15, 30)
near(clone_minimum, math.floor(1e8 / 30), "clone native capacity is an exact integer")
near(clone_maximum, math.floor(1e8 / 30), "clone maximum honors integer critical capacity")
assert(clone_maximum * 30 <= 1e8, "clone 30x critical crosses native capacity")
local ranged = projection.prepare_attack_components({}, 1234, 1456, 9e8, 33, 137, 20)
assert(ranged.minimum == math.floor(ranged.minimum)
    and ranged.maximum == math.floor(ranged.maximum), "native base range uses integer setters")
local ranged_bonus = ranged.weapon + ranged.research + ranged.equipment
near(((ranged.minimum + ranged.maximum) * 0.5 + ranged_bonus) * ranged.scale,
    (1234 + 1456) * 0.5 + 9e8 + 33 + 137, "base range midpoint compensation preserves average")
assert(math.abs((ranged.minimum + ranged_bonus) * ranged.scale - (1234 + 9e8 + 33 + 137))
        <= ranged.scale + 1e-6
    and math.abs((ranged.maximum + ranged_bonus) * ranged.scale - (1456 + 9e8 + 33 + 137))
        <= ranged.scale + 1e-6, "native base endpoint error is bounded by one scaled unit")
assert((ranged.maximum + ranged_bonus) * 20 <= 1e8,
    "midpoint rounding must not cross post-critical native capacity")

growth[0] = { growth_attack = 1e12 }
bus.emit(events.WEAPON_GROWTH_CHANGED, { player_id = 0, snapshot = growth[0] })
near(check_native(first, "weapon growth").attack_min, 1e12 + 745, "weapon logical growth stays unscaled")
progression[0] = { attack_flat = 2e11, all_attributes = 30 }
bus.emit(events.HERO_PROGRESSION_CHANGED, { player_id = 0, changed_section = "hero" })
near(check_native(first, "progression growth").attack_min, 1.2e12 + 748, "progression logical growth stays unscaled")
technology[0] = { attack_flat = 3e11, attack_bonus_pct = 35, critical_chance_pct = 100 }
bus.emit(events.TECHNOLOGY_STATS_CHANGED, { player_id = 0, changed_section = "hero" })
near(check_native(first, "research growth").attack_min, (1.5e12 + 748) * 1.35,
    "research flat and panel percentage remain logical")
equipment_stats[0].attack_flat = 4e11
bus.emit(events.WEAPON_EQUIPPED_CHANGED, { player_id = 0, slot = "ring", reason = "ring_attack_change" })
near(check_native(first, "equipment growth").attack_min, (1.9e12 + 611) * 1.35,
    "equipment independent attack contributes once before percentage")
debug_attack(0)
local cancelled = check_native(first, "zero override with huge equipment")
near(cancelled.attack_max, 0, "large independently owned equipment cancels exactly")
local cancelled_reset = bus.request(events.HERO_COMBAT_STATS_DEBUG_ATTACK_REQUEST,
    { player_id = 0, reset = true })
assert(cancelled_reset and cancelled_reset.ok)
check_native(first, "reset huge equipment")
equipment[0] = { main_hand_content_id = "weapon_legend_abyss_01", main_hand_name = "Abyss" }
bus.emit(events.WEAPON_EQUIPPED_CHANGED, { player_id = 0, slot = "main_hand", reason = "weapon_replacement" })
local replaced = check_native(first, "weapon replacement")
assert(replaced.weapon_content_id == "weapon_legend_abyss_01", "replacement is authoritative")
near(replaced.attack_min, (1.9e12 + 705611) * 1.35, "replacement weapon/attributes stay logical")

local config = require("combat/damage_rule_config")
local repository = require("combat/damage_transaction_repository")
local filter = require("combat/damage_filter_service")
repository.init(config)
filter.init({ event_bus = bus, events = damage_events, repository = repository, config = config })
local last_logical, last_resolved
bus.subscribe(damage_events.DAMAGE_FILTERED, function(payload) last_logical = payload.final_damage end)
bus.subscribe(damage_events.DAMAGE_RESOLVED, function(payload) last_resolved = payload.final_damage end)
local victim = unit(201, nil)
victim.team, victim.maximum, victim.health = 3, 1000, 1000
local function filtered_hit(native_damage, expected_logical, category, inflictor, damage_type)
    local keys = { entindex_attacker_const = first:entindex(), entindex_victim_const = victim:entindex(),
        entindex_inflictor_const = inflictor, damage_category_const = category,
        damagetype_const = damage_type or DAMAGE_TYPE_PURE, damage = native_damage }
    assert(filter._filter_for_test(filter, keys), "production filter blocked the hit")
    near(last_logical, expected_logical, "filter logical damage restored exactly once")
    near(last_resolved, expected_logical, "resolved transaction keeps final logical damage")
    assert(keys.damage >= 0 and keys.damage < math.huge, "filter passed invalid native damage")
    return keys.damage, keys
end
local current, native = check_native(first, "final projected attack")
filtered_hit(native, native * current.native_attack_scale, DOTA_DAMAGE_CATEGORY_ATTACK, nil)
local modifier = first.modifiers.modifier_weapon_stat_projection
modifier:OnAttackRecord({ attacker = first, record = 77 })
local critical_factor = 1 + modifier:GetModifierDamageOutgoing_Percentage() / 100
near(critical_factor, 20, "real critical modifier applies monkey W")
filtered_hit(native * critical_factor, native * current.native_attack_scale * critical_factor,
    DOTA_DAMAGE_CATEGORY_ATTACK, nil)
near(modifier:GetModifierDamageOutgoing_Percentage(), 0, "critical state cannot amplify a subsequent proc")
filtered_hit(12345, 12345, DOTA_DAMAGE_CATEGORY_SPELL, 999)
filtered_hit(6789, 6789, DOTA_DAMAGE_CATEGORY_SPELL, nil)
filtered_hit(6789, 6789, "0", nil)

-- The physical monster route must restore the hero's 20x hit before applying
-- authored War3 armor, then publish that logical damage before HP projection.
local armor = require("config/armor_balance")
victim.survival_monster_corpse, victim.survival_is_wave_monster = true, true
victim.survival_armor_mapping_version = armor.CUSTOM_WAR3_MAPPING_VERSION
victim.survival_effective_war3_armor = 512
local logical_critical = ((current.engine_attack_min + current.engine_attack_max) * 0.5
    + current.engine_equipment_attack_bonus) * critical_factor
local after_armor = logical_critical / 11.24
local ordinary_physical, ordinary_keys = filtered_hit(native * critical_factor, after_armor,
    DOTA_DAMAGE_CATEGORY_ATTACK, nil, DAMAGE_TYPE_PHYSICAL)
near(ordinary_physical, after_armor, "ordinary wave monster receives armored logical native damage")
assert(ordinary_keys.damage_flags == DOTA_DAMAGE_FLAG_IGNORES_PHYSICAL_ARMOR,
    "custom War3 armor must prevent another native physical-armor reduction")
local projected_victim = projection.prepare(victim, { health = 1e20, attack = 1 })
victim.maximum, victim.health = projected_victim.health, projected_victim.health
local output_damage = filtered_hit(native * critical_factor,
    native * current.native_attack_scale * critical_factor, DOTA_DAMAGE_CATEGORY_ATTACK, nil)
near(output_damage, last_logical / victim.survival_endless_health_scale,
    "victim health projection converts restored logical damage once")
local projected_physical, projected_keys = filtered_hit(native * critical_factor, after_armor,
    DOTA_DAMAGE_CATEGORY_ATTACK, nil, DAMAGE_TYPE_PHYSICAL)
near(projected_physical, after_armor / victim.survival_endless_health_scale,
    "endless monster HP projection follows the custom armor calculation")
assert(projected_keys.damage_flags == DOTA_DAMAGE_FLAG_IGNORES_PHYSICAL_ARMOR,
    "scaled physical damage keeps the custom armor engine flag")

-- Invalid raw/native scales cannot publish a misleading resolved transaction.
local function invalid_filter(amount, attack_scale, health_scale)
    local before = last_logical
    local old_attack, old_health = first.survival_endless_attack_scale, victim.survival_endless_health_scale
    first.survival_endless_attack_scale, victim.survival_endless_health_scale = attack_scale, health_scale
    local keys = { entindex_attacker_const = first:entindex(), entindex_victim_const = victim:entindex(),
        damage_category_const = DOTA_DAMAGE_CATEGORY_ATTACK, damagetype_const = DAMAGE_TYPE_PURE,
        damage = amount }
    local allowed = filter._filter_for_test(filter, keys)
    first.survival_endless_attack_scale, victim.survival_endless_health_scale = old_attack, old_health
    assert(allowed == false and last_logical == before, "invalid filter input emitted resolved damage")
end
for _, invalid in ipairs(invalid_numbers) do
    invalid_filter(invalid, current.native_attack_scale, victim.survival_endless_health_scale)
    invalid_filter(native, invalid, victim.survival_endless_health_scale)
    invalid_filter(native, current.native_attack_scale, invalid)
end
invalid_filter(native, 0, victim.survival_endless_health_scale)
invalid_filter(native, current.native_attack_scale, 0)
owner_unchanged()
output("HERO_LARGE_ATTACK_PROJECTION_PASS production hero/modifiers/filter; ordinary/fractional, 1e12, 9e15, 20x, 512 War3 armor, all growth sources, replacement/reset, client values and missing HP")
