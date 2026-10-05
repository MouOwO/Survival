package.path="scripts/vscripts/?.lua;"..package.path
local time,cpu,tools=0,0,false
Time=function() return time end
IsInToolsMode=function() return tools end
IsServer=function() return true end
local original_clock=os.clock
os.clock=function() return cpu end
local commands={}
Convars={RegisterCommand=function(_,name,callback) commands[name]=callback end}
GameRules={GetGameTime=function() return time end}
local profiler=require("core/scheduler_profile")
local scheduler=require("core/scheduler")
assert(commands.survival_perf_capture and not profiler.start(15))
tools=true
IsServer=function() return false end
assert(not profiler.start(2))
IsServer=function() return true end
local original_print=print;local logs={}
print=function(line) logs[#logs+1]=line end
assert(profiler.start(2) and not profiler.start(2))
scheduler.after(0,function() cpu=cpu+0.012 end,"slow_task")
scheduler.after(0,function() cpu=cpu+0.001 end,"fast_task")
for i=1,400 do scheduler.after(0,function() cpu=cpu+0.0001 end,"unique_"..i) end
assert(scheduler.think()==0.05)
time=2
assert(scheduler.think()==0.05 and profiler.begin_tick()==nil)
local output=table.concat(logs,"\n")
assert(output:find("done reason=complete clock=cpu_os_clock ticks=1",1,true))
assert(output:find("task=slow_task calls=1 total_ms=12.000 max_ms=12.000 errors=0",1,true))
assert(output:find("task=<other>",1,true) and #logs<=22)
assert(not profiler.stop())
assert(profiler.start(1))
scheduler.after(0,function() error("expected_profile_failure") end,"failed")
scheduler.think();commands.survival_perf_capture(nil,"stop")
assert(profiler.begin_tick()==nil)
assert(table.concat(logs,"\n"):find("task=failed calls=1 total_ms=0.000 max_ms=0.000 errors=1",1,true))
print=original_print;os.clock=original_clock
print("SCHEDULER_PROFILE_PASS tools-only opt-in, bounded aggregate rows/output, measured CPU costs, deadline stop, error reporting, manual stop")
