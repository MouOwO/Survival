-- Bounded, anonymous transport diagnostics for the restricted production test.
-- The local service maps this parameter-free GET to its read-only health route.
local M = {}
local URL = "https://pay.xiaofengnet.com/ws4-web/health"
local PREFIX = "[WS4-MP-10] "
local LATCH = "__survival_ws4_mp10_network_probe"
local MAX_SAMPLES, MAX_SECONDS, TIMEOUT = 8, 300, 8
local DELAYS = { 5, 30, 120, 240 }
local FIELDS = { "event", "api", "sample", "trigger", "elapsed", "phase", "state", "map",
    "server", "dedicated", "tools", "present", "factory", "request", "send", "timeout",
    "status", "reason", "limit_samples", "limit_seconds" }

local function clock()
    if type(Time) ~= "function" then return nil end
    local ok, value = pcall(Time)
    if ok and type(value) == "number" and value == value and value >= 0 and value < math.huge then return value end
end

local function boolean_api(name)
    local api = rawget(_G, name)
    if type(api) ~= "function" then return "unknown" end
    local ok, value = pcall(api)
    if ok and value == true then return "true" end
    if ok and value == false then return "false" end
    return "unknown"
end

local function permitted()
    local ok, allowed = pcall(function()
        if type(IsServer) ~= "function" or IsServer() ~= true
            or type(IsClient) ~= "function" or IsClient() ~= false
            or type(GetMapName) ~= "function" or GetMapName() ~= "template_map" then return false end
        local profile = require("config/release_profile")
        if type(profile) ~= "table" or profile.channel ~= "production" then return false end
        local auth = require("config/player_web_auth")
        if type(auth) ~= "table" then return false end
        if auth.enabled ~= true then
            -- A configured native match may observe anonymous transport without
            -- enabling web-auth, profiles, commerce or any persistence route.
            -- Never configure the provider here: its own live guard must pass.
            if auth.enabled ~= false then return false end
            local config = require("config/session_multiplayer_test")
            local session = package.loaded["systems/session_multiplayer_test"]
            if type(config) ~= "table" or config.enabled ~= true or config.expected_map ~= "template_map"
                or type(session) ~= "table" or type(session.is_enabled) ~= "function"
                or session.is_enabled() ~= true then return false end
        end
        local offline = package.loaded["debug/offline_logic_test"]
        if offline and (type(offline.is_enabled) ~= "function" or offline.is_enabled() ~= false) then return false end
        if Convars and type(Convars.GetStr) == "function"
            and Convars:GetStr("survival_offline_logic_test") == "1" then return false end
        local access = require("core/test_access_policy")
        return type(access) == "table" and type(access.enabled) == "function" and access.enabled() == true
            and type(access.enforce_connected) == "function" and access.enforce_connected() == true
    end)
    return ok and allowed == true
end

local function context()
    if not GameRules or type(GameRules.GetGameModeEntity) ~= "function" then return nil end
    local ok, mode = pcall(GameRules.GetGameModeEntity, GameRules)
    return ok and mode or nil
end

local function phase()
    local ok, state = pcall(function() return GameRules:State_Get() end)
    if not ok or type(state) ~= "number" or state ~= math.floor(state) or state < 0 or state > 32 then
        return "unknown", -1
    end
    for _, item in ipairs({ { "setup", "DOTA_GAMERULES_STATE_CUSTOM_GAME_SETUP" },
        { "pregame", "DOTA_GAMERULES_STATE_PRE_GAME" }, { "ingame", "DOTA_GAMERULES_STATE_GAME_IN_PROGRESS" } }) do
        if type(rawget(_G, item[2])) == "number" and state == rawget(_G, item[2]) then return item[1], state end
    end
    return "other", state
end

local function json_value(value)
    if type(value) == "boolean" then return value and "true" or "false" end
    if type(value) == "number" and value == value and value > -math.huge and value < math.huge then return tostring(value) end
    if type(value) ~= "string" or #value > 32 or not value:match("^[A-Za-z0-9_]+$") then value = "unknown" end
    return '"' .. value .. '"'
end

local function emit(run, fields)
    fields.phase, fields.state = phase()
    fields.elapsed = math.min(MAX_SECONDS, math.max(0, math.floor((clock() or run.started) - run.started)))
    fields.map, fields.server = "template_map", true
    fields.dedicated, fields.tools = boolean_api("IsDedicatedServer"), boolean_api("IsInToolsMode")
    local encoded = {}
    for _, name in ipairs(FIELDS) do
        if fields[name] ~= nil then encoded[#encoded + 1] = '"' .. name .. '":' .. json_value(fields[name]) end
    end
    pcall(print, PREFIX .. "{" .. table.concat(encoded, ",") .. "}")
end

local function complete_sample(run, sample, available)
    local observed = run.observation
    if not observed or observed.sample ~= sample or observed.remaining <= 0 then return end
    observed.remaining = observed.remaining - 1
    if available == true then observed.available = true end
    run.status = observed.remaining > 0 and "probing" or observed.available and "available" or "unavailable"
end

local function stop(run, reason)
    if not run.live then return end
    run.live = false
    for _, pending in ipairs(run.pending) do pending.active = false end
    local observed = run.observation
    if not observed then run.status = "not_run"
    elseif observed.remaining > 0 then
        observed.remaining = 0
        run.status = observed.available and "available" or "unavailable"
    end
    emit(run, { event = "stop", sample = run.samples, reason = reason })
end

local function current(run)
    local now = clock()
    return run.live and rawget(_G, LATCH) == run and context() == run.mode and now ~= nil
        and now >= run.started and now - run.started < MAX_SECONDS and permitted()
end

local function status_code(response)
    local ok, value = pcall(function() return type(response) == "table" and response.StatusCode or nil end)
    if ok and type(value) == "number" and value == math.floor(value) and value >= 0 and value <= 599 then return value end
    return 0
end

local function probe(run, api_name, label, trigger)
    if not current(run) then return end
    local fields = { event = "request", api = label, sample = run.samples, trigger = trigger,
        present = false, factory = "missing", request = "none", send = "not_attempted", timeout = "missing", status = 0 }
    local factory = rawget(_G, api_name)
    if type(factory) ~= "function" then complete_sample(run, fields.sample, false); emit(run, fields) return end
    fields.present = true
    local created, request = pcall(factory, "GET", URL)
    fields.factory = created and "ok" or "throw"
    if not created then complete_sample(run, fields.sample, false); emit(run, fields) return end
    fields.request = request == false and "false" or type(request)
    if type(request) ~= "table" and type(request) ~= "userdata" then
        complete_sample(run, fields.sample, false); emit(run, fields) return
    end
    local found, send = pcall(function() return request.Send end)
    if not found or type(send) ~= "function" then
        fields.send = found and "missing" or "throw"
        complete_sample(run, fields.sample, false)
        emit(run, fields) return
    end
    local timeout_ok, timeout_method = pcall(function() return request.SetHTTPRequestAbsoluteTimeoutMS end)
    if not timeout_ok then fields.timeout = "throw"
    elseif type(timeout_method) == "function" then
        local configured, result = pcall(timeout_method, request, TIMEOUT * 1000)
        fields.timeout = not configured and "throw" or result == false and "false" or "set"
    end
    if not current(run) then return end
    local pending = { active = true, deadline = clock() + TIMEOUT, tick = run.ticks,
        sample = run.samples, api = label, trigger = trigger, sending = true }
    run.pending[#run.pending + 1] = pending
    local function finish(code)
        if not pending.active or not current(run) or clock() >= pending.deadline then return end
        pending.active = false
        complete_sample(run, pending.sample, code == 200)
        emit(run, { event = "callback", api = label, sample = pending.sample, trigger = trigger, status = code })
    end
    local sent, accepted = pcall(send, request, function(response)
        if not pending.active or not current(run) then return end
        local code = status_code(response)
        if pending.sending then
            if pending.queued == nil then pending.queued = code end
        else finish(code) end
    end)
    pending.sending = false
    fields.send = not sent and "throw" or accepted == false and "false" or accepted == nil and "nil"
        or accepted == true and "true" or "other"
    if not sent or accepted == false then
        pending.active = false
        complete_sample(run, pending.sample, false)
    end
    emit(run, fields)
    if pending.active and pending.queued ~= nil then finish(pending.queued) end
end

function M.public_status()
    -- Observation only: no admission enforcement, configuration, HTTP, logging
    -- or scheduling from HUD polling. Never carry a result into another map.
    local run = rawget(_G, LATCH)
    if type(run) ~= "table" or run.mode ~= context() then return "not_run" end
    local ok, here = pcall(function()
        return type(IsServer) == "function" and IsServer() == true
            and type(IsClient) == "function" and IsClient() == false
            and type(GetMapName) == "function" and GetMapName() == "template_map"
    end)
    if not ok or not here then return "not_run" end
    local status = run.status
    if status == "probing" or status == "available" or status == "unavailable" then return status end
    return "not_run"
end

function M.activate()
    if not permitted() then return false end
    local started, mode = clock(), context()
    if not started or not mode or type(mode.SetContextThink) ~= "function" then return false end
    local previous = rawget(_G, LATCH)
    if type(previous) == "table" and previous.mode == mode then return true end
    if type(previous) == "table" and previous.live == true then stop(previous, "context") end
    local run = { mode = mode, started = started, live = true, ticks = 0, samples = 0, status = "probing",
        pending = {}, phases = {}, delay = 1 }
    rawset(_G, LATCH, run)
    local function tick()
        run.ticks = run.ticks + 1
        if not current(run) or run.ticks > MAX_SECONDS + 2 then stop(run, "boundary") return nil end
        local now, active = clock(), 0
        for _, pending in ipairs(run.pending) do
            if pending.active and (now >= pending.deadline or run.ticks - pending.tick >= TIMEOUT) then
                pending.active = false
                complete_sample(run, pending.sample, false)
                emit(run, { event = "timeout", api = pending.api, sample = pending.sample, trigger = pending.trigger, status = 0 })
            end
            if pending.active then active = active + 1 end
        end
        if run.samples >= MAX_SAMPLES then
            if active == 0 then stop(run, "samples") return nil end
            return 1
        end
        local selected_phase = phase()
        local trigger
        if run.samples == 0 then trigger = "initial"
        elseif selected_phase ~= "other" and selected_phase ~= "unknown" and not run.phases[selected_phase] then trigger = selected_phase
        elseif DELAYS[run.delay] and now - run.started >= DELAYS[run.delay] then
            trigger, run.delay = "delay", run.delay + 1
        end
        if trigger then
            run.phases[selected_phase] = true
            run.samples = run.samples + 1
            run.observation = { sample = run.samples, remaining = 2, available = false }
            run.status = "probing"
            probe(run, "CreateHTTPRequestScriptVM", "scriptvm", trigger)
            probe(run, "CreateHTTPRequest", "legacy", trigger)
        end
        return 1
    end
    local scheduled, accepted = pcall(mode.SetContextThink, mode, "SurvivalWorkshopNetworkProbe10", function()
        local ok, delay = pcall(tick)
        if not ok then stop(run, "internal") return nil end
        return delay
    end, 0.1)
    if not scheduled or accepted == false then
        run.live = false
        -- No run started. A transient scheduling failure must not leave a
        -- same-context latch that reports success while no timer exists.
        if rawget(_G, LATCH) == run then rawset(_G, LATCH, nil) end
        return false
    end
    emit(run, { event = "start", sample = 0, limit_samples = MAX_SAMPLES, limit_seconds = MAX_SECONDS })
    return true
end

return M
