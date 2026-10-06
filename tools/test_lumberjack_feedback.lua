package.path = "scripts/vscripts/?.lua;" .. package.path
local now, green, gold = 0, {}, {}
GameRules = {GetGameTime = function() return now end}
PlayerResource = {GetPlayer = function(_, id) return id ~= 2 and {id = id} or nil end}
package.loaded["core/particle_manager"] = {show_green_number = function(unit, amount, player)
    green[#green + 1] = {unit = unit, amount = amount, player = player.id}
end}
CustomGameEventManager = {Send_ServerToPlayer = function(_, player, event, data)
    assert(event == "survival_gold_mine_income_number")
    gold[#gold + 1] = {player = player.id, data = data}
end}
local scheduler = require("core/scheduler")
local feedback = require("systems/harvest_feedback_service")
local function worker(id)
    return {entindex = function() return id end, IsNull = function(self) return self.removed == true end}
end
local a, b = worker(10), worker(11)
for i = 1, 1000 do feedback.add(0, a, i, 2) end
assert(scheduler.task_count() == 1 and #green == 0 and #gold == 0)
feedback.add(1, a, 7, 3)
feedback.add(0, b, 9, 4)
assert(scheduler.task_count() == 3, "players and workers remain independent")
now = 0.249; scheduler.think(); assert(#green == 0)
now = 0.25; scheduler.think()
assert(#green == 3 and #gold == 3 and scheduler.task_count() == 0)
assert(green[1].unit == a and green[1].amount == 500500 and green[1].player == 0)
assert(gold[1].player == 0 and gold[1].data.amount == 2000 and gold[1].data.target_entindex == 10)
assert(green[2].player == 1 and green[2].amount == 7 and gold[2].player == 1)
assert(green[3].unit == b and green[3].amount == 9)

-- Pause never spins, reschedules or loses totals. Resume displays one batch.
feedback.add(0, a, 20, 0)
for i = 1, 100 do scheduler.think() end
assert(#green == 3 and scheduler.task_count() == 1)
now = 0.5; scheduler.think(); assert(#green == 4 and #gold == 3 and green[4].amount == 20)

-- Removed/recycled units, missing players, disconnect and map reset must not
-- leak labels, cross-owner totals or timers into replacement entities.
feedback.add(0, a, 10, 2); a.removed = true
now = 0.75; scheduler.think(); assert(#green == 4)
feedback.add(2, b, 10, 2); now = 1; scheduler.think(); assert(#green == 4)
feedback.add(0, b, 10, 2); feedback.add(1, b, 20, 3)
feedback.reset(0); assert(scheduler.task_count() == 1)
now = 1.25; scheduler.think(); assert(#green == 5 and green[5].player == 1 and green[5].amount == 20)
feedback.add(0, b, 10, 2); feedback.reset(); assert(scheduler.task_count() == 0)
local old, replacement = worker(20), worker(20)
feedback.add(0, old, 100, 1); feedback.add(0, replacement, 3, 2)
now = 1.5; scheduler.think()
assert(#green == 6 and green[6].unit == replacement and green[6].amount == 3)
feedback.add(-1, b, 1, 1); feedback.add(0, a, 1, 1)
assert(scheduler.task_count() == 0)
print("LUMBERJACK_FEEDBACK_PASS: 1000 hits -> 1 wood overhead + 1 gold label per worker; exact sums; private owners/workers; pause/removal/reuse/disconnect/reset")
