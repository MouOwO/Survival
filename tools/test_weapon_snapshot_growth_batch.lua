-- Real event bus/scheduler/tooltip builder. Engine IO and authority boundaries only are fake.
package.path="scripts/vscripts/?.lua;"..package.path
-- Presentation fixtures have no Steam/engine admission; that policy has its
-- own tests. Keep the real event bus and fake only this authority boundary.
package.loaded["core/test_access_policy"]={enabled=function()return false end}
local bus=require("core/event_bus")
local events=require("core/events")

local scheduler=require("core/scheduler")
local tooltip=require("ui/tooltip_view_model")
local definitions=require("config/generated/weapon_definitions")
local selected
for _,row in ipairs(definitions.rows)do if row.equipment_slot=="main_hand"and row.next_content_id~=""then selected=row.content_id;break end end
assert(selected)
local time,writes,sends,reads,builds=0,{},0,0,0
local data,heroes,outputs={},{},{}
local read_hook,write_hook
GameRules={GetGameTime=function()return time end}
PlayerResource={IsValidPlayerID=function(_,id)return id==0 or id==1 end,GetPlayer=function(_,id)return{id=id}end}
CustomNetTables={SetTableValue=function(_,name,key,value)
 if key=="root"then return end
 assert(name=="survival_weapon_snapshot","removed dead table was published")
 writes[#writes+1]={id=tonumber(key),value=value};outputs[tonumber(key)]=value
 if write_hook then local h=write_hook;write_hook=nil;h()end
end}
CustomGameEventManager={Send_ServerToPlayer=function()sends=sends+1 end}
local original=tooltip.weapon_snapshot
tooltip.weapon_snapshot=function(...)builds=builds+1;return original(...)end
local function reset()writes,sends,reads,builds={},0,0,0 end
local function advance(dt)time=time+dt;scheduler.think()end
local function event(kind,id,reason)bus.emit(kind,{player_id=id,reason=reason})end
local function grow(id,n,kind,reason)
 data[id].growth=data[id].growth+n
 event(kind or events.WEAPON_GROWTH_CHANGED,id,reason or"attack_landed")
end
bus.reset();scheduler.clear()
for id=0,1 do
 data[id]={content=selected,growth=0,hammers=0,instances={[selected]={quantity=1}}};heroes[id]={}
 -- A true large container is built once; hit traffic must not iterate it.
 for n=1,10000 do data[id].instances['synthetic_item_'..n]={quantity=n}end
end
bus.handle_request(events.WEAPON_EQUIPMENT_GET_REQUEST,function(x)
 reads=reads+1
 local result={ok=true,snapshot={player_id=x.player_id,main_hand_content_id=data[x.player_id].content}}
 if read_hook then local h=read_hook;read_hook=nil;h()end
 return result
end)
bus.handle_request(events.WEAPON_GROWTH_GET_REQUEST,function(x)
 reads=reads+1;local d=data[x.player_id]
 return{ok=true,snapshot={growth_attack=d.growth,stage_attack_count=d.growth,stage_attack_target=1000,progress_per_attack=1+d.hammers,forging_hammer_count=d.hammers}}
end)
bus.handle_request(events.EQUIPMENT_INSTANCE_GET_REQUEST,function(x)reads=reads+1;return{ok=true,instances=data[x.player_id].instances}end)
bus.handle_request(events.EQUIPMENT_GROWTH_GET_REQUEST,function()reads=reads+1;return{ok=true,progress={}}end)
local service=require("ui/weapon_synthesis_snapshot_service")
service.init()
for id=0,1 do bus.emit(events.HERO_SUMMONED,{player_id=id,unit=heroes[id]})end
assert(#writes==0 and scheduler.task_count()==2)
advance(0)
assert(#writes==2 and reads==8 and builds==2 and sends==0)
assert(outputs[0].version==2 and outputs[0].tooltip_view_model.items.synthetic_item_10000.quantity==10000)
reset()
for n=1,10000 do
 grow(0,1)
 grow(0,1,events.WEAPON_GROWTH_CHANGED,"damage_dealt")
 grow(0,1,events.EQUIPMENT_GROWTH_CHANGED,"normal_attack")
 grow(0,1,events.EQUIPMENT_GROWTH_CHANGED,"legal_enemy_kill")
end
assert(data[0].growth==40000,"authority must remain synchronous")
advance(1)
assert(#writes==0 and reads==0 and builds==0 and sends==0 and scheduler.task_count()==0)
for n=1,1000 do service.publish_player(0,"stable_request")end
assert(#writes==0 and reads==0 and builds==0 and sends==0)
print("WEAPON_HOT_PASS N=10001 per owner;40000 hits+1000 requests ->0 reads/builds/timers/NetTables/wake; authority unchanged")
-- Structural observers settle once. Updating counts/hammer/weapon remains real.
reset();data[0].hammers=3;data[0].instances.synthetic_item_1.quantity=99
for _,kind in ipairs({events.CONTENT_INVENTORY_CHANGED,events.EQUIPMENT_INSTANCE_CHANGED,events.WEAPON_EQUIPPED_CHANGED,events.WEAPON_SYNTHESIZED})do event(kind,0)end
assert(scheduler.task_count()==1 and reads==0)
advance(0)
assert(#writes==1 and reads==4 and builds==1 and sends==0)
assert(outputs[0].tooltip_view_model.items.synthetic_item_1.quantity==99)
assert(outputs[0].main_hand_context.forging_hammer_count==3)
reset();for n=1,1000 do event(events.CONTENT_INVENTORY_CHANGED,0)end;advance(0)
assert(#writes==0 and reads==4 and builds==1,"same completed container has no duplicate native write")
print("WEAPON_STRUCTURE_PASS four nested metadata notifications ->1 completed-source build/1 table; unchanged burst ->0 writes")
-- Reentrant source changes reject old projection before any native write.
reset();read_hook=function()data[0].hammers=4;event(events.WEAPON_EQUIPPED_CHANGED,0)end
event(events.CONTENT_INVENTORY_CHANGED,0);advance(0)
assert(#writes==1 and reads==5 and builds==1 and outputs[0].main_hand_context.forging_hammer_count==4)
reset();write_hook=function()
 bus.emit(events.HERO_REMOVED,{player_id=0,unit=heroes[0]})
 heroes[0]={};data[0].hammers=1
 bus.emit(events.HERO_SUMMONED,{player_id=0,unit=heroes[0]})
end
data[0].hammers=2;event(events.CONTENT_INVENTORY_CHANGED,0);advance(0)
assert(#writes==2 and outputs[0].main_hand_context.forging_hammer_count==1)
-- Removed/replaced hero, other owner and hot init cannot resurrect old work.
reset();event(events.CONTENT_INVENTORY_CHANGED,0);event(events.CONTENT_INVENTORY_CHANGED,1)
local old=heroes[0];bus.emit(events.HERO_REMOVED,{player_id=0,unit=old});grow(0,1)
advance(0);assert(#writes==0 and reads==4 and builds==1)
heroes[0]={};data[0].hammers=2;bus.emit(events.HERO_SUMMONED,{player_id=0,unit=heroes[0]});advance(0)
assert(outputs[0].main_hand_context.forging_hammer_count==2)
reset();event(events.CONTENT_INVENTORY_CHANGED,0);service.init();advance(0)
assert(#writes==0 and reads==0 and builds==0 and scheduler.task_count()==0)
grow(0,1);assert(reads==0 and scheduler.task_count()==0)
event(events.CONTENT_INVENTORY_CHANGED,0);advance(0)
assert(#writes==1 and reads==4 and builds==1 and sends==0)
print("WEAPON_LIFECYCLE_PASS true source/write reentry,two owners,removed/replacement,init cancellation; synthetic counts not native FPS")
