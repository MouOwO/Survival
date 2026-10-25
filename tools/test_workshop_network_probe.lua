-- Exercise the real bounded probe; only engine/configuration I/O is replaced.
local MODULE = "scripts/vscripts/systems/workshop_network_probe.lua"
local decoder = dofile("scripts/vscripts/core/json_decoder.lua")
local checks = 0
local fixtures = {}
local function check(value, message) checks = checks + 1; assert(value, message) end
local function load(path, env)
    local chunk = assert(loadfile(path))
    setfenv(chunk, env)
    return chunk()
end
local function fixture()
    local state = { now = 100, state = 2, server = true, client = false, map = "template_map", tools = false,
        dedicated = false, logs = {}, requests = {}, callbacks = {}, schedules = 0,
        release = { channel = "production" }, auth = { enabled = true }, access = true, admitted = true, offline = false, bad_logs = 0 }
    fixtures[#fixtures + 1] = state
    local env = setmetatable({}, { __index = _G })
    env._G, env.package = env, { loaded = {} }
    env.Time = function() return state.now end
    env.IsServer, env.IsClient = function() return state.server end, function() return state.client end
    env.IsDedicatedServer, env.IsInToolsMode = function() return state.dedicated end, function() return state.tools end
    env.GetMapName = function() return state.map end
    env.DOTA_GAMERULES_STATE_CUSTOM_GAME_SETUP, env.DOTA_GAMERULES_STATE_PRE_GAME, env.DOTA_GAMERULES_STATE_GAME_IN_PROGRESS = 2, 7, 8
    env.Convars = { GetStr = function() return state.offline and "1" or "0" end }
    env.require = function(name)
        if name == "config/release_profile" then return state.release end
        if name == "config/player_web_auth" then return state.auth end
        check(name == "core/test_access_policy", "only trusted activation guards can be required")
        return { enabled = function() return state.access end, enforce_connected = function() return state.admitted end }
    end
    env.print = function(line)
        local ok, parsed = pcall(decoder.decode, line:sub(13))
        if line:sub(1, 12) ~= "[WS4-MP-09] " or line:find("PRIVATE", 1, true)
            or line:find("https", 1, true) or line:find("765611", 1, true)
            or not ok or type(parsed) ~= "table" or parsed.map ~= "template_map" or parsed.server ~= true then
            state.bad_logs = state.bad_logs + 1; return
        end
        state.logs[#state.logs + 1] = parsed
    end
    local host = { SetContextThink = function(_, name, callback, delay)
        check(name == "SurvivalWorkshopNetworkProbe09" and delay == 0.1, "one fixed timer")
        state.schedules, state.tick = state.schedules + 1, callback
    end }
    state.host = host
    env.GameRules = { GetGameModeEntity = function() return state.host end, State_Get = function() return state.state end }
    state.factory = function(kind, behavior)
        return function(method, url)
            check(method == "GET" and url == "https://pay.xiaofengnet.com/ws4-web/health", "only anonymous fixed GET health")
            state.requests[#state.requests + 1] = kind
            if behavior == "throw" then error("PRIVATE factory") end
            if behavior == "nil" then return nil end
            if behavior == "false" then return false end
            if behavior == "number" then return 99 end
            if behavior == "missing_send" then return {} end
            return { SetHTTPRequestAbsoluteTimeoutMS = function(_, value) check(value == 8000, "native timeout is bounded") end,
                Send = function(_, callback)
                    state.callbacks[#state.callbacks + 1] = callback
                    if behavior == "send_throw" then error("PRIVATE Send") end
                    if behavior == "send_false" then callback({ StatusCode = 200, Body = "PRIVATE" }); return false end
                    if behavior == "sync_double" then callback({ StatusCode = 200, Body = "PRIVATE" }); callback({ StatusCode = 503 }); return true end
                    if behavior == "send_nil" then return nil end
                    return true
                end }
        end
    end
    env.CreateHTTPRequestScriptVM, env.CreateHTTPRequest = state.factory("scriptvm"), state.factory("legacy")
    state.advance = function(seconds)
        for _ = 1, seconds do
            state.now = state.now + 1
            if state.tick then local delay = state.tick(); if delay == nil then state.tick = nil else check(delay == 1, "fixed bounded polling interval") end end
        end
    end
    state.count = function(event, api, field, value)
        local count = 0
        for _, row in ipairs(state.logs) do
            if row.event == event and (not api or row.api == api) and (not field or row[field] == value) then count = count + 1 end
        end
        return count
    end
    return env, state, load(MODULE, env)
end

-- Development, offline, clients and entry maps cannot even schedule network work.
for _, change in ipairs({ function(e,s) s.release.channel = "development" end,
    function(e,s) s.auth.enabled = false end, function(e,s) s.offline = true end,
    function(e,s) e.package.loaded["debug/offline_logic_test"] = { is_enabled = function() return true end } end,
    function(e,s) s.server = false; s.client = true end, function(e,s) s.client = true end,
    function(e,s) s.map = "ws4_entry" end, function(e,s) s.access = false end,
    function(e,s) s.admitted = false end, function(e,s) e.IsServer = function() error("PRIVATE") end end,
    function(e,s) e.Time = false end }) do
    local env, state, probe = fixture(); change(env, state)
    check(probe.activate() == false and #state.requests == 0 and state.schedules == 0 and #state.logs == 0, "rejected contexts remain silent and zero HTTP")
end

local env, state, probe = fixture()
check(probe.activate() and probe.activate() and state.schedules == 1, "duplicate activate is latched")
local reloaded = load(MODULE, env)
check(reloaded.activate() and state.schedules == 1, "module reload also preserves the context latch")
state.advance(1)
check(#state.requests == 2 and state.count("request") == 2, "both factories sampled independently")
state.callbacks[1]({ StatusCode = 200, Body = "PRIVATE token" })
state.callbacks[1]({ StatusCode = 500 })
check(state.count("callback", "scriptvm") == 1 and state.count("callback", "scriptvm", "status", 200) == 1, "duplicate callbacks ignored")
state.state = 7; state.advance(1)
state.state = 8; state.advance(1)
check(state.count("request", "scriptvm", "trigger", "pregame") == 1 and state.count("request", "scriptvm", "trigger", "ingame") == 1, "phase transitions are sampled")
state.advance(400)
check(#state.requests <= 16 and state.tick == nil and state.count("stop") == 1, "bounded requests and schedule terminate")
local previous_callbacks = state.count("callback")
for _, callback in ipairs(state.callbacks) do callback({ StatusCode = 200, Body = "PRIVATE" }) end
check(state.count("callback") == previous_callbacks and probe.activate() and state.schedules == 1, "expired callbacks and reactivation cannot restart the probe")

for _, row in ipairs({ {"throw", "factory", "throw"}, {"nil", "request", "nil"}, {"false", "request", "false"},
    {"number", "request", "number"}, {"missing_send", "send", "missing"}, {"send_throw", "send", "throw"},
    {"send_false", "send", "false"}, {"send_nil", "send", "nil"}, {"sync_double", "send", "true"} }) do
    env, state, probe = fixture()
    env.CreateHTTPRequestScriptVM = state.factory("scriptvm", row[1])
    check(probe.activate()); state.advance(1)
    check(state.count("request", "scriptvm", row[2], row[3]) == 1, "factory and Send result classification: " .. row[1])
    check(state.count("request", "legacy", "factory", "ok") == 1, "legacy remains independently available")
    if row[1] == "send_nil" then
        state.callbacks[1]({ StatusCode = 201, Body = "PRIVATE" })
        check(state.count("callback", "scriptvm", "status", 201) == 1, "nil Send return accepts a real callback")
    elseif row[1] == "send_false" or row[1] == "send_throw" then
        state.callbacks[1]({ StatusCode = 200 })
        check(state.count("callback", "scriptvm") == 0, "failed sends discard synchronous and late callbacks")
    elseif row[1] == "sync_double" then check(state.count("callback", "scriptvm") == 1, "synchronous double callback reduced to one") end
end

env, state, probe = fixture(); env.CreateHTTPRequestScriptVM, env.CreateHTTPRequest = false, false
check(probe.activate()); state.advance(1)
check(#state.requests == 0 and state.count("request", nil, "factory", "missing") == 2, "missing APIs logged without invocation")
env, state, probe = fixture(); check(probe.activate()); state.advance(1)
state.advance(8); state.callbacks[1]({ StatusCode = 200 })
check(state.count("timeout", "scriptvm") >= 1 and state.count("callback", "scriptvm") == 0, "timeouts invalidate late callbacks")
env, state, probe = fixture(); check(probe.activate()); state.advance(1)
state.auth.enabled = false; state.callbacks[1]({ StatusCode = 200 }); state.advance(100)
check(#state.requests == 2 and state.count("callback") == 0 and state.tick == nil, "configuration revocation cancels subsequent HTTP and callbacks")
env, state, probe = fixture(); check(probe.activate()); state.advance(1)
state.host = {}; state.callbacks[1]({ StatusCode = 200 }); state.advance(1)
check(state.count("callback") == 0 and state.tick == nil, "a replaced game-mode entity expires the old run")
env, state, probe = fixture(); check(probe.activate())
for _ = 1, 305 do if state.tick then local delay = state.tick(); if delay == nil then state.tick = nil end end end
check(state.tick == nil and #state.requests == 2, "tick bound still terminates if the engine clock stops")
for _, value in ipairs({ -1, 600, "PRIVATE", 0/0 }) do
    env, state, probe = fixture(); check(probe.activate()); state.advance(1)
    state.callbacks[1]({ StatusCode = value, Body = "PRIVATE" })
    check(state.count("callback", "scriptvm", "status", 0) == 1, "invalid native callback statuses remain bounded")
end
env, state, probe = fixture()
env.IsDedicatedServer, env.IsInToolsMode = function() error("PRIVATE") end, false
check(probe.activate()); state.advance(1)
check(state.logs[1].dedicated == "unknown" and state.logs[1].tools == "unknown", "unavailable environment flags never leak exceptions")
for _, behavior in ipairs({ "missing", "throw", "false" }) do
    env, state, probe = fixture()
    if behavior == "missing" then state.host.SetContextThink = false
    elseif behavior == "throw" then state.host.SetContextThink = function() error("PRIVATE timer") end
    else state.host.SetContextThink = function() return false end end
    check(probe.activate() == false and #state.requests == 0 and #state.logs == 0, "missing or refused scheduling cannot start HTTP")
end
env, state, probe = fixture(); check(probe.activate()); state.now = state.now + 300; state.advance(1)
check(#state.requests == 0 and state.tick == nil, "elapsed-time limit rejects delayed first execution")

-- Execute the exact addon wrapper separately with return tuples and failures.
local file = assert(io.open("scripts/vscripts/addon_game_mode.lua", "rb"))
local source = file:read("*a"); file:close()
local wrapper = assert(source:match("(%-%- BEGIN WS4%-MP%-09 NETWORK PROBE WRAPPER.-%-%- END WS4%-MP%-09 NETWORK PROBE WRAPPER)"))
local order = {}
local wrapped = setmetatable({ Activate = function() order[#order + 1] = "old"; return 7, nil, false end,
    require = function(name) check(name == "systems/workshop_network_probe"); return { activate = function() order[#order + 1] = "probe"; error("PRIVATE") end } end }, {__index = _G})
local chunk = assert(loadstring(wrapper)); setfenv(chunk, wrapped); chunk()
local function pack(...) return { n = select("#", ...), ... } end
local values = pack(wrapped.Activate())
check(values.n == 3 and values[1] == 7 and values[2] == nil and values[3] == false and table.concat(order, ",") == "old,probe", "wrapper preserves old return tuple and isolates probe failure")
order = {}; wrapped.Activate = function() order[#order + 1] = "old"; error("old failure") end
chunk = assert(loadstring(wrapper)); setfenv(chunk, wrapped); chunk()
check(not pcall(wrapped.Activate) and table.concat(order, ",") == "old", "old activation failure propagates before any probe")
for _, item in ipairs(fixtures) do check(item.bad_logs == 0, "every emitted line is safe parseable JSON, including stopped/error paths") end
print("WORKSHOP_NETWORK_PROBE_PASS checks=" .. checks)
