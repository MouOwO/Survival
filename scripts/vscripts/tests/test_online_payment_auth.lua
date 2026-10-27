-- Integration through the actual release policy, access gate, PWA resolver,
-- HTTP profile provider and payment service. Only engine IO/profile storage
-- boundaries are fixtures; no cash policy or web_auth.resolve is replaced.
package.path="scripts/vscripts/?.lua;"..package.path
-- The signed production inventory excludes this optional debug module. Leave
-- real require/module loading intact, but reject its missing production path:
-- a generic debug stub would conceal a payment.init startup regression.
local missing_offline_loads=0
assert(package.loaded["debug/offline_logic_test"]==nil)
table.insert(package.loaders,1,function(name)
    if name=="debug/offline_logic_test" then
        missing_offline_loads=missing_offline_loads+1
        error("production inventory has no debug/offline_logic_test")
    end
end)
local json=require("core/json_encoder")
local decode=require("core/json_decoder").decode
local release_config=require("config/release_profile")
release_config.channel="production"
local cash_config=require("config/commerce_payment_access")
local web_config=require("config/player_web_auth")
local session,clock,map,tools="online_payment_auth_match_01",100,"template_map",false
local players,requests,sent,listeners,engine,timers={},{},{},{},{},{}
local loaded,authenticated={},{}
local refresh_calls,held_refresh=0,nil
local fail_factory=false
local function entity(id)
    local p={id=id}
    function p:GetPlayerID()return self.id end
    function p:IsNull()return false end
    return p
end
players[0]={entity=entity(0),account=885195478,connected=2,team=2}
players[1]={entity=entity(1),account=463897428,connected=2,team=2}
IsServer=function()return true end
IsInToolsMode=function()return tools end
GetMapName=function()return map end
Time=function()return clock end
DisconnectClient=function()error("approved fixture player must never be kicked")end
PlayerResource={
    IsValidPlayerID=function(_,id)return players[id]~=nil end,
    IsFakeClient=function()return false end,
    GetPlayer=function(_,id)return players[id] and players[id].entity end,
    GetSteamAccountID=function(_,id)return players[id] and players[id].account end,
    GetConnectionState=function(_,id)return players[id] and players[id].connected end,
    GetTeam=function(_,id)return players[id] and players[id].team end,
}
EntIndexToHScript=function(index)return players[index-200] and players[index-200].entity end
ListenToGameEvent=function(name,callback)engine[name]=callback end
Convars={GetStr=function(_,name)
    assert(name~="survival_fishing_api_token","production must not read a global game/payment bearer")
    return ""
end}
CustomNetTables={SetTableValue=function()error("private capability must not be broadcast")end}
CustomGameEventManager={
    RegisterListener=function(_,name,callback)listeners[name]=callback;return name end,
    UnregisterListener=function(_,name)listeners[name]=nil end,
    Send_ServerToAllClients=function()error("cash data must never broadcast")end,
    Send_ServerToPlayer=function(_,p,name,body)
        local raw=json.encode(body)
        assert(not raw:find("pwa1_",1,true) and not raw:find("device_fixture",1,true),"private server credential leaked")
        sent[#sent+1]={player=p,name=name,body=body}
    end,
}
CreateHTTPRequestScriptVM=function(method,url)
    if fail_factory then return nil end
    local r={method=method,url=url,headers={}}
    function r:SetHTTPRequestHeaderValue(k,v)self.headers[k]=v end
    function r:SetHTTPRequestRawPostBody(_,raw)self.body=decode(raw) end
    function r:SetHTTPRequestAbsoluteTimeoutMS(value)self.timeout=value end
    function r:Send(callback)self.complete=callback end
    requests[#requests+1]=r
    return r
end
package.loaded["systems/match_setup_service"]={get_session_id=function()return session end,
    get_mode=function()return "standard" end,get_profile_mode=function()return "standard" end,
    is_mode_selected=function()return true end}
package.loaded["systems/startup_loading_service"]={is_ready=function()return false end}
package.loaded["core/scheduler"]={after=function(_,callback,key)timers[key]=callback end,
    cancel=function(key)timers[key]=nil end}
package.loaded["systems/commerce_service"]={init=function()end}
package.loaded["systems/archive_service"]={set_purchase_provider=function()end}
package.loaded["debug/payment_test_commands"]={init=function()end}
package.loaded["systems/gameplay_phase_guard"]={post_clear_frozen=function()return false end}
local provider=require("systems/player_profile_providers/http_fishing_provider")
provider.init()
local active_provider=provider
local profiles={
    get_provider=function()return active_provider end,
    get_profile=function(id)return loaded[id] and {save={gameplay_stats={initial_wood=180}}} or nil end,
    is_authenticated_for_account=function(id,account)
        return authenticated[id]==account and tostring(players[id].account)==account
    end,
    refresh_player=function(id,reason,done,failed)
        refresh_calls=refresh_calls+1
        held_refresh={id=id,reason=reason,done=done,failed=failed}
        return {ok=true}
    end,
}
package.loaded["systems/player_profile_service"]=profiles
local policy=require("core/commerce_release_policy")
local web=require("systems/player_web_auth")
local payment=require("systems/payment_service")
web.init(session)
payment.init()
assert(missing_offline_loads==0 and package.loaded["debug/offline_logic_test"]==nil,
    "production payment startup must succeed without loading the absent offline arena")
assert(cash_config.enabled==false and not policy.real_money_allowed(),"default remains closed")
cash_config.enabled=true
assert(not policy.online_allowed(),"trusted web authentication is required")
web_config.enabled=true
assert(policy.online_allowed() and not require("core/release_policy").development_allowed(),"cash cannot enable debug commands")
tools=true;assert(not policy.online_allowed(),"Tools cannot enable the ordinary production checkout")
cash_config.connection_helper=true
assert(policy.online_allowed() and not require("core/release_policy").development_allowed(),
    "only the signed connection-helper opt-in permits production Tools; debug remains closed")
cash_config.connection_helper=false;tools=false
map="ws4_lobby";assert(not policy.online_allowed());map="template_map"
local good_base=cash_config.base_url
cash_config.base_url="https://evil.invalid";assert(not policy.online_allowed());cash_config.base_url=good_base
local access_config=require("config/test_access")
local saved_ids=access_config.allowed_steamids
access_config.allowed_steamids={saved_ids[1],saved_ids[2],saved_ids[3]}
assert(not policy.online_allowed(),"an invalid roster cannot open cash")
access_config.allowed_steamids=saved_ids
assert(policy.online_allowed())

local function capability(id,key,spoof)
    listeners.survival_payment_capability_request(200+id,{request_id=key,PlayerID=spoof or id,
        account_id="attacker",match_session_id="attacker"})
    return sent[#sent] and sent[#sent].body
end
local function dispatch(id,body)
    clock=clock+2
    listeners.survival_payment_request(200+id,body)
end
local function complete(index,body,status)
    requests[index].complete({StatusCode=status or 200,Body=json.encode(body)})
end
local tokens={"pwa1_"..string.rep("a",64),"pwa1_"..string.rep("b",64)}
local function authenticate(id)
    local account=tostring(players[id].account)
    local function accepted(result)
        assert(result.authenticated and result.account_id==account)
        authenticated[id]=account
    end
    local before=#requests
    provider.authenticate(account,accepted,function(error)assert(error=="player_web_auth_pending",error)end)
    assert(#requests==before+1 and requests[#requests].url==web_config.base_url.."/v1/player-auth/start")
    assert(requests[#requests].headers.Authorization==nil)
    local code=id==0 and "ABCD2345" or "EFGH2345"
    complete(#requests,{ok=true,status="pending",device_code="device_fixture_abcdefghijklmnopqrstuvwxyz_"..id,
        user_code=code,verification_uri=web_config.base_url.."/authorize?code="..code,expires_in=600,poll_interval=3})
    clock=clock+3
    provider.authenticate(account,accepted,function(error)assert(error=="player_web_auth_pending",error)end)
    assert(requests[#requests].url==web_config.base_url.."/v1/player-auth/poll")
    complete(#requests,{ok=true,status="approved",account_id=account,match_session_id=session,
        access_token=tokens[id+1],expires_in=14400})
    assert(requests[#requests].url==web_config.base_url.."/v1/session/authenticate")
    assert(requests[#requests].headers.Authorization=="Bearer "..tokens[id+1])
    complete(#requests,{authenticated=true,account_id=account,match_session_id=session})
end
tools=true
listeners.survival_payment_capability_request(200,{request_id="client_helper_spoof",connection_helper=true,
    enabled=true,PlayerID=1})
assert(sent[#sent].body.enabled==false and not policy.online_allowed(),"client helper flags cannot enable production Tools")
cash_config.connection_helper=true
local c=capability(0,"before_auth",1)
assert(c.enabled==false and c.account_id==tostring(players[0].account) and c.player_id==0 and #requests==0)
local emitted=#sent
listeners.survival_payment_request(999,{PlayerID=0,action="create",sku="monthly_pass"})
listeners.survival_payment_capability_request(999,{PlayerID=0,request_id="forged"})
assert(#requests==0 and #sent==emitted,"invalid entities cannot request another player's cash state")
authenticate(0)
c=capability(0,"profile_missing",1)
assert(c.enabled==false,"entry authentication alone cannot prove loaded cloud entitlements")
loaded[0]=true
c=capability(0,"ready_0",1)
assert(c.enabled==true and c.request_id=="ready_0" and c.player_id==0 and c.match_session_id==session)
active_provider={resolve_account_id=provider.resolve_account_id}
c=capability(0,"memory_provider")
assert(c.enabled==false,"an injected/memory provider cannot obtain cash capability")
active_provider=provider
c=capability(0,"restored_provider");assert(c.enabled==true)

dispatch(0,{PlayerID=1,action="create",sku="monthly_pass",quantity=1,provider="alipay",
    account_id=tostring(players[1].account),match_session_id="forged_match",amount_fen=1})
local order_request=#requests
local r=requests[order_request]
assert(r.method=="POST" and r.url==web_config.base_url.."/v1/payments/create")
assert(r.headers.Authorization=="Bearer "..tokens[1] and r.timeout==30000)
assert(r.body.account_id==tostring(players[0].account) and r.body.match_session_id==session
    and r.body.amount_fen==nil and r.body.PlayerID==nil and r.body.quantity==1 and r.body.provider=="alipay")
local order_id="AL"..string.rep("1",30)
complete(order_request,{ok=true,sku="monthly_pass",order_id=order_id,state="pending",amount_fen=5800})
assert(sent[#sent].player==players[0].entity and sent[#sent].body.amount_fen==5800)
tools=false;cash_config.connection_helper=false
assert(policy.online_allowed(),"the ordinary native path remains independent of the helper opt-in")
local before=#requests
dispatch(1,{PlayerID=0,action="status",sku="monthly_pass",order_id=order_id})
assert(#requests==before,"the unapproved player cannot query this order")
authenticate(1);loaded[1]=true
dispatch(1,{PlayerID=0,action="status",sku="monthly_pass",order_id=order_id})
assert(#requests==before+3 and sent[#sent].body.error=="order_not_in_session")
dispatch(0,{PlayerID=1,action="status",sku="monthly_pass",order_id="forged"})
assert(requests[#requests].url==web_config.base_url.."/v1/payments/status" and requests[#requests].body.order_id==order_id)
before=#sent
complete(#requests,{ok=true,sku="monthly_pass",order_id=order_id,state="delivered"})
assert(refresh_calls==1 and #sent==before,"receipt must wait for authoritative refresh")
held_refresh.failed()
assert(sent[#sent].body.error=="reward_refresh_pending" and sent[#sent].body.state=="delivered")
dispatch(0,{action="status",sku="monthly_pass"})
complete(#requests,{ok=true,sku="monthly_pass",order_id=order_id,state="delivered"})
assert(refresh_calls==2)
held_refresh.done()
assert(sent[#sent].body.ok==true and sent[#sent].body.state=="delivered")
dispatch(0,{action="status",sku="monthly_pass"})
complete(#requests,{ok=true,sku="monthly_pass",order_id=order_id,state="delivered"})
assert(refresh_calls==2,"the same confirmed order must not refresh twice")
dispatch(0,{action="cancel",sku="monthly_pass",order_id="forged"})
assert(requests[#requests].url==web_config.base_url.."/v1/payments/cancel" and requests[#requests].body.order_id==order_id)
complete(#requests,{ok=true,sku="monthly_pass",order_id=order_id,state="delivered"})
local resets_before=#requests
assert(not payment.reset_player({player_id=0,args={}},"refreshmoney"))
dispatch(0,{action="reset",kind="refreshdata"})
assert(#requests==resets_before,"production cannot expose reset routes")
dispatch(0,{action="create",sku="refresh_connection"})
complete(#requests,{ok=true,sku="refresh_connection",order_id="AL"..string.rep("4",30),state="delivered"})
local stale_refresh=held_refresh
engine.player_disconnect({PlayerID=0})
engine.player_connect_full({PlayerID=0})
before=#sent
stale_refresh.done()
assert(#sent==before,"a delayed profile refresh cannot acknowledge cash after slot generation changes")

dispatch(0,{action="catalog",request_id="cached"})
complete(#requests,{ok=true,products={},catalog_hash="one"})
local cached_count=#requests
listeners.survival_payment_request(200,{action="catalog",request_id="cached_again"})
assert(#requests==cached_count and sent[#sent].body.request_id=="cached_again")
clock=clock+3
dispatch(0,{action="catalog",request_id="stale_connection"})
local stale=#requests
engine.player_disconnect({PlayerID=0})
engine.player_connect_full({PlayerID=0}) -- Same entity/account/session: generation still changes.
dispatch(0,{action="catalog",request_id="fresh_connection"})
assert(#requests==stale+1,"a reconnect cannot inherit the previous slot cache or pending job")
before=#sent
complete(stale,{ok=true,products={},catalog_hash="old"})
assert(#sent==before,"the old same-slot callback cannot reply after reconnect")
complete(#requests,{ok=true,products={},catalog_hash="fresh"})
assert(sent[#sent].body.request_id=="fresh_connection")
dispatch(0,{action="status",sku="monthly_pass"})
assert(sent[#sent].body.error=="order_not_in_session","old slot order capabilities must be forgotten")

dispatch(0,{action="create",sku="revoked_order"})
local revoked=#requests
cash_config.enabled=false
c=capability(0,"disabled_again");assert(c.enabled==false)
before=refresh_calls
complete(revoked,{ok=true,sku="revoked_order",order_id="AL"..string.rep("2",30),state="delivered",
    checkout_url="https://must-not-publish.invalid"})
assert(refresh_calls==before and sent[#sent].body.error=="real_money_disabled" and sent[#sent].body.checkout_url==nil)
cash_config.enabled=true
fail_factory=true
dispatch(0,{action="create",sku="factory_failure"})
assert(sent[#sent].body.error=="payment_unavailable")
fail_factory=false

dispatch(0,{action="create",sku="old_slot_pending"})
local old_slot=#requests
players[0].entity=entity(0)
players[0].account=players[1].account
authenticated[0]=tostring(players[0].account)
before=#sent
complete(old_slot,{ok=true,sku="old_slot_pending",order_id="AL"..string.rep("3",30),state="pending"})
assert(#sent==before,"a changed entity/account cannot receive the previous player's order")
session="online_payment_auth_match_02"
web.init(session)
local duplicate_before=#requests
dispatch(0,{action="catalog",request_id="new_match"})
assert(#requests==duplicate_before,"one Steam account occupying two live slots must not start authorization")
players[1].connected=3
dispatch(0,{action="catalog",request_id="new_match_single_slot"})
assert(requests[#requests].url==web_config.base_url.."/v1/player-auth/start"
    and requests[#requests].body.match_session_id==session,"a new match cannot reuse an old PWA token")
before=#sent
players[0].entity=entity(0)
complete(#requests,{ok=true,status="pending",device_code="device_fixture_abcdefghijklmnopqrstuvwxyz_new",
    user_code="JKLM2345",verification_uri=web_config.base_url.."/authorize?code=JKLM2345",expires_in=600,poll_interval=3})
assert(#sent==before,"stale PWA completion must not address a replacement player entity")
authenticate(0)
c=capability(0,"rejected_grant");assert(c.enabled==true)
dispatch(0,{action="create",sku="expired_grant_order"})
local rejected=#requests
complete(rejected,{ok=false,error="player_session_expired"},403)
assert(requests[#requests].url==web_config.base_url.."/v1/player-auth/start",
    "backend rejection must invalidate the local PWA grant")
local capability_after_rejection
for i=#sent,1,-1 do
    if sent[i].name=="survival_payment_capability" then capability_after_rejection=sent[i].body;break end
end
assert(capability_after_rejection.enabled==false and capability_after_rejection.request_id=="rejected_grant",
    "an asynchronous replacement authorization cannot retain an enabled cash capability")
cash_config.enabled=false
assert(not policy.real_money_allowed())
assert(missing_offline_loads==0 and package.loaded["debug/offline_logic_test"]==nil,
    "production cash requests and revocation cannot load optional debug modules")
print("ONLINE_PAYMENT_AUTH_PASS: real policy/access/PWA/profile/payment code paths, signed helper opt-in without debug, private capability, engine-source identity, fixed player bearer URLs, quote isolation, refresh gate, reconnect generation, revocation and no reset")
