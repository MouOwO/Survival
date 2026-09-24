package.path = "scripts/vscripts/?.lua;" .. package.path
local current_time, tools_mode, callback = 0, false, nil
Time = function() return current_time end
IsServer = function() return true end
IsInToolsMode = function() return tools_mode end
GameRules = { GetGameModeEntity = function() return {
    SetContextThink = function(_, _, fn) callback = fn end,
} end }
local lines = {}
local original_print = print
print = function(line) lines[#lines + 1] = line end
local emit = function(name, payload) return name, nil, payload end
local request = function() error("original_error") end
local think = function() return 0.05 end
package.loaded["core/event_bus"] = { emit = emit, request = request }
package.loaded["core/scheduler"] = { think = think, task_count = function() return 3 end }
local probe = require("tests/manual_combat_performance")
local bus = package.loaded["core/event_bus"]
assert(not probe.run(5) and bus.emit == emit, "disabled outside tools")
tools_mode = true
assert(probe.run(5))
local wrapped_emit = bus.emit
assert(not probe.run(5) and bus.emit == wrapped_emit, "no stacked capture wrappers")
local a, b, c = bus.emit("resource_changed", 42)
assert(a == "resource_changed" and b == nil and c == 42, "return values preserved")
local ok, err = pcall(bus.request)
assert(not ok and err:find("original_error", 1, true), "errors preserved")
current_time = 4
assert(callback() == 0.25)
current_time = 5
assert(callback() == nil and bus.emit == emit and bus.request == request, "automatic cleanup")
assert(package.loaded["core/scheduler"].think == think)
local output = table.concat(lines, "\n")
assert(output:find("emit:resource_changed count=1", 1, true))
assert(output:find("metrics=call_counts_only", 1, true))
assert(probe.run(5))
local reload_emit = function() return "reloaded" end
bus.emit = reload_emit
assert(probe.stop() and bus.emit == reload_emit, "do not roll back code reloaded during capture")
assert(callback() == nil and not probe.stop(), "manual stop idempotent")
print = original_print
print("COMBAT_PERFORMANCE_CAPTURE_PASS: tools gate, bounded capture, returns/errors, no stacked hooks, cleanup/reload")
