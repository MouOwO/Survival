package.path = "scripts/vscripts/?.lua;" .. package.path

local time, humans, disconnected, profiles, pending, requests, listeners, published, thinker
local engine_state, authenticated, profile_pending, profile_requests, responses, history
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
        get_progression = function(id)
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
local function success(request, counts)
    local response = { ok = true, authenticated = true, account_id = request.account,
        match_session_id = request.session,
        progression = { loaded = true, clear_counts = counts or {}, highest_difficulty = 0 } }
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

-- Admission authenticates independently of mode. Mode profiles release a
-- separate gameplay gate after the engine has already entered the game.
local admitted, playable = 0, 0
local choosing = fixture(2, { on_ready = function() admitted = admitted + 1 end })
choosing.gameplay_gate(function() playable = playable + 1 end)
assert(#requests == 2 and #profile_requests == 0 and not choosing.snapshot().setup.mode_selected)
select_mode(choosing, "pure")
assert(not choosing.snapshot().setup.mode_selected and #profile_requests == 0,
    "even the host cannot choose a mode before admission")
assert(responses[#responses].payload.error == "admission_not_complete")
assets_done() ui(choosing, 0) ui(choosing, 1)
assert(not choosing.is_ready(), "UI flags never replace backend authentication")
success(requests[1], { n5 = 1 }) success(requests[2], { n6 = 1 }) choosing.tick()
assert_admitted(choosing)
assert(admitted == 1 and playable == 0 and not choosing.is_gameplay_ready())
assert(not choosing.snapshot().profiles_ready and not choosing.is_player_ready(0) and #profile_requests == 0)
local options = choosing.snapshot().setup.difficulty_options
assert(options[6].unlocked == 1 and options[7].unlocked == 0,
    "difficulty choices use authenticated host progression before mode-profile loading")
local selection_session = choosing.snapshot().session_id
select_mode(choosing, "pure", 1)
assert(not choosing.snapshot().setup.mode_selected and responses[#responses].payload.error == "selection_not_host")
select_mode(choosing, "pure", 0, "old-session")
assert(not choosing.snapshot().setup.mode_selected and #profile_requests == 0)
select_mode(choosing, "pure")
assert(choosing.snapshot().setup.mode_id == "pure" and #profile_requests == 2)
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
disconnected[1] = false
assert(service.is_player_ready(1), "same-account reconnect keeps its authenticated save")
humans[1].account, profiles[1] = 9000, { account_id = "9000", revision = 1 }
assert(not service.is_player_ready(1), "a new account cannot inherit an admitted player slot")
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

-- Tools party room: no timer, stale UI event, or joining client may start it.
local dispatched = 0
local party = fixture(3, { wait_for_party = true,
    on_load_start = function() dispatched = dispatched + 1 end })
assert(party.is_party_waiting() and party.snapshot().party_count == 3)
time = 1000
party.tick()
assert(#requests == 0 and dispatched == 0 and not party.is_ready())
ui(party, 0)
local sid = party.snapshot().session_id
listeners.survival_party_start(201, {session_id=sid, PlayerID=0})
listeners.survival_party_start(200, {session_id='stale-session'})
assert(party.is_party_waiting() and dispatched == 0)
humans[2].state = 3
disconnected[2] = true
party.tick()
assert(party.snapshot().party_count == 2)
Convars = { GetStr = function() return '' end }
listeners.survival_party_start(200, {session_id=sid})
assert(not party.is_party_waiting() and dispatched == 1 and #requests == 0)
assert(party.snapshot().phase == 'connecting_backend' and #party.snapshot().players == 2)
time = time + 60
party.tick()
assert(party.snapshot().error == 'backend_connection_pending' and #requests == 0)
Convars = { GetStr = function() return 'test-credential-present' end }
party.tick()
assert(#requests == 2 and dispatched == 1)
listeners.survival_party_start(200, {session_id=sid})
assert(#requests == 2 and dispatched == 1, 'double click cannot repeat loading')
for _, request in ipairs(requests) do success(request) end
ui(party, 1)
assets_done()
party.tick()
assert_admitted(party)
Convars = nil
local solo_dispatch = 0
local solo = fixture(1, { on_load_start = function() solo_dispatch = solo_dispatch + 1 end })
assert(not solo.is_party_waiting() and solo_dispatch == 1 and #requests == 1)
print('STARTUP_PARTY_ROOM_PASS: host authority, no early auth, disconnect cleanup, backend wait, once-only dispatch')
