package.path="scripts/vscripts/?.lua;"..package.path
local profile={channel="production"}
package.loaded["config/release_profile"]=profile
local sent,http,refreshes,pass_provider={},0,0,"unset"
local profile_done
local account={save={gameplay_stats={}}}
package.loaded["systems/player_profile_service"]={get_profile=function()return account end,
    get_provider=function()return {resolve_account_id=function()return "fixture_account" end} end,
    refresh_player=function(_,_,done)refreshes=refreshes+1;profile_done=done;return {ok=true} end}
package.loaded["systems/match_setup_service"]={get_session_id=function()return "fixture_session" end}
package.loaded["systems/commerce_service"]={init=function()end}
package.loaded["systems/archive_service"]={set_purchase_provider=function(value)pass_provider=value end}
package.loaded["systems/gameplay_phase_guard"]={post_clear_frozen=function()return false end}
package.loaded["core/scheduler"]={after=function()end,cancel=function()end}
package.loaded["debug/payment_test_commands"]={init=function()end}
PlayerResource={IsValidPlayerID=function(_,id)return id==0 end,IsFakeClient=function()return false end,
    GetPlayer=function()return {} end}
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
assert(pass_provider==nil,"production cannot register the cash monthly-pass provider")
for _,channel in ipairs({"production","test","Development","",false}) do
    profile.channel=channel
    for _,tools in ipairs({true,false}) do
        IsInToolsMode=function()return tools end
        for _,action in ipairs({"catalog","create","status","cancel"}) do
            payment.handle({PlayerID=0,action=action,sku="u_coin_recharge",provider="wechat",quantity=1,
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
    payment.handle({PlayerID=0,action="create",sku="u_coin_recharge",quantity=1})
    assert(http==0 and sent[#sent].result.error=="real_money_disabled")
end
IsInToolsMode=function()return true end
payment.handle({PlayerID=0,action="create",sku="u_coin_recharge",quantity=1})
assert(http==1,"explicit development + server Tools may still exercise its payment transport")
profile.channel="production"
callback({StatusCode=200,Body='{"ok":true,"sku":"u_coin_recharge","order_id":"fixture_order","state":"delivered"}'})
assert(refreshes==0 and sent[#sent].result.error=="real_money_disabled",
    "a late developer response cannot grant or refresh after the release gate closes")
profile.channel="development"
payment.handle({PlayerID=0,action="create",sku="second_fixture",quantity=1})
callback({StatusCode=200,Body='{"ok":true,"sku":"second_fixture","order_id":"second_order","state":"delivered","checkout_url":"https://fixture.invalid"}'})
assert(refreshes==1 and type(profile_done)=="function")
profile.channel="production"
profile_done()
local final=sent[#sent].result
assert(final.error=="real_money_disabled" and final.checkout_url==nil and final.order_id==nil,
    "revoking cash during profile refresh cannot publish a cash receipt or checkout URL")
print("NONCOMMERCIAL_PAYMENT_RELEASE_PASS: closed production catalogue/orders/pass, spoofed flags ignored, no HTTP, developer-only transport, late response denied")
