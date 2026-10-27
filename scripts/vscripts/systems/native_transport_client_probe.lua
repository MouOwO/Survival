-- Anonymous diagnostic only. Safe to load in client Lua: no server modules,
-- credentials, profiles, orders, or replacement of native HTTP factories.
local M = {}
local REVISION = "WS4-NATIVE-PROBE-01"
local URL = "https://pay.xiaofengnet.com/ws4-web/health"
local LATCH = "__survival_native_transport_probe_http01"
local LIMIT, SECONDS, TIMEOUT = 6, 160, 10
local FIELDS = {"event", "side", "api", "selected_api", "sample", "trigger", "nonce", "present", "factory",
    "global_type", "nested_type", "nested_lookup", "nested_callable",
    "handle", "send", "header", "timeout", "status", "available", "reason", "elapsed"}

local function clock()
    if type(Time) ~= "function" then return nil end
    local ok, value = pcall(Time)
    if ok and type(value) == "number" and value == value and value >= 0 and value < math.huge then return value end
end
local function side()
    local ok, server, client = pcall(function() return IsServer(), IsClient() end)
    if ok and server == true and client == false then return "server" end
    if ok and server == false and client == true then return "client" end
end
local function context()
    if not GameRules or type(GameRules.GetGameModeEntity) ~= "function" then return nil end
    local ok, value = pcall(GameRules.GetGameModeEntity, GameRules)
    return ok and value or nil
end
local function map_allowed()
    local ok, value = pcall(function() return GetMapName() end)
    return ok and value == "template_map"
end
local function valid_nonce(value)
    return type(value) == "string" and #value == 32 and value:match("^[a-f0-9]+$") ~= nil
end
local function scalar(value)
    if type(value) == "boolean" then return value and "true" or "false" end
    if type(value) == "number" and value == value and value > -math.huge and value < math.huge then return tostring(value) end
    if type(value) ~= "string" or #value > 40 or not value:match("^[A-Za-z0-9_]+$") then value = "unknown" end
    return '"' .. value .. '"'
end
local function emit(run, fields)
    fields.side = run.side
    fields.elapsed = math.max(0, math.min(SECONDS, math.floor((clock() or run.started) - run.started)))
    local out = {'"revision":"' .. REVISION .. '"'}
    for _, name in ipairs(FIELDS) do
        if fields[name] ~= nil then out[#out + 1] = '"' .. name .. '":' .. scalar(fields[name]) end
    end
    pcall(print, "[" .. REVISION .. "] {" .. table.concat(out, ",") .. "}")
end
local function current(run)
    local now = clock()
    return run.live and rawget(_G, LATCH) == run and side() == run.side and context() == run.mode
        and map_allowed() and now ~= nil and now >= run.started and now - run.started < SECONDS
end
local function stop(run, reason)
    if not run.live then return end
    run.live = false
    for _, pending in ipairs(run.pending) do pending.active = false end
    emit(run, {event = "stop", reason = reason, sample = run.samples})
end
local function method(handle, name)
    local ok, value = pcall(function() return handle[name] end)
    return ok and type(value) == "function" and value or nil
end
local function response_status(response)
    local ok, value = pcall(function() return type(response) == "table" and response.StatusCode or nil end)
    if ok and type(value) == "number" and value == math.floor(value) and value >= 0 and value <= 599 then return value end
    return 0
end
local function yhttp_factory()
    local owner = rawget(_G, "yhttp")
    local observed = {global_type = type(owner), nested_type = "not_read", nested_lookup = "not_table", nested_callable = false}
    if type(owner) == "function" then return owner, "yhttp_function", observed end
    if type(owner) ~= "table" then return nil, "yhttp", observed end
    -- DoDoTD exposes a table namespace. Read through its normal lookup so a
    -- lazy export works, but contain exceptions and never invoke __call or
    -- fall back to a caller-controlled name. No owner/self argument is added:
    -- the observed interface is yhttp.CreateHTTPRequestScriptVM(method, url).
    local found, factory = pcall(function() return owner.CreateHTTPRequestScriptVM end)
    observed.nested_lookup = found and "ok" or "throw"
    observed.nested_type = found and type(factory) or "unknown"
    observed.nested_callable = found and type(factory) == "function"
    return observed.nested_callable and factory or nil, "yhttp_scriptvm", observed
end
local function request(run, name, label, nonce, trigger)
    if not current(run) then return end
    local fields = {event = "request", api = label, sample = run.samples, trigger = trigger, nonce = nonce,
        present = false, factory = "missing", handle = "none", send = "not_attempted", header = "missing",
        timeout = "missing", status = 0, available = false}
    local factory
    if name == "yhttp" then
        local observed
        factory, fields.api, observed = yhttp_factory()
        label = fields.api
        for key, value in pairs(observed) do fields[key] = value end
        if observed.nested_lookup == "throw" then fields.factory = "lookup_throw" end
    else factory = rawget(_G, name) end
    if type(factory) ~= "function" then emit(run, fields); return end
    fields.present = true
    local ok, handle = pcall(factory, "GET", URL)
    fields.factory = ok and "ok" or "throw"
    if not ok then emit(run, fields); return end
    fields.handle = type(handle)
    if type(handle) ~= "table" and type(handle) ~= "userdata" then emit(run, fields); return end
    local send = method(handle, "Send")
    if not send then fields.send = "missing"; emit(run, fields); return end
    -- /health accepts no query parameters. Correlation is a harmless fixed
    -- header; absence of the header API never silently sends another request.
    local header = method(handle, "SetHTTPRequestHeaderValue")
    if not header then emit(run, fields); return end
    local set, accepted = pcall(header, handle, "X-WS4-Probe-Nonce", nonce)
    fields.header = not set and "throw" or accepted == false and "false" or "set"
    if not set or accepted == false then emit(run, fields); return end
    local timeout = method(handle, "SetHTTPRequestAbsoluteTimeoutMS")
    if timeout then
        local configured, value = pcall(timeout, handle, TIMEOUT * 1000)
        fields.timeout = not configured and "throw" or value == false and "false" or "set"
    end
    if not current(run) then return end
    local pending = {active = true, deadline = clock() + TIMEOUT, tick = run.ticks,
        sample = run.samples, api = label, nonce = nonce, trigger = trigger, sending = true}
    run.pending[#run.pending + 1] = pending
    local function finish(status)
        if not pending.active or not current(run) or clock() >= pending.deadline then return end
        pending.active = false
        local available = status >= 200 and status < 300
        if available then run.available = true end
        emit(run, {event = "callback", api = label, sample = pending.sample, trigger = trigger,
            nonce = nonce, status = status, available = available})
    end
    local sent, result = pcall(send, handle, function(response)
        if not pending.active or not current(run) then return end
        local status = response_status(response)
        if pending.sending then
            if pending.queued == nil then pending.queued = status end
        else finish(status) end
    end)
    pending.sending = false
    fields.send = not sent and "throw" or result == false and "false" or result == true and "true"
        or result == nil and "nil" or "other"
    if not sent or result == false then pending.active = false end
    emit(run, fields)
    if pending.active and pending.queued ~= nil then finish(pending.queued) end
end
local function generated_nonce(run)
    -- Diagnostic correlation, never an authorization challenge or credential.
    return string.format("%08x%08x%08x%08x", math.floor(run.started * 1000) % 4294967296,
        run.samples, run.side == "server" and 1 or 2, run.ticks)
end
local function sample(run, options)
    if not current(run) then return false, "context_unavailable" end
    if run.samples >= LIMIT then return false, "sample_limit" end
    local nonce = options.nonce
    if nonce ~= nil and not valid_nonce(nonce) then return false, "nonce_invalid" end
    local trigger = options.trigger or "manual"
    if type(trigger) ~= "string" or #trigger < 1 or #trigger > 24 or not trigger:match("^[a-z0-9_]+$") then
        return false, "trigger_invalid"
    end
    run.samples = run.samples + 1
    nonce = nonce or generated_nonce(run)
    if run.nonces[nonce] then run.samples = run.samples - 1; return false, "nonce_reused" end
    run.nonces[nonce] = true
    request(run, "CreateHTTPRequestScriptVM", "scriptvm", nonce, trigger)
    request(run, "CreateHTTPRequest", "legacy", nonce, trigger)
    if run.include_yhttp then request(run, "yhttp", "yhttp", nonce, trigger) end
    return true
end
local function phase()
    local ok, value = pcall(function() return GameRules:State_Get() end)
    if not ok then return nil end
    for _, item in ipairs({{"setup", "DOTA_GAMERULES_STATE_CUSTOM_GAME_SETUP"},
        {"pregame", "DOTA_GAMERULES_STATE_PRE_GAME"}, {"ingame", "DOTA_GAMERULES_STATE_GAME_IN_PROGRESS"}}) do
        if type(rawget(_G, item[2])) == "number" and value == rawget(_G, item[2]) then return item[1] end
    end
end

function M.inventory(options)
    -- Callable before a client timer/entity exists. Presence is observation
    -- only: no factory invocation, network request, or reachability claim.
    options = options or {}
    if type(options) ~= "table" then return false, "options_invalid" end
    local actual = side()
    if not actual or not map_allowed() then return false, "context_unavailable" end
    local run = {side = actual, started = clock() or 0}
    for _, entry in ipairs({{"CreateHTTPRequestScriptVM", "scriptvm"}, {"CreateHTTPRequest", "legacy"}, {"yhttp", "yhttp"}}) do
        local kind = type(rawget(_G, entry[1]))
        local fields = {event = "inventory", api = entry[2], present = kind == "function", factory = kind,
            send = "not_attempted", available = false, reason = "not_invoked"}
        if entry[1] == "yhttp" then
            fields.global_type, fields.nested_type = kind, "not_read"
            fields.nested_lookup, fields.nested_callable = "disabled", false
            -- Even harmless member lookup may execute a metatable. The
            -- optional namespace is never inspected beyond its raw global
            -- type unless the diagnostic operator explicitly opts in.
            if options.include_yhttp == true then
                local factory, label, observed = yhttp_factory()
                fields.selected_api, fields.present = label, factory ~= nil
                for key, value in pairs(observed) do fields[key] = value end
            end
        end
        emit(run, fields)
    end
    return true
end

function M.start(options)
    options = options or {}
    if type(options) ~= "table" then return false, "options_invalid" end
    local actual, started, mode = side(), clock(), context()
    if not actual or options.side and options.side ~= actual or not started or not mode or not map_allowed() then
        return false, "context_unavailable"
    end
    local prior = rawget(_G, LATCH)
    if type(prior) == "table" and prior.mode == mode then
        if prior.side ~= actual or not prior.live then return false, "run_finished" end
        return true
    end
    if type(prior) == "table" and prior.live then stop(prior, "context_changed") end
    -- The client VM may lack this API. Report that honestly and do not send
    -- requests without a working deadline owner. A root wrapper may retry
    -- later once its real game-mode context exists.
    local think = method(mode, "SetContextThink")
    if not think then return false, "timer_unavailable" end
    local run = {side = actual, mode = mode, started = started, live = true, ticks = 0, samples = 0,
        pending = {}, nonces = {}, phases = {}, delay = 1, automatic = options.automatic ~= false,
        include_yhttp = options.include_yhttp == true, available = false}
    rawset(_G, LATCH, run)
    local function tick()
        run.ticks = run.ticks + 1
        if not current(run) or run.ticks > SECONDS + 1 then stop(run, "boundary"); return nil end
        local now, active = clock(), 0
        for _, pending in ipairs(run.pending) do
            if pending.active and (now >= pending.deadline or run.ticks - pending.tick >= TIMEOUT) then
                pending.active = false
                emit(run, {event = "timeout", api = pending.api, sample = pending.sample, trigger = pending.trigger,
                    nonce = pending.nonce, status = 0, available = false})
            end
            if pending.active then active = active + 1 end
        end
        if run.samples >= LIMIT then
            if active == 0 then stop(run, "sample_limit"); return nil end
            return 1
        end
        if run.automatic then
            local selected, trigger = phase(), nil
            if run.samples == 0 then trigger = "initial"
            elseif selected and not run.phases[selected] then trigger = selected
            elseif ({5, 30})[run.delay] and now - started >= ({5, 30})[run.delay] then
                trigger = "delay"; run.delay = run.delay + 1
            end
            if trigger then
                if selected then run.phases[selected] = true end
                sample(run, {trigger = trigger})
            end
        end
        return 1
    end
    local scheduled, accepted = pcall(think, mode, "SurvivalNativeTransportProbe01", function()
        local ok, delay = pcall(tick)
        if not ok then stop(run, "internal"); return nil end
        return delay
    end, 0.1)
    if not scheduled or accepted == false then
        run.live = false
        if rawget(_G, LATCH) == run then rawset(_G, LATCH, nil) end
        return false, "timer_refused"
    end
    emit(run, {event = "start", sample = 0})
    return true
end

function M.sample(options)
    if type(options) ~= "table" then return false, "options_invalid" end
    if options.nonce ~= nil and not valid_nonce(options.nonce) then return false, "nonce_invalid" end
    local ok, reason = M.start({side = options.side, automatic = false, include_yhttp = options.include_yhttp})
    if not ok then return false, reason end
    return sample(rawget(_G, LATCH), options)
end
function M.stop()
    local run = rawget(_G, LATCH)
    if type(run) == "table" and run.side == side() then stop(run, "manual") end
end
function M.status()
    local run = rawget(_G, LATCH)
    if type(run) ~= "table" or run.side ~= side() or run.mode ~= context() then return {started = false} end
    return {started = true, live = current(run) == true, side = run.side, samples = run.samples,
        available = run.available == true, revision = REVISION}
end
return M
