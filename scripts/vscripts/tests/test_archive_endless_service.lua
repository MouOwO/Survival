package.path = "scripts/vscripts/?.lua;" .. package.path
local bus = require("core/event_bus")
local events = require("core/events")
local config = require("systems/archive_endless_config")
local projection = require("combat/endless_stat_projection")
local clock, next_id, calls, fail_at = 0, 0, 0, nil
local jobs, spawned, scores = {}, {}, {}
GameRules = { GetGameTime = function() return clock end }
package.loaded["core/scheduler"] = {
    after = function(_, cb, key) jobs[key] = cb end,
    every = function(_, cb, key) jobs[key] = cb end,
    cancel = function(key) jobs[key] = nil end,
}
UTIL_Remove = function(unit) unit.removed = true end
package.loaded["systems/monster_hero_visual_service"] = { clear = function() end }
package.loaded["systems/archive_service"] = {
    record_endless_wave = function(id, number, difficulty)
        scores[id] = (scores[id] or 0) + config.score(number)
        return { ok = true }
    end,
}
package.loaded["systems/wave_system"] = { spawn_challenge_monster = function(row, def, id)
    calls = calls + 1
    if fail_at == calls then return nil end
    assert(def.endless and row.attack_speed == 1 and def.model_path == config.rules.model_path)
    next_id = next_id + 1
    local unit = { id = next_id, player_id = id, row = row }
    function unit:IsNull() return self.removed == true end
    function unit:entindex() return self.id end
    spawned[#spawned+1] = unit
    return unit
end }
local service = require("systems/archive_endless_service")
service.init()
local function kill(unit) bus.emit(events.ENGINE_ENTITY_KILLED, { victim = unit, victim_entindex = unit.id }) end
local function advance(id)
    local key = "archive_endless_next:" .. id
    local cb = jobs[key]; jobs[key] = nil
    if cb then cb() end
end
assert(config.score(1)==1 and config.score(10)==1 and config.score(11)==8 and config.score(91)==64)
assert(config.wave(1,1000).health == config.wave(20,1000).health)
assert(service.start(0,1))
assert(#spawned==5 and service.snapshot(0).seconds==60)
assert(not service.start(0,1), "duplicate start")
assert(service.start(1,20))
for i=1,4 do kill(spawned[i]) end
assert((scores[0] or 0)==0, "partial clear no score")
kill(spawned[5]); kill(spawned[5])
assert(scores[0]==1 and service.snapshot(0).remaining==0, "one award per wave")
advance(0)
assert(service.snapshot(0).wave==2 and service.snapshot(0).remaining==5, "immediate next wave")
clock=60
kill(spawned[6])
assert(service.snapshot(1).status=="finished" and (scores[1] or 0)==0, "deadline kills do not score")
jobs.archive_endless_timer()
assert(service.snapshot(0).status=="finished" and scores[0]==1, "timeout retains prior score")
local count=#spawned
kill(spawned[count]); advance(0)
assert(#spawned==count, "late death does not restart")
assert(service.start(2,10))
service.cancel(2,"disconnect")
assert(service.snapshot(2).status=="finished" and (scores[2] or 0)==0)
fail_at=calls+3
assert(not service.start(3,10), "partial spawn failure")
assert(service.snapshot(3).remaining==0 and spawned[#spawned].removed)
fail_at=nil
assert(service.start(3,10), "failed first wave can retry")
service.cancel(3)
assert(service.start(4,20))
for number=1,1000 do
    local first=#spawned-4
    for i=first,first+4 do kill(spawned[i]) end
    advance(4)
end
assert(service.snapshot(4).status=="finished" and service.snapshot(4).cleared==1000)
local expected=0;for number=1,1000 do expected=expected+config.score(number) end
assert(scores[4]==expected and expected==347500)
local last=config.wave(20,1000)
local unit={}
local engine=projection.prepare(unit,last)
assert(engine.health<=100000000 and engine.attack<=100000000)
assert(math.abs(projection.incoming(unit,last.health)-engine.health)<0.001)
assert(math.abs(projection.outgoing(unit,engine.attack,true)/last.attack-1)<1e-12)
assert(projection.outgoing(unit,42,false)==42)
assert(projection.incoming({},42)==42)
local wave90 = config.wave(1,90)
assert(not service.can_rebuild_wall(99))
assert(not service.on_wall_destroyed(99), "mainline wall defeat not suppressed")
assert(service.start(5,1))
local wave_start = #spawned - 4
for i=wave_start,wave_start+4 do kill(spawned[i]) end
assert(scores[5] == 1)
assert(service.on_wall_destroyed(5))
assert(service.snapshot(5).status == "finished" and service.snapshot(5).score == 1)
local before = #spawned
advance(5)
assert(#spawned == before and scores[5] == 1, "wall destruction cancels queued next wave")
assert(service.can_rebuild_wall(5) and not service.start(5,1), "rebuild allowed but endless stays consumed")
assert(service.start(6,1))
local first_enemy = spawned[#spawned-4]
assert(service.on_wall_destroyed(6))
assert(first_enemy.removed and service.snapshot(6).remaining == 0)
kill(first_enemy)
assert((scores[6] or 0) == 0, "late deaths after wall destruction cannot award")
assert(service.on_wall_destroyed(6), "subsequent rebuilt walls also avoid defeat")
fail_at = calls + 1
assert(not service.start(7,1))
assert(not service.can_rebuild_wall(7), "failed start does not unlock rebuilding")
fail_at = nil
local displayed = {}
local native = projection.prepare(displayed, wave90)
assert(tonumber(projection.for_ui(displayed, native.health, "health")) == wave90.health)
assert(tonumber(projection.for_ui(displayed, native.health / 2, "health")) == wave90.health / 2)
assert(tonumber(projection.for_ui(displayed, native.attack, "attack")) == wave90.attack)
assert(type(projection.for_ui({}, 100, "health")) == "number", "ordinary units unchanged")
assert(type(projection.for_ui(unit, engine.health, "health")) == "string", "large numbers safe for network")
assert(math.abs(tonumber(projection.for_ui(unit, engine.health, "health")) / last.health - 1) < 1e-12)
print("ARCHIVE_ENDLESS_PASS: five units, 1000 waves, scoring, deadlines, duplicates, isolation, failure cleanup, large stats")
