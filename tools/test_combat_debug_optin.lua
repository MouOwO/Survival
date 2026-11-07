package.path='scripts/vscripts/?.lua;'..package.path
local service_path=arg[1]or'scripts/vscripts/ui/combat_stats_ui_service.lua'
package.loaded['core/test_access_policy']={enabled=function()return false end}
local gets=0
package.loaded['systems/technology_stat_manager']={get=function()gets=gets+1;return{final={hero={}}}end}
package.loaded['systems/player_profile_service']={get_profile=function()return nil end}
local bus,E=require('core/event_bus'),require('core/events');bus.reset()
local scheduler=require('core/scheduler');scheduler.clear()
local time,debugwrites,statswrites,checks=0,0,0,0
GameRules={GetGameTime=function()return time end}
local unit={IsNull=function()return false end,IsAlive=function()return true end,entindex=function()return 10 end,
 GetPlayerOwnerID=function()return 0 end,GetUnitName=function()return'npc_dota_hero_doom_bringer'end}
EntIndexToHScript=function(id)return id==10 and unit end
CustomNetTables={GetTableValue=function()return nil end,SetTableValue=function(_,name,key,value)
 if name=='survival_combat_debug'then debugwrites=debugwrites+1 else statswrites=statswrites+1 end
end}
package.loaded['ui/ui_request_router']={route_owner_hero_stats=function()return false end}
local techrequests=0;bus.handle_request(E.TECHNOLOGY_STATE_GET_REQUEST,function()techrequests=techrequests+1;return{levels={}}end)
local service=assert(loadfile(service_path))();service.init()
local function check(v,message)assert(v,message);checks=checks+1 end
local function damage()bus.emit(E.COMBAT_DAMAGE_RESOLVED,{player_id=0,attacker_entindex=10,final_damage=12})end
local function growth()bus.emit(E.TECHNOLOGY_STATS_CHANGED,{player_id=0,changed_section='lumberjack'})end
local function advance(dt)time=time+dt;scheduler.think()end
bus.emit(E.HERO_SUMMONED,{player_id=0,unit=unit})
for _=1,1000 do damage();growth();bus.emit(E.TECHNOLOGY_CHANGED,{player_id=0,levels={}})end
check(debugwrites==0 and gets==0 and techrequests==0 and scheduler.task_count()==0,'ordinary hidden debug does no DTO, request, timer or network work')
IsInToolsMode=function()return false end
check(service.set_debug_enabled(0,true)==false,'ordinary clients cannot enable development publishing')
IsInToolsMode=function()return true end
bus.emit(E.HERO_COMBAT_STATS_CHANGED,{player_id=0,snapshot={entindex=10,attack_min=1,attack_max=1,refresh_version=1,reason='hero_summoned'}})
check(statswrites==1,'authority overlay remains active while debug disabled')
check(service.set_debug_enabled(0,true),'explicit Tools diagnostic enabled')
check(debugwrites==1 and gets==1 and techrequests==1,'opt-in initializes requested owner once')
for _=1,1000 do damage()end
check(scheduler.task_count()==1,'enabled debug damage coalesces to one deadline')
advance(.151);check(debugwrites==2 and scheduler.task_count()==0,'enabled debug retains live counts')
damage();growth();check(scheduler.task_count()==2,'both real debug timers active')
local prior=debugwrites
check(service.set_debug_enabled(0,false),'explicit disable')
advance(.2);check(debugwrites==prior and scheduler.task_count()==0,'disable cancels all pending debug work')
for _=1,1000 do damage();growth()end
check(debugwrites==prior and scheduler.task_count()==0,'disabled subscriptions produce no new timer')
service.set_debug_enabled(0,true);damage();growth();prior=debugwrites;service.init();advance(.2)
check(debugwrites==prior and scheduler.task_count()==0,'init clears old diagnostic epoch')
bus.emit(E.HERO_COMBAT_STATS_CHANGED,{player_id=0,snapshot={entindex=10,attack_min=2,attack_max=2,refresh_version=2,reason='equipment_changed'}})
check(statswrites==2,'authority still immediate after init')
service.set_debug_enabled(0,true);damage();prior=debugwrites
bus.emit(E.PLAYER_DISCONNECTED,{player_id=0});advance(.2)
check(debugwrites==prior and scheduler.task_count()==0,'disconnect revokes diagnostic owner')
print(require('core/json_encoder').encode({status='DEBUG_OPTIN_DEFAULT_ZERO_WORK_PASS',checks=checks,default_damage_and_tech_events=3000,native_validation=false}))
