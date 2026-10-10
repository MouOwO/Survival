-- Actual Tools dispatcher, entirely offline: no engine, files, or TCP writes.
local path = "scripts/vscripts/tests/manual_extreme_capture_driver.lua"
local pending_key = "SURVIVAL_EXTREME_CAPTURE_PENDING"
local api_key = "SURVIVAL_EXTREME_CAPTURE_DRIVER_API"
local registry_key = "SURVIVAL_EXTREME_CAPTURE_COMMAND_REGISTERED"
local nonce = "0123456789abcdef01234567"
local other_nonce = "abcdef0123456789abcdef01"
local phases = {"VALID", "VPROF_READY", "BEGIN", "FPS", "VPROF_REPORT", "END", "CLEAN"}
local messages, callbacks, registrations, calls = {}, {}, 0, {}
local tools, server, mode = true, true, {id=1}
local original_print = print
print = function(message) messages[#messages+1] = tostring(message) end
IsInToolsMode = function() return tools end
IsServer = function() return server end
GameRules = {GetGameModeEntity=function() return mode end}
Convars = {RegisterCommand=function(_, command, callback)
    assert(callbacks[command] == nil, "native command name must never be registered twice")
    registrations = registrations+1; callbacks[command] = callback
end}
local function load() return assert(loadfile(path))() end
local function phase_callbacks(failing)
    local result = {}
    for _, phase in ipairs(phases) do
        local name = phase
        result[name] = function(state)
            calls[name] = (calls[name] or 0)+1
            assert(_G[pending_key] == state and state.mode == mode)
            if name == "BEGIN" then
                state.selection, state.clock = {}, {}
                SURVIVAL_EXTREME_SELECTION, SURVIVAL_EXTREME_CAPTURE_CLOCK = state.selection, state.clock
            end
            if failing == name then error("injected " .. name .. " failure") end
        end
    end
    return result
end
local function rejected(module, capture_nonce, phase, expected)
    local count = #messages
    local ok, reason = module.dispatch(capture_nonce, phase)
    assert(ok == false and reason == expected, tostring(reason) .. " ~= " .. expected)
    for index=count+1,#messages do assert(not messages[index]:match("^EXTREME_CAPTURE_"), "reject never prints success ack") end
end

tools = false
local module = load()
assert(registrations == 0 and _G[api_key] == nil, "production loading is inert")
assert(module.prepare(nonce, phase_callbacks()) == false)
tools, server = true, false
assert(module.prepare(nonce, phase_callbacks()) == false and registrations == 0)
server = true
module = load()
assert(registrations == 0 and _G[pending_key] == nil, "Tools require does not register/start/schedule")
assert(module.prepare("bad;quit", phase_callbacks()) == false)
local missing = phase_callbacks(); missing.FPS = nil
assert(module.prepare(nonce, missing) == false)
local extra = phase_callbacks(); extra.EVAL = function() error("must never run") end
assert(module.prepare(nonce, extra) == false and registrations == 0)
local previous_convars = Convars
Convars = nil
assert(module.prepare(nonce, phase_callbacks()) == false and _G[pending_key] == nil)
Convars = {RegisterCommand=function() error("injected native registry failure") end}
assert(module.prepare(nonce, phase_callbacks()) == false and _G[registry_key] == nil)
Convars = previous_convars
assert(module.prepare(nonce, phase_callbacks()))
assert(registrations == 1)
local native = callbacks[module.command]
local first = _G[pending_key]
assert(module.prepare(other_nonce, phase_callbacks()) == false and _G[pending_key] == first)
rejected(module, other_nonce, "VALID", "capture_nonce_mismatch")
rejected(module, nonce, "EVAL", "invalid_phase")
rejected(module, "bad;quit", "VALID", "invalid_nonce")
rejected(module, nonce, "BEGIN", "phase_out_of_order")
tools = false; rejected(module, nonce, "VALID", "tools_server_only"); tools = true
server = false; rejected(module, nonce, "VALID", "tools_server_only"); server = true
native(module.command, nonce, "VALID", "unexpected")
assert(not calls.VALID, "extra console arguments cannot invoke a phase")
native(module.command, nonce, "VALID")
assert(calls.VALID == 1 and messages[#messages] == "EXTREME_CAPTURE_VALID_" .. nonce)
rejected(module, nonce, "VALID", "phase_already_run")
assert(module.dispatch(nonce, "VPROF_READY"))
assert(module.dispatch(nonce, "BEGIN"))
rejected(module, nonce, "BEGIN", "phase_already_run")
assert(calls.BEGIN == 1, "duplicate BEGIN never repeats spawning/release")

-- Reload while a capture is pending. The one native callback must resolve the
-- new API, preserve the nonce/order, and never bind another ConCommand.
local reloaded = load()
assert(_G[api_key] == reloaded and registrations == 1 and _G[pending_key] == first)
local dispatch = reloaded.dispatch
local forwarded = 0
reloaded.dispatch = function(...) forwarded = forwarded+1; return dispatch(...) end
native(reloaded.command, nonce, "FPS")
assert(forwarded == 1 and calls.FPS == 1)
assert(reloaded.dispatch(nonce, "VPROF_REPORT"))
assert(reloaded.dispatch(nonce, "END"))
assert(reloaded.dispatch(nonce, "CLEAN"))
assert(_G[pending_key] == nil and first.closed and first.phases == nil and first.mode == nil)
assert(first.selection == nil and first.clock == nil and first.nonce == nil)
assert(SURVIVAL_EXTREME_SELECTION == nil and SURVIVAL_EXTREME_CAPTURE_CLOCK == nil)
rejected(reloaded, nonce, "CLEAN", "capture_nonce_mismatch")

assert(reloaded.prepare(other_nonce, phase_callbacks("BEGIN")))
assert(reloaded.dispatch(other_nonce, "VALID")); assert(reloaded.dispatch(other_nonce, "VPROF_READY"))
rejected(reloaded, other_nonce, "BEGIN", "phase_callback_failed")
local begin_calls = calls.BEGIN
rejected(reloaded, other_nonce, "BEGIN", "phase_already_run")
rejected(reloaded, other_nonce, "FPS", "phase_failed")
assert(calls.BEGIN == begin_calls)
assert(reloaded.dispatch(other_nonce, "CLEAN"), "cleanup remains available after partial gameplay failure")
assert(_G[pending_key] == nil and SURVIVAL_EXTREME_SELECTION == nil)

assert(reloaded.prepare(nonce, phase_callbacks("CLEAN")))
local failed_cleanup = _G[pending_key]
rejected(reloaded, nonce, "CLEAN", "phase_callback_failed")
assert(_G[pending_key] == nil and failed_cleanup.closed and failed_cleanup.phases == nil,
    "cleanup errors still release pending closures")

assert(reloaded.prepare(nonce, phase_callbacks()))
local old_world = _G[pending_key]
local clean_calls = calls.CLEAN
mode = {id=2}
rejected(reloaded, nonce, "VALID", "game_mode_changed")
rejected(reloaded, nonce, "CLEAN", "game_mode_changed")
assert(reloaded.prepare(other_nonce, phase_callbacks()))
assert(old_world.closed and old_world.phases == nil and calls.CLEAN == clean_calls,
    "new map discards stale references without invoking old-world closures")
assert(reloaded.dispatch(other_nonce, "CLEAN"))
assert(registrations == 1, "many captures and module reloads retain exactly one native command")
print = original_print
print("EXTREME_CAPTURE_DRIVER_PASS: Tools/server/nonce/phase/GameMode guards, exact acknowledgements, one native registration, latest API reload, ordered one-shot BEGIN, partial failure/early cleanup, and bounded pending scope disposal")
