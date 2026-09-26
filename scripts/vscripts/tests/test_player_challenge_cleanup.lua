package.path = "scripts/vscripts/?.lua;" .. package.path
-- Exercise each real challenge cleanup subscriber with two same-team owners.
local noop = function() end
local tasks, removed, notices = {}, {}, {}
DOTA_TEAM_GOODGUYS, DOTA_TEAM_BADGUYS, DOTA_TEAM_NEUTRALS = 2, 3, 4
GameRules = {GetGameTime = function() return 10 end}
package.loaded["core/scheduler"] = {
    cancel = function(id) tasks[id] = nil end,
    every = function(delay, fn, id) tasks[id] = fn end,
    after = function(delay, fn, id) tasks[id] = fn end,
}
for _, name in ipairs({"hero_return_home_service", "destination_validation_service",
    "challenge_monster_visual_service", "monster_hero_visual_service",
    "monster_hull_scale", "monster_navigation_policy", "wave_monster_collision"}) do
    package.loaded["systems/" .. name] = {clear = noop, apply = noop}
end
package.loaded["systems/wave_system"] = {}
package.loaded["systems/multiplayer_player_service"] = {is_defeated = function(id) return id == 0 end}
local bus, events = require("core/event_bus"), require("core/events")
local function upvalue(fn, wanted)
    for i = 1, 100 do
        local name, value = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then return value end
    end
    error("missing production state: " .. wanted)
end
local function unit(index)
    local value = {index = index}
    function value:IsNull() return self.removed == true end
    function value:IsAlive() return not self.removed end
    function value:entindex() return self.index end
    return value
end
UTIL_Remove = function(value) value.removed = true; removed[#removed + 1] = value end
local challenge = require("systems/challenge_session_service")
local monsters = require("systems/monster_spawn_service")
local building = require("systems/building_challenge_service")
challenge.init(); monsters.init(); building.init()
local sessions = upvalue(challenge.init, "sessions")
local prepared = upvalue(challenge.init, "challenge_11_prepared_by_player")
local session_meta = upvalue(challenge.init, "monster_meta")
local active = upvalue(monsters.init, "active_by_entindex")
local encounters = upvalue(monsters.init, "active_by_encounter")
local retries = upvalue(monsters.init, "retry_until_by_player")
local building_meta = upvalue(building.init, "monster_meta")
local buildings = upvalue(building.init, "states")
local alive_by_team = upvalue(building.init, "alive_by_team")
local owned, survivor = {}, {}
for id = 0, 1 do
    local targets = id == 0 and owned or survivor
    local normal, staging, boss, building_boss = unit(id * 10 + 1), unit(id * 10 + 2), unit(id * 10 + 3), unit(id * 10 + 4)
    targets[1], targets[2], targets[3], targets[4] = normal, staging, boss, building_boss
    sessions[id] = { encounter_fixture = {player_id = id, encounter_id = "encounter_fixture",
        encounter = {display_name = "fixture"}, status = "active", members = {},
        monsters = {[normal:entindex()] = normal}, monster_count = 1} }
    prepared[id] = {monsters = {}, prepared_monsters = {[staging:entindex()] = staging}}
    session_meta[normal:entindex()] = {player_id = id}
    session_meta[staging:entindex()] = {player_id = id}
    active[boss:entindex()] = {player_id = id, encounter_id = "same_encounter", unit = boss}
    -- A legacy global encounter cache currently points at the surviving owner.
    encounters.same_encounter = boss:entindex()
    retries[id] = {same_encounter = 100}
    building_meta[building_boss:entindex()] = {player_id = id, entindex = building_boss:entindex(),
        challenge_id = "same_challenge", team = 2, unit = building_boss, status = "active"}
    buildings[100 + id] = {player_id = id, team = 2}
    alive_by_team[2] = {same_challenge = building_boss}
end
bus.subscribe(events.MONSTER_ENCOUNTER_CHANGED, function(p) notices[#notices + 1] = p end)
bus.emit(events.PLAYER_DISCONNECTED, {player_id = 0})
assert(#removed == 0 and sessions[0] and prepared[0] and retries[0], "ordinary disconnect preserves grace-period gameplay")
bus.emit(events.PLAYER_DISCONNECTED, {player_id = 0, defeat_cleanup = true})
assert(sessions[0] == nil and prepared[0] == nil and retries[0] == nil and buildings[100] == nil)
assert(sessions[1] and prepared[1] and retries[1] and buildings[101])
for _, value in ipairs(owned) do assert(value.removed, "all of the losing player's challenge units must retire") end
for _, value in ipairs(survivor) do assert(not value.removed, "same-team survivor challenge units must persist") end
assert(session_meta[1] == nil and session_meta[2] == nil and session_meta[11] and session_meta[12])
assert(active[3] == nil and active[13] and encounters.same_encounter == 13)
assert(building_meta[4] == nil and building_meta[14] and alive_by_team[2].same_challenge == survivor[4])
assert(#notices == 1 and notices[1].player_id == 0 and notices[1].status == "cancelled")
assert(not challenge.start({player_id = 0, encounter_id = "encounter_fixture"}).ok)
assert(not bus.request(events.MONSTER_ENCOUNTER_START_REQUEST, {player_id = 0}).ok)
assert(not bus.request(events.MONSTER_ENCOUNTER_REENTER_REQUEST, {player_id = 0}).ok)
assert(not bus.request(events.BUILDING_CHALLENGE_SUMMON_REQUEST, {player_id = 0}).ok)
bus.emit(events.PLAYER_DISCONNECTED, {player_id = 0, defeat_cleanup = true})
assert(#removed == 4 and #notices == 1, "repeated cleanup is idempotent")
print("PLAYER_CHALLENGE_CLEANUP_PASS: real subscribers remove own rooms/staging/bosses, preserve same-team owners/cache, honor disconnect grace, reject reentry, idempotent")