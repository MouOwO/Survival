-- Real compact and bulk codecs/dispatcher; deterministic scheduler and emitter.
package.path='scripts/vscripts/?.lua;'..package.path
local T=require('ui/compact_ui_transport')
local W=require('ui/compact_wire')
local B=require('ui/compact_grid_bulk_wire')
local lookup=dofile('scripts/vscripts/config/generated/ui_static_catalog_lookup.lua')
local budget=dofile('scripts/vscripts/config/generated/ui_compact_wire_budget.lua')
local schema=assert(W.compile_lookup(lookup,1))
local F,R=lookup.field_by_name,lookup.by_key
local tasks,packets={},{}
local handle,cpu,fail,completed={},0,false,0
local t=T.new({lookup=lookup,budget=budget,player=function()return handle end,authorize=function()return true end,
 session_token=function()return 900 end,cpu_ms=function()return cpu end,
 after=function(_,fn,key)tasks[key]=fn end,cancel=function(key)tasks[key]=nil end,
 emit=function(_,event,packet)
  if fail then fail=false;return false end
  assert(event=='cw'and #packet.d<=24 or event=='gb'and #packet.d<=896)
  packets[#packets+1]={event=event,packet=packet};return true
 end})
local function pump(one)
 for n=1,1000 do local fn=tasks.compact_ui_dispatch;if not fn then return end
  tasks.compact_ui_dispatch=nil;cpu=cpu+16;local before=#packets;fn()
  assert(#packets-before<=8,'all views share a bounded dispatch')
  if one then return end
 end;error('dispatcher did not become idle')
end
local function meta()return {{record=R['grid:static:meta'],field=F.grid_scope,value=1}}end
t.register_view(6,{bulk_static=true,snapshot=meta})
assert(not pcall(t.register_view,7,{bulk_static=true,snapshot=meta}))
assert(not t.publish_bulk_static(0,'abc',1,{epoch=1,base_revision=1}))
assert(t.receive(0,assert(W.encode_resync(schema,{schema=1,schema_sha256=lookup.sha256,session=1,epoch=1,view=1},0,1))))
pump();packets={}
local revision=0
local function control(visible,types)
 revision=revision+1;local ops={{record=R['wire:control'],field=F.visible,value=visible}}
 if types~=nil then ops[#ops+1]={record=R['wire:control'],field=F.types,value=types}end
 local result,why;for _,p in ipairs(assert(W.encode(schema,{schema=1,schema_sha256=lookup.sha256,session=900,epoch=1,view=6},revision,ops,{full=true})))do result,why=t.receive(0,p)end
 return result,why
end
assert(control(true));pump();assert(not t.bulk_static_enabled(0));assert(not t.bulk_binding(0))
assert(not t.publish_bulk_static(0,'abc',1,{epoch=1,base_revision=1}))
assert(control(true,1));pump();packets={}
local binding=assert(t.bulk_binding(0));assert(t.bulk_static_enabled(0))
-- An authoritative delta may overtake the baseline handoff. The bitmap keeps
-- its original metadata revision, and later typed word updates overlay it.
assert(t.publish(0,6,{{record=R['grid:static:meta'],field=F.grid_complete,value=false}}));pump();packets={}
assert(t.bulk_binding(0).revision==2)
assert(not t.publish_bulk_static(0,'abc',1,{epoch=binding.epoch,base_revision=3}))
assert(not t.publish_bulk_static(0,'abc',1,{epoch=binding.epoch+1,base_revision=1}))
local result=assert(t.publish_bulk_static(0,string.rep(string.char(85),2304),1,{epoch=binding.epoch,base_revision=1,on_complete=function()completed=completed+1 end}))
assert(result.frames==4 and result.base_revision==1)
pump(true);assert(#packets<=2 and completed==0,'rare bitmap shares two-background-frame quota')
pump();assert(completed==1)
for _,row in ipairs(packets)do local h=assert(B.Decode(row.packet));assert(row.event=='gb'and h.base_revision==1 and h.epoch==binding.epoch)end
local metrics=t.inspect();assert(metrics.bulk_frames==4 and metrics.max_native_bytes<=49)
assert(metrics.bulk_max_value_bytes<=896 and not metrics.bulk_native_bytes,'uncalibrated bulk native envelope is not reported as measured')
packets={};assert(t.publish_bulk_static(0,string.rep('a',2304),1,{epoch=binding.epoch,base_revision=1,on_complete=function()completed=completed+1 end}))
assert(control(false));pump();assert(#packets==0 and completed==1,'close cancels all pending bulk and completion')
assert(control(true,1));pump();binding=t.bulk_binding(0);packets={}
assert(t.publish_bulk_static(0,string.rep('b',2304),1,{epoch=binding.epoch,base_revision=1,on_complete=function()completed=completed+1 end}))
t.disconnect(0);pump();assert(#packets==0 and completed==1 and not t.bulk_binding(0))
-- Both emitters can fail. The invalid head must be removed immediately, so a
-- subsequent full recovery is deliverable rather than stranded behind it.
assert(t.receive(0,assert(W.encode_resync(schema,{schema=1,schema_sha256=lookup.sha256,session=1,epoch=1,view=1},0,1))))
pump();revision=0;assert(control(true,1));pump();binding=t.bulk_binding(0);packets={}
assert(t.publish_bulk_static(0,'abc',1,{epoch=binding.epoch,base_revision=1}));fail=true;pump()
assert(t.queue_depth(0,6)==0 and #packets==0)
assert(t.publish(0,6,meta(),{full=true,priority=false}));pump();assert(#packets>0)
packets={};assert(t.publish(0,6,meta(),{full=true,priority=false}));fail=true;pump();assert(t.queue_depth(0,6)==0)
assert(t.publish(0,6,meta(),{full=true,priority=false}));pump();assert(#packets>0)
t.reset();assert(next(tasks)==nil)
print('PASS_BULK_TRANSPORT: negotiated_view6_only,base_R1_survives_K_R2,global_quota,close_disconnect_cancel,cw_and_bulk_failure_recovery')
