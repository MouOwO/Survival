-- Actual profile/payment/permanent/resource modules; only HTTP and engine are faked.
package.path='scripts/vscripts/?.lua;'..package.path
require("tests/development_release_profile")
-- Synthetic accounts exercise the real profile chain without the production allowlist.
package.loaded['config/test_access']={enabled=false}
local bus=require('core/event_bus');local events=require('core/events')
local mode,session='standard','payment_refresh_session_1'
local accounts={[0]='123',[1]='456'}
local requests,sent,public,events_seen,timers={},{},{},{},{}
local now=0
package.loaded['systems/match_setup_service']={get_mode=function()return mode end,
 get_session_id=function()return session end,is_mode_selected=function()return mode~=nil end}
package.loaded['core/scheduler']={every=function()end,cancel=function(key)timers[key]=nil end,
 after=function(_,fn,key)timers[key]=fn end}
package.loaded['core/logger']={info=function()end,warn=function()end}
package.loaded['systems/gameplay_phase_guard']={post_clear_frozen=function()return false end}
package.loaded['systems/player_context_service']={is_defeated=function()return false end}
package.loaded['systems/commerce_service']={init=function()end}
package.loaded['systems/archive_service']={set_purchase_provider=function()end}
GameRules={GetGameTime=function()return now end,GetGameModeEntity=function()return {} end}
PlayerResource={GetSteamAccountID=function(_,id)return tonumber(accounts[id])end,
 IsValidPlayerID=function(_,id)return accounts[id]~=nil end,IsFakeClient=function()return false end,
 GetPlayer=function(_,id)return {id=id}end,GetTeam=function()return 2 end}
CustomNetTables={SetTableValue=function(_,table_name,key,value)
 public[tonumber(key)]=value;events_seen[#events_seen+1]={kind='public',id=tonumber(key),revision=value.revision}
end}
CustomGameEventManager={RegisterListener=function()end,
 Send_ServerToPlayer=function(_,player,name,value)sent[#sent+1]={player=player.id,name=name,value=value}end}
Convars={RegisterConvar=function()end,GetStr=function(_,key)
 if key=='survival_fishing_api_token' then return 'fictional_payment_refresh_test_token' end
 return ''
end}
Time=function()now=now+2;return now end
IsInToolsMode=function()return true end
ListenToGameEvent=function()end
CreateHTTPRequestScriptVM=function(method,url)
 local request={url=url,method=method};requests[#requests+1]=request
 function request:SetHTTPRequestHeaderValue()end
 function request:SetHTTPRequestAbsoluteTimeoutMS()end
 function request:SetHTTPRequestRawPostBody(_,body)self.body=require('core/json_decoder').decode(body)end
 function request:Send(done)self.done=done end
 return request
end
local profiles=require('systems/player_profile_service')
local entitlements=require('systems/player_entitlement_service')
local effects=require('systems/permanent_reward_effect_service')
local resources=require('systems/resource_system')
local function reset_world()
 bus.reset();requests,sent,public,events_seen,timers={},{},{},{},{}
 entitlements.init();effects.init();resources.init();profiles.init()
 bus.subscribe(events.PLAYER_PROFILE_CHANGED,function(p)events_seen[#events_seen+1]={kind='profile',id=p.player_id,reason=p.reason}end)
 bus.subscribe(events.PLAYER_ENTITLEMENT_CHANGED,function(p)events_seen[#events_seen+1]={kind='entitlement',id=p.player_id,vip=p.values.vip}end)
end
local function snapshot(id,revision,wood,tickets,vip)
 local value={schema_version=1,account_id=accounts[id],revision=revision,mode=mode,match_session_id=session,
  progression={loaded=true,clear_counts={}},entitlements={vip={active=vip==true},archive_pass={active=true}},
  achievements={},public={},save={gameplay_stats={initial_wood=wood,initial_gold=0,hero_attack_bonus_pct=20},
  archive={},content_inventory={special_lottery_ticket=tickets}}}
 local copy=require('core/json_decoder').decode(require('core/json_encoder').encode(value))
 copy.mode,copy.match_session_id,copy.progression=nil,nil,nil
 value.account_profile=copy
 return value
end
local function respond(request,value,status)
 request.done({StatusCode=status or 200,Body=require('core/json_encoder').encode(value)})
end
local function wood(id)return bus.request(events.RESOURCE_GET_REQUEST,{player_id=id or 0}).wood end
local function vip(id)return bus.request(events.PLAYER_ENTITLEMENT_GET_REQUEST,{player_id=id or 0}).snapshot.values.vip end
local function load(id,revision,amount,tickets,is_vip)
 assert(profiles.load_player(id,'fixture_load').ok)
 respond(requests[#requests],snapshot(id,revision,amount,tickets,is_vip))
 assert(profiles.get_profile(id).revision==revision)
end
local function spend(id,amount)assert(bus.request(events.RESOURCE_TRY_SPEND_REQUEST,{player_id=id,wood=amount}).ok)end
local function delivered_count()
 local count=0
 for _,packet in ipairs(sent)do if packet.name=='survival_payment_result' and packet.value.ok and packet.value.state=='delivered' then count=count+1 end end
 return count
end
local function no_temporary_invalidation(from)
 for i=from+1,#events_seen do local event=events_seen[i]
  assert(not(event.id==0 and event.kind=='public' and event.revision==0),'refresh must not publish empty public data')
  assert(not(event.id==0 and event.kind=='entitlement' and event.vip==0),'refresh must not revoke existing VIP')
  assert(not(event.id==0 and event.kind=='profile' and event.reason=='loading'),'refresh must not emit an empty profile')
 end
end

-- Preserve the old destructive-load contract and prove the reported P1 first.
reset_world();load(0,1,140,2,true);spend(0,90);assert(wood()==50)
assert(profiles.load_player(0,'old_payment_refresh').pending)
local legacy_empty=wood()
respond(requests[#requests],snapshot(0,2,140,7,true))
assert(legacy_empty==0 and wood()==130,'baseline reproduction: wallet50 -> loading0 -> reload130')
print('PAYMENT_REFRESH_BASELINE_REPRO: wallet50 -> loading0 -> 130')

reset_world();load(0,1,140,2,true);load(1,1,100,0,false)
spend(0,90);spend(1,40);assert(wood()==50 and wood(1)==60)
local payment=require('systems/payment_service');payment.init()
local order_serial=0
local function payment_start(sku,quantity)
 order_serial=order_serial+1
 local oid='WX'..string.format('%030x',order_serial)
 local before=delivered_count()
 payment.handle({PlayerID=0,action='create',sku=sku,quantity=quantity or 1})
 local pay_request=requests[#requests]
 assert(pay_request.url:match('/payments/create$'))
 local event_start=#events_seen
 respond(pay_request,{ok=true,state='delivered',order_id=oid,sku=sku,effects={}})
 local profile_request=requests[#requests]
 assert(profile_request~=pay_request and profile_request.url:match('/v1/profile$'))
 assert(delivered_count()==before,'delivery acknowledgement must wait for profile commit')
 assert(profiles.get_profile(0) and vip()==1,'existing profile and VIP stay live during refresh')
 assert(bus.request(events.PERMANENT_REWARD_EFFECTS_GET_REQUEST,{player_id=0}).totals.hero_attack_bonus_pct==20,
  'existing units keep their permanent projection during refresh')
 no_temporary_invalidation(event_start)
 return profile_request,oid,before,event_start
end
local ticket_request,ticket_order,before,event_start=payment_start('video_p001',5)
assert(wood()==50 and profiles.get_profile(0).save.content_inventory.special_lottery_ticket==2)
assert(profiles.get_account_profile(0).save.content_inventory.special_lottery_ticket==2)
local count=#requests
payment.handle({PlayerID=0,action='status',sku='video_p001'})
assert(#requests==count and sent[#sent].value.error=='payment_busy','status while refreshing must not supersede its profile generation')
respond(ticket_request,snapshot(0,2,140,7,true))
assert(delivered_count()==before+1 and wood()==50 and wood(1)==60,'five tickets must not change either wallet')
assert(profiles.get_profile(0).save.content_inventory.special_lottery_ticket==7)
assert(profiles.get_account_profile(0).save.content_inventory.special_lottery_ticket==7)
assert(public[0].revision==2 and vip()==1)
no_temporary_invalidation(event_start)
count=#requests;payment.handle({PlayerID=0,action='status',sku='video_p001'})
respond(requests[#requests],{ok=true,state='delivered',order_id=ticket_order,sku='video_p001'})
assert(#requests==count+1 and wood()==50,'repeated delivered status cannot reload or grant twice')
print('PAYMENT_REFRESH_TICKETS_PASS: atomic profile/account/public/VIP, wallet unchanged, repeated receipt safe')

local wood_request,wood_order=payment_start('wood_100_test_50_v3')
assert(wood()==50)
respond(wood_request,snapshot(0,3,240,7,true))
assert(wood()==150 and wood(1)==60,'wood purchase applies only its +100 delta to its owner')
print('PAYMENT_REFRESH_WOOD_PASS: exactly +100, unrelated player unchanged')

local failed_request,failed_order,prior=payment_start('failed_ticket_fixture')
respond(failed_request,{error='fictional_network_error'},503)
assert(profiles.get_profile(0).revision==3 and wood()==150 and vip()==1)
assert(profiles.get_account_profile(0).revision==3 and public[0].revision==3)
assert(sent[#sent].value.error=='reward_refresh_pending' and delivered_count()==prior)
payment.handle({PlayerID=0,action='status',sku='failed_ticket_fixture'})
respond(requests[#requests],{ok=true,state='delivered',order_id=failed_order,sku='failed_ticket_fixture'})
local retry_request=requests[#requests]
respond(retry_request,snapshot(0,4,240,9,true))
assert(profiles.get_profile(0).revision==4 and wood()==150 and delivered_count()==prior+1)
print('PAYMENT_REFRESH_FAILURE_PASS: old data retained, no success before commit, retry completes once')

-- Validation, stale revision and exceptions retain every section of the live save.
local done,failed=0,0
profiles.refresh_player(0,'invalid_refresh',function()done=done+1 end,function()failed=failed+1 end)
local invalid=snapshot(0,5,240,9,true);invalid.entitlements.vip.active='wrong'
respond(requests[#requests],invalid)
assert(done==0 and failed==1 and profiles.get_profile(0).revision==4 and wood()==150 and vip()==1)
profiles.refresh_player(0,'stale_refresh',function()done=done+1 end,function()failed=failed+1 end)
respond(requests[#requests],snapshot(0,3,140,2,false))
assert(done==0 and failed==2 and profiles.get_profile(0).revision==4 and wood()==150 and vip()==1)
local provider=profiles.get_provider();local real_fetch=provider.fetch_snapshot
provider.fetch_snapshot=function()error('fictional_provider_error')end
local thrown=profiles.refresh_player(0,'throw_refresh',nil,function()failed=failed+1 end)
provider.fetch_snapshot=real_fetch
assert(not thrown.ok and failed==3 and wood()==150 and profiles.get_profile(0).revision==4)

-- Newer refresh generations own both data and callbacks; late success/failure cannot erase them.
profiles.refresh_player(0,'older_refresh',function()done=done+1 end,function()failed=failed+1 end)
local older=requests[#requests]
profiles.refresh_player(0,'newer_refresh',function()done=done+1 end,function()failed=failed+1 end)
local newer=requests[#requests]
respond(newer,snapshot(0,6,240,10,true));respond(older,snapshot(0,5,999,1,false))
assert(done==1 and failed==3 and profiles.get_profile(0).revision==6 and wood()==150 and vip()==1)
respond(older,{error='late_failure'},503)
assert(profiles.get_profile(0).revision==6)
print('PAYMENT_REFRESH_GENERATION_PASS: invalid/stale/exception retained, reverse replies cannot revert new state')

-- A superseded/lost profile callback cannot hold payment busy permanently.
local timed_request,timed_order,timed_before=payment_start('timeout_ticket_fixture')
assert(timers['payment_profile_refresh:0'])
timers['payment_profile_refresh:0']()
assert(delivered_count()==timed_before and sent[#sent].value.error=='reward_refresh_pending')
assert(profiles.get_profile(0).revision==6 and wood()==150 and vip()==1)
payment.handle({PlayerID=0,action='status',sku='timeout_ticket_fixture'})
local retry_status=requests[#requests]
assert(retry_status.url:match('/payments/status$'),'timeout must release its own busy job')
respond(retry_status,{ok=true,state='delivered',order_id=timed_order,sku='timeout_ticket_fixture'})
respond(requests[#requests],snapshot(0,6,240,10,true))
respond(timed_request,snapshot(0,6,999,999,false))
assert(delivered_count()==timed_before+1 and profiles.get_profile(0).save.content_inventory.special_lottery_ticket==10)
assert(wood()==150 and vip()==1 and timers['payment_profile_refresh:0']==nil)
print('PAYMENT_REFRESH_TIMEOUT_PASS: retry existing order, no premature success or late overwrite')

-- The same slot must never retain old account/session permissions on rebind.
profiles.refresh_player(0,'old_session_refresh')
local old_session_request=requests[#requests]
session='payment_refresh_session_2'
assert(profiles.refresh_player(0,'new_session_refresh').pending)
local new_session_request=requests[#requests]
assert(profiles.get_profile(0)==nil and profiles.get_account_profile(0)==nil and vip()==0 and public[0].revision==0)
respond(new_session_request,snapshot(0,7,240,10,true))
respond(old_session_request,{error='old_session_failure'},503)
assert(profiles.get_profile(0).match_session_id==session and profiles.get_profile(0).revision==7 and vip()==1)

profiles.refresh_player(0,'slot_change_inflight',function()error('old slot must not commit')end,
 function(error_code)assert(error_code=='profile_binding_changed')end)
local old_account_request=requests[#requests]
local old_account_snapshot=snapshot(0,8,999,99,true)
accounts[0]='789'
respond(old_account_request,old_account_snapshot)
assert(profiles.get_profile(0)==nil and profiles.get_account_profile(0)==nil and vip()==0 and public[0].revision==0)
assert(profiles.refresh_player(0,'new_account_refresh').pending)
respond(requests[#requests],snapshot(0,1,10,0,false))
assert(profiles.get_profile(0).account_id=='789' and profiles.get_account_profile(0).account_id=='789' and vip()==0)
assert(public[1].revision==1 and wood(1)==60,'other slot wallet/public cache must remain unchanged; old session profile is hidden')
print('PAYMENT_REFRESH_BINDING_PASS: session and account changes invalidate old data, late replies never cross slots')
-- Test-only remote reset also retains the current snapshot until its commit.
profiles.refresh_player(0,'reset_fixture_bonus')
respond(requests[#requests],snapshot(0,2,110,3,true))
local reset_before=wood()
IsInToolsMode=function()return true end
RandomInt=function()return 12345 end
assert(payment.reset_player({player_id=0,args={}},'refreshmoney'))
local reset_http=requests[#requests]
assert(reset_http.url:match('/payments/reset$'))
respond(reset_http,{ok=true,revision=3})
local reset_profile=requests[#requests]
assert(reset_profile~=reset_http and vip()==1 and profiles.get_profile(0).save.content_inventory.special_lottery_ticket==3)
respond(reset_profile,snapshot(0,3,10,0,false))
assert(wood()==reset_before-100 and vip()==0 and profiles.get_profile(0).save.content_inventory.special_lottery_ticket==0,
 'reset applies its negative delta and permission change once at commit')
local http_count=#requests
payment.handle({PlayerID=0,action='status',sku='timeout_ticket_fixture'})
assert(#requests==http_count and sent[#sent].value.error=='order_not_in_session','committed reset clears prior checkout references')
print('PAYMENT_REFRESH_RESET_PASS: preserve while pending, authoritative negative delta/VIP removal on commit')
print('PAYMENT_PROFILE_REFRESH_PASS: actual profile, payment, entitlement, permanent and resource modules; zero external requests')
