local M = {}

local tasks = {}
local next_id = 0
local initialized = false

local function now()
    return GameRules:GetGameTime()
end

local function remove_task(task_id)
    tasks[task_id] = nil
end

function M.after(delay, callback, task_id)
    assert(type(callback) == "function", "callback must be a function")
    next_id = next_id + 1
    local id = task_id or ("task_" .. tostring(next_id))
    tasks[id] = {
        run_at = now() + math.max(0, delay or 0),
        callback = callback,
    }
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
    remove_task(task_id)
end

function M.clear()
    tasks = {}
end

function M.think()
    local current = now()
    local due = {}
    for task_id, task in pairs(tasks) do
        if task.run_at <= current then
            table.insert(due, task_id)
        end
    end

    for _, task_id in ipairs(due) do
        local task = tasks[task_id]
        if task then
            remove_task(task_id)
            local ok, result = pcall(task.callback)
            if not ok then
                print("[Scheduler] task failed: " .. tostring(result))
            elseif type(result) == "number" and result >= 0 then
                task.run_at = now() + result
                tasks[task_id] = task
            end
        end
    end

    return 0.05
end

function M.init()
    if initialized then return end
    initialized = true
    GameRules:GetGameModeEntity():SetContextThink(
        "SurvivalSchedulerThink",
        function() return M.think() end,
        0.05
    )
end

return M
