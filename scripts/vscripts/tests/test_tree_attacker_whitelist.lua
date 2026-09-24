package.path = "scripts/vscripts/?.lua;" .. package.path
local rules = require("systems/tree_damage_rules")
local next_index, time = 0, 10
DOTA_DAMAGE_CATEGORY_ATTACK = 1
GameRules = { GetGameTime = function() return time end }
local function unit(name, real_hero, fields)
    next_index = next_index + 1
    local value = fields or {}
    value.index = next_index
    value.IsNull = function(self) return self.removed == true end
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

-- Evidence remains isolated across attackers, victims and simultaneous records.
local second_tree = unit("enemy_tree")
assert(rules.mark_basic_attack(hero, tree, 301))
assert(rules.mark_basic_attack(hero, tree, 302))
assert(rules.mark_basic_attack(hero, second_tree, 303))
assert(rules.mark_basic_attack(worker, tree, 301))
assert(rules.clear_basic_attack(hero, tree, 301))
assert(rules.consume_basic_attack(hero, tree), "clearing one record preserves another projectile")
assert(not rules.consume_basic_attack(hero, tree))
assert(rules.consume_basic_attack(worker, tree), "another attacker's same record stays isolated")
rules.clear_basic_attack(hero, nil, 303)
assert(not rules.consume_basic_attack(hero, second_tree), "target-less record cleanup finds this attacker's victim")
assert(rules.mark_basic_attack(hero, tree, 304))
time = time + 4
assert(not rules.consume_basic_attack(hero, tree), "expired evidence never authorizes damage")

-- Attack-record events are global. A forest must ignore unrelated combat using
-- a local identity lookup, before entity getters or evidence-table traversal.
class = function(t) return t end
IsServer = function() return true end
package.loaded["core/scheduler"] = {}
local progression = require("modifiers/modifier_tree_progression")
local forest = {}
for i = 1, 100 do
    local own_tree = i == 1 and tree or unit("enemy_tree")
    forest[i] = setmetatable({ GetParent = function() return own_tree end }, { __index = progression })
end
local clear_calls, original_clear = 0, rules.clear_basic_attack_token
rules.clear_basic_attack_token = function(...)
    clear_calls = clear_calls + 1
    return original_clear(...)
end
for _ = 1, 100 do
    for _, modifier in ipairs(forest) do modifier:OnAttackRecordDestroy({attacker=enemy, record=400}) end
end
assert(clear_calls == 0, "100 trees x 100 ordinary attacks must perform zero evidence cleanup calls")
forest[1]:OnAttackStart({attacker=hero, target=tree, record=401})
for _, modifier in ipairs(forest) do modifier:OnAttackRecordDestroy({attacker=hero, record=402}) end
assert(clear_calls == 1, "only the tree with pending evidence processes target-less record destruction")
assert(rules.consume_basic_attack(hero, tree), "unrelated record destruction preserves pending evidence")
for _, modifier in ipairs(forest) do modifier:OnAttackRecordDestroy({attacker=hero, record=401}) end
assert(clear_calls == 2)
for _, modifier in ipairs(forest) do modifier:OnAttackRecordDestroy({attacker=hero, record=401}) end
assert(clear_calls == 2, "drained evidence stops the tree's listener work")
forest[1]:OnAttackStart({attacker=worker, target=tree, record=403})
forest[1]:OnAttackFail({attacker=worker, target=tree, record=403})
assert(not rules.consume_basic_attack(worker, tree), "failed attack cannot leave reusable evidence")
forest[1]:OnAttackStart({attacker=hero, target=tree, record=404})
forest[1]:OnAttackStart({attacker=worker, target=tree, record=405})
assert(rules.mark_basic_attack(hero, second_tree, 406))
forest[1]:OnDestroy()
assert(not rules.consume_basic_attack(hero, tree) and not rules.consume_basic_attack(worker, tree),
    "tree removal clears its outstanding evidence before projectile destruction")
assert(rules.consume_basic_attack(hero, second_tree), "tree removal preserves another tree's evidence")
assert(forest[1].tree_attackers == nil, "tree removal releases watched attacker handles")
rules.clear_basic_attack_token = original_clear

-- Cleanup owns a cached queue token, so deletion cannot strand evidence or
-- require touching an invalid engine entity to find its former indices.
local deleted_worker, deleted_tree = unit("npc_survival_lumberjack"), unit("enemy_tree")
local lifecycle = setmetatable({GetParent=function() return deleted_tree end}, {__index=progression})
lifecycle:OnAttackStart({attacker=deleted_worker, target=deleted_tree, record=501})
local removed_attacker_token = lifecycle.tree_attackers[deleted_worker]
deleted_worker.removed = true
deleted_worker.entindex = function() error("deleted attacker index must not be read") end
lifecycle:OnAttackRecordDestroy({attacker=deleted_worker, record=501})
assert(#removed_attacker_token.entries == 0 and lifecycle.tree_attackers[deleted_worker] == nil,
    "record destruction clears evidence after attacker invalidation")
lifecycle:OnAttackStart({attacker=hero, target=deleted_tree, record=502})
local removed_tree_token = lifecycle.tree_attackers[hero]
deleted_tree.removed = true
lifecycle.GetParent = function() error("destroyed parent must not be read for cleanup") end
lifecycle:OnDestroy()
assert(#removed_tree_token.entries == 0 and lifecycle.tree_attackers == nil,
    "modifier destruction clears evidence after parent invalidation")

local recycled_hero, recycled_tree = unit("npc_dota_hero_sven", true), unit("enemy_tree")
local old_hero, old_tree = unit("npc_dota_hero_sven", true), unit("enemy_tree")
recycled_hero.index, recycled_tree.index = old_hero.index, old_tree.index
local old_modifier = setmetatable({GetParent=function() return old_tree end}, {__index=progression})
old_modifier:OnAttackStart({attacker=old_hero, target=old_tree, record=503})
assert(not rules.consume_basic_attack(recycled_hero, old_tree), "reused attacker index is not attack evidence")
assert(not rules.consume_basic_attack(old_hero, recycled_tree), "reused victim index is not attack evidence")
assert(rules.mark_basic_attack(recycled_hero, recycled_tree, 503))
old_hero.removed, old_tree.removed = true, true
old_modifier:OnAttackRecordDestroy({attacker=old_hero, record=503})
assert(rules.consume_basic_attack(recycled_hero, recycled_tree),
    "late cleanup token never clears a replacement entity's same-index same-record evidence")

-- OnAttackStart may omit its record while RecordDestroy supplies a number.
-- Canceled starts must stay bounded without ever reaching the damage filter.
local canceled = setmetatable({GetParent=function() return tree end}, {__index=progression})
local canceled_token
for index = 1, 1000 do
    time = 100 + index * 0.05
    canceled:OnAttackStart({attacker=worker, target=tree})
    canceled_token = canceled.tree_attackers[worker]
    assert(#canceled_token.entries <= 62, "mark prunes expired canceled starts before appending")
    canceled:OnAttackRecordDestroy({attacker=worker, record=10000 + index})
end
time = time + 4
canceled:OnAttackRecordDestroy({attacker=worker, record=20001})
assert(#canceled_token.entries == 0 and canceled.tree_attackers[worker] == nil,
    "numeric record destruction prunes expired nil-record evidence and releases its watcher")

local _, mixed_token = rules.mark_basic_attack(hero, tree, nil)
time = time + 2
assert(rules.mark_basic_attack(hero, tree, 601))
assert(rules.mark_basic_attack(hero, tree, 602))
time = time + 2
assert(rules.mark_basic_attack(hero, tree, 603))
assert(#mixed_token.entries == 3 and mixed_token.entries[1].record == "601",
    "expired nil-record start is pruned without dropping valid simultaneous projectiles")
assert(rules.clear_basic_attack_token(mixed_token, 602))
assert(#mixed_token.entries == 2 and mixed_token.entries[1].record == "601"
    and mixed_token.entries[2].record == "603", "destroy removes only its valid record and preserves FIFO order")
assert(rules.consume_basic_attack(hero, tree) and rules.consume_basic_attack(hero, tree)
    and not rules.consume_basic_attack(hero, tree), "each retained projectile authorizes exactly one hit")
local _, valid_nil_token = rules.mark_basic_attack(hero, tree, nil)
assert(rules.mark_basic_attack(hero, tree, 604))
assert(rules.clear_basic_attack_token(valid_nil_token, 604) and #valid_nil_token.entries == 1,
    "numeric destruction must not guess which unexpired nil-record start it belongs to")
assert(rules.consume_basic_attack(hero, tree), "valid nil-record fallback remains usable once")
rules.reset_pending_attacks()
print("TREE_EVIDENCE_HOTPATH_PASS: 100 trees x 100 unrelated attacks cleanup calls=0; owned record cleanup=1")
print("TREE_EVIDENCE_LIFETIME_PASS: invalid attacker/parent cleanup and reused entity indices stay isolated")
print("TREE_EVIDENCE_EXPIRY_PASS: 1000 canceled nil-record starts bounded to 3 seconds; live projectiles preserved")
print("TREE_ATTACKER_WHITELIST_PASS: real heroes/workers, pre-identity towers, ultimate/hero-model towers, visual carriers, attack evidence and normal combat")
