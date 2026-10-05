-- Opt-in aggregate profiling. Disabled scheduling reads no profiling clocks,
-- creates no task statistics and prints no per-callback diagnostic messages.
local M = {}
local capture
local MAX_TASK_ROWS = 128

local function clocks()
    local wall = rawget(_G,"Time")
    local cpu = os and os.clock
    if type(wall)~="function" then wall=cpu end
    if type(wall)~="function" then return nil end
    return wall, type(cpu)=="function" and cpu or wall,
        type(cpu)=="function" and "cpu_os_clock" or "engine_Time"
end

function M.start(seconds)
    if type(IsServer)=="function" and not IsServer() then return false,"server_only" end
    if not IsInToolsMode or not IsInToolsMode() then return false,"tools_only" end
    if capture then return false,"already_running" end
    local wall,measure,kind=clocks()
    if not wall then return false,"clock_unavailable" end
    capture={wall=wall,measure=measure,clock=kind,started=wall(),
        seconds=math.max(1,math.min(30,tonumber(seconds) or 15)),
        rows={},row_count=0,ticks=0,total=0,maximum=0}
    print("[SCHEDULER_PERF] started seconds="..tostring(capture.seconds).." clock="..kind)
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
    print(string.format("[SCHEDULER_PERF] done reason=%s clock=%s ticks=%d total_ms=%.3f max_tick_ms=%.3f",
        reason or "complete",completed.clock,completed.ticks,completed.total*1000,completed.maximum*1000))
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

function M.record(current,id,started,ok)
    if current~=capture then return end
    -- Fixed-size aggregate rows. Wave/attack IDs can otherwise create an
    -- unbounded table; excess IDs share a final bucket.
    id=tostring(id)
    if not current.rows[id] and current.row_count>=MAX_TASK_ROWS then id="<other>" end
    local row=current.rows[id]
    if not row then
        row={count=0,total=0,maximum=0,errors=0}
        current.rows[id]=row;current.row_count=current.row_count+1
    end
    local elapsed=math.max(0,current.measure()-started)
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
    end,"Aggregate scheduler task CPU costs for 1-30 seconds; use stop to cancel.",0)
end

return M
