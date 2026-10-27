package.path="scripts/vscripts/?.lua;"..package.path
local profile={channel="production"}
package.loaded["config/release_profile"]=profile
local sent,http,refreshes,pass_provider={},0,0,"unset"
local profile_done
local account={save={gameplay_stats={}}}
local provider={resolve_account_id=function()return "fixture_account" end}
package.loaded["systems/player_profile_service"]={get_profile=function()return account end,
    get_provider=function()return provider end,
    refresh_player=function(_,_,done)refreshes=refreshes+1;profile_done=done;return {ok=true} end}
package.loaded["systems/match_setup_service"]={get_session_id=function()return "fixture_session" end}
package.loaded["systems/commerce_service"]={init=function()end}
package.loaded["systems/archive_service"]={set_purchase_provider=function(value)pass_provider=value end}
package.loaded["systems/gameplay_phase_guard"]={post_clear_frozen=function()return false end}
package.loaded["core/scheduler"]={after=function()end,cancel=function()end}
package.loaded["debug/payment_test_commands"]={init=function()end}
local player={GetPlayerID=function()return 0 end,IsNull=function()return false end}
EntIndexToHScript=function(index)return index==200 and player or nil end
PlayerResource={IsValidPlayerID=function(_,id)return id==0 end,IsFakeClient=function()return false end,
    GetPlayer=function()return player end}
CustomGameEventManager={RegisterListener=function()end,Send_ServerToPlayer=function(_,_,name,result)
    sent[#sent+1]={name=name,result=result}
end}
Convars={GetStr=function()return "fixture_token" end}
local clock=100
Time=function()clock=clock+2;return clock end
local callback
CreateHTTPRequestScriptVM=function()
    http=http+1
    return {SetHTTPRequestHeaderValue=function()end,SetHTTPRequestRawPostBody=function()end,
        Send=function(_,done)callback=done end}
end
IsServer=function()return true end
IsInToolsMode=function()return true end
local payment=require("systems/payment_service")
payment.init()
local function handle(payload)return payment.handle(200,payload)end
assert(pass_provider==nil,"production cannot register the cash monthly-pass provider")
for _,channel in ipairs({"production","test","Development","",false}) do
    profile.channel=channel
    for _,tools in ipairs({true,false}) do
        IsInToolsMode=function()return tools end
        for _,action in ipairs({"catalog","create","status","cancel"}) do
            handle({PlayerID=0,action=action,sku="u_coin_recharge",provider="wechat",quantity=1,
                request_id="fixture_request",real_money_enabled=true,channel="development"})
            local result=sent[#sent].result
            if action=="catalog" then
                assert(result.ok and result.real_money_enabled==false and #result.products==0)
                assert(result.wechat==false and result.alipay==false)
            else assert(result.ok==false and result.error=="real_money_disabled") end
            assert(http==0,"closed release must never contact a cash backend")
        end
        local completed
        assert(payment.open_pass_checkout(0,{sku="archive_pass_monthly"},function(result)completed=result end)==false)
        assert(completed and completed.ok==false)
    end
end
profile.channel="development"
for _,engine in ipairs({"missing","false","throws"}) do
    IsInToolsMode=engine=="missing" and nil or engine=="false" and function()return false end or function()error("engine unavailable")end
    handle({PlayerID=0,action="create",sku="u_coin_recharge",quantity=1})
    assert(http==0 and sent[#sent].result.error=="real_money_disabled")
end
IsInToolsMode=function()return true end
-- Acceptance isolation applies even to a developer Tools build. Use the real
-- match-local latch: changing its configuration cannot reopen cash mid-match.
local acceptance_config=require("config/mode_release_config")
local original_acceptance=acceptance_config.all_difficulties_unlocked
local acceptance=require("debug/mode_unlock_test")
acceptance_config.all_difficulties_unlocked=true
acceptance.reset("fixture_session")
assert(acceptance.is_enabled())
local function assert_acceptance_cash_closed()
    local before_http=http
    for _,action in ipairs({"catalog","create","status","cancel"}) do
        handle({PlayerID=0,action=action,sku="u_coin_recharge",quantity=1})
        local result=sent[#sent].result
        if action=="catalog" then
            assert(result.ok and result.real_money_enabled==false and #result.products==0)
        else assert(result.ok==false and result.error=="real_money_disabled") end
    end
    for _,kind in ipairs({"refreshdata","refreshmoney"}) do
        local ok,reason=payment.reset_player({player_id=0,args={}},kind)
        assert(ok==false and reason=="real_money_disabled",
            "read-only acceptance must not reset a real account")
    end
    local completed
    assert(payment.open_pass_checkout(0,{sku="archive_pass_monthly"},function(result)completed=result end)==false)
    assert(completed and completed.ok==false and http==before_http,
        "acceptance catalogues/orders/pass/resets must not contact a cash backend")
end
assert_acceptance_cash_closed()
acceptance_config.all_difficulties_unlocked=false
assert(acceptance.is_enabled(),"disabling the flag cannot end this match's write isolation")
assert_acceptance_cash_closed()
acceptance.reset("fixture_session")
assert(not acceptance.is_enabled(),"a new normal match restores the normal cash policy")
handle({PlayerID=0,action="create",sku="u_coin_recharge",quantity=1})
assert(http==1,"explicit development + server Tools may still exercise its payment transport")
profile.channel="production"
callback({StatusCode=200,Body='{"ok":true,"sku":"u_coin_recharge","order_id":"fixture_order","state":"delivered"}'})
assert(refreshes==0 and sent[#sent].result.error=="real_money_disabled",
    "a late developer response cannot grant or refresh after the release gate closes")
profile.channel="development"
handle({PlayerID=0,action="create",sku="second_fixture",quantity=1})
callback({StatusCode=200,Body='{"ok":true,"sku":"second_fixture","order_id":"second_order","state":"delivered","checkout_url":"https://fixture.invalid"}'})
assert(refreshes==1 and type(profile_done)=="function")
profile.channel="production"
profile_done()
local final=sent[#sent].result
assert(final.error=="real_money_disabled" and final.checkout_url==nil and final.order_id==nil,
    "revoking cash during profile refresh cannot publish a cash receipt or checkout URL")
acceptance_config.all_difficulties_unlocked=original_acceptance
print("NONCOMMERCIAL_PAYMENT_RELEASE_PASS: closed production catalogue/orders/pass, acceptance cash/reset isolation and match latch, spoofed flags ignored, developer-only transport restored, late response denied")
