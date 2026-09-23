package.path = "scripts/vscripts/?.lua;" .. package.path
local json = require("core/json_encoder")
local decoder = require("core/json_decoder")
local mode, session = nil, "mode_fixture_session_1"
package.loaded["systems/match_setup_service"] = {
    get_mode = function() return mode end,
    get_session_id = function() return session end,
    is_mode_selected = function() return mode ~= nil end,
}
local tasks, requests, entitlements = {}, {}, {}
package.loaded["core/scheduler"] = { every = function(_, fn, key) tasks[key] = fn end }
package.loaded["core/logger"] = { info = function() end, warn = function() end }
package.loaded["systems/player_entitlement_service"] = {
    replace_all = function(id, values) entitlements[id] = values end,
}
Convars = { RegisterConvar = function() end,
    GetStr = function(_, key) return key == "survival_fishing_api_token" and "fictional-test-token" or "" end }
GameRules = { GetGameModeEntity = function() return {} end, GetGameTime = function() return 100 end }
PlayerResource = { IsValidPlayerID = function(_, id) return id == 0 end,
    GetSteamAccountID = function() return 9000000123 end }
CreateHTTPRequestScriptVM = function(method, url)
    local request = { method = method, url = url }
    requests[#requests+1] = request
    function request:SetHTTPRequestHeaderValue() end
    function request:SetHTTPRequestAbsoluteTimeoutMS() end
    function request:SetHTTPRequestRawPostBody(_, body) self.body = decoder.decode(body) end
    function request:Send(callback) self.complete = callback end
    return request
end
local profiles = require("systems/player_profile_service")
profiles.init()
local function snapshot(revision)
    return { schema_version = 1, account_id = "9000000123", revision = revision,
        match_session_id = session, mode = mode,
        progression = { loaded = true, clear_counts = {n5=2}, highest_difficulty=5 },
        entitlements = {}, achievements = {}, public = {},
        save = { gameplay_stats = {}, archive = {}, content_inventory = {} } }
end
local function respond(index, value)
    requests[index].complete({StatusCode=200,Body=json.encode(value)})
end

assert(profiles.load_player(0).error == "mode_not_selected")
tasks.http_profile_preload()
assert(#requests == 0 and entitlements[0] == nil, "mode gate precedes invalidation and HTTP")
mode = "pure"
profiles.load_player(0)
assert(requests[1].url:match("/v1/session/login$"), "pure first request must be login")
assert(requests[1].body.match_session_id == session and requests[1].body.mode == "pure")
respond(1, snapshot(9))
assert(profiles.is_loaded_for_account(0, "9000000123"))
assert(profiles.get_profile(0).save.gameplay_stats.initial_wood == 10)
assert(next(profiles.get_profile(0).save.archive) == nil)
assert(profiles.get_progression(0).clear_counts.n5 == 2, "difficulty permissions survive pure default view")
assert(not entitlements[0].vip)
local business = snapshot(10)
business.mode, business.match_session_id, business.progression = nil, nil, nil
business.save.gameplay_stats.initial_wood = 900
business.save.archive.clear_counts = {n5=2,n6=1}
business.save.content_inventory = {old_permanent=1,new_permanent=1}
business.entitlements = {vip={active=true}}
local update = snapshot(10)
update.save.gameplay_stats.initial_wood = 12
update.save.content_inventory.new_permanent = 1
update.account_profile = business
update.progression.clear_counts.n6 = 1
assert(profiles.apply_snapshot(0, update, "archive_online_checkpoint").ok)
assert(profiles.get_profile(0).save.gameplay_stats.initial_wood == 12)
assert(profiles.get_profile(0).save.content_inventory.old_permanent == nil)
assert(not entitlements[0].vip, "business VIP must never grant combat entitlement")
assert(profiles.get_account_profile(0).save.gameplay_stats.initial_wood == 900)
assert(profiles.get_account_profile(0).save.content_inventory.old_permanent == 1)
local returned = profiles.get_account_profile(0)
returned.save.content_inventory.old_permanent = 0
assert(profiles.get_account_profile(0).save.content_inventory.old_permanent == 1, "business view is copied")
assert(profiles.apply_snapshot(0, snapshot(9)).error == "snapshot_revision_stale")
assert(profiles.get_progression(0).clear_counts.n6 == 1)

profiles.load_player(0, "star_blessing_grant")
assert(requests[2].url:match("/v1/profile$") and requests[2].body.match_session_id == session)
respond(2, update)
local provider = profiles.get_provider()
for _, item in ipairs({{"online_checkpoint", "/v1/online%-time/checkpoint$"},
    {"archive_submit", "/v1/archive/command$"}, {"lottery_snapshot", "/v1/lottery/snapshot$"}}) do
    provider[item[1]]({account_id="9000000123"}, function() end, function() end)
    assert(requests[#requests].body.match_session_id == session)
    assert(requests[#requests].url:match(item[2]))
end

session = "mode_fixture_session_2"
assert(profiles.get_profile(0) == nil and profiles.get_progression(0) == nil)
assert(not profiles.is_loaded_for_account(0, "9000000123"), "new session cannot reuse old authentication")
assert(profiles.apply_snapshot(0, update).error == "match_profile_mismatch")
profiles.load_player(0)
local index = #requests
assert(requests[index].url:match("/v1/session/login$"), "new match gets a new immutable baseline")
local next_snapshot = snapshot(10)
respond(index, next_snapshot)
assert(profiles.get_profile(0).save.gameplay_stats.initial_wood == 10)
assert(profiles.get_account_profile(0).save.content_inventory.old_permanent == nil)
mode = nil
local before = #requests
assert(profiles.load_player(0).error == "mode_not_selected")
assert(#requests == before and not profiles.is_loaded_for_account(0, "9000000123"))
print("PLAYER_PROFILE_MODES_PASS: mode-before-HTTP, pure defaults, real progression, separate account view, session isolation, all transports scoped")
