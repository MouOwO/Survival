-- Real event consumer; deterministic scheduler/engine transport doubles.
-- This verifies scheduling and payload correctness, not real frame times.
package.path = "scripts/vscripts/?.lua;" .. package.path
local bus = require("core/event_bus")
local events = require("core/events")
local now, tasks, calls, sent, builds = 0, {}, 0, {}, 0
package.loaded["core/scheduler"] = {
    after = function(delay, callback, id)
        calls = calls + 1
        tasks[id] = {at = now + delay, callback = callback}
    end,
    cancel = function(id) tasks[id] = nil end,
    every = function() error("idle polling must not be registered") end,
}
local function flush(at)
    now = at
    local task = tasks.ui_snapshot_flush
    assert(task and task.at <= now + 1e-9, "flush must already be due")
    tasks.ui_snapshot_flush = nil
    task.callback()
end
DOTA_MAX_TEAM_PLAYERS = 4
local players = {[0] = {id = 0}, [1] = {id = 1}, [2] = {id = 2}}
PlayerResource = {
    IsValidPlayerID = function(_, id) return players[id] ~= nil end,
    GetPlayer = function(_, id) return players[id] end,
    GetTeam = function(_, id) return id == 2 and 3 or 2 end,
}
CustomGameEventManager = {Send_ServerToPlayer = function(_, player, name, snapshot)
    assert(name == "survival_ui_private_snapshot")
    sent[#sent + 1] = {id = player.id, snapshot = snapshot}
end}
local during_build
local function register_projection()
    bus.handle_request("ui.projection.build_snapshot", function(payload)
        builds = builds + 1
        if during_build then local callback = during_build; during_build = nil; callback() end
        return {player_id = payload.player_id, build = builds}
    end)
end
local service = require("ui/ui_snapshot_service")
register_projection()
service.init()
assert(calls == 1 and tasks.ui_snapshot_flush.at == 0.25 and #sent == 0)
flush(0.25)
assert(#sent == 3 and next(tasks) == nil, "initial full snapshot is sent once, then idle")
for i = 1, 3 do assert(sent[i].snapshot.sequence == i) end

sent = {}
now = 1
local previous_calls = calls
bus.emit(events.UI_DIRTY, {team = 2})
local first = tasks.ui_snapshot_flush
for i = 1, 20 do
    now = 1 + i * 0.01
    bus.emit(events.UI_DIRTY, {team = 2})
end
assert(calls == previous_calls + 1 and tasks.ui_snapshot_flush == first and first.at == 1.25,
    "continuous dirty events keep the first deadline")
flush(1.25)
assert(#sent == 2 and sent[1].id ~= 2 and sent[2].id ~= 2 and next(tasks) == nil)

-- A dirty event raised during projection must survive the in-flight batch.
sent = {}
now = 2
bus.emit(events.UI_DIRTY, {team = 2})
during_build = function() bus.emit(events.UI_DIRTY, {team = 3}) end
flush(2.25)
assert(#sent == 2 and tasks.ui_snapshot_flush.at == 2.5)
flush(2.5)
assert(#sent == 3 and sent[3].id == 2 and next(tasks) == nil)

-- Full invalidation subsumes the smaller batch without duplicate players.
sent = {}
now = 3
bus.emit(events.UI_DIRTY, {team = 2})
bus.emit(events.UI_DIRTY, {})
flush(3.25)
assert(#sent == 3 and next(tasks) == nil)

-- An explicit HUD resync remains immediate and does not start an idle loop.
sent = {}
bus.emit(events.UI_SNAPSHOT_REQUESTED, {player_id = 1})
assert(#sent == 1 and sent[1].id == 1 and next(tasks) == nil)

now = 4
bus.emit(events.UI_DIRTY, {team = 2})
local stale = tasks.ui_snapshot_flush.callback
bus.reset() -- Production game initialization resets the event bus first.
register_projection()
service.init()
local fresh = tasks.ui_snapshot_flush
sent = {}
stale()
assert(#sent == 0 and tasks.ui_snapshot_flush == fresh, "old-generation callback is inert")
flush(4.25)
assert(#sent == 3 and sent[1].snapshot.sequence == 1 and next(tasks) == nil)
print("UI_SNAPSHOT_SCHEDULING_PASS: initial/owner-team/burst/fixed deadline/reentrant dirty/explicit resync/generation/no idle polling")
