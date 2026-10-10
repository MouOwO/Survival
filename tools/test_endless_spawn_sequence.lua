-- Exercise production bus/scheduler/endless logic with only native unit creation
-- and archive I/O replaced. No assumptions about native frame rate or CPU time.
package.path = "scripts/vscripts/?.lua;" .. package.path

local bus, events = require("core/event_bus"), require("core/events")
local scheduler = require("core/scheduler")
local guard = require("systems/gameplay_phase_guard")
local noop = function() end
local clock, serial, units, attempts, rewards, publications, changes
local removed, cleared_visuals, death_visuals, phase_expired, defeated
local fail_attempt, fail_setter_attempt, throw_attempt, wave_limit, spawn_hook, record_hook, fail_score
local rules = {monsters_per_wave = 5, spawn_interval = 0.5, time_limit_seconds = 60,
    attack_speed = 1, magic_resistance = 20, model_path = "test/endless.vmdl",
    model_scale = 1, move_speed = 300, attack_range = 100}

package.loaded["systems/archive_endless_config"] = {
    rules = rules,
    wave = function(_, number)
        if wave_limit and number > wave_limit then return nil end
        return {health = 100 * number, attack = number, war3_armor = number}
    end,
    score = function(number)
        if fail_score then error("score calculation exception") end
        return number * 7
    end,
}
package.loaded["systems/player_context_service"] = {
    is_defeated = function(id) return defeated[id] == true end,
}
package.loaded["systems/archive_service"] = {
    record_endless_wave = function(id, number, difficulty)
        if record_hook then record_hook(id, number, difficulty) end
        rewards[#rewards + 1] = {player_id = id, wave = number, difficulty = difficulty}
    end,
}
package.loaded["systems/monster_hero_visual_service"] = {
    clear = function(unit)
        cleared_visuals[unit.id] = (cleared_visuals[unit.id] or 0) + 1
    end,
    on_death = function(unit)
        death_visuals[unit.id] = (death_visuals[unit.id] or 0) + 1
    end,
}
package.loaded["systems/wave_system"] = {
    spawn_challenge_monster = function(row, definition, player_id)
        attempts = attempts + 1
        if attempts == throw_attempt then error("native spawn exception") end
        if attempts == fail_attempt then return nil, "native_create_failed" end
        serial = serial + 1
        local unit = {id = serial, owner = player_id, born_at = clock,
            alive = true, row = row, definition = definition, attempt = attempts}
        function unit:IsNull() return self.removed == true end
        function unit:IsAlive() return self.alive and not self.removed end
        function unit:entindex() return self.id end
        function unit:SetDeathXP()
            if self.attempt == fail_setter_attempt then error("native setter exception") end
        end
        unit.SetMinimumGoldBounty, unit.SetMaximumGoldBounty = noop, noop
        unit.SetBaseMagicalResistanceValue = noop
        units[#units + 1] = unit
        if spawn_hook then spawn_hook(unit) end
        return unit
    end,
}
PlayerResource = {GetPlayer = function(_, id) return {player_id = id} end}
CustomGameEventManager = {
    Send_ServerToPlayer = function(_, player, event_name, snapshot)
        assert(event_name == "survival_endless_state")
        publications[#publications + 1] = {player_id = player.player_id, snapshot = snapshot}
    end,
}
GameRules = {GetGameTime = function() return clock end}
UTIL_Remove = function(unit)
    unit.removed, unit.alive = true, false
    removed[unit.id] = (removed[unit.id] or 0) + 1
    bus.emit(events.ENGINE_ENTITY_KILLED, {victim = unit, victim_entindex = unit.id})
end
local endless = require("systems/archive_endless_service")

local assertions = 0
local function check(value, reason)
    assertions = assertions + 1
    assert(value, reason)
end
local function setup()
    -- Release any preceding scenario before resetting the mock's bookkeeping.
    if units then for id = 0, 3 do endless.cancel(id, "fixture reset") end end
    clock, serial, attempts = 0, 0, 0
    units, rewards, publications, changes = {}, {}, {}, {}
    removed, cleared_visuals, death_visuals, defeated = {}, {}, {}, {}
    phase_expired, fail_attempt, fail_setter_attempt, throw_attempt, wave_limit = false, nil, nil, nil, nil
    spawn_hook, record_hook, fail_score = nil, nil, false
    rules.monsters_per_wave, rules.spawn_interval, rules.time_limit_seconds = 5, 0.5, 60
    bus.reset()
    scheduler.clear()
    guard.reset()
    guard.set_post_clear_frozen(true)
    bus.handle_request("archive.challenge_state", function() return {expired = phase_expired and 1 or 0} end)
    endless.init(function(id) changes[id] = (changes[id] or 0) + 1 end)
end
local function tick(value)
    clock = value
    scheduler.think()
end
local function kill(unit)
    unit.alive = false
    bus.emit(events.ENGINE_ENTITY_KILLED, {victim = unit, victim_entindex = unit.id})
end
local function living(player_id)
    local result = {}
    for _, unit in ipairs(units) do
        if unit.owner == player_id and unit:IsAlive() then result[#result + 1] = unit end
    end
    return result
end
local function count_births(player_id)
    local count = 0
    for _, unit in ipairs(units) do if unit.owner == player_id then count = count + 1 end end
    return count
end
local function all_removed(reason)
    for _, unit in ipairs(units) do
        if not death_visuals[unit.id] then
            check(removed[unit.id] == 1 and cleared_visuals[unit.id] == 1, reason)
        end
    end
end

setup()
check(endless.start(0, 1), "first monster is created synchronously")
check(#units == 1 and units[1].born_at == 0, "start cannot create an entire wave in one frame")
check(not guard.post_clear_frozen(), "ordinary gameplay remains enabled during births")
check(endless.snapshot(0).remaining == 5 and endless.snapshot(0).pending == 4,
    "remaining includes queued births so the client does not mistake a temporary empty lane for a cleared wave")
check(endless.snapshot(0).seconds == 60, "deadline begins at wave start")
tick(0.49)
check(#units == 1, "next birth waits for its configured interval")
for number = 2, 5 do
    tick((number - 1) * 0.5)
    check(#units == number, "one pending monster per spawn callback")
    check(units[number].born_at == (number - 1) * 0.5, "birth deadlines follow the configured interval")
end
check(endless.snapshot(0).remaining == 5 and endless.snapshot(0).seconds == 58,
    "births cannot extend the sixty-second deadline")
check(changes[0] == 1, "births and countdowns must not republish every archive hub ability")
tick(3)
check(changes[0] == 1, "idle countdown only sends the endless state")
for _, unit in ipairs(living(0)) do kill(unit) end
check(#rewards == 1 and rewards[1].wave == 1 and endless.snapshot(0).score == 7,
    "completed wave records exactly one reward")
check(changes[0] == 1, "kill counter updates must not repaint archive abilities")
kill(units[1])
check(#rewards == 1, "duplicate death events cannot count twice")
tick(3.01)
check(#units == 6 and endless.snapshot(0).wave == 2, "next wave starts asynchronously with one monster")

setup()
check(endless.start(0, 1))
kill(units[1])
check(endless.snapshot(0).remaining == 4 and endless.snapshot(0).pending == 4 and #rewards == 0 and endless.is_running(0),
    "death during spawning is recorded but pending births prevent early completion")
for number = 2, 5 do
    tick((number - 1) * 0.5)
    check(#units == number and endless.snapshot(0).wave == 1, "early deaths cannot advance the wave")
    kill(units[number])
    check(#rewards == (number == 5 and 1 or 0), "last planned birth and death are required for reward")
end
check(endless.snapshot(0).remaining == 0 and endless.snapshot(0).cleared == 1,
    "all five early deaths clear the current wave")
tick(2.01)
check(#units == 6 and endless.snapshot(0).wave == 2, "early-death wave schedules only one successor")

setup()
spawn_hook = kill
check(endless.start(0, 1), "a native spawn listener may kill the first monster synchronously")
check(endless.snapshot(0).remaining == 4 and endless.snapshot(0).pending == 4 and #rewards == 0,
    "synchronous factory death is recovered after the unit is registered")
for number = 2, 5 do
    tick((number - 1) * 0.5)
    check(#units == number and #rewards == (number == 5 and 1 or 0),
        "synchronous newborn deaths count once and never advance past pending births")
end
for _, unit in ipairs(units) do check(death_visuals[unit.id] == 1, "newborn death cleanup runs exactly once") end
check(endless.snapshot(0).remaining == 0 and endless.snapshot(0).score == 7,
    "five synchronous newborn deaths produce exactly one complete wave")
tick(2.01)
check(#units == 6 and endless.snapshot(0).wave == 2, "synchronous deaths do not recursively create the next wave")

setup()
spawn_hook = function(unit) endless.cancel(unit.owner, "factory listener cancelled") end
check(not endless.start(0, 1), "a factory listener cancelling the first birth returns a failed start")
check(not endless.is_running(0) and #units == 1 and #rewards == 0,
    "an unregistered first newborn cannot escape cancellation")
all_removed("cancelled first newborn is cleaned after native creation returns")
tick(2)
check(#units == 1 and scheduler.task_count() == 0 and guard.post_clear_frozen(),
    "synchronous cancellation leaves no timer, queued birth or gameplay window")

setup()
check(endless.start(0, 1))
spawn_hook = function(unit) endless.cancel(unit.owner, "factory listener cancelled") end
tick(0.5)
check(not endless.is_running(0) and #units == 2 and #rewards == 0,
    "a later factory listener may cancel both the tracked lane and the unregistered newborn")
all_removed("later cancellation releases both old and newborn units once")
tick(2)
check(#units == 2 and scheduler.task_count() == 0, "later factory cancellation cannot reschedule itself")

setup()
check(endless.start(0, 1))
spawn_hook = function() endless.init(function(id) changes[id] = (changes[id] or 0) + 1 end) end
tick(0.5)
check(not endless.is_running(0) and endless.snapshot(0).status == "idle" and #units == 2,
    "init inside native creation invalidates the old run identity")
all_removed("reentrant reset releases the newborn returned by an obsolete factory callback")
tick(2)
check(#units == 2 and #rewards == 0 and scheduler.task_count() == 0,
    "a stale factory return cannot install a birth task into the new session")

setup()
check(endless.start(0, 1))
tick(10)
check(#units == 2, "a late scheduler tick must not catch up all queued births in one frame")
tick(10)
check(#units == 2, "repeated same-time scheduler turns cannot burst-create pending monsters")
tick(10.49)
check(#units == 2, "late birth schedules the next interval from its actual callback time")
tick(10.5)
check(#units == 3 and endless.snapshot(0).seconds == 50, "late scheduler does not reset the wave deadline")

setup()
for id = 0, 3 do check(endless.start(id, 1), "all four players can run an isolated challenge") end
check(#units == 4, "four simultaneous players create four initial monsters rather than twenty")
check(scheduler.task_count() <= 5, "four players share one countdown and at most one pending birth task each")
for number = 2, 5 do
    tick((number - 1) * 0.5)
    check(#units == number * 4, "each player creates exactly one monster per interval")
    for id = 0, 3 do
        check(count_births(id) == number and endless.snapshot(id).remaining == 5
                and endless.snapshot(id).pending == 5 - number,
            "birth bookkeeping never crosses player ownership")
    end
end
for _, unit in ipairs(living(0)) do kill(unit) end
check(#rewards == 1 and rewards[1].player_id == 0, "kills only award their own player")
check(endless.snapshot(1).remaining == 5 and endless.snapshot(2).remaining == 5 and endless.snapshot(3).remaining == 5,
    "other players remain unchanged when one wave completes")
endless.cancel(1, "manual stop")
check(endless.is_running(0) and endless.is_running(2) and endless.is_running(3),
    "cancellation only closes one player's challenge")
check(not guard.post_clear_frozen(), "other active players retain their ordinary gameplay window")

setup()
check(endless.start(0, 1))
tick(0.5)
endless.cancel(0, "manual stop")
check(not endless.is_running(0) and guard.post_clear_frozen(), "stop closes the last active gameplay window")
check(changes[0] == 2, "start and stop are the only archive ability state transitions")
all_removed("cancellation releases both live units and their visuals once")
local previous_births = #units
tick(120)
check(#units == previous_births and #rewards == 0, "cancelled spawn callbacks cannot create or reward monsters")
check(scheduler.task_count() == 0, "no endless timer or spawn task survives the last active run")

setup()
check(endless.start(0, 1))
phase_expired = true
tick(0.5)
check(#units == 1 and not endless.is_running(0) and #rewards == 0,
    "phase expiry prevents a queued birth before it reaches native creation")
all_removed("phase expiry cleans the existing monster")

setup()
check(endless.start(0, 1))
tick(60)
check(#units == 1 and not endless.is_running(0) and #rewards == 0,
    "the wave deadline also applies while pending births remain")
all_removed("birth timeout cleans the existing monster")

setup()
rules.monsters_per_wave = 1
check(endless.start(0, 1))
clock = 60
kill(units[1])
check(#rewards == 0 and not endless.is_running(0), "boundary deaths cannot award a timed-out wave before the timer runs")

setup()
check(endless.start(0, 1))
phase_expired = true
kill(units[1])
check(#rewards == 0 and not endless.is_running(0), "phase-boundary deaths stop queued births without a reward")
tick(1)
check(#units == 1 and scheduler.task_count() == 0, "phase-boundary death cancels the pending spawn")

setup()
check(endless.start(0, 1))
defeated[0] = true
bus.emit(events.PLAYER_DEFEATED, {player_id = 0})
check(not endless.is_running(0) and guard.post_clear_frozen(), "player defeat closes the spawn sequence")
all_removed("player defeat releases its live monster")
tick(1)
check(#units == 1 and #rewards == 0 and scheduler.task_count() == 0, "defeat cannot leave a scheduled birth")

setup()
rules.spawn_interval = 0.3
check(endless.start(0, 1))
tick(0.299)
check(#units == 1, "the birth delay follows CSV configuration rather than a hardcoded half-second")
tick(0.3)
check(#units == 2, "configured shorter interval creates the next monster")
tick(0.6)
check(#units == 3, "configured interval applies to subsequent births too")

for _, failure_kind in ipairs({"return_nil", "throw_spawn", "throw_setter"}) do
    setup()
    check(endless.start(0, 1))
    if failure_kind == "return_nil" then fail_attempt = 3
    elseif failure_kind == "throw_spawn" then throw_attempt = 3
    else fail_setter_attempt = 3 end
    tick(0.5)
    tick(1)
    check(not endless.is_running(0) and #rewards == 0 and guard.post_clear_frozen(),
        "partial wave failure ends the run without awarding partial credit: " .. failure_kind)
    all_removed("partial wave failure releases every created unit: " .. failure_kind)
    previous_births = #units
    tick(120)
    check(#units == previous_births and scheduler.task_count() == 0,
        "partial wave failure cancels subsequent births and timers: " .. failure_kind)
end

setup()
fail_attempt = 1
check(not endless.start(0, 1) and #units == 0 and not endless.is_running(0),
    "first birth failure remains a synchronous start error")
check(guard.post_clear_frozen() and scheduler.task_count() == 0, "first-birth failure leaves no active window or tasks")
fail_attempt = nil
check(endless.start(0, 1), "a failed first birth does not consume the player's single start")

setup()
for id = 0, 3 do check(endless.start(id, 1)) end
tick(0.5)
endless.init(function(id) changes[id] = (changes[id] or 0) + 1 end)
all_removed("map reset releases old live units and their appearances")
for id = 0, 3 do check(not endless.is_running(id), "map reset removes every old run") end
previous_births = #units
tick(120)
check(#units == previous_births and #rewards == 0 and scheduler.task_count() == 0,
    "map reset cannot resurrect old queued births or idle timers")
check(guard.post_clear_frozen(), "map reset releases old gameplay windows")

setup()
rules.monsters_per_wave, wave_limit = 1, 1
check(endless.start(0, 1))
kill(units[1])
check(#rewards == 1 and endless.snapshot(0).score == 7, "single-monster configurations preserve immediate death rewards")
tick(0)
check(not endless.is_running(0) and #units == 1 and scheduler.task_count() == 0,
    "the last configured wave finishes without scheduling a new birth")

for _, failure_kind in ipairs({"record", "score"}) do
    setup()
    rules.monsters_per_wave = 1
    check(endless.start(0, 1))
    if failure_kind == "record" then
        record_hook = function() error("archive record exception") end
    else
        fail_score = true
    end
    kill(units[1])
    local state = endless.snapshot(0)
    check(not endless.is_running(0) and state.status == "finished" and state.cleared == 0 and state.score == 0,
        "settlement exception stops the run without marking the failed wave cleared: " .. failure_kind)
    check(#rewards == 0 and guard.post_clear_frozen() and scheduler.task_count() == 0,
        "settlement exception cannot leave a playable window, countdown or successor: " .. failure_kind)
    tick(120)
    check(#units == 1 and scheduler.task_count() == 0,
        "settlement exception never turns into a permanently running empty wave: " .. failure_kind)
end

setup()
rules.monsters_per_wave = 1
check(endless.start(0, 1))
record_hook = function(id) endless.cancel(id, "record listener cancelled") end
kill(units[1])
check(not endless.is_running(0) and guard.post_clear_frozen() and scheduler.task_count() == 0,
    "record callback cancellation cannot install a next-wave task after stopping the run")
tick(120)
check(#units == 1 and scheduler.task_count() == 0, "record callback cancellation cannot spawn a successor later")

setup()
rules.monsters_per_wave = 1
check(endless.start(0, 1))
record_hook = function() endless.init(function(id) changes[id] = (changes[id] or 0) + 1 end) end
kill(units[1])
check(not endless.is_running(0) and endless.snapshot(0).status == "idle" and scheduler.task_count() == 0,
    "record callback reset invalidates the old run before a successor is scheduled")
tick(120)
check(#units == 1 and scheduler.task_count() == 0, "obsolete settlement callback cannot spawn into the new session")

setup()
wave_limit = 20
for id = 0, 3 do check(endless.start(id, 1)) end
local expected_score = 0
for wave = 1, wave_limit do
    for _ = 2, 5 do
        tick(clock + 0.5)
        check(scheduler.task_count() <= 5, "repeated four-player waves retain bounded scheduler tasks")
    end
    expected_score = expected_score + wave * 7
    for id = 0, 3 do
        local alive = living(id)
        check(#alive == 5, "repeated waves contain five distinct live units per player")
        for _, unit in ipairs(alive) do kill(unit) end
        local state = endless.snapshot(id)
        check(state.remaining == 0 and state.pending == 0 and state.cleared == wave
                and state.score == expected_score, "repeated wave scores and death counts remain exact")
    end
    tick(clock + 0.01)
end
check(#units == 400 and #rewards == 80 and scheduler.task_count() == 0,
    "twenty waves across four players finish without duplicate births, rewards or idle tasks")
for _, unit in ipairs(units) do
    check(death_visuals[unit.id] == 1 and not removed[unit.id],
        "death visual cleanup occurs once without removing the corpse before its own lifecycle finishes")
end
for id = 0, 3 do
    check(not endless.is_running(id) and changes[id] == 2, "repeated waves only repaint archive abilities at start and finish")
end

print("ENDLESS_SPAWN_SEQUENCE_PASS: " .. assertions ..
    " checks; sequential births, early deaths, late scheduling, four players, cancellation, timeout, failure and reset")
