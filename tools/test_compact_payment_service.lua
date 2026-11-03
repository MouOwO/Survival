-- Real payment evaluator + compact bridge. Only engine/profile/PWA/HTTP I/O
-- boundaries are synthetic; the existing online-auth suite covers real policy.
package.path="scripts/vscripts/?.lua;"..package.path
local bus=require("core/event_bus")
local events=require("core/events")
local players,accounts,authenticated,bound,opened={},{},{},{},{}
local callbacks,published,sent,listeners,http,invalidated={},{},{},{},{},{}
local pending=false
local provider={resolve_account_id=function(id)return accounts[id]end}
for id=0,3 do
 local player={id=id};function player:GetPlayerID()return self.id end;function player:IsNull()return false end
 players[id]=player;accounts[id]=tostring(1000+id);authenticated[id]=true;bound[id]=true;opened[id]=true
end
local session="synthetic_compact_payment_match_1"
Time=function()return 100 end
PlayerResource={IsValidPlayerID=function(_,id)return players[id]~=nil end,IsFakeClient=function()return false end,
 GetPlayer=function(_,id)return players[id]end,GetSteamAccountID=function(_,id)return tonumber(accounts[id])end,
 GetConnectionState=function()return 2 end,GetTeam=function()return 2 end}
EntIndexToHScript=function(source)return players[source-100]end
CustomGameEventManager={RegisterListener=function(_,name,fn)listeners[name]=fn end,
 Send_ServerToPlayer=function(_,player,name,body)sent[#sent+1]={player=player,name=name,body=body}end}
local registered
local transport={is_bound=function(id)return bound[id]==true end,is_open=function(id,view)return view==9 and opened[id]==true end,
 register_view=function(id,handler)assert(id==9);registered=handler end,
 publish=function(id,view,ops,options)published[#published+1]={id=id,view=view,ops=ops};assert(options.priority);return{queued=true}end}
package.loaded["ui/compact_ui_transport"]=transport
package.loaded["config/generated/ui_static_catalog_lookup"]={by_key={["payment:capability"]=9000},field_by_name={known=1,enabled=2,request_token=3}}
package.loaded["core/commerce_release_policy"]={online_allowed=function()return true end,real_money_allowed=function()return true end}
package.loaded["core/test_access_policy"]={allowed=function()return true end}
package.loaded["systems/player_profile_service"]={get_provider=function()return provider end,get_profile=function()return{save={}}end,
 is_authenticated_for_account=function(id,account)return authenticated[id]and accounts[id]==account end}
package.loaded["systems/player_profile_providers/http_fishing_provider"]=provider
package.loaded["systems/match_setup_service"]={get_session_id=function()return session end}
package.loaded["core/scheduler"]={after=function()end,cancel=function()end}
package.loaded["systems/commerce_service"]={init=function()end}
package.loaded["systems/archive_service"]={set_purchase_provider=function()end}
package.loaded["debug/payment_test_commands"]={init=function()end}
package.loaded["systems/gameplay_phase_guard"]={post_clear_frozen=function()return false end}
package.loaded["systems/player_web_auth"]={
 resolve=function(account,match,success,failure)
  callbacks[#callbacks+1]={account=account,match=match,success=success,failure=failure}
  if not pending then success("https://pay.xiaofengnet.com/ws4-web","pwa1_"..string.rep("a",64))end
 end,
 invalidate=function(account,match)invalidated[#invalidated+1]={account=account,match=match}end}
CreateHTTPRequestScriptVM=function()
 local request={}
 function request:SetHTTPRequestHeaderValue()end;function request:SetHTTPRequestRawPostBody()end
 function request:SetHTTPRequestAbsoluteTimeoutMS(value)assert(value==30000)end
 function request:Send(callback)self.complete=callback end
 http[#http+1]=request;return request
end
local payment=require("systems/payment_service")
bus.reset();payment.init();assert(registered)
local function value(row,field)for _,op in ipairs(row.ops)do if op.field==field then return op.value end end end
local function intent(id,token,alias)return registered.intent(id,"payment_capability",{request_token=token,session_token=alias or 7})end
local function changed(id)bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=id})end

for id=0,3 do
 local unknown=registered.open(id);assert(#unknown==1 and unknown[1].value==0)
end
assert(#callbacks==0 and #published==0 and #sent==0,"opening/initial snapshots cannot authorize or start PWA")
intent(0,1)
assert(#callbacks==1 and #published==1 and #sent==0)
assert(value(published[1],1)==1 and value(published[1],2)==1 and value(published[1],3)==1)
for _,op in ipairs(published[1].ops)do assert(op.record==9000 and type(op.value)=="number")end
local before=#published
for n=1,1000 do intent(0,1)end
assert(#callbacks==1 and #published==before,"same nonce never starts another authorization or renews a lease")
changed(0);assert(#callbacks==2 and #published==before,"unchanged real validation does not resend identical capability")
assert(registered.intent(0,"payment_capability",{request_token=2,session_token=7,arg_a=99})==nil)
assert(#callbacks==2,"no account/player/session argument is accepted")

assert(payment.handle(100,{action="catalog",request_id="synthetic_cash_catalog"})==true)
assert(#http==1,"capability did not create an order; this explicit catalog action did")
pending=true
http[1].complete({StatusCode=403,Body='{"ok":false,"error":"unauthorized"}'})
assert(#invalidated==1 and invalidated[1].account==accounts[0]and invalidated[1].match==session)
assert(value(published[#published],2)==0 and #published[#published].ops==1,"HTTP403 revokes the exact retained last compact challenge through the original evaluator")
for _,row in ipairs(sent)do assert(row.name~="survival_payment_capability","compact clients receive no legacy identity strings")end
local old_auth=callbacks[#callbacks]
pending=false;intent(0,2)
before=#published;old_auth.success("https://pay.xiaofengnet.com/ws4-web","pwa1_"..string.rep("b",64))
assert(#published==before,"old serial cannot approve a newer challenge")

for id=1,3 do intent(id,10+id)end
for id=1,3 do assert(published[#published-3+id].id==id)end
authenticated[1]=false;changed(1)
assert(published[#published].id==1 and value(published[#published],2)==0)
local current=#callbacks
listeners.survival_payment_capability_request(999,{PlayerID=0,request_id="forged_actor"})
listeners.survival_payment_capability_request(100,{PlayerID=3,request_id="stale_old_protocol"})
assert(#callbacks==current,"invalid actor or a bound old-protocol request cannot start authorization")

bound[3]=false
listeners.survival_payment_capability_request(103,{PlayerID=0,request_id="explicit_old_reader"})
assert(sent[#sent].name=="survival_payment_capability"and sent[#sent].player==players[3])
assert(sent[#sent].body.player_id==3 and sent[#sent].body.account_id==accounts[3]and sent[#sent].body.request_id=="explicit_old_reader")
bound[3]=true;before=#sent;changed(3);assert(#sent==before,"compact binding terminates the explicitly subscribed old publisher")

pending=true;intent(2,99);local delayed=callbacks[#callbacks];before=#published
accounts[2]="2002";delayed.success("https://pay.xiaofengnet.com/ws4-web","pwa1_"..string.rep("c",64))
assert(#published==before,"changed account invalidates asynchronous authorization")
pending=false;intent(2,100)
pending=true;intent(2,101);delayed=callbacks[#callbacks];before=#published
players[2]={id=2,GetPlayerID=function()return 2 end,IsNull=function()return false end}
delayed.success("https://pay.xiaofengnet.com/ws4-web","pwa1_"..string.rep("d",64))
assert(#published==before,"replacement actual handle cannot inherit an old receipt")

local old_listener=listeners.survival_payment_capability_request
bus.reset();payment.init();before=#callbacks
old_listener(100,{request_id="retired_world"})
assert(#callbacks==before,"old engine listener is inert after the real bus generation reset")
local wire=require("ui/compact_wire")
local definition={id=1,sha256=string.rep("a",64),records={9000},fields={
 [1]={kind="bool"},[2]={kind="bool"},[3]={kind="uint",min=1,max=16383}}}
local schema=assert(wire.compile_schema(definition))
local packets,native_max=0,0
for _,row in ipairs(published)do
 local encoded=assert(wire.encode(schema,{schema=1,schema_sha256=string.rep("a",64),session=16383,epoch=16383,view=9},16383,row.ops))
 for _,packet in ipairs(encoded)do assert(#packet.d<=24);packets=packets+1;native_max=math.max(native_max,25+#packet.d)end
end
assert(native_max<=49)
if arg and arg[1]=="--emit"then
 local binding={schema=1,schema_sha256=definition.sha256,session=16383,epoch=16383,view=9}
 local transactions={{full=true,revision=1,packets=assert(wire.encode(schema,binding,1,{{record=9000,field=1,value=0}},{full=true}))}}
 for _,row in ipairs(published)do if row.id==0 then
  local revision=#transactions+1
  transactions[#transactions+1]={revision=revision,packets=assert(wire.encode(schema,binding,revision,row.ops))}
 end end
 print("COMPACT_PAYMENT_WIRE_FIXTURES:"..require("core/json_encoder").encode({schema=definition,binding=binding,transactions=transactions}))
end
print("COMPACT_PAYMENT_CODEC_CALIBRATED packets="..packets.." max_native_message_bytes="..native_max.."; maximum legal header; 25B measured fixed overhead model, not new native/FPS evidence")
print("COMPACT_PAYMENT_SERVICE_PASS real evaluator/bridge + 4 synthetic owners; original auth binding/actor allowlist/403 path; replay+stable zero sends; legacy opt-in; account/handle/world rejection; no real HTTP/transaction")
