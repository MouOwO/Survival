package.path = "scripts/vscripts/?.lua;" .. package.path
local release = require("config/mode_release_config")
release.all_difficulties_unlocked = false

local time, humans, disconnected, profiles, pending, requests, listeners, published, thinker
local engine_state, authenticated, profile_pending, profile_requests, responses, history
-- Only this fixture's synthetic roster is admitted, independent of local IDs.
local function fixture_actor(id) return humans ~= nil and humans[id] ~= nil end
package.loaded["core/test_access_policy"] = {
    enabled=function() return true end, allowed=fixture_actor, enforce=fixture_actor,
}
local asset, mode, unique, modules, asset_retry_calls, asset_retry_result = nil, nil, 0, {}, 0, nil
Time = function() return time end
DoUniqueString = function(prefix) unique = unique + 1 return prefix .. "_" .. unique end
DOTA_MAX_TEAM_PLAYERS = 8
DOTA_CONNECTION_STATE_CONNECTED = 2
DOTA_TEAM_SPECTATOR = 1
DOTA_GAMERULES_STATE_CUSTOM_GAME_SETUP = 2
local function match_state() return require("systems/match_setup_service") end
local function fixture(count, settings)
    time, humans, disconnected, profiles, pending, requests, listeners = 0, {}, {}, {}, {}, {}, {}
    authenticated, profile_pending, profile_requests, responses, history = {}, {}, {}, {}, {}
    engine_state = 2
    asset, mode, asset_retry_calls = { total = 10, ready = 0, failed = 0, progress = 0, complete = false }, "async", 0
    asset_retry_result = { ok = true }
    for id = 0, count - 1 do
        local player = { id = id }
        function player:GetPlayerID() return self.id end
        function player:IsNull() return false end
        humans[id] = { valid = true, fake = false, account = 1000 + id, player = player, state = 2 }
    end
    PlayerResource = {
        IsValidPlayerID = function(_, id) return humans[id] and humans[id].valid end,
        IsFakeClient = function(_, id) return humans[id] and humans[id].fake end,
        GetSteamAccountID = function(_, id) return humans[id] and humans[id].account end,
        GetPlayerName = function(_, id) return "Player\n" .. id end,
        GetPlayer = function(_, id) return humans[id] and humans[id].player end,
        GetConnectionState = function(_, id) return humans[id] and humans[id].state end,
        GetTeam = function(_, id) return humans[id] and humans[id].team or 2 end,
    }
    EntIndexToHScript = function(index) return humans[index - 200] and humans[index - 200].player end
    GameRules = {
        PlayerHasCustomGameHostPrivileges = function(_, player) return player.id == 0 end,
        GetGameTime = function() error("startup must never depend on frozen GameTime") end,
        State_Get = function() return engine_state end,
        GetGameModeEntity = function() return { SetContextThink = function(_, name, callback, delay)
            assert(name == "SurvivalStartupLoadingThink" and delay > 0)
            thinker = callback
        end } end,
    }
    CustomNetTables = { SetTableValue = function(_, name, key, value)
        assert(name == "survival_loading" and key == "state")
        published = value
        for _, player in ipairs(value.players or {}) do
            assert(player.player_name == "Player " .. player.player_id, "every loading phase publishes a safe display name")
            assert(player.account == nil and player.account_id == nil, "public roster must not expose private authentication records")
        end
        history[#history + 1] = value
    end }
    CustomGameEventManager = {
        RegisterListener = function(_, name, callback) listeners[name] = callback return name end,
        UnregisterListener = function(_, name) listeners[name] = nil end,
        Send_ServerToPlayer = function(_, player, name, payload)
            responses[#responses + 1] = { id = player.id, name = name, payload = payload }
        end,
    }
    modules.profiles = {
        get_profile = function(id) return profiles[id] end,
        get_progression = function(id, selected_mode)
            local record = authenticated[id]
            if record and modules.profiles.is_authenticated_for_account(id, tostring(humans[id].account)) then
                return record.progression
            end
        end,
        is_authenticated_for_account = function(id, account)
            local record = authenticated[id]
            return record ~= nil and record.account_id == account
                and record.match_session_id == match_state().get_session_id()
        end,
        is_authenticating = function(id) return pending[id] == true end,
        authenticate_player = function(id, reason, callback)
            assert(reason == "startup_admission", "admission must not fetch a mode profile")
            local request = { id = id, callback = callback, account = tostring(humans[id].account),
                session = match_state().get_session_id() }
            requests[#requests + 1] = request
            if mode == "auth_fail" then
                callback({ ok = false, error = "unauthorized: private-token-and-account-detail" })
                return { ok = false, error = "unauthorized" }
            end
            pending[id] = true
            return { ok = true, pending = true }
        end,
        is_loading = function(id) return profile_pending[id] == true end,
        is_loaded_for_account = function(id, account)
            local profile = profiles[id]
            return profile ~= nil and profile.account_id == account
                and profile.match_session_id == match_state().get_session_id()
                and profile.mode == match_state().get_mode()
        end,
        load_player = function(id, reason, success, failure)
            assert(match_state().is_mode_selected(), "mode profile cannot load before selection")
            assert(not modules.profiles.is_loaded_for_account(id, tostring(humans[id].account)),
                "startup cannot reset an already loaded mode profile")
            assert(reason == "match_mode_selected")
            local request = { id = id, success = success, failure = failure,
                account = tostring(humans[id].account), session = match_state().get_session_id(),
                mode = match_state().get_mode() }
            profile_requests[#profile_requests + 1] = request
            profile_pending[id] = true
            return { ok = true, pending = true }
        end,
    }
    modules.multiplayer = {
        participating_player_ids = function()
            local result = {}
            for id in pairs(humans) do result[#result + 1] = id end
            return result
        end,
        is_disconnected = function(id) return disconnected[id] == true end,
    }
    package.loaded["systems/player_profile_service"] = modules.profiles
    package.loaded["systems/multiplayer_player_service"] = modules.multiplayer
    package.loaded["systems/startup_asset_preload_service"] = {
        snapshot = function() return asset end,
        retry = function() asset_retry_calls = asset_retry_calls + 1 return asset_retry_result end,
    }
    package.loaded["systems/startup_loading_service"] = nil
    local service = require("systems/startup_loading_service")
    if settings ~= false then service.init(settings or {}) end
    return service
end
local function success(request, counts, rich_counts)
    -- This fixture independently authenticates equal standard/pure counters;
    -- returning the complete receipt preserves the real provenance contract.
    local standard, pure = {}, {}
    for key,value in pairs(counts or {}) do standard[key],pure[key]=value,value end
    local response = { ok = true, authenticated = true, account_id = request.account,
        match_session_id = request.session,
        progression = { loaded = true, clear_counts = counts or {},
            standard_clear_counts = standard, mode_clear_counts = {pure=pure},
            rich_clear_counts = rich_counts or {}, highest_difficulty = 0 } }
    authenticated[request.id] = response
    pending[request.id] = false
    request.callback(response)
end
local function profile_success(request)
    profiles[request.id] = { account_id = request.account, match_session_id = request.session,
        mode = request.mode, revision = 1, save = { private_permanent_item = 1 } }
    profile_pending[request.id] = false
    request.success({ ok = true })
end
local function ui(service, id, payload)
    payload = payload or { session_id = service.snapshot().session_id }
    listeners.survival_loading_client_ready(200 + id, payload)
end
local function assets_done()
    asset = { total = 10, ready = 10, failed = 0, progress = 100, complete = true }
end
local function select_mode(service, mode_id, id, session)
    listeners.survival_loading_mode_select(200 + (id or 0), {
        session_id = session or service.snapshot().session_id, mode_id = mode_id, PlayerID = 0 })
end
local function assert_admitted(service)
    local state = service.snapshot()
    assert(service.is_ready() and state.admission_complete and state.all_ready and state.phase == "ready")
    assert(state.error == nil, "mode/profile errors must not reopen the loading page")
end

-- Browser approval remains a normal wait and uses the existing retry clock;
-- neither a pending receipt nor UI readiness can count as authentication.
do
    local waiting = fixture(1)
    pending[0] = false
    requests[1].callback({ ok = false, error = "player_web_auth_pending" })
    assets_done() ui(waiting, 0) waiting.tick()
    assert(not waiting.is_ready() and waiting.snapshot().error == nil)
    assert(not waiting.snapshot().players[1].authenticated and #requests == 1)
    time = 4; waiting.tick()
    assert(#requests == 1, "pending browser approval must not create per-tick HTTP requests")
    time = 5; waiting.tick()
    assert(#requests == 2, "existing admission retry owns browser polling")
end

do
    local web_config = require("config/player_web_auth")
    local previous_server, previous_convars = IsServer, Convars
    IsServer = function() return true end
    Convars = { GetStr = function() return "" end }
    web_config.enabled = true
    local personal = fixture(1, { tools_backend_wait = true })
    assert(#requests == 1 and personal.snapshot().phase ~= "connecting_backend" and not personal.is_ready(),
        "player web authentication must begin without an author server token, while admission stays closed")
    web_config.enabled = false
    local original = fixture(1, { tools_backend_wait = true })
    assert(#requests == 0 and original.snapshot().phase == "connecting_backend",
        "disabling web authentication preserves the existing Tools credential wait")
    IsServer, Convars = previous_server, previous_convars
end

-- A rejected server-owned mode choice carries its precise unlock condition
-- through the real listener, rather than dropping it before Panorama sees it.
do
    local hinted = fixture(1)
    success(requests[1], {n10=99}, {})
    authenticated[0].progression.cold_clear_counts = {}
    modules.profiles.get_authenticated_progression = function(id) return authenticated[id].progression end
    assets_done() ui(hinted, 0) hinted.tick()
    assert_admitted(hinted)
    select_mode(hinted, "cold")
    local response = responses[#responses].payload
    assert(response.success == 0 and response.error == "mode_not_unlocked")
    assert(response.unlock_hint == require("config/mode_progression").entry_hint("cold"),
        "mode-specific server hint survives the network response envelope")
    assert(#profile_requests == 0, "a locked mode never starts gameplay profile loading")
end

-- Admission authenticates independently of mode. Mode profiles release a
-- separate gameplay gate after the engine has already entered the game.
local admitted, playable = 0, 0
local choosing = fixture(2, { on_ready = function() admitted = admitted + 1 end })
choosing.gameplay_gate(function() playable = playable + 1 end)
assert(#requests == 2 and #profile_requests == 0 and not choosing.snapshot().setup.mode_selected)
assert(not choosing.snapshot().setup.difficulty_data_ready)
select_mode(choosing, "pure")
assert(not choosing.snapshot().setup.mode_selected and #profile_requests == 0,
    "even the host cannot choose a mode before admission")
assert(responses[#responses].payload.error == "admission_not_complete")
assets_done() ui(choosing, 0) ui(choosing, 1)
assert(not choosing.is_ready(), "UI flags never replace backend authentication")
success(requests[1], { n5 = 1, n6 = 1 }) choosing.tick()
assert(not choosing.snapshot().setup.difficulty_data_ready,
    "the host's loaded progression never substitutes for an unknown teammate")
success(requests[2], { n5 = 1 }) choosing.tick()
assert_admitted(choosing)
assert(admitted == 1 and playable == 0 and not choosing.is_gameplay_ready())
assert(not choosing.snapshot().profiles_ready and not choosing.is_player_ready(0) and #profile_requests == 0)
local options = choosing.snapshot().setup.difficulty_options
assert(options[6].unlocked == 1 and options[7].unlocked == 0,
    "difficulty choices use the lowest teammate before mode-profile loading")
local preloaded = choosing.snapshot().setup
assert(preloaded.difficulty_data_ready and preloaded.max_difficulty_id == "N6")
assert(not preloaded.can_confirm_difficulty, "mode is still required before difficulty confirmation")
assert(preloaded.difficulty_limit_player_ids[1] == 1)
assert(preloaded.difficulty_options_by_mode.standard[6].unlocked == 1
    and preloaded.difficulty_options_by_mode.pure[6].unlocked == 1
    and preloaded.difficulty_options_by_mode.rich[6].unlocked == 0,
    "all mode previews are loaded before the first mode click, including independent rich progress")
assert(#profile_requests == 0 and #requests == 2 and profiles[0] == nil and profiles[1] == nil,
    "difficulty preload neither repeats HTTP nor applies a gameplay profile")
release.all_difficulties_unlocked = true
choosing.tick()
local acceptance = choosing.snapshot().setup
assert(acceptance.difficulty_access_policy == "all_configured" and acceptance.max_difficulty_id == "N10")
assert(acceptance.difficulty_options_by_mode.standard[10].unlocked == 1
    and acceptance.difficulty_options_by_mode.pure[10].unlocked == 1,
    "authenticated admission immediately previews all released-mode tiers")
assert(acceptance.difficulty_options_by_mode.rich[30].unlocked == 0,
    "the mode-entry prerequisite remains independent of open difficulty tiers")
assert(#profile_requests == 0 and #requests == 2, "tier preview adds no mode-profile HTTP request")
release.all_difficulties_unlocked = false
choosing.tick()
assert(choosing.snapshot().setup.difficulty_access_policy == "progression"
    and choosing.snapshot().setup.max_difficulty_id == "N6")
local selection_session = choosing.snapshot().session_id
select_mode(choosing, "pure", 1)
assert(not choosing.snapshot().setup.mode_selected and responses[#responses].payload.error == "selection_not_host")
select_mode(choosing, "pure", 0, "old-session")
assert(not choosing.snapshot().setup.mode_selected and #profile_requests == 0)
select_mode(choosing, "pure")
assert(choosing.snapshot().setup.mode_id == "pure" and #profile_requests == 2)
assert(choosing.snapshot().setup.can_confirm_difficulty and choosing.is_difficulty_selection_ready(0))
assert(not choosing.is_player_ready(0) and not choosing.is_gameplay_ready(),
    "difficulty is immediately confirmable while login still gates every gameplay action")
assert(choosing.snapshot().session_id == selection_session and admitted == 1 and #requests == 2)
select_mode(choosing, "standard")
assert(choosing.snapshot().setup.mode_id == "pure" and responses[#responses].payload.error == "mode_locked")
assert(#profile_requests == 2, "repeated mode events cannot reset pending profiles")
profile_success(profile_requests[1]) choosing.tick()
assert(not choosing.is_gameplay_ready() and not choosing.snapshot().profiles_ready and playable == 0)
assert_admitted(choosing)
profile_success(profile_requests[2])
assert(thinker() == nil and choosing.is_gameplay_ready() and choosing.snapshot().profiles_ready)
assert(playable == 1 and choosing.is_player_ready(0) and choosing.is_player_ready(1))
choosing.tick()
assert(admitted == 1 and playable == 1 and #profile_requests == 2)
assert(choosing.gameplay_gate(function() playable = playable + 1 end) and playable == 2)
local saved_profile = profiles[0]
choosing.init({})
assert(not choosing.snapshot().setup.mode_selected and not choosing.is_ready() and not choosing.is_gameplay_ready())
assert(profiles[0] == saved_profile, "new session does not reset the profile service")
assert(not choosing.is_player_ready(0), "old match profiles cannot satisfy a new session")

-- The lowest non-host teammate stays in the permission roster after admission.
-- Neither disconnect/invalid engine slot nor missing trusted authentication can
-- turn that player into a higher unlocked cap for the remaining host.
local frozen = fixture(2)
success(requests[1], { n5 = 1, n9 = 1 }) success(requests[2], { n5 = 1 })
assets_done() ui(frozen, 0) ui(frozen, 1)
assert_admitted(frozen)
assert(frozen.snapshot().setup.max_difficulty_id == "N6"
    and frozen.snapshot().setup.difficulty_limit_player_ids[1] == 1)
local roster = frozen.selection_player_ids()
roster[2] = nil
assert(#frozen.selection_player_ids() == 2, "callers cannot mutate the frozen roster")
disconnected[1], humans[1].valid = true, false
frozen.tick()
assert(#frozen.selection_player_ids() == 2 and frozen.snapshot().setup.difficulty_data_ready)
assert(frozen.snapshot().setup.max_difficulty_id == "N6"
    and frozen.snapshot().setup.difficulty_options[10].unlocked == 0)
authenticated[1] = nil
frozen.tick()
assert(not frozen.snapshot().setup.difficulty_data_ready
    and frozen.snapshot().setup.max_difficulty_id == ""
    and frozen.snapshot().setup.difficulty_options[10].unlocked == 0,
    "unknown teammate progression fails closed instead of falling back to the host")
assert(#requests == 2 and #profile_requests == 0)

-- A loading-screen handshake can arrive before the engine has assigned every
-- lobby human a PlayerResource slot. Do not latch the first client's roster.
local early_service = fixture(1, false)
engine_state = 1
early_service.init({ minimum_wait_seconds = 0 })
success(requests[1]) assets_done() ui(early_service, 0)
assert(not early_service.is_ready() and early_service.snapshot().players[1].ready)
local second_player = { id = 1, GetPlayerID = function(self) return self.id end, IsNull = function() return false end }
humans[1] = { valid = true, fake = false, account = 1001, player = second_player, state = 2 }
engine_state = 2
early_service.tick()
assert(#requests == 2 and #early_service.snapshot().players == 2 and not early_service.is_ready(),
    "engine setup must collect the second lobby human before roster release")
engine_state = 6 -- A native state jump cannot bypass the other barriers.
early_service.tick()
assert(not early_service.is_ready())
success(requests[2]) ui(early_service, 1)
assert(early_service.is_ready())
early_service = fixture(1)
GameRules.State_Get = nil
success(requests[1]) assets_done() ui(early_service, 0)
assert(not early_service.is_ready(), "missing engine state API fails closed")
GameRules.State_Get = function() return 2 end
early_service.tick()
assert(early_service.is_ready())

-- All three barriers are independent; identity always comes from the engine.
local fired = 0
local service = fixture(2, { minimum_wait_seconds = 10, on_ready = function() fired = fired + 1 end })
assert(#requests == 2 and not service.is_ready())
local session = service.snapshot().session_id
listeners.survival_loading_client_ready(0, { session_id = session, PlayerID = 0 })
assert(not service.snapshot().players[1].client_ready, "player IDs are not entity indices")
ui(service, 0, { session_id = "old-session", PlayerID = 0, authenticated = true })
assert(not service.snapshot().players[1].client_ready)
ui(service, 0, { session_id = session, PlayerID = 1, player_id = 1, authenticated = true })
assert(service.snapshot().players[1].client_ready and not service.snapshot().players[2].client_ready)
assert(not service.snapshot().players[1].authenticated, "UI cannot authenticate an account")
success(requests[1])
assets_done()
service.tick()
assert(service.snapshot().players[1].ready and service.snapshot().phase == "waiting")
assert(not service.is_ready() and not service.snapshot().players[2].authenticated)
success(requests[2])
ui(service, 1)
assert(not service.is_ready(), "joining window is preserved even if both players finish early")
time = 10
assert(thinker() > 0 and service.is_ready() and fired == 1,
    "real-time polling continues after admission until mode profiles are ready")
service.tick()
assert(fired == 1)
service.gate(function() fired = fired + 1 end)
assert(fired == 2, "callbacks registered after readiness run once immediately")
assert(published.session_id == session and published.all_ready and published.progress == 100)
for _, row in ipairs(published.players) do
    assert(row.account_id == nil and row.account == nil and row.save == nil and row.token == nil)
end
local mutated = service.snapshot()
mutated.players[1].authenticated = false
assert(service.snapshot().players[1].authenticated)
assert(not service.is_player_ready(0) and not service.is_player_ready(1))
select_mode(service, "standard")
profile_success(profile_requests[1]) profile_success(profile_requests[2]) service.tick()
assert(service.is_gameplay_ready() and service.snapshot().profiles_ready)
assert(service.is_player_ready(0) and service.is_player_ready(1))
assert(not service.is_player_ready(2) and not service.is_player_ready(0.5))
local reconnect_profile = profiles[1]
disconnected[1] = true
assert(not service.is_player_ready(1) and service.is_ready(), "a disconnected actor cannot use the released global gate")
assert(not service.is_difficulty_selection_ready(1), "disconnect also revokes the setup-only gate")
disconnected[1] = false
assert(service.is_player_ready(1), "same-account reconnect keeps its authenticated save")
humans[1].account, profiles[1] = 9000, { account_id = "9000", revision = 1 }
assert(not service.is_player_ready(1), "a new account cannot inherit an admitted player slot")
assert(not service.is_difficulty_selection_ready(1), "setup permissions are still bound to the authenticated account")
humans[1].account = 1001
assert(not service.is_player_ready(1), "the live profile must still match the locked account")
profiles[1] = nil
assert(not service.is_player_ready(1), "missing current profile is never authenticated by old readiness")
profiles[1] = reconnect_profile
humans[1].fake = true
assert(not service.is_player_ready(1), "a bot cannot inherit the admitted slot")
humans[1].fake = false
assert(service.is_player_ready(1) and profiles[1] == reconnect_profile and #requests == 2 and #profile_requests == 2)
local outsider = { id = 2, GetPlayerID = function(self) return self.id end }
humans[2] = { valid = true, fake = false, account = 1002, player = outsider, state = 2 }
profiles[2] = { account_id = "1002", revision = 1, mode = "standard", match_session_id = session }
assert(not service.is_player_ready(2), "a fully loaded late entrant still was not admitted to this match")

-- Safe Workshop diagnostics reach Panorama without opening admission or
-- exposing arbitrary provider errors, keys, or malformed status strings.
for _, code in ipairs({"workshop_dedicated_server_required", "workshop_key_api_unavailable",
    "workshop_key_call_failed", "workshop_key_empty", "workshop_server_key_unavailable",
    "workshop_key_state_Invalid_NotOnDedicatedServer", "workshop_connection_invalid",
    "workshop_server_not_authorized", "workshop_backend_unreachable", "workshop_backend_rejected",
    "workshop_pairing_0123456789abcdef", "backend_token_missing"}) do
    local checked=fixture(1)
    pending[0]=false
    requests[1].callback({ok=false,error=code})
    ui(checked,0); assets_done(); checked.tick()
    assert(checked.snapshot().error==code, "diagnostic must not be collapsed: "..code)
    assert(not checked.is_ready() and not checked.snapshot().admission_complete)
end
for _, code in ipairs({"workshop_key_state_Invalid_<script>", "workshop_key_state_"..string.rep("a",64),
    "workshop_key_state_Invalid_"..string.rep("x",80), "private-runtime-error"}) do
    local checked=fixture(1)
    pending[0]=false
    requests[1].callback({ok=false,error=code})
    ui(checked,0); assets_done(); checked.tick()
    assert(checked.snapshot().error=="profile_load_failed")
    assert(not checked.is_ready())
end

-- Authentication errors remain closed and recover on real time while GameTime
-- throws. Client retry is rate-limited and never impersonates another player.
service = fixture(1, false)
mode = "auth_fail"
service.init()
ui(service, 0)
assets_done()
service.tick()
assert(service.snapshot().phase == "error" and service.snapshot().error == "backend_authentication_failed")
assert(#requests == 1 and not service.is_ready())
mode, time = "async", 1
listeners.survival_loading_retry(200, { session_id = service.snapshot().session_id })
assert(#requests == 1, "manual retry cannot hammer the backend faster than five seconds")
time = 5
thinker()
assert(#requests == 2)
success(requests[2])
thinker()
assert(service.is_ready() and service.snapshot().error == nil)

-- Existing authentication owns its pending request; wait for it, then retry
-- on real time if it fails, without reinitializing the profile subsystem.
service = fixture(1, false)
pending[0] = true
service.init()
assert(#requests == 0)
time, pending[0] = 2, false
service.tick()
assert(#requests == 0)
time = 7
service.tick()
assert(#requests == 1)

-- Lost HTTP callbacks time out; a retry may replace the stale generation.
service = fixture(1)
requests[1].callback({ ok = true, authenticated = true, account_id = "forged", match_session_id = "old" })
assets_done() ui(service, 0)
assert(not service.is_ready() and not service.snapshot().players[1].authenticated,
    "only the profile service's trusted auth state can satisfy admission")
service = fixture(1)
time = 45
service.tick()
assert(service.snapshot().error == "profile_load_timeout" and #requests == 1)
time = 49
service.tick()
assert(#requests == 1)
time = 50
service.tick()
assert(#requests == 2 and not service.is_ready())

-- Bots/spectators are excluded, but a known human cannot disappear from the
-- barrier by disconnecting or becoming invalid. Reconnect requires a new UI ack.
service = fixture(4, false)
humans[2].fake, humans[3].team = true, DOTA_TEAM_SPECTATOR
service.init()
assert(#requests == 2 and #service.snapshot().players == 2)
success(requests[1]) success(requests[2])
ui(service, 0) ui(service, 1)
disconnected[1], humans[1].valid = true, false
assets_done()
service.tick()
assert(not service.is_ready() and #service.snapshot().players == 2)
assert(service.snapshot().players[2].status == "disconnected" and not service.snapshot().players[2].client_ready)
disconnected[1], humans[1].valid = false, true
service.tick()
assert(not service.is_ready(), "cached authentication does not replace the reconnect handshake")
ui(service, 1)
assert(service.is_ready() and #requests == 2 and #profile_requests == 0,
    "same account reconnect reuses authentication without loading mode profiles")

-- Cached authentication never reloads. A different account taking a waiting slot
-- cannot satisfy the original account requirement, even with an old UI ack.
service = fixture(1)
success(requests[1])
ui(service, 0)
service.tick()
assert(#requests == 1)
humans[0].account = 9000
authenticated[0] = { account_id = "9000", match_session_id = service.snapshot().session_id }
assets_done()
service.tick()
assert(not service.is_ready() and service.snapshot().error == "player_identity_changed")
service = fixture(1)
authenticated[0] = { account_id = "wrong-cached-account", match_session_id = service.snapshot().session_id }
assets_done() ui(service, 0)
assert(not service.is_ready() and not service.snapshot().players[1].authenticated,
    "a cached different account cannot prove authentication")

-- A human joining during the setup window joins the frozen-until-ready roster.
service = fixture(1, { minimum_wait_seconds = 10 })
success(requests[1]) ui(service, 0) assets_done()
local late = { id = 1, GetPlayerID = function(self) return self.id end, IsNull = function() return false end }
humans[1] = { valid = true, fake = false, account = 1001, player = late, state = 2 }
time = 9
service.tick()
assert(#requests == 2 and #service.snapshot().players == 2)
time = 10
service.tick()
assert(not service.is_ready(), "the setup deadline cannot bypass a newly arrived human")
success(requests[2]) ui(service, 1)
assert(service.is_ready())

-- Asset failure, no human roster, or an unresolved account keeps the gate shut.
service = fixture(1)
success(requests[1]) ui(service, 0)
asset = { total = 10, ready = 9, failed = 1, progress = 100, complete = true }
service.tick()
assert(not service.is_ready() and service.snapshot().error == "asset_preload_failed")
local authenticated_profile = authenticated[0]
local retry_event = listeners.survival_loading_retry
retry_event(200, { session_id = service.snapshot().session_id })
assert(asset_retry_calls == 1 and #requests == 1 and #profile_requests == 0 and authenticated[0] == authenticated_profile,
    "authenticated players can retry failed assets without reloading their profile")
assert(service.snapshot().players[1].authenticated and not service.is_ready(),
    "accepting an asset retry is not proof of resource readiness")
time = 4
retry_event(200, { session_id = service.snapshot().session_id })
assert(asset_retry_calls == 1, "asset retry clicks obey the real-time cooldown")
time = 5
retry_event(0, { session_id = service.snapshot().session_id, PlayerID = 0 })
assert(asset_retry_calls == 1, "payload identity cannot authorize a global resource retry")
retry_event(200, { session_id = service.snapshot().session_id })
assert(asset_retry_calls == 2 and #requests == 1)
assets_done() service.tick()
assert(service.is_ready() and authenticated[0] == authenticated_profile)
service = fixture(1)
success(requests[1]) ui(service, 0)
asset = { total = 10, ready = 9, failed = 1, progress = 100, complete = false }
asset_retry_result = { ok = false, error = "startup_assets_require_map_reload" }
listeners.survival_loading_retry(200, { session_id = service.snapshot().session_id })
assert(service.snapshot().error == "asset_reload_required" and not service.is_ready())
time = 5
listeners.survival_loading_retry(200, { session_id = service.snapshot().session_id })
assert(asset_retry_calls == 1 and #requests == 1,
    "resources that require map reload must not invite endless ineffective retries")
service = fixture(0)
assets_done() service.tick()
assert(not service.is_ready())
service = fixture(1, false)
humans[0].account = 0
service.init() assets_done() ui(service, 0)
assert(not service.is_ready() and #requests == 0 and #service.snapshot().players == 1)

-- Profile preparation errors belong to the HUD setup, never the completed
-- loading screen. Retry only the failed player, retaining all loaded profiles.
service = fixture(2)
success(requests[1]) success(requests[2]) assets_done() ui(service, 0) ui(service, 1)
local admitted_index, gameplay_count = #history, 0
service.gameplay_gate(function() gameplay_count = gameplay_count + 1 end)
select_mode(service, "standard")
local first, second = profile_requests[1], profile_requests[2]
profile_success(first)
profile_pending[second.id] = false
second.failure("http_status_503: private-token-and-account-detail")
service.tick()
assert_admitted(service)
assert(service.snapshot().setup.error == "profile_load_failed" and not service.snapshot().profiles_ready)
assert(not service.is_gameplay_ready() and gameplay_count == 0)
assert(not service.is_player_ready(first.id) and not service.is_player_ready(second.id),
    "no player may start gameplay while another admitted mode profile is missing")
engine_state, time = 6, 4
thinker()
assert(#profile_requests == 2 and #requests == 2)
time = 5 thinker()
assert(#profile_requests == 3 and profile_requests[3].id == second.id,
    "automatic retry reloads only the failed mode profile")
profile_success(profile_requests[3]) thinker()
assert(service.is_gameplay_ready() and service.snapshot().profiles_ready and gameplay_count == 1)
assert(service.snapshot().setup.error == nil and #requests == 2)
for index = admitted_index, #history do
    local state = history[index]
    assert(state.admission_complete and state.all_ready and state.phase == "ready" and state.error == nil,
        "profile preparation must never flash the loading background again")
end

-- HUD retry accepts only the engine actor/session and does not repeat the
-- successful player's profile or the initial account authentication.
service = fixture(2)
success(requests[1]) success(requests[2]) assets_done() ui(service, 0) ui(service, 1)
select_mode(service, "standard")
profile_success(profile_requests[1])
local failed_profile_request = profile_requests[2]
profile_pending[failed_profile_request.id] = false
failed_profile_request.failure("http_status_503")
service.tick()
local hud_retry = listeners.survival_loading_retry
hud_retry(0, { session_id = service.snapshot().session_id, PlayerID = failed_profile_request.id })
hud_retry(200 + failed_profile_request.id, { session_id = "old-session" })
assert(#profile_requests == 2)
hud_retry(200 + failed_profile_request.id, { session_id = service.snapshot().session_id })
assert(#profile_requests == 3 and profile_requests[3].id == failed_profile_request.id and #requests == 2)
profile_pending[failed_profile_request.id] = false
profile_requests[3].failure("http_status_503")
time = 1
hud_retry(200 + failed_profile_request.id, { session_id = service.snapshot().session_id })
assert(#profile_requests == 3, "repeated HUD retry clicks must be rate-limited")
assert_admitted(service)

-- Mode-profile requests also have a real-time timeout: a lost callback may
-- not leave admitted clients waiting forever behind the HUD setup panel.
service = fixture(1)
success(requests[1]) assets_done() ui(service, 0)
select_mode(service, "pure")
time = 45 service.tick()
assert_admitted(service)
assert(service.snapshot().setup.error == "profile_load_timeout" and #profile_requests == 1)
time = 49 service.tick()
assert(#profile_requests == 1)
time = 50 service.tick()
assert(#profile_requests == 2 and not service.is_gameplay_ready())
profile_success(profile_requests[2]) service.tick()
assert(service.is_gameplay_ready() and #requests == 1)

-- A disconnect after admission only blocks gameplay. Original-account
-- reconnect may complete the mode profile without repeating admission.
service = fixture(1)
success(requests[1]) assets_done() ui(service, 0)
disconnected[0] = true
service.tick()
assert_admitted(service)
assert(not service.is_gameplay_ready() and service.snapshot().setup.error == "player_disconnected")
disconnected[0] = false
select_mode(service, "pure")
profile_success(profile_requests[1]) service.tick()
assert(service.is_gameplay_ready() and #requests == 1)

-- Account replacement after admission stays rejected in the setup phase;
-- the global admission latch is never reused as gameplay authorization.
service = fixture(1)
success(requests[1]) assets_done() ui(service, 0)
select_mode(service, "standard")
humans[0].account = 9000
profile_success(profile_requests[1]) service.tick()
assert_admitted(service)
assert(service.snapshot().setup.error == "player_identity_changed")
assert(not service.is_gameplay_ready() and not service.is_player_ready(0))

-- A new loading session rejects old UI/auth/think callbacks without resetting any
-- loaded profile state. The published session survives late UI subscriptions.
service = fixture(1)
local old_session, old_listener, old_think, old_request = service.snapshot().session_id,
    listeners.survival_loading_client_ready, thinker, requests[1]
pending[0] = false
service.init()
assert(service.snapshot().session_id ~= old_session and old_think() == nil)
old_listener(200, { session_id = old_session, authenticated = true })
assert(not service.snapshot().players[1].client_ready)
success(old_request)
assets_done() ui(service, 0)
assert(not service.is_ready() and not service.snapshot().players[1].authenticated)
success(requests[2]) service.tick()
assert_admitted(service)

print("STARTUP_LOADING_SERVICE_PASS: independent admission, all-player auth, mode-profile gameplay gate, monotonic completion, identity, retries, reconnect, session isolation")

-- Native team selection owns its host start/countdown. Neither a loading
-- handshake, spoofed custom start event nor elapsed time may begin admission.
local dispatched, native_admitted, native_playable = 0, 0, 0
local native = fixture(3, { native_team_setup = true, tools_backend_wait = true,
    on_load_start = function() dispatched = dispatched + 1 end,
    on_ready = function() native_admitted = native_admitted + 1 end })
native.gameplay_gate(function() native_playable = native_playable + 1 end)
assert(native.is_native_team_setup() and native.is_party_waiting(),
    'Tools authentication bridges must still wait for the native host start')
assert(native.snapshot().phase == 'team_setup' and native.snapshot().native_team_setup == true)
assert(listeners.survival_party_start == nil, 'the removed custom party event cannot launch the match')
local sid = native.snapshot().session_id
ui(native, 0) ui(native, 1) ui(native, 2)
time = 1000
native.tick()
assert(#requests == 0 and dispatched == 0 and not native.is_ready())
listeners.survival_loading_retry(200, {session_id=sid})
select_mode(native, 'standard')
assert(#requests == 0 and asset_retry_calls == 0 and not native.snapshot().setup,
    'native team setup cannot start assets/authentication or select a mode')
GameRules.State_Get = nil
native.tick()
assert(native.is_native_team_setup() and dispatched == 0, 'missing native state fails closed')
GameRules.State_Get = function() return engine_state end
humans[2].state, disconnected[2] = 3, true
native.tick()
assert(not native.snapshot().players[3].client_ready, 'disconnect invalidates the earlier loading handshake')
-- Valve SetRemainingSetupTime's countdown remains in state 2 until complete.
engine_state = 2
native.tick()
assert(dispatched == 0 and #requests == 0)
Convars = { GetStr = function() return '' end }
engine_state = 3
native.tick()
assert(not native.is_native_team_setup() and not native.is_party_waiting() and dispatched == 1 and #requests == 0)
assert(native.snapshot().phase == 'connecting_backend' and not native.snapshot().native_team_setup)
assert(#native.snapshot().players == 3, 'native start never drops an unready participant')
time = time + 60
native.tick()
assert(native.snapshot().error == 'backend_connection_pending' and #requests == 0)
Convars = { GetStr = function() return 'test-credential-present' end }
native.tick()
assert(#requests == 2 and dispatched == 1)
for _, request in ipairs(requests) do success(request) end
assets_done()
native.tick()
assert(not native.is_ready() and native_admitted == 0 and native_playable == 0,
    'entering the native game cannot bypass a disconnected participant')
humans[2].state, disconnected[2] = 2, nil
native.tick()
assert(#requests == 3 and #profile_requests == 0)
success(requests[3]) native.tick()
assert(not native.is_ready(), 'reconnected player must acknowledge the loading UI again')
ui(native, 2)
assert_admitted(native)
assert(native_admitted == 1 and not native.is_gameplay_ready() and native_playable == 0)
select_mode(native, 'pure', 1)
assert(not native.snapshot().setup.mode_selected)
select_mode(native, 'pure')
assert(#profile_requests == 3 and #requests == 3 and dispatched == 1)
profile_success(profile_requests[1]) profile_success(profile_requests[2]) native.tick()
assert(not native.is_gameplay_ready() and native_playable == 0,
    'all mode profiles remain mandatory after official start')
profile_success(profile_requests[3]) native.tick()
assert(native.is_gameplay_ready() and native_playable == 1)
native.tick()
assert(native_admitted == 1 and native_playable == 1 and dispatched == 1)
for id = 0, 2 do assert(native.is_player_ready(id)) end
Convars = nil

-- A late service initialization after native setup still starts its loading
-- callback exactly once and keeps both admission and gameplay checks closed.
local late = fixture(1, false)
engine_state = 6
local late_dispatch = 0
late.init({ native_team_setup = true, on_load_start = function() late_dispatch = late_dispatch + 1 end })
assert(late_dispatch == 1 and #requests == 1 and not late.is_native_team_setup())
assert(not late.is_ready() and not late.is_gameplay_ready() and not late.is_player_ready(0))
late.tick()
assert(late_dispatch == 1 and #requests == 1)
print('STARTUP_NATIVE_TEAM_SETUP_PASS: Valve lifecycle, no custom party event, all-player auth/assets/UI/profile gates, disconnect/reconnect, host mode, once-only startup')

-- Exercise the actual addon lifecycle callback against the real loading
-- service. Native GAME_IN_PROGRESS must not emit gameplay start early.
local addon_file = assert(io.open('scripts/vscripts/addon_game_mode.lua', 'rb'))
local addon_source = addon_file:read('*a')
addon_file:close()
local lifecycle_body = assert(addon_source:match('local function on_game_state_changed%(%)\r?\n(.-)\r?\nend'))
assert(not lifecycle_body:find('FinishCustomGameSetup', 1, true),
    'the addon must not override Valve host start/countdown')
local emitted, event_native = 0, fixture(2, {native_team_setup=true})
local lifecycle_env = setmetatable({
    GameRules = GameRules,
    DOTA_GAMERULES_STATE_GAME_IN_PROGRESS = 7,
    DOTA_GAMERULES_STATE_POST_GAME = 8,
    game_started_emitted = false,
    events = { GAME_STARTED = 'fixture_game_started' },
    event_bus = { emit = function(name)
        assert(name == 'fixture_game_started')
        emitted = emitted + 1
    end },
}, {__index=_G})
local lifecycle_chunk = assert(loadstring('return function()\n' .. lifecycle_body .. '\nend'))
setfenv(lifecycle_chunk, lifecycle_env)
local lifecycle = lifecycle_chunk()
engine_state = 7
lifecycle() lifecycle()
assert(emitted == 0 and not event_native.is_gameplay_ready())
event_native.tick()
for _, request in ipairs(requests) do success(request) end
assets_done() ui(event_native, 0) ui(event_native, 1)
assert_admitted(event_native)
lifecycle()
assert(emitted == 0, 'admission alone must not start waves or builder/game timers')
select_mode(event_native, 'standard')
assert(event_native.is_difficulty_selection_ready(0) and not event_native.is_gameplay_ready())
lifecycle()
assert(emitted == 0, 'opening the setup-only difficulty gate never releases GAME_STARTED')
profile_success(profile_requests[1]) event_native.tick()
assert(emitted == 0, 'a single mode profile cannot release GAME_STARTED')
profile_success(profile_requests[2]) event_native.tick()
assert(emitted == 1 and event_native.is_gameplay_ready())
lifecycle()
assert(emitted == 1, 'repeated native state/admission callbacks start gameplay once')
print('STARTUP_NATIVE_GAMEPLAY_LIFECYCLE_PASS: actual addon callback, native phase cannot bypass profiles, once-only GAME_STARTED')

-- Native setup deliberately has no timeout/auto-start. Its real Valve panel
-- must be mounted, otherwise a correctly closed server gate deadlocks on a
-- start button that does not exist (blank logo/chat-only setup screen).
local manifest_file = assert(io.open('panorama/src/layout/custom_game/custom_ui_manifest.xml', 'rb'))
local manifest = manifest_file:read('*a')
manifest_file:close()
local native_team_views, handshake_views = 0, 0
for element in manifest:gmatch('<CustomUIElement%s+.-/>') do
    if element:match('type="GameSetup"') then
        local layout = element:match('layoutfile="([^"]+)"')
        if layout == 'file://{resources}/layout/custom_game/native_team_setup.xml' then
            native_team_views = native_team_views + 1
        elseif layout == 'file://{resources}/layout/custom_game/startup_team_setup_loading.xml' then
            handshake_views = handshake_views + 1
        end
    end
end
assert(native_team_views == 1,
    'an infinite native setup phase needs exactly one registered official team-select wrapper')
assert(handshake_views == 1,
    'keep the separate loading handshake context alongside the visible official setup')
local native_layout_file = assert(io.open('panorama/src/layout/custom_game/native_team_setup.xml', 'rb'))
local native_layout = native_layout_file:read('*a')
native_layout_file:close()
assert(native_layout:find('file://{resources}/scripts/custom_game/native_team_setup.js', 1, true),
    'the registered native setup wrapper must include its real loader script')
assert(not native_layout:find('layout/custom_game/team_select.xml', 1, true),
    'keep native XML out of static compile dependencies: Valve only ships its compiled CSS tree')
local native_script_file = assert(io.open('panorama/src/scripts/custom_game/native_team_setup.js', 'rb'))
local native_script = native_script_file:read('*a')
native_script_file:close()
assert(native_script:find('file://{resources}/layout/custom_game/team_select.xml', 1, true)
    and native_script:find('BLoadLayout', 1, true),
    'the real setup loader must mount Valve team_select.xml at runtime')
print('STARTUP_NATIVE_SETUP_MANIFEST_PASS: official host start view and loading handshake are both mounted')
