package.path='scripts/vscripts/?.lua;'..package.path
local handlers,sent,requests={},{},{}
local loaded=true
local refreshed=0
local profile={save={content_inventory={},gameplay_stats={initial_wood=180}}}
local provider={resolve_account_id=function(id)return id==0 and '123' or '456' end}
package.loaded['systems/player_profile_service']={get_provider=function()return provider end,
 get_profile=function()return loaded and profile or nil end,
 load_player=function(id,reason,done)refreshed=refreshed+1;done();return {ok=true} end}
package.loaded['systems/match_setup_service']={get_session_id=function()return 'safe_session' end}
PlayerResource={IsValidPlayerID=function(_,id)return id==0 or id==1 end,IsFakeClient=function()return false end,
 GetPlayer=function(_,id)return {id=id} end}
CustomGameEventManager={RegisterListener=function(_,name,f)handlers[name]=f end,
 Send_ServerToPlayer=function(_,player,name,body)sent[#sent+1]=body end}
Convars={GetStr=function()return 'server_only_test_token' end}
local clock=0
IsInToolsMode=function()return true end
ListenToGameEvent=function(name,callback)handlers[name]=callback end
Time=function()clock=clock+2;return clock end
CreateHTTPRequestScriptVM=function(method,url)
 local r={method=method,url=url};requests[#requests+1]=r
 function r:SetHTTPRequestHeaderValue(name,value)r.header=value end
 function r:SetHTTPRequestRawPostBody(kind,body)r.body=body end
 function r:Send(done)r.done=done end
 return r
end
local service=require('systems/payment_service');service.init();service.init()
local handle=handlers.survival_payment_request
handle(0,{PlayerID=0,action='create',sku='wood_100_test_50_v3',account_id='attacker',amount=1})
local body=require('core/json_decoder').decode(requests[1].body)
assert(body.account_id=='123' and body.amount==nil and body.match_session_id=='safe_session')
handle(0,{PlayerID=0,action='create',sku='wood_100_test_50_v3'});assert(#requests==1,'in-flight duplicate blocked')
requests[1].done({StatusCode=200,Body='{"ok":true,"sku":"wood_100_test_50_v3","order_id":"WX111111111111111111111111111111","state":"pending"}'})
handle(0,{PlayerID=0,action='status',sku='wood_100_test_50_v3',order_id='other_player_order'})
body=require('core/json_decoder').decode(requests[2].body)
assert(body.order_id=='WX111111111111111111111111111111')
requests[2].done({StatusCode=200,Body='{"ok":true,"sku":"wood_100_test_50_v3","order_id":"WX111111111111111111111111111111","state":"delivered"}'})
assert(refreshed==1)
assert(sent[#sent].game_values.initial_wood==180,"UI must receive the refreshed match stat")
handle(0,{PlayerID=0,action='status',sku='wood_100_test_50_v3'})
requests[3].done({StatusCode=200,Body='{"ok":true,"sku":"wood_100_test_50_v3","order_id":"WX111111111111111111111111111111","state":"delivered"}'})
assert(refreshed==1,'duplicate success must not grant or repeatedly reload')
loaded=false;handle(0,{PlayerID=0,action='create',sku='wood_100_test_50_v3'});assert(#requests==3)
loaded=true
IsInToolsMode=function()return false end
local ok=service.reset_player({player_id=0,args={}},'refreshdata')
assert(not ok and #requests==3,'production client must not invoke remote resets')
handle(0,{PlayerID=0,action='reset',kind='refreshdata'})
assert(#requests==3,'client UI event cannot invoke the chat-only reset')
IsInToolsMode=function()return true end
RandomInt=function()return 123456 end
handlers.player_chat({playerid=0,text='refreshmoney'})
assert(#requests==4,'the engine chat input must dispatch the reset')
local reset=require('core/json_decoder').decode(requests[4].body)
assert(reset.account_id=='123' and reset.kind=='refreshmoney' and reset.request_id)
requests[4].done({StatusCode=503,Body='{"ok":false,"error":"payment_unavailable"}'})
assert(service.reset_player({player_id=0,args={}},'refreshmoney'))
assert(require('core/json_decoder').decode(requests[5].body).request_id==reset.request_id,
 'uncertain reset retries must use the same operation identity')
requests[5].done({StatusCode=200,Body='{"ok":true,"kind":"refreshmoney","revision":99}'})
assert(refreshed==2,'remote reset must load the authoritative profile')
handle(0,{PlayerID=0,action='status',sku='wood_100_test_50_v3'})
assert(#requests==5,'reset must forget old paid checkout references')
assert(service.reset_player({player_id=0,args={}},'refreshdata'))
assert(require('core/json_decoder').decode(requests[6].body).request_id~=reset.request_id)
requests[6].done({StatusCode=200,Body='{"ok":true,"kind":"refreshdata","revision":100}'})
assert(refreshed==3)
profile.entitlements={vip={active=true},archive_pass={active=true}}
profile.save.gameplay_stats.hero_attack_bonus_pct=12
handle(0,{PlayerID=0,action='create',sku='csv_bundle_new',amount=1,account_id='attacker'})
assert(#requests==7,'CSV products must not need a Lua SKU allowlist change')
body=require('core/json_decoder').decode(requests[7].body)
assert(body.sku=='csv_bundle_new' and body.account_id=='123' and body.amount==nil)
requests[7].done({StatusCode=200,Body='{"ok":true,"sku":"csv_bundle_new","order_id":"WX222222222222222222222222222222","state":"delivered","effects":{"hero_attack_bonus_pct":12}}'})
assert(sent[#sent].game_values.hero_attack_bonus_pct==12)
assert(sent[#sent].game_entitlements.vip.active and sent[#sent].game_entitlements.archive_pass.active)
handle(0,{PlayerID=0,action='create',sku='../invalid'})
assert(#requests==7,'invalid SKU syntax must be rejected before HTTP')
handle(0,{PlayerID=0,action='create',sku='ticket_test',provider='alipay',seller_id='attacker',amount=1})
body=require('core/json_decoder').decode(requests[8].body)
assert(body.provider=='alipay' and body.seller_id==nil and body.amount==nil and body.account_id=='123')
requests[8].done({StatusCode=200,Body='{"ok":true,"sku":"ticket_test","order_id":"AL111111111111111111111111111111","state":"pending","provider":"alipay"}'})
handle(0,{PlayerID=0,action='cancel',sku='ticket_test',order_id='forged'})
assert(require('core/json_decoder').decode(requests[9].body).order_id=='AL111111111111111111111111111111')
requests[9].done({StatusCode=200,Body='{"ok":true,"sku":"ticket_test","order_id":"AL111111111111111111111111111111","state":"closed","provider":"alipay"}'})
handle(0,{PlayerID=0,action='create',sku='ticket_test',provider='attacker'})
assert(#requests==9,'unknown payment providers must be rejected')
print('PAYMENT_GAME_SERVICE_PASS: trusted identity, fixed fields, duplicate requests, authoritative refresh')

-- Reopening and HUD hot reloads must share the same authenticated read.
Time=function()return clock end
clock=1000
local first=#requests+1
handle(0,{PlayerID=0,action='catalog',request_id='hud_a_1'})
handle(0,{PlayerID=0,action='catalog',request_id='hud_b_1'})
assert(#requests==first,'in-flight catalog requests must coalesce')
body=require('core/json_decoder').decode(requests[first].body)
assert(body.account_id=='123' and body.request_id==nil,'UI correlation must not become a payment identity')
requests[first].done({StatusCode=200,Body='{"ok":true,"catalog_hash":"v1","categories":[],"products":[{"sku":"wood_test","owned":0,"enabled":true}]}'})
assert(sent[#sent-1].request_id=='hud_a_1' and sent[#sent].request_id=='hud_b_1','each waiting HUD must receive its own result')
handle(0,{PlayerID=0,action='catalog',request_id='hud_b_2'})
assert(#requests==first and sent[#sent].ok and sent[#sent].request_id=='hud_b_2','rapid reopen must return cached success instead of busy')
clock=clock+3
handle(0,{PlayerID=0,action='catalog',request_id='hud_b_3'})
assert(#requests==first+1,'expired cache must check remote player state')
requests[#requests].done({StatusCode=200,Body='{"ok":true,"catalog_hash":"v1","products":[{"sku":"wood_test","owned":1,"enabled":false}]}'})
assert(sent[#sent].products[1].owned==1,'same catalog hash cannot hide ownership changes')
handle(0,{PlayerID=1,action='catalog',request_id='player_2'})
assert(#requests==first+2,'another player must not receive the first player cache')
assert(require('core/json_decoder').decode(requests[#requests].body).account_id=='456')
requests[#requests].done({StatusCode=503,Body='{"ok":false,"error":"payment_unavailable"}'})
assert(not sent[#sent].ok and sent[#sent].request_id=='player_2')
handle(0,{PlayerID=0,action='create',sku='wood_test',request_id='purchase_1'})
requests[#requests].done({StatusCode=200,Body='{"ok":true,"sku":"wood_test","state":"pending"}'})
clock=clock+1.1
local before=#requests
handle(0,{PlayerID=0,action='catalog',request_id='after_purchase'})
assert(#requests==before+1,'payment actions invalidate the short catalog cache')
requests[#requests].done({StatusCode=200,Body='{"ok":true,"catalog_hash":"v2","products":[]}'})
clock=clock+1.1
package.loaded['systems/match_setup_service'].get_session_id=function()return 'new_session' end
before=#requests
handle(0,{PlayerID=0,action='catalog',request_id='next_session'})
assert(#requests==before+1,'a new session must not reuse the previous session cache')
local oldRequest=requests[#requests]
package.loaded['systems/match_setup_service'].get_session_id=function()return 'third_session' end
clock=clock+2
handle(0,{PlayerID=0,action='catalog',request_id='third_session'})
local replies=#sent
oldRequest.done({StatusCode=200,Body='{"ok":true,"catalog_hash":"old","products":[]}'})
assert(#sent==replies,'late result from another session must not release or overwrite the new request')
requests[#requests].done({StatusCode=200,Body='{"ok":true,"catalog_hash":"new","products":[]}'})
assert(sent[#sent].request_id=='third_session' and sent[#sent].catalog_hash=='new')
print('PAYMENT_CATALOG_SERVICE_PASS: coalescing, rate-limit cache, expiry, identity/session isolation, correlation, ownership refresh')
