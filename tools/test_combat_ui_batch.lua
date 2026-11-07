package.path='scripts/vscripts/?.lua;'..package.path
package.loaded['core/test_access_policy']={enabled=function()return false end}
package.loaded['systems/technology_stat_manager']={get=function()return{final={hero={}}}end}
package.loaded['systems/player_profile_service']={get_profile=function()return nil end}
local bus,events=require('core/event_bus'),require('core/events');bus.reset()
local scheduler=require('core/scheduler');scheduler.clear()
local time,checks=0,0
GameRules={GetGameTime=function()return time end}
local units,writes,latest={},{},{}
local function unit(id,owner)
 return{IsNull=function(self)return self.removed==true end,IsAlive=function()return true end,
 GetPlayerOwnerID=function()return owner end,GetUnitName=function()return'npc_dota_hero_doom_bringer'end,entindex=function()return id end}
end
units[10],units[11]=unit(10,0),unit(11,1)
EntIndexToHScript=function(id)return units[id]end
CustomNetTables={GetTableValue=function()return nil end,SetTableValue=function(_,name,key,value)
 if name=='survival_combat_stats'then writes[key]=(writes[key]or 0)+1;latest[key]=value end
end}
local errors={};local original_print=print
print=function(s)if tostring(s):find('handler error',1,true)or tostring(s):find('task failed',1,true)then errors[#errors+1]=s end end
package.preload['ui/combat_stats_ui_service']=function()return assert(loadfile(arg[1]or'scripts/vscripts/ui/combat_stats_ui_service.lua'))()end
-- This fixture isolates legacy display coalescing; compact routing has its own real wire test.
package.loaded['ui/ui_request_router']={route_owner_hero_stats=function()return false end}
local service=require('ui/combat_stats_ui_service');service.init()
local function check(ok,why)assert(ok,why);checks=checks+1 end
local function snap(id,version,reason)
 return{player_id=id,entindex=10+id,hero_id='hero_doom_bringer',refresh_version=version,
 reason=reason or'damage_dealt',attack_min=100+version,attack_max=100+version,
 strength=version,agility=version,intellect=version,attack_speed=2,armor=0}
end
local function emit(id,v,reason)bus.emit(events.HERO_COMBAT_STATS_CHANGED,{player_id=id,snapshot=snap(id,v,reason)})end
local function advance(dt)time=time+dt;scheduler.think()end
emit(0,1,'hero_summoned');check(writes.player_0==1,'initial snapshot immediate')
for v=2,1001 do emit(0,v)end
check(writes.player_0==1 and scheduler.task_count()==1,'1000 growth changes use one fixed deadline')
advance(.099);check(writes.player_0==1,'no premature publication')
advance(.002);check(writes.player_0==2 and latest.player_0.attack_min==1101,'final exact sample published at deadline')
check(scheduler.task_count()==0,'no polling remains after last sample')
for _=1,1000 do emit(0,1001)end
check(scheduler.task_count()==0 and writes.player_0==2,'same authoritative revision cannot republish')
emit(1,1,'hero_summoned');emit(0,1002);emit(1,2)
check(scheduler.task_count()==2,'two owners have independent bounded work')
emit(0,1003,'equipment_changed')
check(writes.player_0==3 and latest.player_0.refresh_version==1003,'active change immediately replaces pending growth')
advance(.101);check(writes.player_0==3 and writes.player_1==2 and latest.player_1.refresh_version==2,'old active-owner callback cancelled; other owner still completes')
emit(0,1004);bus.emit(events.UNIT_COMBAT_STATS_CHANGED,{entindex=10,unit=units[10]})
check(writes.player_0==4 and latest.player_0.refresh_version==1004,'temporary buff forces immediate projection of newest authority')
advance(.101);check(writes.player_0==4,'buff flush has no duplicate tail')
emit(0,1005);local old=units[10];units[10]=unit(10,0);old.removed=true
advance(.101);check(writes.player_0==4,'entity-index reuse rejects old delayed payload')
emit(0,1,'hero_summoned');check(writes.player_0==5 and latest.player_0.refresh_version==1,'new hero identity publishes immediately')
emit(0,2);bus.emit(events.HERO_REMOVED,{player_id=0,unit=old})
advance(.101);check(writes.player_0==6 and latest.player_0.refresh_version==2,'late removal for old handle cannot cancel new hero')
emit(0,3);bus.emit(events.PLAYER_DISCONNECTED,{player_id=0});advance(.101);emit(0,4)
check(writes.player_0==6 and scheduler.task_count()==0,'disconnect cancels tail and ignores later old-player growth')
bus.emit(events.HERO_READY,{player_id=0});emit(0,5)
check(writes.player_0==7,'ready starts a fresh owner publication')
emit(0,6);service.init();advance(.101)
check(writes.player_0==7,'service reload cancels old work')
emit(0,7,'hero_summoned');local start=writes.player_0
for v=8,2007 do emit(0,v);advance(.001)end
advance(.101)
check(writes.player_0-start<=21 and latest.player_0.refresh_version==2007,'continuous stream has bounded fixed windows and exact trailing sample')
emit(0,2008);bus.reset();advance(.101)
check(latest.player_0.refresh_version==2007,'old world callback cannot publish after bus reset')
check(#errors==0,table.concat(errors,'\n'))
print=original_print
print(require('core/json_encoder').encode({status='REAL_COMBAT_UI_BATCH_LIFECYCLE_PASS',checks=checks,continuous_2000_growth_publications=writes.player_0-start,
 native_validation=false,network_calls=0,tracked_changes=0}))
