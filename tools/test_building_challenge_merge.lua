package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path

local handlers = {}
local subscribers = {}
local scheduled = {}
local spawned = {}

package.preload["core/event_bus"] = function()
    return {
        handle_request = function(name, callback) handlers[name] = callback end,
        subscribe = function(name, callback)
            subscribers[name] = subscribers[name] or {}
            subscribers[name][#subscribers[name] + 1] = callback
        end,
        emit = function(name, payload)
            for _, callback in ipairs(subscribers[name] or {}) do callback(payload) end
        end,
        request = function(name)
            if name == "building.list.request" then
                return { ok = true, buildings = {
                    { building_id = "main_city", level = 5 },
                } }
            end
            if name == "monster.reward.grant.request" then return { ok = true } end
            local callback = handlers[name]
            return callback and callback({}) or nil
        end,
    }
end

package.preload["core/scheduler"] = function()
    return {
        cancel = function() end,
        every = function(_, callback, task_id) scheduled[task_id] = callback end,
    }
end

package.preload["systems/wave_system"] = function()
    return {
        spawn_challenge_monster = function(row, definition)
            local unit = {
                id = 800 + #spawned + 1,
                alive = true,
                challenge_id = definition.challenge_id,
                wave_number = row.wave_number,
            }
            function unit:IsNull() return false end
            function unit:IsAlive() return self.alive end
            function unit:entindex() return self.id end
            spawned[#spawned + 1] = unit
            return unit
        end,
    }
end

local events = require("core/events")
local event_bus = require("core/event_bus")
local service = require("systems/building_challenge_service")

local abilities = {}
for index = 1, 5 do
    local name = string.format("ability_challenge_monster_0%d", index)
    local ability = { name = name, cooldown = 0, start_count = 0 }
    function ability:IsNull() return false end
    function ability:GetAbilityName() return self.name end
    function ability:GetCooldownTimeRemaining() return self.cooldown end
    function ability:StartCooldown(value)
        self.cooldown = value
        self.start_count = self.start_count + 1
    end
    abilities[name] = ability
end

local building = {
    survival_building_id = "building_challenge",
    alive = true,
}
function building:IsNull() return false end
function building:IsAlive() return self.alive end
function building:entindex() return 700 end
function building:GetTeamNumber() return 2 end
function building:FindAbilityByName(name) return abilities[name] end
for _, ability in pairs(abilities) do
    function ability:GetCaster() return building end
end

service.init()
event_bus.emit(events.BUILDING_CREATED, {
    building_id = "building_challenge",
    unit = building,
    entindex = 700,
    player_id = 0,
    team = 2,
})

for index = 1, 5 do
    local ability = abilities[string.format("ability_challenge_monster_0%d", index)]
    assert(ability.start_count == 1 and ability.cooldown > 0,
        "every challenge ability must enter its initial cooldown")
end

local manual = abilities.ability_challenge_monster_05
manual.cooldown = 0
local manual_result = handlers[events.BUILDING_CHALLENGE_SUMMON_REQUEST]({
    building = building,
    building_entindex = 700,
    challenge_id = "challenge_monster_05",
    source_ability = manual,
})
assert(manual_result and manual_result.ok == true,
    "manual challenge 05 summon must succeed")
assert(spawned[1].challenge_id == "challenge_monster_05",
    "manual challenge 05 must use the alchemist definition")

abilities.ability_challenge_monster_01.cooldown = 0
abilities.ability_challenge_monster_02.cooldown = 0
local auto_result = handlers[events.BUILDING_CHALLENGE_AUTO_REQUEST]({
    building = building,
    building_entindex = 700,
    enabled = true,
})
assert(auto_result and auto_result.ok == true and auto_result.enabled == true,
    "auto challenge toggle must enable the registered building")

local auto_tick = scheduled.building_challenge_auto_summon
assert(type(auto_tick) == "function", "auto challenge scheduler must be registered")
auto_tick()
assert(#spawned == 2, "one auto tick must summon at most one challenge monster")
assert(spawned[2].challenge_id == "challenge_monster_01",
    "auto challenge must use configured sort order")

print("BUILDING_CHALLENGE_MERGE_LUA51_PASS")