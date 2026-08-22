package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error((message or "assert_equal") .. ": expected=" .. tostring(expected)
            .. " actual=" .. tostring(actual))
    end
end

class = function(base) return base or {} end
IsServer = function() return true end
DOTA_DAMAGE_CATEGORY_ATTACK = 1
DOTA_TEAM_BADGUYS = 3
MODIFIER_PROPERTY_BASEDAMAGEOUTGOING_PERCENTAGE = 1
MODIFIER_PROPERTY_PREATTACK_BONUS_DAMAGE = 2
MODIFIER_EVENT_ON_TAKEDAMAGE = 3
MODIFIER_EVENT_ON_ATTACK_LANDED = 4
MODIFIER_PROPERTY_MIN_HEALTH = 5
MODIFIER_STATE_MAGIC_IMMUNE = 6

local state = require("systems/rogue_effect_state_service")
state.reset()
assert(state.add_numeric(0, "next_rogue_reroll_count", 1))
assert_equal(state.take_numeric(0, "next_rogue_reroll_count"), 1, "reroll take")
assert_equal(state.take_numeric(0, "next_rogue_reroll_count"), 0, "reroll one shot")
assert(state.add_numeric(0, "building_challenge_reward_doubles", 5))
assert(state.consume_numeric(0, "building_challenge_reward_doubles", 1))
assert_equal(state.numeric(0, "building_challenge_reward_doubles"), 4,
    "bounty decrements")

local requests = {}
local granted_item = nil
local granted_builder = {
    IsNull = function() return false end,
    AddItem = function(_, item) granted_item = item return item end,
}
package.loaded["core/event_bus"] = {
    request = function(event, payload)
        requests[#requests + 1] = { event = event, payload = payload }
        if event == "builder.get.request" then
            return { ok = true, builder = granted_builder }
        end
        if tostring(event):match("hero.combat_stats") then
            return { ok = true, snapshot = { attack_total = 1000 } }
        end
        return { ok = true }
    end,
}
package.loaded["core/events"] = {
    HERO_COMBAT_STATS_GET_REQUEST = "hero.combat_stats.get.request",
    BUILDER_GET_REQUEST = "builder.get.request",
}
package.loaded["systems/player_context_service"] = {
    is_owned_by = function(player_id, unit)
        return player_id == 0 and unit.survival_player_id == 0
    end,
}
dofile("scripts/vscripts/modifiers/modifier_rogue_combat_effects.lua")

CreateItem = function(name)
    assert_equal(name, "item_survival_rogue_nuclear_bomb", "bomb item name")
    return {}
end
UTIL_Remove = function() end
local registry = require("systems/rogue_effect_registry")
assert(registry.get("grant_nuclear_bomb_action").apply({
    player_id = 0,
    params = { batch_size = 4, batch_interval_seconds = 0.05 },
}), "bomb item grant")
assert_equal(granted_item.survival_nuclear_batch_size, 4, "bomb grant batch size")
assert_equal(granted_item.survival_nuclear_batch_interval, 0.05,
    "bomb grant batch interval")

state.add_numeric(0, "unit_attack_bonus_pct", 30)
state.add_numeric(0, "tower_hero_attack_projection_pct", 10)
local tower = { survival_building_id = "arrow_tower" }
local combat = setmetatable({ player_id = 0 }, {
    __index = modifier_rogue_combat_bonus,
})
function combat:GetParent() return tower end
assert_equal(combat:GetModifierBaseDamageOutgoing_Percentage(), 30, "morale pct")
assert_equal(combat:GetModifierPreAttack_BonusDamage(), 100, "hero attack projection")

local added = {}
local attacker = {
    survival_player_id = 0,
    survival_rogue_dummy_attack_bonus = 0,
    IsNull = function() return false end,
    GetTeamNumber = function() return 2 end,
    AddNewModifier = function(_, _, _, name, kv)
        added[#added + 1] = { name = name, value = kv.value }
    end,
}
local dummy_parent = {
    survival_player_id = 0,
    GetTeamNumber = function() return 3 end,
}
local dummy = setmetatable({ value = 100 }, {
    __index = modifier_rogue_training_dummy,
})
function dummy:GetParent() return dummy_parent end
dummy:OnAttackLanded({ target = dummy_parent, attacker = attacker })
dummy:OnAttackLanded({ target = dummy_parent, attacker = attacker })
assert_equal(attacker.survival_rogue_dummy_attack_bonus, 200, "dummy stacks every hit")
assert_equal(added[2].value, 200, "dummy modifier refresh value")

local killed = {}
local alive = {}
local function monster(options)
    options = options or {}
    return {
        survival_is_wave_monster = options.wave,
        survival_is_challenge_monster = options.challenge,
        survival_is_boss = options.boss,
        survival_boss_role = options.boss_role,
        survival_monster_role = options.role,
        IsNull = function() return false end,
        IsAlive = function(self) return alive[self] ~= false end,
        GetTeamNumber = function() return 3 end,
        HasModifier = function(_, name) return options.modifier_boss == true
            and name == "modifier_boss" end,
        ForceKill = function(self) killed[self] = (killed[self] or 0) + 1
            alive[self] = false end,
    }
end
local normal = monster({ wave = true })
local normal_two = monster({ wave = true })
local wave_leader = monster({ wave = true, role = "wave_leader" })
local assault_boss = monster({ wave = true, role = "assault_boss" })
local boss = monster({ challenge = true, boss = true })
local proxy = monster({})
Entities = { FindAllByClassname = function()
    return { normal, normal_two, wave_leader, assault_boss, boss, proxy }
end }
local scheduled = {}
package.loaded["core/scheduler"] = {
    after = function(delay, callback, task_id)
        scheduled[#scheduled + 1] = {
            delay = delay, callback = callback, task_id = task_id,
        }
    end,
}
dofile("scripts/vscripts/items/item_survival_rogue_actions.lua")
local removed = 0
local caster = {
    IsNull = function() return false end,
    RemoveItem = function() removed = removed + 1 end,
}
local bomb = setmetatable({
    survival_nuclear_batch_size = 1,
    survival_nuclear_batch_interval = 0.05,
}, { __index = item_survival_rogue_nuclear_bomb })
function bomb:GetCaster() return caster end
function bomb:IsNull() return false end
function bomb:entindex() return 99 end
function bomb:SetActivated(value) self.activated = value end
bomb:OnSpellStart()
assert_equal(killed[normal], nil, "bomb defers kills beyond spell stack")
assert_equal(bomb.activated, false, "bomb disables repeat casts")
assert_equal(#scheduled, 1, "bomb uses one shared batch task")
assert_equal(scheduled[1].delay, 0.05, "bomb uses configured interval")
assert_equal(scheduled[1].callback(), 0.05, "first batch continues")
assert_equal(killed[normal], 1, "bomb kills first normal monster")
alive[normal_two] = false
assert_equal(scheduled[1].callback(), false, "final batch completes")
assert_equal(killed[normal_two], nil, "bomb skips stale target")
assert_equal(killed[boss], nil, "bomb excludes boss")
assert_equal(killed[wave_leader], nil, "bomb excludes wave leader")
assert_equal(killed[assault_boss], nil, "bomb excludes assault boss")
assert_equal(killed[proxy], nil, "bomb excludes unrelated enemy")
assert_equal(removed, 1, "bomb removes item after batches")
bomb:OnSpellStart()
assert_equal(#scheduled, 1, "bomb rejects repeat cast")

print("ROGUE_REWARDS_08_18_LUA51_PASS")