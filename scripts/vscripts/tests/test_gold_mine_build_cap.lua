package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;"
    .. package.path

local events = require("core/events")
local gold_mine_build_cap = 6
local subscribers = {}
local existing_buildings = {}

package.loaded["core/event_bus"] = {
    emit = function(event_name, payload)
        for _, handler in ipairs(subscribers[event_name] or {}) do
            handler(payload)
        end
    end,
    subscribe = function(event_name, handler)
        subscribers[event_name] = subscribers[event_name] or {}
        subscribers[event_name][#subscribers[event_name] + 1] = handler
    end,
    handle_request = function() end,
    request = function(event_name, payload)
        if event_name == events.PERMANENT_REWARD_EFFECTS_GET_REQUEST then
            assert(payload and payload.player_id == 0,
                "gold mine capacity query used the wrong player")
            return {
                ok = true,
                totals = { gold_mine_build_cap = gold_mine_build_cap },
            }
        end
        if event_name == events.BUILDING_LIST_REQUEST then
            return { ok = true, buildings = existing_buildings }
        end
        if event_name == events.ROGUE_REWARD_CONSUMED_GET_REQUEST then
            return true
        end
        return nil
    end,
}

package.loaded["systems/building_count_limit_service"] = nil
local limits = require("systems/building_count_limit_service")

assert(limits.maximum(5, "gold_mine", 0) == 11,
    "gold_mine_build_cap=6 must expand the base capacity 5 to 11")
assert(not limits.reached(5, 10, "gold_mine", 0),
    "the eleventh gold-mine slot must remain available")
assert(limits.reached(5, 11, "gold_mine", 0),
    "the twelfth gold-mine request must be rejected")
assert(limits.maximum(7, "arrow_tower", 0) == 7,
    "gold-mine capacity must not affect other buildings")

-- This test only exercises the Builder's construction branch. Avoid loading
-- route visuals so unrelated asset-catalog work cannot affect this contract.
package.loaded["config/tower_route_config"] = {}
package.loaded["ui/ability_runtime_builder"] = nil
local runtime_builder = require("ui/ability_runtime_builder")
local state = {
    player_id = 0,
    city_level = 3,
    building_counts = { gold_mine = 10 },
}
local resources = {
    wood = 100000,
    gold = 100000,
    population = 0,
    population_cap = 100,
}
local runtime = runtime_builder.build(
    "ability_build_gold_mine", state, resources
)
assert(runtime.available == 1,
    "Builder runtime closed the gold-mine skill before base+expansion capacity")

state.building_counts.gold_mine = 11
runtime = runtime_builder.build("ability_build_gold_mine", state, resources)
assert(runtime.available == 0,
    "Builder runtime retained the gold-mine skill at base+expansion capacity")

local function fake_builder()
    local builder = { slots = {}, modifiers = {} }
    function builder:IsNull() return false end
    function builder:entindex() return 500 end
    function builder:GetAbilityCount()
        local maximum = -1
        for index in pairs(self.slots) do maximum = math.max(maximum, index) end
        return maximum + 1
    end
    function builder:GetAbilityByIndex(index) return self.slots[index] end
    function builder:FindAbilityByName(name)
        for _, ability in pairs(self.slots) do
            if ability.name == name then return ability end
        end
        return nil
    end
    function builder:AddAbility(name)
        local index = 0
        while self.slots[index] do index = index + 1 end
        local ability = { name = name }
        function ability:GetAbilityName() return self.name end
        function ability:SetLevel(value) self.level = value end
        function ability:SetHidden(value) self.hidden = value end
        function ability:SetActivated(value) self.active = value end
        function ability:GetCooldownTimeRemaining() return 0 end
        self.slots[index] = ability
        return ability
    end
    function builder:RemoveAbility(name)
        for index, ability in pairs(self.slots) do
            if ability.name == name then
                self.slots[index] = nil
                return
            end
        end
    end
    function builder:HasModifier(name) return self.modifiers[name] == true end
    function builder:AddNewModifier(_, _, name) self.modifiers[name] = true end
    return builder
end

existing_buildings = {
    { entindex = 1, player_id = 0, building_id = "wall", level = 1 },
    { entindex = 2, player_id = 0, building_id = "main_city", level = 3 },
}
for index = 1, 5 do
    existing_buildings[#existing_buildings + 1] = {
        entindex = 10 + index,
        player_id = 0,
        building_id = "gold_mine",
        level = 1,
    }
end

gold_mine_build_cap = 0
package.loaded["systems/builder_progression_system"] = nil
local progression = require("systems/builder_progression_system")
progression.init()
local builder = fake_builder()
for _, handler in ipairs(subscribers[events.BUILDER_READY] or {}) do
    handler({ builder = builder, player_id = 0, team = 2 })
end
assert(builder:FindAbilityByName("ability_build_gold_mine") == nil,
    "base capacity should close the skill at five gold mines")

gold_mine_build_cap = 6
for _, handler in ipairs(subscribers[events.PERMANENT_REWARD_EFFECTS_CHANGED] or {}) do
    handler({ player_id = 0 })
end
assert(builder:FindAbilityByName("ability_build_gold_mine") ~= nil,
    "capacity expansion did not immediately restore the Builder skill")

for index = 6, 11 do
    for _, handler in ipairs(subscribers[events.BUILDING_CREATED] or {}) do
        handler({
            entindex = 10 + index,
            player_id = 0,
            team = 2,
            building_id = "gold_mine",
            level = 1,
        })
    end
end
assert(builder:FindAbilityByName("ability_build_gold_mine") == nil,
    "Builder skill did not close at the expanded capacity of eleven")

print("GOLD_MINE_BUILD_CAP_LUA51_PASS")
