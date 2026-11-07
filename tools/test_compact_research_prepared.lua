-- Production Lua -> real compact codec -> stdout vectors; never writes files.
-- Usage from repository root: lua tools/test_compact_research_prepared.lua [1|2|4] [source-root]
-- Source-root defaults to the actual working project; CLI override is for an
-- explicit isolated source checkout. Test access fixture applies only here.
local SOURCE=(arg and arg[2])or'.'
package.path=SOURCE..'/scripts/vscripts/?.lua;'..package.path
package.loaded['config/test_access']={enabled=false}
local bus,events=require('core/event_bus'),require('core/events')
local names=require('research/research_event_names')
local L=require('config/generated/ui_static_catalog_lookup')
assert(L.production,'committed production catalog required; no experimental fallback')
local wire=require('ui/compact_wire');local schema=assert(wire.compile_lookup(L,1))
local count=tonumber(arg and arg[1])or 4
assert(count>=1 and count<=4)
local players,units,buildings,levels,techlevels,rebirth={},{},{},{},{},{}
local tasks,frames,cpu,world_time,alive={}, {},0,100,true
local checks,failures=0,{}
local function ok(value,why)checks=checks+1;if not value then failures[#failures+1]=why;error(why,0)end end
for id=0,3 do
 players[id]={id=id};levels[id]={};techlevels[id]={};rebirth[id]=10
 for _,row in ipairs(L.production.research)do levels[id][row.group]=0;techlevels[id][row.definition.tech_id]=0 end
end
local mode={IsNull=function()return not alive end,SetContextThink=function(_,key,fn)tasks[key]=fn end}
GameRules={GetGameModeEntity=function()return mode end,GetGameTime=function()return world_time end}
GetSystemTimeMS=function()return cpu end
PlayerResource={GetPlayer=function(_,id)return players[id]end,GetTeam=function()return 2 end,IsValidPlayerID=function(_,id)return players[id]~=nil end}
EntIndexToHScript=function(id)return units[id]end
local list_calls,forbidden=0,0
bus.handle_request(events.BUILDING_LIST_REQUEST,function(p)
 list_calls=list_calls+1;ok(p.handles_only==true,'one indexed bootstrap must request minimal handles')
 local result={};for n=1,4000 do result[n]={building_id='arrow_tower',entindex=10000+n}end
 return{buildings=result}
end)
bus.handle_request(names.STATE_GET_REQUESTED,function(p)return{ok=true,legacy_levels=levels[p.player_id],levels=techlevels[p.player_id]}end)
bus.handle_request(events.HERO_PROGRESSION_GET_REQUEST,function(p)return{snapshot={rebirth_level=rebirth[p.player_id]}}end)
for _,name in ipairs({events.TECHNOLOGY_STATE_GET_REQUEST,events.RESOURCE_GET_REQUEST,events.PERMANENT_REWARD_EFFECTS_GET_REQUEST})do
 bus.handle_request(name,function()forbidden=forbidden+1;error('slim first-paint must not read queues/wallets/discounts')end)
end
local Transport=require('ui/compact_ui_transport')
local transport=Transport.new({lookup=L,budget=require('config/generated/ui_compact_wire_budget'),player=function(id)return players[id]end,
 authorize=function(id)return alive and players[id]~=nil end,session_token=function(id)return 600+id end,
 cpu_ms=function()return cpu end,after=function(delay,fn,key)ok(delay==0,'transport continuation only');tasks[key]=fn end,
 cancel=function(key)tasks[key]=nil end,
 emit=function(id,event,p)ok(event=='cw'and #p.d+25<=50,'wire<=50B');frames[#frames+1]={id=id,packet=p,at_ms=cpu};return true end})
local handlers={};local register=transport.register_view
transport.register_view=function(id,h)handlers[id]=h;return register(id,h)end
local service=require('ui/research_prepared_bootstrap').new({transport=transport,lookup=L,allowed=function(id)return alive and players[id]~=nil end})
local pump_passes=0
local function pump()
 for n=1,10000 do
  if not next(tasks)then return end
  cpu=cpu+16;pump_passes=pump_passes+1
  local batch={};for key,fn in pairs(tasks)do batch[#batch+1]={key,fn}end
  for _,row in ipairs(batch)do
   local key,fn=row[1],row[2]
   if tasks[key]==fn then
    tasks[key]=nil;local again=fn()
    if again==0 and tasks[key]==nil then tasks[key]=fn end
   end
  end
 end error('dispatch_did_not_idle')
end
local revisions,control_needs_full={},{}
local function send_control(id,view,visible,probe,extra)
 local key=id..':'..view;revisions[key]=(revisions[key]or 0)+1
 local ops=extra or{{record=L.by_key['wire:control'],field=L.field_by_name.visible,value=visible},
  {record=L.by_key['wire:control'],field=L.field_by_name.known,value=probe}}
 local packets=assert(wire.encode(schema,{schema=1,schema_sha256=L.sha256,session=600+id,epoch=1,view=view},revisions[key],ops,{full=revisions[key]==1 or control_needs_full[key]}))
 local result,why
 for _,p in ipairs(packets)do result,why=transport.receive(id,p)end
 control_needs_full[key]=not result
 return result,why
end
for id=0,count-1 do
 assert(transport.receive(id,assert(wire.encode_resync(schema,{schema=1,schema_sha256=L.sha256,session=1,epoch=1,view=1},0,1))));pump()
 for owner=0,3 do if owner~=id then assert(send_control(id,12+owner,false,true))end end
end
pump();frames={}
ok(service.inspect().learning.learning_builds==0 and next(tasks)==nil,'empty slots project/send nothing and have no timer')
local function building(entity,owner,kind)
 local unit={id=entity,IsNull=function()return false end,GetTeamNumber=function()return 2 end}
 function unit:IsAlive()return not self.dead end;function unit:entindex()return self.id end
 units[entity]=unit
 local row={entindex=entity,player_id=owner,team=2,level=1,unit=unit,building_id=kind};buildings[entity]=row
 bus.emit(events.BUILDING_CREATED,row);return row
end
local created_at=cpu
for id=0,count-1 do building(20+id,id,'building_research_lab');building(30+id,id,'building_advanced_research_lab')end
pump();local hint_done=cpu
local function metric(rows)
 local bytes,max=0,0;local per={}
 for _,row in ipairs(rows)do
  local n=#row.packet.d+25;bytes=bytes+n;max=math.max(max,n)
  local p=per[tostring(row.id)]or{frames=0,bytes=0};per[tostring(row.id)]=p;p.frames=p.frames+1;p.bytes=p.bytes+n;p.last_ms=row.at_ms
 end
 return{frames=#rows,calibrated_native_bytes=bytes,max_calibrated_native_bytes=max,per_player=per,native_measurement=false}
end
local hints=metric(frames);local hint_vectors=frames;frames={}
local input_pairs=count*(count-1)
ok(service.inspect().service.metrics.snapshots==input_pairs,'only foreign same-team actual labs prepared')
ok(service.inspect().learning.learning_builds==(count>1 and count or 0),'one shared learning computation per viewer, never per lab')
for id=0,count-1 do for owner=0,count-1 do if owner~=id then assert(send_control(id,12+owner,true,false))end end end
pump();local initial=metric(frames);local ready_ms=cpu-created_at;local initial_vectors=frames;frames={}
ok(forbidden==0 and list_calls==1,'zero wallet/queue/discount/recovery scans')
ok(world_time==100,'all preparation/transport drains while simulation clock stays paused')
local initial_reads=service.inspect().learning.authority_reads
local initial_builds=service.inspect().learning.learning_builds
for n=1,1000 do
 bus.emit(events.RESOURCE_CHANGED,{player_id=0,wood=n,gold=0})
 bus.emit(events.TECHNOLOGY_RESEARCH_STATE_CHANGED,{player_id=0,source_entindex=31})
 bus.emit(events.PERMANENT_REWARD_EFFECTS_CHANGED,{player_id=0,totals={technology_wood_cost_refund_pct=n%10}})
 bus.emit(events.HERO_PROGRESSION_CHANGED,{player_id=0,rebirth_level=10})
 bus.emit(events.HERO_PROGRESSION_CHANGED,{player_id=0,reason='star_blessing_attributes_per_second'})
end
pump();ok(#frames==0 and next(tasks)==nil,'5000 unrelated/stable events emit zero prepared frames/timers')
ok(service.inspect().learning.authority_reads==initial_reads and service.inspect().learning.learning_builds==initial_builds,'5000 stable events cause zero authority reads/rebuilds')
service.reset();pump()
ok(#frames==0 and next(tasks)==nil,'same-world reinitialization retains subscriptions without resending unchanged values')
local after_reset_builds=service.inspect().learning.learning_builds
local update_vectors={};local single_change
local lifecycle_vectors={}
if count>1 then
 levels[0].researcher_hero_attack=1;techlevels[0]['ARS-10']=1
 bus.emit(names.LEVEL_CHANGED,{player_id=0,tech_id='ARS-10',level=1})
 pump();single_change=metric(frames);update_vectors=frames;frames={}
 ok(service.inspect().learning.learning_builds==after_reset_builds+1,'one viewer update rebuilds learning once across every foreign scope')
 for _,row in ipairs(update_vectors)do local h=assert(wire.peek_header(row.packet));ok(row.id==0 and h.view>=13,'only changed viewer facts updated')end
 for n=1,1000 do bus.emit(names.LEVEL_CHANGED,{player_id=0,tech_id='ARS-10',level=1})end
 pump();ok(#frames==0 and next(tasks)==nil,'same tech level repeatedly emits/schedules nothing')
 local before=service.inspect().learning.learning_builds
 rebirth[0]=0;bus.emit(events.HERO_PROGRESSION_CHANGED,{player_id=0,rebirth_level=0});pump()
 ok(service.inspect().learning.learning_builds==before+1,'rebirth changes shared learning exactly once')
 frames={}
 -- Real private preparation does not add an intent or typed-input route.
 local result,why=send_control(0,13,nil,nil,{{record=L.by_key['wire:control'],field=L.field_by_name.action_code,value=9},
  {record=L.by_key['wire:control'],field=L.field_by_name.request_token,value=1}})
 ok(not result and why=='view_intent_not_allowed','prepared cannot execute research/purchase')
 -- A duplicate owner lab is rejected as an ambiguous slot, never aliased.
 local reads=service.inspect().learning.authority_reads
 local duplicate=building(131,1,'building_advanced_research_lab');pump()
 lifecycle_vectors[#lifecycle_vectors+1]={name='duplicate_revoke',frames=frames};frames={}
 ok(service.inspect().learning.authority_reads==reads,'duplicate does not recompute or leak an arbitrary lab')
 for viewer=0,count-1 do if viewer~=1 then assert(send_control(viewer,13,false,true))end end;pump()
 ok(#frames==0,'client revoke feedback leaves empty slot probing with zero full')
 duplicate.unit.dead=true;bus.emit(events.BUILDING_DESTROYED,duplicate);units[131]=nil;pump()
 lifecycle_vectors[#lifecycle_vectors+1]={name='duplicate_removed_hint',frames=frames};frames={}
 for viewer=0,count-1 do if viewer~=1 then ok(not transport.is_open(viewer,13),'restored slot only hinted until explicitOpen');assert(send_control(viewer,13,true,false))end end;pump()
 lifecycle_vectors[#lifecycle_vectors+1]={name='duplicate_removed_restore',frames=frames};frames={}
 ok(service.inspect().learning.authority_reads==reads,'restored identity reuses this viewer learning cache')
 local previous=buildings[31]
 previous.unit.dead=true;bus.emit(events.BUILDING_DESTROYED,previous);pump()
 lifecycle_vectors[#lifecycle_vectors+1]={name='destroy_revoke',frames=frames};frames={}
 for viewer=0,count-1 do if viewer~=1 then assert(send_control(viewer,13,false,true))end end;pump()
 ok(#frames==0,'destroyed empty slot never sends a full snapshot')
 local fresh=building(31,1,'building_advanced_research_lab');pump()
 lifecycle_vectors[#lifecycle_vectors+1]={name='reused_entity_hint',frames=frames};frames={}
 for viewer=0,count-1 do if viewer~=1 then assert(send_control(viewer,13,true,false))end end;pump()
 lifecycle_vectors[#lifecycle_vectors+1]={name='reused_entity_restore',frames=frames};frames={}
 bus.emit(events.BUILDING_DESTROYED,previous);pump()
 ok(#frames==0,'late destroyed old handle cannot revoke the reused entity')
 local unknown=building(131,-1,'building_advanced_research_lab');pump()
 ok(#frames==0 and service.inspect().service.metrics.invalid==1,'neutral/unsupported owner is not mapped to player0')
 -- Close removes its subscription; future changes cannot warm a closed slot.
 assert(send_control(0,13,false,false));pump();frames={}
 levels[0].researcher_hero_attack=2;techlevels[0]['ARS-10']=2
 bus.emit(names.LEVEL_CHANGED,{player_id=0,tech_id='ARS-10',level=2});pump()
 for _,row in ipairs(frames)do local h=assert(wire.peek_header(row.packet));ok(h.view~=13 or row.id~=0,'closed prepared lane stays closed')end
 frames={}
 -- Reconnect with same numeric player invalidates pending old actor work.
 bus.emit(names.LEVEL_CHANGED,{player_id=1,tech_id='ARS-10',level=2})
 bus.emit(events.PLAYER_DISCONNECTED,{player_id=1});transport.disconnect(1);players[1]={id=1};pump()
 for _,row in ipairs(frames)do ok(row.id~=1,'old actor work must not reach a new handle')end
 frames={}
end
ok(service.inspect().service.metrics.errors==0,'no errors swallowed by the real dispatch driver')
ok(service.inspect().service.metrics.max_pass_work<=2,'hard2 pair preparation work bound')
ok(next(tasks)==nil,'idle has no context think')
local report={status='SLIM_PREPARED_REAL_TRANSPORT_PASS',checks=checks,players=count,pairs=input_pairs,hints=hints,initial=initial,
 simulated_creation_to_ready_ms=ready_ms,simulated_hint_ready_ms=hint_done-created_at,simulated_frame_ms=16,
 network_RTT_ms=0,simulation_clock_paused=true,first_paint_only=true,costs_queue_auto_not_prepared=true,
 metrics=service.inspect(),single_change=single_change,forbidden_reads=forbidden,list_calls=list_calls,failures=failures,
 vectors=initial_vectors,update_vectors=update_vectors,hint_vectors=hint_vectors,lifecycle_vectors=lifecycle_vectors}
-- Complete vectors are passed directly to the JS regression via stdout.
-- The report labels all timestamps/bytes as simulation/calibration, not native.
print(require('core/json_encoder').encode(report))

