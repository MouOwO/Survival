package.path = "scripts/vscripts/?.lua;" .. package.path
local time, cpu, tools, server, callback = 0, 0, false, true
Time = function() return time end
IsServer = function() return server end
IsInToolsMode = function() return tools end
local original_clock, original_print = os.clock, print
os.clock = function() return cpu end
local lines = {}
print = function(line) lines[#lines + 1] = line end
GameRules = { GetGameModeEntity = function() return {
    SetContextThink = function(_, _, fn) callback = fn end,
} end }
local failure = { name = "original_failure" }
local emit = function(name, value) cpu = cpu + 0.003; return name, nil, value end
local request = function() cpu = cpu + 0.001; error(failure) end
local think = function() cpu = cpu + 0.010; return 0.05 end
package.loaded["core/event_bus"] = { emit = emit, request = request }
local world_resets = 0
local init = function() world_resets = world_resets + 1 end
package.loaded["core/scheduler"] = { think = think, init = init, task_count = function() return 3 end }
package.loaded["combat/damage_transaction_repository"] = { count = function() return 7 end }
FindUnitsInRadius = function() return { 42 }, nil, "tail" end
local radius = FindUnitsInRadius
ParticleManager = {
    CreateParticle = function(_, path) return 42, nil, path end,
    DestroyParticle = function() end, ReleaseParticleIndex = function() end,
}
local create = ParticleManager.CreateParticle
local capture = require("tests/manual_boss_performance")
local bus = package.loaded["core/event_bus"]
assert(not capture.run(5) and bus.emit == emit)
tools, server = true, false
assert(not capture.run(5))
server = true
_G.SURVIVAL_COMBAT_PERFORMANCE_CAPTURE = {}
assert(not capture.run(5) and bus.emit == emit)
_G.SURVIVAL_COMBAT_PERFORMANCE_CAPTURE = nil
assert(capture.run(5))
local wrapper = bus.emit
assert(not capture.run(5) and bus.emit == wrapper)
local a, b, c = bus.emit("resource_changed", 99)
assert(a == "resource_changed" and b == nil and c == 99)
local ok, err = pcall(bus.request)
assert(not ok and err == failure, "error object must survive wrapping")
assert(package.loaded["core/scheduler"].think() == 0.05)
local units, middle, tail = FindUnitsInRadius()
assert(units[1] == 42 and middle == nil and tail == "tail")
for i = 1, 300 do
    bus.emit("event_" .. i)
    local id, blank, path = ParticleManager:CreateParticle("particles/probe_" .. i)
    assert(id == 42 and blank == nil and path == "particles/probe_" .. i)
end
assert(_G.SURVIVAL_BOSS_PERFORMANCE_CAPTURE.events.size == 65)
assert(_G.SURVIVAL_BOSS_PERFORMANCE_CAPTURE.particles.size == 65)
time = 4
assert(callback() == 0.25)
time = 5
assert(callback() == nil and bus.emit == emit and bus.request == request)
assert(ParticleManager.CreateParticle == create and FindUnitsInRadius == radius)
local output = table.concat(lines, "\n")
assert(output:find("name=scheduler.think calls=1 total_ms=10.000 max_ms=10.000", 1, true))
assert(output:find("name=event_bus.request calls=1 total_ms=1.000 max_ms=1.000 errors=1", 1, true))
assert(output:find("particle_created name=<other>", 1, true))
assert(output:find("damage_records=7", 1, true))
assert(output:find("particle_releases_are_not_particle_deaths", 1, true))
assert(#lines <= 68 and not capture.stop())
assert(capture.run(5))
local reloaded = function() return "reloaded" end
bus.emit = reloaded
assert(capture.stop() and bus.emit == reloaded and callback() == nil)
assert(capture.run(5))
package.loaded["core/scheduler"].init()
assert(world_resets == 1 and package.loaded["core/scheduler"].init == init)
assert(not capture.stop() and callback() == nil, "new world stops old hooks")
-- A read-only native manager is skipped and explicitly reported.
ParticleManager = setmetatable({}, { __index = { CreateParticle = create },
    __newindex = function() error("native methods are read-only") end })
assert(capture.run(5) and capture.stop())
assert(table.concat(lines, "\n"):find("unavailable_hooks=", 1, true))
os.clock = nil
assert(capture.run(1))
time = 6
assert(callback() == nil)
assert(table.concat(lines, "\n"):find("clock=engine_Time", 1, true))
GameRules.GetGameModeEntity = function() return {
    SetContextThink = function() error("timer_rejected") end,
} end
local started, why = capture.run(1)
assert(not started and tostring(why):find("timer_rejected", 1, true))
assert(not _G.SURVIVAL_BOSS_PERFORMANCE_CAPTURE and bus.emit == reloaded)
assert(FindUnitsInRadius == radius, "failed timer setup restores all installed hooks")
print, os.clock = original_print, original_clock
print("BOSS_PERFORMANCE_CAPTURE_PASS: tools gate, clock costs, nil returns/error identity, bounded events/particles, cleanup, reload/world reset, read-only engine hooks, clock fallback")
