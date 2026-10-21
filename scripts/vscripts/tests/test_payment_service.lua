package.path = "scripts/vscripts/?.lua;" .. package.path
require("tests/development_release_profile")
package.path='scripts/vscripts/?.lua;'..package.path
-- Commerce has its own scheduler/runtime tests; this fixture tests the
-- authenticated payment transport without starting an unrelated game loop.
package.loaded['systems/commerce_service']={init=function() end}
package.loaded['core/scheduler']={after=function()end,cancel=function()end}
local pass_provider
package.loaded['systems/archive_service']={set_purchase_provider=function(value)pass_provider=value end}
local handlers,sent,requests={},{},{}
local loaded=true
local refreshed=0
local profile={save={content_inventory={},gameplay_stats={initial_wood=180}}}
local provider={resolve_account_id=function(id)return id==0 and '123' or '456' end}
package.loaded['systems/player_profile_service']={get_provider=function()return provider end,
 get_profile=function()return loaded and profile or nil end,
 load_player=function()error("payment must use non-destructive refresh")end,
 refresh_player=function(id,reason,done)refreshed=refreshed+1;done();return {ok=true} end}
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
handle(0,{PlayerID=0,action='create',sku='wood_100_test_50_v3',account_id='attacker',amount=1,u_coin_price=1,u_coin_per_yuan=1,amount_fen=1})
local body=require('core/json_decoder').decode(requests[1].body)
assert(body.account_id=='123' and body.amount==nil and body.match_session_id=='safe_session')
assert(body.u_coin_price==nil and body.u_coin_per_yuan==nil and body.amount_fen==nil,'client cannot forward its own cash/U-coin quote')
handle(0,{PlayerID=0,action='create',sku='wood_100_test_50_v3'});assert(#requests==1,'in-flight duplicate blocked')
requests[1].done({StatusCode=200,Body='{"ok":true,"sku":"wood_100_test_50_v3","order_id":"WX111111111111111111111111111111","state":"pending","amount_fen":120,"u_coin_price":1200,"u_coin_per_yuan":1000}'})
assert(sent[#sent].amount_fen==120 and sent[#sent].u_coin_price==1200 and sent[#sent].u_coin_per_yuan==1000,'authenticated order quote must reach the game UI unchanged')
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
requests[first].done({StatusCode=200,Body='{"ok":true,"catalog_hash":"v1","categories":[],"products":[{"sku":"wood_test","owned":0,"enabled":true,"amount_fen":120,"u_coin_price":1200,"u_coin_per_yuan":1000}]}'})
assert(sent[#sent-1].request_id=='hud_a_1' and sent[#sent].request_id=='hud_b_1','each waiting HUD must receive its own result')
handle(0,{PlayerID=0,action='catalog',request_id='hud_b_2'})
assert(#requests==first and sent[#sent].ok and sent[#sent].request_id=='hud_b_2','rapid reopen must return cached success instead of busy')
assert(sent[#sent].products[1].amount_fen==120 and sent[#sent].products[1].u_coin_price==1200 and sent[#sent].products[1].u_coin_per_yuan==1000,'catalog cache must retain the server quote')
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

-- Opening a pass from the daily panel enters confirmation without submitting
-- an order, using only the server-configured product and authenticated player.
local pass_rules=require('config/generated/archive_daily_rules').by_id.default
assert(pass_provider and type(pass_provider.open_checkout)=='function')
local before_checkout=#requests
local result
assert(pass_provider.open_checkout(0,{sku=pass_rules.pass_sku,amount_fen=1,account_id='attacker'},function(value)result=value end))
assert(result.ok and sent[#sent].sku=='archive_pass_monthly')
assert(#requests==before_checkout,'opening the monthly confirmation cannot create a payment intent')
assert(not pass_provider.open_checkout(0,{sku='forged_product'},function(value)result=value end) and not result.ok)
loaded=false
assert(not pass_provider.open_checkout(0,{sku=pass_rules.pass_sku},function(value)result=value end))
loaded=true
assert(not pass_provider.open_checkout(-1,{sku=pass_rules.pass_sku}))
local get_token=Convars.GetStr
Convars.GetStr=function()return '' end
assert(not pass_provider.open_checkout(0,{sku=pass_rules.pass_sku}))
Convars.GetStr=get_token
assert(#requests==before_checkout,'invalid checkout entries cannot contact the gateway')
print('MONTHLY_CHECKOUT_SERVICE_PASS: trusted SKU and player, profile/token validation, confirmation creates no order')

-- Count is the only new client-owned order field. Identity/prices remain server-owned.
local before_quantity=#requests
handle(0,{PlayerID=0,action='create',sku='quantity_ticket',quantity=7,amount_fen=1,unit_amount_fen=1})
assert(#requests==before_quantity+1)
local quantity_body=require('core/json_decoder').decode(requests[#requests].body)
assert(quantity_body.quantity==7 and quantity_body.amount_fen==nil and quantity_body.unit_amount_fen==nil)
requests[#requests].done({StatusCode=200,Body='{"ok":true,"sku":"quantity_ticket","order_id":"WX333333333333333333333333333333","state":"pending","quantity":7,"unit_amount_fen":120,"amount_fen":840}'} )
assert(sent[#sent].quantity==7 and sent[#sent].amount_fen==840)
local before_invalid=#requests
for _,bad in ipairs({0,-1,1.5,101,'5',true}) do
 handle(0,{PlayerID=0,action='create',sku='quantity_invalid',quantity=bad})
 assert(#requests==before_invalid and sent[#sent].error=='quantity_invalid')
end
print('PAYMENT_QUANTITY_BRIDGE_PASS: integer1..100, trusted totals, no client price forwarding')

-- Recharge is the only large-quantity product. Cash totals and wallet credits
-- are authenticated response fields, never a client-supplied exchange rate.
clock=clock+3
handle(0,{PlayerID=0,action='catalog',request_id='recharge_catalog'})
requests[#requests].done({StatusCode=200,Body='{"ok":true,"products":[{"sku":"u_coin_recharge","product_type":"recharge","enabled":true,"amount_fen":100,"recharge_u_coin_per_unit":100,"max_quantity":999999}]}'})
local recharge=sent[#sent].products[1]
assert(recharge.sku=='u_coin_recharge' and recharge.product_type=='recharge'
 and recharge.amount_fen==100 and recharge.recharge_u_coin_per_unit==100 and recharge.max_quantity==999999,
 'catalog must preserve authoritative recharge metadata')
local recharge_order
for _,selection in ipairs({{quantity=1,provider='wechat'},{quantity=999999,provider='alipay'}}) do
 clock=clock+2
 local before=#requests
 handle(0,{PlayerID=0,action='create',sku='u_coin_recharge',quantity=selection.quantity,provider=selection.provider,
  account_id='attacker',amount_fen=1,unit_amount_fen=1,recharge_u_coin_per_unit=999999,recharge_u_coin_total=999999999})
 assert(#requests==before+1,'recharge quantity endpoints must reach the payment transport')
 local sent_body=require('core/json_decoder').decode(requests[#requests].body)
 assert(sent_body.sku=='u_coin_recharge' and sent_body.quantity==selection.quantity and sent_body.provider==selection.provider)
 assert(sent_body.account_id=='123' and sent_body.amount_fen==nil and sent_body.unit_amount_fen==nil
  and sent_body.recharge_u_coin_per_unit==nil and sent_body.recharge_u_coin_total==nil,
  'client cannot choose the recharge price, grant or account')
 recharge_order={ok=true,sku='u_coin_recharge',product_type='recharge',state='pending',
  order_id='RC'..string.format('%030d',selection.quantity),quantity=selection.quantity,max_quantity=999999,
  unit_amount_fen=100,amount_fen=100*selection.quantity,recharge_u_coin_per_unit=100,recharge_u_coin_total=100*selection.quantity}
 requests[#requests].done({StatusCode=200,Body=require('core/json_encoder').encode(recharge_order)})
 assert(sent[#sent].quantity==selection.quantity and sent[#sent].amount_fen==100*selection.quantity
  and sent[#sent].max_quantity==999999 and sent[#sent].product_type=='recharge'
  and sent[#sent].recharge_u_coin_total==100*selection.quantity)
end
local recharges_before=refreshed
clock=clock+2
handle(0,{PlayerID=0,action='status',sku='u_coin_recharge'})
recharge_order.state='delivered'
requests[#requests].done({StatusCode=200,Body=require('core/json_encoder').encode(recharge_order)})
assert(refreshed==recharges_before+1 and sent[#sent].state=='delivered','recharge uses the existing authoritative refresh')
clock=clock+2
handle(0,{PlayerID=0,action='status',sku='u_coin_recharge'})
requests[#requests].done({StatusCode=200,Body=require('core/json_encoder').encode(recharge_order)})
assert(refreshed==recharges_before+1,'duplicate recharge receipt cannot refresh or grant twice')
local recharge_invalid=#requests
for _,bad in ipairs({0,-1,1.5,1000000,'999999',true,math.huge,-math.huge,0/0}) do
 handle(0,{PlayerID=0,action='create',sku='u_coin_recharge',quantity=bad})
 assert(#requests==recharge_invalid and sent[#sent].error=='quantity_invalid')
end
for _,sku in ipairs({'quantity_ticket','u_coin_recharge_extra'}) do
 handle(0,{PlayerID=0,action='create',sku=sku,quantity=999999})
 assert(#requests==recharge_invalid and sent[#sent].error=='quantity_invalid','recharge maximum must not extend to other products')
end
clock=clock+2
handle(0,{PlayerID=0,action='create',sku='quantity_ticket',quantity=100})
assert(#requests==recharge_invalid+1 and require('core/json_decoder').decode(requests[#requests].body).quantity==100,
 'ordinary products retain their inclusive quantity100 endpoint')
requests[#requests].done({StatusCode=200,Body='{"ok":true,"sku":"quantity_ticket","state":"pending","quantity":100}'})
print('PAYMENT_RECHARGE_BRIDGE_PASS: recharge-only integer1..999999, both channels, trusted cash/grant metadata, invalid quantities and duplicate refresh safe')
