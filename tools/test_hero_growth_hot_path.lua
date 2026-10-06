-- Production stat service, adapter, health guard, scheduler, bus and math.
-- Only unrelated bootstrap/config and the native entity/modifier boundary are mocked.
package.path = "scripts/vscripts/?.lua;" .. package.path
for _, name in ipairs({ "systems/effect_handler_registry", "systems/equipment_effect_service",
    "systems/equipment_stat_aggregation_service", "systems/triggered_proc_service" }) do
    package.loaded[name] = { init = function() end }
end
local rules = { hero_strength_health_per_point = 0, hero_intellect_attack_per_point = 0,
    number = function(_, fallback) return fallback end }
package.loaded["config/global_rules"] = rules
local definition = { hero_id = "growth_test", unit_name = "npc_growth_test", attack_speed = 2,
    base_damage_min = 112, base_damage_max = 120, base_health = 1000,
    base_strength = 10, base_agility = 20, base_intellect = 30, attack_range = 800 }
package.loaded["config/generated/hero_definitions"] = { by_id = { growth_test = definition } }
package.loaded["config/generated/weapon_definitions"] = { by_id = {
    growing = { base_attack_min = 50, base_attack_max = 60,
        base_strength = 1, base_agility = 2, base_intellect = 3 },
    replacement = { base_attack_min = 80, base_attack_max = 100,
        base_strength = 4, base_agility = 5, base_intellect = 6 },
} }
package.loaded["config/generated/hero_attack_projectiles"] = { by_id = {
    growth_test = { attack_capability = "ranged", projectile_speed = 900,
        projectile_model = "particles/test_projectile.vpcf" },
} }
local technology, equipment, growth = {}, {}, {}
package.loaded["systems/technology_stat_manager"] = {
    get = function(id) return { final = { hero = technology[id] or {} } } end,
}
local logs = {}
package.loaded["core/logger"] = { info = function(category)
    logs[category] = (logs[category] or 0) + 1
end, warn = function() end }
DOTA_UNIT_CAP_RANGED_ATTACK, DOTA_UNIT_CAP_MELEE_ATTACK = 2, 1
local now = 0
GameRules = { GetGameTime = function() return now end }
local bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")
local health_guard = require("core/hero_health_guard")
local counts, publications, growth_reads = {}, {}, {}
local function count(unit, key)
    local c = counts[unit]
    c[key] = (c[key] or 0) + 1
end
local function near(actual, expected, label)
    assert(type(actual) == "number" and math.abs(actual - expected) < 1e-7,
        (label or "number") .. ": " .. tostring(actual) .. " != " .. tostring(expected))
end
local function snapshot(id)
    local result, err = bus.request(events.HERO_COMBAT_STATS_GET_REQUEST, { player_id = id })
    assert(result and result.ok, tostring(err or result and result.error))
    return result.snapshot
end
local function unit(id, player_id)
    local u = { id = id, player_id = player_id, modifiers = {}, health = 230,
        maximum = 300, native_health = 300, bat = 0.5, damage_min = 112, damage_max = 120,
        projectile_speed = 300, refill_on_calculate = true }
    counts[u] = {}
    function u:IsNull() return self.null == true end
    function u:IsAlive() return not self.null and not self.dead end
    function u:entindex() return self.id end
    function u:GetLevel() return 1 end
    function u:GetUnitName() return "npc_growth_test" end
    function u:GetHealth() return self.health end
    function u:GetMaxHealth() return self.maximum end
    function u:SetHealth(value) count(self, "health"); self.health = value end
    function u:GetBaseAttackTime() return self.bat end
    function u:SetBaseAttackTime(value)
        count(self, "bat")
        if self.fail_next_bat then self.fail_next_bat = nil; return false end
        self.bat = value
    end
    function u:GetBaseDamageMin() return self.damage_min end
    function u:GetBaseDamageMax() return self.damage_max end
    function u:SetBaseDamageMin(value) count(self, "damage_min"); self.damage_min = value end
    function u:SetBaseDamageMax(value) count(self, "damage_max"); self.damage_max = value end
    function u:SetBaseStrength() count(self, "strength_zero") end
    function u:SetBaseAgility() count(self, "agility_zero") end
    function u:SetBaseIntellect() count(self, "intellect_zero") end
    function u:Script_SetAttackRange(value) count(self, "range"); self.range = value end
    function u:SetAcquisitionRange(value) count(self, "acquisition"); self.acquisition = value end
    function u:GetAttackRange() return self.range or 150 end
    function u:GetAttackSpeed() return 100 end
    function u:GetPhysicalArmorValue() return 0 end
    function u:GetMoveCapability() return 1 end
    function u:GetAttackCapability() return self.capability end
    function u:SetAttackCapability(value) count(self, "capability"); self.capability = value end
    function u:SetRangedProjectileName(value) count(self, "projectile_name"); self.projectile = value end
    function u:GetProjectileSpeed()
        local modifier = self.modifiers.modifier_survival_hero_projectile_speed
        return self.projectile_speed + (modifier and modifier.stack or 0)
    end
    function u:SetProjectileSpeed(value) count(self, "projectile_speed"); self.projectile_speed = value end
    function u:FindModifierByName(name) return self.modifiers[name] end
    function u:HasModifier(name) return self.modifiers[name] ~= nil end
    function u:RemoveModifierByName(name) self.modifiers[name] = nil end
    function u:CalculateStatBonus()
        count(self, "calculate")
        local bonus = self.modifiers.modifier_survival_hero_base_health
        self.maximum = self.native_health + (bonus and bonus.stack or 0)
        -- Simulate the reported native stat-recalculation refill. The real
        -- adapter and health guard must preserve missing HP despite this.
        if self.refill_on_calculate then self.health = self.maximum end
    end
    function u:AddNewModifier(_, _, name, params)
        count(self, "modifier_add:" .. name)
        local m = { stack = 0 }
        function m:GetStackCount() return self.stack end
        function m:SetHealthBonus(value) count(u, "health_bonus"); self.stack = value end
        function m:SetStackCount(value) count(u, "stack:" .. name); self.stack = value end
        function m:SetProjectileSpeedBonus(value) count(u, "projectile_bonus"); self.stack = value end
        function m:SetAttackRange(value) count(u, "range_modifier"); self.range = value end
        function m:SetTechnologyValues(...) count(u, "technology"); self.values = { ... } end
        function m:ForceRefresh()
            if name == "modifier_weapon_stat_projection" then
                count(u, "weapon_refresh")
                self.snapshot = snapshot(u.player_id) -- Real modifier's recursive request contract.
            elseif name == "modifier_equipment_effects" then
                count(u, "equipment_refresh")
            end
        end
        self.modifiers[name] = m
        if params and params.health_bonus then m:SetHealthBonus(params.health_bonus) end
        if params and params.projectile_speed_bonus then m:SetProjectileSpeedBonus(params.projectile_speed_bonus) end
        return m
    end
    -- The primary hero adapter normally installs this before HERO_SUMMONED.
    u:AddNewModifier(u, nil, "modifier_survival_hero_attack_range", {})
    return u
end
package.loaded["core/modifier_registry"] = { ensure = function(u, name, params)
    return u:FindModifierByName(name) or u:AddNewModifier(u, nil, name, params)
end }
local print_original = print
print = function(message)
    if tostring(message):find("%[EventBus%] handler error")
        or tostring(message):find("%[Scheduler%] task failed") then error(message) end
end
local service = require("systems/hero_combat_stat_service")
service.init()
bus.handle_request(events.WEAPON_EQUIPMENT_GET_REQUEST, function(payload)
    return { ok = true, snapshot = equipment[payload.player_id] or {} }
end)
bus.handle_request(events.WEAPON_GROWTH_GET_REQUEST, function(payload)
    local id = payload.player_id
    growth_reads[id] = (growth_reads[id] or 0) + 1
    return { ok = true, snapshot = growth[id] or {} }
end)
bus.handle_request(events.EQUIPMENT_STATS_GET_REQUEST, function()
    return { ok = true, snapshot = { values = {} } }
end)
bus.subscribe(events.HERO_COMBAT_STATS_CHANGED, function(payload)
    local id = payload.player_id
    publications[id] = (publications[id] or 0) + 1
end)
local function summon(id, player_id)
    equipment[player_id] = equipment[player_id] or { main_hand_content_id = "growing", main_hand_name = "Growing" }
    growth[player_id] = growth[player_id] or {}
    local hero = unit(id, player_id)
    bus.emit(events.HERO_SUMMONED, { player_id = player_id, hero_id = "growth_test", unit = hero })
    near(hero.maximum, 1000, "real health adapter at birth")
    return hero
end
local function copy_counts(hero)
    local copy = {}
    for key, value in pairs(counts[hero]) do copy[key] = value end
    return copy
end
local function delta(hero, before, key) return (counts[hero][key] or 0) - (before[key] or 0) end
local stable_native = { "equipment_refresh", "projectile_name", "projectile_speed", "projectile_bonus",
    "capability", "bat", "range", "acquisition", "range_modifier",
    "strength_zero", "agility_zero", "intellect_zero", "damage_min", "damage_max", "technology",
    "health_bonus", "calculate", "health" }
local first, second = summon(101, 0), summon(102, 1)
first.health, second.health = 600, 700
scheduler.clear()
local before, other_before = copy_counts(first), copy_counts(second)
local reads, other_publications, projectile_logs = growth_reads[0], publications[1], logs.HeroProjectile
local other_snapshot = snapshot(1)
for index = 1, 100 do
    growth[0] = { growth_attack = index * 3, growth_strength = index,
        growth_agility = index * 2, growth_intellect = index * 4, stage_attack_count = index }
    bus.emit(events.WEAPON_GROWTH_CHANGED, { player_id = 0, snapshot = growth[0], reason = "attack_growth" })
    local current = snapshot(0)
    near(current.attack_min, 162 + index * 3, "immediate logical attack")
    near(current.attack_max, 180 + index * 3, "immediate upper attack")
    near(current.strength, 11 + index, "immediate strength")
    near(current.agility, 22 + index * 2, "immediate agility")
    near(current.intellect, 33 + index * 4, "immediate intellect")
    near(first.modifiers.modifier_weapon_stat_projection.snapshot.engine_weapon_attack_bonus,
        55 + index * 3, "native projection reads the newly committed snapshot")
end
for _, key in ipairs(stable_native) do
    assert(delta(first, before, key) == 0, "growth must not rewrite stable native field: " .. key)
end
assert(delta(first, before, "weapon_refresh") == 100, "changed attack projection must refresh exactly once per growth")
assert(growth_reads[0] == reads, "committed growth payload must avoid a redundant growth GET")
assert(logs.HeroProjectile == projectile_logs, "real projectile adapter must not rerun or log on attack growth")
assert(publications[1] == other_publications and snapshot(1) == other_snapshot, "other player snapshot stays untouched")
for key, value in pairs(counts[second]) do assert(value == other_before[key], "other player's native state mutated") end
near(first.health, 600, "attack and logical attributes must not heal")
assert(scheduler.task_count() == 2, "one hundred growth refreshes retain only the latest two guard jobs")

-- Counter changes are visible to the UI but affect no native combat property.
scheduler.clear()
before = copy_counts(first)
local publications_before = publications[0]
for index = 101, 200 do
    growth[0].stage_attack_count = index
    bus.emit(events.WEAPON_GROWTH_CHANGED, { player_id = 0, snapshot = growth[0], reason = "stage_progress" })
end
near(snapshot(0).stage_attack_count, 200, "counter-only events still publish UI progress")
assert(publications[0] == publications_before + 100)
for _, key in ipairs(stable_native) do assert(delta(first, before, key) == 0, "counter-only native write: " .. key) end
assert(delta(first, before, "weapon_refresh") == 0 and scheduler.task_count() == 0,
    "counter-only events must not refresh native projection or schedule health guards")
publications_before = publications[0]
for _ = 1, 100 do bus.emit(events.WEAPON_GROWTH_CHANGED, { player_id = 0, snapshot = growth[0] }) end
assert(publications[0] == publications_before, "identical counters must not republish snapshots")

-- Real gear and technology changes still invalidate their required projections.
before = copy_counts(first)
equipment[0] = { main_hand_content_id = "replacement", main_hand_name = "Replacement" }
bus.emit(events.WEAPON_EQUIPPED_CHANGED, { player_id = 0, slot = "main_hand", content_id = "replacement" })
assert(delta(first, before, "equipment_refresh") == 1 and delta(first, before, "projectile_name") == 1,
    "actual equipment changes still run equipment and native projectile setup")
near(snapshot(0).attack_min, 492, "actual replacement weapon data")
near(first.health, 600, "real equipment recalculation preserves missing health")
before = copy_counts(first)
technology[0] = { attack_bonus_pct = 20, attack_speed_bonus_pct = 25 }
bus.emit(events.TECHNOLOGY_STATS_CHANGED, { player_id = 0, changed_section = "hero" })
near(snapshot(0).attack_min, 492 * 1.2, "effective technology attack change")
near(snapshot(0).attack_speed, 2.5, "effective technology attack speed")
assert(delta(first, before, "technology") == 1 and delta(first, before, "bat") == 1
    and delta(first, before, "weapon_refresh") == 1)
near(first.health, 600, "technology changes cannot refill health")
before = copy_counts(first)
first.fail_next_bat = true
technology[0].attack_speed_bonus_pct = 50
bus.emit(events.TECHNOLOGY_STATS_CHANGED, { player_id = 0, changed_section = "hero" })
near(first.bat, 0.4, "a native setter can explicitly reject a projection")
bus.emit(events.TECHNOLOGY_STATS_CHANGED, { player_id = 0, changed_section = "hero" })
near(first.bat, 1 / 3, "failed setter must retry when the effective value remains unchanged")
assert(delta(first, before, "bat") == 2, "the failed write cannot be cached as successfully applied")
bus.emit(events.TECHNOLOGY_STATS_CHANGED, { player_id = 0, changed_section = "hero" })
assert(delta(first, before, "bat") == 2, "successful retry restores stable-write suppression")

-- Attribute conversions do require native damage/health updates. The real
-- health adapter must preserve the same missing HP, not refill on Calculate.
rules.hero_strength_health_per_point, rules.hero_intellect_attack_per_point = 2, 3
before = copy_counts(first)
local missing = first.maximum - first.health
bus.emit(events.WEAPON_GROWTH_CHANGED, { player_id = 0, snapshot = growth[0] })
local converted = snapshot(0)
near(converted.strength, 114)
near(converted.intellect, 436)
near(converted.attribute_health_bonus, 228)
near(converted.attribute_attack_bonus, 1308)
near(first.maximum, 1228)
near(first.maximum - first.health, missing, "health conversion must preserve damage already taken")
assert(delta(first, before, "health_bonus") == 1 and delta(first, before, "damage_min") == 1
    and delta(first, before, "damage_max") == 1)
before = copy_counts(first)
bus.emit(events.WEAPON_GROWTH_CHANGED, { player_id = 0, snapshot = growth[0] })
assert(delta(first, before, "calculate") == 0 and delta(first, before, "health_bonus") == 0
    and delta(first, before, "health") == 0, "unchanged real health projection must not recalculate or heal")

-- Deletion drops projection caches; even a new handle reusing its entity
-- index must receive all initialization writes. Old events cannot delete it.
first.null = true
bus.emit(events.HERO_REMOVED, { player_id = 0, unit = first })
assert(not bus.request(events.HERO_COMBAT_STATS_GET_REQUEST, { player_id = 0 }).ok)
rules.hero_strength_health_per_point, rules.hero_intellect_attack_per_point = 0, 0
local replacement = summon(101, 0)
assert(replacement ~= first and counts[replacement].strength_zero == 1
    and counts[replacement].agility_zero == 1 and counts[replacement].intellect_zero == 1
    and counts[replacement].bat == 1 and counts[replacement].range == 1,
    "new entity identity cannot reuse old native projection caches")
bus.emit(events.HERO_REMOVED, { player_id = 0, unit = first })
assert(snapshot(0).entindex == replacement.id and snapshot(1) == other_snapshot)

-- Use the real scheduler to verify bounded pending callbacks, current-value
-- precedence, intentional healing, player separation and reused entindexes.
scheduler.clear()
local guarded = unit(900, 2)
guarded.maximum, guarded.health = 1000, 400
for _ = 1, 1000 do health_guard.protect_value(guarded, 400, "burst") end
assert(scheduler.task_count() == 2 and not counts[guarded].health,
    "1000 stable protects must leave two tasks and perform no health writes")
guarded.health = 1000
scheduler.think()
near(guarded.health, 400, "latest immediate guard restores a native refill")
guarded.health = 1000
now = now + 0.12
scheduler.think()
near(guarded.health, 400, "latest delayed guard restores a late native refill")
assert(scheduler.task_count() == 0)
health_guard.protect_value(guarded, 400, "before_intentional_heal")
health_guard.allow_healing(guarded)
guarded.health = 1000
now = now + 0.2
scheduler.think()
near(guarded.health, 1000, "intentional healing invalidates both former guard generations")
guarded.health = 500
health_guard.protect_value(guarded, 500, "newer_value")
local other_guard = unit(901, 3)
other_guard.maximum, other_guard.health = 1000, 700
for _ = 1, 1000 do health_guard.protect_value(other_guard, 700, "other_player") end
assert(scheduler.task_count() == 4, "two identities have independent bounded guard jobs")
guarded.health, other_guard.health = 1000, 1000
now = now + 0.2
scheduler.think()
near(guarded.health, 500); near(other_guard.health, 700)
health_guard.protect_value(guarded, 500, "old_entity")
guarded.null = true
local reused = unit(900, 2)
reused.maximum, reused.health = 1000, 800
health_guard.protect_value(reused, 800, "new_entity")
assert(scheduler.task_count() == 4, "reused native index cannot alias another handle's guard tasks")
reused.health = 1000
now = now + 0.2
scheduler.think()
near(reused.health, 800, "old entity guard cannot alter new handle with reused index")
assert(scheduler.task_count() == 0)
print = print_original
print("HERO_GROWTH_HOT_PATH_PASS 100 growth: equip/projectile/BAT/range/native-attribute rewrites=0, projection refresh=100; 100 counter-only: all native writes=0; exact stats, real adapter HP, gear/technology, players and identity")
print("HERO_HEALTH_GUARD_BOUNDED_PASS 1000 protects=2 real scheduler tasks; native refill, intentional healing generations, two players and reused identity")
