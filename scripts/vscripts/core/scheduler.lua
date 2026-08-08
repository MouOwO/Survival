local M = {}

local tasks = {}
local next_id = 0
local generation = 0

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

function M.task_count()
    local count = 0
    for _ in pairs(tasks) do count = count + 1 end
    return count
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
    -- Workshop Tools can keep required Lua modules alive between Run sessions
    -- while replacing the game-mode entity. Rebind the think every session and
    -- discard callbacks that belong to the previous game.
    tasks = {}
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
