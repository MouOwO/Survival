-- Real entry authentication, match choice, HTTP profile and progression APIs.
package.path = "scripts/vscripts/?.lua;" .. package.path
local decoder, encoder = require("core/json_decoder"), require("core/json_encoder")
local tasks, requests, account = {}, {}, 9000000123
package.loaded["core/scheduler"] = {every=function(_,fn,key) tasks[key]=fn end}
package.loaded["core/logger"] = {info=function() end,warn=function() end}
package.loaded["systems/player_entitlement_service"] = {replace_all=function() end}
PlayerResource = {IsValidPlayerID=function(_,id) return id==0 end,IsFakeClient=function() return false end,
    GetPlayer=function() return {} end,GetTeam=function() return 2 end,GetConnectionState=function() return 2 end,
    GetSteamAccountID=function() return account end}
GameRules = {PlayerHasCustomGameHostPrivileges=function() return true end,
    GetGameModeEntity=function() return {} end,GetGameTime=function() return 100 end}
Convars = {RegisterConvar=function() end,
    GetStr=function(_,key) return key=="survival_fishing_api_token" and "test-only-token" or "" end}
CreateHTTPRequestScriptVM = function(_,url)
    local r={url=url};requests[#requests+1]=r
    function r:SetHTTPRequestHeaderValue() end
    function r:SetHTTPRequestAbsoluteTimeoutMS() end
    function r:SetHTTPRequestRawPostBody(_,body) self.body=decoder.decode(body) end
    function r:Send(fn) self.complete=fn end
    return r
end
local setup, profiles = require("systems/match_setup_service"), require("systems/player_profile_service")
local difficulty = require("config/difficulty_config")
local function option(mode)
    for _, row in ipairs(setup.snapshot().mode_options) do if row.mode_id==mode then return row end end
    error("missing mode option: "..mode)
end
setup.init("rich-profile-session-old-backend"); profiles.init()
assert(setup.select_mode(0,"rich",setup.get_session_id()).error=="mode_profile_pending")
assert(profiles.load_player(0).error=="mode_not_selected" and #requests==0)
local function response(value) requests[#requests].complete({StatusCode=200,Body=encoder.encode(value)}) end
local function auth(progress)
    assert(profiles.authenticate_player(0,"rich_test").pending)
    assert(requests[#requests].url:match("/v1/session/authenticate$") and requests[#requests].body.mode==nil)
    response({authenticated=true,account_id=tostring(account),match_session_id=setup.get_session_id(),progression=progress})
end
auth({loaded=true,clear_counts={n10=99}})
assert(not profiles.supports_rich_mode(0),"old backend cannot advertise rich through ordinary clears")
assert(option("rich").pending==1)
assert(option("rich").unlock_hint:find("服务尚未就绪",1,true))
assert(setup.select_mode(0,"rich",setup.get_session_id()).error=="mode_profile_pending")
assert(setup.select_mode(0,"standard",setup.get_session_id()).ok,"standard remains selectable on the old backend")
profiles.load_player(0)
assert(requests[#requests].body.mode=="standard")
response({schema_version=1,account_id=tostring(account),revision=1,mode="standard",
    match_session_id=setup.get_session_id(),progression={loaded=true,clear_counts={n10=99}},
    save={gameplay_stats={},archive={},content_inventory={}},entitlements={},achievements={},public={}})
assert(profiles.get_profile(0) and not profiles.supports_rich_mode(0),"old profile contract still loads normally")
setup.init("rich-profile-session-one")
auth({loaded=true,clear_counts={n10=1},standard_clear_counts={},rich_clear_counts={}})
assert(profiles.supports_rich_mode(0),"new authenticated backend explicitly advertises the independent rich map")
assert(profiles.get_profile(0)==nil,"entry admission never loads combat bonuses")
assert(setup.select_mode(0,"rich",setup.get_session_id()).error=="mode_not_unlocked")
-- A fresh session cannot reuse the previously authenticated account binding.
setup.init("rich-profile-session-two")
auth({loaded=true,clear_counts={n10=1},rich_clear_counts={}})
assert(require("config/mode_progression").entry_unlocked("rich",profiles.get_progression(0,"rich")),
    "historical standard fallback survives replacing the advanced clear permission view")
setup.init("rich-profile-session-two-confirmed")
auth({loaded=true,clear_counts={n10=1,n5=12},standard_clear_counts={n10=1},rich_clear_counts={}})
local auth_requests = #requests
assert(difficulty.is_unlocked("N6", profiles.get_progression(0, "standard")))
assert(difficulty.is_unlocked("N6", profiles.get_progression(0, "pure")))
assert(not difficulty.is_unlocked("N6", profiles.get_progression(0, "rich")))
assert(#requests == auth_requests and profiles.get_profile(0) == nil,
    "all difficulty previews use startup authentication before mode/login, without applying bonuses")
local external=profiles.get_authenticated_progression(0);external.standard_clear_counts.n10=0
assert(option("rich").unlocked==1,"returned permissions are copied")
account=9000000456
assert(not profiles.supports_rich_mode(0),"capability cannot transfer to a different account")
assert(option("rich").pending==1,"another account cannot reuse the host's unlock")
account=9000000123
assert(setup.select_mode(0,"rich",setup.get_session_id()).ok)
assert(not difficulty.is_unlocked("N6",profiles.get_progression(0)),"standard N5 does not unlock rich N6")
profiles.load_player(0)
assert(requests[#requests].url:match("/v1/session/login$") and requests[#requests].body.mode=="rich")
local snap={schema_version=1,account_id=tostring(account),revision=5,mode="standard",game_mode="rich",
    match_session_id=setup.get_session_id(),entitlements={},achievements={},public={},
    progression={loaded=true,clear_counts={n5=12,n10=1},standard_clear_counts={n10=1},rich_clear_counts={n5=1}},
    save={gameplay_stats={initial_wood=777},archive={},content_inventory={old_item=2}}}
response(snap)
assert(profiles.get_profile(0).save.gameplay_stats.initial_wood==777,"rich inherits standard combat bonuses")
assert(profiles.get_profile(0).save.content_inventory.old_item==2)
assert(difficulty.is_unlocked("N6",profiles.get_progression(0)))
assert(difficulty.is_unlocked("N7",profiles.get_progression(0)),"rich N5 opens the whole N6-N10 bracket")
assert(profiles.get_progression(0, "standard").clear_counts.n5 == 12
    and profiles.get_progression(0, "rich").clear_counts.n5 == 1,
    "explicit previews retain independent maps after the rich profile loads")
setup.init("rich-profile-session-three")
assert(not profiles.supports_rich_mode(0),"capability cannot transfer to a different match session")
auth({loaded=true,clear_counts={},standard_clear_counts={n10="1"},rich_clear_counts={}})
assert(profiles.get_authenticated_progression(0)==nil,"malformed trusted metadata is still rejected")
assert(setup.select_mode(0,"rich",setup.get_session_id()).error=="mode_profile_pending")
for index,mode in ipairs({"cold","scourge"}) do
    setup.init(mode.."-profile-session-one")
    auth({loaded=true,clear_counts={n5=12,n10=1},standard_clear_counts={n10=1},
        rich_clear_counts={n5=1,n10=1},cold_clear_counts={n5=1,n10=1},scourge_clear_counts={}})
    assert(profiles.supports_mode_progression(0,mode))
    assert(setup.select_mode(0,mode,setup.get_session_id()).ok)
    profiles.load_player(0)
    assert(requests[#requests].body.mode==mode,"durable HTTP login must retain the real advanced mode")
    local sample={schema_version=1,account_id=tostring(account),revision=10+index,mode="standard",game_mode="rich",
        match_session_id=setup.get_session_id(),entitlements={},achievements={},public={},
        progression={loaded=true,clear_counts={n5=12,n10=1},standard_clear_counts={n10=1},
            rich_clear_counts={n5=1,n10=1},cold_clear_counts={n5=1,n10=1},scourge_clear_counts={}},
        save={gameplay_stats={initial_wood=777},archive={},content_inventory={old_item=2}}}
    response(sample)
    assert(profiles.get_profile(0)==nil,"wrong game_mode cannot complete advanced login")
    profiles.load_player(0)
    sample.game_mode=mode
    response(sample)
    assert(profiles.get_profile(0).game_mode==mode and profiles.get_profile(0).save.gameplay_stats.initial_wood==777)
    assert(profiles.get_progression(0).mode_id==mode)
    local expected=mode=="cold" and 1 or nil
    assert(profiles.get_progression(0).clear_counts.n5==expected,"advanced permissions read only their own permanent counter")
    sample.game_mode="rich"
    assert(profiles.apply_snapshot(0,sample,"archive_fixture").error=="match_profile_mismatch",
        "archive receipt must retain game identity, not just standard combat projection")
    sample.game_mode=mode;sample.revision=sample.revision+1
    assert(profiles.apply_snapshot(0,sample,"archive_fixture").ok)
    account=9000000456
    assert(not profiles.supports_mode_progression(0,mode),"independent capability cannot transfer to another account")
    account=9000000123
    setup.init(mode.."-profile-session-two")
    assert(profiles.get_profile(0)==nil and not profiles.supports_mode_progression(0,mode),
        "advanced gameplay and capability are scoped to the authenticated match")
end
print("RICH_MODE_PROFILES_PASS: authenticated chain, independent counters, durable advanced identity and scoped receipts")
