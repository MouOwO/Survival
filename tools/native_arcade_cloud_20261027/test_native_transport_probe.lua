-- Run actual probe modules in isolated engine fixtures. No HTTP or live game.
local SERVER = "scripts/vscripts/systems/native_transport_probe.lua"
local CLIENT = "scripts/vscripts/systems/native_transport_client_probe.lua"
local decoder = dofile("scripts/vscripts/core/json_decoder.lua")
local checks, groups = 0, 0
local function check(value, message) checks = checks + 1; assert(value, message or "check failed") end
local function load(path, env)
    local chunk = assert(loadfile(path)); setfenv(chunk, env); return chunk()
end
local function nonce(number) return string.format("%032x", number) end
local function fixture(client_side)
    local state = {now = 100, server = not client_side, client = client_side == true, phase = 2, map = "template_map",
        session = "native_probe_session_01", logs = {}, sent = {}, callbacks = {}, requests = {}, require_calls = {},
        allowed = true, gate = true, connected = {[0] = 2, [1] = 2}, fake = {}, teams = {[0] = 2, [1] = 2},
        accounts = {[0] = 463897428, [1] = 885195478}, players = {}, schedules = 0, bad_logs = 0,
        roster = {enabled = true, allowed_steamids = {"76561198424163156", "76561198845461206", "76561198104787442", "76561198974301984"}}}
    local env = setmetatable({}, {__index = _G}); env._G = env; env.package = {loaded = {}}
    env.Time = function() return state.now end
    env.IsServer, env.IsClient = function() return state.server end, function() return state.client end
    env.GetMapName = function() return state.map end
    env.DOTA_GAMERULES_STATE_CUSTOM_GAME_SETUP, env.DOTA_GAMERULES_STATE_PRE_GAME, env.DOTA_GAMERULES_STATE_GAME_IN_PROGRESS = 2, 7, 8
    state.entities = {}
    for id = 0, 1 do
        local bound = id
        local player = {GetPlayerID = function() return bound end, IsNull = function() return false end}
        state.entities[id + 10], state.players[id] = player, player
    end
    env.EntIndexToHScript = function(index) return state.entities[index] end
    env.PlayerResource = {
        GetPlayer = function(_, id) return state.players[id] end,
        IsValidPlayerID = function(_, id) return state.players[id] ~= nil end,
        IsFakeClient = function(_, id) return state.fake[id] == true end,
        GetConnectionState = function(_, id) return state.connected[id] end,
        GetTeam = function(_, id) return state.teams[id] end,
        GetSteamAccountID = function(_, id) return state.accounts[id] end,
    }
    env.CustomGameEventManager = {
        RegisterListener = function(_, event, callback)
            check(event == "survival_native_transport_probe_request", "fixed diagnostic request")
            state.listener, state.registrations = callback, (state.registrations or 0) + 1
            return 1
        end,
        Send_ServerToPlayer = function(_, player, event, reply)
            check(event == "survival_native_transport_probe_reply", "fixed private reply")
            state.sent[#state.sent + 1] = {player = player, reply = reply}
        end,
        Send_ServerToAllClients = function() error("broadcast forbidden") end,
    }
    state.host = {SetContextThink = function(_, name, callback, delay)
        check(name == "SurvivalNativeTransportProbe01" and delay == 0.1, "bounded named timer")
        state.tick, state.schedules = callback, state.schedules + 1
    end}
    env.GameRules = {GetGameModeEntity = function() return state.host end, State_Get = function() return state.phase end}
    env.require = function(name)
        state.require_calls[#state.require_calls + 1] = name
        if client_side then error("client must not require any server module: " .. name) end
        if name == "config/test_access" then return state.roster end
        if name == "core/test_access_policy" then return {
            enabled = function() return state.gate end, init = function() return state.gate end,
            allowed = function() return state.allowed end,
        } end
        if name == "systems/match_setup_service" then return {get_session_id = function() return state.session end} end
        if name == "systems/native_transport_client_probe" then
            state.sampler = state.sampler or load(CLIENT, env); return state.sampler
        end
        error("unexpected module: " .. name)
    end
    env.print = function(line)
        local prefix = "[WS4-NATIVE-PROBE-01] "
        local ok, row = pcall(decoder.decode, line:sub(#prefix + 1))
        if line:sub(1, #prefix) ~= prefix or not ok or type(row) ~= "table"
            or row.revision ~= "WS4-NATIVE-PROBE-01" or row.side ~= (state.server and "server" or "client")
            or line:find("SECRET", 1, true) or line:find("https", 1, true) or line:find("463897428", 1, true) then
            state.bad_logs = state.bad_logs + 1; return
        end
        state.logs[#state.logs + 1] = row
    end
    state.factory = function(label, behavior)
        return function(method, url)
            check(method == "GET" and url == "https://pay.xiaofengnet.com/ws4-web/health", "exact anonymous GET URL, no query")
            local record = {label = label}; state.requests[#state.requests + 1] = record
            if behavior == "throw" then error("SECRET factory exception") end
            if behavior == "nil" then return nil end
            if behavior == "false" then return false end
            if behavior == "number" then return 17 end
            if behavior == "missing_send" then return {} end
            local handle = {
                SetHTTPRequestHeaderValue = function(_, name, value)
                    check(name == "X-WS4-Probe-Nonce" and type(value) == "string" and #value == 32
                        and value:match("^[a-f0-9]+$") ~= nil, "only nonce header")
                    record.nonce = value
                    if behavior == "header_throw" then error("SECRET header") end
                    return behavior ~= "header_false"
                end,
                SetHTTPRequestAbsoluteTimeoutMS = function(_, milliseconds) check(milliseconds == 10000, "10 second native timeout") end,
                Send = function(_, callback)
                    check(record.nonce ~= nil, "nonce set before send")
                    state.callbacks[#state.callbacks + 1] = callback
                    if behavior == "send_throw" then error("SECRET send") end
                    if behavior == "send_false" then callback({StatusCode = 200, Body = "SECRET"}); return false end
                    if behavior == "sync_double" then callback({StatusCode = 204, Body = "SECRET"}); callback({StatusCode = 503}); return true end
                    if behavior == "send_nil" then return nil end
                    return true
                end,
            }
            if behavior == "missing_header" then handle.SetHTTPRequestHeaderValue = nil end
            return handle
        end
    end
    env.CreateHTTPRequestScriptVM, env.CreateHTTPRequest = state.factory("scriptvm"), state.factory("legacy")
    state.advance = function(seconds)
        for _ = 1, seconds do
            state.now = state.now + 1
            if state.tick then local delay = state.tick(); if delay == nil then state.tick = nil else check(delay == 1, "fixed timer interval") end end
        end
    end
    state.count = function(event, api, field, value)
        local count = 0
        for _, row in ipairs(state.logs) do
            if row.event == event and (not api or row.api == api) and (not field or row[field] == value) then count = count + 1 end
        end
        return count
    end
    local sampler = load(CLIENT, env)
    state.sampler = sampler
    return env, state, load(SERVER, env), sampler
end
local function group(name, callback)
    callback(); groups = groups + 1; print("PASS " .. name)
end

group("private echo identity and exact protocol", function()
    local _, s, p = fixture()
    check(p.init() and p.init() and s.registrations == 1, "listener initialized once")
    check(#s.requests == 0 and s.schedules == 0, "echo init performs no HTTP")
    s.listener(10, {nonce = nonce(1), echo_b64 = "YWJj_-"})
    check(#s.sent == 1 and s.sent[1].player == s.players[0], "reply to actual source entity")
    local row, count = s.sent[1].reply, 0; for _ in pairs(row) do count = count + 1 end
    check(count == 7 and row.ok == true and row.revision == "WS4-NATIVE-PROBE-01" and row.nonce == nonce(1)
        and row.echo_b64 == "YWJj_-" and row.player_id == 0 and row.account_id == "463897428"
        and row.match_session_id == s.session, "exact seven-field bound diagnostic reply")
    s.listener(11, {nonce = nonce(2), echo_b64 = "Zg", PlayerID = 1})
    check(#s.sent == 2 and s.sent[2].player == s.players[1], "matching engine PlayerID metadata never chooses actor")
    check(#s.logs == 0, "echo never logs identity or payload")
end)

group("payload cannot select player, identity, endpoint or permissions", function()
    for _, payload in ipairs({
        {nonce = nonce(1), echo_b64 = "Zg", PlayerID = 1},
        {nonce = nonce(1), echo_b64 = "Zg", PlayerID = "0"},
        {nonce = nonce(1), echo_b64 = "Zg", player_id = 0},
        {nonce = nonce(1), echo_b64 = "Zg", account_id = "463897428"},
        {nonce = nonce(1), echo_b64 = "Zg", enabled = true},
        {nonce = nonce(1), echo_b64 = "Zg", url = "https://attacker.invalid"},
        {nonce = string.rep("A", 32), echo_b64 = "Zg"},
        {nonce = nonce(1), echo_b64 = "Zg=="}, {nonce = nonce(1), echo_b64 = "abc def"},
        {nonce = nonce(1), echo_b64 = string.rep("a", 193)}, {nonce = nonce(1), echo_b64 = ""},
    }) do
        local _, s, p = fixture(); check(p.init()); s.listener(10, payload)
        check(#s.sent == 0 and #s.requests == 0, "malformed or injected fields stay inert")
    end
end)

group("source entity, live human and four-account guards", function()
    for _, change in ipairs({
        function(e, s) s.entities[10] = nil end,
        function(e, s) s.players[0] = {} end,
        function(e, s) s.entities[10].IsNull = function() return true end end,
        function(e, s) s.fake[0] = true end,
        function(e, s) s.connected[0] = 3 end,
        function(e, s) s.connected[0] = nil end,
        function(e, s) s.teams[0] = 1 end,
        function(e, s) s.accounts[0] = 123456789 end,
        function(e, s) s.accounts[0] = 0 end,
        function(e, s) s.accounts[0] = "463897428" end,
        function(e, s) s.gate = false end,
        function(e, s) s.allowed = false end,
        function(e, s) s.roster.enabled = false end,
        function(e, s) s.roster.allowed_steamids[4] = nil end,
        function(e, s) s.roster.allowed_steamids[5] = "76561198845461206" end,
        function(e, s) s.session = "" end,
        function(e, s) s.session = "bad\nmatch" end,
        function(e, s) s.map = "other_map" end,
        function(e, s) e.Time = nil end,
    }) do
        local e, s, p = fixture(); check(p.init()); change(e, s)
        s.listener(10, {nonce = nonce(1), echo_b64 = "Zg"})
        check(#s.sent == 0, "invalid source/config/session denied")
    end
    local _, s, p = fixture(); check(p.init())
    for _, source in ipairs({-1, 0/0, 10.5, "not_an_entity", 999}) do
        s.listener(source, {nonce = nonce(1), echo_b64 = "Zg"})
    end
    check(#s.sent == 0, "source is an entity index, never a player slot")
end)

group("nonces and rate limits survive reconnect and slot changes", function()
    local _, s, p = fixture(); check(p.init())
    for index = 1, 11 do s.listener(10, {nonce = nonce(index), echo_b64 = "Zg"}) end
    check(#s.sent == 10, "at most ten replies per account per thirty seconds")
    s.accounts[1] = s.accounts[0]
    s.listener(11, {nonce = nonce(12), echo_b64 = "Zg"})
    check(#s.sent == 10, "another slot with same account cannot reset the window")
    s.now = s.now + 30
    s.listener(11, {nonce = nonce(1), echo_b64 = "Zg"})
    check(#s.sent == 10, "nonce never reused in current session")
    s.listener(11, {nonce = nonce(13), echo_b64 = "Zg"})
    check(#s.sent == 11, "fresh nonce after window is eligible")
    s.now = s.now - 1
    s.listener(11, {nonce = nonce(14), echo_b64 = "Zg"})
    check(#s.sent == 11, "clock reversal cannot reset rate limits")
    s.now = s.now + 2; s.session = "native_probe_session_02"
    s.listener(11, {nonce = nonce(1), echo_b64 = "Zg"})
    check(#s.sent == 12 and s.sent[12].reply.match_session_id == s.session, "new actual match binds its own reply")
end)

group("client sampler loads without any require or server event listeners", function()
    local _, s, p, sampler = fixture(true)
    check(p.init() == false and s.listener == nil and #s.require_calls == 0, "server listener refuses client VM")
    check(sampler.start({side = "client", automatic = false}));
    check(sampler.sample({side = "client", nonce = nonce(1), trigger = "manual"}))
    check(#s.requests == 2 and #s.require_calls == 0 and s.bad_logs == 0, "real client-tagged factories sampled without server imports")
    check(sampler.status().side == "client" and sampler.status().available == false, "handles are not availability evidence")
    s.callbacks[1]({StatusCode = 204, Body = "SECRET"})
    check(sampler.status().available == true and s.count("callback", "scriptvm", "available", true) == 1, "real 2xx callback is evidence")
    check(sampler.sample({side = "server", nonce = nonce(2)}) == false and #s.requests == 2, "cannot spoof server side")
end)

group("client inventory remains usable without server-only timer APIs", function()
    local e, s, _, sampler = fixture(true)
    s.host = nil
    e.CreateHTTPRequestScriptVM, e.CreateHTTPRequest = false, nil
    e.yhttp = s.factory("yhttp")
    check(sampler.inventory() and #s.require_calls == 0 and #s.requests == 0 and s.schedules == 0,
        "inventory works before client entity/timer exists and invokes nothing")
    check(s.count("inventory") == 3 and s.count("inventory", "yhttp", "present", true) == 1
        and s.count("inventory", "scriptvm", "present", false) == 1 and s.bad_logs == 0,
        "type inventory does not fabricate callback availability")
    check(sampler.sample({nonce = nonce(1)}) == false and #s.requests == 0,
        "real callback sample still needs a deadline owner")
end)

group("server facade invokes real shared sampler and fixed header only", function()
    local _, s, p, sampler = fixture()
    check(p.sample({nonce = nonce(1), trigger = "manual", side = "client", url = "https://attacker.invalid"}))
    check(#s.requests == 2 and #s.logs == 3 and s.logs[1].side == "server", "server facade ignores caller URL/side")
    check(s.requests[1].nonce == nonce(1) and s.requests[2].nonce == nonce(1), "nonce correlation present on both independent requests")
    check(sampler.status().available == false, "Send acceptance does not assert reachability")
    s.callbacks[1]({StatusCode = 500, Body = "SECRET"})
    check(sampler.status().available == false and s.count("callback", "scriptvm", "available", false) == 1, "non-2xx callback not successful")
    s.callbacks[2]({StatusCode = 299, Body = "SECRET"})
    check(sampler.status().available == true and s.bad_logs == 0, "2xx evidence logged without body")
end)

group("factory, handle and Send failures remain distinct", function()
    for _, row in ipairs({{"throw", "factory", "throw"}, {"nil", "handle", "nil"},
        {"false", "handle", "boolean"}, {"number", "handle", "number"}, {"missing_send", "send", "missing"},
        {"missing_header", "header", "missing"}, {"header_false", "header", "false"}, {"header_throw", "header", "throw"},
        {"send_throw", "send", "throw"}, {"send_false", "send", "false"}, {"send_nil", "send", "nil"},
        {"sync_double", "send", "true"}}) do
        local e, s, _, sampler = fixture()
        e.CreateHTTPRequestScriptVM = s.factory("scriptvm", row[1])
        check(sampler.sample({nonce = nonce(1)}))
        check(s.count("request", "scriptvm", row[2], row[3]) == 1, "actual failure classification " .. row[1])
        check(s.count("request", "legacy", "factory", "ok") == 1, "other factory is independent")
        if row[1] == "send_false" or row[1] == "send_throw" then
            s.callbacks[1]({StatusCode = 200, Body = "SECRET"})
            check(s.count("callback", "scriptvm") == 0, "failed Send discards queued and late callbacks")
        elseif row[1] == "sync_double" then
            check(s.count("callback", "scriptvm", "status", 204) == 1 and s.count("callback", "scriptvm") == 1,
                "only first synchronous callback accepted")
        elseif row[1] == "send_nil" then
            check(sampler.status().available == false); s.callbacks[1]({StatusCode = 201})
            check(sampler.status().available == true, "nil Send return needs an actual successful callback")
        end
        check(s.bad_logs == 0, "exceptions and response bodies never logged")
    end
end)

group("missing APIs and yhttp remain honest optional inventory", function()
    local e, s, _, sampler = fixture()
    e.CreateHTTPRequestScriptVM, e.CreateHTTPRequest = false, false
    e.yhttp = s.factory("yhttp")
    check(sampler.sample({nonce = nonce(1)}))
    check(#s.requests == 0 and s.count("request", nil, "factory", "missing") == 2, "nil factories never counted as HTTP success")
    local original = e.yhttp
    local e2, s2, _, sampler2 = fixture(); e2.yhttp = s2.factory("yhttp", "sync_double")
    local selected = e2.yhttp
    check(sampler2.sample({nonce = nonce(1), include_yhttp = true}))
    check(#s2.requests == 3 and s2.count("callback", "yhttp_function", "available", true) == 1,
        "explicit optional compatible yhttp function can supply callback evidence")
    check(e.yhttp == original and e2.yhttp == selected, "native or optional factory globals never replaced")
end)

group("disabled yhttp namespace is never read through a metatable", function()
    local e, s, _, sampler = fixture(true)
    local reads, calls = 0, 0
    local namespace = setmetatable({}, {
        __index = function() reads = reads + 1; error("SECRET disabled member") end,
        __call = function() calls = calls + 1; error("namespace cannot be called") end,
    })
    e.yhttp = namespace
    check(sampler.inventory() and reads == 0 and calls == 0, "default inventory observes only raw global type")
    check(s.count("inventory", "yhttp", "global_type", "table") == 1
        and s.count("inventory", "yhttp", "nested_lookup", "disabled") == 1,
        "table presence is distinguished from uninspected nested callable")
    check(sampler.sample({nonce = nonce(1)}) and #s.requests == 2 and reads == 0 and calls == 0,
        "default sample does not inspect or invoke optional table")
    s.advance(6)
    check(reads == 0 and calls == 0 and e.yhttp == namespace and s.bad_logs == 0,
        "timer and original globals remain independent of disabled namespace")
end)

group("DoDoTD table factory is read safely and invoked as a dot function", function()
    for _, lazy in ipairs({false, true}) do
        local e, s, _, sampler = fixture(true)
        local reads, namespace_calls = 0, 0
        local factory = s.factory("yhttp_table", "sync_double")
        local namespace = setmetatable(lazy and {} or {CreateHTTPRequestScriptVM = factory}, {
            __index = function(_, key)
                reads = reads + 1
                check(key == "CreateHTTPRequestScriptVM", "only fixed nested factory name is looked up")
                return factory
            end,
            __call = function() namespace_calls = namespace_calls + 1; error("namespace __call forbidden") end,
        })
        e.yhttp = namespace
        local native_vm, native_legacy = e.CreateHTTPRequestScriptVM, e.CreateHTTPRequest
        check(sampler.inventory({include_yhttp = true}) and #s.requests == 0,
            "selected inventory reads callable type without invoking any factory")
        check(s.count("inventory", "yhttp", "global_type", "table") == 1
            and s.count("inventory", "yhttp", "nested_type", "function") == 1
            and s.count("inventory", "yhttp", "nested_callable", true) == 1
            and s.count("inventory", "yhttp", "selected_api", "yhttp_scriptvm") == 1,
            "inventory accurately names table namespace and its nested factory")
        check(sampler.sample({nonce = nonce(1), include_yhttp = true, url = "https://attacker.invalid"}))
        check(#s.requests == 3 and s.requests[3].label == "yhttp_table" and s.requests[3].nonce == nonce(1)
            and s.count("request", "yhttp_scriptvm", "nested_callable", true) == 1
            and s.count("callback", "yhttp_scriptvm", "status", 204) == 1,
            "real nested function gets only fixed GET URL, nonce header and real 2xx callback")
        check(namespace_calls == 0 and reads == (lazy and 2 or 0) and e.yhttp == namespace
            and e.CreateHTTPRequestScriptVM == native_vm and e.CreateHTTPRequest == native_legacy and s.bad_logs == 0,
            "no callable-table fallback, self injection, global replacements or exception/body logs")
    end
end)

group("optional table member errors and noncallables do not escape or fall back", function()
    for _, behavior in ipairs({"throw", "nil", "table", "false", "string"}) do
        local e, s, _, sampler = fixture()
        local reads, namespace_calls = 0, 0
        e.yhttp = setmetatable({}, {
            __index = function(_, key)
                check(key == "CreateHTTPRequestScriptVM", "only the actual nested export is read")
                reads = reads + 1
                if behavior == "throw" then error("SECRET nested lookup") end
                if behavior == "table" then return setmetatable({}, {__call = function() error("callable member table forbidden") end}) end
                if behavior == "false" then return false end
                if behavior == "string" then return "SECRET" end
            end,
            __call = function() namespace_calls = namespace_calls + 1; error("namespace __call forbidden") end,
        })
        check(sampler.inventory({include_yhttp = true}) and #s.requests == 0 and reads == 1)
        check(s.count("inventory", "yhttp", "nested_callable", false) == 1
            and s.count("inventory", "yhttp", "nested_lookup", behavior == "throw" and "throw" or "ok") == 1,
            "inventory preserves missing/member-lookup failure distinction")
        check(sampler.sample({nonce = nonce(1), include_yhttp = true}) and #s.requests == 2 and reads == 2,
            "bad optional member leaves both standard factory samples intact")
        check(s.count("request", "yhttp_scriptvm", "factory", behavior == "throw" and "lookup_throw" or "missing") == 1
            and s.count("callback", "yhttp_scriptvm") == 0 and namespace_calls == 0 and s.bad_logs == 0,
            "no optional fallback, false callback, metamethod error leak or table invocation")
    end
end)

group("optional table preserves request, timeout and sample limits", function()
    local e, s, _, sampler = fixture()
    e.yhttp = {CreateHTTPRequestScriptVM = s.factory("yhttp_table")}
    for index = 1, 6 do check(sampler.sample({nonce = nonce(index), include_yhttp = true})) end
    check(sampler.sample({nonce = nonce(7), include_yhttp = true}) == false
        and #s.requests == 18 and sampler.status().samples == 6, "six samples still mean at most eighteen total factory calls")
    check(sampler.status().available == false, "nested handle and Send true are not callback evidence")
    s.advance(10)
    check(s.count("timeout", "yhttp_scriptvm") == 6 and s.count("timeout") == 18 and s.tick == nil,
        "each nested request uses the same ten-second deadline and bounded lifecycle")
    for _, callback in ipairs(s.callbacks) do callback({StatusCode = 200, Body = "SECRET"}) end
    check(s.count("callback") == 0 and s.bad_logs == 0, "expired nested callbacks cannot revive the finished probe")
end)

group("timeout, duplicate and late callback lifecycle", function()
    local _, s, _, sampler = fixture()
    check(sampler.sample({nonce = nonce(1)})); s.advance(10)
    check(s.count("timeout") == 2 and sampler.status().available == false, "10 second timeout for each accepted Send")
    for _, callback in ipairs(s.callbacks) do callback({StatusCode = 200, Body = "SECRET"}) end
    check(s.count("callback") == 0, "late success cannot revive timed out requests")
    check(sampler.sample({nonce = nonce(1)}) == false and #s.requests == 2, "sample nonce cannot be reused")
    check(sampler.sample({nonce = nonce(2)})); s.callbacks[3]({StatusCode = 200}); s.callbacks[3]({StatusCode = 200})
    check(s.count("callback") == 1, "duplicate callback ignored")
    sampler.stop(); s.callbacks[4]({StatusCode = 200}); s.advance(1)
    check(s.count("callback") == 1 and s.tick == nil and sampler.start() == false, "stopped context cannot restart or accept callbacks")
end)

group("automatic phases and delays have a fixed total request budget", function()
    local e, s, _, sampler = fixture()
    e.CreateHTTPRequestScriptVM, e.CreateHTTPRequest = s.factory("scriptvm", "nil"), s.factory("legacy", "nil")
    s.phase = 0
    check(sampler.start() and sampler.start() and s.schedules == 1, "start latches real game context")
    s.advance(1); s.phase = 2; s.advance(1); s.phase = 7; s.advance(1); s.phase = 8; s.advance(1)
    s.advance(200)
    check(s.count("request", "scriptvm", "trigger", "initial") == 1
        and s.count("request", "scriptvm", "trigger", "setup") == 1
        and s.count("request", "scriptvm", "trigger", "pregame") == 1
        and s.count("request", "scriptvm", "trigger", "ingame") == 1, "nil handles do not suppress later actual phase observations")
    check(sampler.status().samples == 6 and #s.requests == 12 and s.tick == nil, "at most six samples and twelve standard factory invocations")
    local reloaded = load(CLIENT, e)
    check(reloaded.start() == false and #s.requests == 12, "module reload cannot reset total per-context budget")
end)

group("missing timer, stale context, invalid side and frozen clock fail closed", function()
    for _, change in ipairs({
        function(e, s) s.host.SetContextThink = false end,
        function(e, s) s.host.SetContextThink = function() return false end end,
        function(e, s) s.host.SetContextThink = function() error("SECRET timer") end end,
        function(e, s) e.Time = false end,
        function(e, s) s.map = "unrelated_map" end,
        function(e, s) s.server, s.client = true, true end,
    }) do
        local e, s, _, sampler = fixture(); change(e, s)
        check(sampler.sample({nonce = nonce(1)}) == false and #s.requests == 0, "no timer/side/context means no real Send")
    end
    local _, s, _, sampler = fixture(); check(sampler.sample({nonce = nonce(1)}))
    s.host = {}; s.callbacks[1]({StatusCode = 200}); s.advance(1)
    check(s.count("callback") == 0 and s.tick == nil, "old world callbacks rejected")
    local _, frozen, _, frozen_sampler = fixture(); check(frozen_sampler.sample({nonce = nonce(1)}))
    for _ = 1, 165 do if frozen.tick then local delay = frozen.tick(); if delay == nil then frozen.tick = nil end end end
    check(frozen.tick == nil and #frozen.requests == 2 and frozen.count("timeout") == 2, "tick limits remain bounded with frozen Time")
end)

group("invalid status never turns a callback into successful transport", function()
    for _, value in ipairs({-1, 600, "200", 0/0}) do
        local _, s, _, sampler = fixture(); check(sampler.sample({nonce = nonce(1)}))
        s.callbacks[1]({StatusCode = value, Body = "SECRET"})
        check(s.count("callback", "scriptvm", "status", 0) == 1 and sampler.status().available == false and s.bad_logs == 0,
            "invalid status is classified as zero with no body logging")
    end
end)

print(string.format("PASS native transport probe: %d groups, %d checks (no live network/game)", groups, checks))
