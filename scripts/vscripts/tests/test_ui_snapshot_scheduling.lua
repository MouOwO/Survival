-- Real event consumer; deterministic scheduler/engine transport doubles.
-- This verifies scheduling and payload correctness, not real frame times.
package.path = "scripts/vscripts/?.lua;" .. package.path
-- Synthetic player slots have no Steam identity. Keep the real event bus and
-- snapshot subscription consumer; only this standalone fixture's access config
-- selects unrestricted development behavior.
package.loaded["config/test_access"]={enabled=false}
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
assert(calls == 1 and tasks.ui_snapshot_flush.at == 0 and #sent == 0)
flush(0)
assert(#sent == 0 and builds == 0 and next(tasks) == nil, "cold setup cannot opt into legacy snapshots")
for i=1,1000 do
    bus.emit(events.UI_DIRTY,{player_id=1,team=2})
    flush(0)
end
assert(#sent==0 and builds==0 and next(tasks)==nil,"1000 pre-Hello dirty batches neither build nor send a legacy snapshot")
for id=0,2 do bus.emit(events.UI_SNAPSHOT_REQUESTED,{player_id=id}) end
assert(#sent==3 and builds==3 and next(tasks)==nil,"only actual explicit requests subscribe legacy players")
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
assert(calls == previous_calls + 1 and tasks.ui_snapshot_flush == first and first.at == 1,
    "continuous dirty events keep the first deadline")
flush(1.25)
assert(#sent == 2 and sent[1].id ~= 2 and sent[2].id ~= 2 and next(tasks) == nil)

-- A dirty event raised during projection must survive the in-flight batch.
sent = {}
now = 2
bus.emit(events.UI_DIRTY, {team = 2})
during_build = function() bus.emit(events.UI_DIRTY, {team = 3}) end
flush(2.25)
assert(#sent == 2 and tasks.ui_snapshot_flush.at == 2.25)
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
assert(#sent==0 and next(tasks)==nil,"a new world never inherits legacy subscriptions")
for id=0,2 do bus.emit(events.UI_SNAPSHOT_REQUESTED,{player_id=id}) end
assert(#sent == 3 and sent[1].snapshot.sequence == 1 and next(tasks) == nil)
print("UI_SNAPSHOT_SCHEDULING_PASS: initial/owner-team/burst/fixed deadline/reentrant dirty/explicit resync/generation/no idle polling")

-- Personal invalidations take precedence even when a team accompanies them.
sent={};now=5
local previous=builds
for i=1,1000 do bus.emit(events.UI_DIRTY,{player_id=0,team=2}) end
flush(5.25)
assert(#sent==1 and sent[1].id==0 and builds==previous+1)
assert(next(tasks)==nil)
bus.emit(events.UI_DIRTY,{player_id=99,team=2})
assert(next(tasks)==nil,"invalid personal recipient never broadcasts")
sent={};now=6
bus.emit(events.UI_DIRTY,{player_id=0,team=2})
bus.emit(events.UI_DIRTY,{team=2})
flush(6.25)
assert(#sent==2,"overlapping personal/team invalidations do not duplicate recipients")
sent={};now=7
bus.emit(events.UI_DIRTY,{player_id=0})
during_build=function()bus.emit(events.UI_DIRTY,{player_id=1})end
flush(7.25);assert(#sent==1 and sent[1].id==0)
flush(7.5);assert(#sent==2 and sent[2].id==1)
print("PERSONAL_HUD_BATCH_PASS: 1000 changes => one owner build/send; invalid recipients, overlap and reentrant updates")

sent={};now=8
players[1]={id=1,reused=true}
local before_reuse=builds
bus.emit(events.UI_DIRTY,{player_id=1});flush(8.25)
assert(#sent==0 and builds==before_reuse,"a reused player slot cannot inherit its former handle's legacy subscription")
bus.emit(events.UI_SNAPSHOT_REQUESTED,{player_id=1})
assert(#sent==1 and sent[1].id==1 and builds==before_reuse+1,"the new handle activates only through its own explicit request")
print("HUD_LEGACY_SUBSCRIPTION_PASS: cold1000=0build/send, real request activation, world reset and playerhandle reuse isolated")
