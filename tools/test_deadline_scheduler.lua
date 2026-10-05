package.path="scripts/vscripts/?.lua;"..package.path
local Queue=require("core/deadline_queue")
local q=Queue.new()
local expected,serial={},0
math.randomseed(61005)
-- Check deadline and insertion order after mixed replacement/removal/pop.
for step=1,8000 do
    local id="job_"..math.random(1,150)
    local kind=math.random(1,4)
    if kind<=2 then
        serial=serial+1
        local task={run_at=math.random(0,20)}
        q:put(id,task);expected[id]={task=task,serial=serial}
    elseif kind==3 then q:remove(id);expected[id]=nil
    else
        local first
        for key,value in pairs(expected) do
            if not first or value.task.run_at<first.value.task.run_at
                or (value.task.run_at==first.value.task.run_at and value.serial<first.value.serial) then
                first={id=key,value=value}
            end
        end
        local popped=q:pop()
        assert((not first and not popped) or (popped.id==first.id and popped.task==first.value.task))
        if first then expected[first.id]=nil end
    end
    local count=0;for _ in pairs(expected) do count=count+1 end
    assert(q:count()==count)
end
q:clear()
for i=1,10000 do q:put("replace",{run_at=i}) end
assert(q:count()==1 and q:pop().task.run_at==10000 and q:count()==0)

local time,clock_calls=0,0
GameRules={GetGameTime=function() return time end}
Time=function() clock_calls=clock_calls+1;return time end
local original_clock=os.clock
os.clock=function() error("inactive profiler must not read CPU clocks") end
local scheduler=require("core/scheduler")
local fired=0
for i=1,1000 do scheduler.after(30,function() fired=fired+1 end,"future_"..i) end
local original_pairs=pairs
pairs=function() error("think and task_count must not scan pending tasks") end
for i=1,200 do time=i*0.05;assert(scheduler.think()==0.05) end
assert(scheduler.task_count()==1000 and fired==0 and clock_calls==0)
time=30;scheduler.think()
assert(fired==1000 and scheduler.task_count()==0)
pairs=original_pairs;os.clock=original_clock

-- Due batches are snapshots: an immediate task scheduled in a callback waits
-- until the next engine think, and a due task can be cancelled by a peer.
scheduler.clear();time=0
local calls={}
scheduler.after(0,function()
    calls[#calls+1]="a";scheduler.cancel("b")
    scheduler.after(0,function() calls[#calls+1]="c" end,"c")
    assert(scheduler.task_count()==1)
end,"a")
scheduler.after(0,function() calls[#calls+1]="b" end,"b")
scheduler.think();assert(table.concat(calls)=="a")
scheduler.think();assert(table.concat(calls)=="ac" and scheduler.task_count()==0)
local errors=0;local old_print=print
print=function() errors=errors+1 end
scheduler.after(0,function() error("expected") end,"error")
scheduler.after(0,function() fired=fired+1 end,"survivor")
scheduler.think();print=old_print
assert(errors==1 and fired==1001 and scheduler.task_count()==0)
-- Preserve the existing user's running-callback replacement/clear/init fixes.
scheduler.clear();time=0
local repeats,replacement=0,0
scheduler.every(0,function()
    repeats=repeats+1
    scheduler.after(1,function() replacement=replacement+1 end,"self")
end,"self")
scheduler.think();time=0.5;scheduler.think()
assert(repeats==1 and replacement==0 and scheduler.task_count()==1)
time=1;scheduler.think();assert(replacement==1 and scheduler.task_count()==0)
scheduler.every(0,function() repeats=repeats+1;scheduler.cancel("cancel_self") end,"cancel_self")
scheduler.think();scheduler.think();assert(repeats==2 and scheduler.task_count()==0)
scheduler.every(0,function()
    scheduler.clear();scheduler.after(0,function() replacement=replacement+1 end,"after_clear")
end,"clear_self")
scheduler.think();assert(scheduler.task_count()==1)
scheduler.think();assert(replacement==2 and scheduler.task_count()==0)
local installed={}
GameRules.GetGameModeEntity=function() return {SetContextThink=function(_,name,callback,delay)
    assert(name=="SurvivalSchedulerThink" and delay==0.05);installed[#installed+1]=callback
end} end
scheduler.init()
local old=installed[#installed]
scheduler.every(0,function()
    scheduler.init();scheduler.after(0,function() replacement=replacement+1 end,"new_world")
end,"reset_world")
assert(old()==0.05 and old()==nil and scheduler.task_count()==1)
assert(installed[#installed]()==0.05 and replacement==3 and scheduler.task_count()==0)
print("DEADLINE_SCHEDULER_PASS 8000 mixed queue operations, bounded replacement, zero idle scans/clocks, due snapshot, cancellation, errors")
