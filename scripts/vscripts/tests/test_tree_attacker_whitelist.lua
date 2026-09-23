package.path = "scripts/vscripts/?.lua;" .. package.path
local rules = require("systems/tree_damage_rules")
local next_index, time = 0, 10
DOTA_DAMAGE_CATEGORY_ATTACK = 1
GameRules = { GetGameTime = function() return time end }
local function unit(name, real_hero, fields)
    next_index = next_index + 1
    local value = fields or {}
    value.index = next_index
    value.IsNull = function() return false end
    value.GetUnitName = function() return name end
    value.IsRealHero = function() return real_hero == true end
    value.IsIllusion = function(self) return self.illusion == true end
    value.entindex = function(self) return self.index end
    return value
end
local tree = unit("enemy_tree")
local enemy = unit("npc_survival_enemy")
local hero = unit("npc_dota_hero_sven", true)
local worker = unit("npc_survival_lumberjack")
for _, attacker in ipairs({hero, worker}) do
    assert(rules.is_allowed_tree_attacker(attacker), "gameplay hero and lumberjack remain eligible")
    assert(rules.allows_damage(attacker, tree, DOTA_DAMAGE_CATEGORY_ATTACK, false))
    assert(not rules.allows_damage(attacker, tree, 2, false), "hero spells still cannot damage the resource tree")
    assert(rules.mark_basic_attack(attacker, tree, 100))
    assert(rules.consume_basic_attack(attacker, tree), "real basic-attack evidence is available once")
    assert(not rules.consume_basic_attack(attacker, tree))
end

local towers = {
    unit("building_arrow_tower", false), -- Before Lua identity assignment.
    unit("npc_dota_unit_ultimate_tower", false),
    unit("npc_dota_hero_sven", true, {survival_building_id = "arrow_tower"}),
    unit("npc_dota_hero_sven", true, {survival_building_id = "ultimate_tower"}),
    unit("npc_dota_hero_sven", true, {survival_ultimate_tower = true}),
}
for _, tower in ipairs(towers) do
    assert(rules.is_arrow_tower(tower), "all tower identities share targeting restrictions")
    assert(not rules.is_allowed_tree_attacker(tower), "a hero carrier must not grant a tower lumber rights")
    assert(not rules.allows_damage(tower, tree, DOTA_DAMAGE_CATEGORY_ATTACK, true), "even supplied evidence cannot authorize tower damage")
    assert(not rules.mark_basic_attack(tower, tree, 200))
    assert(rules.allows_damage(tower, enemy, DOTA_DAMAGE_CATEGORY_ATTACK), "ordinary combat damage remains allowed")
end
for _, attacker in ipairs({
    unit("npc_dota_hero_sven", true, {survival_is_building = true}),
    unit("npc_dota_hero_sven", true, {survival_is_native_wearable_visual = true}),
    unit("npc_dota_hero_sven", true, {survival_is_native_wearable = true}),
    unit("npc_dota_hero_sven", true, {illusion = true}),
    unit("npc_survival_enemy"),
}) do
    assert(not rules.is_allowed_tree_attacker(attacker), "buildings, visual-only entities, illusions and creeps are denied")
    assert(not rules.allows_damage(attacker, tree, DOTA_DAMAGE_CATEGORY_ATTACK, true))
end
assert(not rules.is_allowed_tree_attacker(nil))
assert(not rules.is_arrow_tower(hero) and not rules.is_arrow_tower(worker))
print("TREE_ATTACKER_WHITELIST_PASS: real heroes/workers, pre-identity towers, ultimate/hero-model towers, visual carriers, attack evidence and normal combat")
