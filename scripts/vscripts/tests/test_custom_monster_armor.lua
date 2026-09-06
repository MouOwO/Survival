package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path

DAMAGE_TYPE_PHYSICAL = 1
DAMAGE_TYPE_MAGICAL = 2
DOTA_DAMAGE_FLAG_IGNORES_PHYSICAL_ARMOR = 512

package.loaded["config/generated/global_rules"] = {
    by_id = { runtime_detailed_diagnostics = { value = 0, enabled = true } },
}
package.loaded["systems/tree_damage_rules"] = {
    is_tree = function() return false end,
    is_arrow_tower = function() return false end,
    is_basic_attack_category = function() return false end,
    consume_basic_attack = function() return false end,
    allows_damage = function() return true end,
    reset_pending_attacks = function() end,
}
package.loaded["systems/anti_air_rules"] = {
    can_attack = function() return true end,
    has_damage_taken_aura = function() return false end,
}

local armor_balance = require("config/armor_balance")
local filter_service = require("combat/damage_filter_service")

local entities = {}
EntIndexToHScript = function(index) return entities[index] end

local function unit(index, monster, armor)
    local value = {
        survival_monster_corpse = monster,
        survival_armor_mapping_version = monster
            and armor_balance.CUSTOM_WAR3_MAPPING_VERSION or nil,
        survival_war3_armor = armor,
        survival_effective_war3_armor = armor,
    }
    function value:IsNull() return false end
    function value:entindex() return index end
    function value:HasModifier() return false end
    function value:GetHealth() return 20000 end
    function value:GetMaxHealth() return 20000 end
    return value
end

entities[1] = unit(1, false, nil)
entities[2] = unit(2, true, 117)

local pending_record = nil
local emitted = {}
filter_service.init({
    event_bus = { emit = function(name, payload) emitted[#emitted + 1] = { name, payload } end },
    events = {
        DAMAGE_BLOCKED = "blocked",
        DAMAGE_FILTERED = "filtered",
        DAMAGE_RESOLVED = "resolved",
    },
    repository = { consume_pending = function()
        local record = pending_record
        pending_record = nil
        return record
    end },
    config = {
        global_post_bonus_pct = 0,
        minimum_post_multiplier = 0,
        boss_rules = { enabled = false },
    },
})

local function close(actual, expected, label)
    assert(math.abs(actual - expected) < 0.001,
        string.format("%s: expected %.6f, got %.6f", label, expected, actual))
end

local function run(damage, damage_type, record, victim)
    pending_record = record
    local keys = {
        damage = damage,
        damagetype_const = damage_type,
        entindex_attacker_const = 1,
        entindex_victim_const = victim or 2,
        damage_flags = 0,
    }
    assert(filter_service._filter_for_test(nil, keys) == true)
    return keys
end

close(run(801, DAMAGE_TYPE_PHYSICAL).damage, 801 / 3.34, "117 armor 801")
close(run(1401, DAMAGE_TYPE_PHYSICAL).damage, 1401 / 3.34, "117 armor 1401")

local pierced = run(801, DAMAGE_TYPE_PHYSICAL, { physical_armor_ignore_pct = 30 })
close(pierced.damage, 801 / (1 + 0.02 * 117 * 0.7), "30 percent pierce")
assert(pierced.damage_flags == DOTA_DAMAGE_FLAG_IGNORES_PHYSICAL_ARMOR)

entities[2].survival_effective_war3_armor = 0
close(run(801, DAMAGE_TYPE_PHYSICAL).damage, 801, "zero armor")
entities[2].survival_effective_war3_armor = -25
close(run(801, DAMAGE_TYPE_PHYSICAL).damage, 801, "negative armor")
entities[2].survival_effective_war3_armor = 117

close(run(801, DAMAGE_TYPE_MAGICAL).damage, 801, "magical isolation")
entities[3] = unit(3, false, nil)
close(run(801, DAMAGE_TYPE_PHYSICAL, nil, 3).damage, 801, "non-monster isolation")
close(run(801, DAMAGE_TYPE_PHYSICAL, { damage_kind = "ability" }).damage,
    801 / 3.34, "physical ability")

assert(filter_service._add_damage_flag_for_test(512, 512) == 512)
assert(filter_service._add_damage_flag_for_test(2, 512) == 514)

entities[2].survival_endless_health_scale = 100
close(run(33400, DAMAGE_TYPE_PHYSICAL).damage, 100, "endless health projection after armor")
entities[1].survival_endless_attack_scale = 20
close(run(1670, DAMAGE_TYPE_PHYSICAL).damage, 100, "endless basic attack with omitted category")
entities[1].survival_endless_attack_scale = 1e40
assert(run(1e8, DAMAGE_TYPE_PHYSICAL, nil, 3).damage == 1e30, "native float overflow guard")
entities[1].survival_endless_attack_scale = nil
entities[2].survival_endless_health_scale = nil

print("CUSTOM_MONSTER_ARMOR_PASS")
