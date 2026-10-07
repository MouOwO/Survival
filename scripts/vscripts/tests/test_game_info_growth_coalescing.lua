package.path="scripts/vscripts/?.lua;"..package.path
local bus,events=require("core/event_bus"),require("core/events")
local now=0;GameRules={GetGameTime=function()return now end}
local scheduler=require("core/scheduler")
local sent,builds,listeners=0,0,{}
CustomNetTables={SetTableValue=function()sent=sent+1 end}
CustomGameEventManager={RegisterListener=function(_,name,fn)listeners[name]=fn end}
PlayerResource={IsValidPlayerID=function()return true end}
bus.handle_request(events.HERO_COMBAT_STATS_GET_REQUEST,function()builds=builds+1;return {ok=true,snapshot={attack_min=20,attack_max=20}}end)
bus.handle_request(events.TECHNOLOGY_STATS_GET_REQUEST,function()return {ok=true,snapshot={final={}}}end)
bus.handle_request(events.PERMANENT_REWARD_EFFECTS_GET_REQUEST,function()return {ok=true,totals={}}end)
local service=require("ui/game_info_service");service.init()
local function burst()
 for i=1,500 do
  bus.emit(events.HERO_COMBAT_STATS_CHANGED,{player_id=0})
  bus.emit(events.PERMANENT_REWARD_EFFECTS_CHANGED,{player_id=0,changed_section="tower",reason="attack"})
 end
end
burst()
assert(sent==0 and builds==0 and scheduler.task_count()==0,"closed panel has zero builds/tasks")
listeners.ui_game_info_request(nil,{PlayerID=0,open=1})
assert(sent==1 and builds==1,"opening immediately builds latest state")
burst()
assert(sent==1 and builds==1 and scheduler.task_count()==1)
now=.11;scheduler.think();assert(sent==2 and builds==2)
bus.emit(events.HERO_COMBAT_STATS_CHANGED,{player_id=1})
assert(scheduler.task_count()==0,"only open owner subscribes")
burst()
listeners.ui_game_info_request(nil,{PlayerID=0,open=0})
now=.3;scheduler.think();assert(sent==2 and scheduler.task_count()==0,"close cancels pending flush")
burst();assert(scheduler.task_count()==0)
listeners.ui_game_info_request(nil,{PlayerID=0,open=1});assert(sent==3)
burst()
bus.emit(events.PLAYER_DISCONNECTED,{player_id=0})
now=.5;scheduler.think();assert(sent==3 and scheduler.task_count()==0)
listeners.ui_game_info_request(nil,{PlayerID=0,open=1});assert(sent==4)
burst();service.init();now=.7;scheduler.think();assert(sent==4)
burst();assert(scheduler.task_count()==0)
print("GAME_INFO_GROWTH_PASS: closed 1000 events -> zero builds/tasks; open -> one coalesced build/send; close, owner, reconnect, reset")
