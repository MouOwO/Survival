local M = {}
local deadline_queue = require("core/deadline_queue").new()
local profiler = require("core/scheduler_profile")

local tasks = {}
local running_tasks = {}
local next_id = 0
local generation = 0
local task_generation = 0
local pending_count = 0

local function now()
    return GameRules:GetGameTime()
end

local function remove_task(task_id)
    if tasks[task_id] then pending_count = pending_count - 1 end
    tasks[task_id] = nil
    deadline_queue:remove(task_id)
end

function M.after(delay, callback, task_id)
    assert(type(callback) == "function", "callback must be a function")
    next_id = next_id + 1
    local id = task_id or ("task_" .. tostring(next_id))
    if not tasks[id] then pending_count = pending_count + 1 end
    tasks[id] = {
        run_at = now() + math.max(0, delay or 0),
        callback = callback,
    }
    deadline_queue:put(id, tasks[id])
    return id
end

function M.every(interval, callback, task_id)
    local id = task_id or ("repeat_" .. tostring(next_id + 1))
    return M.after(interval, function()
        local result = callback()
        if result == false then
            return false
        end
        return interval
    end, id)
end

function M.cancel(task_id)
    local pending, running = tasks[task_id], running_tasks[task_id]
    if pending then pending.cancelled = true end
    if running then running.cancelled = true end
    remove_task(task_id)
end

function M.clear()
    tasks = {}
    deadline_queue:clear()
    pending_count = 0
    -- Invalidate callbacks currently running without stopping the installed
    -- engine think. Its separate generation only changes on init().
    task_generation = task_generation + 1
end

function M.task_count()
    return pending_count
end

function M.think()
    local current = now()
    local active_generation = task_generation
    local profile = profiler.begin_tick()
    local started = profile and profile.measure()
    local due
    local first = deadline_queue:peek()
    while first and first.task.run_at <= current do
        due = due or {}
        due[#due + 1] = deadline_queue:pop()
        first = deadline_queue:peek()
    end
    if not due then
        if profile then profiler.end_tick(profile, started) end
        return 0.05
    end

    for _, entry in ipairs(due) do
        local task_id, task = entry.id, entry.task
        -- Another due callback can replace this ID with a later task. Only
        -- the exact object that was due at the start belongs to this batch.
        if task_generation == active_generation and tasks[task_id] == task then
            remove_task(task_id)
            running_tasks[task_id] = task
            local task_started = profile and profile.measure()
            local ok, result = pcall(task.callback)
            if profile then profiler.record(profile, task_id, task_started, ok) end
            if running_tasks[task_id] == task then running_tasks[task_id] = nil end
            if not ok then
                print("[Scheduler] task failed: " .. tostring(result))
            elseif task_generation == active_generation and not task.cancelled
                and tasks[task_id] == nil and type(result) == "number" and result >= 0 then
                -- An explicit after() inside the callback owns the next run.
                -- Do not overwrite it with the callback's repeat interval.
                task.run_at = now() + result
                tasks[task_id] = task
                pending_count = pending_count + 1
                deadline_queue:put(task_id, task)
            end
        end
    end
    if profile then profiler.end_tick(profile, started) end

    return 0.05
end

function M.init()
    -- Workshop Tools can keep required Lua modules alive between Run sessions
    -- while replacing the game-mode entity. Rebind the think every session and
    -- discard callbacks that belong to the previous game.
    M.clear()
    profiler.stop("world_reset")
    next_id = 0
    generation = generation + 1
    local current_generation = generation
    GameRules:GetGameModeEntity():SetContextThink(
        "SurvivalSchedulerThink",
        function()
            if current_generation ~= generation then
                return nil
            end
            return M.think()
        end,
        0.05
    )
end

return M
