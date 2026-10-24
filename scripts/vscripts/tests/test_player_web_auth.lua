package.path = "scripts/vscripts/?.lua;" .. package.path
local json = require("core/json_encoder")
local decoder = require("core/json_decoder")
local config = { enabled = true, base_url = "https://pay.xiaofengnet.com/ws4-web" }
package.loaded["config/player_web_auth"] = config
package.loaded["core/test_access_policy"] = { allowed = function(id) return id == 0 or id == 1 end }
local clock, session, admitted, selected_mode = 0, "web_auth_fixture_match_1", false, false
local players, requests, events, listeners = {}, {}, {}, {}
local authenticated = {}
Time = function() return clock end
IsServer = function() return true end
DOTA_MAX_TEAM_PLAYERS = 4
local function player(id, account)
    local entity = { id = id }
    function entity:GetPlayerID() return self.id end
    function entity:IsNull() return false end
    players[id] = { entity = entity, account = account, connected = 2, team = 2 }
end
player(0, 1001); player(1, 1002)
PlayerResource = {
    IsValidPlayerID = function(_, id) return players[id] ~= nil end,
    IsFakeClient = function() return false end,
    GetTeam = function(_, id) return players[id] and players[id].team end,
    GetConnectionState = function(_, id) return players[id] and players[id].connected end,
    GetSteamAccountID = function(_, id) return players[id] and players[id].account end,
    GetPlayer = function(_, id) return players[id] and players[id].entity end,
}
EntIndexToHScript = function(index) return players[index - 200] and players[index - 200].entity end
CustomNetTables = { SetTableValue = function() error("web authentication must not publish a nettable") end }
CustomGameEventManager = {
    RegisterListener = function(_, name, callback) listeners[name] = callback return name end,
    UnregisterListener = function(_, name) listeners[name] = nil end,
    Send_ServerToPlayer = function(_, entity, name, body)
        assert(name == "survival_player_web_auth_state" and body.player_id == entity.id)
        assert(body.device_code == nil and body.access_token == nil and body.account_id == nil)
        local raw = json.encode(body)
        assert(not raw:find("device_fixture", 1, true) and not raw:find("pwa1_", 1, true))
        events[#events + 1] = { id = entity.id, body = body }
    end,
}
package.loaded["systems/startup_loading_service"] = { is_ready = function() return admitted end }
package.loaded["systems/player_profile_service"] = {
    is_authenticated_for_account = function(id) return authenticated[id] == true end,
}
package.loaded["systems/match_setup_service"] = {
    get_session_id = function() return session end,
    is_mode_selected = function() return selected_mode end,
}
Convars = { GetStr = function() return "legacy_fixture_server_bearer" end }
CreateHTTPRequestScriptVM = function(method, url)
    local request = { method = method, url = url, headers = {} }
    function request:SetHTTPRequestHeaderValue(key, value) self.headers[key] = value end
    function request:SetHTTPRequestRawPostBody(_, raw) self.body = decoder.decode(raw) end
    function request:SetHTTPRequestAbsoluteTimeoutMS(ms) self.timeout = ms end
    function request:Send(callback) self.complete = callback end
    requests[#requests + 1] = request
    return request
end
local web = require("systems/player_web_auth")
local provider = require("systems/player_profile_providers/http_fishing_provider")
provider.init()
local errors, successes = {}, {}
local function failure(code) errors[#errors + 1] = code end
local function success(url, token) successes[#successes + 1] = {url, token} end
local function resolve(account) web.resolve(account or "1001", session, success, failure) end
local function reply(index, body, status)
    assert(requests[index] and requests[index].complete)
    requests[index].complete({ StatusCode = status or 200, Body = json.encode(body) })
end
local function pending(code)
    return {ok=true,status="pending",device_code="device_fixture_abcdefghijklmnopqrstuvwxyz",user_code=code or "ABCD2345",
        verification_uri=config.base_url .. "/authorize?code=" .. (code or "ABCD2345"), expires_in=600,poll_interval=3}
end
local function approved(account)
    return {ok=true,status="approved",account_id=account or "1001",match_session_id=session,
        access_token="pwa1_" .. string.rep("a",64),expires_in=14400}
end
web.init(session)
provider.lottery_catalog({md5="fixture_catalog"}, function() error("no authorization exists") end, failure)
assert(#requests == 0 and #events == 0 and errors[#errors] == "player_web_auth_pending",
    "server metadata waits for a real approval without creating another player's flow")
local errors_before_start = #errors
resolve()
assert(#requests == 1 and requests[1].url == config.base_url .. "/v1/player-auth/start")
assert(requests[1].body.account_id == "1001" and requests[1].body.match_session_id == session)
assert(requests[1].headers.Authorization == nil, "start must not use an author/server bearer")
assert(#successes == 0 and #errors == errors_before_start, "HTTP start is genuinely asynchronous")
resolve()
assert(#requests == 1 and errors[#errors] == "player_web_auth_pending", "one HTTP start per binding")
reply(1, pending())
assert(events[#events].body.user_code == "ABCD2345" and events[#events].id == 0)
clock = 2; resolve()
assert(#requests == 1, "no poll before the minimum interval")
clock = 3; resolve()
assert(requests[2].url:match("/player%-auth/poll$") and requests[2].body.device_code)
reply(2, {ok=true,status="pending"})
clock = 6
local receipt
provider.authenticate("1001", function(value) receipt = value end, failure)
assert(#requests == 3 and requests[3].url:match("/player%-auth/poll$"))
reply(3, approved())
assert(#requests == 4 and requests[4].url == config.base_url .. "/v1/session/authenticate")
assert(requests[4].headers.Authorization == "Bearer " .. approved().access_token)
assert(requests[4].body.account_id == "1001" and requests[4].body.match_session_id == session)
reply(4, {authenticated=true,account_id="1001",match_session_id=session,progression={}})
assert(receipt and receipt.authenticated == true, "browser approval still invokes ordinary admission authentication")
resolve()
assert(#requests == 4 and successes[#successes][2] == approved().access_token, "private capability cache is reusable")

-- Event identity is the server-supplied entity, never payload PlayerID/account.
local callback = listeners.survival_player_web_auth_request
callback(200, {session_id=session,PlayerID=1,account_id="1002"})
assert(#requests == 4, "spoofed fields cannot start another account")
callback(201, {session_id=session,PlayerID=0,account_id="1001"})
assert(#requests == 5 and requests[5].body.account_id == "1002")
reply(5, pending("EFGH6789"))
assert(events[#events].id == 1 and events[#events].body.user_code == "EFGH6789")
clock = 9; resolve("1002")
assert(requests[6].body.device_code == pending().device_code and requests[6].body.account_id == "1002")
local count = #requests
callback(-1,{session_id=session}); callback(1,{session_id=session}); callback(201,{session_id="wrong_session"})
admitted = true; callback(201,{session_id=session}); admitted = false
assert(#requests == count, "unknown sources, wrong sessions and an open gate cannot trigger auth HTTP")

-- Rebinding a player slot drops the old asynchronous approval and its secret.
local before = #events
player(1, 1003)
reply(6, approved("1002"))
assert(#events == before and #requests == count)
resolve("1002")
assert(errors[#errors] == "player_web_auth_binding_changed")
player(1, 1002)
resolve("1002")
assert(#requests == count + 1 and requests[#requests].url:match("/player%-auth/start$"))

-- New match epochs reject late responses, rather than passing old tokens on.
local old_request = #requests
session = "web_auth_fixture_match_2"; web.init(session)
reply(old_request, pending())
assert(#events == before + 1, "only the new start's pre-response state was published")
resolve(); local malformed = pending(); malformed.verification_uri = "https://other.invalid/authorize?code=ABCD2345"
reply(#requests, malformed)
assert(errors[#errors] == "player_web_auth_invalid_response" and events[#events].body.verification_uri == "")
local limited_count = #requests
resolve(); assert(#requests == limited_count, "failed starts also retain the three-second request limit")
clock = 12; resolve(); reply(#requests, pending())
clock = 15; resolve(); reply(#requests, approved("1002"))
assert(errors[#errors] == "player_web_auth_invalid_response", "an approved receipt cannot change account")

-- Expired codes stop polling, clear the old display, then start a fresh flow.
clock = 612; resolve()
assert(errors[#errors] == "player_web_auth_expired" and events[#events].body.user_code == "")
local expired_count = #requests
resolve(); assert(#requests == expired_count + 1 and requests[#requests].url:match("/player%-auth/start$"))
reply(#requests, pending())
local native_http = CreateHTTPRequestScriptVM
CreateHTTPRequestScriptVM = function() error("private-native-detail") end
clock = 615; resolve()
assert(errors[#errors] == "player_web_auth_unavailable", "native exceptions become fixed errors")
CreateHTTPRequestScriptVM = native_http
local before_client = #requests
IsServer = function() return false end
resolve()
assert(#requests == before_client and errors[#errors] == "player_web_auth_configuration_invalid",
    "a client VM cannot create or retrieve a player capability")
IsServer = function() return true end

-- The existing server-wide catalog has no account field. It may borrow only
-- an already-approved current player capability, with deterministic ownership.
requests, events = {}, {}
session, clock = "web_auth_metadata_match", 1000
web.init(session)
assert(web.authorized_account(session) == nil)
resolve("1002"); reply(1, pending("EFGH6789"))
clock = 1003; resolve("1002")
local second_approval = approved("1002")
second_approval.access_token = "pwa1_" .. string.rep("b",64)
reply(2, second_approval)
assert(web.authorized_account(session) == "1002")
resolve("1001"); reply(3, pending())
clock = 1006; resolve("1001"); reply(4, approved())
assert(web.authorized_account(session) == "1001", "lowest current PlayerID wins, regardless of approval order")
provider.lottery_catalog({md5="fixture_catalog"}, function() end, failure)
assert(#requests == 5 and requests[5].url == config.base_url .. "/v1/lottery/catalog")
assert(requests[5].body.account_id == "1001" and requests[5].body.match_session_id == session
    and requests[5].body.md5 == "fixture_catalog")
assert(requests[5].headers.Authorization == "Bearer " .. approved().access_token)
selected_mode = true
provider.lottery_snapshot({}, function() error("accountless private request must fail") end, failure)
assert(#requests == 5 and errors[#errors] == "player_web_auth_binding_changed",
    "the approved-account fallback is confined to the read-only catalog route")
selected_mode = false
players[0].connected = 0
assert(web.authorized_account(session) == "1002", "a disconnected owner's capability cannot serve metadata")
provider.lottery_catalog({md5="fixture_catalog"}, function() end, failure)
assert(#requests == 6 and requests[6].body.account_id == "1002"
    and requests[6].headers.Authorization == "Bearer " .. second_approval.access_token)
clock = 20000
provider.lottery_catalog({md5="fixture_catalog"}, function() error("expired approval") end, failure)
assert(#requests == 6 and web.authorized_account(session) == nil and errors[#errors] == "player_web_auth_pending")
session = "web_auth_metadata_new_match"; web.init(session)
assert(web.authorized_account(session) == nil and web.authorized_account("web_auth_metadata_match") == nil)

-- Explicit disable preserves the existing server/workshop route unchanged.
config.enabled = false; web.init(session)
provider.authenticate("1001", function() end, failure)
assert(requests[#requests].url:match("/v1/session/authenticate$"))
assert(requests[#requests].url ~= config.base_url .. "/v1/session/authenticate")
assert(requests[#requests].headers.Authorization == "Bearer legacy_fixture_server_bearer")

-- Each failure phase exports only one bounded enum tuple to its own player.
-- No HTTP body, native exception, account, session or capability is logged.
local ordinary_print, diagnostics = print, {}
print = function(value) diagnostics[#diagnostics + 1] = value end
local diagnostic_case = 0
local function reset_diagnostic()
    diagnostic_case = diagnostic_case + 1
    session, clock = "web_auth_diagnostic_" .. diagnostic_case, 30000
    config.enabled = true
    requests, events, errors, successes, diagnostics = {}, {}, {}, {}, {}
    players[0].connected, players[1].connected = 2, 2
    CreateHTTPRequestScriptVM = native_http
    web.init(session)
end
local function expect_diagnostic(phase, stage, status)
    local event = events[#events]
    assert(event and event.id == 0 and event.body.status == "failed")
    local body = event.body
    assert(body.diagnostic_revision == "WS4-WEB-04" and body.diagnostic_phase == phase
        and body.diagnostic_stage == stage and body.diagnostic_status == status)
    assert(body.user_code == "" and body.verification_uri == "", "failure diagnostics never expose a stale short code")
    assert(body.error == "player_web_auth_unavailable" or body.error == "player_web_auth_invalid_response")
    assert(diagnostics[#diagnostics] == "[WS4-WEB-04] phase=" .. phase .. " stage=" .. stage .. " status=" .. status)
    local exported = json.encode(events) .. table.concat(diagnostics, "\n")
    for _, private in ipairs({"private-native-detail", "private-response-body", "device_fixture", "pwa1_"}) do
        assert(not exported:find(private, 1, true), "diagnostic leaked private data")
    end
    for _, log in ipairs(diagnostics) do
        assert(not log:find(session, 1, true) and not log:find("1001", 1, true))
    end
end
local function send_behavior(behavior)
    CreateHTTPRequestScriptVM = function(method, url)
        local http = native_http(method, url)
        function http:Send(callback)
            self.complete = callback
            return behavior(self, callback)
        end
        return http
    end
end

reset_diagnostic(); CreateHTTPRequestScriptVM = nil; resolve()
expect_diagnostic("start", "API", 0)
for _, construct in ipairs({function() return nil end, function() error("private-native-detail") end}) do
    reset_diagnostic(); CreateHTTPRequestScriptVM = construct; resolve()
    expect_diagnostic("start", "create", 0)
end
for _, send in ipairs({function() return false end, function() error("private-native-detail") end}) do
    reset_diagnostic(); send_behavior(send); resolve()
    expect_diagnostic("start", "send", 0)
    local before_late = #events
    reply(1, pending())
    assert(#events == before_late and #successes == 0, "a rejected send cannot later publish or approve")
end

for _, response in ipairs({{}, {StatusCode=0}, {StatusCode=403}, {StatusCode=429}, {StatusCode=502},
    {StatusCode=-1}, {StatusCode=600}, {StatusCode=200.5}, {StatusCode="private-native-detail"}}) do
    reset_diagnostic(); resolve()
    response.Body = "private-response-body"
    requests[1].complete(response)
    local status = tonumber(response.StatusCode)
    if not status or status < 0 or status > 599 or status ~= math.floor(status) then status = 0 end
    expect_diagnostic("start", "http", status)
end
reset_diagnostic(); resolve(); requests[1].complete(nil)
expect_diagnostic("start", "http", 0)
for _, raw in ipairs({"private-response-body", string.rep("x", 16385), "true"}) do
    reset_diagnostic(); resolve(); requests[1].complete({StatusCode=200, Body=raw})
    expect_diagnostic("start", "json", 200)
end
reset_diagnostic(); resolve(); requests[1].complete({StatusCode=200})
expect_diagnostic("start", "json", 200)
reset_diagnostic(); resolve(); requests[1].complete({StatusCode=200, Body="null"})
expect_diagnostic("start", "fields", 200)
for _, body in ipairs({{ok=false,error="private-response-body"}, {ok=true,status="pending"}}) do
    reset_diagnostic(); resolve(); reply(1, body)
    expect_diagnostic("start", "fields", 200)
end
reset_diagnostic(); resolve()
local injected_uri = pending(); injected_uri.verification_uri = "https://other.invalid/private-response-body"
reply(1, injected_uri); expect_diagnostic("start", "fields", 200)

-- A void/nil Send result is supported by the native API. Missing callbacks
-- produce their own timeout, and a late callback cannot change that result.
reset_diagnostic(); resolve()
assert(#errors == 0, "void native Send is an accepted asynchronous request")
clock = clock + 16; resolve()
expect_diagnostic("start", "timeout", 0)
local timed_events = #events
reply(1, pending())
assert(#events == timed_events and #successes == 0)
resolve(); assert(#requests == 2, "a timeout permits a fresh request on the next retry")
reply(2, pending())
assert(events[#events].body.status == "pending" and events[#events].body.user_code == "ABCD2345")
assert(events[#events].body.diagnostic_revision == "" and events[#events].body.diagnostic_stage == "")

-- Poll diagnostics retain phase identity and hide codes while failed. A valid
-- pending receipt restores only the original, strictly validated public code.
clock = clock + 3; resolve(); requests[3].complete({StatusCode=403,Body="private-response-body"})
expect_diagnostic("poll", "http", 403)
clock = clock + 3; resolve(); reply(4, {ok=true,status="pending"})
assert(events[#events].body.status == "pending" and events[#events].body.user_code == "ABCD2345"
    and events[#events].body.diagnostic_revision == "")
clock = clock + 3; resolve(); reply(5, approved("1002"))
expect_diagnostic("poll", "fields", 200)
clock = clock + 3; resolve(); reply(6, approved())
assert(events[#events].body.status == "approved" and events[#events].body.diagnostic_revision == ""
    and events[#events].body.user_code == "" and #successes == 1)

-- The usual three-second startup retries must not flood native game logs.
reset_diagnostic(); CreateHTTPRequestScriptVM = nil; resolve()
expect_diagnostic("start", "API", 0)
for _ = 1, 9 do clock = clock + 3; resolve() end
assert(#diagnostics == 1, "identical failures are logged at most once in thirty seconds")
clock = clock + 3; resolve()
assert(#diagnostics == 2, "a persistent failure still emits a bounded periodic diagnostic")
CreateHTTPRequestScriptVM = function() return nil end
clock = clock + 3; resolve()
expect_diagnostic("start", "create", 0)
assert(#diagnostics == 3, "a changed failure stage is immediately distinguishable")
CreateHTTPRequestScriptVM, print = native_http, ordinary_print
print("PLAYER_WEB_AUTH_PASS: asynchronous approval, private state, provider routing, epochs and bounded WS4-WEB-04 diagnostics")
