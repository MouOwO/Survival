package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path

local event_bus = require("core/event_bus")
local events = require("core/events")

local next_ability_id = 1

local function new_ability(name, cooldown)
    local value = {
        id = next_ability_id,
        name = name,
        index = -1,
        cooldown = cooldown or 0,
    }
    next_ability_id = next_ability_id + 1
    function value:GetAbilityName() return self.name end
    function value:SetLevel(level) self.level = level end
    function value:SetHidden(hidden) self.hidden = hidden end
    function value:SetActivated(active) self.active = active end
    function value:GetCooldownTimeRemaining() return self.cooldown end
    function value:EndCooldown() self.cooldown = 0 end
    function value:StartCooldown(remaining) self.cooldown = remaining end
    return value
end

local builder = {
    slots = {},
    modifiers = {},
    add_count = 0,
    remove_count = 0,
    reject_index_change = true,
    set_index_count = 0,
    invalid_index_reads = 0,
}
function builder:IsNull() return false end
function builder:entindex() return 301 end
function builder:GetAbilityCount()
    local maximum = -1
    for index, _ in pairs(self.slots) do maximum = math.max(maximum, index) end
    return maximum + 1
end
function builder:GetAbilityByIndex(index)
    if index < 0 or index >= self:GetAbilityCount() then
        self.invalid_index_reads = self.invalid_index_reads + 1
        return nil
    end
    return self.slots[index]
end
function builder:FindAbilityByName(name)
    for index = 0, 63 do
        local value = self.slots[index]
        if value and value.name == name then return value end
    end
    return nil
end
function builder:AddAbility(name)
    local value = new_ability(name)
    value.owner = self
    function value:SetAbilityIndex(index)
        self.owner.set_index_count = self.owner.set_index_count + 1
        if self.owner.reject_index_change then return end
        if self.index == index then return end
        if self.owner.slots[index] then return end
        if self.index >= 0 then self.owner.slots[self.index] = nil end
        self.index = index
        self.owner.slots[index] = self
    end
    local index = 0
    while self.slots[index] do index = index + 1 end
    value.index = index
    self.slots[index] = value
    self.add_count = self.add_count + 1
    return value
end
function builder:InjectAbility(name, index, cooldown)
    assert(not self.slots[index], "test slot already occupied")
    local value = new_ability(name, cooldown)
    value.owner = self
    function value:SetAbilityIndex(next_index)
        if self.index == next_index or self.owner.slots[next_index] then return end
        self.owner.slots[self.index] = nil
        self.index = next_index
        self.owner.slots[next_index] = self
    end
    value.index = index
    self.slots[index] = value
    return value
end
function builder:RemoveAbility(name)
    for index = 0, 63 do
        local value = self.slots[index]
        if value and value.name == name then
            self.slots[index] = nil
            self.remove_count = self.remove_count + 1
            return
        end
    end
end
function builder:HasModifier(name) return self.modifiers[name] == true end
function builder:AddNewModifier(caster, source, name) self.modifiers[name] = true end

local function ability_at(index, name)
    local value = builder.slots[index]
    assert(value and value.name == name,
        name .. " must occupy engine index " .. tostring(index))
    return value
end

local function count_named(name)
    local result = 0
    for _, value in pairs(builder.slots) do
        if value.name == name then result = result + 1 end
    end
    return result
end

event_bus.reset()
local rogue_consumed = false
event_bus.handle_request(events.BUILDING_LIST_REQUEST, function()
    return { buildings = {} }
end)
event_bus.handle_request(events.ROGUE_REWARD_CONSUMED_GET_REQUEST, function()
    return rogue_consumed
end)
local progression = require("systems/builder_progression_system")
progression.init()
local unmanaged = builder:InjectAbility("ability_unmanaged_builder_intrinsic", 0, 0)
event_bus.emit(events.BUILDER_READY, {
    builder = builder,
    player_id = 0,
    team = 2,
})

local initial_wall = builder:FindAbilityByName("ability_build_wall")
local initial_rogue = builder:FindAbilityByName("ability_survival_rogue_reward")
local initial_blink = builder:FindAbilityByName("ability_survival_builder_blink")
assert(initial_wall and initial_wall.level == 1
        and initial_wall.hidden == false and initial_wall.active == true,
    "wall must stay enabled when the engine rejects immediate slot reassignment")
assert(initial_blink and initial_blink.level == 1
        and initial_blink.hidden == false and initial_blink.active == true,
    "blink must stay enabled in the natural tail slot")
assert(initial_rogue and initial_rogue.level == 1
        and initial_rogue.hidden == false and initial_rogue.active == true,
    "the one-shot rogue reward must be visible and active at game start")
assert(ability_at(0, "ability_unmanaged_builder_intrinsic") == unmanaged,
    "the non-managed prefix ability must be preserved")
ability_at(8, "ability_survival_rogue_reward")
for index = 2, 6 do
    local placeholder = ability_at(
        index,
        "ability_survival_builder_slot_" .. tostring(index) .. "_placeholder"
    )
    assert(placeholder.hidden == true and placeholder.active == false,
        "unused builder slots must remain hidden and inactive")
end
assert(builder.set_index_count == 0,
    "builder synchronization must not depend on SetAbilityIndex")

builder.reject_index_change = false
event_bus.emit(events.BUILDING_CHANGED, {
    team = 2,
    building_id = "main_city",
    level = 0,
})
ability_at(1, "ability_build_wall")
ability_at(8, "ability_survival_rogue_reward")
ability_at(7, "ability_survival_builder_blink")

event_bus.emit(events.BUILDING_CREATED, {
    team = 2,
    building_id = "wall",
    level = 1,
})
assert(ability_at(8, "ability_survival_rogue_reward") == initial_rogue,
    "wall stage refresh must preserve the unconsumed G reward instance")
assert(builder:FindAbilityByName("ability_build_wall") == nil,
    "wall ability must be removed after stage change")
ability_at(1, "ability_build_main_city")
ability_at(7, "ability_survival_builder_blink")

rogue_consumed = true
event_bus.emit(events.ROGUE_REWARD_CHANGED, {
    player_id = 0,
    reason = "builder_consumed",
})
assert(builder:FindAbilityByName("ability_survival_rogue_reward") == nil,
    "consumed rogue reward ability must be removed permanently")
local consumed_placeholder = ability_at(2, "ability_survival_builder_slot_2_placeholder")
assert(consumed_placeholder.hidden == true and consumed_placeholder.active == false,
    "the independent G reward must not replace the W-slot placeholder")
event_bus.emit(events.BUILDING_CHANGED, {
    team = 2,
    building_id = "main_city",
    level = 0,
})
assert(builder:FindAbilityByName("ability_survival_rogue_reward") == nil,
    "later builder synchronization must not restore the consumed reward")
ability_at(2, "ability_survival_builder_slot_2_placeholder")

ability_at(1, "ability_build_main_city")
ability_at(7, "ability_survival_builder_blink")

event_bus.emit(events.BUILDING_CREATED, {
    team = 2,
    building_id = "main_city",
    level = 1,
})
ability_at(1, "ability_build_arrow_tower")
ability_at(2, "ability_build_research_lab")
local farm = ability_at(3, "ability_build_farm")
ability_at(4, "ability_build_hero_altar")
ability_at(5, "ability_build_gold_mine")
ability_at(7, "ability_survival_builder_blink")

event_bus.emit(events.BUILDING_CREATED, {
    team = 2,
    building_id = "building_farm",
    level = 1,
})
assert(builder:FindAbilityByName("ability_build_farm") == nil,
    "a building ability must be replaced at its count limit")
ability_at(3, "ability_survival_builder_slot_3_placeholder")
event_bus.emit(events.BUILDING_DESTROYED, {
    team = 2,
    building_id = "building_farm",
})
assert(ability_at(3, "ability_build_farm") ~= farm,
    "releasing a building limit must restore the managed ability")

event_bus.emit(events.BUILDING_CREATED, {
    team = 2,
    building_id = "building_research_lab",
    level = 1,
})
ability_at(1, "ability_build_arrow_tower")
local advanced = ability_at(2, "ability_build_advanced_research_lab")
ability_at(3, "ability_build_farm")
ability_at(4, "ability_build_hero_altar")
ability_at(5, "ability_build_gold_mine")
local challenge = ability_at(6, "ability_build_challenge")
local blink = ability_at(7, "ability_survival_builder_blink")
assert(advanced.active == false,
    "advanced lab must remain disabled below main city level 4")

event_bus.emit(events.BUILDING_CHANGED, {
    team = 2,
    building_id = "main_city",
    level = 4,
})
assert(ability_at(2, "ability_build_advanced_research_lab") == advanced,
    "correct layout must preserve the advanced lab entity")
assert(ability_at(6, "ability_build_challenge") == challenge,
    "correct layout must preserve the challenge entity")
assert(ability_at(7, "ability_survival_builder_blink") == blink,
    "correct layout must preserve the blink entity")
assert(advanced.active == true,
    "advanced lab must activate at main city level 4")

challenge.cooldown = 7.25
blink.cooldown = 3.5
builder:InjectAbility("ability_build_challenge", 9, 2.0)
builder:InjectAbility("ability_build_wall", 8, 0)
builder.slots[5], builder.slots[10] = nil, builder.slots[5]
builder.slots[10].index = 10
local add_before_repair = builder.add_count
event_bus.emit(events.BUILDING_CHANGED, {
    team = 2,
    building_id = "main_city",
    level = 4,
})
assert(ability_at(0, "ability_unmanaged_builder_intrinsic") == unmanaged,
    "layout repair must preserve the non-managed ability instance")
ability_at(1, "ability_build_arrow_tower")
ability_at(2, "ability_build_advanced_research_lab")
ability_at(3, "ability_build_farm")
ability_at(4, "ability_build_hero_altar")
local repaired_gold = ability_at(5, "ability_build_gold_mine")
local repaired_challenge = ability_at(6, "ability_build_challenge")
local repaired_blink = ability_at(7, "ability_survival_builder_blink")
assert(count_named("ability_build_challenge") == 1,
    "duplicate challenge instances must be removed")
assert(count_named("ability_build_wall") == 0,
    "stale managed abilities must be removed")
assert(repaired_challenge.cooldown == 7.25,
    "rebuild must preserve the longest remaining challenge cooldown")
assert(repaired_blink.cooldown == 3.5,
    "rebuild must preserve blink cooldown")
assert(repaired_gold.index == 5, "misordered ability must return to its relative CSV slot")
assert(builder.add_count > add_before_repair, "invalid layout must be rebuilt")

local add_after_repair = builder.add_count
local remove_after_repair = builder.remove_count
event_bus.emit(events.BUILDING_CHANGED, {
    team = 2,
    building_id = "main_city",
    level = 4,
})
assert(builder.add_count == add_after_repair and builder.remove_count == remove_after_repair,
    "an already correct layout must be idempotent")
assert(ability_at(6, "ability_build_challenge") == repaired_challenge,
    "idempotent sync must preserve repaired challenge entity")
assert(ability_at(7, "ability_survival_builder_blink") == repaired_blink,
    "idempotent sync must preserve repaired blink entity")
assert(builder.set_index_count == 0,
    "later synchronization must preserve natural-slot construction")
assert(builder.invalid_index_reads == 0,
    "builder synchronization must never read beyond GetAbilityCount")

print("BUILDER_ABILITY_SLOTS_LUA51_PASS")
