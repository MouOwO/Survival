package.path='scripts/vscripts/?.lua;'..package.path
local json=require('core/json_encoder')
local L=require('config/generated/ui_static_catalog_lookup')
local draft=not L.production
if draft then
 local file=assert(io.open('output/production_ui_static_seed_20261103.json','rb'));local text=file:read('*a');file:close()
 L.production=require('core/json_decoder').decode(text)
 local fields={'production_entity','production_selection','production_kind','production_revision','production_capacity','production_queue_count','production_max_count','production_queued_count','production_flags','production_reserved_level','production_job_handle','production_job_state','production_action','production_refunded','production_started_hi','production_started_lo','production_finish_hi','production_finish_lo','production_duration_hi','production_duration_lo','production_next_hi','production_next_lo','production_status'}
 for n,name in ipairs(fields)do local id=163+n;assert(not L.fields[id]);L.field_by_name[name]=id;L.fields[id]={id=id,name=name,kind=name=='production_max_count'and'sint'or'uint',min=name=='production_max_count'and -2147483647 or 0,max=name=='production_max_count'and 2147483647 or 4294967295}end
 local function add(key,kind,business)local id=#L.records+1;L.by_key[key]=id;L.records[id]={id=id,key=key,domain='production',kind=kind,business_id=business}end
 add('production:state','state');add('production:input','input')
 for _,row in ipairs(L.production.training)do add('production:training:'..row.training_id,'training',row.training_id)end
 for _,row in ipairs(L.production.research)do add('production:research:'..row.group,'research',row.group)end
 for n=1,7 do add('production:job:'..n,'job',n)end
 for n=1,8 do add('production:receipt:'..n,'receipt',n)end
end
-- Pure fake-player fixture: do not impersonate a live Steam identity.
package.loaded['config/test_access']={enabled=false}
local bus,events=require('core/event_bus'),require('core/events')
local research_events=require('research/research_event_names')
local production=require('ui/production_ui_service')
local now=100.125;GameRules={GetGameTime=function()return now end}
local players,units,buildings,levels={},{},{},{}
for id=0,3 do players[id]={id=id};levels[id]={lumberjack_speed=id}end
for _,id in ipairs({10,11,20,30})do
 local unit={id=id};function unit:IsNull()return false end;function unit:IsAlive()return true end;function unit:entindex()return self.id end;units[id]=unit
 buildings[id]={entindex=id,player_id=id==11 and 1 or id==30 and 1 or 0,team=2,level=4,
  building_id=id<20 and'main_city'or id==20 and'building_research_lab'or'building_advanced_research_lab'}
end
EntIndexToHScript=function(id)return units[id]end
PlayerResource={GetTeam=function(_,id)return 2 end,GetPlayer=function(_,id)return players[id]end}
package.loaded['systems/player_context_service'].is_owned_by=function(id,unit)return buildings[unit.id].player_id==id end
local tracker=require('systems/worker_training_progress').create(require('config/generated/training_definitions'))
local queue,train_calls,research_calls,cancel_calls= nil,0,0,0
local timers={}
queue=require('systems/worker_training_queue_service').create({capacity=7,now=function()return now end,
 schedule=function(delay,fn,key)timers[key]=fn end,cancel=function(key)timers[key]=nil end,
 validate=function()return true end,can_reserve=function()return{ok=true}end,reserve=function()return{ok=true}end,refund=function()end,
 finish=function(job)tracker:record_independent(job.player_id,job.training_id);return{ok=true}end,
 changed=function(player,team,source)bus.emit(events.WORKER_CHANGED,{player_id=player,source_entindex=source,training_queue_changed=1})end})
local function training(player,source)
 local result=queue:snapshot(source,player);result.options=tracker:get_all(player)
 for _,row in ipairs(result.options)do row.cost_wood,row.cost_gold,row.population=row.wood_cost,row.gold_cost,row.population_cost
  row.queued_count=queue:reserved(player,row.training_id);row.prerequisite_met=1;row.available=1;row.reason='';row.can_afford=1;row.resource_check_on_cast=1
 end;return result
end
local lanes={}
local function clone(value)if type(value)~='table'then return value end local out={}for key,item in pairs(value)do out[key]=clone(item)end return out end
local function lane(player,source)
 local key=player..':'..source;if not lanes[key]then lanes[key]={researching=1,sequence=3,queue_count=2,queue_capacity=7,capacity=7,
  started_at=now,finish_at=now+2.25,duration=2.25,next_start_at=now+3.25,auto_enabled=1,auto_research={researcher_hero_attack=1},reserved_levels={researcher_hero_attack=3},
  active_job={job_id=key..':9007199254740993',technology_group='researcher_hero_attack',target_level=2},
  queued={{job_id=key..':9007199254740994',technology_group='researcher_hero_attack',target_level=3}},blocked_head={},blocked_reason='',research_group='researcher_hero_attack',target_level=2,display_name='英雄攻击强化'}end
 return lanes[key]
end
bus.handle_request(events.BUILDING_QUERY_REQUEST,function(payload)return buildings[payload.entindex]end)
bus.handle_request(events.WORKER_TRAINING_GET_REQUEST,function(payload)return training(payload.player_id,payload.source_entindex)end)
bus.handle_request(events.WORKER_TRAIN_REQUEST,function(payload)
 assert(payload._training_trace and payload._training_trace.action_code==8
  and payload._training_trace.request_token==1 and payload._training_trace.production_selection==1
  and payload._training_trace.owner_serial>0 and payload._training_trace.adapter_generation>0,
  'accepted compact input carries server-created owner/token provenance without exposing it on the wire')
 train_calls=train_calls+1;local row=require('config/generated/training_definitions').by_id[payload.training_id]
 return queue:enqueue({player_id=payload.player_id,source_entindex=payload.source_entindex,team=2,training_id=payload.training_id,name=row.name,level=row.level,duration=row.training_duration_seconds})
end)
bus.handle_request(research_events.STATE_GET_REQUESTED,function(payload)return{legacy_levels=levels[payload.player_id]}end)
bus.handle_request(events.HERO_PROGRESSION_GET_REQUEST,function()return{snapshot={rebirth_level=10}}end)
bus.handle_request(events.PERMANENT_REWARD_EFFECTS_GET_REQUEST,function(payload)return{totals={technology_wood_cost_refund_pct=payload.player_id*10}}end)
bus.handle_request(events.TECHNOLOGY_STATE_GET_REQUEST,function(payload)return{research=lane(payload.player_id,payload.source_entindex)}end)
bus.handle_request(events.TECHNOLOGY_PURCHASE_NEXT_REQUEST,function(payload)research_calls=research_calls+1;return{ok=true,queued=true}end)
local cancelled
bus.handle_request(events.TECHNOLOGY_RESEARCH_CANCEL_REQUEST,function(payload)cancel_calls=cancel_calls+1;cancelled=payload.job_id;return{ok=true,refunded=true}end)
bus.handle_request(events.SHOP_AUTO_RESEARCH_TOGGLE_REQUEST,function(payload)
 local state=lane(payload.player_id,payload.source_entindex);local group=payload.technology_group
 state.auto_research[group]=not state.auto_research[group]and 1 or nil
 state.auto_enabled=next(state.auto_research)and 1 or 0
 -- Matches the actual shop_system.toggle_auto_research ordering: publish the
 -- authoritative lane before its operation returns (no polling/invalidation
 -- inferred from a successful result).
 bus.emit(events.TECHNOLOGY_RESEARCH_STATE_CHANGED,{player_id=payload.player_id,source_entindex=payload.source_entindex})
 return{ok=true,enabled=state.auto_research[group]~=nil}
end)
CustomGameEventManager={RegisterListener=function()end,Send_ServerToPlayer=function()error('compact must not emit legacy event')end}
local handlers,sent={},{}
local open=true
local transport={register_view=function(id,handler)handlers[id]=handler end,is_open=function()return open end,is_bound=function()return true end,
 publish=function(id,view,ops,opts)sent[#sent+1]={id=id,ops=ops,full=opts.full};return{queued=true}end}
local bridge
production.init({source_player_id=function(p)return p.PlayerID end,valid_player_id=function(id)return players[id]~=nil end,
 send=function()error('legacy receipt')end,selected=function()return nil end,push=function()error('legacy selected push')end,
 compact_refresh=function(id,payload)return bridge and bridge.changed(id,payload)or false end})
local function source(id,entity)return production.decorate(id,units[entity],{success=1,entindex=entity},true)end
local sources=0
local alive=true
bridge=require('ui/compact_production_views').new({transport=transport,lookup=L,generation=bus.get_generation(),
 current=function()return alive end,allowed=function(id)return players[id]~=nil end,player=function(id)return players[id]end,
 snapshot=function(id,entity)sources=sources+1;return source(id,entity)end,stamp=production.stamp,execute=production.execute})
local function input(id,e,s)return handlers[7].input(id,1,{production_entity=e,production_selection=s})end
assert(input(0,10,1));local initial=sent[#sent].ops;local expected=source(0,10)
local before=sources;local visited=bridge.inspect(0).metrics.record_visits
for n=1,1000 do bridge.changed(0,{player_id=0})end
assert(sources==before and bridge.inspect(0).metrics.record_visits==visited,'stable repeated events must not rebuild/snapshot/scan records')
local state=assert(require('ui/compact_production_projection').new(L)).initialize()
assert(state.update(expected,10,1));local before_visits=state.inspect().record_visits
for n=1,1000 do local clone={training=expected.training,_production_stamp=expected._production_stamp};assert(#assert(state.update(clone,10,1))==0)end
assert(state.inspect().record_visits==before_visits,'same trusted dependency stamp on a new DTO must remain O(1)')
local F,R=L.field_by_name,L.by_key
local train_record=R['production:training:train_lumberjack_01']
assert(handlers[7].intent(0,'production_train',{arg_a=10,arg_b=train_record,arg_c=1,request_token=1,session_token=41}))
assert(train_calls==1);local trained=sent[#sent].ops;local trained_expected=source(0,10)
assert(handlers[7].intent(0,'production_train',{arg_a=10,arg_b=train_record,arg_c=1,request_token=1,session_token=41}).duplicate)
assert(train_calls==1,'duplicate nonce must not enqueue twice')
assert(not handlers[7].intent(0,'production_train',{arg_a=10,arg_b=train_record+1,arg_c=1,request_token=1,session_token=41}))
assert(input(0,30,2));local research_ops=sent[#sent].ops;local research_expected=clone(source(0,30))
assert(input(1,30,1));local viewer1=source(1,30);assert(research_expected.research.abilities_by_name.ability_research_ars_10.cost_wood~=viewer1.research.abilities_by_name.ability_research_ars_10.cost_wood,'shared lab costs must remain private')
local handle
for _,op in ipairs(research_ops)do if op.record==R['production:job:1']and op.field==F.production_job_handle then handle=op.value end end
assert(handle)
assert(handlers[7].intent(0,'production_cancel',{arg_a=30,arg_b=handle,arg_c=2,request_token=2,session_token=41}))
assert(cancelled=='0:30:9007199254740993','cancel must preserve the exact original string ID')
assert(input(0,20,3));assert(input(0,30,4));local n=cancel_calls
assert(handlers[7].intent(0,'production_cancel',{arg_a=30,arg_b=handle,arg_c=2,request_token=3,session_token=41}));assert(cancel_calls==n,'ABA prior selection gets terminal rejection without executing')
assert(handlers[7].intent(0,'production_cancel',{arg_a=30,arg_b=4294967295,arg_c=4,request_token=4,session_token=41}));assert(cancel_calls==n,'expired job gets a terminal rejection, never a retargeted cancel')
local previous_stamp=production.stamp(0,30)
assert(handlers[7].intent(0,'production_auto',{arg_a=30,arg_b=R['production:research:researcher_hero_attack'],arg_c=4,request_token=5,session_token=41}))
assert(production.stamp(0,30)~=previous_stamp,'real auto state publication invalidates the private presentation stamp')
assert(source(0,30).research.abilities_by_name.ability_research_ars_10.auto_research_enabled==0,'auto-off cannot retain the previous private cache')
open=false;handlers[7].close(0);open=true;assert(input(0,10,5))
assert(handlers[7].intent(0,'production_train',{arg_a=10,arg_b=train_record,arg_c=5,request_token=1,session_token=41})==nil,'nonce reuse across close/reopen rejected')
assert(train_calls==1)
-- An authoritative execution can synchronously reset world/actor scope. Its
-- old result must not publish into the new owner even when entity IDs match.
local count=#sent;local old_execute=production.execute
local isolated=require('ui/compact_production_views').new({transport={register_view=function(_,h)handlers[8]=h end,is_open=function()return true end,is_bound=function()return true end,publish=transport.publish},lookup=L,
 allowed=function()return true end,player=function()return players[2]end,current=function()return alive end,snapshot=source,stamp=production.stamp,
 execute=function()players[2]={id=2};return{success=1,source_entindex=10}end})
assert(handlers[8].input(2,1,{production_entity=10,production_selection=1}));count=#sent
assert(not handlers[8].intent(2,'production_train',{arg_a=10,arg_b=train_record,arg_c=1,request_token=1,session_token=42}));assert(#sent==count,'old actor result must not publish')
local output={draft_registry=draft,seed=L.production,fields=L.fields,records=L.records,initial_ops=initial,initial_expected=expected,trained_ops=trained,trained_expected=trained_expected,research_ops=research_ops,research_expected=research_expected}
local wire=require('ui/compact_wire');local schema=assert(wire.compile_lookup(L,1))
local function metric(ops,full)
 local packets,m=assert(wire.encode(schema,{schema=1,schema_sha256=L.sha256,session=1,epoch=1,view=7},1,ops,{full=full,value_budget=24}))
 local total,max=0,0;for _,packet in ipairs(packets)do local bytes=25+#packet.d;total=total+bytes;max=math.max(max,bytes)end
 return{changes=m.changes,frames=#packets,calibrated_native_bytes=total,max_calibrated_native_bytes=max,actual_native_measurement=false}
end
output.metrics={initial=metric(initial,true),train=metric(trained,false),research=metric(research_ops,true)}
local function encode(v)
 if type(v)=='number'then return string.format('%.17g',v)end
 if type(v)~='table'then return json.encode(v)end
 local keys={};for key in pairs(v)do keys[#keys+1]=key end
 local array=#keys>0 and #keys==#v;for _,key in ipairs(keys)do if type(key)~='number'then array=false end end
 local out={};if array then for n=1,#v do out[n]=encode(v[n])end;return'['..table.concat(out,',')..']'end
 table.sort(keys);for _,key in ipairs(keys)do out[#out+1]=json.encode(key)..':'..encode(v[key])end;return'{'..table.concat(out,',')..'}'
end
if arg and arg[1]=='emit'then print(encode(output))else print('PASS production actual queue/private decoration/1000 stable/nonce/ABA/exact cancel/owner guard')end

