package.path = "scripts/vscripts/?.lua;" .. package.path
local Queue = require("systems/worker_training_queue_service")
local now, pending, funds, spent, refunded, finished, valid = 0, {}, 100, 0, 0, {}, true
local queue = Queue.create({capacity = 7, now = function() return now end,
    schedule = function(delay, callback, id) pending[id] = {at = now + delay, run = callback} end,
    cancel = function(id) pending[id] = nil end,
    validate = function() return valid, "removed" end,
    reserve = function(job)
        if funds < job.cost then return {ok = false, error = "poor"} end
        funds, spent = funds - job.cost, spent + job.cost
        return {ok = true}
    end,
    refund = function(job) funds, refunded = funds + job.cost, refunded + job.cost end,
    finish = function(job)
        if job.fail then return {ok = false, error = "spawn_failed"} end
        finished[#finished + 1] = job.job_id
        return {ok = true}
    end,
    changed = function() end,
})
local function add(city, player, tier, fail)
    return queue:enqueue({source_entindex = city, player_id = player, team = 2,
        training_id = tier or "lv1", duration = 1, level = 1, name = "Worker", cost = 10, fail = fail})
end
local function tick(at)
    now = at
    local due = {}
    for id, task in pairs(pending) do if task.at <= now then due[#due + 1] = {id, task} end end
    for _, item in ipairs(due) do pending[item[1]] = nil; item[2].run() end
end
assert(add(10, 0).ok and add(10, 0, "lv2").ok)
assert(#finished == 0 and funds == 80 and queue:reserved(0, "lv1") == 1)
assert(queue:snapshot(10, 1).queue_count == 0, "other players cannot inspect queue")
assert(not add(10, 1).ok, "cannot append to another player's city")
local snapshot = queue:snapshot(10, 0)
assert(snapshot.active_job.started_at == 0 and snapshot.active_job.finish_at == 1)
assert(snapshot.queue_count == 2 and snapshot.queued[1].training_id == "lv2")
assert(add(11, 1).ok, "another player trains in parallel")
tick(0.99); assert(#finished == 0)
tick(1); assert(#finished == 2 and queue:snapshot(10, 0).active_job.finish_at == 2)
tick(2); assert(#finished == 3 and queue:snapshot(10, 0).queue_count == 0)
assert(funds == 70 and refunded == 0)
assert(add(10, 0).ok and add(10, 0).ok)
local stale = pending["worker_training:10"].run
queue:cancel_player(0, "disconnected")
assert(funds == 70 and refunded == 20 and queue:reserved(0, "lv1") == 0)
stale(); stale(); assert(#finished == 3 and refunded == 20, "cancelled callbacks are idempotent")
assert(add(10, 0, "lv1", true).ok)
tick(3); assert(funds == 70 and refunded == 30, "failed completion refunds once")
for _ = 1, 7 do assert(add(10, 0).ok) end
assert(queue:snapshot(10, 0).queue_count == 7 and #queue:snapshot(10, 0).queued == 6)
local eighth = add(10, 0)
assert(not eighth.ok and eighth.error == "training_queue_full" and funds == 0,
    "eighth job rejected without charging; capacity includes active job")
valid = false; tick(4)
assert(funds == 70 and queue:snapshot(10, 0).queue_count == 0)
valid = true; assert(add(10, 0).ok)
stale = pending["worker_training:10"].run
queue:reset(); stale(); assert(#finished == 3 and queue:reserved(0, "lv1") == 0)
print("PASS independent training queue: serial completion, parallel players, reservations, capacity, ownership, refund and stale callbacks")