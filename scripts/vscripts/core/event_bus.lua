local M = {}

local subscribers = {}
local request_handlers = {}
local next_token = 0

local function safe_call(handler, payload, event_name)
    local ok, result = pcall(handler, payload)
    if not ok then
        print(string.format("[EventBus] handler error event=%s error=%s", tostring(event_name), tostring(result)))
        return nil, result
    end
    return result, nil
end

function M.reset()
    subscribers = {}
    request_handlers = {}
    next_token = 0
end

function M.subscribe(event_name, handler)
    assert(type(event_name) == "string", "event_name must be a string")
    assert(type(handler) == "function", "handler must be a function")

    next_token = next_token + 1
    local token = next_token
    subscribers[event_name] = subscribers[event_name] or {}
    subscribers[event_name][token] = handler
    return { event_name = event_name, token = token }
end

function M.unsubscribe(subscription)
    if not subscription then return end
    local bucket = subscribers[subscription.event_name]
    if bucket then
        bucket[subscription.token] = nil
    end
end

function M.emit(event_name, payload)
    local bucket = subscribers[event_name]
    if not bucket then return end

    local handlers = {}
    for _, handler in pairs(bucket) do
        table.insert(handlers, handler)
    end

    for _, handler in ipairs(handlers) do
        safe_call(handler, payload or {}, event_name)
    end
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
