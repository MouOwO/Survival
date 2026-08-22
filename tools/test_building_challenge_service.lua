package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path

local event_bus = require("core/event_bus")
local events = require("core/events")
event_bus.reset()

local game_time = 0
GameRules = {
    GetGameTime = function() return game_time end,
}

local auto_tick
local tasks = {}
local function schedule(interval, callback, task_id, repeating)
    tasks[task_id] = {
        interval = interval,
        callback = callback,
        repeating = repeating,
    }
    return task_id
end
local function run_latest_lifecycle_task(kind)
    local selected_id
    local selected_sequence = -1
    for task_id in pairs(tasks) do
        local sequence = tonumber(task_id:match(
            "^building_challenge_lifecycle_(%d+)_" .. kind .. "$"
        ))
        if sequence and sequence > selected_sequence then
            selected_id = task_id
            selected_sequence = sequence
        end
    end
    assert(selected_id, "lifecycle task missing: " .. kind)
    local task = tasks[selected_id]
    tasks[selected_id] = nil
    local result = task.callback()
    if task.repeating and result ~= false then tasks[selected_id] = task end
end
package.loaded["core/scheduler"] = {
    cancel = function(task_id) tasks[task_id] = nil end,
    after = function(delay, callback, task_id)
        return schedule(delay, callback, task_id, false)
    end,
    every = function(interval, callback, task_id)
        if task_id == "building_challenge_auto_summon" then
            assert(interval == 1, "auto interval changed")
            auto_tick = callback
        end
        return schedule(interval, callback, task_id, true)
    end,
}

local next_entindex = 100
local spawned = {}
package.loaded["systems/wave_system"] = {
    get_difficulty = function() return "N3" end,
    spawn_challenge_monster = function(row, definition)
        next_entindex = next_entindex + 1
        local unit = { alive = true, index = next_entindex, removed = false }
        function unit:IsNull() return self.removed end
        function unit:IsAlive() return self.alive end
        function unit:entindex() return self.index end
        spawned[#spawned + 1] = {
            unit = unit,
            row = row,
            definition = definition,
        }
        return unit
    end,
}

local city_level = 4
local wall_health = 100
local wall = {}
function wall:IsNull() return false end
function wall:GetHealth() return wall_health end
function wall:GetMaxHealth() return 100 end
event_bus.handle_request(events.BUILDING_LIST_REQUEST, function()
    return {
        ok = true,
        buildings = {
            { building_id = "main_city", level = city_level },
            { building_id = "wall", unit = wall },
        },
    }
end)

local removed = {}
UTIL_Remove = function(unit)
    unit.alive = false
    unit.removed = true
    removed[#removed + 1] = unit
end

local function ability(name)
    local result = { name = name, cooldown = 0 }
    function result:IsNull() return false end
    function result:GetAbilityName() return self.name end
    function result:GetCaster() return self.caster end
    function result:GetCooldownTimeRemaining() return self.cooldown end
    function result:StartCooldown(value) self.cooldown = value end
    return result
end

local abilities = {
    ability_challenge_monster_01 = ability("ability_challenge_monster_01"),
    ability_challenge_monster_02 = ability("ability_challenge_monster_02"),
    ability_challenge_monster_03 = ability("ability_challenge_monster_03"),
    ability_challenge_monster_04 = ability("ability_challenge_monster_04"),
    ability_challenge_monster_05 = ability("ability_challenge_monster_05"),
}
local building = {
    index = 10,
    alive = true,
    survival_building_id = "building_challenge",
}
function building:IsNull() return false end
function building:IsAlive() return self.alive end
function building:entindex() return self.index end
function building:GetTeamNumber() return 2 end
function building:FindAbilityByName(name) return abilities[name] end
for _, entry in pairs(abilities) do entry.caster = building end

local rewards = {}
local notifications = {}
event_bus.handle_request(events.MONSTER_REWARD_GRANT_REQUEST, function(payload)
    rewards[#rewards + 1] = payload
    return { ok = true }
end)
event_bus.subscribe(events.UI_NOTIFICATION, function(payload)
    notifications[#notifications + 1] = payload
end)

package.loaded["systems/building_challenge_service"] = nil
require("systems/building_challenge_service").init()
assert(type(auto_tick) == "function", "auto task missing")
event_bus.emit(events.BUILDING_CREATED, {
    building_id = "building_challenge",
    entindex = building.index,
    unit = building,
    player_id = 0,
    team = 2,
})
local expected_cooldowns = {
    ability_challenge_monster_01 = 100,
    ability_challenge_monster_02 = 110,
    ability_challenge_monster_03 = 120,
    ability_challenge_monster_04 = 130,
    ability_challenge_monster_05 = 140,
}
for name, entry in pairs(abilities) do
    assert(entry.cooldown == expected_cooldowns[name],
        "building completion cooldown missing: " .. name)
end

abilities.ability_challenge_monster_01.cooldown = 0
local first = event_bus.request(events.BUILDING_CHALLENGE_SUMMON_REQUEST, {
    building = building,
    building_entindex = building.index,
    challenge_id = "challenge_monster_01",
    source_ability = abilities.ability_challenge_monster_01,
})
assert(first and first.ok and #spawned == 1 and first.wave_number == 1,
    "manual challenge summon failed")
assert(spawned[1].definition.model_path
        == "models/heroes/tiny/tiny_04/tiny_04.vmdl",
    "manual challenge visual configuration invalid")
assert(spawned[1].row.wave_number == 1, "manual challenge wave invalid")
assert(spawned[1].row.difficulty_id == "N3", "manual challenge difficulty invalid")
assert(spawned[1].row.health == 6000, "manual challenge health invalid")
assert(spawned[1].row.armor == 10, "manual challenge armor invalid")
assert(spawned[1].unit.survival_display_name == "山岭巨人",
    "challenge instance display name missing")
assert(spawned[1].unit.survival_challenge_difficulty_id == "N3",
    "challenge instance difficulty missing")
local duplicate = event_bus.request(events.BUILDING_CHALLENGE_SUMMON_REQUEST, {
    building = building,
    building_entindex = building.index,
    challenge_id = "challenge_monster_01",
    source_ability = abilities.ability_challenge_monster_01,
})
assert(duplicate and not duplicate.ok
        and duplicate.error == "challenge_monster_already_alive",
    "same challenge alive limit failed")

event_bus.emit(events.BUILDING_DESTROYED, {
    building_id = "building_challenge",
    entindex = building.index,
})
local replacement = building
replacement.index = 11
event_bus.emit(events.BUILDING_CREATED, {
    building_id = "building_challenge",
    entindex = replacement.index,
    unit = replacement,
    player_id = 0,
    team = 2,
})
local cross_rebuild = event_bus.request(events.BUILDING_CHALLENGE_SUMMON_REQUEST, {
    building = replacement,
    building_entindex = replacement.index,
    challenge_id = "challenge_monster_01",
    source_ability = abilities.ability_challenge_monster_01,
})
assert(cross_rebuild and not cross_rebuild.ok,
    "building rebuild bypassed team alive limit")

spawned[1].unit.alive = false
event_bus.emit(events.ENGINE_ENTITY_KILLED, {
    victim = spawned[1].unit,
    victim_entindex = spawned[1].unit:entindex(),
})
assert(#rewards == 1 and rewards[1].team == 2 and rewards[1].player_id == 0
        and rewards[1].reward_profile_id == "reward_building_challenge_mountain_giant"
        and rewards[1].challenge_wave_number == 1,
    "challenge death reward ownership failed")

abilities.ability_challenge_monster_01.cooldown = 0
local second = event_bus.request(events.BUILDING_CHALLENGE_SUMMON_REQUEST, {
    building = replacement,
    building_entindex = replacement.index,
    challenge_id = "challenge_monster_01",
    source_ability = abilities.ability_challenge_monster_01,
})
assert(second and second.ok and second.wave_number == 2
        and spawned[2].row.health == 2000 and spawned[2].row.armor == 20,
    "challenge progress did not advance independently")

local locked_blademaster = event_bus.request(events.BUILDING_CHALLENGE_SUMMON_REQUEST, {
    building = replacement,
    building_entindex = replacement.index,
    challenge_id = "challenge_monster_04",
    source_ability = abilities.ability_challenge_monster_04,
})
assert(locked_blademaster and not locked_blademaster.ok
        and locked_blademaster.error == "challenge_main_city_level_required",
    "blademaster main city prerequisite missing")
city_level = 5

for _, entry in pairs(abilities) do entry.cooldown = 0 end
local auto_result = event_bus.request(events.BUILDING_CHALLENGE_AUTO_REQUEST, {
    building = replacement,
    building_entindex = replacement.index,
    enabled = true,
})
assert(auto_result and auto_result.ok, "auto summon toggle failed")
auto_tick()
assert(#spawned == 3
        and spawned[3].definition.display_name == "树人"
        and abilities.ability_challenge_monster_02.cooldown == 110,
    "auto fixed order or one-per-tick rule failed")
auto_tick()
assert(#spawned == 4
        and spawned[4].definition.display_name == "红龙"
        and abilities.ability_challenge_monster_03.cooldown == 120,
    "auto tick did not summon exactly one challenge")

wall_health = 49
local immediate_failure = event_bus.request(events.BUILDING_CHALLENGE_SUMMON_REQUEST, {
    building = replacement,
    building_entindex = replacement.index,
    challenge_id = "challenge_monster_05",
    source_ability = abilities.ability_challenge_monster_05,
})
assert(immediate_failure and not immediate_failure.ok
        and immediate_failure.cast_consumed == true
        and immediate_failure.error == "challenge_failed_wall_health"
        and immediate_failure.wave_number == 1
        and #removed == 1 and #rewards == 1,
    "immediate wall health failure contract invalid")

abilities.ability_challenge_monster_04.cooldown = 0
auto_tick()
assert(#spawned == 6
        and spawned[6].definition.display_name == "剑圣"
        and abilities.ability_challenge_monster_04.cooldown == 130
        and #removed == 2 and #rewards == 1,
    "automatic immediate failure did not consume cooldown without reward")

wall_health = 50
local boundary = event_bus.request(events.BUILDING_CHALLENGE_SUMMON_REQUEST, {
    building = replacement,
    building_entindex = replacement.index,
    challenge_id = "challenge_monster_05",
    source_ability = abilities.ability_challenge_monster_05,
})
assert(boundary and boundary.ok and boundary.wave_number == 1,
    "wall at exactly 50 percent incorrectly failed")
wall_health = 49
run_latest_lifecycle_task("wall")
assert(#removed == 3 and #rewards == 1,
    "delayed wall health failure rewarded or did not remove the unit")

spawned[3].unit.alive = false
event_bus.emit(events.ENGINE_ENTITY_KILLED, {
    victim = spawned[3].unit,
    victim_entindex = spawned[3].unit:entindex(),
})
assert(#rewards == 1,
    "death before the next wall check bypassed the low-health failure")

wall_health = 100
local timeout_candidate = event_bus.request(
    events.BUILDING_CHALLENGE_SUMMON_REQUEST,
    {
        building = replacement,
        building_entindex = replacement.index,
        challenge_id = "challenge_monster_05",
        source_ability = abilities.ability_challenge_monster_05,
    }
)
assert(timeout_candidate and timeout_candidate.ok
        and timeout_candidate.wave_number == 1,
    "wall failure consumed challenge progress")
game_time = 60
run_latest_lifecycle_task("timeout")
assert(#removed == 4 and #rewards == 1,
    "60 second timeout rewarded or did not remove the unit")

wall_health = 50
local normal_kill = event_bus.request(events.BUILDING_CHALLENGE_SUMMON_REQUEST, {
    building = replacement,
    building_entindex = replacement.index,
    challenge_id = "challenge_monster_05",
    source_ability = abilities.ability_challenge_monster_05,
})
assert(normal_kill and normal_kill.ok and normal_kill.wave_number == 1,
    "timeout consumed challenge progress")
normal_kill.unit.alive = false
event_bus.emit(events.ENGINE_ENTITY_KILLED, {
    victim = normal_kill.unit,
    victim_entindex = normal_kill.unit:entindex(),
})
event_bus.emit(events.ENGINE_ENTITY_KILLED, {
    victim = normal_kill.unit,
    victim_entindex = normal_kill.unit:entindex(),
})
assert(#rewards == 2 and rewards[2].challenge_wave_number == 1,
    "normal kill was not rewarded exactly once at the 50 percent boundary")
local progressed = event_bus.request(events.BUILDING_CHALLENGE_SUMMON_REQUEST, {
    building = replacement,
    building_entindex = replacement.index,
    challenge_id = "challenge_monster_05",
    source_ability = abilities.ability_challenge_monster_05,
})
assert(progressed and progressed.ok and progressed.wave_number == 2,
    "normal rewarded kill did not advance challenge progress")

spawned[2].unit.alive = false
event_bus.emit(events.ENGINE_ENTITY_KILLED, {
    victim = spawned[2].unit,
    victim_entindex = spawned[2].unit:entindex(),
})
assert(#rewards == 2,
    "death at exactly 60 seconds incorrectly granted a reward")
local retry_after_death_boundary = event_bus.request(
    events.BUILDING_CHALLENGE_SUMMON_REQUEST,
    {
        building = replacement,
        building_entindex = replacement.index,
        challenge_id = "challenge_monster_01",
        source_ability = abilities.ability_challenge_monster_01,
    }
)
assert(retry_after_death_boundary and retry_after_death_boundary.ok
        and retry_after_death_boundary.wave_number == 2,
    "60 second death failure consumed challenge progress")
assert(#notifications == 6,
    "challenge failures did not emit exactly one notification each")

print("BUILDING_CHALLENGE_SERVICE_LUA51_PASS")