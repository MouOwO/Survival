-- Actual router non-hero DTO + armor/portrait/tooltip projectors, no engine IO.
package.path="scripts/vscripts/?.lua;"..package.path
for _,name in ipairs({"systems/building_system","ui/weapon_synthesis_snapshot_service","systems/hero_summon_projection","systems/building_batch_upgrade_service","systems/gold_mine_batch_upgrade_service"})do package.loaded[name]={}end
package.loaded["ui/production_ui_service"]={}
package.loaded["core/scheduler"]={}
local router=require("ui/ui_request_router")
local L=require("config/generated/ui_static_catalog_lookup")
local layout=require("ui/selected_stats_schema")
local factory=assert(require("ui/compact_selected_projection").new(L))
local unit={survival_building_id="arrow_tower",survival_level=1,survival_attack_min=123.5,survival_attack_max=123.5,survival_attack_speed=0.8,
 entindex=function()return 90 end,GetUnitName=function()return"building_arrow_tower"end,GetHealth=function()return 500 end,
 GetMaxHealth=function()return 1000 end,GetMana=function()return 0 end,GetMaxMana=function()return 0 end,
 GetPhysicalArmorValue=function()return -7.25 end,GetBaseAttackTime=function()return 1.7 end,GetAttackSpeed=function()return 1.25 end}
local source=require("ui/combat_stat_projection").for_ui(router._test.unit_combat_snapshot(unit));source.success=1
local state,ops=assert(factory.initialize(source,90,11));local initial=ops
local portrait_fixture
for _,asset in ipairs(require("config/asset_catalog").rows)do if asset.portrait_unit_name and asset.portrait_unit_name~=""and asset.portrait_item_def and asset.portrait_item_def~=""then
 local decorated={};for k,v in pairs(unit)do decorated[k]=v end
 decorated.survival_model_asset_id=asset.asset_id;decorated.GetModelName=function()return asset.primary_model end
 local real=require("ui/combat_stat_projection").for_ui(router._test.unit_combat_snapshot(decorated));real.success=1
 local _,rows=assert(factory.initialize(real,90,22));portrait_fixture={ops=rows,source=real};break
end end
assert(portrait_fixture,"real wearable portrait fixture required")
local critical_ops,auxiliary_ops=state.split_ops()
local wire=require("ui/compact_wire");local schema=assert(wire.compile_lookup(L,1))
local packets=assert(wire.encode(schema,{schema=1,schema_sha256=L.sha256,session=12000,epoch=400,view=5},100000,ops,{full=true}))
for _,packet in ipairs(packets)do assert(#packet.d<=24)end
local sizes={}
for _,case in ipairs({{name="production_first",epoch=1,revision=1},{name="production_last_epoch",epoch=16383,revision=1},{name="codec_max_header",epoch=16383,revision=2097151}})do
 local encoded=assert(wire.encode(schema,{schema=1,schema_sha256=L.sha256,session=16383,epoch=case.epoch,view=5},case.revision,ops,{full=true}))
 local bytes,max=0,0;for _,p in ipairs(encoded)do bytes=bytes+#p.d+25;max=math.max(max,#p.d+25)end
 local core=assert(wire.encode(schema,{schema=1,schema_sha256=L.sha256,session=16383,epoch=case.epoch,view=5},1,critical_ops,{full=true}))
 local aux=assert(wire.encode(schema,{schema=1,schema_sha256=L.sha256,session=16383,epoch=case.epoch,view=5},2,auxiliary_ops,{full=false}))
 local core_bytes,aux_bytes=0,0;for _,p in ipairs(core)do core_bytes=core_bytes+#p.d+25 end;for _,p in ipairs(aux)do aux_bytes=aux_bytes+#p.d+25 end
 sizes[#sizes+1]={name=case.name,packets=#encoded,estimated_native_bytes=bytes,estimated_max_native_bytes=max,
  four_player_queue_seconds_at_160_packets_sec=#encoded*4/160,critical_packets=#core,critical_estimated_native_bytes=core_bytes,
  auxiliary_packets=#aux,auxiliary_estimated_native_bytes=aux_bytes,four_player_critical_queue_seconds_at_160_packets_sec=#core*4/160}
end
for i=1,1000 do local out,metrics=assert(state.update(source));assert(#out==0 and metrics.static_catalogue_scans==0)end
local metadata={};for k,v in pairs(source)do metadata[k]=v end;metadata.refresh_sequence=999;metadata.refresh_version=999
assert(#assert(state.update(metadata))==0,"source version without display changes caused network traffic")
source.attack_min=source.attack_min+0.1
local delta=assert(state.update(source));assert(#delta<=2 and #delta>0)
local bad={};for k,v in pairs(source)do bad[k]=v end;bad.portrait_model_name="__UNREGISTERED_DYNAMIC_MODEL__"
local unknown_resource_ops=assert(state.update(bad));assert(state.inspect().unknown_text_fields[1]=="portrait_model_name")
local unknown_marker=false
for _,op in ipairs(unknown_resource_ops)do
 if op.record==L.by_key["selected:metric:portrait_model_name"]and op.field==L.field_by_name.known then unknown_marker=op.value==0 end
 assert(not(op.record==L.by_key["selected:state"]and op.field==L.field_by_name.known and op.value==0),"unknown resource discarded verified combat values")
end
assert(unknown_marker);assert(state.update(source))
local transitions={};local typed=assert(factory.initialize(source,90,11))
for _,case in ipairs({{value=5},{value=0.25},{value=0},{remove=true},{value=2147483648},{value=-0.0}})do
 local current={};for k,v in pairs(source)do current[k]=v end;current.mana=case.remove and nil or case.value
 local changed=assert(typed.update(current));transitions[#transitions+1]={ops=changed,expected=case.remove and"unknown"or string.format("%.17g",case.value)}
end
local views,published,selected={}, {}, {};local snapshots=0;local world=true
local service=require("ui/compact_selected_views").new({lookup=L,current=function()return world end,
 transport={register_view=function(id,h)views[id]=h end,is_open=function()return true end,publish=function(id,view,out,opt)published[#published+1]={id=id,ops=out,full=opt.full};return true end},
 allowed=function(id)return id>=0 and id<=3 end,selected=function(id,e)selected[id]=e end,
 snapshot=function(id,e)snapshots=snapshots+1;local s={};for k,v in pairs(source)do s[k]=v end;s.entindex=e;return s end})
for id=0,3 do assert(views[5].input(id,1,{selected_entity=90+id,selected_token=1}));assert(selected[id]==90+id)end
assert(views[5].input(0,1,{selected_entity=91,selected_token=2}));assert(views[5].input(0,1,{selected_entity=90,selected_token=3}))
local n=snapshots;assert(not views[5].input(0,1,{selected_entity=90,selected_token=2})and snapshots==n)
assert(views[5].input(0,2,{selected_entity=0,selected_token=4})and selected[0]==nil)
world=false;assert(not views[5].input(0,1,{selected_entity=90,selected_token=5})and snapshots==n)
if arg[1]=="emit"then
 local exact={};for _,path in ipairs(layout.numeric_paths)do local value=source
  for key in path:gmatch("[^.]+")do value=type(value)=="table"and value[tonumber(key)or key]or nil end
  if value~=nil then exact[path]=string.format("%.17g",tonumber(value))end
 end
 print(require("core/json_encoder").encode({initial_ops=initial,critical_ops=critical_ops,auxiliary_ops=auxiliary_ops,source=source,portrait_fixture=portrait_fixture,unknown_resource_ops=unknown_resource_ops,exact_numeric=exact,delta_ops=delta,transitions=transitions,numeric_paths=layout.numeric_paths,text_paths=layout.text_paths,schema_sha256=L.sha256}))
else print(require("core/json_encoder").encode({status="COMPACT_SELECTED_PASS_SYNTHETIC_NOT_NATIVE",sizes=sizes,fixed_numeric_paths=#layout.numeric_paths,
 fixed_text_paths=#layout.text_paths,full_ops=#initial,stable_updates=1000,stable_ops=0,codec_worst_sample_packets=#packets,
 primitive_delta_ops=#delta,unknown_text_atomic=true,four_players=true,aba_token_guard=true,clear=true,stale_world=true}))end
