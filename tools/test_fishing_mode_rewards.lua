-- Real profile/HTTP transport, online lifecycle, scheduler and archive coin reducer.
-- HTTP responses stand in for committed backend snapshots; no live account is changed.
package.path = "scripts/vscripts/?.lua;" .. package.path
local bus, events = require("core/event_bus"), require("core/events")
local json, decoder = require("core/json_encoder"), require("core/json_decoder")
local scheduler = require("core/scheduler")
local now, mode, session = 0, "standard", "fishing_mode_session_001"
local requests, local_rewards, local_writes, started, permanent_grants = {}, 0, 0, 0, 0
local setup = {
    get_mode = function() return mode end,
    get_profile_mode = function() return mode == "fishing" and "standard" or mode end,
    get_session_id = function() return session end,
    is_mode_selected = function() return mode ~= nil end,
}
package.loaded["systems/match_setup_service"] = setup
package.loaded["systems/startup_loading_service"] = {is_player_ready = function() return true end}
package.loaded["systems/player_context_service"] = {
    is_defeated = function() return false end,
    active_player_ids = function() return {0} end,
}
package.loaded["systems/commerce_effects"] = {owned = function() return false end, has = function() return false end}
package.loaded["core/logger"] = {info = function() end, warn = function() end}
package.loaded["systems/player_entitlement_service"] = {replace_all = function() end}
package.loaded["systems/permanent_reward_effect_service"] = {value = function() return 0 end}
GameRules = {GetGameTime = function() return now end}
PlayerResource = {
    IsValidPlayerID = function(_, id) return id == 0 end,
    GetSteamAccountID = function() return 9000000201 end,
    GetTeam = function() return 2 end,
    GetPlayer = function() return {} end,
}
RandomFloat = function() return 0 end
Convars = {RegisterConvar = function() end,
    GetStr = function(_, key) return key == "survival_fishing_api_token" and "fixture-only-token" or "" end}
CreateHTTPRequestScriptVM = function(_, url)
    local request = {url = url}
    requests[#requests + 1] = request
    function request:SetHTTPRequestHeaderValue() end
    function request:SetHTTPRequestAbsoluteTimeoutMS() end
    function request:SetHTTPRequestRawPostBody(_, body) self.body = decoder.decode(body) end
    function request:Send(callback) self.complete = callback end
    return request
end
local function respond(index, response)
    local request = requests[index]
    assert(request and not request.responded, "one HTTP completion per request")
    request.responded = true
    request.complete({StatusCode = 200, Body = json.encode(response)})
end
bus.handle_request(events.RESOURCE_ADD_REQUEST, function() local_writes = local_writes + 1; return {ok = true} end)
bus.handle_request(events.TECHNOLOGY_STATS_ROGUE_ADD_REQUEST, function() local_writes = local_writes + 1; return {ok = true} end)
bus.handle_request(events.BUILDING_LIST_REQUEST, function() return {buildings = {}} end)
bus.subscribe(events.FISHING_STARTED, function() started = started + 1 end)
bus.subscribe(events.FISHING_REWARD_GRANTED, function(payload)
    if payload.grant_id then permanent_grants = permanent_grants + 1
    else local_rewards = local_rewards + 1 end
end)
local fishing = require("systems/fishing_service")
fishing.init()
assert(fishing.grant(0, "large_lobster_gold_per_second_1").ok)
assert(fishing.grant(0, "large_fish_wall_health_1000").ok)
bus.emit(events.WAVE_CHANGED, {difficulty_selected = true})
assert(started == 1 and local_rewards == 2)
local before_writes, before_rewards = local_writes, local_rewards
mode = "fishing"
local wall_updates = 0
EntIndexToHScript = function() return {
    IsNull = function() return false end, IsAlive = function() return true end,
    GetMaxHealth = function() return 100 end, GetHealth = function() return 100 end,
    SetBaseMaxHealth = function() wall_updates = wall_updates + 1 end,
    SetMaxHealth = function() wall_updates = wall_updates + 1 end,
    SetHealth = function() wall_updates = wall_updates + 1 end,
} end
assert(fishing.grant(0, "large_fish_wall_health_1000").error == "fishing_mode_match_rewards_disabled")
bus.emit(events.BUILDING_CREATED, {building_id = "wall", player_id = 0, entindex = 100})
now = 480; scheduler.think()
assert(local_writes == before_writes and local_rewards == before_rewards and wall_updates == 0,
    "even an existing local timer/income/wall effect must not pay in fishing mode")
fishing.init()
bus.emit(events.WAVE_CHANGED, {difficulty_selected = true})
assert(started == 1, "fishing must ignore even an unexpected difficulty-selected event")
assert(fishing.grant(0, "random").error == "fishing_mode_match_rewards_disabled")
for _, normal in ipairs({"pure", "standard"}) do
    mode = normal
    assert(fishing.grant(0, "seed_wood_20").ok, "ordinary modes retain local rewards")
end
mode = "fishing"
scheduler.clear(); now = 0
local profiles = require("systems/player_profile_service")
profiles.init()
local remote = {schema_version = 1, account_id = "9000000201", revision = 1,
    match_session_id = session, mode = "standard",
    progression = {loaded = true, clear_counts = {}}, entitlements = {}, achievements = {}, public = {},
    save = {gameplay_stats = {initial_wood = 10}, archive = {}, content_inventory = {}, fishing_inventory = {}}}
assert(profiles.load_player(0).pending)
assert(requests[1].url:match("/v1/session/login$") and requests[1].body.mode == "standard")
respond(1, remote)
assert(setup.get_mode() == "fishing" and profiles.get_profile(0).mode == "standard")
assert(profiles.is_loaded_for_account(0, "9000000201"), "standard backend profile binds to fishing gameplay")
local coins = require("systems/archive_online_rewards")
local online = require("systems/online_time_service")
online.init()
bus.emit(events.HERO_READY, {player_id = 0})
assert(#requests == 2 and requests[2].url:match("/v1/online%-time/checkpoint$"))
assert(requests[2].body.match_session_id == session and requests[2].body.final == false)
respond(2, {profile = remote, elapsed_seconds = 0, online_seconds_total = 0, grants = {}})
local grant = {grant_id = "committed-fixture-grant-001", reward_id = "star_blessing_001",
    definition_version = 3, amount = 10}
for minute = 1, 10 do
    now = minute * 60
    scheduler.think()
    local index = #requests
    assert(requests[index].url:match("/v1/online%-time/checkpoint$") and not requests[index].responded)
    assert(coins.apply({kind = "online_checkpoint", session = "backend_fixture_clock",
        actual_seconds = now, map_seconds = now}, remote.save.archive, remote.save.gameplay_stats,
        function() end, remote.save))
    remote.revision = remote.revision + 1
    if minute == 10 then
        remote.save.fishing_inventory.star_blessing_001 = 1
        remote.save.gameplay_stats.initial_wood = 20
    end
    respond(index, {profile = remote, elapsed_seconds = 60, online_seconds_total = now,
        grants = minute == 10 and {grant} or {}})
    if minute == 10 then
        assert(requests[#requests].url:match("/v1/profile$"), "permanent award reuses authoritative profile refresh")
        respond(#requests, remote)
    end
    assert(profiles.get_profile(0).save.archive.online.coins == minute,
        "existing online reducer/HTTP snapshot continues one coin per minute")
end
local profile = profiles.get_profile(0)
assert(profile.save.gameplay_stats.initial_wood == 20 and profile.save.fishing_inventory.star_blessing_001 == 1)
assert(permanent_grants == 1, "the real online lifecycle announces the committed permanent grant once")
now = 660; scheduler.think()
respond(#requests, {profile = remote, grants = {grant}})
respond(#requests, remote)
assert(permanent_grants == 1, "repeated grant receipts do not publish twice")
online.disconnect(0)
assert(requests[#requests].body.final == true, "disconnect retains the existing final online checkpoint")
respond(#requests, {profile = remote, grants = {}})
local old_count = #requests
now = 720; scheduler.think()
assert(#requests == old_count, "closed online session stops heartbeats")
session = "fishing_mode_session_002"
remote.match_session_id = session
assert(profiles.load_player(0).pending)
assert(requests[#requests].url:match("/v1/session/login$") and requests[#requests].body.mode == "standard")
respond(#requests, remote)
assert(profiles.get_profile(0).save.fishing_inventory.star_blessing_001 == 1
    and profiles.get_profile(0).save.archive.online.coins == 10,
    "new gameplay session reloads the permanent inventory and coins from the account snapshot")
local mismatch
profiles.get_provider().fetch_snapshot("9000000201", function() error("wrong backend mode accepted") end,
    function(reason) mismatch = reason end)
remote.mode = "fishing"
respond(#requests, remote)
assert(mismatch == "match_profile_mismatch", "mapping never weakens backend mode validation")
print("FISHING_MODE_REWARDS_PASS: local awards/timers/effects blocked; pure/standard preserved; standard login identity, online checkpoint, permanent inventory refresh/dedup, minute coins, disconnect and new-session reload")
