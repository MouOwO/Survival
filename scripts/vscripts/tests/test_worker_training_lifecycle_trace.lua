package.path = "scripts/vscripts/?.lua;" .. package.path
local Queue = require("systems/worker_training_queue_service")
local now, pending, traces, queue, fail, cancel_finish, throw_trace, completed
local function fixture()
    now, pending, traces, fail, cancel_finish, throw_trace, completed = 0, {}, {}, false, false, false, 0
    queue = Queue.create({now=function() return now end,capacity=7,
        schedule=function(delay,callback,id) pending[id]=callback end,
        cancel=function(id) pending[id]=nil end,
        validate=function() return true end,
        can_reserve=function() return {ok=true} end,
        reserve=function() return {ok=true} end,
        refund=function() end,changed=function() end,
        finish=function(job)
            if cancel_finish then queue:cancel_city(job.source_entindex,"cancel") end
            if fail then return {ok=false} end
            completed=completed+1
            return {ok=true,entindex=100+completed}
        end,
        trace=function(phase,job,result,generation)
            if throw_trace then error("diagnostic failure") end
            traces[#traces+1]={phase=phase,job=job.job_id,generation=generation,
                token=job._training_trace.request_token,paid=job.paid,
                result=result and result.entindex}
        end})
end
local function add(token)
    return queue:enqueue({source_entindex=10,player_id=0,team=2,training_id="train_lumberjack_01",duration=1,
        _training_trace=token and {request_token=token} or nil})
end
fixture()
for i=1,5 do assert(add(i).ok) end
assert(#traces==6,"five enqueue plus first paid start only")
for i=1,5 do
    now=i;local callback=assert(pending.worker_training_10 or pending["worker_training:10"])
    callback();callback()
end
assert(completed==5 and #traces==15,"exactly three stages per successful job; duplicate timers grant none")
local phases={}
for _,row in ipairs(traces)do
    phases[row.job]=phases[row.job]or{}
    assert(not phases[row.job][row.phase]);phases[row.job][row.phase]=true
    if row.phase=="start"then assert(row.paid)end
    if row.phase=="complete"then assert(row.result and row.result>0)end
end
fixture();assert(add(1).ok);local stale=pending["worker_training:10"]
queue:cancel_city(10,"cancel");now=1;stale()
assert(#traces==2 and completed==0,"cancelled job has no successful completion evidence")
fixture();assert(add(1).ok);fail=true;now=1;pending["worker_training:10"]()
assert(#traces==2 and completed==0,"failed spawn has no completion evidence")
fixture();assert(add(1).ok);cancel_finish=true;now=1;pending["worker_training:10"]()
assert(#traces==2,"synchronous source removal cannot credit a detached head")
fixture();assert(add().ok);now=1;pending["worker_training:10"]()
assert(completed==1 and #traces==0,"unattributed native/reward/auto input does not gain diagnostic provenance")
fixture();throw_trace=true;assert(add(1).ok);now=1;pending["worker_training:10"]()
assert(completed==1,"logging failure cannot alter gameplay")
fixture();assert(add(1).ok);local before=traces[1].generation;local stale=pending["worker_training:10"]
queue:reset();assert(add(1).ok);local after=traces[#traces].generation
assert(before~=after,"reset must distinguish reused local job IDs")
now=1;stale();assert(completed==0);pending["worker_training:10"]();assert(completed==1)
print("worker training lifecycle trace assertions passed; no native FPS measured")
