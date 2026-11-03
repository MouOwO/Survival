package.path='scripts/vscripts/?.lua;'..package.path
local L=require('config/generated/ui_static_catalog_lookup')
local lookup={};for key,value in pairs(L)do lookup[key]=value end
lookup.grid={};for key,value in pairs(L.grid)do lookup.grid[key]=value end;lookup.grid.atlases={}
local W=require('ui/compact_grid_bulk_wire');local wire=require('ui/compact_wire');local schema=assert(wire.compile_lookup(L,1))
local tasks,handlers,published,bulks={},{},{},{}
local opened,bindings,owners,cap,busy={},{},{},true,false
local scheduler={after=function(_,fn,key)tasks[key]=fn end,cancel=function(key)tasks[key]=nil end}
local function owner(id)owners[id]=owners[id]or{};return owners[id]end
local function binding(id)bindings[id]=bindings[id]or{schema=1,schema_sha256=L.sha256,session=id+7,epoch=1,view=6,revision=1};return bindings[id]end
local T={register_view=function(id,handler)handlers[id]=handler end,is_bound=function()return true end,
 is_open=function(id,view)return opened[id..':'..view]end,queue_depth=function()return busy and 1 or 0 end,
 bulk_static_enabled=function()return cap end,bulk_binding=binding,
 publish=function(id,view,ops,options)local b=binding(id);if options.full then b.epoch=b.epoch+1;b.revision=1 else b.revision=b.revision+1 end;published[#published+1]={id=id,view=view,ops=ops,options=options,revision=b.revision};return true end,
 publish_bulk_static=function(id,raw,scope,options)
  local b=binding(id);assert(b.epoch==options.epoch and options.base_revision>=1 and options.base_revision<=b.revision)
  local context={};for k,v in pairs(b)do context[k]=v end;context.base_revision=options.base_revision
  local packets,report=assert(W.Encode(context,scope,raw));local job={id=id,raw=raw,scope=scope,options=options,packets=packets,report=report,owner=owner(id),epoch=b.epoch}
  bulks[#bulks+1]=job;return{queued=true}
 end}
local area=L.grid.atlases[1].area
local fields={};for part in(area..'|'):gmatch('(.-)|')do fields[#fields+1]=part end
local hex=fields[8];local function area_with(nexthex)local copy={}for n=1,7 do copy[n]=fields[n]end;copy[8]=nexthex;return table.concat(copy,'|')end
local areas={[0]=area,[1]=area_with('22222222'..hex:sub(9))}
local channel
channel=require('ui/compact_grid_views').new({lookup=lookup,transport=T,scheduler=scheduler,
 bootstrap=function()end,bootstrap_static=function(id)channel.send(id,'ui_grid_placement_static_area',{area=areas[id],grid_scope_version=1})end,dispatch=function()return true end})
assert(handlers[6].bulk_static)
opened['0:4'],opened['0:6']=true,true;handlers[4].open(0)
local metadata=handlers[6].open(0);local step=assert(tasks['grid_static_delivery:0'])
local F,R=L.field_by_name,L.by_key
local function meta_value(ops,name)for _,op in ipairs(ops)do if op.record==R['grid:static:meta']and op.field==F[name]then return op.value end end end
assert(meta_value(metadata,'types')==1 and meta_value(metadata,'grid_complete')==0)
for _,op in ipairs(metadata)do assert(L.records[op.record].kind~='static_word')end
busy=true;assert(step()==0.05 and #bulks==0,'CW metadata must drain before publishing its bound bitmap')
-- A current mouse/cell delta remains on the small typed path. A word removed
-- from the server's sparse bitmap must become explicit0 for a fresh receiver.
areas[0]=area_with('00000000'..hex:sub(9))
channel.send(0,'ui_grid_placement_static_area',{area=areas[0],grid_scope_version=1})
local zero=published[#published];assert(#zero.ops==1 and zero.ops[1].record==R['grid:static:word:1']and zero.ops[1].value==0 and not zero.ops[1].remove)
busy=false;step();assert(#bulks==1);local first=bulks[1];assert(#first.raw==2304 and #first.packets==4)
assert(first.options.base_revision==1 and binding(0).revision==2,'a K delta before bulk cannot relabel the raw metadata base')
first.options.on_complete();local complete=published[#published]
assert(#complete.ops==1 and complete.ops[1].field==F.grid_complete and complete.ops[1].value==1)
-- A read-only resync must replay a complete current baseline. Metadata alone
-- cannot restore a newly created client after thousands of typed fields were
-- intentionally replaced by one bitmap.
local recovery=handlers[6].snapshot(0);assert(meta_value(recovery,'grid_complete')==0)
binding(0).epoch=binding(0).epoch+1;binding(0).revision=1
step=assert(tasks['grid_static_delivery:0']);step();assert(#bulks==2 and bulks[2].raw~=first.raw)
local before=#published;handlers[6].close(0);bulks[2].options.on_complete();assert(#published==before,'Close cancels the completion of a previously queued private blob')
-- Two players keep independent bytes and owner references.
opened['1:4'],opened['1:6']=true,true;handlers[4].open(1);local other_meta=handlers[6].open(1);assert(meta_value(other_meta,'types')==1)
tasks['grid_static_delivery:1']();local second=bulks[#bulks];assert(second.id==1 and second.raw~=first.raw)
owners[1]={};opened['1:6']=false;before=#published;second.options.on_complete();assert(#published==before)
-- Explicit non-capable clients keep the compatible path. Common verified
-- template atlas/K never enters this bulk branch at all (covered by existing
-- exact292B/48B tests).
cap=false;opened['0:6']=true;local legacy=handlers[6].open(0);assert(meta_value(legacy,'types')==nil)
local meta_packets=assert(wire.encode(schema,{schema=1,schema_sha256=L.sha256,session=7,epoch=1,view=6},1,metadata,{full=true,value_budget=24}))
local meta_bytes=0;for _,packet in ipairs(meta_packets)do meta_bytes=meta_bytes+#packet.d+25 end
local output={schema_sha256=L.sha256,metadata=metadata,zero=zero.ops,complete=complete.ops,packets=first.packets,scope=first.scope,raw_hex=hex,
 binding={schema=1,schema_sha256=L.sha256,session=7,epoch=1,view=6,revision=1},
 metrics={words=576,raw_bytes=#first.raw,bulk_frames=#first.packets,bulk_ascii_bytes=first.report.ascii_bytes,max_bulk_value=first.report.max_value_bytes,
 meta_frames=#meta_packets,meta_calibrated_bytes=meta_bytes,legacy_native_bytes=4813,old_small_frames=577,old_small_calibrated_bytes=27633,new_native_measurement=false}}
if arg and arg[1]=='emit'then print(require('core/json_encoder').encode(output))else print('PASS grid bulk views: unknown4fragments, cap gate, metadata first, sparse remove explicit0, current resync, close/owner/private bytes')end
