-- Real payment -> profile -> inventory/lottery projections; only transports/engine are fixtures.
package.path='scripts/vscripts/?.lua;'..package.path
require("tests/development_release_profile")
-- Admission is covered separately; these transport fixtures use synthetic accounts.
package.loaded['config/test_access']={enabled=false}
local bus,ev=require('core/event_bus'),require('core/events')
local decoder,encoder=require('core/json_decoder'),require('core/json_encoder')
local handlers,sent,http,fetches,lottery_reads={},{},{},{},{}
local accounts={[0]='1200',[1]='1201'}
local clock=100
local setup={get_session_id=function()return 'reward_refresh_session' end,get_mode=function()return 'standard' end,is_mode_selected=function()return true end}
package.loaded['systems/match_setup_service']=setup
local tasks={}
package.loaded['core/scheduler']={every=function()end,after=function(delay,callback,key)tasks[key]={delay=delay,callback=callback} end,cancel=function(key)tasks[key]=nil end}
package.loaded['core/logger']={info=function()end,warn=function()end,error=function()end}
package.loaded['systems/commerce_service']={init=function()end}
package.loaded['systems/archive_service']={set_purchase_provider=function()end}
package.loaded['systems/gameplay_phase_guard']={post_clear_frozen=function()return false end}
local rights={}
package.loaded['systems/player_entitlement_service']={replace_all=function(id,value)rights[id]=value end}
local provider={init=function()end,resolve_account_id=function(id)return accounts[id] end,
 fetch_snapshot=function(account,success,failure)fetches[#fetches+1]={account=account,success=success,failure=failure} end,
 lottery_snapshot=function(payload,done,fail)lottery_reads[#lottery_reads+1]={payload=payload,done=done,fail=fail} end}
PlayerResource={IsValidPlayerID=function(_,id)return accounts[id]~=nil end,IsFakeClient=function()return false end,
 GetPlayer=function(_,id)return {id=id} end,GetTeam=function()return 2 end}
CustomGameEventManager={RegisterListener=function(_,name,fn)handlers[name]=fn end,
 Send_ServerToPlayer=function(_,player,name,value)sent[#sent+1]={id=player.id,name=name,data=value} end}
Convars={GetStr=function()return 'fixture_transport_token' end}
Time=function()clock=clock+2;return clock end
IsInToolsMode=function()return true end
ListenToGameEvent=function()end
CreateHTTPRequestScriptVM=function(method,url)
 local request={url=url}
 function request:SetHTTPRequestHeaderValue()end
 function request:SetHTTPRequestRawPostBody(_,body)self.body=decoder.decode(body)end
 function request:Send(callback)self.done=callback end
 http[#http+1]=request;return request
end
local profiles=require('systems/player_profile_service')
profiles.init({provider=provider})
require('systems/content_inventory_service').init()
require('systems/lottery_http_service').init()
require('systems/payment_service').init()
local inventory_events,lottery_events={},{}
bus.subscribe(ev.CONTENT_INVENTORY_CHANGED,function(p)inventory_events[#inventory_events+1]=p end)
bus.subscribe(ev.LOTTERY_CHANGED,function(p)lottery_events[#lottery_events+1]=p end)
local function profile(id,revision,tickets,wood,skin,u_coin)
 return {schema_version=1,account_id=accounts[id],revision=revision,entitlements={vip={active=true}},
  achievements={},public={},save={gameplay_stats={initial_wood=wood},archive={commerce={balances={u_coin=u_coin or (id==0 and 17 or 23)}}},
  content_inventory={special_lottery_ticket=tickets,lottery_monkey_king=skin or 0}}}
end
local function snapshot(tickets,skin)
 return {ok=true,snapshots={{selected_pool_id='summer',tickets=tickets,
  selected_pool={id='summer',tickets=tickets},pools={{id='summer',tickets=tickets}},
  items={{id='lottery_monkey_king',owned_count=skin or 0}}}}}
end
local function inventory(id)
 return bus.request(ev.CONTENT_INVENTORY_GET_REQUEST,{player_id=id}).snapshot.counts
end
assert(profiles.apply_snapshot(0,profile(0,1,2,140)).ok)
lottery_reads[#lottery_reads].done(snapshot(2,0))
assert(profiles.apply_snapshot(1,profile(1,1,4,200)).ok)
lottery_reads[#lottery_reads].done(snapshot(4,0))
assert(inventory(0).special_lottery_ticket==2 and inventory(1).special_lottery_ticket==4)
-- Begin an older balance read just before the payment is delivered.
local open_result
bus.request(ev.LOTTERY_SNAPSHOT_REQUEST,{player_id=0,pool_id='summer',prefetch=1,complete=function(r)open_result=r end})
local old_read=lottery_reads[#lottery_reads]
local payment=handlers.survival_payment_request
payment(nil,{PlayerID=0,action='create',sku='video_p001',quantity=7,request_id='purchase_fixture'})
local order={ok=true,order_id='WX'..string.rep('1',30),sku='video_p001',state='pending',quantity=7}
http[#http].done({StatusCode=200,Body=encoder.encode(order)})
payment(nil,{PlayerID=0,action='status',sku='video_p001',request_id='status_fixture'})
order.state='delivered'
local before_reply=#sent
http[#http].done({StatusCode=200,Body=encoder.encode(order)})
assert(#fetches==1 and fetches[1].account==accounts[0])
assert(profiles.get_profile(0).save.content_inventory.special_lottery_ticket==2,'No empty profile while authoritative refresh is in flight')
assert(rights[0].vip==true,'Existing VIP must not flicker off')
assert(#sent==before_reply,'Delivered receipt waits for the real profile commit')
local before_inventory=#inventory_events
fetches[1].success(profile(0,2,9,140,1))
assert(inventory(0).special_lottery_ticket==9 and inventory(0).lottery_monkey_king==1)
assert(#inventory_events==before_inventory+1,'Other purchased contents notify existing consumers exactly once')
assert(inventory_events[#inventory_events].changes.special_lottery_ticket==7)
assert(inventory_events[#inventory_events].changes.lottery_monkey_king==1)
assert(sent[#sent].name=='survival_payment_result' and sent[#sent].data.state=='delivered')
assert(sent[#sent].id==0 and sent[#sent].data.game_entitlements.vip.active)
local n=#lottery_events
old_read.done(snapshot(2,0))
assert(not open_result and #lottery_events==n,'Pre-payment read cannot publish old ticket count or complete reopening')
assert(lottery_reads[#lottery_reads]~=old_read,'Payment causes a trailing authoritative read')
lottery_reads[#lottery_reads].done(snapshot(9,1))
assert(open_result.ok and open_result.snapshot.tickets==9 and open_result.snapshot.items[1].owned_count==1)
assert(lottery_events[#lottery_events].player_id==0)
assert(inventory(1).special_lottery_ticket==4 and profiles.get_profile(1).save.gameplay_stats.initial_wood==200)
-- Repeated successful polling is not another grant or another profile reload.
local profile_reads,content_events=#fetches,#inventory_events
payment(nil,{PlayerID=0,action='status',sku='video_p001',request_id='status_duplicate'})
http[#http].done({StatusCode=200,Body=encoder.encode(order)})
assert(#fetches==profile_reads and #inventory_events==content_events and inventory(0).special_lottery_ticket==9)
assert(#http==3,'Only create/status/status fake transport calls, no gateway')
print('PAYMENT_REWARD_REFRESH_CHAIN_PASS: real payment/profile/inventory/lottery modules, 7 tickets and other ownership refresh, no empty profile, no stale publish, player isolation and duplicate receipt')

-- Cash recharge uses this same delivery path. Its balance must already be in
-- the authoritative profile/account save before the UI gets success.
local function u_coin(id)
 return (profiles.get_account_profile(id) or profiles.get_profile(id)).save.archive.commerce.balances.u_coin
end
assert(u_coin(0)==17 and u_coin(1)==23)
local refreshes_before=#fetches
payment(nil,{PlayerID=0,action='create',sku='u_coin_recharge',provider='alipay',quantity=999999,request_id='recharge_max'})
assert(http[#http].body.quantity==999999 and http[#http].body.provider=='alipay')
local recharge={ok=true,order_id='RC'..string.rep('2',30),sku='u_coin_recharge',product_type='recharge',
 state='delivered',quantity=999999,amount_fen=99999900,recharge_u_coin_per_unit=100,recharge_u_coin_total=99999900,max_quantity=999999}
local recharge_before=#sent
http[#http].done({StatusCode=200,Body=encoder.encode(recharge)})
assert(#sent==recharge_before and #fetches==refreshes_before+1 and u_coin(0)==17,
 'pending recharge refresh retains the old balance and withholds success')
fetches[#fetches].success(profile(0,3,9,140,1,99999917))
assert(u_coin(0)==99999917 and u_coin(1)==23,'max recharge balance is visible only to its owner')
assert(sent[#sent].data.state=='delivered' and sent[#sent].data.recharge_u_coin_total==99999900)
assert(inventory(0).special_lottery_ticket==9 and inventory(0).lottery_monkey_king==1,
 'wallet recharge leaves unrelated inventory intact')
local after_refresh=#fetches
payment(nil,{PlayerID=0,action='status',sku='u_coin_recharge',request_id='recharge_duplicate'})
http[#http].done({StatusCode=200,Body=encoder.encode(recharge)})
assert(#fetches==after_refresh and u_coin(0)==99999917 and u_coin(1)==23,
 'duplicate recharge status does not add balance or start another profile load')
print('PAYMENT_RECHARGE_REFRESH_CHAIN_PASS: max quantity balance atomically reaches real profile/account save, unrelated inventory/player intact, no duplicate refresh')
