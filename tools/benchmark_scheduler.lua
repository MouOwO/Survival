-- Deterministic queue workload, not a measurement of Dota frame time.
package.path = "scripts/vscripts/?.lua;" .. package.path
local time = 0
GameRules = {GetGameTime = function() return time end}
local scheduler = arg and arg[1] and dofile(arg[1]) or require("core/scheduler")
local original_pairs = pairs
local visits, callbacks = 0, 0
for i = 1, 1000 do
    scheduler.after(30, function() callbacks = callbacks + 1 end, "future_" .. i)
end
pairs = function(t)
    local next_item, state, first = original_pairs(t)
    return function(s, k)
        local key, value = next_item(s, k)
        if key ~= nil then visits = visits + 1 end
        return key, value
    end, state, first
end
for tick = 1, 200 do time = tick * 0.05; scheduler.think() end
pairs = original_pairs
local idle_visits = visits
assert(callbacks == 0 and scheduler.task_count() == 1000)
time = 30; scheduler.think()
assert(callbacks == 1000 and scheduler.task_count() == 0)

-- Separate uninstrumented CPU timing. Informational only; never a test threshold.
scheduler.clear(); time = 0
for i = 1, 1000 do scheduler.after(1000, function() end) end
local started = os.clock()
for tick = 1, 10000 do time = tick * 0.05; scheduler.think() end
local elapsed_ms = (os.clock() - started) * 1000
print(string.format('{"kind":"offline_lua_simulation","tasks":1000,"idle_ticks":200,"idle_entries_visited":%d,"callbacks_at_deadline":%d,"timed_idle_ticks":10000,"cpu_ms":%.3f}',
    idle_visits, callbacks, elapsed_ms))
