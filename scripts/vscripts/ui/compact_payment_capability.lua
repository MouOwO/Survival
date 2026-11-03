-- Private presentation capability. The payment service retains every actor,
-- account/profile/PWA check; this bridge never creates an order or grants cash.
local M = {}
function M.new(o)
    local record = o.lookup.by_key["payment:capability"]
    if not record then return nil, "payment_compact_schema_missing" end
    local F = o.lookup.field_by_name
    assert(F.known and F.enabled and F.request_token, "payment_compact_fields_missing")
    local players, live = {}, true
    local function active() return live and (not o.current or o.current()) end
    local function owner(id)
        if not active() then return nil end
        local scope = o.scope(id)
        if not scope then players[id] = nil; return nil end
        local state = players[id]
        if not state or state.scope ~= scope then
            state = { scope = scope, used = {}, token = nil, sent = nil }
            players[id] = state
        end
        return state
    end
    local function unknown(id)
        local state = owner(id)
        if not state then return nil end
        state.sent = nil
        return { {record = record, field = F.known, value = 0} }
    end
    local function intent(id, action, args)
        if action ~= "payment_capability" or not o.transport.is_open(id, 9) then return nil end
        if args.arg_a ~= nil or args.arg_b ~= nil or args.arg_c ~= nil then return nil, "payment_capability_args_forbidden" end
        local token, alias = args.request_token, args.session_token
        if type(token) ~= "number" or token ~= math.floor(token) or token < 1 or token > 16383
            or type(alias) ~= "number" or alias ~= math.floor(alias) or alias < 1 or alias > 16383 then return nil, "payment_capability_token_invalid" end
        local state = owner(id)
        if not state then return nil end
        if state.used[token] then return {duplicate = true} end
        state.used[token] = true; state.token = token
        local scope = state.scope
        return o.evaluate(id, token, function(enabled)
            if not active() or players[id] ~= state or state.token ~= token
                or not o.scope_current(scope) or not o.transport.is_open(id, 9) then return false end
            enabled = enabled == true
            if state.sent and state.sent.token == token and state.sent.enabled == enabled then return true end
            local changes = {}
            if not state.sent then changes[#changes+1] = {record = record, field = F.known, value = 1} end
            if not state.sent or state.sent.enabled ~= enabled then
                changes[#changes+1] = {record = record, field = F.enabled, value = enabled and 1 or 0}
            end
            if not state.sent or state.sent.token ~= token then
                changes[#changes+1] = {record = record, field = F.request_token, value = token}
            end
            -- A fresh token is an authoritative re-evaluation even when its
            -- bool is unchanged. Atomic typed state retains that verified bool.
            local result = o.transport.publish(id, 9, changes, {priority = true})
            if result ~= nil and result ~= false then state.sent = {token = token, enabled = enabled} end
            return result
        end)
    end
    o.transport.register_view(9, {open = unknown, snapshot = unknown, intent = intent,
        close = function(id) local state = players[id]; if state then state.sent = nil end end})
    return {dispose = function() live = false; players = {} end,
        inspect = function(id) local state = players[id]; return state and {token = state.token, sent = state.sent ~= nil} or {} end}
end
return M
