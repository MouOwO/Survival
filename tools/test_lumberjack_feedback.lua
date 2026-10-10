package.path = "scripts/vscripts/?.lua;" .. package.path
local now, green, gold, missing = 0, {}, {}, {[2] = true}
GameRules = {GetGameTime = function() return now end}
PlayerResource = {GetPlayer = function(_, id) return not missing[id] and {id = id} or nil end}
package.loaded["core/particle_manager"] = {show_green_number = function(unit, amount, player)
    assert(amount > 0, "zero wood must not create an overhead event")
    green[#green + 1] = {unit = unit, amount = amount, player = player.id, at = now}
end}
CustomGameEventManager = {Send_ServerToPlayer = function(_, player, event, data)
    assert(event == "survival_gold_mine_income_number" and data.amount > 0)
    assert(data.critical == 0)
    gold[#gold + 1] = {player = player.id, data = data, at = now}
end}
local scheduler = require("core/scheduler")
local feedback = require("systems/harvest_feedback_service")
local function worker(id)
    return {entindex = function() return id end, IsNull = function(self) return self.removed == true end}
end
local function at(time)
    now = time
    scheduler.think()
end
local function reset()
    feedback.reset()
    assert(scheduler.task_count() == 0)
    now, green, gold, missing = 0, {}, {}, {[2] = true}
end

-- The first of 1000 genuine hits needs no think or delay. The remaining 999
-- are exactly summed once; other players and workers have separate windows.
do
    local a, b = worker(10), worker(11)
    feedback.add(0, a, 1, 2)
    assert(#green == 1 and #gold == 1 and green[1].at == 0 and gold[1].at == 0)
    assert(green[1].amount == 1 and gold[1].data.amount == 2)
    for i = 2, 1000 do feedback.add(0, a, i, 2) end
    assert(scheduler.task_count() == 1 and #green == 1 and #gold == 1)
    feedback.add(1, a, 7, 3)
    feedback.add(0, b, 9, 4)
    assert(scheduler.task_count() == 3 and #green == 3 and #gold == 3)
    assert(green[2].player == 1 and green[2].amount == 7 and gold[2].player == 1)
    assert(green[3].unit == b and green[3].amount == 9)
    at(0.249); assert(#green == 3 and #gold == 3)
    at(0.25)
    assert(#green == 4 and #gold == 4 and scheduler.task_count() == 1)
    assert(green[4].unit == a and green[4].player == 0 and green[4].amount == 500499)
    assert(gold[4].player == 0 and gold[4].data.amount == 1998 and gold[4].data.target_entindex == 10)
    assert(green[1].amount + green[4].amount == 500500)
    assert(gold[1].data.amount + gold[4].data.amount == 2000)
    at(0.5)
    assert(scheduler.task_count() == 0 and #green == 4 and #gold == 4, "idle windows stop without empty labels")
end

-- A busy worker displays once per window, then becomes immediate again after
-- the first empty window. No hit installs a second timer for that worker.
reset()
do
    local a = worker(10)
    feedback.add(0, a, 10, 1)
    at(0.05); feedback.add(0, a, 20, 2)
    at(0.10); feedback.add(0, a, 30, 3)
    assert(scheduler.task_count() == 1)
    at(0.249); assert(#green == 1)
    at(0.25); assert(#green == 2 and green[2].amount == 50 and gold[2].data.amount == 5)
    at(0.30); feedback.add(0, a, 40, 4)
    at(0.49); feedback.add(0, a, 50, 5)
    assert(scheduler.task_count() == 1 and #green == 2)
    at(0.5); assert(#green == 3 and green[3].amount == 90 and gold[3].data.amount == 9)
    assert(green[2].at - green[1].at == 0.25 and green[3].at - green[2].at == 0.25)
    at(0.75); assert(scheduler.task_count() == 0 and #green == 3)
    feedback.add(0, a, 60, 6)
    assert(#green == 4 and green[4].at == 0.75 and green[4].amount == 60)
    at(1); assert(scheduler.task_count() == 0 and #green == 4)
end

-- Game time does not advance during pause: the one existing window stays put
-- and its accumulated tail is shown once when game time reaches the deadline.
reset()
do
    local a = worker(10)
    feedback.add(0, a, 20, 0)
    feedback.add(0, a, 30, 4)
    for i = 1, 100 do scheduler.think() end
    assert(#green == 1 and #gold == 0 and scheduler.task_count() == 1)
    at(0.25); assert(#green == 2 and green[2].amount == 30 and #gold == 1)
    at(0.5); assert(scheduler.task_count() == 0 and #green == 2)
end

-- Invalid owners, absent players, deleted workers and nonpositive rewards
-- cannot create either a label or a task. Valid numeric-string owners work.
reset()
do
    local a, removed = worker(10), worker(11)
    removed.removed = true
    feedback.add(nil, a, 1, 1)
    feedback.add(-1, a, 1, 1)
    feedback.add("bad", a, 1, 1)
    feedback.add(0.5, a, 1, 1)
    feedback.add(math.huge, a, 1, 1)
    feedback.add(0 / 0, a, 1, 1)
    feedback.add(2, a, 1, 1)
    feedback.add(0, nil, 1, 1)
    feedback.add(0, removed, 1, 1)
    feedback.add(0, a, 0, 0)
    feedback.add(0, a, -10, -2)
    feedback.add(0, a, 0.9, -2)
    feedback.add(0, a, "bad", nil)
    feedback.add(0, a, math.huge, 0 / 0)
    assert(#green == 0 and #gold == 0 and scheduler.task_count() == 0)
    feedback.add("1", a, 7, 3)
    assert(#green == 1 and green[1].player == 1 and #gold == 1)
    at(0.25); assert(scheduler.task_count() == 0)
end

-- Gold-only hits do not manufacture a zero wood label; each channel is
-- independently floored and clamped before both immediate and buffered output.
reset()
do
    local a = worker(10)
    feedback.add(0, a, -5, 5.8)
    assert(#green == 0 and #gold == 1 and gold[1].data.amount == 5)
    feedback.add(0, a, 2.9, 3.8)
    at(0.25)
    assert(#green == 1 and green[1].amount == 2 and #gold == 2 and gold[2].data.amount == 3)
    at(0.5); assert(scheduler.task_count() == 0)
end

-- Deletion or loss of the player suppresses only the undisplayed tail and
-- retires its window. A later valid hit starts a fresh immediate window.
reset()
do
    local a = worker(10)
    feedback.add(0, a, 10, 1)
    feedback.add(0, a, 20, 2)
    a.removed = true
    at(0.25); assert(#green == 1 and #gold == 1 and scheduler.task_count() == 0)
    local b = worker(11)
    feedback.add(0, b, 30, 3)
    feedback.add(0, b, 40, 4)
    missing[0] = true
    at(0.5); assert(#green == 2 and #gold == 2 and scheduler.task_count() == 0)
    feedback.add(0, b, 50, 5)
    assert(#green == 2 and scheduler.task_count() == 0)
    missing[0] = nil
    feedback.add(0, b, 60, 6)
    assert(#green == 3 and green[3].amount == 60 and scheduler.task_count() == 1)
end

-- Disconnect/reset cancels the appropriate buffered totals, including the
-- still-open idle windows, without affecting another player's window.
reset()
do
    local a = worker(10)
    feedback.add(0, a, 10, 1); feedback.add(0, a, 20, 2)
    feedback.add(1, a, 30, 3); feedback.add(1, a, 40, 4)
    feedback.reset(0)
    assert(scheduler.task_count() == 1)
    at(0.25)
    assert(#green == 3 and green[3].player == 1 and green[3].amount == 40)
    assert(#gold == 3 and gold[3].player == 1 and gold[3].data.amount == 4)
    feedback.reset("1"); assert(scheduler.task_count() == 0)
    feedback.add(0, a, 50, 5); feedback.add(0, a, 60, 6)
    feedback.reset(); assert(scheduler.task_count() == 0)
    at(1); assert(#green == 4 and #gold == 4)
    feedback.add(0, a, 70, 7)
    assert(#green == 5 and green[5].amount == 70, "reset leaves no stale entry delaying the next hit")
end

-- An entity index reused by a new worker replaces the old window and does
-- not replay the old worker's accumulated tail onto the replacement.
reset()
do
    local old, replacement = worker(20), worker(20)
    feedback.add(0, old, 100, 1); feedback.add(0, old, 200, 2)
    feedback.add(0, replacement, 3, 4); feedback.add(0, replacement, 5, 6)
    assert(#green == 2 and green[1].unit == old and green[2].unit == replacement)
    assert(scheduler.task_count() == 1 and green[2].amount == 3)
    at(0.25)
    assert(#green == 3 and green[3].unit == replacement and green[3].amount == 5)
    assert(#gold == 3 and gold[3].data.amount == 6 and gold[3].data.target_entindex == 20)
    at(0.5); assert(scheduler.task_count() == 0)
end
reset()
print("LUMBERJACK_FEEDBACK_PASS: immediate first hit; exact first+999-tail sums; independent 0.25s windows; idle stop; owners; pause/deletion/reuse/disconnect/reset; positive channels only")
