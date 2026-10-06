-- Exercise real rebirth rewards, skill grants and native ability activation.
-- Only Source 2 units/net tables and the progression boundary are mocked.
package.path = "scripts/vscripts/?.lua;" .. package.path
local bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")
local definitions = require("config/generated/hero_skill_definitions")
local rewards = require("config/generated/reward_effects")
local time, next_entity = 0, 1000
local rebirth = { [0] = 0, [1] = 0 }
GameRules = { GetGameTime = function() return time end }
CustomNetTables = { SetTableValue = function(_, name)
    assert(name == "survival_hero_skills" or name == "survival_hero_skill_choice")
end }
local function hero()
    next_entity = next_entity + 1
    local unit = { index = next_entity, abilities = {}, slots = {}, health = 400 }
    function unit:IsNull() return self.removed == true end
    function unit:IsAlive() return not self.removed end
    function unit:entindex() return self.index end
    function unit:GetHealth() return self.health end
    function unit:GetMaxHealth() return 1000 end
    function unit:SetHealth(value) self.health = value end
    function unit:GetAbilityCount() return #self.slots end
    function unit:GetAbilityByIndex(index) return self.slots[index + 1] end
    function unit:FindAbilityByName(name) return self.abilities[name] end
    function unit:SetAbilityPoints(value) assert(value == 0) end
    function unit:CalculateStatBonus() end
    function unit:RemoveAbility(name)
        local ability = self.abilities[name]
        self.abilities[name] = nil
        for index, item in ipairs(self.slots) do
            if item == ability then table.remove(self.slots, index); break end
        end
    end
    function unit:AddAbility(name)
        assert(not self.abilities[name])
        next_entity = next_entity + 1
        local ability = { name = name, index = next_entity, level = 0, cooldown = 0 }
        function ability:IsNull() return false end
        function ability:GetAbilityName() return self.name end
        function ability:entindex() return self.index end
        function ability:GetCooldownTimeRemaining() return self.cooldown end
        function ability:StartCooldown(value) self.cooldown = value end
        function ability:SetLevel(value) self.level = value end
        function ability:SetHidden(value) self.hidden = value end
        function ability:SetActivated(value) self.active = value end
        function ability:IsActivated() return self.active end
        unit.abilities[name], unit.slots[#unit.slots + 1] = ability, ability
        return ability
    end
    return unit
end
local function snapshot(player_id)
    local result, failure = bus.request(events.HERO_SKILL_STATE_GET_REQUEST, { player_id = player_id })
    assert(result and result.ok, tostring(failure))
    return result.snapshot
end
local gates = {
    { "skill_blademaster_exclusive", 1 },
    { "skill_blademaster_agility", 3 },
    { "skill_blademaster_swiftness", 6 },
    { "skill_blademaster_mobility", 10 },
}
local function check(unit, player_id, stage, expected_gates)
    local state = snapshot(player_id)
    assert(state.hero_ready == 1 and state.unit_entindex == unit:entindex())
    assert(#state.skills == 4, "rebirth must never grant another hero's exclusive skill")
    for index, gate in ipairs(expected_gates or gates) do
        local skill, unlocked = state.skills[index], stage >= gate[2]
        assert(skill.skill_id == gate[1], "fixed Q/W/E/R order changed")
        assert(skill.level == (unlocked and 1 or 0), gate[1] .. " activated at wrong rebirth")
        assert(skill.locked == (unlocked and 0 or 1))
        assert(skill.locked_reason == (unlocked and "" or "完成" .. gate[2] .. "转后激活"))
        local ability = unit:GetAbilityByIndex(index - 1)
        assert(ability == unit:FindAbilityByName(definitions.by_id[gate[1]].ability_name))
        assert(ability:IsActivated() == unlocked and ability.hidden == false)
        -- Locked native passives remain level one for their tooltip; activation
        -- and the real skill snapshot, rather than native level, gate gameplay.
        assert(ability.level == 1)
    end
    assert(unit.health == 400, "rebirth skill synchronization must not heal the hero")
end
local function reward(player_id, stage)
    rebirth[player_id] = stage
    local profile = string.format("reward_rebirth_%02d", stage)
    local dispatched = 0
    for _, effect in ipairs(rewards.rows) do
        if effect.enabled ~= false and effect.reward_profile_id == profile
            and effect.effect_type == "grant_exclusive_skill" then
            bus.emit(events.HERO_SKILL_REWARD_REQUEST, {
                player_id = player_id, effect = effect, trigger_level = stage,
            })
            dispatched = dispatched + 1
        end
    end
    if stage == 1 or stage == 3 or stage == 6 or stage == 10 then
        assert(dispatched > 0, "production rebirth reward is missing at " .. stage)
    end
end
local function advance(amount)
    time = time + amount
    scheduler.think()
end
bus.reset(); scheduler.clear()
bus.handle_request(events.HERO_PROGRESSION_GET_REQUEST, function(payload)
    return { ok = true, snapshot = { rebirth_level = rebirth[payload.player_id] } }
end)
require("systems/hero_skill_system").init()
require("systems/hero_skill_choice_service").init()
local own, other = hero(), hero()
bus.emit(events.HERO_SUMMONED, { player_id = 0, hero_id = "hero_blademaster", unit = own })
bus.emit(events.HERO_SUMMONED, { player_id = 1, hero_id = "hero_blademaster", unit = other })
advance(0.04); advance(0.4)
check(own, 0, 0); check(other, 1, 0)
local handles = {}
for name, ability in pairs(own.abilities) do handles[name] = ability end
for _, stage in ipairs({ 1, 2, 3, 5, 6, 9, 10 }) do
    reward(0, stage)
    check(own, 0, stage); check(other, 1, 0)
    reward(0, stage)
    check(own, 0, stage)
    for name, ability in pairs(handles) do
        assert(own.abilities[name] == ability, "rebirth must preserve ability handles/cooldowns")
    end
end
bus.emit(events.HERO_REMOVED, { player_id = 0, unit = own })
own.removed = true
assert(snapshot(0).hero_ready == 0)
local replacement = hero()
bus.emit(events.HERO_SUMMONED, { player_id = 0, hero_id = "hero_blademaster", unit = replacement })
advance(0.04); advance(0.4)
reward(0, 10)
check(replacement, 0, 10); check(other, 1, 0)
bus.emit(events.HERO_REMOVED, { player_id = 0, unit = own })
check(replacement, 0, 10)
-- The hero-specific reward must still grant Monkey King's own W/E/R.
bus.emit(events.HERO_REMOVED, { player_id = 1, unit = other })
other.removed = true
local monkey = hero()
local monkey_gates = {
    { "skill_monkey_king_exclusive", 1 },
    { "skill_monkey_king_fury", 3 },
    { "skill_monkey_king_swiftness", 6 },
    { "skill_monkey_king_agility", 10 },
}
bus.emit(events.HERO_SUMMONED, { player_id = 1, hero_id = "hero_monkey_king", unit = monkey })
advance(0.04); advance(0.4)
check(monkey, 1, 0, monkey_gates)
for _, stage in ipairs({ 1, 3, 6, 10 }) do
    reward(1, stage)
    check(monkey, 1, stage, monkey_gates)
    reward(1, stage)
    check(monkey, 1, stage, monkey_gates)
    check(replacement, 0, 10)
end
print("BLADEMASTER_REBIRTH_UNLOCK_PASS")
