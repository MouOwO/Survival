package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path

DAMAGE_TYPE_PHYSICAL = 1
DAMAGE_TYPE_MAGICAL = 2
DOTA_DAMAGE_FLAG_IGNORES_PHYSICAL_ARMOR = 512

package.loaded["config/generated/global_rules"] = {
    by_id = { runtime_detailed_diagnostics = { value = 0, enabled = true } },
}
package.loaded["systems/tree_damage_rules"] = {
    is_tree = function(unit) return unit and unit.test_tree == true end,
    is_allowed_tree_attacker = function() return true end,
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

entities[2].test_tree = true
entities[2].GetHealth = function() return 100000000 end
entities[2].survival_endless_health_scale = 10000000
close(run(1e30, DAMAGE_TYPE_PHYSICAL).damage, 99999999, "tree lethal hit stops at one HP")
entities[2].GetHealth = function() return 1 end
close(run(1e30, DAMAGE_TYPE_PHYSICAL).damage, 0, "tree cannot lose its last HP")
print("CUSTOM_MONSTER_ARMOR_PASS: tree overflow and lethal damage protected")

-- Exercise the real Deal -> adapter -> filter path with both verbosity modes.
-- Reuse this damage-filter fixture so the switch cannot hide a numeric/event
-- regression behind a stubbed damage service.
local rules = require("combat/damage_rule_config")
local damage_service = require("combat/damage_service")
local damage_debug = require("combat/combat_debug_service")
local repository = require("combat/damage_transaction_repository")
local combat_events = require("combat/combat_events")
assert(rules.debug_enabled == false, "per-transaction logging is opt-in by default")
DAMAGE_TYPE_PURE = 4
GameRules = { GetGameTime = function() return 42 end }
RandomFloat = function() return 0 end
entities[2].test_tree = false
local original_print = print

local function run_verbose_case(enabled)
    rules.debug_enabled = enabled
    local logs, events, native_calls = {}, {}, 0
    print = function(line) logs[#logs + 1] = line end
    local bus = { emit = function(name, payload)
        events[#events + 1] = { name = name, payload = payload }
    end }
    repository.init(rules)
    damage_debug.init(rules)
    filter_service.init({ event_bus = bus, events = combat_events,
        repository = repository, config = rules })
    damage_service.init({ event_bus = bus, events = combat_events,
        context = require("combat/damage_context"), rules = rules,
        repository = repository, adapter = require("adapters/dota_damage_adapter"),
        debug = damage_debug })
    ApplyDamage = function(request)
        native_calls = native_calls + 1
        assert(filter_service._filter_for_test(nil, {
            damage = request.damage, damagetype_const = request.damage_type,
            entindex_attacker_const = request.attacker:entindex(),
            entindex_victim_const = request.victim:entindex(),
            damage_flags = request.damage_flags or 0,
        }))
    end
    local request = { transaction_id = "verbosity_equivalence", attacker = entities[1],
        victim = entities[2], source_kind = "script", base_damage = 100,
        fixed_damage_bonus = 10, pre_damage_bonus_pct = 0.1,
        can_crit = true, crit_chance = 1, crit_multiplier = 2,
        post_damage_bonus_pct = 0.2, target_post_reduction_pct = 0.1,
        physical_armor_ignore_pct = 25, damage_type = DAMAGE_TYPE_PHYSICAL }
    local dealt = damage_service:Deal(request)
    local blocked = damage_service:Deal(request)
    print = original_print
    assert(native_calls == 1, "duplicate transactions still never reach the engine")
    assert(dealt.success and dealt.critical)
    close(dealt.submitted_damage, 242, "verbosity submitted damage")
    close(dealt.final_damage, 242 * 1.1 / (1 + 0.02 * 117 * 0.75),
        "verbosity armor/post damage")
    assert(not blocked.success and blocked.blocked_reason == "duplicate_transaction_id")
    local expected = { combat_events.DAMAGE_REQUESTED, combat_events.DAMAGE_CALCULATED,
        combat_events.DAMAGE_FILTERED, combat_events.DAMAGE_RESOLVED,
        combat_events.DAMAGE_SUBMITTED, combat_events.DAMAGE_BLOCKED }
    assert(#events == #expected, "all damage/statistics events remain present")
    for index, name in ipairs(expected) do assert(events[index].name == name) end
    return { dealt = dealt, blocked = blocked, events = events }, logs
end

local quiet, quiet_logs = run_verbose_case(false)
local verbose, verbose_logs = run_verbose_case(true)
assert(#quiet_logs == 0, "default emits no transaction logs")
assert(#verbose_logs == 2, "explicit true logs success and blocked transactions")
for _, line in ipairs(verbose_logs) do
    assert(line:find("[CombatDamage] transaction_id=", 1, true) == 1)
end
local function same(actual, expected, path)
    if actual == expected then return end
    assert(type(actual) == "table" and type(expected) == "table", path .. " differs")
    for key, value in pairs(actual) do same(value, expected[key], path .. "." .. tostring(key)) end
    for key in pairs(expected) do assert(actual[key] ~= nil, path .. " missing " .. tostring(key)) end
end
same(quiet, verbose, "damage_and_events")
local live_logs = {}
print = function(line) live_logs[#live_logs + 1] = line end
rules.debug_enabled = false
damage_debug.log(quiet.dealt)
rules.debug_enabled = true
damage_debug.log(quiet.dealt)
rules.debug_enabled = false
damage_debug.log(quiet.dealt)
print = original_print
assert(#live_logs == 1, "same shared config supports live opt-in/out without reinitialization")
print("COMBAT_DEBUG_LOGGING_PASS: quiet default, explicit opt-in, identical damage/blocked results and event payloads")
