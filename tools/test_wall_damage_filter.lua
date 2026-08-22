package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path

DAMAGE_TYPE_PHYSICAL = 1
DOTA_DAMAGE_FLAG_IGNORES_PHYSICAL_ARMOR = 8
DOTA_DAMAGE_CATEGORY_ATTACK = 1

local attacker = { index = 1 }
local victim = {
    index = 2,
    survival_war3_armor_target = true,
    survival_armor_mapping_version = 3,
    survival_effective_war3_armor = 36,
    survival_building_id = "wall",
    survival_player_id = 0,
}
for _, unit in ipairs({ attacker, victim }) do
    function unit:IsNull() return false end
    function unit:entindex() return self.index end
    function unit:GetUnitName() return self == victim and "building_wall" or "attacker" end
    function unit:HasModifier() return false end
    function unit:IsInvulnerable() return false end
    function unit:FindAllModifiersByName() return {} end
    function unit:GetHealth() return 100 end
    function unit:GetMaxHealth() return 100 end
end

function EntIndexToHScript(index)
    return index == attacker.index and attacker or victim
end

local emitted = {}
local event_bus = {}
function event_bus.emit(name, payload) emitted[#emitted + 1] = { name, payload } end
local repository = {}
function repository.consume_pending() return { physical_armor_ignore_pct = 50 } end

local filter = require("combat/damage_filter_service")
local rogue_effect_state = require("systems/rogue_effect_state_service")
filter.init({
    event_bus = event_bus,
    events = {
        DAMAGE_BLOCKED = "blocked",
        DAMAGE_FILTERED = "filtered",
        DAMAGE_RESOLVED = "resolved",
    },
    repository = repository,
    config = {
        global_post_bonus_pct = 0,
        minimum_post_multiplier = 0,
        boss_rules = { enabled = false, default_damage_taken_multiplier = 1 },
    },
})

local keys = {
    entindex_attacker_const = 1,
    entindex_victim_const = 2,
    damage = 100,
    damagetype_const = DAMAGE_TYPE_PHYSICAL,
    damage_category_const = DOTA_DAMAGE_CATEGORY_ATTACK,
    damage_flags_const = 0,
}
assert(filter._filter_for_test(nil, keys), "wall physical damage accepted")
assert(math.abs(keys.damage - 100 / 1.36) < 0.0001, "wall filter War3 damage")
assert(keys.damage_flags == DOTA_DAMAGE_FLAG_IGNORES_PHYSICAL_ARMOR,
    "wall filter must bypass native armor")
assert(#emitted == 2 and emitted[1][1] == "filtered"
    and emitted[2][1] == "resolved", "wall damage events")

rogue_effect_state.set_wall_damage_cap(0, 20)
keys.damage = 1000
assert(filter._filter_for_test(nil, keys), "ion shield wall damage accepted")
assert(keys.damage == 20, "ion shield did not cap final damage at 20 percent max health")

victim.survival_player_id = 1
keys.damage = 1000
assert(filter._filter_for_test(nil, keys), "foreign wall damage accepted")
assert(keys.damage > 20, "ion shield leaked to another player's wall")

print("WALL_DAMAGE_FILTER_LUA51_PASS")