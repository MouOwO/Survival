-- Actual sender/harvest producer. Optional source root supports isolated candidates.
local root=arg[1]or"."
package.path=root.."/scripts/vscripts/?.lua;scripts/vscripts/?.lua;"..package.path
-- Synthetic players have no Steam identities. This process-only config does
-- not test or alter production admission; sender actor/recipient guards below
-- are still the actual implementation.
package.loaded["config/test_access"]={enabled=false}
local real_print=print
print=function(...)
    local text=tostring((...))
    assert(not text:find("handler error",1,true),text)
    real_print(...)
end
local bus,events=require("core/event_bus"),require("core/events")
local checks=0
local function check(value,message)checks=checks+1;assert(value,message)end
local listeners,sends,registrations,unregistrations,player_reads={}, {},0,0,0
local next_listener=0
local players={}
for id=0,3 do players[id]={id=id,GetPlayerID=function(self)return self.id end}end
local actors={}
for id=0,3 do actors[100+id]=players[id]end
PlayerResource={GetPlayer=function(_,id)player_reads=player_reads+1;return players[id]end}
EntIndexToHScript=function(index)return actors[index]end
CustomGameEventManager={
 RegisterListener=function(_,name,fn)
  check(name=="survival_gold_number_ready","one narrow capability event")
  registrations=registrations+1;next_listener=next_listener+1
  listeners[next_listener]=fn;return next_listener
 end,
 UnregisterListener=function(_,id)unregistrations=unregistrations+1;listeners[id]=nil end,
 Send_ServerToPlayer=function(_,player,event,payload)
  check(event=="gn"or event=="survival_gold_mine_income_number","one representation")
  sends[#sends+1]={player=player.id,event=event,payload=payload}
 end,
}
local sender=require("ui/gold_income_numbers")
sender.init()
local ready=listeners[next_listener]
for i=1,1000 do sender.init()end
check(registrations==1,"stable init is O(1), registers once")
local function send(id,e,a,c)
 sender.send(id,players[id],e or 117,a or 60,c or 0)
 return sends[#sends]
end
check(send(0).event=="survival_gold_mine_income_number","old client remains legacy")
ready(101,{PlayerID=0,v=1})
check(send(0).event=="survival_gold_mine_income_number","other actor cannot opt in another player")
ready(100,{PlayerID=0,v=2})
check(send(0).event=="survival_gold_mine_income_number","unknown version is not negotiated")
ready(100,{PlayerID=0,v=1})
check(send(0).event=="gn","capability selects compact")
check(send(1).event=="survival_gold_mine_income_number","capability is recipient isolated")
for _,a in ipairs({1,100,65536,2147483648,9007199254740991,1e20,1e100})do
 for _,c in ipairs({0,1})do
  local result=send(0,32767,a,c)
  check(result.payload.e==32767 and result.payload.a==a and result.payload.c==c,"numbers unchanged, no clamp/extra precision loss")
 end
end
local before_reads,before_reg,before_sends=player_reads,registrations,#sends
for i=1,9379 do send(0,117,i,i%2)end
check(#sends-before_sends==9379,"no event lost or duplicate")
check(player_reads==before_reads and registrations==before_reg,"no additional native lookups/listeners per emission")
bus.emit(events.PLAYER_DISCONNECTED,{player_id=0})
check(send(0).event=="survival_gold_mine_income_number","disconnect revokes capability")
ready(100,{PlayerID=0,v=1})
local replacement={id=0,GetPlayerID=function(self)return self.id end}
players[0]=replacement;actors[100]=replacement
check(send(0).event=="survival_gold_mine_income_number","same slot new handle requires capability")
ready(100,{PlayerID=0,v=1})
check(send(0).event=="gn","replacement can negotiate")
local old_ready=ready
bus.reset();sender.init();ready=listeners[next_listener]
old_ready(100,{PlayerID=0,v=1})
check(send(0).event=="survival_gold_mine_income_number","old-world callback cannot opt in")
check(unregistrations==1 and registrations==2,"world replacement removes old native listener")
ready(100,{PlayerID=0,v=1})
check(send(0).event=="gn","new world negotiates once")

-- Produce actual new wire data for the actual Panorama consumer test.
real_print("VECTORS_BEGIN")
for id=0,3 do
 ready(100+id,{PlayerID=id,v=1})
 for _,amount in ipairs({1,321,65536,2147483648,9007199254740991,1e20,1e100})do
  for critical=0,1 do
   local r=send(id,1000+id,amount,critical)
   real_print(string.format("VECTOR\t%d\t%s\t%d\t%.17g\t%d",r.player,r.event,r.payload.e,r.payload.a,r.payload.c))
  end
 end
end
real_print("VECTORS_END")

-- Real existing harvest service retains its sum and quarter-second timing.
local now,green=0,0
GameRules={GetGameTime=function()return now end}
package.loaded["core/particle_manager"]={show_green_number=function()green=green+1 end}
local scheduler=require("core/scheduler")
local harvest=require("systems/harvest_feedback_service")
local worker={entindex=function()return 551 end,IsNull=function(self)return self.removed==true end}
local first=#sends
for i=1,1000 do harvest.add(0,worker,1,2)end
check(#sends==first+1 and sends[#sends].payload.a==2,"harvest first hit stays immediate")
check(scheduler.task_count()==1,"harvest retains exactly one existing timer")
now=0.25;scheduler.think()
check(#sends==first+2 and sends[#sends].payload.a==1998,"harvest tail sums all amounts exactly")
now=0.5;scheduler.think()
check(scheduler.task_count()==0,"idle ends; no new timer")
harvest.add(0,worker,1,2);harvest.add(0,worker,1,3)
worker.removed=true;now=0.75;scheduler.think()
check(scheduler.task_count()==0 and sends[#sends].payload.a==2,"removed entity never sends queued tail")

-- Actual mine settlement schedules and sends: no fake invocation of a copied
-- produce_once function. Only native building visuals and clock are isolated.
local tasks={}
package.loaded["core/scheduler"]={after=function(_,fn,key)tasks[key]=fn end,cancel=function(key)tasks[key]=nil end}
package.loaded["systems/building_visual_service"]={apply=function()end}
package.loaded["systems/building_sound_service"]={upgrade_completed=function()end}
package.loaded["systems/building_upgrade_process"]={is_active=function()return false end}
package.loaded["systems/technology_stat_manager"]={get=function()return {final={gold_mine={}}}end}
local gold_mine=require("systems/gold_mine_system")
gold_mine.init()
local resource_total,resource_calls,allow=0,0,true
bus.handle_request(events.RESOURCE_ADD_REQUEST,function(payload)
 resource_calls=resource_calls+1
 if allow then resource_total=resource_total+payload.gold end
 return {ok=allow}
end)
local mine={}
function mine:IsNull()return false end
function mine:IsAlive()return not self.dead end
function mine:entindex()return 777 end
function mine:FindAbilityByName()return nil end
for _,method in ipairs({"SetBaseMaxHealth","SetMaxHealth","SetHealth","SetPhysicalArmorBaseValue"})do mine[method]=function()end end
bus.emit(events.BUILDING_CREATED,{unit=mine,building_id="gold_mine",player_id=0,team=2,level=1,definition={}})
local function produce()
 local count,task=0,nil
 for _,fn in pairs(tasks)do count=count+1;task=fn end
 check(count==1,"one real production timer")
 task()
end
RandomFloat=function()return 100 end
local begin=#sends;produce()
check(resource_calls==1 and #sends==begin+1 and sends[#sends].event=="gn","successful mine income emits exactly one compact event")
check(sends[#sends].payload.e==777 and sends[#sends].payload.a==resource_total and sends[#sends].payload.c==0,"normal mine numbers match actual credited amount")
RandomFloat=function()return -1 end
local previous_total=resource_total;produce()
check(sends[#sends].payload.c==1 and sends[#sends].payload.a==resource_total-previous_total,"critical mine matches actual credited amount and style")
allow=false;begin=#sends;produce()
check(#sends==begin and resource_calls==3,"failed settlement never displays income")
mine.dead=true;produce()
check(#sends==begin and resource_calls==3,"dead mine never settles or displays")
real_print("GOLD_COMPACT_LUA_PASS checks="..checks.." emissions=9379 native_probe=false")
