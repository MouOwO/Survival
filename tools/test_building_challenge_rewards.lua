package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path

local event_bus = require("core/event_bus")
local events = require("core/events")
event_bus.reset()

package.loaded["systems/hero_return_home_service"] = {
    return_unit = function() end,
}

local progression_effects = {}
event_bus.handle_request(events.HERO_PROGRESSION_APPLY_REQUEST, function(payload)
    progression_effects[#progression_effects + 1] = payload.effects
    return { ok = true }
end)

package.loaded["systems/technology_stat_manager"] = nil
local stats = require("systems/technology_stat_manager")
stats.init()
package.loaded["systems/monster_reward_service"] = nil
require("systems/monster_reward_service").init()

local function grant(profile_id, wave_number)
    return event_bus.request(events.MONSTER_REWARD_GRANT_REQUEST, {
        player_id = 0,
        team = 2,
        reward_profile_id = profile_id,
        challenge_wave_number = wave_number,
        encounter_id = "building_challenge:test",
    })
end

assert(grant("reward_building_challenge_mountain_giant", 1).ok)
assert(grant("reward_building_challenge_treant", 3).ok)
assert(grant("reward_building_challenge_red_dragon", 1).ok)
assert(grant("reward_building_challenge_alchemist", 1).ok)
local final = stats.get(0).final
assert(final.wall.technology_armor_bonus == 1
        and final.wall.health_bonus_pct == 1,
    "mountain giant reward projection failed")
assert(final.tower.attack_flat == 300 and final.tower.attack_bonus_pct == 1,
    "treant challenge-wave scaling failed")
assert(final.lumberjack.wood_per_hit_bonus == 1,
    "red dragon lumber reward failed")
assert(final.gold_mine.income_bonus_pct == 2,
    "alchemist gold mine reward failed")

assert(grant("reward_building_challenge_blademaster", 4).ok)
local hero = progression_effects[#progression_effects]
assert(#hero == 2 and hero[1].value == 4000 and hero[2].value == 8000,
    "blademaster challenge-wave scaling failed")

print("BUILDING_CHALLENGE_REWARDS_LUA51_PASS")