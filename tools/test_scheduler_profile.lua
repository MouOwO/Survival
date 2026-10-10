package.path="scripts/vscripts/?.lua;"..package.path
local time,cpu,tools,wall=0,0,false,0
Time=function() return time end
IsInToolsMode=function() return tools end
IsServer=function() return true end
local original_clock,original_time=os.clock,os.time
os.clock=function() return cpu end
os.time=function() return wall end
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
for i=1,200 do
    local id="distinct_"..string.char(65+math.floor((i-1)/26))..string.char(65+(i-1)%26)
    scheduler.after(0,function() end,id)
end
assert(scheduler.think()==0.05)
time=2
wall=2
assert(scheduler.think()==0.05 and profiler.begin_tick()==nil)
local output=table.concat(logs,"\n")
assert(output:find("done reason=complete clock=cpu_os_clock ticks=1",1,true))
assert(output:find("task=slow_task calls=1 total_ms=12.000 max_ms=12.000 errors=0",1,true))
assert(output:find("task=unique_* calls=400 total_ms=40.000",1,true),"dynamic sequence IDs share a useful bounded aggregate")
assert(output:find("task=<other>",1,true) and #logs<=22)
assert(not profiler.stop())
assert(profiler.start(1))
scheduler.after(0,function() error("expected_profile_failure") end,"failed")
scheduler.think();commands.survival_perf_capture(nil,"stop")
assert(profiler.begin_tick()==nil)
assert(table.concat(logs,"\n"):find("task=failed calls=1 total_ms=0.000 max_ms=0.000 errors=1",1,true))
GetSystemTimeMS=function() return cpu*1000 end
assert(profiler.start(1))
scheduler.after(0,function() cpu=cpu+0.021 end,"native_clock")
scheduler.think();profiler.stop("native_clock_test")
assert(table.concat(logs,"\n"):find("clock=engine_system_time_ms",1,true))
assert(table.concat(logs,"\n"):find("task=native_clock calls=1 total_ms=21.000",1,true),"native inline timing cannot use the frame-constant Time()")
assert(profiler.start(90))
local current=assert(profiler.begin_tick())
assert(current.seconds==90 and current.duration_clock=='wall_GetSystemTimeMS')
time=time+9999
assert(profiler.begin_tick()==current,'Advancing simulation time cannot end a real-wall capture')
cpu=cpu+89
assert(profiler.begin_tick()==current,'Paused/slow simulation still uses the full requested wall window')
cpu=cpu+1.1
assert(profiler.begin_tick()==nil,'90s wall deadline expires without advancing simulation')
assert(profiler.start(999) and profiler.begin_tick().seconds==120);profiler.stop('upper_bound')
assert(profiler.start(0) and profiler.begin_tick().seconds==1);profiler.stop('lower_bound')
assert(profiler.start(0/0) and profiler.begin_tick().seconds==15);profiler.stop('finite_bound')

local function advance(value) cpu=cpu+value end
local repeat_a=assert(loadstring('return function(advance) return function() advance(0.005) end end',
    '@fixture_repeat_a.lua'))()(advance)
local repeat_b=assert(loadstring('return function(advance) return function() advance(0.007) end end',
    '@fixture_repeat_b.lua'))()(advance)
local getinfo,getupvalue=debug.getinfo,debug.getupvalue
local source_reads=0
debug.getinfo=function(...) source_reads=source_reads+1;return getinfo(...) end
debug.getupvalue=function(...) source_reads=source_reads+1;return getupvalue(...) end
assert(profiler.start(2))
local a=scheduler.every(0,repeat_a)
local b=scheduler.every(0,repeat_b)
scheduler.think()
local first_reads=source_reads
assert(first_reads>0)
scheduler.think()
assert(source_reads==first_reads,'Repeated callbacks reuse cached source labels during a capture')
profiler.stop('repeat_sources')
output=table.concat(logs,'\n')
assert(output:find('task=fixture_repeat_a.lua:1 calls=2 total_ms=10.000',1,true))
assert(output:find('task=fixture_repeat_b.lua:1 calls=2 total_ms=14.000',1,true))
assert(not output:find('task=repeat_*',1,true),'Unrelated repeating closures must not collapse into repeat_*')
scheduler.think()
assert(source_reads==first_reads,'Disabled scheduling does not inspect callback sources')
scheduler.cancel(a);scheduler.cancel(b)
debug.getinfo,debug.getupvalue=getinfo,getupvalue
local reads=0;GetSystemTimeMS=function() reads=reads+1;return 0 end
scheduler.after(0,function() end);scheduler.think()
assert(reads==0,"disabled profiling adds no CPU clock reads")
GetSystemTimeMS=nil
print=original_print;os.clock=original_clock;os.time=original_time
print("SCHEDULER_PROFILE_PASS tools-only opt-in, bounded rows/output, 1-120s real-wall deadlines, measured costs, repeating callback sources, disabled zero-reflection/clock cost")
