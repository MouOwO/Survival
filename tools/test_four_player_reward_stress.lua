-- Native HTTP transport is an offline stdin/stdout bridge to a local fixture DB.
-- Production reward dispatcher, archive queue, profile service, adapter and
-- HTTP provider run unchanged. No game, socket, existing save, or payment API.
package.path = "scripts/vscripts/?.lua;" .. package.path
local encode = require("core/json_encoder").encode
local decode = require("core/json_decoder").decode
local function rpc(message)
    io.stdout:write(encode(message), "\n"); io.stdout:flush()
    return decode(assert(io.stdin:read("*l"), "offline controller closed"))
end
print = function(message) io.stderr:write(tostring(message), "\n") end
local bus, events = require("core/event_bus"), require("core/events")
local scheduler = require("core/scheduler")
local context = require("systems/player_context_service")
local multiplayer = require("systems/multiplayer_player_service")
local setup = require("systems/match_setup_service")
local clock, fixture, actors, requests = 0, nil, {}, 0
DOTA_TEAM_GOODGUYS, DOTA_MAX_TEAM_PLAYERS = 2, 6
GameRules = {GetGameTime = function() return clock end,
    PlayerHasCustomGameHostPrivileges = function(_, id) return id == 0 end}
Convars = {GetStr = function(_, name)
    if name == "survival_fishing_api_token" then return "offline-fixture-only" end
    if name == "survival_archive_http_enabled" then return "1" end
    return ""
end, RegisterConvar = function() end}
PlayerResource = {
    GetPlayer = function(_, id) return actors[id] and id or nil end,
    IsValidPlayerID = function(_, id) return actors[id] ~= nil end,
    IsFakeClient = function(_, id) return actors[id] and actors[id].fake == true end,
    GetTeam = function(_, id) return actors[id] and actors[id].team or 0 end,
    GetSteamAccountID = function(_, id) return actors[id] and actors[id].account or 0 end,
}
CustomGameEventManager = {RegisterListener = function() end, Send_ServerToPlayer = function() end}
-- Visual/UI clocks only: unrelated to rewards, account identity or eligibility.
package.loaded["systems/title_presentation_service"] = {
    init = function() end, rows = function() return {} end, preview_mode = function() return false end}
package.loaded["systems/online_time_service"] = {disconnect = function() end}
function CreateHTTPRequestScriptVM(method, url)
    assert(method == "POST")
    local path = assert(url:match("(/v1/.*)$"), "unrecognized offline route")
    local body
    return {
        SetHTTPRequestHeaderValue = function(_, header, value)
            assert(header == "Authorization" and value == "Bearer offline-fixture-only")
        end,
        SetHTTPRequestRawPostBody = function(_, _, value) body = decode(value) end,
        SetHTTPRequestAbsoluteTimeoutMS = function() end,
        Send = function(_, callback)
            requests = requests + 1
            local response = rpc({kind = "transport", path = path, body = body})
            callback({StatusCode = response.status, Body = encode(response.body)})
        end,
    }
end
local provider = require("systems/player_profile_providers/http_fishing_provider")
local profiles = require("systems/player_profile_service")
local archive = require("systems/archive_service")
local cooperative = require("systems/archive_cooperative_reward_service")
local checks, failures, operation_log = 0, {}, {}
local function check(value, message)
    checks = checks + 1
    if not value then failures[#failures + 1] = message end
end
local function action(name, fn)
    operation_log[#operation_log + 1] = {time = clock, name = name}
    local ok, result = pcall(fn)
    if not ok then failures[#failures + 1] = name .. ": " .. tostring(result) end
    return result
end
local function tick(delta) clock = clock + (delta or 1); scheduler.think() end
local function drain()
    cooperative.flush_endless_rewards()
    for i = 1, 80 do
        local pending = cooperative.has_pending()
        for id = 0, 3 do pending = pending or archive.has_pending(id) end
        if not pending then return true end
        tick(1)
    end
    check(false, "reward/outbox queue failed to drain within 80 simulated seconds")
    return false
end
local function checkpoint(stage)
    local account_profiles = {}
    for id = 0, 3 do account_profiles[tostring(id)] = profiles.get_account_profile(id) or false end
    rpc({kind = "checkpoint", stage = stage, profiles = account_profiles})
end
local function challenge(id, name, seq)
    return action("challenge " .. name .. " source=" .. id .. " sequence=" .. seq,
        function() return cooperative.record_challenge(id, name, seq, fixture.difficulty) end)
end
local function run_round(scene, round)
    fixture = rpc({kind = "begin", scene = scene, round = round})
    bus.reset(); scheduler.clear(); context._reset_for_test(); multiplayer._reset_for_test()
    clock, requests, checks, failures, operation_log, actors = 0, 0, 0, {}, {}, {}
    local rand = fixture.seed
    RandomInt = function(low, high)
        rand = (rand * 48271) % 2147483647
        return low + math.floor(rand / 2147483647 * (high - low + 1))
    end
    for id = 0, 3 do
        actors[id] = {account = fixture.accounts[id + 1], team = 2,
            contribution = scene == "B" and id ~= fixture.defender and 0 or 100 + id,
            wall_alive = true, position = scene == "A" and (id + 1) or 1}
        multiplayer.mark_connected(id)
    end
    actors[4] = {account = 90004, team = 2, fake = true}
    actors[5] = {account = 90005, team = 1}
    require("config/generated/archive_http_bundle").hash = fixture.bundle_hash
    setup.init(fixture.session)
    check(setup.select_mode(0, "standard", fixture.session).ok, "real match setup selected standard mode")
    profiles.init({provider = provider})
    for id = 0, 3 do
        if not (round == 2 and id == 3) then
            check(profiles.load_player(id, "offline_stress").ok, "real profile loader accepts own account " .. id)
        end
    end
    archive.init(); archive.set_clock(function() return fixture.server_now end); cooperative.init()
    check(cooperative.begin({0, 1, 2, 3, 4, 5}, fixture.difficulty), "real frozen roster excludes fake/spectator")
    checkpoint("initial")
    for _, id in ipairs(fixture.order) do
        action("clear player=" .. id, function()
            bus.emit("archive.final_wave_cleared", {player_id = id, difficulty_id = fixture.difficulty, cooperative_win = 1})
            bus.emit("archive.final_wave_cleared", {player_id = id, difficulty_id = fixture.difficulty, cooperative_win = 1})
        end)
    end
    if round == 2 then
        check(archive.has_pending(3), "late profile retains clear intent")
        check(profiles.load_player(3, "late_profile").ok, "late profile eventually loads")
    end
    drain(); checkpoint("clear")
    for index, name in ipairs(fixture.challenges) do
        local source = scene == "B" and fixture.defender or fixture.order[index]
        local result = challenge(source, name, fixture.seed + index)
        check(result and result.ok and result.recipients == 4, "four eligible recipients for " .. name)
        check(challenge((source + 1) % 4, name, fixture.seed + index + 90).duplicate,
            "other summoner cannot repeat " .. name)
        tick(1)
    end
    if fixture.difficulty_number < 4 then
        check(not challenge(fixture.defender, "shadow_4", 98).ok, "locked shadow4 rejected by formal CSV difficulty")
    end
    drain(); checkpoint("challenge")
    for wave = 1, 30 do
        local source = scene == "B" and fixture.defender or fixture.order[(wave - 1) % 4 + 1]
        local result = cooperative.record_endless_wave(source, wave, fixture.difficulty_number)
        check(result.ok and result.recipients == 4, "full four-player endless wave " .. wave)
        if wave <= 20 then
            check(cooperative.record_endless_wave((source + 1) % 4, wave, fixture.difficulty_number).duplicate,
                "overlapping endless run deduplicates layer " .. wave)
        end
        if wave % 7 == 0 then tick(1) end
    end
    drain(); checkpoint("endless")
    if round == 4 then
        rpc({kind = "arm", mode = "hold", player = 3, challenge = "shadow_1"})
        check(challenge(0, "shadow_1", 71).recipients == 4, "pre-disconnect event freezes four recipients")
        multiplayer.mark_disconnected(3)
        multiplayer.defeat(2, "offline_qualification_failure")
        check(challenge(0, "social_ex", 72).recipients == 2, "disconnected and defeated get no new event")
        check(not challenge(2, "social_beast", 73).ok, "defeated player cannot source reward")
        rpc({kind = "release"}); drain()
        multiplayer.mark_connected(3)
        check(challenge(3, "social_ex", 74).duplicate, "reconnect never claims old event")
    elseif round == 5 then
        local original = archive.record_challenge
        local missing = true
        archive.record_challenge = function(id, ...)
            if id == 1 and missing then error("offline_injected_handoff_failure") end
            return original(id, ...)
        end
        check(challenge(0, "shadow_1", 81).recipients == 4, "outbox freezes all shares before handoff failure")
        check(cooperative.has_pending(), "outbox owns handoff failure")
        multiplayer.mark_disconnected(1)
        missing = false; archive.record_challenge = original
        tick(1); drain()
        check(not cooperative.has_pending(), "outbox delivers pre-disconnect intent exactly once")
        multiplayer.mark_connected(1)
        check(challenge(1, "shadow_1", 82).duplicate, "retry and summoner change do not reroll")
    else
        check(challenge(scene == "B" and fixture.defender or fixture.order[1], fixture.additional_shadow, 61).recipients == 4,
            "additional low-tier shared shadow still gives all four")
        drain()
    end
    checkpoint("final")
    check(not cooperative.record_challenge(4, "social_beast", 91, fixture.difficulty).ok, "fake source rejected")
    check(not cooperative.record_challenge(5, "social_beast", 92, fixture.difficulty).ok, "spectator source rejected")
    for id = 0, 3 do
        check(not archive.has_pending(id), "account queue drained player " .. id)
        if scene == "B" and id ~= fixture.defender then
            check(actors[id].contribution == 0 and actors[id].wall_alive,
                "zero-damage wall participant remains eligible player " .. id)
        end
    end
    rpc({kind = "end", checks = checks, failures = failures, requests = requests, operations = operation_log})
end
for _, scene in ipairs({"A", "B"}) do
    for round = 1, 5 do
        local ok, error_message = pcall(run_round, scene, round)
        if not ok then rpc({kind = "fatal", scene = scene, round = round, error = tostring(error_message)}) end
    end
end
rpc({kind = "done"})
