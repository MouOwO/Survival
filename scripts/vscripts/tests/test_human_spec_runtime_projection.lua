-- Run with LuaJIT 2.1 from the addon root. Exercise native integer setters,
-- the production damage filter, and UI projection as one numeric boundary.
package.path = "scripts/vscripts/?.lua;" .. package.path
DAMAGE_TYPE_PHYSICAL, DAMAGE_TYPE_MAGICAL = 1, 2
DOTA_DAMAGE_FLAG_IGNORES_PHYSICAL_ARMOR = 512
package.loaded["config/generated/global_rules"] = {
    by_id = {runtime_detailed_diagnostics = {value = 0, enabled = true}},
}
package.loaded["systems/tree_damage_rules"] = {
    is_tree = function() return false end,
    is_arrow_tower = function() return false end,
    is_lumberjack = function() return false end,
    is_allowed_tree_attacker = function() return true end,
    allows_damage = function() return true end,
    is_basic_attack_category = function() return false end,
    consume_basic_attack = function() return false end,
    reset_pending_attacks = function() end,
}
package.loaded["systems/anti_air_rules"] = {
    can_attack = function() return true end,
    has_damage_taken_aura = function() return false end,
}
local projection = require("combat/endless_stat_projection")
local armor = require("config/armor_balance")
local ui = require("ui/combat_stat_projection")
local filter = require("combat/damage_filter_service")
local entities, last_damage, pending_record = {}, nil, nil
EntIndexToHScript = function(index) return entities[index] end
filter.init({
    event_bus = {emit = function(_, payload)
        if payload.final_damage ~= nil then last_damage = payload.final_damage end
    end},
    events = {DAMAGE_BLOCKED = "blocked", DAMAGE_FILTERED = "filtered", DAMAGE_RESOLVED = "resolved"},
    repository = {consume_pending = function()
        local value = pending_record
        pending_record = nil
        return value
    end},
    config = {global_post_bonus_pct = 0, minimum_post_multiplier = 0,
        boss_rules = {enabled = false}},
})

local function close(actual, expected, label)
    assert(math.abs(actual - expected) <= math.max(1e-10, math.abs(expected) * 1e-12),
        tostring(label) .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function unit(index)
    local value = {health = 100, maximum = 100}
    function value:IsNull() return false end
    function value:entindex() return index end
    function value:HasModifier() return false end
    function value:GetHealth() return self.health end
    function value:GetMaxHealth() return self.maximum end
    function value:SetBaseMaxHealth(n) self.base_health = math.floor(n) end
    function value:SetMaxHealth(n) self.maximum = math.floor(n) end
    function value:SetHealth(n) self.health = math.floor(n) end
    function value:SetBaseDamageMin(n) self.minimum = math.floor(n) end
    function value:SetBaseDamageMax(n) self.maximum_attack = math.floor(n) end
    entities[index] = value
    return value
end
local function spawn(index, row)
    local value = unit(index)
    local native = projection.prepare_exact(value, row)
    value:SetBaseMaxHealth(native.health)
    value:SetMaxHealth(native.health)
    value:SetHealth(native.health)
    value:SetBaseDamageMin(native.attack)
    value:SetBaseDamageMax(native.attack)
    assert(value.maximum <= 1e8 and value.minimum <= 16777216)
    close(tonumber(projection.for_ui(value, value.maximum, "health")), row.health, "logical HP")
    close(tonumber(projection.for_ui(value, value.minimum, "attack")), row.attack, "logical attack min")
    close(tonumber(projection.for_ui(value, value.maximum_attack, "attack")), row.attack, "logical attack max")
    assert(native.human_spec == row.human_spec and native.war3_armor == row.war3_armor)
    return value
end
local function hit(attacker, victim, damage, damage_type, record)
    last_damage, pending_record = nil, record
    local keys = {damage = damage, damagetype_const = damage_type or DAMAGE_TYPE_MAGICAL,
        entindex_attacker_const = attacker:entindex(), entindex_victim_const = victim:entindex(),
        damage_flags = 0}
    local accepted = filter._filter_for_test(nil, keys)
    return accepted, keys.damage, last_damage
end

local target = unit(2)
for _, row in ipairs({
    {health = 150.75, attack = 2473.9, war3_armor = 117.6, human_spec = true},
    {health = 8537831201685, attack = 34151312000, human_spec = true},
    {health = 100.25, attack = 16777217, human_spec = true},
    {health = 10.5, attack = 0, human_spec = true},
    {health = 0.75, attack = 0.25, human_spec = true},
}) do
    local original_health, original_attack = row.health, row.attack
    local attacker = spawn(1, row)
    assert(row.health == original_health and row.attack == original_attack, "source formulas stay precise")
    local accepted, damage, logical = hit(attacker, target, attacker.minimum)
    assert(accepted)
    close(logical, row.attack, "native basic attack restored once")
    close(damage, row.attack, "ordinary target receives logical attack")
    accepted, damage, logical = hit(attacker, target, 12.75, DAMAGE_TYPE_MAGICAL, {damage_kind = "ability"})
    assert(accepted)
    close(logical, 12.75, "scripted damage is already logical")
end

local attacker = spawn(1, {health = 100, attack = 2473.9})
local victim = spawn(2, {health = 150.75, attack = 0})
victim.survival_monster_corpse = true
victim.survival_armor_mapping_version = armor.CUSTOM_WAR3_MAPPING_VERSION
victim.survival_war3_armor, victim.survival_effective_war3_armor = 117.6, 117.6
local accepted, damage, logical = hit(attacker, victim, attacker.minimum, DAMAGE_TYPE_PHYSICAL)
assert(accepted)
close(logical, 2473.9 / (1 + 0.02 * 117.6), "fractional armor used in damage")
close(damage * victim.survival_endless_health_scale, logical, "projected incoming health damage")
local raw = {armor = 117.6, armor_mapping_version = armor.CUSTOM_WAR3_MAPPING_VERSION}
local display = ui.for_ui(raw)
assert(raw.armor == 117.6 and display.armor == 117.6 and display.armor_display == 117)
assert(display.stat_tooltips.armor.display_value == 117)
assert(display.stat_tooltips.armor.logical_value == 117.6)
close(display.stat_tooltips.armor.physical_reduction_pct,
    100 * (1 - 1 / (1 + 0.02 * 117.6)), "tooltip reduction retains fractional armor")
assert(ui.for_ui(display).armor == 117.6, "repeated UI projection never truncates effective armor")
assert(ui.for_ui({armor = -0.1, armor_mapping_version = armor.CUSTOM_WAR3_MAPPING_VERSION}).armor_display == -1)

-- Values below one are opt-in to this authored-stat projection. Legacy safety
-- checks must still reject malformed scales and retain old endless behavior.
attacker, victim = spawn(1, {health = 0.75, attack = 0.25}), unit(2)
assert(hit(attacker, victim, attacker.minimum))
attacker.survival_exact_stat_projection = nil
assert(not hit(attacker, victim, attacker.minimum))
for _, invalid in ipairs({0, -1, math.huge, -math.huge, 0/0}) do
    attacker.survival_exact_stat_projection = true
    attacker.survival_endless_attack_scale = invalid
    assert(not hit(attacker, victim, 1), "invalid attack scale rejected")
end
attacker = unit(1)
victim = spawn(2, {health = 0.75, attack = 1})
assert(hit(attacker, victim, 0.25))
victim.survival_exact_stat_projection = nil
assert(not hit(attacker, victim, 0.25))
for _, invalid in ipairs({0, -1, math.huge, -math.huge, 0/0}) do
    victim.survival_exact_stat_projection = true
    victim.survival_endless_health_scale = invalid
    assert(not hit(attacker, victim, 1), "invalid health scale rejected")
end
local legacy = unit(3)
projection.prepare_exact(legacy, {health = 1.5, attack = 0.5})
local old = projection.prepare(legacy, {health = 1e10, attack = 1e12})
assert(old.health == 1e8 and old.attack == 1e8)
assert(legacy.survival_endless_health_scale == 100 and legacy.survival_endless_attack_scale == 10000)
assert(legacy.survival_exact_stat_projection == nil)
old = projection.prepare(unit(4), {health = 100.5, attack = 1.5})
assert(old.health == 100.5 and old.attack == 1.5, "legacy prepare is unchanged")
for _, row in ipairs({{health = 0, attack = 1}, {health = math.huge, attack = 1},
    {health = 100, attack = -1}, {health = 100, attack = 0/0},
    {health = 100, attack = "invalid"}, {health = 100}}) do
    assert(not pcall(projection.prepare_exact, {}, row), "malformed authored stats rejected")
end
print("HUMAN_SPEC_RUNTIME_PROJECTION_PASS: integer setters, fractional/large/zero stats, physical/scripted damage, raw armor/display floor, and legacy guards")
