-- Run from the addon root. Uses production skill configuration, event bus,
-- scheduler, hero skill system and UI request adapter with engine-only stubs.
package.path = "scripts/vscripts/?.lua;" .. package.path

local bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")
local definitions = require("config/generated/hero_skill_definitions")
local passives = require("config/hero_passive_skill_definitions")
local time, next_entity = 0, 1000
GameRules = { GetGameTime = function() return time end }
local published, listeners, sent = {}, {}, {}
CustomNetTables = { SetTableValue = function(_, table_name, key, value)
    assert(table_name == "survival_hero_skills")
    published[#published + 1] = { key = key, value = value }
end }
PlayerResource = {
    IsValidPlayerID = function(_, player_id) return player_id == 0 or player_id == 1 end,
    GetPlayer = function(_, player_id) return { player_id = player_id } end,
}
CustomGameEventManager = {
    RegisterListener = function(_, name, callback)
        assert(listeners[name] == nil, "listener registered twice: " .. name)
        listeners[name] = callback
    end,
    Send_ServerToPlayer = function(_, player, name, payload)
        sent[#sent + 1] = { player_id = player.player_id, name = name, payload = payload }
    end,
}

local function hero()
    next_entity = next_entity + 1
    local unit = { index = next_entity, abilities = {}, slots = {}, health = 400,
        add_count = 0, remove_count = 0, writes = 0 }
    function unit:IsNull() return self.removed == true end
    function unit:IsAlive() return true end
    function unit:entindex() return self.index end
    function unit:GetHealth() return self.health end
    function unit:GetMaxHealth() return 1000 end
    function unit:SetHealth(value) self.health = value; self.writes = self.writes + 1 end
    function unit:GetAbilityCount() return #self.slots end
    function unit:GetAbilityByIndex(index) return self.slots[index + 1] end
    function unit:FindAbilityByName(name) return self.abilities[name] end
    function unit:SetAbilityPoints(value)
        assert(value == 0, "native hero-level skill points must stay disabled")
        self.writes = self.writes + 1
    end
    function unit:CalculateStatBonus() self.writes = self.writes + 1 end
    function unit:RemoveAbility(name)
        self.remove_count = self.remove_count + 1
        local ability = self.abilities[name]
        self.abilities[name] = nil
        for index, item in ipairs(self.slots) do
            if item == ability then table.remove(self.slots, index); break end
        end
    end
    function unit:AddAbility(name)
        assert(not self.abilities[name])
        self.add_count = self.add_count + 1
        next_entity = next_entity + 1
        local ability = { name = name, index = next_entity, level = 0, cooldown = 0 }
        function ability:IsNull() return false end
        function ability:GetAbilityName() return self.name end
        function ability:entindex() return self.index end
        function ability:GetCooldownTimeRemaining() return self.cooldown end
        function ability:StartCooldown(value) self.cooldown = value end
        function ability:SetLevel(value)
            unit.writes = unit.writes + 1
            self.level = value
            if unit.fail_level_once == self.name then
                unit.fail_level_once = nil
                error("injected_engine_level_sync_failure")
            end
        end
        function ability:SetHidden(value) self.hidden = value; unit.writes = unit.writes + 1 end
        function ability:SetActivated(value) self.active = value; unit.writes = unit.writes + 1 end
        function ability:IsActivated() return self.active end
        unit.abilities[name], unit.slots[#unit.slots + 1] = ability, ability
        return ability
    end
    return unit
end

local function request(name, payload)
    local result, error_message = bus.request(name, payload)
    assert(result, "request failed: " .. tostring(error_message))
    return result
end
local function snapshot(player_id)
    local result = request(events.HERO_SKILL_STATE_GET_REQUEST, { player_id = player_id or 0 })
    assert(result.ok)
    return result.snapshot
end
local function item(skill_id, player_id)
    for _, row in ipairs(snapshot(player_id).skills) do
        if row.skill_id == skill_id then return row end
    end
    return nil
end
local function points(amount, player_id)
    assert(request(events.HERO_SKILL_POINT_SET_REQUEST, {
        player_id = player_id or 0, points = amount,
    }).ok)
end
local function grant(skill_id, amount)
    local result = request(events.HERO_SKILL_GRANT_REQUEST, {
        player_id = 0, skill_id = skill_id, levels = amount or 1,
    })
    assert(result.ok, tostring(result.error))
end
local function send_upgrade(payload)
    local before = #sent
    listeners.ui_hero_skill_upgrade_request(nil, payload)
    assert(#sent == before + 1, "upgrade must send one response")
    assert(sent[#sent].name == "ui_hero_skill_upgrade_result")
    assert(sent[#sent].payload.request_id == tostring(payload.request_id or ""))
    return sent[#sent].payload
end

bus.reset(); scheduler.clear()
require("systems/hero_skill_system").init()
require("ui/hero_skill_ui_service").init()
assert(listeners.ui_hero_skill_upgrade_request and listeners.ui_hero_skill_choice_select)
assert(not listeners.ui_hero_skill_state_request and not listeners.ui_hero_skill_state,
    "retired passive management window must not register state requests")
local own_hero, other_hero = hero(), hero()
bus.emit(events.HERO_SUMMONED, { player_id = 0, hero_id = "hero_axe", unit = own_hero })
bus.emit(events.HERO_SUMMONED, { player_id = 1, hero_id = "hero_doom", unit = other_hero })
time = 0.04; scheduler.think()
time = 0.40; scheduler.think()
assert(snapshot().hero_ready == 1 and snapshot().unit_entindex == own_hero:entindex())
assert(snapshot(1).unit_entindex == other_hero:entindex())

local skill_id = "proto_flame_burst"
local another_skill = "proto_frost_nova"
assert(definitions.by_id[skill_id].is_public == true)
assert(passives.by_id[skill_id].max_level > 2)
grant(skill_id)
assert(item(skill_id).level == 1 and item(skill_id).can_upgrade == 0)
points(4)
assert(item(skill_id).can_upgrade == 1, "owned public passive with points needs the plus flag")
local locked = assert(item("skill_axe_counter_helix"))
assert(locked.locked == 1 and locked.can_upgrade == 0, "rebirth exclusive stays locked")

local function current_payload()
    return { PlayerID = 0, unit_entindex = own_hero:entindex(), skill_id = skill_id,
        expected_level = item(skill_id).level, request_id = "upgrade-test" }
end
local function engine_handles()
    local handles = {}
    for name, ability in pairs(own_hero.abilities) do handles[name] = ability end
    return handles, own_hero.add_count, own_hero.remove_count
end
local function same_handles(handles, adds, removes)
    assert(own_hero.add_count == adds and own_hero.remove_count == removes,
        "point upgrade must not rebuild the ability bar")
    for name, ability in pairs(handles) do
        assert(own_hero.abilities[name] == ability, "point upgrade replaced ability " .. name)
    end
end
local function fails_without_mutation(payload, expected_error)
    local before, writes, count = snapshot(), own_hero.writes, #published
    local current_level = item(skill_id).level
    local other_before = snapshot(1)
    local result = send_upgrade(payload)
    assert(not result.ok and result.error == expected_error,
        expected_error .. " expected; got " .. tostring(result.error))
    local after = snapshot()
    assert(after.skill_points == before.skill_points and after.version == before.version)
    assert(item(skill_id).level == current_level and own_hero.writes == writes)
    assert(#published == count, "rejected upgrade must not refresh the skill snapshot/UI")
    assert(snapshot(1).version == other_before.version and snapshot(1).skill_points == other_before.skill_points)
end

local handles, adds, removes = engine_handles()
local upgraded_ability = own_hero:FindAbilityByName(definitions.by_id[skill_id].ability_name)
upgraded_ability.cooldown = 7
local successful_request = current_payload()
local before = snapshot()
local result = send_upgrade(successful_request)
assert(result.ok and result.level == 2 and result.skill_points == 3)
assert(snapshot().skill_points == before.skill_points - 1 and snapshot().version == before.version + 1)
assert(item(skill_id).level == 2 and upgraded_ability.level == 2 and upgraded_ability.cooldown == 7)
assert(own_hero:GetHealth() == 400, "point upgrade may not refill health")
same_handles(handles, adds, removes)
fails_without_mutation(successful_request, "skill_level_changed")
successful_request.request_id = "same-level-different-request-id"
fails_without_mutation(successful_request, "skill_level_changed")

local invalid = current_payload(); invalid.unit_entindex = other_hero:entindex()
fails_without_mutation(invalid, "combat_hero_changed")
invalid = current_payload(); invalid.skill_id = another_skill; invalid.expected_level = 0
fails_without_mutation(invalid, "skill_not_owned")
assert(item(another_skill) == nil, "point request must not grant an unowned skill")
invalid = current_payload(); invalid.skill_id = "skill_axe_counter_helix"; invalid.expected_level = 0
fails_without_mutation(invalid, "public_pool_skill_invalid")
assert(item("skill_axe_counter_helix").locked == 1)
invalid = current_payload(); invalid.skill_id = "nonexistent_skill"
fails_without_mutation(invalid, "public_pool_skill_invalid")
invalid = current_payload(); invalid.expected_level = nil
fails_without_mutation(invalid, "skill_request_invalid")
invalid = current_payload(); invalid.unit_entindex = nil
fails_without_mutation(invalid, "skill_request_invalid")
invalid = current_payload(); invalid.expected_level = "not-a-number"
fails_without_mutation(invalid, "skill_request_invalid")

points(0)
assert(item(skill_id).can_upgrade == 0)
fails_without_mutation(current_payload(), "skill_points_insufficient")
points(3)
handles, adds, removes = engine_handles()
before = snapshot()
local published_before = #published
own_hero.fail_level_once = definitions.by_id[skill_id].ability_name
result = send_upgrade(current_payload())
assert(not result.ok and result.error == "skill_sync_failed")
assert(snapshot().skill_points == before.skill_points and snapshot().version == before.version)
assert(item(skill_id).level == 2 and upgraded_ability.level == 2,
    "engine mutation preceding sync failure must roll back with point/level state")
assert(#published == published_before, "failed transaction must not publish success state")
assert(item(skill_id).can_upgrade == 1, "rolled-back point must remain usable")
same_handles(handles, adds, removes)
result = send_upgrade(current_payload())
assert(result.ok and result.level == 3 and result.skill_points == 2)
same_handles(handles, adds, removes)

grant(skill_id, passives.by_id[skill_id].max_level)
assert(item(skill_id).is_max_level == 1 and item(skill_id).can_upgrade == 0)
fails_without_mutation(current_payload(), "skill_already_max")

-- Invalid client player IDs cannot issue a business request or receive data.
local sent_before, version = #sent, snapshot().version
listeners.ui_hero_skill_upgrade_request(nil, { PlayerID = 99, unit_entindex = own_hero:entindex(),
    skill_id = skill_id, expected_level = 5 })
assert(#sent == sent_before and snapshot().version == version)

-- Retire only the management window: reward choice transport remains available.
local choice_request
bus.handle_request(events.HERO_SKILL_CHOICE_SELECT_REQUEST, function(payload)
    choice_request = payload
    return { ok = true, skill_id = payload.skill_id }
end)
listeners.ui_hero_skill_choice_select(nil, { PlayerID = 0, choice_token = "fixture-token", skill_id = another_skill })
assert(choice_request.player_id == 0 and choice_request.choice_token == "fixture-token")
assert(sent[#sent].name == "ui_hero_skill_choice_result" and sent[#sent].payload.ok)
bus.emit(events.HERO_SKILL_CHOICE_CHANGED, { player_id = 0, choice_token = "fixture-next", choices = {} })
assert(sent[#sent].name == "ui_hero_skill_choice")
for _, message in ipairs(sent) do
    assert(message.name ~= "ui_hero_skill_state", "old management UI still receives pushed state")
end

print("HERO_SKILL_POINT_UPGRADE_PASS: plus projection, bound hero/expected-level requests, single point spending, duplicate rejection, locked/unowned/max/no-point rejection, rollback, stable ability instances, retired management UI and preserved choices")
