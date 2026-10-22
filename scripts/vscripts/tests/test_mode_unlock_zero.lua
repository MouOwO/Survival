package.path = "scripts/vscripts/?.lua;" .. package.path
local release_profile = require("tests/development_release_profile")
local release = require("config/mode_release_config")
release.all_difficulties_unlocked = false
local released_modes = {"standard", "rich", "cold", "pure"}
local maximum = {standard=10, rich=30, cold=50, pure=10}
-- Exercise the engine chat dispatcher, authenticated profile/HTTP flow and
-- real selection permissions together. Only engine APIs and unrelated chat
-- commands are stubbed; no fake permission or provider replaces the code under test.
package.path = "scripts/vscripts/?.lua;" .. package.path
local encoder = require("core/json_encoder")
local decoder = require("core/json_decoder")
local bus, events = require("core/event_bus"), require("core/events")
local tools, cheats, host, clock = false, false, 0, 100
local accounts = {[0] = 9000000123, [1] = 9000000456}
local tasks, requests, notifications, chat, loading_ticks, refreshes = {}, {}, {}, nil, 0, {}
local players = {[0] = {id=0}, [1] = {id=1}}
package.loaded["core/test_access_policy"] = {
    enabled=function() return true end,
    allowed=function(id) return players[id] ~= nil end,
    enforce=function(id) return players[id] ~= nil end,
}
DOTA_MAX_TEAM_PLAYERS = 2
IsServer = function() return true end
IsInToolsMode = function() return tools end
Time = function() return clock end
GameRules = {
    IsCheatMode = function() return cheats end,
    PlayerHasCustomGameHostPrivileges = function(_, player) return player.id == host end,
    GetGameModeEntity = function() return players end,
    GetGameTime = function() return clock end,
}
PlayerResource = {
    IsValidPlayerID = function(_, id) return players[id] ~= nil end,
    IsFakeClient = function() return false end,
    GetPlayer = function(_, id) return players[id] end,
    GetTeam = function() return 2 end,
    GetConnectionState = function() return 2 end,
    GetSteamAccountID = function(_, id) return accounts[id] or 0 end,
}
Convars = {RegisterConvar=function() end, GetStr=function(_, key)
    if key == "survival_fishing_api_token" then return "fictional-test-token" end
    if key == "survival_archive_http_enabled" then return "1" end
    return ""
end}
CustomGameEventManager = {RegisterListener=function() end, Send_ServerToPlayer=function() end}
ListenToGameEvent = function(name, handler)
    assert(name == "player_chat"); chat = handler
end
CreateHTTPRequestScriptVM = function(method, url)
    local request = {method=method, url=url}
    requests[#requests + 1] = request
    function request:SetHTTPRequestHeaderValue() end
    function request:SetHTTPRequestAbsoluteTimeoutMS() end
    function request:SetHTTPRequestRawPostBody(_, body) self.body = decoder.decode(body) end
    function request:Send(callback) self.complete = callback end
    return request
end
package.loaded["core/logger"] = {info=function() end, warn=function() end}
package.loaded["core/scheduler"] = {
    every=function(_, fn, key) tasks[key] = fn end,
    after=function(_, fn, key) tasks[key or tostring(fn)] = fn end,
    cancel=function(key) tasks[key] = nil end,
}
package.loaded["systems/player_entitlement_service"] = {replace_all=function() end}
package.loaded["systems/startup_loading_service"] = {
    selection_player_ids=function() return {0,1} end,
    tick=function() loading_ticks = loading_ticks + 1 end,
}
package.loaded["systems/wave_system"] = {
    refresh_selection=function(reason) refreshes[#refreshes + 1] = reason end,
}
for _, name in ipairs({
    "debug/weapon_cheat_handlers", "debug/research_technology_test",
    "debug/dev_asset_preload", "debug/health_cheat", "debug/armor_engine_diagnostic",
    "systems/building_system", "systems/rogue_reward_service", "systems/fishing_service",
    "systems/player_gameplay_stats_order_service", "systems/monster_corpse_lifecycle_service",
}) do package.loaded[name] = {} end
package.loaded["debug/attack_speed_cheat"] = {init=function() end}
package.loaded["systems/player_context_service"] = {
    active_player_ids=function() return {0,1} end,
    is_defeated=function() return false end,
}
local setup = require("systems/match_setup_service")
local profiles = require("systems/player_profile_service")
local test = require("debug/mode_unlock_test")
local difficulty = require("config/difficulty_config")
local team = require("systems/team_difficulty_service")
-- Capture a legitimate development callback, then verify call-time revocation.
tools = true
require("debug/cheat_command_service").init()
tools = false
local serial = 0
local function fresh()
    serial = serial + 1
    bus.reset()
    bus.subscribe(events.UI_NOTIFICATION, function(payload) notifications[#notifications + 1] = payload end)
    setup.init("zero-unlock-test-session-" .. serial)
    profiles.init()
    assert(not test.is_enabled(), "new match setup must reset the test grant")
end
local function command(text, id)
    chat({playerid=id or 0, text=text})
end
local function empty_progress()
    return {loaded=true, clear_counts={}, standard_clear_counts={},
        rich_clear_counts={}, cold_clear_counts={}, scourge_clear_counts={},
        ruins_clear_counts={}, celestial_clear_counts={}, mode_clear_counts={pure={}}}
end
local function quotas()
    local summary = {day_key=tostring(require("systems/archive_calendar").day()), by_key={}}
    for _, key in ipairs({"clear", "mode_rich", "mode_cold", "mode_scourge"}) do
        summary.by_key[key] = {key=key, limit=3, earned=3, remaining=0, capped=1}
    end
    return summary
end
local function respond(value, status, index)
    requests[index or #requests].complete({StatusCode=status or 200, Body=encoder.encode(value)})
end
local function authenticate(id, progress)
    local result = profiles.authenticate_player(id, "zero_unlock_test")
    assert(result.ok and result.pending)
    local request = requests[#requests]
    assert(request.url:match("/v1/session/authenticate$") and request.body.mode == nil,
        "test admission must use the real auth-only endpoint")
    respond({authenticated=true, account_id=tostring(accounts[id]),
        match_session_id=setup.get_session_id(), progression=progress or empty_progress(), daily_limits=quotas()})
    assert(profiles.is_authenticated_for_account(id, tostring(accounts[id])))
end
local function authenticate_team(progress)
    authenticate(0, progress); authenticate(1, progress)
end
local function mode_option(mode)
    for _, row in ipairs(setup.snapshot().mode_options) do
        if row.mode_id == mode then return row end
    end
    error("missing mode " .. tostring(mode))
end
local function raw_snapshot(id, mode)
    return {schema_version=1, account_id=tostring(accounts[id]), revision=7,
        mode=mode, match_session_id=setup.get_session_id(), progression=empty_progress(),
        save={gameplay_stats={initial_wood=777}, archive={clear_counts={},
            standard_clear_counts={}, rich_clear_counts={}, cold_clear_counts={}, scourge_clear_counts={}},
            content_inventory={existing_item=2}}, entitlements={}, achievements={}, public={}}
end

fresh()
assert(type(chat) == "function" and not test.is_enabled())
command("0")
assert(not test.is_enabled() and #notifications == 0,
    "an invocation outside Tools is ignored before dispatch")
tools = true
command("0 extra")
assert(not test.is_enabled(), "numeric command rejects extra arguments")
command("0", 1)
assert(not test.is_enabled(), "a non-host cannot change the match's test permission")
chat({playerid=99, text="0"})
assert(not test.is_enabled(), "invalid engine actors cannot enable the test flag")
local before_ticks, before_refresh = loading_ticks, #refreshes
command("  0  ")
assert(test.is_enabled() and loading_ticks == before_ticks + 1
    and #refreshes == before_refresh + 1 and refreshes[#refreshes] == "mode_unlock_test",
    "actual chat success refreshes both loading and wave permission snapshots")
assert(not team.current("cold").ready and mode_option("cold").pending == 1,
    "test permission never invents authentication for an unread account")
authenticate(0)
assert(not team.current("cold").ready, "one authenticated host cannot replace a teammate's admission")
authenticate(1)
local real_counts = encoder.encode(profiles.get_authenticated_progression(0))
local real_quota = encoder.encode(profiles.get_authenticated_daily_limits(0))
assert(#setup.snapshot().mode_options == #released_modes, "only released modes enter the UI")
for _, mode in ipairs(released_modes) do
    local option = mode_option(mode)
    assert(option.unlocked == 1 and option.pending == 0,
        "all released UI entries use the server's active test permission: " .. mode)
    assert(option.daily_capped ~= 1 and option.daily_capped ~= true,
        "a capped reward counter must not close an isolated test entry")
    do
        local permission = team.current(mode)
        assert(permission.ready and permission.max_difficulty_id == "N" .. maximum[mode]
            and #permission.options == maximum[mode]
            and permission.difficulty_access_policy == "read_only_acceptance")
        for number, row in ipairs(permission.options) do
            assert(row.difficulty_id == "N" .. number and row.unlocked == 1,
                "test team must actually admit every supported difficulty")
            assert(difficulty.is_unlocked(row.difficulty_id, profiles.get_progression(0, mode), mode))
        end
    end
end
assert(encoder.encode(profiles.get_authenticated_progression(0)) == real_counts
    and encoder.encode(profiles.get_authenticated_daily_limits(0)) == real_quota,
    "permission bypass leaves authoritative clear counters and daily quotas unchanged")
local ok = test.enable(0)
assert(ok and test.is_enabled(), "repeating the active grant is idempotent")

-- Every released choice must enter through the real profile loader. The two
-- advanced test sessions intentionally use a standard durable backend binding;
-- only their local combat projection receives the true gameplay mode marker.
for _, mode in ipairs(released_modes) do
    fresh(); authenticate_team()
    command("0")
    assert(test.is_enabled() and setup.select_mode(0, mode, setup.get_session_id()).ok,
        "real mode selection must accept the test grant: " .. mode)
    assert(setup.get_mode() == mode, "wave and spawn consumers retain the actual gameplay mode")
    assert(setup.select_mode(0, mode == "pure" and "standard" or "pure", setup.get_session_id()).error == "mode_locked",
        "the debug grant must not silently switch a selected match")
    assert(profiles.load_player(0).pending)
    local request = requests[#requests]
    local expected_mode = mode == "pure" and "pure" or "standard"
    assert(request.url:match("/v1/session/login$") and request.body.mode == expected_mode,
        "advanced test login must avoid backend predecessor gates without faking its account progress")
    local response = raw_snapshot(0, expected_mode)
    respond(response)
    local profile = profiles.get_profile(0)
    assert(profile and profiles.is_loaded_for_account(0, tostring(accounts[0])),
        "test selection must reach a fully loaded combat account: " .. mode)
    if mode == "rich" or mode == "cold" or mode == "scourge" then
        assert(profile.game_mode == mode and tonumber(profile.debug_mode_unlock) == 1,
            "advanced standard reply needs an explicit local test/gameplay projection")
        assert(profile.save.gameplay_stats.initial_wood == 777 and profile.save.content_inventory.existing_item == 2)
    end
    assert(next(profiles.get_authenticated_progression(0).standard_clear_counts) == nil
        and next(profiles.get_authenticated_progression(0).rich_clear_counts) == nil
        and next(profiles.get_authenticated_progression(0).cold_clear_counts) == nil,
        "successful test login must not fabricate predecessor clears")
    assert(profiles.refresh_player(0, "test_read_again").pending)
    assert(requests[#requests].url:match("/v1/profile$"), "subsequent reads reuse the immutable durable session")
    respond(response)
    assert(profiles.get_profile(0), "refresh must retain the local projection and account binding")
end

-- The live provider must reject every account-write family before native HTTP
-- creation. This exercises its real transport, not a fake archive adapter.
local provider = profiles.get_provider()
local before_requests = #requests
for _, method in ipairs({"archive_submit", "online_checkpoint", "archive_submit_endless_batch"}) do
    local rejected
    provider[method]({account_id=tostring(accounts[0]),
        commands={{id="isolated-session:endless:1", kind="endless", wave=1, difficulty=1}},
        command={kind="clear"}},
        function() error("isolated test write unexpectedly succeeded: " .. method) end,
        function(error_code) rejected = error_code end)
    if #requests == before_requests + 1 then
        assert(method == "archive_submit_endless_batch" and requests[#requests].url:match("/v1/archive/config$"),
            "a capability read is the only additional HTTP request permitted")
        respond({capabilities={endless_batch=1}})
        before_requests = #requests
    end
    assert(rejected == "mode_unlock_test_read_only" and #requests == before_requests,
        "test account writes must fail before transport: " .. method)
end
local profile_before = encoder.encode(profiles.get_profile(0))
local save = profiles.update_save_sections(0, {archive={clear_counts={n10=100}}}, "test_must_not_save")
assert(not save.ok and save.error == "mode_unlock_test_read_only"
    and encoder.encode(profiles.get_profile(0)) == profile_before and #requests == before_requests,
    "local save APIs cannot turn the test grant into account progression")

-- Use the actual reward queue: a test victory is intentionally skipped and
-- never becomes a successful permanent receipt or a stuck retry job.
package.loaded["systems/title_presentation_service"] = {init=function() end}
local archive = require("systems/archive_service")
archive.init()
for _, id in ipairs({0,1}) do
    local skipped = archive.record_clear(id, "N10", 0)
    assert(skipped.ok and skipped.skipped and skipped.test_only and not skipped.receipt,
        "test clears must be explicitly skipped rather than acknowledged as durable wins")
    assert(not archive.has_pending(id), "test wins must not remain in the remote retry queue")
end
assert(#requests == before_requests and encoder.encode(profiles.get_profile(0)) == profile_before)

-- Cheat-enabled matches use the same host requirement; resetting the match
-- removes the temporary grant and restores the genuine advanced login mode.
fresh(); tools, cheats = false, true
command("0", 1)
assert(not test.is_enabled(), "cheats do not grant a non-host selection authority")
command("0")
assert(not test.is_enabled(), "sv_cheats cannot replace the Tools and development gate")
tools = true
command("0", 1)
assert(not test.is_enabled(), "development Tools still requires the real selector")
command("0")
assert(test.is_enabled(), "development Tools host may enable the isolated test")
authenticate_team()
assert(setup.select_mode(0, "standard", setup.get_session_id()).ok)
assert(profiles.load_player(0).pending)
respond(raw_snapshot(0, "standard"))
assert(difficulty.is_unlocked("N10", profiles.get_progression(0, "standard"), "standard"))
-- sv_cheats may be turned off while the already-unlocked wave runs. Revoking
-- the permission gate must never re-enable settlement of this test match.
cheats, tools = false, false
assert(test.is_enabled(), "the isolation grant stays latched until match reset even if cheats are disabled")
local rejected, prior = nil, #requests
profiles.get_provider().archive_submit({account_id=tostring(accounts[0]), command={kind="standard_clear"}},
    function() error("disabled cheats cannot authorize a test match write") end,
    function(error_code) rejected = error_code end)
assert(rejected == "mode_unlock_test_read_only" and #requests == prior)
local latched_clear = archive.record_clear(0, "N10", 0)
assert(latched_clear.ok and latched_clear.skipped and not archive.has_pending(0),
    "turning cheats off must not persist a test-unlocked standard N10")
fresh(); tools, cheats = true, false
local advanced_progress = empty_progress()
advanced_progress.standard_clear_counts.n10 = 1
advanced_progress.standard_clear_counts.n5 = 1
advanced_progress.rich_clear_counts.n10 = 1
advanced_progress.cold_clear_counts.n10 = 1
-- Avoid daily exhaustion here to inspect the ordinary, non-test backend path.
local normal_quotas = quotas
quotas = function() return nil end
authenticate_team(advanced_progress)
quotas = normal_quotas
assert(not test.is_enabled() and setup.select_mode(0, "cold", setup.get_session_id()).ok)
assert(profiles.load_player(0).pending and requests[#requests].body.mode == "cold",
    "a new normal match must retain the real backend advanced-mode gate")
local normal_response = raw_snapshot(0, "standard")
normal_response.game_mode = "cold"
normal_response.progression = advanced_progress
respond(normal_response)
assert(profiles.get_profile(0) and not profiles.get_profile(0).debug_mode_unlock,
    "normal advanced profile receipts never receive the local debug projection")
assert(not difficulty.is_unlocked("N10", profiles.get_progression(0, "cold"), "cold"),
    "new match restores the real own-mode N5 difficulty requirement")
assert(not test.enable(0), "an already-selected normal match cannot acquire a different durable test binding")
print("MODE_UNLOCK_ZERO_PASS: real chat/auth/mode/team/difficulty/HTTP entry, four released modes, N1-N50, UI refresh, reset and isolated writes")

-- The configured acceptance arena also starts through the actual startup
-- service in a production build, with no Tools/cheats/chat command. Keep the
-- real authentication and profile HTTP flow; stub only native engine APIs,
-- the completed asset preloader and multiplayer connection enumeration.
release_profile.channel = "production"
tools, cheats = false, false
assert(require("core/release_policy").is_production())
local startup_listeners = {}
for _, player in pairs(players) do
    function player:GetPlayerID() return self.id end
    function player:IsNull() return false end
end
function players:SetContextThink(_, callback) self.startup_think = callback end
GameRules.State_Get = function() return 3 end
DOTA_GAMERULES_STATE_CUSTOM_GAME_SETUP = 2
EntIndexToHScript = function(index) return players[index - 200] end
CustomGameEventManager.RegisterListener = function(_, name, handler)
    startup_listeners[name] = handler
    return name
end
CustomGameEventManager.UnregisterListener = function(_, name) startup_listeners[name] = nil end
package.loaded["systems/multiplayer_player_service"] = {
    participating_player_ids=function() return {0,1} end,
    is_disconnected=function() return false end,
}
package.loaded["systems/startup_asset_preload_service"] = {snapshot=function()
    return {total=1, ready=1, failed=0, progress=100, complete=true}
end}
package.loaded["systems/startup_loading_service"] = nil
local startup = require("systems/startup_loading_service")
local function start_real_startup(automatic, without_quota)
    release.all_difficulties_unlocked = automatic
    bus.reset()
    profiles.init()
    local prior = #requests
    startup.init()
    assert(test.is_enabled() == automatic and setup.snapshot().read_only_acceptance == automatic,
        "real startup owns the per-match automatic acceptance latch")
    assert(not startup.is_ready() and not team.current("cold").ready,
        "automatic acceptance still requires both authenticated accounts")
    assert(#requests == prior + 2, "real startup must request both account authentications")
    for index=prior+1,prior+2 do
        local request = requests[index]
        assert(request.url:match("/v1/session/authenticate$") and request.body.mode == nil)
        local quota = not without_quota and quotas() or nil
        respond({authenticated=true, account_id=request.body.account_id,
            match_session_id=setup.get_session_id(), progression=empty_progress(), daily_limits=quota}, 200, index)
    end
    startup.tick()
    assert(not startup.is_ready(), "HTTP authentication cannot replace the client UI handshake")
    for _, id in ipairs({0,1}) do
        startup_listeners.survival_loading_client_ready(200+id, {session_id=setup.get_session_id()})
    end
    assert(startup.is_ready() and not startup.is_gameplay_ready(),
        "mode combat profiles still gate gameplay after authenticated admission")
end
local function assert_isolated_writes(mode)
    local count = #requests
    for _, id in ipairs({0,1}) do
        local before = encoder.encode(profiles.get_profile(id))
        for _, method in ipairs({"archive_submit", "online_checkpoint", "archive_submit_endless_batch"}) do
            local failure
            profiles.get_provider()[method]({account_id=tostring(accounts[id]),
                commands={{id="acceptance:endless:1", kind="endless", wave=1, difficulty=1}},
                command={kind="clear"}},
                function() error("automatic acceptance persisted an account write: " .. method) end,
                function(code) failure=code end)
            if #requests == count + 1 then
                assert(method == "archive_submit_endless_batch"
                    and requests[#requests].url:match("/v1/archive/config$"))
                respond({capabilities={endless_batch=1}})
                count = #requests
            end
            assert(failure == "mode_unlock_test_read_only" and #requests == count,
                "every account write transport is blocked before creating HTTP: " .. method)
        end
        local changed = profiles.update_save_sections(id,
            {archive={clear_counts={n10=100}}}, "automatic_acceptance_must_not_save")
        assert(not changed.ok and changed.error == "mode_unlock_test_read_only")
        for _, result in ipairs({archive.record_clear(id, "N"..maximum[mode], 0),
            archive.record_boss(id, "acceptance-boss"), archive.record_endless_wave(id, 1, 1)}) do
            assert(result.ok and result.skipped and result.test_only and not result.receipt,
                "test victories and rewards must never become durable receipts")
        end
        assert(not archive.has_pending(id) and encoder.encode(profiles.get_profile(id)) == before)
    end
    assert(#requests == count, "isolated rewards never create a write or retry transport")
end
for _, mode in ipairs(released_modes) do
    start_real_startup(true)
    assert(not test.enable(0), "production still rejects manually invoking the developer grant")
    local snapshot = startup.snapshot().setup
    assert(snapshot.read_only_acceptance and snapshot.difficulty_access_policy == "read_only_acceptance")
    for _, candidate in ipairs(released_modes) do
        local option, permission = mode_option(candidate), team.current(candidate)
        assert(option.unlocked == 1 and option.pending == 0 and option.daily_capped ~= 1,
            "empty clears and exhausted daily quotas cannot close acceptance modes")
        assert(permission.ready and permission.max_difficulty_id == "N" .. maximum[candidate]
            and #permission.options == maximum[candidate])
        for _, row in ipairs(permission.options) do assert(row.unlocked == 1) end
    end
    for _, closed in ipairs({"scourge", "ruins", "celestial", "fishing"}) do
        assert(setup.select_mode(0, closed, setup.get_session_id()).error == "mode_not_released",
            "acceptance must retain the configured four-mode release boundary")
    end
    local prior = #requests
    startup_listeners.survival_loading_mode_select(200,
        {session_id=setup.get_session_id(), mode_id=mode})
    assert(setup.get_mode() == mode and #requests == prior+2)
    for index=prior+1,prior+2 do
        local request = requests[index]
        local expected = mode == "pure" and "pure" or "standard"
        assert(request.url:match("/v1/session/login$") and request.body.mode == expected,
            "acceptance uses an ordinary read binding without advanced backend entry gates")
        local id = request.body.account_id == tostring(accounts[0]) and 0 or 1
        respond(raw_snapshot(id, expected), 200, index)
    end
    startup.tick()
    assert(startup.is_gameplay_ready() and startup.is_player_ready(0) and startup.is_player_ready(1),
        "every acceptance mode reaches real HTTP-profile-ready gameplay")
    assert(profiles.get_profile(0).game_mode == mode and profiles.get_profile(0).debug_mode_unlock == 1)
    assert(next(profiles.get_authenticated_progression(0).standard_clear_counts) == nil
        and next(profiles.get_authenticated_progression(0).rich_clear_counts) == nil
        and next(profiles.get_authenticated_progression(0).cold_clear_counts) == nil,
        "acceptance never fabricates permanent entry or tier clears")
    assert(profiles.get_authenticated_daily_limits(0).by_key.mode_cold.capped == 1,
        "opening acceptance entry leaves the account's authentic exhausted quota untouched")
    archive.init()
    assert_isolated_writes(mode)
    release.all_difficulties_unlocked = false
    assert(test.is_enabled() and setup.snapshot().read_only_acceptance
        and team.current(mode).max_difficulty_id == "N"..maximum[mode],
        "turning the switch off during play cannot change this match's admission or isolation")
    assert_isolated_writes(mode)
end
start_real_startup(false)
assert(not setup.snapshot().read_only_acceptance
    and startup.snapshot().setup.difficulty_access_policy == "progression")
assert(mode_option("cold").unlocked == 0 and team.current("standard").max_difficulty_id == "N4",
    "a new normal match restores genuine mode and same-mode tier requirements")
assert(setup.select_mode(0, "cold", setup.get_session_id()).error == "mode_not_unlocked")
assert(setup.select_mode(0, "standard", setup.get_session_id()).error == "mode_daily_limit_reached",
    "a new normal match restores the authentic exhausted daily quota")
start_real_startup(false, true)
local count = #requests
startup_listeners.survival_loading_mode_select(200,
    {session_id=setup.get_session_id(), mode_id="standard"})
assert(#requests == count+2)
for index=count+1,count+2 do
    local id = requests[index].body.account_id == tostring(accounts[0]) and 0 or 1
    respond(raw_snapshot(id, "standard"), 200, index)
end
startup.tick()
assert(startup.is_gameplay_ready() and not profiles.get_profile(0).debug_mode_unlock)
local normal_error
count = #requests
profiles.get_provider().archive_submit({account_id=tostring(accounts[0]), command={kind="standard_clear"}},
    function() end, function(code) normal_error=code end)
assert(not normal_error and #requests == count+1 and requests[#requests].url:match("/v1/archive/command$"),
    "a new normal match restores the ordinary account-write transport")
print("AUTOMATIC_ACCEPTANCE_PASS: production real startup, four modes N1-N50, auth/profile readiness, exhausted quotas, all account writes isolated, midmatch latch and normal new-match restoration")
