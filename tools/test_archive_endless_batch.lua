package.path="scripts/vscripts/?.lua;"..package.path
local noop=function() end
local time, requests, provider, notifications=0,{},{},{}
GameRules={GetGameTime=function() return time end}
PlayerResource={GetPlayer=function() end,IsValidPlayerID=function() return false end}
CustomGameEventManager={RegisterListener=noop}
package.loaded["systems/player_profile_service"]={get_profile=function() end,get_provider=function() return {} end}
package.loaded["systems/title_presentation_service"]={init=noop}
package.loaded["systems/archive_online_clock"]={init=noop,disconnect=noop,flush=noop}
local bus,events=require("core/event_bus"),require("core/events")
local scheduler=require("core/scheduler")
local archive=require("systems/archive_service")
local depth,max_depth=0,0
local function setup(synchronous,legacy)
    time,requests,depth,max_depth,notifications=0,{},0,0,{}
    bus.reset();scheduler.clear();archive.init()
    bus.subscribe(events.UI_NOTIFICATION,function(payload) notifications[#notifications+1]=payload end)
    provider={submit=function(id,command,done)
        requests[#requests+1]={player=id,commands={command},time=time,done=done}
        if synchronous then done({ok=true}) end
    end}
    if not legacy then provider.submit_endless_batch=function(id,commands,done)
        depth=depth+1;max_depth=math.max(max_depth,depth)
        requests[#requests+1]={player=id,commands=commands,time=time,done=done}
        if synchronous then
            local results={};for _,command in ipairs(commands) do results[#results+1]={id=command.id,ok=true} end
            done({ok=true,results=results})
        end
        depth=depth-1
    end end
    archive.set_provider(provider)
end
local function tick(at) time=at;scheduler.think() end
local function record(first,last,id)
    for wave=first,last do assert(archive.record_endless_wave(id or 0,wave,10).ok) end
end
local function ack(request,fail_wave)
    local results={}
    for _,command in ipairs(request.commands) do
        results[#results+1]={id=command.id,ok=command.wave~=fail_wave}
    end
    request.done({ok=fail_wave==nil,results=results})
end
setup()
record(1,3)
assert(#requests==0 and archive.has_pending(0))
local original_after, held_schedules=scheduler.after,0
scheduler.after=function(delay,callback,key)
    if key=="archive_endless_flush:0" then held_schedules=held_schedules+1 end
    return original_after(delay,callback,key)
end
archive._test.flush(0)
scheduler.after=original_after
assert(held_schedules==1,"one held-queue flush updates its deadline timer only once")
tick(4.99);assert(#requests==0,"retry/profile routes cannot bypass the five-second gate")
tick(5);assert(#requests==1 and #requests[1].commands==3)
local first_id=requests[1].commands[1].id
record(4,4);tick(6);assert(#requests==1,"new waves cannot alter an in-flight immutable batch")
ack(requests[1]);assert(archive.has_pending(0))
tick(9.99);assert(#requests==1)
tick(10);assert(#requests==2 and #requests[2].commands==1 and requests[2].commands[1].wave==4)
ack(requests[2]);assert(not archive.has_pending(0))

setup();record(1,3);tick(5);record(4,4)
local concurrent_id=requests[1].commands[1].id:gsub(":1$",":4")
requests[1].done({ok=true,results={
    {id=requests[1].commands[1].id,ok=false,terminal=true,error="first_rejection"},
    {id=requests[1].commands[2].id,ok=false,terminal=true,error="second_rejection"},
    {id=concurrent_id,ok=true},
    {id="unknown_wave_receipt",ok=false,terminal=true,error="unknown_rejection"},
}})
assert(#notifications==1 and notifications[1].message=="first_rejection",
    "a batch with terminal per-wave errors reports its first matching rejection exactly once")
tick(10)
assert(#requests==2 and #requests[2].commands==2 and requests[2].commands[1].wave==3
    and requests[2].commands[2].wave==4,"missing and unknown acknowledgements cannot discard concurrent/new waves")
ack(requests[2]);assert(not archive.has_pending(0))

setup();record(1,3);tick(5)
local retry_id=requests[1].commands[2].id
ack(requests[1],2)
tick(10);assert(#requests==2 and #requests[2].commands==1)
assert(requests[2].commands[1].id==retry_id,"partial successes are acknowledged and failed waves keep their exact receipt ID")
requests[1].done({ok=true,results={{id=retry_id,ok=true}}})
assert(archive.has_pending(0),"late callbacks cannot clear the new attempt")
ack(requests[2]);assert(not archive.has_pending(0))

setup();record(1,1);tick(5)
local timeout_id=requests[1].commands[1].id
tick(40);tick(40.1);tick(42.1)
assert(#requests>=2 and requests[2].commands[1].id==timeout_id,"a lost entire reply retries the same durable wave ID")
ack(requests[#requests]);assert(not archive.has_pending(0))

setup();record(1,3);assert(archive.record_clear(0,"N10").ok)
assert(#requests==1 and requests[1].commands[1].kind=="clear","other archive intents remain available during the hold")
requests[1].done({ok=true});tick(5)
assert(#requests==2 and #requests[2].commands==3);ack(requests[2])

setup(true);record(1,80);tick(5)
assert(#requests==1 and #requests[1].commands==32 and archive.has_pending(0))
assert(requests[1].commands[1].wave==1 and requests[1].commands[32].wave==32,"batch order is numeric, not lexical")
archive.flush_endless_rewards(0)
assert(#requests==2 and #requests[2].commands==32)
tick(5);assert(#requests==3 and #requests[3].commands==16 and not archive.has_pending(0))
assert(max_depth==1,"synchronous finalization cannot recurse through multiple batches")

setup(true);record(1,3);bus.emit(events.PLAYER_DISCONNECTED,{player_id=0})
assert(#requests==1 and #requests[1].commands==3 and not archive.has_pending(0),"disconnect flushes the held batch")
setup(true);record(1,3);archive.begin_finalization()
assert(#requests==1 and not archive.has_pending(0),"final settlement flushes pending score before declaring saves finished")
assert(not archive.record_endless_wave(0,4,10).ok)

setup();record(1,3);tick(5);record(4,4);archive.flush_endless_rewards(0)
assert(#requests==1,"finish waits for an already in-flight batch")
ack(requests[1]);tick(5)
assert(#requests==2 and requests[2].commands[1].wave==4);ack(requests[2])

setup(true,true);record(1,3);tick(5)
assert(#requests==3 and not archive.has_pending(0),"old providers serially drain the complete bounded window")
for _,request in ipairs(requests) do assert(request.time==5) end
setup();record(1,1);archive.init();tick(5)
assert(#requests==0,"old-session timers cannot submit into a new map")
print("ARCHIVE_ENDLESS_BATCH_PASS: 5s batches, numeric order, 32-wave cap, partial/lost replies, immutable retries, purchases, forced finish/disconnect/finalization, old providers, reset")
