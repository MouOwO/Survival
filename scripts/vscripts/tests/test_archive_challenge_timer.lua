package.path = "scripts/vscripts/?.lua;" .. package.path
local bus, events = require("core/event_bus"), require("core/events")
local scheduler = require("core/scheduler")
local clock, winners, rewards, removed, cancels, units, serial, pending
local noop = function() end
DOTA_TEAM_GOODGUYS = 2
Vector = function(x,y,z) return {x=x,y=y,z=z} end
package.loaded["config/generated/archive_challenge_definitions"] = {rows = {
    {challenge_id="test",building_id=1,enabled=true,min_difficulty=1,description="test",cooldown_seconds=0}
}, by_id = {test={challenge_id="test",building_id=1,enabled=true,min_difficulty=1,description="test",cooldown_seconds=0}}}
package.loaded["config/generated/archive_challenge_stats"] = {by_id={test_N1={enabled=true}}}
package.loaded["config/generated/archive_challenge_rules"] = {by_id={default={
    building_unlock_difficulty=1, building_spacing=240, building_offset_y=360,
    building_model="test.vmdl",building_model_scale=1,phase_duration_seconds=1800}}}
package.loaded["systems/player_context_service"] = {
    register_unit=function(id,u) u.owner=id end, unregister_unit=noop,
    owner_player_id=function(u) return u.owner end}
package.loaded["systems/archive_service"] = {has_pending=function() return pending end,
    record_challenge=function() rewards=rewards+1 end}
package.loaded["systems/archive_endless_service"] = {init=noop,is_running=function() return false end,
    cancel=function(id) cancels[id]=(cancels[id] or 0)+1 end, start=function() return true end}
package.loaded["systems/archive_endless_config"] = {group=function() return {} end}
package.loaded["systems/monster_hero_visual_service"] = {clear=noop,on_death=noop}
local function unit(name,position)
    serial=serial+1
    local u={id=serial,name=name,position=position,abilities={},alive=true}
    function u:IsNull() return self.removed == true end
    function u:IsAlive() return self.alive end
    function u:entindex() return self.id end
    function u:GetAbsOrigin() return self.position end
    function u:FindAbilityByName(n) return self.abilities[n] end
    function u:AddAbility(n)
        local a={IsNull=function() return false end,SetLevel=noop,SetActivated=noop,StartCooldown=noop,
            GetCaster=function() return u end,GetAbilityName=function() return n end}
        self.abilities[n]=a; return a
    end
    u.SetModel=noop;u.SetOriginalModel=noop;u.SetModelScale=noop;u.AddNewModifier=noop
    function u:SetControllableByPlayer(id) self.owner=id end
    units[#units+1]=u
    return u
end
package.loaded["systems/wave_system"] = {
    get_player_spawn_marker=function() return {IsNull=function() return false end,GetAbsOrigin=function() return Vector(0,0,0) end} end,
    spawn_challenge_monster=function() return unit("boss",Vector(0,0,0)) end}
local function setup()
    clock,winners,rewards,removed,cancels,units,serial,pending=100,0,0,0,{},{},0,false
    bus.reset();scheduler.clear()
    GameRules={GetGameTime=function() return clock end,SetGameWinner=function(_,team) assert(team==2);winners=winners+1 end}
    CreateUnitByName=unit;Entities=nil;CustomNetTables=nil
    UTIL_Remove=function(u) u.removed=true;removed=removed+1;bus.emit(events.ENGINE_ENTITY_KILLED,{victim=u,victim_entindex=u.id}) end
    package.loaded["systems/archive_challenge_service"]=nil
    local service=require("systems/archive_challenge_service");service.init()
    assert(service.begin({difficulty_id="N1",player_ids={0,1}}).keep_running)
    return service
end
local function tick(t) clock=t;scheduler.think() end
local service=setup()
local clock_publications=0
bus.subscribe("archive.challenge_timer_changed",function()clock_publications=clock_publications+1 end)
assert(service.phase_snapshot().remaining_seconds==1800 and service.phase_snapshot().deadline==1900)
tick(100);assert(service.phase_snapshot().remaining_seconds==1800,"paused game time does not advance")
tick(500);service.begin({difficulty_id="N1",player_ids={0,1}})
assert(service.phase_snapshot().deadline==1900,"duplicate begin cannot extend deadline")
local state=service._test.players()[0];local hub=state.hubs[1]
assert(service.summon(hub,"test",hub:FindAbilityByName("ability_archive_test")))
local boss=state.active_boss
pending=true
tick(1899.9);assert(winners==0 and service.phase_snapshot().remaining_seconds==1)
assert(clock_publications==0,"no periodic challenge timer broadcast before expiry")
tick(1900);assert(winners==0 and service.phase_snapshot().expired==1 and service.phase_snapshot().saving==1)
assert(rewards==0 and removed==7 and cancels[0]==1 and cancels[1]==1)
assert(service._test.players()[0].finished and service._test.players()[1].finished)
bus.emit(events.ENGINE_ENTITY_KILLED,{victim=boss,victim_entindex=boss.id})
assert(rewards==0,"timeout cleanup must not grant boss rewards")
tick(2000);assert(winners==0 and service.phase_snapshot().saving==1,"slow/failed save must never force winner")
pending=false;tick(2001);assert(winners==1 and scheduler.task_count()==0 and service.phase_snapshot().saving==0)
assert(not service.begin({difficulty_id="N1",player_ids={0,1}}).keep_running)
service=setup();state=service._test.players()[0];hub=state.hubs[1]
assert(service.summon(hub,"test",hub:FindAbilityByName("ability_archive_test")))
clock=1900
bus.emit(events.ENGINE_ENTITY_KILLED,{victim=state.active_boss,victim_entindex=state.active_boss.id})
assert(winners==1 and rewards==0,"deadline enforced even before scheduler gets its turn")
service=setup()
assert(service.finish(service._test.players()[0].hubs[3]));assert(winners==0)
assert(service.finish(service._test.players()[1].hubs[3]));assert(winners==1)
assert(service.phase_snapshot().ended==1 and service.phase_snapshot().expired==0)
tick(5000);assert(winners==1,"manual finish cancels timeout")
service=setup();bus.emit(events.PLAYER_DISCONNECTED,{player_id=0});assert(winners==0)
tick(1950);assert(winners==1,"scheduler delay and disconnect cannot extend phase")
service=setup();bus.reset();service.init();tick(5000);assert(winners==0,"init removes the previous phase timer")
print("ARCHIVE_PHASE_TIMER_PASS: 30 minutes, shared deadline, duplicate begin, pause clock, pending-save barrier, cleanup without rewards, exact deadline, early finish, disconnect and reset")

-- Real endless service must reject a queued next wave and boundary kills.
package.loaded["systems/player_context_service"].is_defeated=function() return false end
package.loaded["systems/archive_endless_config"]={rules={monsters_per_wave=1,time_limit_seconds=60},
    wave=function() return {health=100,attack=1,war3_armor=0} end,score=function() return 1 end}
package.loaded["systems/archive_service"].record_endless_wave=function() rewards=rewards+1 end
package.loaded["systems/archive_endless_service"]=nil
local endless=require("systems/archive_endless_service")
local phase_expired=false
local function endless_setup()
    bus.reset();scheduler.clear();clock=0;rewards=0;phase_expired=false
    bus.handle_request("archive.challenge_state",function() return {expired=phase_expired and 1 or 0} end)
    endless.init()
end
endless_setup();assert(endless.start(0,1))
local monster=units[#units]
bus.emit(events.ENGINE_ENTITY_KILLED,{victim=monster,victim_entindex=monster.id})
assert(rewards==1)
phase_expired=true;local count=#units;tick(0.1)
assert(#units==count and not endless.is_running(0),"queued wave cannot spawn after phase deadline")
endless_setup();assert(endless.start(0,1));monster=units[#units];phase_expired=true
bus.emit(events.ENGINE_ENTITY_KILLED,{victim=monster,victim_entindex=monster.id})
assert(rewards==0 and not endless.is_running(0),"no endless kill reward after phase deadline")
count=#units;assert(not endless.start(1,1));assert(#units==count)
print("ARCHIVE_ENDLESS_DEADLINE_PASS: no late wave, no boundary reward, no expired start")
