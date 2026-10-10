local M = {}

local subscribers = {}
local dispatch_snapshots = {}
local request_handlers = {}
local next_token = 0
-- Opaque identity changes on reset and module replacement; never recycle it.
local generation = {}
local dispatch = {depth = 0}

local function safe_call(handler, payload, event_name)
    local ok, result = pcall(handler, payload)
    if not ok then
        print(string.format("[EventBus] handler error event=%s error=%s", tostring(event_name), tostring(result)))
        return nil, result
    end
    return result, nil
end

function M.get_generation() return generation end

function M.reset()
    generation = {}
    subscribers = {}
    dispatch_snapshots = {}
    request_handlers = {}
    next_token = 0
    -- Active emissions retain their original subscriber snapshot, but work
    -- queued by that world cannot run after its subscriptions are discarded.
    dispatch = {depth = 0}
end

local function drain_after_dispatch(context)
    if context ~= dispatch or context.draining or not context.queue then return end
    context.draining = true
    local index = 1
    while context == dispatch and index <= #context.queue do
        local entry = context.queue[index]
        index = index + 1
        if context.pending[entry.key] == entry then
            context.pending[entry.key] = nil
            safe_call(entry.callback, nil, "after_dispatch:" .. tostring(entry.key))
        end
    end
    context.queue, context.pending, context.draining = nil, nil, nil
end

-- Finish dependent projections once all nested subscribers have committed
-- their data, in this same call stack. A key keeps its first queue position;
-- replacing it updates the callback without accumulating duplicate jobs.
function M.after_dispatch(key, callback)
    assert(key ~= nil, "after_dispatch key must not be nil")
    assert(type(callback) == "function", "callback must be a function")
    local context = dispatch
    if context.depth == 0 and not context.draining then
        return safe_call(callback, nil, "after_dispatch:" .. tostring(key))
    end
    if not context.queue then context.queue, context.pending = {}, {} end
    local entry = context.pending[key]
    if not entry then
        entry = {key = key}
        context.pending[key] = entry
        context.queue[#context.queue + 1] = entry
    end
    entry.callback = callback
end

function M.subscribe(event_name, handler)
    assert(type(event_name) == "string", "event_name must be a string")
    assert(type(handler) == "function", "handler must be a function")

    next_token = next_token + 1
    local token = next_token
    subscribers[event_name] = subscribers[event_name] or {}
    subscribers[event_name][token] = handler
    dispatch_snapshots[event_name] = nil
    return { event_name = event_name, token = token, generation = generation }
end

function M.unsubscribe(subscription)
    if not subscription then return end
    if subscription.generation ~= nil and subscription.generation ~= generation then return end
    local bucket = subscribers[subscription.event_name]
    if bucket then
        local existed = bucket[subscription.token] ~= nil
        bucket[subscription.token] = nil
        if existed then dispatch_snapshots[subscription.event_name] = nil end
    end
end

function M.emit(event_name, payload)
    local bucket = subscribers[event_name]
    if not bucket then return end

    local handlers = dispatch_snapshots[event_name]
    if not handlers then
        handlers = {}
        for _, handler in pairs(bucket) do
            table.insert(handlers, handler)
        end
        dispatch_snapshots[event_name] = handlers
    end

    local context = dispatch
    context.depth = context.depth + 1
    -- Every active emit owns this immutable snapshot. A callback may change
    -- subscriptions or emit recursively: the next emit sees a new snapshot,
    -- while this one still delivers its original handlers in the same order.
    for _, handler in ipairs(handlers) do
        safe_call(handler, payload or {}, event_name)
    end
    context.depth = context.depth - 1
    if context.depth == 0 then drain_after_dispatch(context) end
end

-- Diagnostic tools can wrap existing private callback slots without invoking
-- subscribe/unsubscribe. Explicit invalidation keeps those opt-in probes and
-- their restoration visible; normal emissions never rescan unchanged slots.
function M.invalidate_dispatch(event_name)
    if event_name == nil then dispatch_snapshots = {}
    else dispatch_snapshots[event_name] = nil end
end

function M.handle_request(event_name, handler)
    assert(type(event_name) == "string", "event_name must be a string")
    assert(type(handler) == "function", "handler must be a function")
    if request_handlers[event_name] then
        error("request handler already registered: " .. event_name)
    end
    request_handlers[event_name] = handler
end

function M.request(event_name, payload)
    local handler = request_handlers[event_name]
    if not handler then
        return nil, "no_request_handler:" .. tostring(event_name)
    end
    return safe_call(handler, payload or {}, event_name)
end

return M
