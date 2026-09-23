package.path = "scripts/vscripts/?.lua;" .. package.path
local json = require("core/json_encoder")
local decoder = require("core/json_decoder")
local mode, session, account = nil, "entry_auth_session_1", "9000000123"
local token, events_seen = "fictional-test-token", 0
package.loaded["systems/match_setup_service"] = {
    get_mode = function() return mode end,
    get_session_id = function() return session end,
    is_mode_selected = function() return mode ~= nil end,
}
local tasks, requests, entitlement_calls = {}, {}, 0
package.loaded["core/scheduler"] = { every = function(_, fn, key) tasks[key] = fn end }
package.loaded["core/logger"] = { info = function() end, warn = function() end }
package.loaded["systems/player_entitlement_service"] = {
    replace_all = function() entitlement_calls = entitlement_calls + 1 end,
}
Convars = { RegisterConvar = function() end,
    GetStr = function(_, key) return key == "survival_fishing_api_token" and token or "" end }
GameRules = { GetGameModeEntity = function() return {} end, GetGameTime = function() return 100 end }
PlayerResource = { IsValidPlayerID = function(_, id) return id == 0 end,
    GetSteamAccountID = function() return tonumber(account) end }
CreateHTTPRequestScriptVM = function(_, url)
    local request = {url=url}
    requests[#requests+1] = request
    function request:SetHTTPRequestHeaderValue() end
    function request:SetHTTPRequestAbsoluteTimeoutMS() end
    function request:SetHTTPRequestRawPostBody(_, body) self.body = decoder.decode(body) end
    function request:Send(callback) self.complete = callback end
    return request
end
local profiles = require("systems/player_profile_service")
local bus = require("core/event_bus")
local events = require("core/events")
profiles.init()
bus.subscribe(events.PLAYER_PROFILE_CHANGED, function() events_seen = events_seen + 1 end)
local function receipt()
    return {authenticated=true,account_id=account,match_session_id=session,
        progression={loaded=true,clear_counts={n5=2},highest_difficulty=5}}
end
local function respond(index, value, status)
    requests[index].complete({StatusCode=status or 200,Body=json.encode(value)})
end
local callbacks, last = 0, nil
local function finished(result) callbacks, last = callbacks + 1, result end
assert(profiles.get_profile(0) == nil and not profiles.is_authenticated_for_account(0, account))
assert(profiles.load_player(0).error == "mode_not_selected")
local request = profiles.authenticate_player(0, "entry", finished)
assert(request.ok and request.pending and profiles.is_authenticating(0))
assert(requests[1].url:match("/v1/session/authenticate$") and requests[1].body.mode == nil)
assert(requests[1].body.account_id == account and requests[1].body.match_session_id == session)
respond(1, receipt())
assert(callbacks == 1 and last.ok and last.authenticated and not last.pending)
assert(profiles.is_authenticated_for_account(0, account) and not profiles.is_authenticating(0))
assert(not profiles.is_loaded_for_account(0, account) and profiles.get_profile(0) == nil)
assert(profiles.get_account_profile(0) == nil and entitlement_calls == 0 and events_seen == 0)
assert(profiles.get_progression(0).clear_counts.n5 == 2)
local copied = profiles.get_authenticated_progression(0)
copied.clear_counts.n5 = 999
assert(profiles.get_authenticated_progression(0).clear_counts.n5 == 2)
profiles.authenticate_player(0, "cached", finished)
assert(callbacks == 2 and last.cached and #requests == 1)
tasks.http_profile_preload()
assert(#requests == 1, "authentication does not bypass the unselected-mode load gate")

mode = "pure"
profiles.load_player(0)
assert(#requests == 2 and requests[2].url:match("/v1/session/login$"),
    "entry authentication must not populate provider logged_in")
respond(2, {schema_version=1,account_id=account,revision=2,match_session_id=session,mode=mode,
    progression={loaded=true,clear_counts={n5=2,n6=1},highest_difficulty=6},
    entitlements={},achievements={},public={},save={gameplay_stats={},archive={},content_inventory={}}})
assert(profiles.is_loaded_for_account(0, account))
assert(profiles.get_progression(0).clear_counts.n6 == 1, "mode profile supersedes entry permissions")
local calls = entitlement_calls
profiles.authenticate_player(0, "after_mode", finished)
assert(#requests == 2 and entitlement_calls == calls and profiles.is_loaded_for_account(0, account))

-- A new game and a replaced account slot cannot inherit previous authentication.
session, mode = "entry_auth_session_2", nil
assert(not profiles.is_authenticated_for_account(0, account))
assert(profiles.get_authenticated_progression(0) == nil and profiles.get_progression(0) == nil)
profiles.authenticate_player(0, "new_entry", finished)
local old = #requests
profiles.authenticate_player(0, "timeout_retry", finished)
local retry = #requests
local previous_callbacks = callbacks
respond(old, receipt())
assert(callbacks == previous_callbacks and profiles.is_authenticating(0), "superseded replies cannot finish the replacement")
respond(retry, {error="database_unavailable"}, 503)
assert(callbacks == previous_callbacks + 1 and not last.ok and not profiles.is_authenticating(0))
assert(not profiles.is_authenticated_for_account(0, account))

profiles.authenticate_player(0, "wrong_account", finished)
local wrong = receipt(); wrong.account_id = "9000000456"
respond(#requests, wrong)
assert(not last.ok and last.error == "authentication_identity_mismatch")
profiles.authenticate_player(0, "bad_progression", finished)
local bad = receipt(); bad.progression.clear_counts.n5 = -1
respond(#requests, bad)
assert(not last.ok and last.error == "authentication_progression_invalid")
profiles.authenticate_player(0, "slot_changed", finished)
local old_receipt = receipt()
account = "9000000456"
respond(#requests, old_receipt)
assert(not last.ok and not profiles.is_authenticated_for_account(0, account))

token = ""
previous_callbacks = callbacks
local failed = profiles.authenticate_player(0, "missing_token", finished)
assert(callbacks == previous_callbacks + 1 and failed.pending == false and failed.error == "fishing_api_token_missing")
assert(not profiles.is_authenticated_for_account(0, account) and not profiles.is_authenticating(0))
token = "fictional-test-token"
profiles.authenticate_player(0, "token_restored", finished)
respond(#requests, receipt())
assert(last.ok and profiles.is_authenticated_for_account(0, account))
assert(not profiles.is_loaded_for_account(0, account), "auth recovery still must wait for mode selection")
print("PLAYER_ENTRY_AUTHENTICATION_PASS: auth-only gate, no profile/entitlement effects, mode-login separation, progression, retry/session/account isolation")
