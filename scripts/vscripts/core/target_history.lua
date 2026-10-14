-- Strong entity keys preserve a living/dead-valid handle's history while
-- separating different entities that happen to reuse the same entindex.
local scheduler = require("core/scheduler")
local event_bus = require("core/event_bus")
local M = {}
local task_serial = 0

local function world()
    return GameRules and GameRules.GetGameModeEntity
        and GameRules:GetGameModeEntity() or GameRules or _G
end

local function now()
    return GameRules and GameRules.GetGameTime and GameRules:GetGameTime() or 0
end

function M.new(options)
    options = options or {}
    local values, groups = {}, {}
    local first, last, size = nil, nil, 0
    local epoch, task, task_token = {}, nil, nil
    local owning_world, owning_bus = world(), event_bus.get_generation()
    local budget = math.max(1, math.floor(tonumber(options.budget) or 64))
    local interval = tonumber(options.interval) or 0.25
    local store = {}

    local function append(node)
        node.next = nil
        if last then last.next = node else first = node end
        last = node
        size = size + 1
    end

    local function take()
        local node = first
        first = node.next
        if not first then last = nil end
        node.next = nil
        size = size - 1
        return node
    end

    function store:reset()
        local old_task = task
        -- Revoke ownership before cancellation or releasing strong references.
        epoch, task, task_token = {}, nil, nil
        values, groups = {}, {}
        first, last, size = nil, nil, 0
        if old_task then scheduler.cancel(old_task) end
    end

    local function ensure_task()
        if task then return end
        task_serial = task_serial + 1
        local id = (options.task_prefix or "target_history") .. ":" .. tostring(task_serial)
        local active_epoch, token = epoch, {}
        task, task_token = id, token
        local ok, error_value = pcall(scheduler.after, interval, function()
            if epoch ~= active_epoch or task_token ~= token then return false end
            local current_world, current_bus = world(), event_bus.get_generation()
            if epoch ~= active_epoch or task_token ~= token then return false end
            if current_world ~= owning_world or current_bus ~= owning_bus then
                -- This store belongs to the previous context. A newly initialized
                -- service owns a different store; never mutate its buckets.
                store:reset()
                return false
            end
            local current, steps = now(), math.min(budget, size)
            if epoch ~= active_epoch or task_token ~= token then return false end
            for _ = 1, steps do
                local node = take()
                local group, target = node.group, node.target
                local owned = groups[node.scope] == group and group.active
                    and group.nodes[target] == node
                local value = owned and group.values[target] or nil
                local retire = not owned or value == nil
                if not retire then
                    local valid_ok, removed = pcall(function() return target:IsNull() end)
                    retire = valid_ok and removed == true
                    if not retire and options.expired then
                        local expiry_ok, expired = pcall(options.expired, value, current)
                        retire = expiry_ok and expired == true
                    end
                end
                -- IsNull/expiry can reenter a reset in a native boundary or test.
                if epoch ~= active_epoch or task_token ~= token then return false end
                owned = groups[node.scope] == group and group.active
                    and group.nodes[target] == node
                if not owned then retire = true end
                if owned and group.values[target] ~= value then
                    -- A reentrant hit refreshed this record after it was read.
                    -- Keep that successor value registered for a later sweep.
                    value = group.values[target]
                    retire = value == nil
                end
                if retire then
                    if group.nodes[target] == node then group.nodes[target] = nil end
                    node.group, node.target, node.scope = nil, nil, nil
                    if owned and group.values[target] == value then
                        group.values[target] = nil
                    end
                else
                    append(node)
                end
            end
            if size == 0 then task, task_token = nil, nil; return false end
            return interval
        end, id)
        if not ok then
            task, task_token = nil, nil
            pcall(scheduler.cancel, id)
            -- History still exists. Registration on a later hit retries scheduling.
            return false, error_value
        end
        return true
    end

    function store:bucket(scope)
        local current_world, current_bus = world(), event_bus.get_generation()
        if current_world ~= owning_world or current_bus ~= owning_bus then
            self:reset()
            owning_world, owning_bus = current_world, current_bus
        end
        local group = groups[scope]
        if not group then
            local bucket = {}
            group = { active = true, values = bucket, nodes = {} }
            groups[scope], values[scope] = group, bucket
        end
        return group.values
    end

    function store:track(scope, target)
        local group = groups[scope]
        if not group then self:bucket(scope); group = groups[scope] end
        if not group.nodes[target] then
            local node = { scope = scope, group = group, target = target }
            group.nodes[target] = node
            append(node)
        end
        ensure_task()
    end

    function store:clear_scope(scope)
        local group = groups[scope]
        values[scope], groups[scope] = nil, nil
        if group then
            group.active = false
            group.values, group.nodes = {}, {}
        end
        -- Detached nodes are drained under the same fixed budget. They cannot
        -- erase a successor bucket for this player, even with the same handle.
    end

    function store:all_values() return values end
    function store:snapshot() return { pending = size, task = task } end
    return store
end

return M
