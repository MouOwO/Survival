package.path = "scripts/vscripts/?.lua;" .. package.path
require("tests/development_release_profile")
-- Offline entity doubles have no Steam identity; admission is tested separately.
package.loaded["core/test_access_policy"] = {enabled = function() return false end}
local balance = require("config/human_challenge_balance")
local profiles = require("config/challenge_combat_profile_config")
local rules = require("config/human_monster_rules")
local function close(a, b, label)
    assert(math.abs(a - b) <= math.max(1e-8, math.abs(b) * 1e-13),
        tostring(label) .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

-- Independent literal examples expose rounding, wrong multipliers and the
-- exception that only the first cold/scourge rebirth boss is halved.
local cold = assert(profiles.resolve("encounter_rebirth_01", "N1", "cold"))
assert(cold.health == 450000 and cold.war3_armor == 122.5 and cold.attack == 6000)
close(cold.attack_speed, 1 / 0.6, "rebirth attack interval")
local scourge = assert(profiles.resolve("encounter_rebirth_01", "N1", "scourge"))
assert(scourge.health == 3000000 and scourge.war3_armor == 227.5 and scourge.attack == 12000)
local second = assert(profiles.resolve("encounter_rebirth_02", "N1", "scourge"))
assert(second.health == 20096000 and second.war3_armor == 650 and second.attack == 60000)
local standard = assert(profiles.resolve("practice_attribute", "N1", "standard"))
assert(standard.health == 1777776 and standard.attack == 1000000 and standard.war3_armor == 200)
local hard_room = assert(profiles.resolve("practice_wood", "N22", "scourge"))
assert(hard_room.health == 1650330000 and hard_room.war3_armor == 9620)
close(hard_room.attack, 31000, "rooms retain 1.8+0.2N in scourge")
local hard_boss = assert(profiles.resolve("encounter_rebirth_02", "N22", "scourge"))
assert(hard_boss.attack == 375000)
assert(balance.member_count("challenge_06_ice_wraith") == 13)
assert(balance.member_count("seven_sins_minion") == 11)

local archive_ids = {}
for index = 1, 4 do archive_ids[#archive_ids + 1] = "shadow_" .. index end
for index = 1, 12 do archive_ids[#archive_ids + 1] = string.format("hunt_%02d", index) end
for index = 1, 6 do archive_ids[#archive_ids + 1] = "cage_" .. index end
for _, id in ipairs(archive_ids) do
    local low, high = assert(balance.archive(id, "N1")), assert(balance.archive(id, "N50"))
    for _, key in ipairs({"health", "attack", "war3_armor", "attack_speed"}) do
        assert(low[key] == high[key], "archive values must be final and difficulty independent")
    end
    assert(low.attack_speed == 2.5 and low.authored_attack_speed == 250)
    low.health = 0
    assert(balance.archive(id, "N1").health > 0, "returned rows may not mutate source data")
    for number = 1, 10 do
        local difficulty = "N" .. number
        local stored = assert(require("config/generated/archive_challenge_stats").by_id[id .. "_" .. difficulty])
        local authored = assert(balance.archive(id, difficulty))
        for _, key in ipairs({"health", "attack", "war3_armor", "attack_speed"}) do
            assert(stored[key] == authored[key], "editable archive rows must match the runtime authority")
        end
    end
end
assert(balance.archive("shadow_1", "N1").health == 9000010)
assert(balance.archive("shadow_1", "N50").war3_armor == 998)
assert(balance.archive("shadow_3", "N1").health == 90000020)
assert(balance.archive("hunt_05", "N1").health == 1260000000)
assert(balance.archive("hunt_06", "N1").attack == 42000002)
assert(balance.archive("hunt_09", "N1").attack == 5500002)
assert(balance.archive("hunt_12", "N1").source_name == "神兽狩猎-奥蕾莉亚")
assert(balance.archive("cage_1", "N1").health == 450000000)
assert(balance.archive("cage_6", "N1").source_name == "秘法牢笼-青铜龙诺兹多姆")
assert(balance.archive("social_friend", "N1") == nil, "unmentioned social stats retain their own authority")

local checked = 0
for mode_id, modes in pairs(rules.data.modes) do
    for number, mode in ipairs(modes) do
        local difficulty = "N" .. number
        for index, source in ipairs(rules.data.building_challenges) do
            local id = string.format("challenge_monster_%02d", index)
            for wave = 1, mode.total_waves - 1 do
                local row = assert(balance.building(id, wave, difficulty, mode_id))
                local next_base, current_base = rules.data.waves[wave + 1], rules.data.waves[wave]
                close(row.health, source.fixed_health + next_base.health * mode.hp_multiplier * source.health_coefficient, "building HP")
                close(row.attack, source.fixed_attack + next_base.attack * mode.hp_multiplier * source.attack_coefficient, "building attack uses pI=HP multiplier")
                close(row.war3_armor, current_base.war3_armor * mode.armor_multiplier * (mode_id == "scourge" and 2 or 1), "current-wave final ordinary armor")
                assert(row.formula_wave_number == wave)
                checked = checked + 1
            end
            assert(not balance.building(id, 0, difficulty, mode_id))
            assert(not balance.building(id, mode.total_waves, difficulty, mode_id))
        end
    end
end
print("HUMAN_CHALLENGE_FORMULAS_PASS: " .. checked .. " building rows, independent room/rebirth examples, 22 final archive mappings, 250% attack speed, no double correction")

-- Exercise the actual building service entry and settlement. Combat formulas
-- follow the formal current wave, while reward sequence remains independent.
local bus, events = require("core/event_bus"), require("core/events")
local wave_number, difficulty, mode_id, clock = 0, "N1", "standard", 100
local serial, spawned, rewards, tasks = 500, {}, {}, {}
local noop = function() end
GameRules = {GetGameTime = function() return clock end}
DOTA_TEAM_GOODGUYS, DOTA_TEAM_BADGUYS = 2, 3
package.loaded["core/scheduler"] = {
    every = function(_, callback, id) tasks[id] = callback; return id end,
    after = function(_, callback, id) tasks[id] = callback; return id end,
    cancel = function(id) tasks[id] = nil end,
}
package.loaded["systems/match_setup_service"] = {get_mode = function() return mode_id end}
package.loaded["systems/player_context_service"] = {is_defeated = function() return false end}
package.loaded["systems/monster_hero_visual_service"] = {clear = noop, on_death = noop}
package.loaded["systems/rogue_effect_state_service"] = {numeric = function() return 0 end}
local function unit()
    serial = serial + 1
    local value = {index = serial, alive = true}
    function value:IsNull() return self.removed == true end
    function value:IsAlive() return self.alive end
    function value:entindex() return self.index end
    return value
end
package.loaded["systems/wave_system"] = {
    get_difficulty = function() return difficulty end,
    current_wave_number = function() return wave_number end,
    spawn_challenge_monster = function(row, definition, player)
        local value = unit()
        spawned[#spawned + 1] = {row = row, definition = definition, unit = value, player = player}
        return value
    end,
}
UTIL_Remove = function(value) value.removed = true; value.alive = false end
local wall = unit()
wall.health = 1000
function wall:GetHealth() return self.health end
function wall:GetMaxHealth() return 1000 end
bus.handle_request(events.BUILDING_LIST_REQUEST, function()
    return {buildings = {{building_id = "main_city", level = 5}, {building_id = "wall", unit = wall}}}
end)
bus.handle_request(events.MONSTER_REWARD_GRANT_REQUEST, function(payload)
    rewards[#rewards + 1] = payload; return {ok = true}
end)
local definitions = require("config/generated/building_challenge_definitions")
local building = unit()
building.survival_building_id = "building_challenge"
function building:GetTeamNumber() return 2 end
local abilities = {}
for _, definition in ipairs(definitions.rows) do
    local ability = {}
    function ability:IsNull() return false end
    function ability:GetCaster() return building end
    function ability:GetAbilityName() return definition.ability_name end
    ability.StartCooldown = noop
    abilities[definition.ability_name] = ability
end
function building:FindAbilityByName(name) return abilities[name] end
local service = require("systems/building_challenge_service")
service.init()
bus.emit(events.BUILDING_CREATED, {building_id = "building_challenge", unit = building,
    entindex = building:entindex(), player_id = 0, team = 2})
local definition = definitions.by_id.challenge_monster_01
local function summon()
    return bus.request(events.BUILDING_CHALLENGE_SUMMON_REQUEST, {
        building_entindex = building:entindex(), challenge_id = definition.challenge_id,
        source_ability = abilities[definition.ability_name],
    })
end
assert(not summon().ok and #spawned == 0, "pre-wave challenge must not invent a next wave")
wave_number = 1
assert(summon().ok and #spawned == 1)
assert(spawned[1].row.formula_wave_number == 1 and spawned[1].definition == definition)
spawned[1].unit.alive = false
bus.emit(events.ENGINE_ENTITY_KILLED, {victim_entindex = spawned[1].unit:entindex(), victim = spawned[1].unit})
assert(#rewards == 1 and rewards[1].challenge_wave_number == 1,
    "reward count=" .. #rewards .. " sequence=" .. tostring(rewards[1] and rewards[1].challenge_wave_number))
wave_number = 7
assert(summon().ok and #spawned == 2)
assert(spawned[2].row.formula_wave_number == 7 and spawned[2].unit.survival_challenge_wave_number == 2,
    "reward sequence must not replace the actual formal-wave formula input")
wall.health = 500
spawned[2].unit.alive = false
bus.emit(events.ENGINE_ENTITY_KILLED, {victim_entindex = spawned[2].unit:entindex(), victim = spawned[2].unit})
assert(#rewards == 1, "exactly 50% wall health fails without a reward")
wall.health, wave_number = 1000, 25
assert(not summon().ok and #spawned == 2, "N1 wave25 has no next-wave challenge")
difficulty, wave_number = "N2", 29
assert(summon().ok and #spawned == 3, "N2 must still support current wave29")
spawned[3].unit.alive, wave_number = false, 30
assert(not summon().ok and #spawned == 3, "N2 wave30 has no next-wave challenge")
print("HUMAN_BUILDING_CHALLENGE_RUNTIME_PASS: actual summon/settlement, current-wave stats, independent rewards, N1/N2 terminal limits, <=50% wall failure")
