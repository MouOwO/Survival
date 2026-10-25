-- Real client-facing profile guards, with synthetic engine and HTTP delivery.
-- Run only in standalone Lua 5.1; never loaded into a Dota match.
package.path = "scripts/vscripts/?.lua;" .. package.path
assert(GameRules == nil and CreateHTTPRequestScriptVM == nil, "standalone_fixture_only")
local decode = require("core/json_decoder").decode
local encode = require("core/json_encoder").encode
local data = decode(io.read("*a"))
local mode, session, requests, accounts = nil, nil, {}, {}
local game_mode_entity = {}
IsServer, IsInToolsMode = function() return true end, function() return true end
local disconnects = {}
DisconnectClient = function(id) disconnects[#disconnects + 1] = id end
package.loaded["config/test_access"] = {enabled = true, allowed_steamids = data.synthetic_steamids}
package.loaded["systems/match_setup_service"] = {
    get_mode = function() return mode end,
    get_profile_mode = function() return mode == "pure" and "pure" or "standard" end,
    get_session_id = function() return session end,
    is_mode_selected = function() return mode ~= nil end,
}
package.loaded["core/logger"] = {info = function() end, warn = function() end}
package.loaded["core/scheduler"] = {every = function() end}
package.loaded["systems/player_entitlement_service"] = {replace_all = function() end}
GameRules = {GetGameTime = function() return 100 end, GetGameModeEntity = function() return game_mode_entity end}
PlayerResource = {IsValidPlayerID = function(_, id) return accounts[id] ~= nil end,
    GetSteamAccountID = function(_, id) return tonumber(accounts[id]) end}
Convars = {RegisterConvar = function() end, GetStr = function(_, key)
    return key == "survival_fishing_api_token" and "ui-qa-synthetic-token-only" or "" end}
CreateHTTPRequestScriptVM = function(method, url)
    assert(method == "POST" and url:match("^http://127%.0%.0%.1:8765/v1/"), "loopback_transport_fixture_only")
    local request = {url = url}
    requests[#requests + 1] = request
    function request:SetHTTPRequestHeaderValue(name, value)
        assert(name == "Authorization" and value == "Bearer ui-qa-synthetic-token-only")
    end
    function request:SetHTTPRequestRawPostBody(_, body) self.body = decode(body) end
    function request:SetHTTPRequestAbsoluteTimeoutMS() end
    function request:Send(callback) self.complete = callback end
    return request
end
local bus = require("core/event_bus")
local profiles = require("systems/player_profile_service")
local checks, delayed = 0, nil
local function check(value, label)
    checks = checks + 1
    assert(value, label)
end
local function reply(request, snapshot)
    request.complete({StatusCode = 200, Body = encode(snapshot)})
end
local function refresh(id)
    local result = profiles.refresh_player(id, "ui_qa_five_match")
    check(result.ok and result.pending, "refresh has one synthetic in-flight request")
    return requests[#requests]
end
local function verify(id, view)
    local combat, account = profiles.get_profile(id), profiles.get_account_profile(id)
    check(combat and combat.account_id == view.account_id and combat.revision == view.revision, "correct combat account/revision")
    check(combat.match_session_id == session, "current session owns combat snapshot")
    for _, key in ipairs({"lottery_ticket", "special_lottery_ticket"}) do
        check((combat.save.content_inventory[key] or 0) == (view.save.content_inventory[key] or 0), "combat inventory " .. key)
        local expected = view.account_profile or view
        check((account.save.content_inventory[key] or 0) == (expected.save.content_inventory[key] or 0), "permanent inventory " .. key)
    end
    check(combat.save.gameplay_stats.initial_wood == view.save.gameplay_stats.initial_wood, "pure/standard combat stat projection")
end

for _, round in ipairs(data.rounds) do
    mode, session, game_mode_entity = round.mode, round.session, {}
    accounts = {}
    for index, row in ipairs(round.accounts) do accounts[index - 1] = row.account end
    bus.reset()
    profiles.init()
    accounts[4] = "81999999"
    local count_before = #requests
    local denied = profiles.load_player(4, "ui_qa_fifth_account")
    check(not denied.ok and denied.error == "test_access_denied", "fifth synthetic account remains denied")
    check(#requests == count_before and disconnects[#disconnects] == 4, "denial precedes HTTP and records synthetic disconnect")
    accounts[4] = nil
    local pending = {}
    for index, row in ipairs(round.accounts) do
        local id = index - 1
        local result = profiles.load_player(id, "ui_qa_match_login")
        check(result.ok and result.pending, "new match waits for HTTP login: " .. tostring(result.error))
        pending[id] = requests[#requests]
        check(pending[id].body.match_session_id == session and pending[id].body.mode == mode, "wire identity retains gameplay mode")
    end
    if delayed then
        reply(delayed.request, delayed.snapshot)
        for id = 0, 3 do check(profiles.get_profile(id) == nil, "old match callback cannot populate new match") end
    end
    for index = #round.accounts, 1, -1 do
        local row, id = round.accounts[index], index - 1
        reply(pending[id], row.login)
        verify(id, row.login)
        local older, newer = refresh(id), refresh(id)
        reply(newer, row.final_view)
        verify(id, row.final_view)
        reply(older, row.reward_view)
        verify(id, row.final_view)
        local wrong = profiles.apply_snapshot(id, round.accounts[index % #round.accounts + 1].final_view, "ui_qa_wrong_account")
        check(not wrong.ok and wrong.error == "account_id_mismatch", "cross-account response rejected")
        verify(id, row.final_view)
        local stale = profiles.apply_snapshot(id, row.reward_view, "ui_qa_old_revision")
        check(not stale.ok and stale.error == "snapshot_revision_stale", "late lower revision rejected")
        -- A reconnect-style reload uses the real provider's /profile path.
        local reload = profiles.load_player(id, "ui_qa_reconnect")
        check(reload.ok and reload.pending and requests[#requests].url:match("/v1/profile$"), "same-session reconnect reads existing profile")
        reply(requests[#requests], row.final_view)
        verify(id, row.final_view)
    end
    delayed = {request = refresh(0), snapshot = round.accounts[1].final_view}
end
print("UI_QA_FIVE_MATCH_CLIENT_PASS matches=5 accounts=4 checks=" .. tostring(checks) .. " native_games=0 network=0")
