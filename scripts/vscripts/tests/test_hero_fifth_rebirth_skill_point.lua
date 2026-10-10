-- Run from the addon root with Lua 5.1+. Exercises the CSV-generated rewards,
-- encounter reward dispatcher, progression, skill pool/choice and HUD adapter.
-- Only Dota engine APIs are stubbed; no skill or reward handler is replaced.
package.path = "scripts/vscripts/?.lua;" .. package.path

local bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")
local definitions = require("config/generated/hero_skill_definitions")
local reward_effects = require("config/generated/reward_effects")
local now, serial = 0, 1000
local tables, publications, listeners, sent = {}, {}, {}, {}
local rewards, choice_changes = {}, { [0] = 0, [1] = 0 }
local original_print = print
print = function(message, ...)
    assert(not tostring(message):find("handler error", 1, true), message)
    assert(not tostring(message):find("task failed", 1, true), message)
    original_print(message, ...)
end
GameRules = { GetGameTime = function() return now end }
RandomFloat = function() return 0 end
CustomNetTables = { SetTableValue = function(_, name, key, value)
    assert(name == "survival_hero_skills" or name == "survival_hero_skill_choice")
    tables[name] = tables[name] or {}
    tables[name][key] = value
    publications[#publications + 1] = { name = name, key = key, value = value }
end }
PlayerResource = {
    IsValidPlayerID = function(_, player_id) return player_id == 0 or player_id == 1 end,
    GetPlayer = function(_, player_id) return { player_id = player_id } end,
}
CustomGameEventManager = {
    RegisterListener = function(_, name, callback)
        assert(listeners[name] == nil, "duplicate listener: " .. name)
        listeners[name] = callback
    end,
    Send_ServerToPlayer = function(_, player, name, payload)
        sent[#sent + 1] = { player_id = player.player_id, name = name, payload = payload }
    end,
}

local function hero()
    serial = serial + 1
    local unit = { index = serial, abilities = {}, slots = {}, health = 400 }
    function unit:IsNull() return false end
    function unit:IsAlive() return true end
    function unit:entindex() return self.index end
    function unit:GetHealth() return self.health end
    function unit:GetMaxHealth() return 1000 end
    function unit:SetHealth(value) self.health = value end
    function unit:GetAbilityCount() return #self.slots end
    function unit:GetAbilityByIndex(index) return self.slots[index + 1] end
    function unit:FindAbilityByName(name) return self.abilities[name] end
    function unit:SetAbilityPoints(value)
        assert(value == 0, "rebirth points must not re-enable native hero leveling")
    end
    function unit:CalculateStatBonus() end
    function unit:RemoveAbility(name)
        local ability = self.abilities[name]
        self.abilities[name] = nil
        for index, current in ipairs(self.slots) do
            if current == ability then table.remove(self.slots, index); break end
        end
    end
    function unit:AddAbility(name)
        assert(self.abilities[name] == nil)
        serial = serial + 1
        local ability = { name = name, index = serial, level = 0, cooldown = 0 }
        function ability:IsNull() return false end
        function ability:entindex() return self.index end
        function ability:GetAbilityName() return self.name end
        function ability:GetCooldownTimeRemaining() return self.cooldown end
        function ability:StartCooldown(value) self.cooldown = value end
        function ability:SetLevel(value) self.level = value end
        function ability:SetHidden(value) self.hidden = value end
        function ability:SetActivated(value) self.active = value end
        function ability:IsActivated() return self.active end
        self.abilities[name], self.slots[#self.slots + 1] = ability, ability
        return ability
    end
    return unit
end

local function request(name, payload)
    local result, error_message = bus.request(name, payload)
    assert(result, "request failed: " .. tostring(error_message))
    assert(result.ok, tostring(result.error))
    return result
end
local function snapshot(player_id)
    return request(events.HERO_SKILL_STATE_GET_REQUEST, { player_id = player_id }).snapshot
end
local function progression(player_id)
    return request(events.HERO_PROGRESSION_GET_REQUEST, { player_id = player_id }).snapshot
end
local function choice(player_id)
    return request(events.HERO_SKILL_CHOICE_GET_REQUEST, { player_id = player_id }).snapshot
end
local function item(player_id, skill_id)
    for _, row in ipairs(snapshot(player_id).skills) do
        if row.skill_id == skill_id then return row end
    end
    error("missing skill: " .. skill_id)
end
local function unchanged(player_id, before)
    local after = snapshot(player_id)
    assert(after.version == before.version and after.skill_points == before.skill_points
        and after.public_skill_count == before.public_skill_count,
        "another player's rebirth/upgrade changed this player's skill state")
    for _, row in ipairs(before.skills) do
        assert(item(player_id, row.skill_id).level == row.level)
    end
end

bus.reset(); scheduler.clear()
require("systems/hero_progression_system").init()
require("systems/hero_skill_system").init()
require("systems/hero_skill_pool_service").init()
require("systems/hero_skill_choice_service").init()
require("systems/monster_reward_service").init()
require("ui/hero_skill_ui_service").init()
bus.subscribe(events.MONSTER_REWARD_GRANTED, function(payload)
    rewards[payload.player_id] = payload
end)
bus.subscribe(events.HERO_SKILL_CHOICE_CHANGED, function(payload)
    choice_changes[payload.player_id] = choice_changes[payload.player_id] + 1
end)

local own_hero, other_hero = hero(), hero()
for player_id, unit in pairs({ [0] = own_hero, [1] = other_hero }) do
    bus.emit(events.HERO_READY, { player_id = player_id, hero = unit })
    bus.emit(events.HERO_SUMMONED, {
        player_id = player_id, hero_id = player_id == 0 and "hero_axe" or "hero_doom", unit = unit,
    })
end
now = 0.04; scheduler.think()
now = 0.40; scheduler.think()
assert(snapshot(0).hero_ready == 1 and snapshot(0).unit_entindex == own_hero:entindex())
assert(snapshot(1).hero_ready == 1 and snapshot(1).unit_entindex == other_hero:entindex())

local function complete(player_id, level)
    local profile_id = string.format("reward_rebirth_%02d", level)
    -- The real completion subscriber dispatches all enabled generated effects.
    -- Home teleport is outside this regression; omit its encounter_id field.
    bus.emit(events.MONSTER_ENCOUNTER_COMPLETED, {
        player_id = player_id, reward_profile_id = profile_id,
        reward_transaction_id = "fifth-rebirth-test:" .. player_id .. ":" .. level,
    })
    local reward = assert(rewards[player_id], "completion did not dispatch a reward")
    assert(reward.ok and reward.reward_profile_id == profile_id)
    local expected_count, attributes, attack_gain = 0, 0, 0
    for _, effect in ipairs(reward_effects.rows) do
        if effect.reward_profile_id == profile_id and effect.enabled ~= false then
            expected_count = expected_count + 1
            if effect.effect_type == "add_all_attributes" then attributes = effect.value end
            if effect.effect_type == "add_attack_all_attribute_gain" then attack_gain = effect.value end
        end
    end
    assert(#reward.effects == expected_count, "completion dropped configured reward effects")
    for index = 2, #reward.effects do
        assert(reward.effects[index - 1].sort_order <= reward.effects[index].sort_order)
    end
    assert(progression(player_id).rebirth_level == level)
    return attributes, attack_gain
end

complete(0, 1)
complete(1, 1)
local exclusive_id = "skill_axe_counter_helix"
assert(item(0, exclusive_id).level == 1 and item(0, exclusive_id).locked == 0)
local isolated = snapshot(1)
local owned_public = {}
for level = 2, 4 do
    complete(0, level)
    local offered = choice(0)
    assert(offered.pending == 1 and #offered.candidates == 3,
        "second through fourth rebirth must offer three new public skills")
    local selected = offered.candidates[1].skill_id
    assert(definitions.by_id[selected].is_public == true and not owned_public[selected])
    listeners.ui_hero_skill_choice_select(nil, {
        PlayerID = 0, choice_token = offered.choice_token, skill_id = selected,
    })
    assert(sent[#sent].name == "ui_hero_skill_choice_result" and sent[#sent].payload.ok)
    owned_public[selected] = true
    assert(choice(0).pending == 0 and snapshot(0).public_skill_count == level - 1)
    assert(item(0, selected).level == 1 and item(0, selected).can_upgrade == 0)
    unchanged(1, isolated)
end
assert(snapshot(0).public_skill_count == 3 and snapshot(0).skill_points == 0)

local before_fifth, progression_before = snapshot(0), progression(0)
local choices_before, published_before = choice_changes[0], #publications
local attributes, attack_gain = complete(0, 5)
local fifth = snapshot(0)
assert(fifth.skill_points == 1,
    "fifth rebirth must grant the first public skill point after the three public slots are full")
assert(fifth.public_skill_count == 3 and fifth.version > before_fifth.version)
assert(choice(0).pending == 0 and choice_changes[0] == choices_before,
    "fifth rebirth must not create or publish another choice")
assert(progression(0).all_attributes == progression_before.all_attributes + attributes)
assert(progression(0).attack_all_attribute_gain == progression_before.attack_all_attribute_gain + attack_gain)
assert(#publications > published_before, "fifth point must refresh the HUD skill snapshot")
local published_fifth = assert(tables.survival_hero_skills.player_0)
assert(published_fifth.skill_points == 1 and published_fifth.version == fifth.version)
local upgrade_id
for skill_id in pairs(owned_public) do
    local row = item(0, skill_id)
    assert(row.level == 1 and row.can_upgrade == 1,
        "fifth rebirth's point must expose the upgrade button on each owned public skill")
    upgrade_id = upgrade_id or skill_id
end
assert(item(0, exclusive_id).level == 1 and item(0, exclusive_id).can_upgrade == 0)
unchanged(1, isolated)

local function upgrade(skill_id, request_id)
    local sent_before = #sent
    listeners.ui_hero_skill_upgrade_request(nil, {
        PlayerID = 0, unit_entindex = own_hero:entindex(), skill_id = skill_id,
        expected_level = item(0, skill_id).level, request_id = request_id,
    })
    assert(#sent == sent_before + 1 and sent[#sent].name == "ui_hero_skill_upgrade_result")
    assert(sent[#sent].player_id == 0 and sent[#sent].payload.request_id == request_id)
    return sent[#sent].payload
end
local rejected = upgrade(exclusive_id, "exclusive-cannot-spend-fifth-point")
assert(not rejected.ok and rejected.error == "public_pool_skill_invalid")
assert(snapshot(0).skill_points == 1 and snapshot(0).version == fifth.version)
assert(item(0, exclusive_id).level == 1)
local upgraded = upgrade(upgrade_id, "spend-fifth-point")
assert(upgraded.ok and upgraded.level == 2 and upgraded.skill_points == 0)
assert(snapshot(0).version == fifth.version + 1 and snapshot(0).public_skill_count == 3)
assert(own_hero:FindAbilityByName(definitions.by_id[upgrade_id].ability_name).level == 2)
for skill_id in pairs(owned_public) do
    local row = item(0, skill_id)
    assert(row.level == (skill_id == upgrade_id and 2 or 1) and row.can_upgrade == 0)
end
assert(item(0, exclusive_id).level == 1 and own_hero.health == 400)
unchanged(1, isolated)

complete(0, 6)
assert(snapshot(0).skill_points == 1 and snapshot(0).public_skill_count == 3,
    "sixth rebirth must continue granting one point")
assert(item(0, upgrade_id).level == 2 and item(0, upgrade_id).can_upgrade == 1)
assert(item(0, exclusive_id).level == 1 and choice_changes[0] == choices_before)
unchanged(1, isolated)

-- This player's empty public slots keep capacity from masking an obsolete
-- fifth-rebirth choice rule. The rule itself must stop at rebirth four.
local forbidden_offer = bus.request(events.HERO_SKILL_CHOICE_CREATE_REQUEST, {
    player_id = 1, trigger_level = 5, source = "fifth-rule-regression",
})
assert(forbidden_offer and not forbidden_offer.ok
    and forbidden_offer.error == "skill_choice_rule_missing",
    "fifth rebirth must be outside the new-skill choice rule even with free slots")
local own_before_other_reward = snapshot(0)
local other_choices_before = choice_changes[1]
complete(1, 5)
assert(snapshot(1).skill_points == 1 and snapshot(1).public_skill_count == 0)
assert(choice(1).pending == 0 and choice_changes[1] == other_choices_before)
assert(item(1, "skill_doom_infernal").level == 1
    and item(1, "skill_doom_infernal").can_upgrade == 0)
unchanged(0, own_before_other_reward)
complete(1, 6)
assert(snapshot(1).skill_points == 2 and choice(1).pending == 0)
unchanged(0, own_before_other_reward)

print("HERO_FIFTH_REBIRTH_SKILL_POINT_PASS: real completion/CSV rewards, three public choices, fifth point and HUD upgrade flags, public-only single-point spending, sixth point and player isolation")
