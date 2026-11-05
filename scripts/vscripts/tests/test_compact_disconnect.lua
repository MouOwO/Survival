package.path='scripts/vscripts/?.lua;'..package.path
-- Exercise the actual default native listener and event bus, not just api.new.
package.loaded['core/test_access_policy']={enforce=function()return true end}
package.loaded['systems/startup_loading_service']={is_player_ready=function()return true end}
local bus=require('core/event_bus');local events=require('core/events');bus.reset()
local tasks,listeners,packets={},{},{}
local cpu=0
local mode={IsNull=function()return false end,SetContextThink=function(_,key,fn,delay)assert(delay==0);tasks[key]=fn end}
GameRules={GetGameModeEntity=function()return mode end}
GetSystemTimeMS=function()return cpu end
local function pump()
 for _=1,100 do
  local key,fn=next(tasks);if not fn then return end
  cpu=cpu+16;local again=fn()
  if again==nil and tasks[key]==fn then tasks[key]=nil end
 end
 error('native driver did not become idle')
end
local actor={GetPlayerID=function()return 0 end}
PlayerResource={IsValidPlayerID=function(_,id)return id==0 end,GetPlayer=function(_,id)if id==0 then return actor end end}
EntIndexToHScript=function(index)if index==7 then return actor end end
CustomGameEventManager={RegisterListener=function(_,name,fn)assert(name=='cw');listeners[#listeners+1]=fn;return #listeners end,
 UnregisterListener=function()end,Send_ServerToPlayer=function(_,player,event,packet)
  assert(player==actor and event=='cw');packets[#packets+1]=packet;return true
end}
local T=assert(loadfile('scripts/vscripts/ui/compact_ui_transport.lua'))()
local L=require('config/generated/ui_static_catalog_lookup');local W=require('ui/compact_wire')
local schema=assert(W.compile_lookup(L,1));local F=L.field_by_name;local C=L.by_key['wire:control']
local builds=0;local function snapshot()
 builds=builds+1;local out={};for n=1,40 do out[n]={record=n,field=F.count,value=n}end;return out
end
assert(T.register_view(3,{snapshot=snapshot}))
local bootstrap=assert(W.encode_resync(schema,{schema=1,schema_sha256=L.sha256,session=1,epoch=1,view=1},0,1))
local function native(packet)listeners[#listeners](7,{PlayerID=0,d=packet.d})end
native(bootstrap)
local function open(session,revision)
 local context={schema=1,schema_sha256=L.sha256,session=session,epoch=1,view=3}
 for _,p in ipairs(assert(W.encode(schema,context,revision,{{record=C,field=F.visible,value=true}},{full=true})))do native(p)end
end
open(1,1);assert(T.is_bound(0)and T.queue_depth(0,3)>0 and builds==1)
bus.emit(events.PLAYER_DISCONNECTED,{player_id=0})
assert(not T.is_bound(0)and not T.is_open(0,3)and T.queue_depth(0,3)==0,'disconnect retires state even while native actor/readiness stay valid')
local sent=#packets
pump()
assert(#packets==sent,'cancelled old jobs cannot drain after disconnect')
native(bootstrap);pump()
assert(T.is_bound(0));for n=sent+1,#packets do assert(W.peek_header(packets[n]).session==2)end
open(1,2);assert(builds==1,'old aliases cannot reopen a reconnected player')
open(2,1);assert(builds==2)
local old_listener=listeners[#listeners];bus.reset()
local old_builds=builds;open(2,2)
assert(builds==old_builds,'old-world native input is rejected before lazy instance rebuild')
assert(T.available());assert(not T.is_bound(0))
old_listener(7,{PlayerID=0,d=bootstrap.d});assert(not T.is_bound(0),'old-world native callback is inert')
assert(T.disconnect(0));assert(not T.is_bound(0))
-- First native availability may be the module that initially imports the bus.
-- Its driver must bind the generation returned by require, never a prior nil.
package.loaded['core/event_bus']=nil
local cold=assert(loadfile('scripts/vscripts/ui/compact_ui_transport.lua'))()
assert(cold.register_view(3,{snapshot=snapshot}))
local before=#packets;listeners[#listeners](7,{PlayerID=0,d=bootstrap.d})
pump();assert(cold.is_bound(0) and #packets>before,'cold bus import must bind a live dispatch world')
-- Entity replacement also expires the native listener without a bus reset.
local old_mode_listener=listeners[#listeners]
mode={IsNull=function()return false end,SetContextThink=function(_,key,fn,delay)assert(delay==0);tasks[key]=fn end}
before=#packets;old_mode_listener(7,{PlayerID=0,d=bootstrap.d})
assert(#packets==before,'old-mode native input is rejected before lazy instance rebuild')
assert(cold.available() and not cold.is_bound(0))
old_mode_listener(7,{PlayerID=0,d=bootstrap.d});assert(not cold.is_bound(0))
print('COMPACT_DISCONNECT_PASS real native listener/event bus,queued cancellation,same-handle reconnect,new alias,old-world callback retired')
