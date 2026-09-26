-- Real private snapshot projection/transport: same-team player wave isolation.
package.path = "scripts/vscripts/?.lua;" .. package.path
local bus = require("core/event_bus")
local events = require("core/events")
local tasks, sent, queries = {}, {}, {}
package.loaded["core/scheduler"] = {
    after = function(_, fn, key) tasks[key] = fn end,
    cancel = function(key) tasks[key] = nil end,
}
package.loaded["ui/boss_warning_ui_service"] = { init = function() end }
DOTA_MAX_TEAM_PLAYERS, DOTA_TEAM_GOODGUYS = 4, 2
local players = {}
for id = 0, 3 do players[id] = { player_id = id } end
PlayerResource = {
    IsValidPlayerID = function(_, id) return players[id] ~= nil end,
    GetPlayer = function(_, id) return players[id] end,
    GetTeam = function() return 2 end,
}
GameRules = { GetGameTime = function() return 25 end }
CustomGameEventManager = {
    Send_ServerToPlayer = function(_, player, name, snapshot)
        assert(name == "survival_ui_private_snapshot")
        assert(snapshot.player_id == player.player_id)
        sent[player.player_id] = snapshot
    end,
}
local individual = {
    [0] = {alive=90, overflow_active=false, overflow_remaining=0},
    [1] = {alive=91, overflow_active=true, overflow_remaining=7},
    [2] = {alive=92, overflow_active=true, overflow_remaining=10},
    [3] = {alive=0, overflow_active=false, overflow_remaining=0,
        player_defeated=true, defeat_reason="monster_limit_exceeded"},
}
local unavailable = false
bus.handle_request(events.WAVE_STATE_GET_REQUEST, function(payload)
    queries[#queries + 1] = payload.player_id
    assert(payload.player_id ~= nil, "private HUD must request an explicit player")
    if unavailable then return nil end
    local result = {ok=true,player_id=payload.player_id,alive_limit=90,overflow_grace_seconds=10}
    for key, value in pairs(individual[payload.player_id]) do result[key] = value end
    return result
end)
bus.handle_request(events.RESOURCE_GET_REQUEST, function(payload)
    return {wood=payload.player_id,gold=1,population=0,max_population=10}
end)
bus.handle_request(events.BUILDING_LIST_REQUEST, function() return {buildings={}} end)
require("ui/ui_projection").init()
local snapshots = require("ui/ui_snapshot_service")
snapshots.init()
for id = 0, 1 do
    bus.emit(events.BUILDING_CREATED, {player_id=id,team=2,building_id="main_city",level=id+3})
    bus.emit(events.BUILDING_CREATED, {player_id=id,team=2,building_id="building_research_lab"})
    bus.emit(events.BUILDING_CREATED, {player_id=id,team=2,building_id="building_advanced_research_lab"})
    bus.emit(events.WORKER_CHANGED, {player_id=id,team=2,count_delta=id+2})
end
-- Deliberately contradictory global warning must never leak into a player's HUD.
bus.emit(events.WAVE_CHANGED, {alive=273,alive_limit=90,overflow_active=true,
    overflow_remaining=1,current_wave=8,total_waves=30,timer=35,status="countdown"})
tasks.ui_snapshot_flush()
for id = 0, 3 do
    local row=assert(sent[id]).wave
    assert(row.player_id==id and row.alive==individual[id].alive)
    assert(row.overflow_active==individual[id].overflow_active)
    assert(row.overflow_remaining==individual[id].overflow_remaining)
    assert(row.current_wave==8 and row.timer==35 and row.alive_limit==90)
end
assert(sent[3].wave.player_defeated and sent[3].wave.defeat_reason=="monster_limit_exceeded")
assert(not sent[0].wave.player_defeated and not sent[1].wave.player_defeated)
assert(sent[0].wave~=sent[1].wave, "snapshots must not mutate the shared global table")
assert(sent[0].city_level==3 and sent[1].city_level==4)
assert(sent[0].worker_count==2 and sent[1].worker_count==3)
-- Removing a defeated player's buildings/workers must not erase same-team survivors' HUD state.
for _, building_id in ipairs({"main_city", "building_research_lab", "building_advanced_research_lab"}) do
    bus.emit(events.BUILDING_DESTROYED, {player_id=0,team=2,building_id=building_id})
end
bus.emit(events.WORKER_CHANGED, {player_id=0,team=2,count_delta=-2})
bus.emit(events.WORKER_CHANGED, {team=2,population_training={}})
snapshots.publish_player(0)
snapshots.publish_player(1)
assert(sent[0].city_level==0 and sent[0].worker_count==0)
assert(sent[0].research_unlocked==0 and sent[0].advanced_researcher_unlocked==0)
assert(sent[1].city_level==4 and sent[1].worker_count==3)
assert(sent[1].research_unlocked==1 and sent[1].advanced_researcher_unlocked==1)
local prior=sent[1]
individual[0].alive=12
snapshots.publish_player(0)
assert(sent[0].wave.alive==12 and sent[1]==prior and sent[1].wave.alive==91)
unavailable=true
snapshots.publish_player(0)
assert(sent[0].wave.alive==0 and not sent[0].wave.overflow_active,
    "missing player state cannot fall back to a global defeat warning")
print("PERSONAL_WAVE_PROJECTION_PASS: four same-team recipients, independent timers, personal defeat, global lifecycle, no shared mutation")