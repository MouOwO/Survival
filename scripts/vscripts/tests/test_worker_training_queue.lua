package.path = "scripts/vscripts/?.lua;" .. package.path
local Queue = arg and arg[1] and dofile(arg[1]) or require("systems/worker_training_queue_service")
local function eq(actual, expected, message)
    assert(actual == expected, (message or "values differ") .. ": expected " .. tostring(expected)
        .. ", got " .. tostring(actual))
end
local now, pending, wallets, sources, finished, checks, spends, refunds, publishes
local queue, missing_preflight, missing_spend, reserve_hook, finish_hook, changes, before_spend_hook
local function fixture()
    now, pending, finished, checks, spends, refunds, publishes = 0, {}, {}, 0, 0, 0, 0
    missing_preflight, missing_spend, reserve_hook, finish_hook, changes, before_spend_hook =
        false, false, nil, nil, {}, nil
    wallets = {[0] = {wood = 1000, gold = 1000, population = 0, max_population = 10},
        [1] = {wood = 1000, gold = 1000, population = 0, max_population = 10}}
    sources = {[10] = {player = 0, valid = true}, [11] = {player = 1, valid = true},
        [12] = {player = 0, valid = true}}
    local function eligibility(job)
        local funds = wallets[job.player_id]
        if funds.debug then return {ok = true} end
        if funds.wood < job.wood_cost then return {ok = false, error = "wood_not_enough"} end
        if funds.gold < job.gold_cost then return {ok = false, error = "gold_not_enough"} end
        if funds.population + job.population > funds.max_population then
            return {ok = false, error = "population_not_enough"}
        end
        return {ok = true}
    end
    queue = Queue.create({capacity = 7, now = function() return now end,
        schedule = function(delay, callback, id) pending[id] = {at = now + delay, run = callback} end,
        cancel = function(id) pending[id] = nil end,
        validate = function(job)
            local source = sources[job.source_entindex]
            if not source or not source.valid then return false, "removed" end
            if source.player ~= job.player_id then return false, "training_owner_mismatch" end
            return true
        end,
        can_reserve = function(job)
            checks = checks + 1
            if missing_preflight then return nil end
            return eligibility(job)
        end,
        reserve = function(job)
            spends = spends + 1
            if missing_spend then return nil end
            if before_spend_hook then before_spend_hook(job) end
            local result = eligibility(job)
            if not result.ok then return result end
            local funds = wallets[job.player_id]
            local charge = funds.debug and 0 or 1
            job.refund_wood, job.refund_gold, job.refund_population =
                charge * job.wood_cost, charge * job.gold_cost, charge * job.population
            funds.wood, funds.gold, funds.population = funds.wood - job.refund_wood,
                funds.gold - job.refund_gold, funds.population + job.refund_population
            if reserve_hook then reserve_hook(job) end
            return {ok = true}
        end,
        refund = function(job)
            refunds = refunds + 1
            local funds = wallets[job.player_id]
            funds.wood, funds.gold, funds.population = funds.wood + job.refund_wood,
                funds.gold + job.refund_gold, funds.population - job.refund_population
        end,
        finish = function(job)
            if finish_hook then finish_hook(job) end
            if job.fail then return {ok = false, error = "spawn_failed"} end
            finished[#finished + 1] = {job_id = job.job_id, player = job.player_id,
                city = job.source_entindex, training_id = job.training_id}
            return {ok = true}
        end,
        changed = function(player, team, city)
            publishes = publishes + 1
            changes[#changes + 1] = queue:snapshot(city, player)
        end,
    })
end
local function add(city, player, tier, options)
    options = options or {}
    return queue:enqueue({source_entindex = city or 10, player_id = player or 0, team = 2,
        training_id = tier or "lv1", duration = 1, level = options.level or 1, name = "Worker",
        wood_cost = options.wood or 100, gold_cost = options.gold or 20,
        population = options.population or 1, fail = options.fail})
end
local function snapshot(city, player) return queue:snapshot(city or 10, player or 0) end
local function timers()
    local count = 0
    for _ in pairs(pending) do count = count + 1 end
    return count
end
local function tick(at)
    now = at
    local due = {}
    for id, task in pairs(pending) do
        if task.at <= now then due[#due + 1] = {id, task} end
    end
    table.sort(due, function(left, right) return left[1] < right[1] end)
    for _, item in ipairs(due) do
        if pending[item[1]] == item[2] then
            pending[item[1]] = nil
            item[2].run()
        end
    end
end
local function blocked(reason, expected_tier, count)
    local state = snapshot()
    eq(state.queue_count, count)
    eq(state.active_job.training_id, nil, "waiting head is not active")
    eq(state.blocked_head.training_id, expected_tier)
    eq(state.blocked_head.started_at, 0, "blocked task has no starting clock")
    eq(state.blocked_head.finish_at, 0, "blocked task has no completion clock")
    eq(state.blocked_reason, reason)
    eq(timers(), 1, "each city owns a single retry timer")
end

fixture()
assert(add().ok and add(10, 0, "lv2").ok)
eq(wallets[0].wood, 900, "waiting job does not precharge currency")
eq(wallets[0].population, 1, "waiting job does not preoccupy population")
eq(spends, 1); eq(checks, 2); eq(queue:reserved(0, "lv2"), 1)
eq(snapshot(10, 1).queue_count, 0, "foreign player cannot inspect a queue")
eq(add(10, 1).error, "training_owner_mismatch")
eq(snapshot().active_job.started_at, 0); eq(snapshot().active_job.finish_at, 1)
eq(snapshot().queued[1].training_id, "lv2")
assert(add(11, 1).ok and add(12, 0, "lv1").ok, "players and cities can run in parallel")
eq(queue:reserved(0, "lv1"), 2, "quota reservations span the player's cities")
tick(0.99); eq(#finished, 0)
tick(1); eq(#finished, 3); eq(snapshot().active_job.training_id, "lv2")
eq(snapshot().active_job.finish_at, 2); eq(wallets[0].wood, 700)
tick(2); eq(#finished, 4); eq(snapshot().queue_count, 0); eq(refunds, 0)

for _, shortage in ipairs({{"wood", 99, "wood_not_enough"}, {"gold", 19, "gold_not_enough"},
    {"max_population", 0, "population_not_enough"}}) do
    fixture()
    wallets[0][shortage[1]] = shortage[2]
    eq(add().error, shortage[3]); eq(snapshot().queue_count, 0); eq(spends, 0)
    eq(publishes, 0); eq(timers(), 0)
    wallets[0] = {wood = 1000, gold = 1000, population = 0, max_population = 10}
    eq(add().job_id, 1, "rejected admission must not consume a job ID")
end
fixture(); missing_preflight = true
eq(add().error, "resource_error"); eq(snapshot().queue_count, 0); eq(spends, 0)

fixture(); assert(add().ok and add(10, 0, "lv2").ok and add(10, 0, "lv3").ok)
wallets[0].gold = 0
tick(1); eq(#finished, 1); blocked("gold_not_enough", "lv2", 2)
eq(snapshot().queued[1].training_id, "lv3", "blocked head cannot be overtaken")
eq(wallets[0].wood, 900, "failed head start spends no wood")
local stable_publish, stable_spends = publishes, spends
tick(1.99); eq(spends, stable_spends, "head is not rechecked every frame")
tick(2); blocked("gold_not_enough", "lv2", 2)
eq(publishes, stable_publish, "unchanged block does not repaint the UI")
eq(spends, stable_spends + 1, "one resource attempt per second")
wallets[0].gold = 100
tick(3); eq(snapshot().active_job.training_id, "lv2")
eq(snapshot().active_job.started_at, 3); eq(snapshot().active_job.finish_at, 4)
eq(snapshot().blocked_reason, ""); eq(wallets[0].wood, 800)
tick(4); eq(snapshot().active_job.training_id, "lv3"); eq(wallets[0].wood, 700)
tick(5); eq(#finished, 3); eq(snapshot().queue_count, 0)

fixture(); wallets[0].max_population = 2
assert(add().ok and add(10, 0, "lv2").ok and add(10, 0, "lv3").ok,
    "admission checks the new job, not the combined future population")
eq(wallets[0].population, 1)
wallets[0].max_population = 1
tick(1); blocked("population_not_enough", "lv2", 2)
eq(wallets[0].population, 1); eq(wallets[0].wood, 900)
wallets[0].max_population = 2
tick(2); eq(snapshot().active_job.training_id, "lv2"); eq(wallets[0].population, 2)
tick(3); blocked("population_not_enough", "lv3", 1)
wallets[0].population = 1 -- an unrelated unit was dismissed
tick(4); eq(snapshot().active_job.training_id, "lv3")

fixture(); assert(add().ok and add(10, 0, "lv2").ok)
wallets[0].wood = 0
tick(1); blocked("wood_not_enough", "lv2", 1)
local stale_retry = pending["worker_training:10"].run
queue:cancel_city(10, "cancelled")
eq(refunds, 0, "waiting head was not charged, so cancellation cannot mint resources")
eq(wallets[0].wood, 0); eq(timers(), 0); eq(snapshot().queue_count, 0)
stale_retry(); stale_retry(); eq(spends, 2); eq(timers(), 0)

fixture(); assert(add().ok and add(10, 0, "lv2").ok and add(12, 0).ok and add(11, 1).ok)
local stale_finish = pending["worker_training:10"].run
queue:cancel_player(0, "disconnected")
eq(refunds, 2, "only the player's charged city heads are refunded")
eq(wallets[0].wood, 1000); eq(wallets[0].population, 0)
eq(queue:reserved(0, "lv2"), 0); eq(timers(), 1)
stale_finish(); stale_finish(); eq(refunds, 2)
tick(1); eq(#finished, 1); eq(finished[1].player, 1)

fixture(); assert(add(10, 0, "lv1", {fail = true}).ok and add(10, 0, "lv2").ok)
stale_finish = pending["worker_training:10"].run
tick(1); eq(refunds, 1); eq(wallets[0].wood, 900); eq(snapshot().active_job.training_id, "lv2")
stale_finish(); eq(refunds, 1); eq(snapshot().active_job.training_id, "lv2")
tick(2); eq(#finished, 1); eq(wallets[0].wood, 900)

fixture(); for _ = 1, 7 do assert(add().ok) end
eq(snapshot().queue_count, 7); eq(#snapshot().queued, 6); eq(wallets[0].wood, 900)
eq(add().error, "training_queue_full"); eq(wallets[0].wood, 900)
sources[10].valid = false; tick(1)
eq(refunds, 1); eq(wallets[0].wood, 1000); eq(snapshot().queue_count, 0); eq(timers(), 0)

fixture(); missing_spend = true
assert(add().ok, "an atomic start race leaves the admitted first job waiting")
blocked("resource_error", "lv1", 1); eq(wallets[0].wood, 1000)
stale_retry = pending["worker_training:10"].run
missing_spend = false; tick(1)
eq(snapshot().active_job.started_at, 1); eq(wallets[0].wood, 900)
local completion_timer = pending["worker_training:10"]
stale_retry(); eq(spends, 2); eq(pending["worker_training:10"], completion_timer,
    "a consumed retry cannot replace the active job's completion timer")

fixture(); before_spend_hook = function() wallets[0].wood = 0 end
assert(add().ok, "a resource loss between preflight and spend preserves the admitted job")
blocked("wood_not_enough", "lv1", 1); eq(wallets[0].population, 0)
local previous_publishes = publishes
before_spend_hook = nil; wallets[0].wood = 1000; wallets[0].gold = 0
tick(1); blocked("gold_not_enough", "lv1", 1)
eq(publishes, previous_publishes + 1, "a different shortage updates the waiting message")
sources[10].valid = false; tick(2)
eq(snapshot().queue_count, 0); eq(refunds, 0); eq(timers(), 0,
    "invalid waiting source removes the queue without refunds or retries")

fixture(); wallets[0].debug = true
assert(add().ok and add(10, 0, "lv2").ok)
eq(wallets[0].wood, 1000); eq(wallets[0].population, 0)
queue:cancel_city(10, "cancelled")
eq(refunds, 1); eq(wallets[0].wood, 1000); eq(wallets[0].population, 0,
    "accepted debug purchases refund only their actual zero charge")

fixture(); reserve_hook = function() queue:cancel_city(10, "removed_during_spend") end
assert(add().ok)
eq(snapshot().queue_count, 0); eq(timers(), 0); eq(refunds, 1)
eq(wallets[0].wood, 1000); eq(wallets[0].population, 0,
    "cancellation during resource publication rolls back a detached reservation")

fixture(); assert(add().ok)
stale_finish = pending["worker_training:10"].run
queue:reset(); eq(timers(), 0)
assert(add(10, 0, "new_session").ok)
stale_finish(); eq(#finished, 0); eq(snapshot().active_job.training_id, "new_session")
tick(1); eq(#finished, 1)

fixture(); assert(add().ok and add(10, 0, "lv2").ok)
wallets[0].wood = 0; tick(1)
stale_retry = pending["worker_training:10"].run
queue:reset(); stale_retry(); eq(snapshot().queue_count, 0); eq(timers(), 0)
eq(refunds, 0); eq(spends, 2, "reset invalidates waiting retries as well as completion callbacks")

print("PASS independent training queue: read-only admission, deferred currency/population, FIFO resource waits, stable one-second retries, isolated players/cities, quota/capacity, refunds, debug mode and stale/reentrant callbacks")
