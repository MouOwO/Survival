package.path = "scripts/vscripts/?.lua;" .. package.path
package.loaded["core/test_access_policy"]={enabled=function() return false end,
    enforce=function() return true end,allowed=function() return true end}
local bus, events = require("core/event_bus"), require("core/events")
local scheduler = require("core/scheduler")
local clock, winners, rewards, removed, cancels, units, serial, pending
local acceptance_active, daily_quotas, endless_starts = false, nil, 0
local noop = function() end
DOTA_TEAM_GOODGUYS = 2
PlayerResource = {GetPlayer=function(_,id) return id end,
    IsValidPlayerID=function(_,id) return id==0 or id==1 end,
    IsFakeClient=function() return false end,GetTeam=function() return 2 end}
Vector = function(x,y,z) return {x=x,y=y,z=z} end
package.loaded["config/generated/archive_challenge_definitions"] = {rows = {
    {challenge_id="test",building_id=1,enabled=true,min_difficulty=1,description="test",cooldown_seconds=0,reward_kind="shadow"}
}, by_id = {test={challenge_id="test",building_id=1,enabled=true,min_difficulty=1,description="test",cooldown_seconds=0,reward_kind="shadow"}}}
package.loaded["config/generated/archive_challenge_stats"] = {by_id={test_N1={enabled=true,
    health=100,attack=1,war3_armor=0,attack_speed=1,move_speed=280,attack_range=160,magic_resistance=0,count=1}}}
local endless_action={action_id="endless",building_id=2,slot_order=1,min_difficulty=1,
    enabled=true,ability_name="ability_archive_endless",display_name="无尽挑战",description="计时测试无尽入口"}
package.loaded["config/generated/archive_challenge_actions"]={rows={endless_action},by_id={endless=endless_action}}
package.loaded["config/generated/archive_challenge_rules"] = {by_id={default={
    building_unlock_difficulty=1, building_spacing=240, building_offset_y=360,
    building_count=4,
    building_model="test.vmdl",building_model_scale=1,phase_duration_seconds=1800}}}
package.loaded["systems/player_context_service"] = {
    register_unit=function(id,u) u.owner=id end, unregister_unit=noop,
    owner_player_id=function(u) return u.owner end}
package.loaded["systems/archive_service"] = {has_pending=function() return pending end,
    record_challenge=function() rewards=rewards+1;return {ok=true} end}
package.loaded["debug/mode_unlock_test"] = {is_enabled=function() return acceptance_active end}
package.loaded["systems/player_profile_service"] = {
    get_daily_limit=function(_,key) return daily_quotas and daily_quotas[key] end}
package.loaded["systems/match_setup_service"]={get_mode=function() return "standard" end}
package.loaded["systems/archive_challenge_reward_eligibility"]={check=function() return true end}
package.loaded["systems/archive_endless_service"] = {init=noop,is_running=function() return false end,
    cancel=function(id) cancels[id]=(cancels[id] or 0)+1 end,
    start=function() endless_starts=endless_starts+1;return true end}
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
            EndCooldown=function() u.rejected_casts=(u.rejected_casts or 0)+1 end,
            GetCaster=function() return u end,GetAbilityName=function() return n end}
        self.abilities[n]=a; return a
    end
    u.SetModel=noop;u.SetOriginalModel=noop;u.SetModelScale=noop;u.AddNewModifier=noop
    function u:SetControllableByPlayer(id) self.owner=id end
    units[#units+1]=u
    return u
end
package.loaded["systems/wave_system"] = {
    get_difficulty=function() return "N1" end,
    get_player_spawn_marker=function() return {IsNull=function() return false end,GetAbsOrigin=function() return Vector(0,0,0) end} end,
    spawn_challenge_monster=function() return unit("boss",Vector(0,0,0)) end}
local function setup()
    require("systems/gameplay_phase_guard").reset()
    clock,winners,rewards,removed,cancels,units,serial,pending=100,0,0,0,{},{},0,false
    acceptance_active,daily_quotas,endless_starts=false,nil,0
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
local function active_body(state,id)
    local group=assert(state.active_groups[id])
    return assert(group.units[next(group.units)])
end
local clock_publications=0
bus.subscribe("archive.challenge_timer_changed",function()clock_publications=clock_publications+1 end)
assert(service.phase_snapshot().remaining_seconds==1800 and service.phase_snapshot().deadline==1900)
tick(100);assert(service.phase_snapshot().remaining_seconds==1800,"paused game time does not advance")
tick(500);service.begin({difficulty_id="N1",player_ids={0,1}})
assert(service.phase_snapshot().deadline==1900,"duplicate begin cannot extend deadline")
local state=service._test.players()[0];local hub=state.hubs[1]
assert(service.summon(hub,"test",hub:FindAbilityByName("ability_archive_test")))
local boss=active_body(state,"test")
pending=true
tick(1899.9);assert(winners==0 and service.phase_snapshot().remaining_seconds==1)
assert(clock_publications==0,"no periodic challenge timer broadcast before expiry")
tick(1900);assert(winners==0 and service.phase_snapshot().expired==1 and service.phase_snapshot().saving==1)
assert(rewards==0 and removed==9 and cancels[0]==1 and cancels[1]==1,
    "timeout removes four hubs per owner and the unrewarded live boss")
assert(service._test.players()[0].finished and service._test.players()[1].finished)
bus.emit(events.ENGINE_ENTITY_KILLED,{victim=boss,victim_entindex=boss.id})
assert(rewards==0,"timeout cleanup must not grant boss rewards")
tick(2000);assert(winners==0 and service.phase_snapshot().saving==1,"slow/failed save must never force winner")
pending=false;tick(2001);assert(winners==1 and scheduler.task_count()==0 and service.phase_snapshot().saving==0)
assert(not service.begin({difficulty_id="N1",player_ids={0,1}}).keep_running)
service=setup();state=service._test.players()[0];hub=state.hubs[1]
assert(service.summon(hub,"test",hub:FindAbilityByName("ability_archive_test")))
clock=1900
boss=active_body(state,"test")
bus.emit(events.ENGINE_ENTITY_KILLED,{victim=boss,victim_entindex=boss.id})
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

-- The actual ability/cast path must agree with the quota UI. Acceptance opens
-- these monsters without resetting or spending the real daily counters.
service=setup()
local full_quotas={
    shadow={key="shadow",limit=3,earned=3,remaining=0,capped=1},
    endless={key="endless",limit=3,earned=3,remaining=0,capped=1},
}
daily_quotas=full_quotas
local encoder=require("core/json_encoder")
local quotas_before=encoder.encode(full_quotas)
state=service._test.players()[0]
local endless_state=service._test.players()[1]
hub=state.hubs[1]
local endless_hub=endless_state.hubs[2]
local boss_ability=hub:FindAbilityByName("ability_archive_test")
local endless_ability=endless_hub:FindAbilityByName("ability_archive_endless")
local boss_runtime=service.ability_runtime(hub,"ability_archive_test")
local endless_runtime=service.ability_runtime(endless_hub,"ability_archive_endless")
assert(boss_runtime.available==0 and boss_runtime.daily_capped==1
    and endless_runtime.available==0 and endless_runtime.daily_capped==1,
    "normal challenge and endless UI must retain the real exhausted quota")
local count_before=#units
service.cast(boss_ability,"test")
service.cast(endless_ability,"endless")
assert(#units==count_before and state.active_groups.test==nil and endless_starts==0
    and not endless_state.used.endless and hub.rejected_casts==1 and endless_hub.rejected_casts==1,
    "normal exhausted quotas must also block the actual ability cast")
acceptance_active=true
boss_runtime=service.ability_runtime(hub,"ability_archive_test")
endless_runtime=service.ability_runtime(endless_hub,"ability_archive_endless")
assert(boss_runtime.available==1 and boss_runtime.daily_capped==nil
    and endless_runtime.available==1 and endless_runtime.daily_capped==nil,
    "acceptance challenge and endless UI must allow testing with exhausted real quotas")
service.cast(boss_ability,"test")
service.cast(endless_ability,"endless")
assert(state.active_groups.test and state.used.test and endless_starts==1 and endless_state.used.endless,
    "acceptance must reach the real boss spawn and endless start through ability cast")
assert(daily_quotas==full_quotas and encoder.encode(full_quotas)==quotas_before,
    "acceptance must not reset, spend or otherwise alter the real daily quotas")
service=setup();daily_quotas=full_quotas
state=service._test.players()[0];hub=state.hubs[1]
assert(service.ability_runtime(hub,"ability_archive_test").available==0
    and not service.summon(hub,"test",hub:FindAbilityByName("ability_archive_test"))
    and encoder.encode(full_quotas)==quotas_before,
    "a new normal challenge phase must restore its unchanged real quota limit")
print("ARCHIVE_ACCEPTANCE_QUOTA_PASS: exhausted real quotas block normal UI/casts, acceptance admits boss/endless, counters unchanged and normal limits restored")

-- Real endless service must reject a queued next wave and boundary kills.
package.loaded["systems/player_context_service"].is_defeated=function() return false end
package.loaded["systems/archive_endless_config"]={rules={monsters_per_wave=1,time_limit_seconds=60},
    allowed_variant=function(tier,mode,variant) return tier==1 and mode=="standard" and variant=="endless" end,
    wave=function() return {health=100,attack=1,war3_armor=0} end,score=function() return 1 end}
package.loaded["systems/archive_service"].record_endless_wave=function() rewards=rewards+1;return {ok=true} end
package.loaded["systems/archive_endless_service"]=nil
local endless=require("systems/archive_endless_service")
local phase_expired=false
local function endless_setup()
    require("systems/gameplay_phase_guard").reset()
    bus.reset();scheduler.clear();clock=0;rewards=0;phase_expired=false
    bus.handle_request("archive.challenge_state",function() return {expired=phase_expired and 1 or 0} end)
    local cooperative=require("systems/archive_cooperative_reward_service")
    cooperative.init();assert(cooperative.begin({0},"N1"))
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
