-- Offline boundary/cost characterization; does not change native gameplay.
-- Run from addon root with Lua 5.1. Native C++ cost needs a live capture.
package.path = "scripts/vscripts/?.lua;" .. package.path

DAMAGE_TYPE_PHYSICAL, DAMAGE_TYPE_PURE = 1, 4
DOTA_DAMAGE_CATEGORY_ATTACK, DOTA_DAMAGE_CATEGORY_SPELL = 1, 2
GameRules = { GetGameTime = function() return 0 end }
RandomFloat = function() return 1 end
package.loaded["systems/tree_damage_rules"] = {
    is_tree = function() return false end,
    is_basic_attack_category = function(category) return category == 1 end,
    allows_damage = function() return true end,
    reset_pending_attacks = function() end,
}
package.loaded["systems/anti_air_rules"] = {
    can_attack = function() return true end,
    has_damage_taken_aura = function() return false end,
}
package.loaded["config/generated/global_rules"] = { by_id = {} }
package.loaded["systems/rogue_effect_state_service"] = {
    has_effect = function() return false end,
    numeric = function() return 0 end,
}

local bus = require("core/event_bus")
local events = require("combat/combat_events")
local rules = require("combat/damage_rule_config")
local repository = require("combat/damage_transaction_repository")
local context = require("combat/damage_context")
local projection = require("combat/endless_stat_projection")
local filter = require("combat/damage_filter_service")
local service = require("combat/damage_service")
local adapter = require("adapters/dota_damage_adapter")
local counters, last_native_input, last_native_output, last_logical
local function counted(name, result)
    counters[name] = (counters[name] or 0) + 1
    return result
end
local function entity(index)
    local unit = { index = index }
    function unit:IsNull() return counted("is_null", false) end
    function unit:entindex() return counted("entindex", self.index) end
    function unit:IsInvulnerable() return counted("invulnerable", false) end
    function unit:HasModifier() return counted("has_modifier", false) end
    function unit:IsRealHero() return counted("real_hero", false) end
    return unit
end
local attacker, victim = entity(1), entity(2)
local entities = { attacker, victim }
EntIndexToHScript = function(index) return counted("resolve_entity", entities[index]) end
filter.init({ event_bus = bus, events = events, repository = repository, config = rules })
service.init({ event_bus = bus, events = events, context = context, rules = rules,
    repository = repository, adapter = adapter, debug = { log = function() end } })
bus.subscribe(events.DAMAGE_FILTERED, function(payload)
    counted("filtered", nil)
    last_logical = payload.final_damage
end)
bus.subscribe(events.DAMAGE_RESOLVED, function() counted("resolved", nil) end)
ApplyDamage = function(input)
    counted("native_apply", nil)
    last_native_input = input.damage
    local keys = { entindex_attacker_const = 1, entindex_victim_const = 2,
        entindex_inflictor_const = 3, damage_category_const = DOTA_DAMAGE_CATEGORY_SPELL,
        damagetype_const = input.damage_type, damage = input.damage }
    assert(filter._filter_for_test(filter, keys))
    last_native_output = keys.damage
end

local function near(actual, expected, label)
    assert(type(actual) == "number" and math.abs(actual - expected)
        <= math.max(1e-8, math.abs(expected) * 1e-12),
        label .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local function reset()
    counters = {}
    repository.init(rules)
end
local function instruction_count(callback)
    local instructions = 0
    debug.sethook(function() instructions = instructions + 100 end, "", 100)
    local ok, problem = pcall(callback)
    debug.sethook()
    assert(ok, tostring(problem))
    return instructions
end
local function same_cost(actual, expected)
    for key, value in pairs(actual) do
        assert(value == expected[key], key .. " cost changed with damage magnitude")
    end
    for key, value in pairs(expected) do
        assert(value == actual[key], key .. " cost disappeared with damage magnitude")
    end
end

local baseline, baseline_instructions
projection.prepare(victim, { health = 1e20, attack = 1 })
for _, amount in ipairs({ 100, 1e10, 9e15, 1e30, 1e100 }) do
    reset()
    local instructions = instruction_count(function()
        for _ = 1, 100 do
            local result = service:Deal({ attacker = attacker, victim = victim,
                source_kind = "ability", base_damage = amount,
                damage_type = DAMAGE_TYPE_PURE, can_crit = false })
            assert(result.success)
        end
    end)
    if baseline then
        same_cost(counters, baseline)
        assert(math.abs(instructions - baseline_instructions) <= 200,
            "Lua instruction cost increased with ability damage magnitude")
    else
        baseline, baseline_instructions = counters, instructions
    end
    assert(counters.native_apply == 100 and counters.filtered == 100 and counters.resolved == 100)
    near(last_native_input, amount, "observed pre-filter native ability input")
    near(last_logical, amount, "logical ability damage")
    near(last_native_output, math.min(amount / 1e12, 1e30), "native filter output")
    print(string.format("LARGE_ABILITY_COST amount=%.4g calls=%d instructions=%d native_input=%.4g native_output=%.4g",
        amount, counters.native_apply, instructions, last_native_input, last_native_output))
end

baseline, baseline_instructions = nil, nil
for _, amount in ipairs({ 1e10, 9e15, 1e30, 1e100 }) do
    local native_min, native_max = projection.prepare_attack(attacker, amount, amount)
    assert(native_min <= 1e8 and native_max <= 1e8)
    reset()
    local instructions = instruction_count(function()
        for _ = 1, 100 do
            local keys = { entindex_attacker_const = 1, entindex_victim_const = 2,
                damage_category_const = DOTA_DAMAGE_CATEGORY_ATTACK,
                damagetype_const = DAMAGE_TYPE_PHYSICAL, damage = native_max * 20 }
            assert(filter._filter_for_test(filter, keys))
            near(last_logical, amount * 20, "logical critical restored once")
            near(keys.damage, math.min(amount * 20 / 1e12, 1e30), "scaled critical damage")
        end
    end)
    if baseline then
        same_cost(counters, baseline)
        assert(math.abs(instructions - baseline_instructions) <= 200,
            "Lua instruction cost increased with attack damage magnitude")
    else
        baseline, baseline_instructions = counters, instructions
    end
    assert(counters.filtered == 100 and counters.resolved == 100)
    print(string.format("LARGE_ATTACK_COST amount=%.4g instructions=%d native_attack=%.4g",
        amount, instructions, native_max))
end
-- Invalid carrier values cannot produce damage events or mutate projection
-- state. Finite huge values remain accepted; only NaN/Inf are rejected.
for _, invalid in ipairs({0/0, math.huge, -math.huge}) do
    reset()
    local previous_scale = attacker.survival_endless_attack_scale
    assert(not pcall(projection.prepare_attack, attacker, invalid, 10))
    assert(attacker.survival_endless_attack_scale == previous_scale)
    assert(not pcall(projection.prepare_attack_components, attacker, 1, 1, invalid, 0, 0, 20))
    assert(attacker.survival_endless_attack_scale == previous_scale)
    local keys = {entindex_attacker_const=1, entindex_victim_const=2,
        damage_category_const=DOTA_DAMAGE_CATEGORY_ATTACK,
        damagetype_const=DAMAGE_TYPE_PHYSICAL, damage=invalid}
    assert(not filter._filter_for_test(filter, keys))
    assert(not counters.filtered and not counters.resolved)
end
print("ENDLESS_LARGE_DAMAGE_COST_PASS fixed native call/event counts and bounded Lua instructions; native pre-filter ability input reported separately")
