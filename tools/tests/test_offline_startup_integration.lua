-- Real startup/profile/offline/match/difficulty modules, with engine I/O only
-- replaced. This catches identities that pass the provider's own API but can
-- never satisfy the engine-owned startup roster.
package.path = "scripts/vscripts/?.lua;" .. package.path
local clock, native_state, unique = 0, 2, 0
local steam_account = 885195478
local http_calls, disk_calls, admission_calls, gameplay_calls = 0, 0, 0, 0
local listeners, tasks, responses, published = {}, {}, {}, {}
local asset = {total = 10, ready = 0, failed = 0, progress = 0, complete = false}
local values = {survival_offline_logic_test = "1"}
Convars = {
    RegisterConvar = function(_, key, default) if values[key] == nil then values[key] = default end end,
    GetStr = function(_, key) return values[key] or "" end,
}
IsServer = function() return true end
IsInToolsMode = function() return true end
Time = function() return clock end
DoUniqueString = function(prefix) unique = unique + 1; return prefix .. unique end
DOTA_MAX_TEAM_PLAYERS, DOTA_CONNECTION_STATE_CONNECTED = 4, 2
DOTA_TEAM_SPECTATOR, DOTA_GAMERULES_STATE_CUSTOM_GAME_SETUP = 1, 2
DisconnectClient = function() error("the approved offline owner must not be kicked") end
local player = {GetPlayerID = function() return 0 end, IsNull = function() return false end}
PlayerResource = {
    IsValidPlayerID = function(_, id) return id == 0 end,
    IsFakeClient = function() return false end,
    GetSteamAccountID = function() return steam_account end,
    GetPlayer = function(_, id) return id == 0 and player or nil end,
    GetPlayerName = function() return "Offline owner" end,
    GetConnectionState = function() return 2 end,
    GetTeam = function() return 2 end,
}
EntIndexToHScript = function(index) return index == 200 and player or nil end
GameRules = {
    GetGameSessionConfigValue = function(_, _, default) return default end,
    GetGameModeEntity = function() return {SetContextThink = function(_, name, callback) tasks[name] = callback end} end,
    State_Get = function() return native_state end,
    GetGameTime = function() return clock end,
    PlayerHasCustomGameHostPrivileges = function(_, actor) return actor == player end,
}
CustomGameEventManager = {
    RegisterListener = function(_, name, callback) listeners[name] = callback; return name end,
    UnregisterListener = function(_, name) listeners[name] = nil end,
    Send_ServerToPlayer = function(_, actor, name, payload)
        assert(actor == player); responses[name] = payload
    end,
}
CustomNetTables = {SetTableValue = function(_, name, key, value)
    published[name .. "/" .. key] = value
end}
CreateHTTPRequestScriptVM = function() http_calls = http_calls + 1; error("offline HTTP is forbidden") end
package.loaded["core/logger"] = {info = function() end, warn = function() end}
package.loaded["core/scheduler"] = {every = function(_, callback, name) tasks[name] = callback end}
package.loaded["systems/multiplayer_player_service"] = {
    participating_player_ids = function() return {0} end,
    is_disconnected = function() return false end,
}
package.loaded["systems/startup_asset_preload_service"] = {
    snapshot = function() return asset end,
    retry = function() return {ok = true} end,
}

local offline = require("debug/offline_logic_test")
local profiles = require("systems/player_profile_service")
local startup = require("systems/startup_loading_service")
local setup = require("systems/match_setup_service")
assert(offline.configure())
local original_open = io.open
io.open = function() disk_calls = disk_calls + 1; error("offline fixture file access is forbidden") end
profiles.init(offline.profile_options())
local function launch()
    startup.init({native_team_setup = true, tools_backend_wait = false,
        on_ready = function() admission_calls = admission_calls + 1 end})
    startup.gameplay_gate(function() gameplay_calls = gameplay_calls + 1 end)
end
local function tick(count)
    for _ = 1, count do clock = clock + .25; startup.tick() end
end
local function acknowledge(session)
    listeners.survival_loading_client_ready(200, {session_id = session or setup.get_session_id()})
end
local function select_mode(mode)
    listeners.survival_loading_mode_select(200, {session_id = setup.get_session_id(), mode_id = mode})
    assert(responses.survival_loading_mode_result.success == 1)
end

launch()
assert(startup.is_native_team_setup() and not startup.is_ready())
local first_session = setup.get_session_id()
acknowledge()
assert(not startup.is_ready() and admission_calls == 0, "native host start remains mandatory")
native_state = 3
tick(2)
assert(not startup.is_ready() and startup.snapshot().players[1].authenticated,
    "real Steam identity is authenticated while real asset barrier still blocks")
assert(profiles.get_provider().resolve_account_id(0) == string.format("%.0f", steam_account))
asset = {total = 10, ready = 10, failed = 0, progress = 100, complete = true}
tick(2)
assert(startup.is_ready() and startup.snapshot().progress == 100 and admission_calls == 1,
    "real startup reaches admission rather than looping at 80 percent")
assert(not startup.is_gameplay_ready() and profiles.get_profile(0) == nil,
    "successful admission preserves the mode/profile barrier")
select_mode("pure")
tick(3)
assert(startup.is_gameplay_ready() and startup.is_player_ready(0) and gameplay_calls == 1)
local first_profile = assert(profiles.get_profile(0))
assert(first_profile.mode == "pure" and first_profile.match_session_id == first_session)
assert(first_profile.account_id == tostring(steam_account)
    and profiles.is_loaded_for_account(0, tostring(steam_account)))
assert(startup.is_difficulty_selection_ready(0), "real team difficulty accepts the offline identity")
tick(4)
assert(admission_calls == 1 and gameplay_calls == 1, "both callbacks release exactly once")

-- Reopening within the same Lua process still clears the session-memory save.
native_state = 2
launch()
local second_session = setup.get_session_id()
assert(second_session ~= first_session and not startup.is_ready())
assert(profiles.get_profile(0) == nil and not profiles.is_authenticated_for_account(0, tostring(steam_account)))
acknowledge(first_session)
native_state = 3
tick(3)
assert(not startup.is_ready() and admission_calls == 1,
    "old UI handshake cannot authenticate the new session")
acknowledge()
tick(2)
assert(startup.is_ready() and admission_calls == 2)
select_mode("standard")
tick(3)
assert(startup.is_player_ready(0) and gameplay_calls == 2)
local second_profile = profiles.get_profile(0)
assert(second_profile.account_id == first_profile.account_id
    and second_profile.match_session_id ~= first_profile.match_session_id
    and next(second_profile.save.content_inventory) == nil,
    "same Steam account is isolated by a fresh memory session")
assert(profiles.apply_snapshot(0, first_profile).error == "match_profile_mismatch")
-- All previews must work with a blank offline account, independently of the
-- separate released-tier acceptance switch, through the real startup gates.
local release = require("config/mode_release_config")
release.all_difficulties_unlocked = false
local team = require("systems/team_difficulty_service")
local mode_test = require("debug/mode_unlock_test")
local maximum = {standard=10, pure=10, rich=30, cold=50, scourge=50, ruins=50, celestial=35}
local modes = {"standard", "rich", "cold", "scourge", "ruins", "celestial", "fishing", "pure"}
for _, mode in ipairs(modes) do
    native_state = 2
    launch()
    local options = setup.snapshot().mode_options
    assert(#options == 8, "offline exposes every configured mode")
    for index, option in ipairs(options) do
        assert(option.mode_id == modes[index] and option.unlocked == 1 and option.pending == 0)
        assert(option.daily_capped == nil and option.daily_pending == nil)
    end
    assert(mode_test.is_enabled(), "offline previews keep settlement isolation even without tier acceptance")
    acknowledge()
    native_state = 3
    tick(4)
    assert(startup.is_ready())
    select_mode(mode)
    tick(3)
    assert(startup.is_gameplay_ready() and startup.is_player_ready(0), mode .. " reaches gameplay")
    local profile = assert(profiles.get_profile(0))
    assert(profile.game_mode == mode and profile.mode == (mode == "pure" and "pure" or "standard"))
    assert(next(profile.save.archive) == nil, "unlocking modes never manufactures permanent clears")
    if mode == "fishing" then
        assert(setup.is_fishing_mode() and #team.current(mode).options == 0)
    else
        local snapshot = team.current(mode)
        assert(snapshot.ready and #snapshot.options == maximum[mode])
        assert(snapshot.max_difficulty_id == "N" .. maximum[mode])
        for _, option in ipairs(snapshot.options) do assert(option.unlocked == 1) end
        assert(startup.is_difficulty_selection_ready(0))
    end
end
-- Switching the launch choice does not convert an existing preview into a
-- normal settling match; the isolation grant is latched until a fresh setup.
values.survival_offline_logic_test = "0"
assert(offline.configure() == false and not release.is_offline_preview())
assert(mode_test.is_enabled())
setup.init("normal_launch_after_offline_preview")
assert(not mode_test.is_enabled() and #setup.snapshot().mode_options == 4)
for _, mode in ipairs({"scourge", "ruins", "celestial", "fishing"}) do
    assert(not release.is_available(mode) and not release.is_difficulty_open(mode))
    assert(setup.select_mode(0, mode, setup.get_session_id()).error == "mode_not_released")
end
assert(http_calls == 0 and disk_calls == 0, "full admission and gameplay path uses no API or save files")
io.open = original_open
print("OFFLINE_STARTUP_INTEGRATION_PASS: all eight blank-profile offline modes, full difficulty ranges, real admission/profile/team gates, isolated settlement, unchanged normal release gates, no HTTP/files")
