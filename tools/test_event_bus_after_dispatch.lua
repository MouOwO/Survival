package.path = "scripts/vscripts/?.lua;" .. package.path
local bus = require("core/event_bus")
local trace = {}
local function mark(value) trace[#trace + 1] = value end
local function expect(value)
    assert(table.concat(trace, "|") == value, table.concat(trace, "|"))
end

bus.after_dispatch("outside", function() mark("immediate") end)
expect("immediate")
bus.reset(); trace = {}
bus.subscribe("inner", function()
    mark("inner")
    bus.after_dispatch("a", function() mark("replaced-inner") end)
    bus.after_dispatch("b", function() mark("b") end)
end)
bus.subscribe("outer", function()
    mark("start")
    bus.after_dispatch("a", function() mark("replaced-outer") end)
    bus.emit("inner")
    bus.after_dispatch("a", function() mark("a-final") end)
    mark("end")
end)
bus.emit("outer")
expect("start|inner|end|a-final|b")

-- A drain callback can enqueue its own key through a nested event. It runs
-- later in the same drain rather than recursing into the unfinished callback.
bus.reset(); trace = {}
bus.subscribe("reenter", function()
    mark("nested")
    bus.after_dispatch("again", function() mark("obsolete") end)
end)
bus.subscribe("outer", function()
    bus.after_dispatch("again", function()
        mark("callback-start")
        bus.emit("reenter")
        bus.after_dispatch("again", function() mark("callback-next") end)
        mark("callback-end")
    end)
end)
bus.emit("outer")
expect("callback-start|nested|callback-end|callback-next")

-- Errors cannot suppress other keys or leave the bus stuck in a dispatch.
bus.reset(); trace = {}
local original_print, logs = print, {}
print = function(value) logs[#logs + 1] = value end
bus.subscribe("outer", function()
    bus.after_dispatch("failure", function() error("expected deferred failure") end)
    bus.after_dispatch("survivor", function() mark("survived") end)
    error("expected subscriber failure")
end)
bus.emit("outer")
bus.after_dispatch("outside", function() mark("outside") end)
print = original_print
expect("survived|outside")
assert(#logs == 2 and logs[1]:find("expected subscriber failure", 1, true)
    and logs[2]:find("expected deferred failure", 1, true))

-- Reset drops queued work from the old world; the new world's nested event
-- and deferred callback still complete before their own emit returns.
bus.reset(); trace = {}
bus.subscribe("outer", function()
    bus.after_dispatch("old", function() error("retired job ran") end)
    bus.reset()
    bus.subscribe("new", function()
        mark("new-event")
        bus.after_dispatch("new", function() mark("new-final") end)
    end)
    bus.emit("new")
    mark("old-return")
end)
bus.emit("outer")
expect("new-event|new-final|old-return")

bus.reset(); trace = {}
bus.subscribe("outer", function()
    bus.after_dispatch("reset", function()
        mark("reset")
        bus.reset()
        bus.after_dispatch("fresh", function() mark("fresh") end)
    end)
    bus.after_dispatch("retired", function() error("retired drain job ran") end)
end)
bus.emit("outer")
expect("reset|fresh")
assert(not pcall(bus.after_dispatch, nil, function() end))
assert(not pcall(bus.after_dispatch, "bad", {}))
print("EVENT_BUS_AFTER_DISPATCH_PASS keyed coalescing, synchronous outer/nested drain, reentry, errors and world reset")
