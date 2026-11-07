-- Real projection/transport and event-driven display service; native IO only is doubled.
-- Optional candidate directory is for pre-promotion review. Default tests real sources.
package.path='scripts/vscripts/?.lua;'..package.path
local candidate=arg[1]
if candidate then for _,name in ipairs({'compact_selected_projection','compact_selected_views','compact_ui_transport','combat_stats_ui_service'})do
 package.preload['ui/'..name]=function()return assert(loadfile(candidate..'/'..name..'.lua'))()end
end end
package.loaded['core/test_access_policy']={enabled=function()return false end}
package.loaded['systems/technology_stat_manager']={get=function()return{final={hero={}}}end}
package.loaded['systems/player_profile_service']={get_profile=function()return nil end}
local W=require('ui/compact_wire');local L=require('config/generated/ui_static_catalog_lookup')
local B=require('config/generated/ui_compact_wire_budget');local schema=assert(W.compile_lookup(L,1))
local bus,E=require('core/event_bus'),require('core/events');bus.reset()
local scheduler=require('core/scheduler');scheduler.clear()
local now,tasks,handles,packets,units,source,versions=0,{},{},{},{},{},{}
local clockframes,maxframes,checks={},0,0
local function check(ok,why)assert(ok,why);checks=checks+1 end
GameRules={GetGameTime=function()return now/1000 end}
for id=0,3 do handles[id]={};units[100+id]={IsNull=function()return false end,IsAlive=function()return true end,
 GetPlayerOwnerID=function()return id end,GetUnitName=function()return'npc_dota_hero_doom_bringer'end,entindex=function()return 100+id end}end
EntIndexToHScript=function(entity)return units[entity]end
PlayerResource={GetPlayer=function(_,id)return handles[id]end}
local net=0
CustomNetTables={GetTableValue=function()return nil end,SetTableValue=function(_,name)if name=='survival_combat_stats'then net=net+1 end end}
local runtime=require('ui/compact_ui_transport').new({lookup=L,budget=B,player=function(id)return handles[id]end,
 authorize=function(id)return handles[id]~=nil end,session_token=function(id)return 900+id end,cpu_ms=function()return now end,
 after=function(_,fn,key)tasks[key]=fn end,cancel=function(key)tasks[key]=nil end,
 emit=function(id,event,payload)
  check(event=='cw'and#payload.d<=24 and#payload.d+25<=50,'bounded calibrated envelope')
  clockframes[now]=(clockframes[now]or 0)+1;maxframes=math.max(maxframes,clockframes[now])
  packets[#packets+1]={id=id,packet=payload,ms=now};return true
 end})
local world=true
local selected=require('ui/compact_selected_views').new({lookup=L,transport=runtime,current=function()return world end,
 allowed=function(id)return handles[id]~=nil end,selected=function()end,
 snapshot=function(id,entity)
  if source[id]and entity==100+id then local s={};for k,v in pairs(source[id])do s[k]=v end;s.success=1;return s end
  return{success=1,entindex=entity,attack_min=42,attack_max=42,strength=0,agility=0,intellect=0,refresh_version=1}
 end})
package.loaded['ui/ui_request_router']={route_owner_hero_stats=function(id,s)return selected.owner_hero_changed(id,s)end}
local service=require('ui/combat_stats_ui_service');service.init()
local function step()
 now=now+16;scheduler.think()
 local fn=tasks.compact_ui_dispatch;tasks.compact_ui_dispatch=nil;if fn then fn()end
end
local function pump()
 for _=1,2000 do if not tasks.compact_ui_dispatch then return end;step()end;error('bounded drain stalled')
end
local function emit(id,reason)
 versions[id]=(versions[id]or 0)+1
 local v=versions[id]
 local s={player_id=id,entindex=100+id,hero_id='hero_doom_bringer',reason=reason or'damage_dealt',refresh_version=v,
  attack_min=2000000+20*v,attack_max=2000008+20*v,strength=900000+5*v,agility=900010+5*v,intellect=900020+5*v,
  weapon_growth_attack=20*v,attack_speed=100,armor=0}
 source[id]=require('ui/combat_stat_projection').for_ui(s)
 bus.emit(E.HERO_COMBAT_STATS_CHANGED,{player_id=id,snapshot=s})
end
local revisions={}
local function control(id,values,input)
 local ops={};for key,value in pairs(values)do ops[#ops+1]={record=L.by_key[input and'selected:input'or'wire:control'],field=L.field_by_name[key],value=value}end
 revisions[id]=(revisions[id]or 0)+1
 for _,p in ipairs(assert(W.encode(schema,{schema=1,schema_sha256=L.sha256,session=900+id,epoch=1,view=5},revisions[id],ops,{full=true})))do assert(runtime.receive(id,p))end
end
local function choose(id,entity,token)control(id,{selected_action=1,selected_entity=entity,selected_token=token},true)end
for id=0,3 do emit(id,'hero_summoned')end
check(net==4,'initial client fallback before negotiation')
for _=1,1000 do emit(0,'equipment_changed')end
check(net==4,'pending handshake publishes one initial image and retains latest authority')
for id=0,3 do
 assert(runtime.receive(id,assert(W.encode_resync(schema,{schema=1,schema_sha256=L.sha256,session=1,epoch=1,view=1},0,1))))
end;pump()
control(0,{visible=1});choose(0,100,1);pump();emit(0,'equipment_changed')
check(net==5,'old client retains immediate NetTable route')
control(0,{visible=0})
for id=0,3 do control(id,{visible=1,types=3});choose(id,100+id,id==0 and 2 or 1)end;pump()
local initial_end=#packets;local before=net;local starts=now
for _=1,62 do
 for id=0,3 do emit(id)end;step()
end
for _=1,10 do step()end;pump()
check(net==before,'modern owner growth never broadcasts full NetTable')
check(maxframes<=8,'four players share actual global eight frames per 16ms')
for id=0,3 do check(runtime.queue_depth(id,5)==0,'tail flush drains')end
local growth_end=#packets
-- Saturated output coalesces to one final source per owner, not a queued tx per hit.
for _=1,1000 do for id=0,3 do emit(id,'equipment_changed')end end
for id=0,3 do check(runtime.queue_depth(id,5)<=1,'bounded one selected display transaction')end
choose(0,100,1) -- delayed token cannot discard the latest pending authoritative source
pump();check(net==before,'busy compact view never adds legacy duplicate')
local final_before_switch=#packets
local stable_versions={};for id=0,3 do stable_versions[tostring(id)]=versions[id]end
choose(0,900,3);pump();local invisible=#packets
for _=1,40 do emit(0,'equipment_changed')end
check(#packets==invisible and net==before,'nonhero selection never receives owner hero data')
choose(0,100,4);pump();local switched_back=#packets
-- Existing explicit lost-transaction resync returns one fresh complete baseline.
local h
for i=#packets,1,-1 do local q=W.peek_header(packets[i].packet);if packets[i].id==0 and q.view==5 then h=q;break end end
assert(runtime.receive(0,assert(W.encode_resync(schema,{schema=1,schema_sha256=L.sha256,session=900,epoch=h.epoch,view=5},0,1))))
pump();local recovered=#packets
control(0,{visible=0});emit(0,'equipment_changed');check(net==before,'closed modern HUD emits no legacy data')
for _=1,1000 do emit(0,'equipment_changed')end
check(net==before,'closed modern capability remains session-bound, not view-bound')
local baseline=#packets
runtime.disconnect(1);emit(1,'equipment_changed');check(net==before and#packets==baseline,'disconnected old session cannot route or republish initial image')
handles[2]={};emit(2,'equipment_changed');check(net==before+1,'new native player handle gets only a fresh initial image')
world=false;emit(3,'equipment_changed');check(net==before+1,'old world cannot restart repeated pre-ready traffic')
selected.dispose();runtime.reset();check(not tasks.compact_ui_dispatch,'reset cancels compact dispatcher')
local raw={};for k,v in pairs(source[0])do raw[k]=v end;raw.success=1
local old=assert(require('ui/compact_selected_projection').new(L)).initialize(raw,100,1)
local modern=assert(require('ui/compact_selected_projection').new(L,{derive_aliases=true})).initialize(raw,100,1)
raw.attack_min=raw.attack_min+20;raw.attack_max=raw.attack_max+20;raw.strength=raw.strength+5;raw.agility=raw.agility+5;raw.intellect=raw.intellect+5
raw.weapon_growth_attack=raw.weapon_growth_attack+20;raw.refresh_version=raw.refresh_version+1;raw=require('ui/combat_stat_projection').for_ui(raw)
local measurements={}
for name,state in pairs({legacy=old,modern=modern})do
 local ops=assert(state.update(raw));local frames=assert(W.encode(schema,{schema=1,schema_sha256=L.sha256,session=900,epoch=1,view=5},2,ops,{}))
 local bytes=0;for _,p in ipairs(frames)do bytes=bytes+#p.d+25 end
 measurements[name]={ops=#ops,frames=#frames,calibrated_bytes=bytes}
end
check(measurements.modern.ops==7 and measurements.legacy.ops==12,'remove only the five exact duplicate fields')
local final_sources,final_versions={},{};for id=0,3 do final_sources[tostring(id)]=source[id];final_versions[tostring(id)]=versions[id]end
print(require('core/json_encoder').encode({checks=checks,packets=packets,initial_end=initial_end,growth_end=growth_end,
 final_before_switch=final_before_switch,invisible=invisible,stable_versions=stable_versions,switched_back=switched_back,recovered=recovered,measurements=measurements,
 max_frames_per_dispatch_window=maxframes,growth_simulated_ms=packets[growth_end].ms-starts,
 source=final_sources,versions=final_versions,network_native_measurement=false,real_game_fps_measurement=false}))
