-- Run the real summon stat projection, multi-arrow dispatch and damage filter.
-- Native entity setters deliberately reject values outside their signed range.
package.path = "scripts/vscripts/?.lua;" .. package.path
package.loaded["core/scheduler"] = {}
package.loaded["core/sound_service"] = { play = function() end }
package.loaded["systems/hero_cosmetic_service"] = {}
package.loaded["systems/keeper_blinding_light_visual"] = {}
package.loaded["systems/anti_air_rules"] = {
    can_attack = function() return true end,
    has_damage_taken_aura = function() return false end,
}

DAMAGE_TYPE_PHYSICAL, DAMAGE_TYPE_MAGICAL = 1, 2
DOTA_DAMAGE_CATEGORY_ATTACK, DOTA_DAMAGE_CATEGORY_SPELL = 1, 2
DOTA_DAMAGE_FLAG_IGNORES_PHYSICAL_ARMOR = 512
DOTA_UNIT_TARGET_TEAM_ENEMY, DOTA_UNIT_TARGET_HERO, DOTA_UNIT_TARGET_BASIC = 2, 4, 8
DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES, FIND_CLOSEST = 16, 0

local exclusive = require("systems/hero_exclusive_passive_service")
local filter = require("combat/damage_filter_service")
local projection = require("combat/endless_stat_projection")
local definitions = require("config/hero_passive_skill_definitions").by_id
local entities, emitted = {}, {}
local function near(actual, expected, label)
    assert(type(actual) == "number" and actual == actual
        and math.abs(actual - expected) <= math.max(1e-7, math.abs(expected) * 1e-12),
        label .. ": " .. tostring(actual) .. " != " .. tostring(expected))
end
local function bounded(value)
    assert(value > 0 and value < 2147483647 and value == math.floor(value),
        "native integer setters must only receive safe positive values: " .. tostring(value))
end
local function unit(index, name)
    local result = { index = index, name = name, health = 100, maximum = 100,
        modifiers = {}, secondary_hits = {} }
    function result:IsNull() return false end
    function result:IsAlive() return true end
    function result:entindex() return self.index end
    function result:GetUnitName() return self.name end
    function result:GetAbsOrigin() return { x = self.index * 10, y = 0, z = 0 } end
    function result:GetTeamNumber() return self.index == 1 and 2 or 3 end
    function result:HasModifier(name) return self.modifiers[name] ~= nil end
    function result:FindModifierByName(name) return self.modifiers[name] end
    function result:AddNewModifier(_, _, name, params)
        local modifier = { interval = params.attack_interval }
        function modifier:SetAttackInterval(value) self.interval = value end
        self.modifiers[name] = modifier
        return modifier
    end
    function result:SetBaseDamageMin(value) bounded(value); self.attack_min = value end
    function result:SetBaseDamageMax(value) bounded(value); self.attack_max = value end
    function result:SetBaseAttackTime(value) self.attack_time = value end
    function result:SetPhysicalArmorBaseValue(value) self.armor = value end
    function result:SetBaseMaxHealth(value) bounded(value); self.maximum = value end
    function result:SetMaxHealth(value) bounded(value); self.maximum = value end
    function result:GetMaxHealth() return self.maximum end
    function result:GetHealth() return self.health end
    function result:SetHealth(value) bounded(value); self.health = value end
    entities[index] = result
    return result
end

EntIndexToHScript = function(index) return entities[index] end
filter.init({
    event_bus = { emit = function(name, payload)
        if name == "resolved" then emitted[#emitted + 1] = payload end
    end },
    events = { DAMAGE_BLOCKED = "blocked", DAMAGE_FILTERED = "filtered", DAMAGE_RESOLVED = "resolved" },
    repository = { consume_pending = function() return nil end },
    config = { global_post_bonus_pct = 0, minimum_post_multiplier = 0,
        boss_rules = { enabled = false } },
})

local summon = unit(1, "npc_survival_drow_companion")
local primary = unit(2, "npc_target")
local candidates = { primary, unit(3, "npc_target"), unit(4, "npc_target"),
    unit(5, "npc_target"), unit(6, "npc_target"), unit(7, "npc_target") }
FindUnitsInRadius = function() return candidates end
local function hit(target, damage, category, inflictor, damage_type)
    local keys = { entindex_attacker_const = 1, entindex_victim_const = target.index,
        damage = damage, damage_category_const = category,
        entindex_inflictor_const = inflictor, damagetype_const = damage_type or DAMAGE_TYPE_PHYSICAL }
    assert(filter._filter_for_test(nil, keys), "unblocked summon damage must be accepted")
    return keys.damage, emitted[#emitted].final_damage
end
function summon:PerformAttack(target, orb, procs, skip_cooldown, ignore_invis,
        use_projectile, fake, never_miss)
    assert(orb == false and procs == false and skip_cooldown == true
        and ignore_invis == false and use_projectile == true
        and fake == false and never_miss == false)
    assert(self.survival_next_drow_secondary == true,
        "secondary arrows must retain the recursion guard")
    local damage = hit(target, self.attack_max, DOTA_DAMAGE_CATEGORY_ATTACK)
    self.secondary_hits[#self.secondary_hits + 1] = damage
end

for _, logical_attack in ipairs({ 11110000000, 9000000000000000 }) do
    for _, definition in ipairs({ definitions.skill_drow_companion, definitions.skill_doom_infernal }) do
        assert(exclusive._test.apply_combat_stats(summon, {
            attack_min = logical_attack / 2, attack_max = logical_attack,
            attack_speed = 10, max_health = 30000000000, runtime_armor = 0,
            strength = 19000, agility = 20000, intellect = 21000,
        }, definition, 1, false))
        assert(summon.attack_min > 0 and summon.attack_max <= 100000000)
        assert(summon.maximum <= 100000000)
        near(summon.survival_exclusive_stat_snapshot.attack_max, logical_attack,
            "HUD retains logical attack")
        near(summon.survival_exclusive_stat_snapshot.strength, 19000,
            "logical attributes remain separate from native attributes")
        near(hit(primary, summon.attack_min, DOTA_DAMAGE_CATEGORY_ATTACK), logical_attack / 2,
            "minimum native attack restores once")
        near(hit(primary, summon.attack_max, DOTA_DAMAGE_CATEGORY_ATTACK), logical_attack,
            "maximum native attack restores once")
        near(hit(primary, summon.attack_max), logical_attack,
            "omitted native category restores once")
        near(hit(primary, summon.attack_max, 0, -1), logical_attack,
            "zero native category and missing inflictor restores once")
        near(hit(primary, 750, DOTA_DAMAGE_CATEGORY_SPELL, nil, DAMAGE_TYPE_MAGICAL), 750,
            "spell-category damage must not multiply by native attack scale")
        near(hit(primary, 750, nil, 999, DAMAGE_TYPE_PHYSICAL), 750,
            "ability inflictor must not multiply by native attack scale")
    end

    summon.survival_drow_companion = true
    summon.survival_drow_max_targets = 5
    summon.survival_drow_attack_range = 1200
    summon.secondary_hits = {}
    assert(exclusive.on_drow_companion_attack_fired(summon, primary))
    assert(#summon.secondary_hits == 4, "a volley has one primary and four secondary arrows")
    for _, damage in ipairs(summon.secondary_hits) do
        near(damage, logical_attack, "each native secondary restores exactly once")
    end
    assert(summon.survival_next_drow_secondary == nil)

    projection.prepare(primary, { attack = 1, health = 1000000000000 })
    local native_damage, logical_damage = hit(primary, summon.attack_max, DOTA_DAMAGE_CATEGORY_ATTACK)
    near(logical_damage, logical_attack, "damage telemetry retains logical damage")
    near(native_damage, logical_attack / primary.survival_endless_health_scale,
        "target health scaling is applied after logical attack restoration")
    near(hit(primary, 750, DOTA_DAMAGE_CATEGORY_SPELL),
        750 / primary.survival_endless_health_scale, "spell receives only target health scaling")
    primary.survival_endless_health_scale = nil
end

-- Returning below the native cap clears the old scale; future hits cannot keep
-- using the previous huge-damage multiplier.
exclusive._test.apply_combat_stats(summon, {
    attack_min = 112, attack_max = 120, attack_speed = 1.4, max_health = 99000,
}, definitions.skill_drow_companion, 1, false)
near(summon.survival_endless_attack_scale, 1, "low attack clears old scale")
near(summon.survival_endless_health_scale, 1, "low health clears old scale")
near(hit(primary, summon.attack_max, DOTA_DAMAGE_CATEGORY_ATTACK), 120,
    "normal attack is restored after huge attack inheritance ends")
print("EXCLUSIVE_SUMMON_DAMAGE_PROJECTION_PASS huge attack/health, native and secondary attacks, spell isolation, target scaling and reset")
