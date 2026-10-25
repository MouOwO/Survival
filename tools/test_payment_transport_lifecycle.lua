-- Real payment service with only engine, HTTP, clock and profile I/O mocked.
-- Optional source path permits a before-change negative control without edits.
package.path='scripts/vscripts/?.lua;'..package.path
local source=arg and arg[1] or 'scripts/vscripts/systems/payment_service.lua'
local encoder=require('core/json_encoder')
local checks=0
local function check(value,message) checks=checks+1;assert(value,message) end
local function fixture(mode)
 local now,cash,account,session=0,true,'123','payment_transport_session_1'
 local tasks,sent,requests,refreshes={},{},{},{}
 package.loaded['core/commerce_release_policy']={real_money_allowed=function()return cash end}
 package.loaded['core/event_bus']={request=function()end,emit=function()end}
 package.loaded['core/events']={}
 package.loaded['core/scheduler']={
  after=function(delay,callback,key)tasks[key]={at=now+delay,callback=callback} end,
  cancel=function(key)tasks[key]=nil end}
 local provider={resolve_account_id=function()return account end}
 package.loaded['systems/player_profile_service']={
  get_provider=function()return provider end,
  get_profile=function()return {save={gameplay_stats={}},entitlements={}} end,
  refresh_player=function(_,_,success,failure)
   refreshes[#refreshes+1]={success=success,failure=failure};return {ok=true,pending=true}
  end}
 package.loaded['systems/match_setup_service']={get_session_id=function()return session end}
 package.loaded['systems/gameplay_phase_guard']={post_clear_frozen=function()return false end}
 PlayerResource={IsValidPlayerID=function(_,id)return id==0 end,IsFakeClient=function()return false end,
  GetPlayer=function()return {} end}
 CustomGameEventManager={Send_ServerToPlayer=function(_,_,name,result)
  sent[#sent+1]={name=name,result=result}
 end}
 Convars={GetStr=function()return 'fictional_transport_test_token' end}
 Time=function()return now end
 CreateHTTPRequestScriptVM=function()
  if mode=='create_throw' then error('fictional_native_exception_do_not_publish') end
  if mode=='create_nil' then return nil end
  local http={};requests[#requests+1]=http
  function http:SetHTTPRequestHeaderValue()
   if mode=='header_throw' then error('fictional_native_exception_do_not_publish') end
  end
  function http:SetHTTPRequestRawPostBody(_,raw)
   self.body=require('core/json_decoder').decode(raw)
   if mode=='body_throw' then error('fictional_native_exception_do_not_publish') end
  end
  function http:SetHTTPRequestAbsoluteTimeoutMS(value)
   check(value==30000,'native transport timeout remains 30 seconds')
   if mode=='timeout_throw' then error('fictional_native_exception_do_not_publish') end
  end
  function http:Send(callback)
   self.callback=callback
   if mode=='send_throw' then error('fictional_native_exception_do_not_publish') end
   if mode=='send_false' then return false end
   if mode=='send_true' then return true end
   return nil -- Current VScript bindings may expose native void.
  end
  return http
 end
 local service=assert(loadfile(source))()
 local function start(action,correlation)
  return service.handle({PlayerID=0,action=action or 'create',sku='transport_fixture',request_id=correlation or 'transport_request'})
 end
 local function advance(delta)
  local stop=now+delta
  while true do
   local key,job
   for candidate,value in pairs(tasks) do
    if value.at<=stop and (not job or value.at<job.at) then key,job=candidate,value end
   end
   if not job then break end
   tasks[key]=nil;now=job.at;job.callback()
  end
  now=stop
 end
 local function respond(http,state)
  http.callback({StatusCode=200,Body=encoder.encode({ok=true,sku='transport_fixture',order_id='synthetic_transport_order',state=state or 'pending'})})
 end
 return {start=start,advance=advance,respond=respond,sent=sent,requests=requests,tasks=tasks,refreshes=refreshes,
  mode=function(value)mode=value end,account=function(value)account=value end,session=function(value)session=value end,
  cash=function(value)cash=value end}
end

for _,mode in ipairs({'send_false','send_throw','header_throw','body_throw','timeout_throw','create_throw','create_nil'}) do
 local f=fixture(mode)
 local called,ok=pcall(f.start,'create','failed_attempt')
 check(called and not ok,mode..' must fail without leaking a native exception')
 check(#f.sent==1 and f.sent[1].result.error=='payment_unavailable',mode..' returns one fixed error')
 check(not encoder.encode(f.sent):find('fictional_native_exception_do_not_publish',1,true),'native error payload stays private')
 check(next(f.tasks)==nil,mode..' leaves no transport timer')
 f.advance(3600);f.mode('send_true');check(f.start('create','retry_attempt'),mode..' releases busy for retry')
 local latest=f.requests[#f.requests];f.respond(latest)
 check(f.sent[#f.sent].result.request_id=='retry_attempt' and f.sent[#f.sent].result.ok,'retry owns the response')
 if #f.requests>1 and f.requests[1].callback then
  local count=#f.sent;f.respond(f.requests[1],'delivered');check(#f.sent==count,'callback after failed Send is retired')
 end
end

for _,mode in ipairs({'send_nil','send_true'}) do
 local f=fixture(mode)
 check(f.start('create','accepted_request'),mode..' is a valid submission')
 f.advance(31);check(#f.sent==0,'native void/true waits for callback')
 f.respond(f.requests[1]);check(#f.sent==1 and f.sent[1].result.ok,'native callback settles once')
 f.respond(f.requests[1]);f.advance(40);check(#f.sent==1 and next(f.tasks)==nil,'duplicate callback and retired timer are inert')
end

do
 local f=fixture('send_nil');check(f.start('create','lost_request'))
 f.advance(32);check(#f.sent==1 and f.sent[1].result.error=='payment_unavailable','missing callback has a finite deadline')
 f.advance(2);check(f.start('create','newer_request'))
 local count=#f.sent;f.respond(f.requests[1],'delivered')
 check(#f.sent==count and #f.refreshes==0,'timeout callback cannot complete a newer request or refresh stale data')
 f.respond(f.requests[2]);check(f.sent[#f.sent].result.request_id=='newer_request','new request remains live')
end

do
 local f=fixture('send_nil');check(f.start('catalog','catalog_waiter_one'));check(f.start('catalog','catalog_waiter_two'))
 check(#f.requests==1,'catalogue reads coalesce')
 f.advance(32);check(#f.sent==2,'lost catalogue settles every waiter')
 check(f.sent[1].result.request_id=='catalog_waiter_one' and f.sent[2].result.request_id=='catalog_waiter_two','waiters keep correlation IDs')
end

do
 local f=fixture('send_nil');f.start('create','slow_delivery');f.advance(29);f.respond(f.requests[1],'delivered')
 check(f.tasks['payment_transport:0']==nil and f.tasks['payment_profile_refresh:0']~=nil,'profile refresh owns a separate deadline')
 f.advance(5);check(#f.sent==0,'transport timeout cannot interrupt accepted delivery refresh')
 f.refreshes[1].success();check(#f.sent==1 and f.sent[1].result.state=='delivered','delivery waits for authoritative profile')
 f.advance(40);check(#f.sent==1 and next(f.tasks)==nil,'successful profile retires both phases')
end

for _,binding in ipairs({'account','session'}) do
 local f=fixture('send_nil');f.start('create','old_binding')
 if binding=='account' then f.account('456') else f.session('payment_transport_session_2') end
 f.advance(2);check(f.start('create','new_binding'))
 local count=#f.sent;f.respond(f.requests[1],'delivered');check(#f.sent==count and #f.refreshes==0,'old '..binding..' callback cannot cross binding')
 f.respond(f.requests[2]);check(f.sent[#f.sent].result.request_id=='new_binding','new binding response remains live')
end

do
 local f=fixture('send_nil');f.start('create','old_session_deadline');f.session('payment_transport_session_2');f.advance(32)
 check(#f.sent==0,'deadline from a retired session is silent');f.advance(2);check(f.start('create','new_session_after_deadline'))
end

print('PAYMENT_TRANSPORT_LIFECYCLE_PASS checks='..checks..' real_gateway_calls=0')
