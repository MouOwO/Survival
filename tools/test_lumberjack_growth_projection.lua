package.path = "scripts/vscripts/?.lua;" .. package.path
GameRules = {GetGameTime = function() return 0 end}
local bus = require("core/event_bus")
local events = require("core/events")
local manager = require("systems/technology_stat_manager")
manager.init()
local previous = manager.get(0)
local original_pairs, visits = pairs, 0
pairs = function(value)
    local iterator, state, first = original_pairs(value)
    return function(s, k)
        local key, item = iterator(s, k)
        if key ~= nil then visits = visits + 1 end
        return key, item
    end, state, first
end
for i = 1, 200 do
    local result = bus.request(events.TECHNOLOGY_STATS_GROWTH_ADD_REQUEST,
        {player_id = 0, section = "lumberjack", field = "attack", amount = 0.25})
    assert(result.ok and result.snapshot.final.lumberjack.attack_flat == i * 0.25)
end
pairs = original_pairs
assert(visits < 6000, "each hit should copy only changed sections, not all research fields")
assert(previous.final.lumberjack.attack_flat == 0 and previous.growth.lumberjack.attack == 0,
    "earlier snapshots retain their value")
local before = manager.get(0)
for _, request in ipairs({
    {"lumberjack", "wood_per_hit", "wood_per_hit_bonus", 3},
    {"hero", "attack", "attack_flat", 8},
    {"hero", "attributes", "attributes_gain_per_second", 2},
}) do
    local result = bus.request(events.TECHNOLOGY_STATS_GROWTH_ADD_REQUEST,
        {player_id = 0, section = request[1], field = request[2], amount = request[4]})
    assert(result.snapshot.final[request[1]][request[3]] == request[4])
end
assert(before.final.hero.attack_flat == 0 and before.final.lumberjack.wood_per_hit_bonus == 0)
assert(manager.get(1).final.lumberjack.attack_flat == 0)
bus.emit(events.TECHNOLOGY_CHANGED, {player_id = 0, levels = {}, reason = "rebuild"})
assert(manager.get(0).final.lumberjack.attack_flat == 50 and manager.get(0).final.hero.attack_flat == 8)
bus.request(events.TECHNOLOGY_STATS_ROGUE_ADD_REQUEST, {player_id = 0, effects = {
    {effect_type = "lumberjack_wood_per_hit", value = 5},
    {effect_type = "hero_all_attributes_flat", value = 4},
}})
bus.request(events.TECHNOLOGY_STATS_CHALLENGE_ADD_REQUEST, {player_id = 0, effects = {
    {effect_type = "challenge_lumber_efficiency_flat", value = 7},
}})
local layered = bus.request(events.TECHNOLOGY_STATS_GROWTH_ADD_REQUEST,
    {player_id = 0, section = "lumberjack", field = "wood_per_hit", amount = 2})
assert(layered.snapshot.final.lumberjack.wood_per_hit_bonus == 17,
    "technology/challenge/rogue/growth layers compose in the original order")
assert(layered.snapshot.final.hero.all_attributes_flat == 4 and layered.snapshot.final.hero.attack_flat == 8,
    "growth leaves unrelated projections intact")
local signed = bus.request(events.TECHNOLOGY_STATS_GROWTH_ADD_REQUEST,
    {player_id = 0, section = "lumberjack", field = "attack", amount = -0.5})
assert(signed.snapshot.final.lumberjack.attack_flat == 49.5)
local rejected = bus.request(events.TECHNOLOGY_STATS_GROWTH_ADD_REQUEST,
    {player_id = 0, section = "hero", field = "invalid", amount = 1})
assert(not rejected.ok)

local profile = {mode = "pure", save = {gameplay_stats = {lumberjack_attack_growth = 0.75},
    permanent_effects = {}, archive = {}, match_boss_effects = {}}}
for i = 1, 2000 do profile.save.permanent_effects["unrelated_" .. i] = i end
package.loaded["systems/player_profile_service"] = {get_profile = function() return profile end}
local rewards = require("systems/permanent_reward_effect_service")
rewards.init(); bus.emit(events.PLAYER_PROFILE_CHANGED, {player_id = 0})
local full = bus.request(events.PERMANENT_REWARD_EFFECTS_GET_REQUEST, {player_id = 0})
local narrow = bus.request(events.PERMANENT_REWARD_EFFECTS_GET_REQUEST,
    {player_id = 0, lumberjack_growth_only = true})
assert(narrow.totals.lumberjack_attack_growth == full.totals.lumberjack_attack_growth
    and narrow.totals.unrelated_1 == nil)
local full_visits, narrow_visits = 0, 0
local function counted_query(narrow_only)
    local count = 0
    pairs = function(value)
        local iterator, state, first = original_pairs(value)
        return function(s, k)
            local key, item = iterator(s, k)
            if key ~= nil then count = count + 1 end
            return key, item
        end, state, first
    end
    for i = 1, 100 do
        bus.request(events.PERMANENT_REWARD_EFFECTS_GET_REQUEST,
            {player_id = 0, lumberjack_growth_only = narrow_only})
    end
    pairs = original_pairs
    return count
end
full_visits, narrow_visits = counted_query(false), counted_query(true)
assert(full_visits >= 200000 and narrow_visits == 0)
narrow.totals.lumberjack_attack_growth = 999
profile.save.gameplay_stats.lumberjack_attack_growth = 1.25
bus.emit(events.PLAYER_PROFILE_CHANGED, {player_id = 0})
assert(bus.request(events.PERMANENT_REWARD_EFFECTS_GET_REQUEST,
    {player_id = 0, lumberjack_growth_only = true}).totals.lumberjack_attack_growth == 1.25)
print("LUMBERJACK_GROWTH_PROJECTION_PASS: 200 immediate growth requests visit " .. visits
    .. " fields; immutable earlier snapshots; all four growth mappings; rebuild/player isolation; live narrow permanent rewards")
print("LUMBERJACK_REWARD_QUERY_PASS: 100 queries full=" .. full_visits .. " narrow=" .. narrow_visits)
