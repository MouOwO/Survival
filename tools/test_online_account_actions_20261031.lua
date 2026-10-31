-- Real release configuration, isolation latch, HTTP provider and cash policy.
-- Synthetic native/identity boundaries only: zero real network or account writes.
local source_root=arg and arg[1] or "scripts/vscripts"
package.path=source_root.."/?.lua;scripts/vscripts/?.lua;"..package.path
local base="https://pay.xiaofengnet.com/ws4-web"
local session="online_account_action_fixture"
package.loaded["core/release_policy"]={development_allowed=function()return false end,is_production=function()return true end}
package.loaded["systems/match_setup_service"]={get_session_id=function()return session end,
    is_mode_selected=function()return true end,get_mode=function()return "standard" end}
package.loaded["systems/player_web_auth"]={enabled=function()return true end,
    resolve=function(account,match,success)assert(account=="123" and match==session);success(base,"FICTIONAL_TEST_TOKEN")end}
package.loaded["config/player_web_auth"]={enabled=true,base_url=base}
package.loaded["config/commerce_payment_access"]={enabled=true,base_url=base,expected_map="template_map",connection_helper=false}
package.loaded["config/test_access"]={enabled=true,allowed_steamids={
    "76561197960265729","76561197960265730","76561197960265731","76561197960265732"}}
package.loaded["core/test_access_policy"]={enabled=function()return true end,init=function()return true end}
IsServer=function()return true end;IsInToolsMode=function()return false end;GetMapName=function()return "template_map" end
Convars={GetStr=function(_,key)return key=="survival_archive_http_enabled" and "1" or "" end}
local release=require("config/mode_release_config")
local shipped_acceptance=release.all_difficulties_unlocked
local isolation=require("debug/mode_unlock_test")
local provider=require("systems/player_profile_providers/http_fishing_provider")
local cash=require("core/commerce_release_policy")
local requests={}
CreateHTTPRequestScriptVM=function(method,url)
    assert(method=="POST" and url==base.."/v1/archive/command")
    local request={}
    function request:SetHTTPRequestHeaderValue(name,value)assert(name=="Authorization" and value=="Bearer FICTIONAL_TEST_TOKEN")end
    function request:SetHTTPRequestRawPostBody(_,raw)self.body=require("core/json_decoder").decode(raw)end
    function request:SetHTTPRequestAbsoluteTimeoutMS(ms)assert(ms==30000)end
    function request:Send()requests[#requests+1]=self end
    return request
end
provider.init()
local function exercise(expect_writable)
    isolation.reset(session)
    assert(isolation.is_enabled()==not expect_writable)
    assert(cash.real_money_allowed()==expect_writable)
    local before=#requests
    for _,kind in ipairs({"commerce_catalog","daily_claim","benefit_claim"}) do
        local failure
        provider.archive_submit({account_id="123",command={id="fixture_"..kind,kind=kind}},
            function()error("fixture native transport has no response")end,function(code)failure=code end)
        if expect_writable then assert(failure==nil)
        else assert(failure=="mode_unlock_test_read_only") end
    end
    assert(#requests-before==(expect_writable and 3 or 0))
end
release.all_difficulties_unlocked=true;exercise(false)
release.all_difficulties_unlocked=false;exercise(true)
assert(#requests==3)
for _,request in ipairs(requests)do assert(request.body.match_session_id==session and request.body.account_id=="123")end
print("ONLINE_ACCOUNT_TRANSPORT_CHAIN_PASS: acceptance=0 HTTP, normal=3 HTTP, real_network_calls=0")
assert(shipped_acceptance==false,"SHIPPED_READ_ONLY_ACCEPTANCE_CAUSES_EMPTY_SHOP_AND_BLOCKED_BENEFITS")
-- The acceptance latch cannot be cleared in the middle of an existing test match.
release.all_difficulties_unlocked=true;isolation.reset(session)
release.all_difficulties_unlocked=false;assert(isolation.is_enabled())
session="new_normal_account_action_fixture";isolation.reset(session);assert(not isolation.is_enabled())
-- Existing guarded offline preview must remain isolated even with the shipping flag off.
package.loaded["debug/offline_logic_test"]={is_enabled=function()return true end}
session="offline_account_action_fixture";isolation.reset(session)
assert(isolation.is_enabled() and not cash.real_money_allowed())
print("ONLINE_ACCOUNT_ACTIONS_CHAIN_PASS: acceptance=0 HTTP, normal=3 HTTP, same-match latch preserved, offline isolated; real_network_calls=0")
