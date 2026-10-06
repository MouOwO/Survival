package.path = "scripts/vscripts/?.lua;" .. package.path
local scheduler = require("core/scheduler")
local time, installed = 0, {}
local mode = { SetContextThink = function(_, name, callback, delay)
    assert(name == "SurvivalSchedulerThink" and delay == 0.05)
    installed[#installed + 1] = callback
end }
GameRules = { GetGameTime = function() return time end,
    GetGameModeEntity = function() return mode end }
local function advance(amount)
    time = time + amount
    assert(scheduler.think() == 0.05)
end
local function reset()
    scheduler.clear()
    time = 0
end

-- Whichever due callback runs first replaces the other with future work.
-- This reproduces stable health-guard IDs without depending on pairs order.
reset()
local original, future = 0, 0
local function first(other)
    return function()
        original = original + 1
        scheduler.after(1, function() future = future + 1 end, other)
    end
end
scheduler.after(0, first("guard_b"), "guard_a")
scheduler.after(0, first("guard_a"), "guard_b")
advance(0)
assert(original == 1 and future == 0 and scheduler.task_count() == 1,
    "future replacement must neither run early nor be removed by the old due batch")
advance(0.99)
assert(future == 0 and scheduler.task_count() == 1)
advance(0.02)
assert(future == 1 and scheduler.task_count() == 0)

reset()
local first_runs, replacement_runs = 0, 0
scheduler.after(0, function()
    first_runs = first_runs + 1
    scheduler.after(1, function() replacement_runs = replacement_runs + 1 end, "self")
    return 0.01
end, "self")
advance(0); advance(0.02)
assert(first_runs == 1 and replacement_runs == 0 and scheduler.task_count() == 1,
    "explicit self-reschedule must win over returned repeat interval")
advance(1)
assert(replacement_runs == 1 and scheduler.task_count() == 0)

reset()
local once, repeats = 0, 0
scheduler.after(0.1, function() once = once + 1 end)
scheduler.every(0.1, function()
    repeats = repeats + 1
    if repeats == 3 then return false end
end, "normal_repeat")
advance(0.11); advance(0.11); advance(0.11)
assert(once == 1 and repeats == 3 and scheduler.task_count() == 0)

reset()
local cancelled_runs = 0
local cancelled = scheduler.after(0, function() cancelled_runs = cancelled_runs + 1 end)
scheduler.cancel(cancelled)
scheduler.every(0, function()
    cancelled_runs = cancelled_runs + 1
    scheduler.cancel("cancel_self")
end, "cancel_self")
advance(0); advance(1)
assert(cancelled_runs == 1 and scheduler.task_count() == 0,
    "cancelling a running repeat must prevent interval-based resurrection")

reset()
local clear_runs, after_clear = 0, 0
scheduler.every(0, function()
    clear_runs = clear_runs + 1
    scheduler.clear()
    scheduler.after(0.2, function() after_clear = after_clear + 1 end, "after_clear")
end, "clear_repeat")
advance(0); advance(0.1)
assert(clear_runs == 1 and after_clear == 0 and scheduler.task_count() == 1)
advance(0.11)
assert(after_clear == 1 and scheduler.task_count() == 0,
    "clear must invalidate the old repeat and retain subsequently scheduled work")

reset()
scheduler.init()
local old_think = installed[#installed]
local new_world_runs = 0
scheduler.every(0, function()
    scheduler.init()
    scheduler.after(0.2, function() new_world_runs = new_world_runs + 1 end, "new_world")
end, "init_repeat")
assert(old_think() == 0.05)
assert(old_think() == nil, "init must invalidate the old engine callback")
local new_think = installed[#installed]
assert(new_think ~= old_think and scheduler.task_count() == 1)
time = 0.21; assert(new_think() == 0.05)
assert(new_world_runs == 1 and scheduler.task_count() == 0,
    "init inside a repeat must not revive the old-world repeat")
scheduler.clear()
local after_plain_clear = 0
scheduler.after(0, function() after_plain_clear = after_plain_clear + 1 end)
assert(new_think() == 0.05 and after_plain_clear == 1,
    "plain clear must leave the engine scheduler binding active")
print("SCHEDULER_REPLACEMENT_PASS due identity, future retention, explicit self-reschedule, after/every/cancel/clear, clear/init reentry and engine binding")
