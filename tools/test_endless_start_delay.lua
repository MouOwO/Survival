-- Real countdown/scheduler/events. Only engine entities and archive I/O mocked.
package.path = "scripts/vscripts/?.lua;" .. package.path
local noop = function() end
local bus, events = require("core/event_bus"), require("core/events")
local scheduler = require("core/scheduler")
local guard = require("systems/gameplay_phase_guard")
local rules = require("config/generated/archive_endless_rules").by_id.default
assert(rules.start_delay_seconds == 20, "the authored entry delay is twenty seconds")
local clock, expired, defeated, notices, bodies, hud, rewards = 0, false, {}, {}, {}, {}, 0
GameRules = {GetGameTime=function() return clock end}
PlayerResource = {GetPlayer=function(_,id) return {id=id} end}
CustomGameEventManager = {Send_ServerToPlayer=function(_,player,_,state)
    hud[#hud+1]={id=player.id,state=state}
end}
UTIL_Remove = function(unit) unit.removed=true end
package.loaded["systems/player_context_service"]={is_defeated=function(id) return defeated[id] end}
package.loaded["systems/match_setup_service"]={get_mode=function() return "standard" end}
package.loaded["systems/archive_endless_config"]={rules=rules,allowed_variant=function() return true end,
    wave=function() return {health=100,attack=1,war3_armor=0} end,score=function() return 1 end}
package.loaded["systems/archive_cooperative_reward_service"]={matches_session=function() return true end,
    record_endless_wave=function() rewards=rewards+1;return {ok=true} end,flush_endless_rewards=noop}
package.loaded["systems/archive_endless_visual_config"]={resolve=function() return {model_path="test.vmdl",display_name="test"} end}
package.loaded["visual/endless_monster_visual_service"]={apply=function() return true end,clear=noop,on_death=noop}
package.loaded["systems/monster_hero_visual_service"]={clear=noop,on_death=noop}
package.loaded["systems/wave_system"]={spawn_challenge_monster=function(_,_,owner)
    local unit={id=#bodies+1,owner=owner,born_at=clock}
    unit.IsNull=function(self) return self.removed end;unit.IsAlive=function() return true end
    unit.entindex=function(self) return self.id end
    unit.SetDeathXP,unit.SetMinimumGoldBounty,unit.SetMaximumGoldBounty=noop,noop,noop
    unit.SetBaseMagicalResistanceValue=noop;bodies[#bodies+1]=unit;return unit
end}
bus.handle_request("archive.challenge_state",function() return {expired=expired and 1 or 0} end)
bus.subscribe(events.UI_NOTIFICATION,function(payload)
    notices[#notices+1]={id=payload.player_id,text=payload.message,time=clock}
end)
local endless=require("systems/archive_endless_service")
local function reset()
    endless.init();scheduler.clear();guard.reset()
    clock,expired,defeated,notices,bodies,hud,rewards=0,false,{},{},{},{},0
end
local function advance(target)
    while clock<target do clock=math.min(target,clock+0.25);scheduler.think() end
end
reset()
guard.set_post_clear_frozen(true)
assert(endless.start(0,1))
assert(endless.is_running(0) and not guard.post_clear_frozen(),"preparation keeps ordinary gameplay alive")
assert(endless.snapshot(0).status=="preparing" and endless.snapshot(0).seconds==20)
assert(not endless.can_rebuild_wall(0),"no post-battle wall privilege before combat")
assert(#bodies==0 and #hud==0 and rewards==0)
assert(not endless.start(0,1) and #notices==1,"repeat clicks cannot restart or duplicate notices")
advance(19.75)
assert(#bodies==0 and rewards==0 and #hud==0,"no wave or reward before twenty seconds")
assert(#notices==4)
for i,seconds in ipairs({20,15,10,5}) do
    assert(notices[i].id==0 and notices[i].time==(i-1)*5)
    assert(notices[i].text=="还有"..seconds.."秒开启无尽挑战")
end
advance(20)
assert(#bodies==1 and bodies[1].born_at==20)
assert(notices[5].text=="无尽挑战现在开始！")
assert(endless.snapshot(0).status=="running" and endless.snapshot(0).seconds==60)
assert(endless.can_rebuild_wall(0),"actual combat unlocks the existing wall rule")
reset();assert(endless.start(0,1));advance(3);assert(endless.start(1,1));advance(20)
assert(bodies[1].owner==0 and endless.snapshot(1).status=="preparing")
advance(23);assert(endless.snapshot(1).status=="running","owners have independent deadlines")
reset();assert(endless.start(0,1));advance(5)
defeated[0]=true;bus.emit(events.PLAYER_DEFEATED,{player_id=0});local count=#notices
advance(30);assert(#bodies==0 and #notices==count and not endless.is_running(0))
assert(endless.snapshot(0).seconds==0)
reset();guard.set_post_clear_frozen(true);assert(endless.start(0,1));expired=true;advance(1)
assert(not endless.is_running(0) and guard.post_clear_frozen());advance(30);assert(#bodies==0)
reset();assert(endless.start(0,1));advance(5);endless.init();advance(30)
assert(#bodies==0 and #notices==2,"world reinitialization cancels pending work")
reset();expired=true;assert(not endless.start(0,1));assert(#notices==0 and #bodies==0,"expired admission cannot announce a start")
reset()
local token=bus.subscribe(events.UI_NOTIFICATION,function() endless.cancel(0,"reentrant cancellation") end)
assert(not endless.start(0,1));bus.unsubscribe(token);advance(30)
assert(#bodies==0 and not endless.is_running(0),"notification callbacks cannot resurrect a cancelled preparation")
reset();assert(endless.start(0,1,"tower"));assert(#bodies==1 and #notices==0,"tower entry timing is unchanged")
print("ENDLESS_START_DELAY_PASS: 20/15/10/5 notices, no early spawn/HUD/reward, wave limit starts at spawn, duplicates, owners, defeat, phase expiry, init, tower")
