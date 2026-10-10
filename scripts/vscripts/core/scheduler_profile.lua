-- Opt-in aggregate profiling. Disabled scheduling reads no profiling clocks,
-- creates no task statistics and prints no per-callback diagnostic messages.
local M = {}
local capture
local MAX_TASK_ROWS = 128

local function finite(value)
    return type(value)=="number" and value==value and value~=math.huge and value~=-math.huge
end

local function clocks()
    local system=rawget(_G,"GetSystemTimeMS")
    local cpu = os and os.clock
    if type(system)=="function" then
        local ok,value=pcall(system)
        if ok and finite(value) then
            local wall=function() return system()/1000 end
            return wall,wall,"engine_system_time_ms","wall_GetSystemTimeMS"
        end
    end
    -- Time() is simulation time and may advance much more slowly under load.
    -- CPU time is only for measuring callbacks, never the capture deadline.
    local wall=os and os.time
    if type(wall)~="function" or type(cpu)~="function" then return nil end
    return wall,cpu,"cpu_os_clock","coarse_wall_os_time"
end

function M.start(seconds)
    if type(IsServer)=="function" and not IsServer() then return false,"server_only" end
    if not IsInToolsMode or not IsInToolsMode() then return false,"tools_only" end
    if capture then return false,"already_running" end
    local wall,measure,kind,duration_clock=clocks()
    if not wall then return false,"clock_unavailable" end
    seconds=tonumber(seconds)
    capture={wall=wall,measure=measure,clock=kind,duration_clock=duration_clock,started=wall(),
        seconds=math.max(1,math.min(120,finite(seconds) and seconds or 15)),
        rows={},row_count=0,ticks=0,total=0,maximum=0,
        callback_labels=setmetatable({},{__mode="k"})}
    print("[SCHEDULER_PERF] started seconds="..tostring(capture.seconds).." clock="..kind.." duration_clock="..duration_clock)
    return true
end

function M.stop(reason)
    local completed=capture
    if not completed then return false end
    capture=nil
    local rows={}
    for id,row in pairs(completed.rows) do rows[#rows+1]={id=id,row=row} end
    table.sort(rows,function(a,b)
        if a.row.total==b.row.total then return a.id<b.id end
        return a.row.total>b.row.total
    end)
    print(string.format("[SCHEDULER_PERF] done reason=%s clock=%s ticks=%d total_ms=%.3f max_tick_ms=%.3f duration_clock=%s wall_seconds=%.3f",
        reason or "complete",completed.clock,completed.ticks,completed.total*1000,completed.maximum*1000,
        completed.duration_clock,math.max(0,completed.wall()-completed.started)))
    for i=1,math.min(20,#rows) do
        local entry=rows[i];local row=entry.row
        print(string.format("[SCHEDULER_PERF] task=%s calls=%d total_ms=%.3f max_ms=%.3f errors=%d",
            entry.id,row.count,row.total*1000,row.maximum*1000,row.errors))
    end
    return true
end

function M.begin_tick()
    local current=capture
    if current and current.wall()-current.started>=current.seconds then
        M.stop("complete");return nil
    end
    return current
end

local function callback_label(current,callback,is_repeat)
    local cached=current.callback_labels[callback]
    if cached then return cached end
    local ok,info=pcall(debug.getinfo,callback,"Sl")
    if not ok or not info then return nil end
    local path=(info.source or info.short_src or "callback"):gsub("\\","/")
    -- scheduler.every wraps the real callback. Inspect its known closure only
    -- during capture; never scan tasks or alter dispatch/delay when disabled.
    if is_repeat and path:match("core/scheduler%.lua$") and debug.getupvalue then
        for index=1,16 do
            local read,name,value=pcall(debug.getupvalue,callback,index)
            if not read or not name then break end
            if name=="callback" and type(value)=="function" then
                local inner_ok,inner=pcall(debug.getinfo,value,"Sl")
                if inner_ok and inner then info=inner end
                break
            end
        end
    end
    -- A loadstring source can contain an entire command. Never dump its code
    -- (or credentials); only file-backed sources retain their complete path.
    local raw_source=info.source or ""
    local source=(raw_source:sub(1,1)=="@" and raw_source:sub(2)
        or (info.what=="C" and "native_callback" or "anonymous_lua_callback"))
        :sub(1,256):gsub("[%z\1-\31\127]","?")
    local label=source..":"..tostring(info.linedefined or 0)
    current.callback_labels[callback]=label
    return label
end

function M.record(current,id,started,ok,callback)
    if current~=capture then return end
    -- Fixed-size aggregate rows. Wave/attack IDs can otherwise create an
    -- unbounded table; excess IDs share a final bucket.
    local elapsed=math.max(0,current.measure()-started)
    id=tostring(id)
    local anonymous_task=id:match("^task_%d+$")
    local anonymous_repeat=id:match("^repeat_%d+$")
    if (anonymous_task or anonymous_repeat) and debug and debug.getinfo and type(callback)=="function" then
        id=callback_label(current,callback,anonymous_repeat~=nil) or (anonymous_repeat and "repeat_*" or "task_*")
    else
        id=id:gsub("%d+","*")
    end
    if not current.rows[id] and current.row_count>=MAX_TASK_ROWS then id="<other>" end
    local row=current.rows[id]
    if not row then
        row={count=0,total=0,maximum=0,errors=0}
        current.rows[id]=row;current.row_count=current.row_count+1
    end
    row.count=row.count+1;row.total=row.total+elapsed
    row.maximum=math.max(row.maximum,elapsed)
    if not ok then row.errors=row.errors+1 end
end

function M.end_tick(current,started)
    if current~=capture then return end
    local elapsed=math.max(0,current.measure()-started)
    current.ticks=current.ticks+1;current.total=current.total+elapsed
    current.maximum=math.max(current.maximum,elapsed)
end

if (type(IsServer)~="function" or IsServer())
    and Convars and type(Convars.RegisterCommand)=="function" then
    Convars:RegisterCommand("survival_perf_capture",function(_,seconds)
        if seconds=="stop" then M.stop("manual");return end
        local ok,reason=M.start(seconds)
        if not ok then print("[SCHEDULER_PERF] unavailable reason="..tostring(reason)) end
    end,"Aggregate scheduler task costs for 1-120 real seconds; use stop to cancel.",0)
end

return M
