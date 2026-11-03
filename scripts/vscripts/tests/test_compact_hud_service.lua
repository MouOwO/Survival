-- Actual snapshot service/projector + deterministic native/scheduler seam.
package.path="scripts/vscripts/?.lua;"..package.path
package.loaded["core/test_access_policy"]={enabled=function()return false end}
local bus=require("core/event_bus"),events
events=require("core/events")
local lookup=dofile("scripts/vscripts/config/generated/ui_static_catalog_lookup.lua")
package.loaded["config/generated/ui_static_catalog_lookup"]=lookup
local tasks,handlers,compact_sends,legacy_sends,builds,slot_queries={},{},{},0,0,0
local bound,opened={},{}
package.loaded["core/scheduler"]={after=function(delay,fn,id)assert(delay==0);tasks[id]=fn end,cancel=function(id)tasks[id]=nil end}
package.loaded["ui/compact_ui_transport"]={available=function()return true end,
    register_view=function(id,handler)assert(not handlers[id]);handlers[id]=handler end,
    is_bound=function(id)return bound[id]end,is_open=function(id,view)return opened[id]end,
    publish=function(id,view,ops,settings)compact_sends[#compact_sends+1]={id=id,ops=ops};return true end}
local players={[0]={},[1]={},[2]={},[3]={}}
DOTA_MAX_TEAM_PLAYERS=64
PlayerResource={IsValidPlayerID=function(_,id)slot_queries=slot_queries+1;return players[id]~=nil end,
    GetPlayer=function(_,id)return players[id]end,GetTeam=function()return 2 end}
CustomGameEventManager={Send_ServerToPlayer=function()legacy_sends=legacy_sends+1 end}
local wood=100
bus.handle_request("ui.projection.build_snapshot",function(p)
    builds=builds+1;return {resources={wood=wood,gold=10,population=2,max_population=20},
        city_level=1,worker_count=4,shop_unlocked=0,research_unlocked=0,advanced_researcher_unlocked=0,
        wave={current_wave=0,total_waves=30,status="waiting",game_mode="standard",difficulty_id="N1",difficulty_selected=false}}
end)
local service=require("ui/ui_snapshot_service");service.init()
local function pump()local fn=tasks.ui_snapshot_flush;assert(fn);tasks.ui_snapshot_flush=nil;fn()end
pump();assert(builds==0 and legacy_sends==0 and #compact_sends==0,"pre-Hello setup is not a legacy subscription")
for _=1,1000 do bus.emit(events.UI_DIRTY,{player_id=0});pump()end
assert(builds==0 and legacy_sends==0 and #compact_sends==0,"1000 cold dirty batches neither build nor send a legacy DTO")
for id=0,3 do bound[id]=true;opened[id]=true;assert(handlers[2].snapshot(id))end
bus.emit(events.UI_DIRTY,{});pump();assert(legacy_sends==0 and #compact_sends==0)
local before=builds
for _=1,1000 do bus.emit(events.UI_DIRTY,{player_id=2,team=2})end
wood=101;pump()
assert(builds==before+1 and #compact_sends==1 and #compact_sends[1].ops==1 and compact_sends[1].id==2)
for _=1,1000 do bus.emit(events.UI_DIRTY,{player_id=2});pump()end
assert(#compact_sends==1 and legacy_sends==0 and next(tasks)==nil)
opened[2]=false;before=builds
bus.emit(events.UI_DIRTY,{player_id=2});pump();assert(builds==before and #compact_sends==1)
local before_queries=slot_queries;bus.emit(events.UI_DIRTY,{team=2});pump()
assert(slot_queries-before_queries==4,"team changes visit the four indexed recipients, not64engine slots")
bound[3]=false;before=builds;service.publish_player(3)
assert(legacy_sends==0 and builds==before,"being unnegotiated alone never opts into the legacy seam")
bus.emit(events.UI_SNAPSHOT_REQUESTED,{player_id=3});assert(legacy_sends==1 and builds==before+1,"an actual old-client request activates its playerhandle")
players[3]={};before=builds;service.publish_player(3)
assert(legacy_sends==1 and builds==before,"a reused slot cannot inherit the old handle subscription")
bus.emit(events.UI_SNAPSHOT_REQUESTED,{player_id=3});assert(legacy_sends==2 and builds==before+1)
print("COMPACT_HUD_SERVICE_PASS: 4owners,1000burst1owner/1field,1000stable0send,closed0projection,team indexed4not64,no duplicate legacy")
