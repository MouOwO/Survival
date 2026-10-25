-- Exercise the real commerce job state machine; no gateway or database calls.
package.path='scripts/vscripts/?.lua;'..package.path
local source=arg and arg[1] or 'scripts/vscripts/systems/commerce_service.lua'
local checks=0
local function check(value,message) checks=checks+1;assert(value,message) end
local function fixture()
 local now,account,session=0,'123','commerce_transport_session_1'
 local requests,sent,tasks={},{},{}
 local mode='pending'
 local function submit(payload,done,failed)
  requests[#requests+1]={payload=payload,done=done,failed=failed}
  if mode=='throw' then error('fictional_native_exception_do_not_publish') end
  if mode=='false' then return false end
 end
 local provider={resolve_account_id=function()return account end,archive_submit=submit}
 package.loaded['systems/player_profile_service']={get_provider=function()return provider end,get_profile=function()return {} end}
 package.loaded['systems/archive_http_adapter']={enabled=function()return true end,
  submit=function(_,command,done)return submit({command=command},done) end}
 package.loaded['systems/match_setup_service']={get_session_id=function()return session end}
 package.loaded['core/scheduler']={after=function(delay,callback,key)tasks[key]={at=now+delay,callback=callback} end,
  cancel=function(key)tasks[key]=nil end}
 PlayerResource={IsValidPlayerID=function()return true end,IsFakeClient=function()return false end,GetPlayer=function()return {} end}
 CustomGameEventManager={Send_ServerToPlayer=function(_,_,_,result)sent[#sent+1]=result end}
 Time=function()return now end
 local service=assert(loadfile(source))()
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
 local function start(action,token)
  return service.handle({PlayerID=0,action=action or 'purchase',sku='commerce_fixture',request_id=token or 'same_purchase_token'})
 end
 return {requests=requests,sent=sent,tasks=tasks,advance=advance,start=start,
  account=function(value)account=value end,session=function(value)session=value end,mode=function(value)mode=value end}
end
local success={ok=true,done=true,response={sku='commerce_fixture',currency='u_coin',price=100,balance=900}}

do
 local f=fixture();f.start('catalog','lost_catalog');f.advance(32)
 check(#f.sent==1 and f.sent[1].error=='commerce_busy' and not f.sent[1].terminal,'lost catalogue callback retires after 32s')
 check(f.sent[1].request_id=='lost_catalog' and next(f.tasks)==nil,'catalogue deadline retains correlation and cancels work')
 f.advance(1);f.start('catalog','catalog_retry');check(#f.requests==2,'manual catalogue retry is not permanently busy')
 f.requests[1].done({ok=true,products={},balances={u_coin=1}})
 check(#f.sent==1,'retired catalogue cannot publish into a newer read')
 f.requests[2].done({ok=true,products={{sku='commerce_fixture'}},balances={u_coin=900}})
 check(#f.sent==4 and f.sent[2].part=='begin' and f.sent[4].part=='end','current catalogue uses bounded begin/product/end')
end

do
 local f=fixture();f.start();f.advance(97)
 check(#f.requests==3 and #f.sent==0,'three independent provider deadlines remain valid through 97 seconds')
 f.advance(1);check(#f.sent==1 and not f.sent[1].terminal and f.sent[1].request_id=='same_purchase_token','lost purchase finishes nonterminal at 98s')
 local id=f.requests[1].payload.command.id
 for _,request in ipairs(f.requests) do check(request.payload.command.id==id,'recovery keeps the exact purchase operation ID') end
 check(next(f.tasks)==nil,'exhausted job leaves no maintenance timer')
 f.advance(1);f.start('purchase','same_purchase_token');check(#f.requests==4,'player retries the original operation')
 f.requests[1].done(success);check(#f.sent==1,'late callback cannot release the new job')
 f.requests[4].done(success);check(#f.sent==2 and f.sent[2].ok,'new query receives the existing operation outcome')
end

do
 local f=fixture();f.start();f.advance(31)
 f.requests[1].done({ok=false,error='archive_busy_retry'});f.advance(1)
 check(#f.requests==2,'first slow failure schedules the existing same-ID recovery')
 f.advance(30);check(#f.sent==0,'overall32s must not abort an allowed second transaction')
 f.requests[2].done(success)
 check(#f.sent==1 and f.sent[1].ok and next(f.tasks)==nil,'slow second attempt succeeds before its own deadline')
 f.requests[2].done(success);f.advance(100);check(#f.sent==1,'duplicate callback cannot duplicate success')
end

do
 local f=fixture();f.start();f.advance(33)
 check(#f.requests==2,'lost callback schedules recovery after its own 32s deadline')
 f.requests[1].done(success);check(#f.sent==0,'timed-out first attempt cannot settle its active retry')
 f.requests[2].done(success);check(#f.sent==1 and f.sent[1].ok,'current retry owns completion')
end

for _,mode in ipairs({'throw','false'}) do
 local f=fixture();f.mode(mode);local called=pcall(f.start)
 check(called,mode..' provider never leaks its exception')
 f.advance(2);check(#f.requests==3 and #f.sent==1 and not f.sent[1].terminal,'failed provider has bounded same-ID retries')
 check(f.sent[1].error=='commerce_busy' and next(f.tasks)==nil,'failure emits only a fixed error')
end

for _,binding in ipairs({'account','session'}) do
 local f=fixture();f.start()
 if binding=='account' then f.account('456') else f.session('commerce_transport_session_2') end
 f.advance(32);check(#f.sent==0 and next(f.tasks)==nil,'retired '..binding..' emits no old account data')
 f.advance(1);f.start('purchase','new_binding_token');check(#f.requests==2,'new binding can submit after retirement')
 f.requests[1].done(success);check(#f.sent==0,'old '..binding..' callback cannot release a newer job')
 f.requests[2].done(success);check(#f.sent==1 and f.sent[1].request_id=='new_binding_token','new binding owns its result')
end

print('COMMERCE_TRANSPORT_LIFECYCLE_PASS checks='..checks..' provider_deadline=32 max_purchase_wait=98 real_gateway_calls=0')
