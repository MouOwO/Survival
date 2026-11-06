-- Actual isolated draft module; synthetic accounts, no Dota/network/files writes.
package.path='scripts/vscripts/?.lua;'..package.path
local draft=arg[1] or 'scripts/vscripts/systems/lottery_http_service.lua'
local events=setmetatable({},{__index=function(_,key)return key end})
local requests,handlers,subscribers,timers,emitted={},{},{},{},{}
local accounts,auth,loaded={[0]='100',[1]='101'},{},{}
local generation,session,mode,clock=1,'synthetic-session-1',nil,0
local counts={resolve=0,authenticated=0,loaded=0,timers=0,after=0}
local logs={};local real_print=print
print=function(line)logs[#logs+1]=line end
GetSystemTimeMS=function()return clock end
DoUniqueString=function()return 'synthetic-local' end
local provider={resolve_account_id=function(id)counts.resolve=counts.resolve+1;return accounts[id]end,
 lottery_catalog=function(payload,success,failure)requests[#requests+1]={payload=payload,success=success,failure=failure}end}
local bus={get_generation=function()return generation end,
 handle_request=function(key,fn)handlers[key]=fn end,
 subscribe=function(key,fn)subscribers[key]=fn end,
 emit=function(key,p)emitted[#emitted+1]={key=key,p=p}end}
package.loaded['systems/player_profile_service']={get_provider=function()return provider end,
 get_account_profile=function()return {revision=1}end,
 is_authenticated_for_account=function(id,account)counts.authenticated=counts.authenticated+1;return auth[id]==account end,
 is_loaded_for_account=function(id,account)counts.loaded=counts.loaded+1;return loaded[id]==account end}
package.loaded['systems/archive_http_adapter']={}
package.loaded['config/generated/archive_http_bundle']={hash=string.rep('a',64)}
package.loaded['config/generated/lottery_catalog_manifest']={config_hash=string.rep('a',64),catalog_md5=string.rep('b',32)}
package.loaded['core/event_bus']=bus
package.loaded['core/events']=events
package.loaded['core/ui_snapshot_delta']={}
package.loaded['systems/match_setup_service']={get_session_id=function()return session end,
 get_mode=function()return mode end,get_profile_mode=function()return mode end}
package.loaded['ui/compact_ui_transport']={is_bound=function()return true end,is_open=function()return false end}
package.loaded['ui/compact_profile_context']={current=function()return nil end}
package.loaded['config/generated/ui_static_catalog_lookup']={by_key={['lottery:state']=1},field_by_name={known=1,enabled=2,error_code=3}}
package.loaded['ui/compact_lottery_projection']={new=function()return {initialize=function()
 return {inspect=function()return {revision=1}end,full_ops=function()return {}end,
 filter=function()return {}end,update=function()return {}end,bind_intent=function()end}
end}end}
package.loaded['core/scheduler']={every=function(seconds,fn,key)
 assert(seconds==30);counts.timers=counts.timers+1;timers[key]=fn end,
 cancel=function(key)timers[key]=nil end,after=function()counts.after=counts.after+1;error('unexpected new timer')end}
local service=assert(loadfile(draft))()
local function event(id,revision)subscribers.PLAYER_PROFILE_CHANGED({player_id=id,revision=revision,account_id=accounts[id]})end
local function poll(n)for i=1,n or 1 do timers.lottery_catalog_poll()end end
local function finish(index,result,metadata)
 requests[index].success(result or {ok=true,config_hash=string.rep('a',64),catalog_md5=string.rep('b',32),unchanged=true},metadata)
end
local function request_count(n,why)assert(#requests==n,why..': '..#requests..' != '..n)end
service.init();poll(100);event(0)
request_count(0,'admission must not request')
assert(counts.resolve==1,'empty idle cannot inspect players')
local early
handlers.LOTTERY_CATALOG_REQUEST({md5='',complete=function(r)early=r end})
assert(early and early.error=='match_profile_not_ready','unready callback must settle immediately')
mode='standard';auth[0]='100';event(0);poll(100)
request_count(0,'authenticated without loaded profile')
loaded[0]='100';event(0,1)
request_count(1,'first real ready edge')
assert(requests[1].payload.account_id=='100','request must use ready owner')
for i=1,100 do event(0,1)end
request_count(1,'coalesce repeated ready events in flight')
finish(1,{ok=true,config_hash=string.rep('a',64),catalog_md5=string.rep('b',32),unchanged=true,
 http_status=403,response_bytes=99999999},{http_status=200,response_bytes=160})
assert(logs[#logs]:find('http_status=200 response_bytes=160',1,true),'only internal metadata supplies transport metrics')
local stable_resolves,stable_auth,stable_loaded=counts.resolve,counts.authenticated,counts.loaded
for i=1,100 do event(0,1)end
request_count(1,'stable ready events do not poll')
assert(counts.resolve==stable_resolves and counts.authenticated==stable_auth and counts.loaded==stable_loaded,
 'same-revision stable events must not cross identity/profile helpers')
poll();request_count(2,'existing refresh remains')
requests[2].failure('match_session_missing',409,51)
assert(logs[#logs]:find('failure=context_missing',1,true),'bounded failure classification')
assert(logs[#logs]:find('http_status=409 response_bytes=51',1,true),'failed response metadata is retained')
poll();request_count(3,'genuine failures retry on existing refresh')
finish(3,nil,{http_status='RAW_SECRET',response_bytes=-10})
assert(logs[#logs]:find('http_status=0 response_bytes=0',1,true) and not logs[#logs]:find('RAW_SECRET',1,true),'malformed metadata cannot enter logs')
auth[1]='101';loaded[1]='101';event(1)
request_count(3,'second ready user does not restart verified catalog')
auth[0]=nil;loaded[0]=nil;event(0)
poll();request_count(4,'fail over to indexed ready peer')
assert(requests[4].payload.account_id=='101')
finish(4)
auth[1]=nil;loaded[1]=nil;event(1)
local before=counts.resolve
poll(100);request_count(4,'all invalidated means zero HTTP')
assert(counts.resolve==before,'empty candidate index must not enumerate')
accounts[1]='102';auth[1]='102';loaded[1]='101';event(1);poll()
request_count(4,'slot reuse cannot inherit readiness')
loaded[1]='102';event(1);poll();request_count(5,'new valid account refresh')
assert(requests[5].payload.account_id=='102')
-- Late reply after a new session is ignored; next ready edge is not suppressed.
session='synthetic-session-2';mode=nil;auth={};loaded={};poll(100)
local before_emit=#emitted
finish(5);assert(#emitted==before_emit,'late session reply must not publish')
request_count(5,'new session admission zero HTTP')
mode='standard';auth[0]='100';loaded[0]='100';event(0)
request_count(6,'new session first ready edge')
finish(6)
-- Reload same textual session still retires the prior bus generation.
poll();request_count(7,'begin old-world request')
generation=2;mode=nil;auth={};loaded={};service.init();poll(100)
before_emit=#emitted;finish(7);assert(#emitted==before_emit,'old-world callback rejected')
request_count(7,'world reload admission zero HTTP')
mode='standard';auth[1]='102';loaded[1]='102';event(1)
request_count(8,'new world ready')
finish(8)
poll();request_count(9,'inflight slot binding')
accounts[1]='103';auth[1]=nil;loaded[1]=nil;event(1)
before_emit=#emitted;finish(9);assert(#emitted==before_emit,'late slot owner reply must not publish')
generation=3;session='synthetic-session-3';mode='standard';auth[1]='103';loaded[1]='103';service.init();event(1)
request_count(10,'new world ready read')
requests[10].failure('http_status_503')
for i=1,100 do event(1)end
request_count(10,'failed immediate edge cannot be spammed by profile events')
poll();request_count(11,'first ready failure still retries through existing refresh');finish(11)
poll();request_count(12,'real mismatch keeps classification')
finish(12,{ok=true,config_hash=string.rep('c',64),catalog_md5=string.rep('b',32),unchanged=true})
assert(logs[#logs]:find('failure=version_mismatch',1,true),'actual hash mismatch must stay visible')
assert(counts.timers==3 and counts.after==0,'one existing timer per world only')
real_print('CATALOG_ADMISSION_SERVICE_PASS requests=12 pre_ready_http=0 stable_ready_http=0 stable_revision_identity_calls=0 new_timers=0 stale_session=pass stale_world=pass stale_slot=pass multi_player=pass retry=pass hash_mismatch=visible')
