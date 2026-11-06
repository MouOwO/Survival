-- The real HTTP lottery service and projection; only external IO is mocked.
-- No game-time advance, real account, HTTP request, Lua settlement or debit.
package.path='scripts/vscripts/?.lua;'..package.path
if arg[1] then
    package.preload['systems/lottery_http_service']=function()return assert(loadfile(arg[1]))()end
end
local bus,events=require('core/event_bus'),require('core/events')
bus.reset()
local session='synthetic_world_one'
local authenticated,loaded=false,false
local requests,timers,published={},{},{}
local traces,original_print={},print
local clock=100
GetSystemTimeMS=function()clock=clock+1;return clock end
print=function(line)
    assert(type(line)=='string' and line:find('^%[LOTTERY_CATALOG_STATE%] '),'only safe sparse catalog telemetry expected')
    traces[#traces+1]=line
end
local resolver_calls,snapshot_calls,settlement_calls=0,0,0
local seed=require('config/generated/lottery_catalog_manifest')
local bundle=require('config/generated/archive_http_bundle')
assert(seed.config_hash==bundle.hash,'real local seed must bind the actual bundle')
local lookup=require('config/generated/ui_static_catalog_lookup')
local function profile()
    if not loaded then return nil end
    return {schema_version=1,account_id='123',revision=1,mode='standard',match_session_id=session,
        save={archive={},gameplay_stats={},content_inventory={lottery_ticket=20,special_lottery_ticket=20}}}
end
local provider={
    resolve_account_id=function()resolver_calls=resolver_calls+1;return '123'end,
    lottery_catalog=function(payload,done,failed)
        requests[#requests+1]={payload=payload,done=done,failed=failed,session=session}
    end,
    lottery_snapshot=function()snapshot_calls=snapshot_calls+1;error('unexpected_snapshot_http')end,
}
package.loaded['systems/player_profile_service']={
    get_provider=function()return provider end,get_account_profile=profile,get_profile=profile,
    is_authenticated_for_account=function(id,account)return authenticated and id==0 and account=='123'end,
    is_loaded_for_account=function(id,account)return loaded and id==0 and account=='123'end,
}
package.loaded['systems/match_setup_service']={get_session_id=function()return session end,
    get_mode=function()return 'standard'end,get_profile_mode=function()return 'standard'end}
package.loaded['systems/archive_http_adapter']={submit=function()settlement_calls=settlement_calls+1;error('unexpected_paid_submit')end}
package.loaded['core/scheduler']={after=function()error('recovery_must_not_schedule_a_wait')end,
    every=function(seconds,callback,key)timers[key]={seconds=seconds,callback=callback}end,
    cancel=function(key)timers[key]=nil end}
package.loaded['ui/compact_ui_transport']={is_bound=function()return true end,is_open=function(_,view)return view==201 end,
    publish=function(id,view,ops,options)published[#published+1]={view=view,ops=ops,full=options.full}end}
local service=require('systems/lottery_http_service')
local function event(count)
    for _=1,count or 1 do bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=0,revision=1})end
end
local function succeed(request)
    request.done({ok=true,unchanged=true,catalog_md5=seed.catalog_md5,config_hash=bundle.hash},
        {http_status=200,response_bytes=160})
end
local function status()
    local ops=assert(service.compact_open(0,'map'))
    local state={}
    for _,op in ipairs(ops)do
        if op.record==lookup.by_key['lottery:state']then
            for _,key in ipairs({'known','enabled','error_code'})do
                if op.field==lookup.field_by_name[key]then state[key]=op.value end
            end
        end
    end
    return state
end
service.init()
assert(#requests==0,'unready startup must not send a catalog HTTP request')
assert(status().error_code==8,'missing catalog must not misreport an already-loaded account')
local unauth_traces=#traces
event(40);assert(#requests==0,'unauthenticated repeated events cannot send catalog requests')
loaded=true;event(40);assert(#requests==0,'loaded without authentication cannot trigger a request')
loaded=false;authenticated=true;event(40);assert(#requests==0,'authentication without loaded profile cannot trigger a request')
assert(#traces==unauth_traces,'unauthenticated repeated events cannot generate logs')
loaded=true;event()
assert(#requests==1,'profile-ready edge must request immediately without advancing 30 seconds')
local inflight_traces=#traces
event(100);assert(#requests==1,'ready events coalesce while catalog request is in flight')
assert(#traces==inflight_traces,'in-flight repeated events cannot generate logs')
succeed(requests[1]);assert(status().known==1 and status().enabled==1,'normal MD5 handshake restores projection')
local ready_resolves=resolver_calls
local ready_traces=#traces
event(100);assert(#requests==1,'verified catalog makes repeated profile events a network no-op')
assert(resolver_calls==ready_resolves,'verified catalog recovery path does not resolve account again')
assert(#traces==ready_traces,'verified catalog profile events generate zero logs')

-- A retained response from an old world cannot satisfy or change the new one.
local old_response=requests[1].done
bus.reset();session='synthetic_world_two';authenticated=false;loaded=false;service.init()
assert(#requests==1,'new unready world also sends no catalog HTTP')
local before_old_reply=#traces
old_response({ok=true,unchanged=true,catalog_md5=seed.catalog_md5,config_hash=bundle.hash})
assert(status().known==0,'old-world reply cannot install a catalog in a new world')
assert(#traces==before_old_reply,'stale reply cannot report ready for the current world')
authenticated=true;loaded=true;event(25)
assert(#requests==2,'a real ready edge coalesces its in-flight catalog without duplicate HTTP')
requests[2].failed('player_web_auth_pending')
event(25);assert(#requests==2,'failed ready requests cannot repeat on every profile event')
timers.lottery_catalog_poll.callback()
assert(#requests==3,'the existing bounded retry remains available after real failures')
succeed(requests[3]);assert(status().known==1)

-- One failed ready recovery does not turn subsequent profile revisions into a
-- request storm. The old bounded periodic fallback is still independently owned.
bus.reset();session='synthetic_world_three';authenticated=false;loaded=false;service.init()
assert(#requests==3)
authenticated=true;loaded=true;event();assert(#requests==4)
requests[4].failed('https://secret.invalid/?token=RAW_SECRET account=PRIVATE_ACCOUNT session=PRIVATE_SESSION',503,45)
local failed_traces=#traces
event(100);assert(#requests==4,'failed ready recovery is not automatically replayed per profile event')
assert(#traces==failed_traces,'failed ready recovery does not log on every repeated profile')
assert(timers.lottery_catalog_poll.seconds==30,'existing periodic fallback remains unchanged')
timers.lottery_catalog_poll.callback();assert(#requests==5);succeed(requests[5])

-- The new event trigger must retain the remote-version protection: a server
-- catalog inconsistent with the pinned seed remains disabled, without a draw.
bus.reset();session='synthetic_world_four';authenticated=false;loaded=false;service.init()
assert(#requests==5)
authenticated=true;loaded=true;event();assert(#requests==6)
local mismatch=seed.catalog_md5==string.rep('a',32)and string.rep('b',32)or string.rep('a',32)
requests[6].done({ok=true,catalog_md5=mismatch,config_hash=bundle.hash,catalog_json='{}'})
local mismatch_status=status()
assert(mismatch_status.known==0 and mismatch_status.enabled==0 and mismatch_status.error_code==6,
    'event recovery cannot bypass catalog MD5/version guard')
local denied=service.compact_draw(0,'map',1,1)
assert(denied.ok==false and denied.error=='lottery_config_refresh_required')
assert(snapshot_calls==0 and settlement_calls==0,'catalog recovery is read-only and never fetches player snapshot or draws')
local stages={waiting_profile=true,profile_ready=true,scope_reset=true,ready=true,failure=true}
local failures={none=true,profile_not_ready=true,auth_pending=true,unclassified=true,version_mismatch=true}
local have={}
for _,line in ipairs(traces)do
    local stage,generation,elapsed,config_ok,md5_ok,failure,status,bytes=line:match('^%[LOTTERY_CATALOG_STATE%] stage=([a-z_]+) generation=(%d+) elapsed_ms=([%-0-9]+) config_match=(%a+) md5_match=(%a+) failure=([a-z_]+) http_status=(%d+) response_bytes=(%d+)$')
    assert(stages[stage] and tonumber(generation) and tonumber(elapsed)>=-1 and failures[failure],'telemetry must use a fixed safe schema')
    assert(tonumber(status)<=599 and tonumber(bytes)<=33554432,'transport metrics must be bounded integers')
    assert((config_ok=='true'or config_ok=='false')and(md5_ok=='true'or md5_ok=='false'))
    assert(not line:find('RAW_SECRET',1,true)and not line:find('PRIVATE_ACCOUNT',1,true)and not line:find('PRIVATE_SESSION',1,true))
    assert(not line:find(bundle.hash,1,true)and not line:find(seed.catalog_md5,1,true),'telemetry cannot disclose hashes')
    have[stage]=true
end
for stage in pairs(stages)do assert(have[stage],'exercise telemetry stage '..stage)end
assert(require('ui/compact_lottery_projection').error_text[8]=='奖池配置尚未同步，请稍候')
print=original_print
print('LOTTERY_PROFILE_CATALOG_RECOVERY_PASS: immediate ready edge; no repeated HTTP/logs; stale world rejected; MD5 protected; catalog-specific message; safe lifecycle timing; paid submits=0')
