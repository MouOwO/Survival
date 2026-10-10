-- Run from the addon root with Lua 5.1:
--   lua tools/test_research_section_refresh.lua
-- Optional A/B: lua tools/test_research_section_refresh.lua <manager> <before>
-- Uses the real 19 research definitions, effect service and event bus. No engine
-- mocks, timers or TEMP baseline are required by the default contract.
package.path = "scripts/vscripts/?.lua;" .. package.path
local bus = require("core/event_bus")
local events = require("core/events")
local names = require("research/research_event_names")
local Effects = require("research/research_effect_service")
local config = require("config/research_technology_config")
local manager_path = arg[1] or "scripts/vscripts/systems/technology_stat_manager.lua"
local before_path = arg[2]

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = copy(child) end
    return result
end

local function same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then
        return a == b or (type(a) == "number" and a ~= a and b ~= b)
    end
    for key, value in pairs(a) do if not same(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end

local function equal(actual, expected, label)
    assert(same(actual, expected), label .. " differs")
end

-- Tower changes deliberately retain the full native-tower recovery path.
-- ARS-07 changes both tower and hero and also remains full.
local sections = {
    ["RS-01"] = "lumberjack", ["RS-02"] = "lumberjack",
    ["RS-03"] = "lumberjack", ["RS-04"] = "lumberjack",
    ["RS-05"] = "lumberjack", ["RS-08"] = "wall", ["RS-09"] = "wall",
    ["ARS-01"] = "lumberjack", ["ARS-02"] = "lumberjack",
    ["ARS-03"] = "wall", ["ARS-04"] = "wall",
    ["ARS-08"] = "hero", ["ARS-09"] = "hero", ["ARS-10"] = "hero",
}

-- Existing neutral challenge/rogue layers each have a critical multiplier of
-- two. Assert this existing numeric contract rather than silently changing it.
local function assert_snapshot(actual, projection, label, additions)
    equal(actual.levels, projection.levels, label .. " levels")
    equal(actual.technology, projection.legacy, label .. " research values")
    local final = copy(projection.legacy)
    final.tower.critical_damage_multiplier = final.tower.critical_damage_multiplier + 4
    final.gold_mine = { income_bonus_pct = 0 }
    final.hero.attack_speed_bonus_pct = 0
    final.hero.attack_interval_flat = 0
    final.hero.all_attributes_flat = 0
    if additions then
        final.hero.attack_flat = final.hero.attack_flat + additions.hero_attack
        final.lumberjack.wood_per_hit_bonus = final.lumberjack.wood_per_hit_bonus
            + additions.wood
        final.wall.technology_armor_bonus = final.wall.technology_armor_bonus
            + additions.wall_armor
    end
    equal(actual.final, final, label .. " final numeric values")
    equal(actual.runtime, {
        training_room_active = false, training_room_action_id = "",
        training_room_income_multiplier = 1,
    }, label .. " runtime")
end

local function run(filename, optimized)
    bus.reset()
    local manager = assert(loadfile(filename))()
    manager.init()
    local levels = { [0] = {}, [1] = {} }
    local repository = {
        GetAllLevels = function(_, id) return copy(levels[id]) end,
        GetTeam = function(_, id) return id >= 0 and 2 or nil end,
    }
    local effects = Effects.new(repository)
    local results, last, publish_count = {}, nil, 0
    bus.subscribe(events.TECHNOLOGY_STATS_CHANGED, function(payload)
        publish_count = publish_count + 1
        last = copy(payload)
    end)
    local function emit(id, projection, section, label, skip_numeric, additions)
        last = nil
        local count = publish_count
        bus.emit(names.EFFECTS_CHANGED, { player_id = id, snapshot = projection })
        assert(last and publish_count == count + 1,
            "actual research producer must publish exactly once: " .. label)
        assert(last.player_id == id and last.reason == "research_effects_changed")
        equal(last.changed_section, optimized and section or nil, label .. " section")
        assert(last.changed_field == nil,
            "research must not enter per-hit attack-growth shortcut")
        if not skip_numeric then assert_snapshot(last.snapshot, projection, label, additions) end
        equal(manager.get(id), last.snapshot, label .. " manager get")
        local response = bus.request(events.TECHNOLOGY_STATS_GET_REQUEST, { player_id = id })
        assert(response.ok == true)
        equal(response.snapshot, last.snapshot, label .. " request snapshot")
        results[#results + 1] = { label = label, player_id = id, snapshot = copy(last.snapshot) }
    end

    emit(0, effects:Recalculate(0), nil, "first-player0")
    emit(1, effects:Recalculate(1), nil, "first-player1")
    assert(#config.technologies == 19, "contract expects all 19 actual technologies")
    for _, definition in ipairs(config.technologies) do
        local id = definition.tech_id
        assert(definition.max_level >= 2, "technology has no second level: " .. id)
        levels[0][id] = 1
        emit(0, effects:Recalculate(0), sections[id], id .. " level1")
        levels[0][id] = 2
        emit(0, effects:Recalculate(0), sections[id], id .. " level2")
    end
    equal(manager.get(1).levels, {}, "player0 upgrades must not change player1")
    levels[1]["ARS-10"] = 1
    emit(1, effects:Recalculate(1), "hero", "isolated-player1")
    emit(1, effects:Recalculate(1), nil, "unchanged-not-guessed")
    levels[1]["RS-01"], levels[1]["ARS-10"] = 1, 2
    emit(1, effects:Recalculate(1), nil, "two-sections")
    local projection = effects:Recalculate(1)
    local unknown = copy(projection)
    unknown.legacy.hero.future_field = 1
    emit(1, unknown, nil, "unknown-field")
    emit(1, projection, nil, "removed-unknown-field")
    unknown = copy(projection)
    unknown.legacy.future_section = { value = 1 }
    emit(1, unknown, nil, "unknown-section")
    emit(1, projection, nil, "removed-unknown-section")
    for _, value in ipairs({ 0 / 0, math.huge, -math.huge, "4" }) do
        local invalid = copy(projection)
        invalid.legacy.hero.attack_flat = value
        emit(1, invalid, nil, "invalid-number " .. tostring(value), true)
        emit(1, projection, nil, "invalid-number-restored " .. tostring(value))
    end
    -- A missing shape cannot be classified. The actual producer accepts a
    -- missing legacy by using fresh values; malformed missing snapshot is ignored.
    emit(1, { levels = copy(levels[1]) }, nil, "missing-legacy", true)
    emit(1, projection, nil, "missing-legacy-restored")
    local count = publish_count
    bus.emit(names.EFFECTS_CHANGED, { player_id = 1 })
    bus.emit(names.EFFECTS_CHANGED, { snapshot = projection })
    assert(publish_count == count, "missing player/snapshot must not publish")

    -- Research still composes immediately with existing gameplay additions.
    local growth = bus.request(events.TECHNOLOGY_STATS_GROWTH_ADD_REQUEST,
        { player_id = 1, section = "hero", field = "attack", amount = 7 })
    assert(growth.ok == true)
    local rogue = bus.request(events.TECHNOLOGY_STATS_ROGUE_ADD_REQUEST,
        { player_id = 1, effects = { { effect_type = "lumberjack_wood_per_hit", value = 3 } } })
    assert(rogue.ok == true)
    local challenge = bus.request(events.TECHNOLOGY_STATS_CHALLENGE_ADD_REQUEST,
        { player_id = 1, effects = { { effect_type = "challenge_wall_armor_flat", value = 6 } } })
    assert(challenge.ok == true)
    levels[1]["ARS-10"] = 3
    emit(1, effects:Recalculate(1), "hero", "growth-rewards-preserved", false,
        { hero_attack = 7, wood = 3, wall_armor = 2 })
    assert(manager.get(1).growth.hero.attack == 7)

    local level_events = 0
    bus.subscribe(names.LEVEL_CHANGED, function() level_events = level_events + 1 end)
    bus.emit(names.LEVEL_CHANGED, { player_id = 1, tech_id = "ARS-10", level = 3 })
    assert(level_events == 1, "stats classification must preserve research-level listeners")
    return results
end

local after = run(manager_path, true)
if before_path then
    local before = run(before_path, false)
    assert(#before == #after)
    for index, value in ipairs(before) do
        equal(after[index], value, "A/B complete snapshot " .. value.label)
    end
end
print("PASS research section refresh: " .. #after
    .. " actual effect-service/event-bus updates; 19 technologies x2 levels;"
    .. " numeric snapshots, isolated players, full fallback and reward/growth preservation"
    .. (before_path and "; before/after snapshots identical" or ""))
