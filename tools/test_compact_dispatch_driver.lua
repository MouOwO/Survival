-- Real production driver + transport + codec. The native entity, elapsed clock
-- and emitter are deterministic doubles, not native pause/FPS measurements.
package.path='scripts/vscripts/?.lua;'..package.path
local Driver=require('ui/compact_dispatch_driver')
local Transport=require('ui/compact_ui_transport')
local wire=require('ui/compact_wire')
local lookup=require('config/generated/ui_static_catalog_lookup')
local budget=require('config/generated/ui_compact_wire_budget')
local schema=assert(wire.compile_lookup(lookup,1))
local fields=lookup.field_by_name
local control=lookup.by_key['wire:control']
local bootstrap={schema=1,schema_sha256=lookup.sha256,session=1,epoch=1,view=1}
local function ops(count)
 local rows={}
 for i=1,count do rows[i]={record=lookup.records[i].id,field=fields.count,value=i}end
 return rows
end
local large=ops(222)
local function fixture()
 local f={clock=0,game_time=100,world={},slots={},history={},after_history={},packets={},installs=0,uninstalls=0,handles={},ready={},revisions={},sessions={}}
 f.mode={IsNull=function()return f.destroyed==true end}
 f.current_mode=f.mode;f.current_world=f.world
 function f.mode:SetContextThink(key,callback,delay)
  assert(delay==0,'production UI driver must never arm a positive engine delay')
  if callback then
   if f.install_error then error('expected_install_error')end
   f.installs=f.installs+1;f.history[#f.history+1]=callback;f.slots[key]=callback
  else f.uninstalls=f.uninstalls+1;f.slots[key]=nil end
 end
 f.driver=Driver.new({entity=f.mode,is_current=function()
  return f.current_world==f.world and f.current_mode==f.mode and not f.mode:IsNull()
 end})
 local session=800
 f.runtime=Transport.new({lookup=lookup,budget=budget,is_current=f.driver.is_current,
  player=function(id)
   if f.player_error==id then error('expected_player_error')end
   if f.player_hook then f.player_hook(id)end
   return f.handles[id]
  end,
  authorize=function(id)return f.ready[id]==true end,
  session_token=function(id)session=session+1;f.sessions[id]=session;return session end,
  after=function(delay,callback,key)
   f.after_history[#f.after_history+1]=callback
   return f.driver.after(delay,callback,key)
  end,cancel=f.driver.cancel,cpu_ms=function()
   if f.clock_error then f.clock_error=false;error('expected_clock_error')end
   return f.clock
  end,
  emit=function(id,event,packet)
   assert(event=='cw' and #packet.d<=24 or event=='gb' and #packet.d<=896)
   f.packets[#f.packets+1]={id=id,packet=packet}
   f.clock=f.clock+(f.emit_cost or 0)
   if f.emit_hook then f.emit_hook(id,packet)end
   return true
  end})
 f.runtime.register_view(3,{snapshot=function()return ops(1)end})
 function f.tick(delta)
  f.clock=f.clock+(delta or 16)
  local due={}
  for key,callback in pairs(f.slots)do due[#due+1]={key,callback}end
  for _,row in ipairs(due)do
   if f.slots[row[1]]==row[2]then
    local again=row[2]()
    assert(again==0 or again==nil)
    if again==nil and f.slots[row[1]]==row[2]then f.slots[row[1]]=nil end
   end
  end
 end
 function f.pump()
  for _=1,1000 do if next(f.slots)==nil then return end f.tick()end
  error('dispatch did not become idle')
 end
 function f.command(id,visible)
  f.revisions[id]=(f.revisions[id]or 0)+1
  local binding={schema=1,schema_sha256=lookup.sha256,session=f.sessions[id],epoch=1,view=3}
  local packets=assert(wire.encode(schema,binding,f.revisions[id],{{record=control,field=fields.visible,value=visible}},{full=f.revisions[id]==1}))
  for _,packet in ipairs(packets)do assert(f.runtime.receive(id,packet))end
 end
 function f.open(id)
  f.handles[id]={};f.ready[id]=true;f.revisions[id]=0
  assert(f.runtime.receive(id,assert(wire.encode_resync(schema,bootstrap,0,1))));f.pump()
  f.command(id,true);f.pump();f.clock=f.clock+16
 end
 return f
end

-- Four recipients share one budget. Existing same-lane jobs rotate one packet
-- at a time; this does not claim per-player fairness with unequal view counts.
local f=fixture()
for id=0,3 do f.open(id)end
local initial=#f.packets
local count,expected={},{ }
local installs=f.installs
for id=0,3 do
 local result=assert(f.runtime.publish(id,3,large,{full=true}))
 expected[id]=result.frames;count[id]=0
end
assert(#f.packets-initial==8 and f.installs==installs+1)
f.tick(5);assert(#f.packets-initial==8,'same real-time window cannot replenish quota')
local round_start=#f.packets;f.tick(11)
assert(#f.packets-round_start==8)
for i=1,8 do assert(f.packets[round_start+i].id==(i-1)%4,'same-lane queue must rotate queued jobs')end
while next(f.slots)do local before=#f.packets;f.tick();assert(#f.packets-before<=8)end
for i=initial+1,#f.packets do local row=f.packets[i];count[row.id]=count[row.id]+1 end
for id=0,3 do assert(count[id]==expected[id] and f.runtime.queue_depth(id,3)==0)end
assert(f.game_time==100 and f.installs==installs+1)
local idle_installs,idle_packets=f.installs,#f.packets
for _=1,1000 do assert(f.runtime.publish(0,3,{},{}).unchanged)end
assert(f.installs==idle_installs and #f.packets==idle_packets and next(f.slots)==nil)
print('PAUSED_DRIVER_SYNTHETIC shared_recipients=4 frames_each='..expected[0]..' one_activation_installs=1 idle_updates=1000 idle_new_installs=0 idle_new_sends=0')

-- Real elapsed-time budget stops before a third native call. One call may
-- cross the 2ms deadline; no claim is made that native calls are preemptible.
f=fixture();f.open(0);f.emit_cost=1.1
initial=#f.packets;assert(f.runtime.publish(0,3,large,{full=true}))
assert(#f.packets-initial==2,'2ms budget must stop the third 1.1ms send')
f.emit_cost=0;f.pump()

-- An expired actor invalidates only its view, without stranding other players.
f=fixture();f.open(0);f.open(1)
assert(f.runtime.publish(0,3,large,{full=true}));assert(f.runtime.publish(1,3,large,{full=true}))
f.player_error=0;f.tick();f.player_error=nil
assert(f.runtime.queue_depth(0,3)==0)
f.pump();assert(f.runtime.queue_depth(1,3)==0)
assert(f.runtime.publish(0,3,ops(2),{full=true}));f.pump();assert(f.runtime.queue_depth(0,3)==0)

-- Native installation errors clear queued; the retained transaction can resume
-- after the next explicit publication, without replaying already emitted data.
f=fixture();f.open(0);f.install_error=true;initial=#f.packets
local full=assert(f.runtime.publish(0,3,large,{full=true}))
assert(#f.packets-initial==8 and next(f.slots)==nil)
local stale_after=f.after_history[#f.after_history]
f.install_error=false;f.clock=f.clock+16
local delta=assert(f.runtime.publish(0,3,ops(1),{}))
local after_retry=#f.packets;stale_after();assert(#f.packets==after_retry,'failed scheduling ticket cannot consume replacement continuation')
f.pump()
assert(#f.packets-initial==full.frames+delta.frames and f.runtime.queue_depth(0,3)==0)

-- Unexpected codec/clock exceptions release running/queued. No permanent
-- retry loop is installed; an explicit fresh publication can recover.
for _,kind in ipairs({'codec','clock'})do
 f=fixture();f.open(0)
 assert(f.runtime.publish(0,3,large,{full=true}))
 local original=wire.production_send
 if kind=='codec'then wire.production_send=function()error('expected_codec_error')end else f.clock_error=true end
 f.tick();wire.production_send=original
 assert(next(f.slots)==nil and f.runtime.inspect().rejected>0)
 assert(f.runtime.publish(0,3,ops(2),{full=true}));f.pump()
 assert(f.runtime.queue_depth(0,3)==0 and next(f.slots)==nil)
end

-- An old codec callback that publishes a replacement and then fails must not
-- invalidate that replacement, and the replacement continues automatically.
f=fixture();f.open(0)
assert(f.runtime.publish(0,3,large,{full=true}))
local original_send=wire.production_send
wire.production_send=function()
 wire.production_send=original_send
 assert(f.runtime.publish(0,3,ops(2),{full=true}))
 error('expected_old_job_error_after_replacement')
end
f.tick();wire.production_send=original_send
assert(f.runtime.queue_depth(0,3)==1 and next(f.slots)~=nil)
f.pump();assert(f.runtime.queue_depth(0,3)==0)

-- Close cancels the native continuation immediately. A callback saved by the
-- engine before cancellation must not touch a replacement installation.
f=fixture();f.open(0);assert(f.runtime.publish(0,3,large,{full=true}))
local old=f.history[#f.history]
f.command(0,false);assert(next(f.slots)==nil)
initial=#f.packets;assert(old()==nil and #f.packets==initial)
f.command(0,true);f.pump()
assert(f.runtime.publish(0,3,large,{full=true}));old=f.history[#f.history]
f.runtime.reset();assert(next(f.slots)==nil)
f.open(0);assert(f.runtime.publish(0,3,large,{full=true}));initial=#f.packets
assert(old()==nil and #f.packets==initial);f.pump()

-- All three native lifetime boundaries reject old work, with no queue scans.
for _,kind in ipairs({'world','entity','destroy'})do
 f=fixture();f.open(0);assert(f.runtime.publish(0,3,large,{full=true}));initial=#f.packets
 if kind=='world'then f.current_world={}elseif kind=='entity'then f.current_mode={}else f.destroyed=true end
 f.tick();assert(#f.packets==initial and next(f.slots)==nil and not f.driver.is_current())
 f.driver.dispose();assert(not pcall(f.driver.after,0,function()end,'compact_ui_dispatch'))
end

-- World reset during actor validation cannot unlink old queue nodes from the
-- fresh world's queues or consume new-world frames inside the old dispatch.
f=fixture();f.open(0);f.open(1)
assert(f.runtime.publish(0,3,large,{full=true}));assert(f.runtime.publish(0,3,ops(1),{}))
assert(f.runtime.publish(1,3,large,{full=true}));initial=#f.packets
f.player_hook=function()
 f.player_hook=nil;f.runtime.reset()
 assert(f.runtime.receive(0,assert(wire.encode_resync(schema,bootstrap,0,1))))
end
f.tick();assert(#f.packets==initial and next(f.slots)~=nil)
f.pump();assert(f.runtime.is_bound(0) and not f.runtime.is_bound(1))

-- Bulk completion has the same world barrier even after its final native send.
f=fixture();f.open(0)
f.runtime.register_view(6,{bulk_static=true,snapshot=function()
 return {{record=lookup.by_key['grid:static:meta'],field=fields.grid_scope,value=1}}
end})
local binding={schema=1,schema_sha256=lookup.sha256,session=f.sessions[0],epoch=1,view=6}
for _,packet in ipairs(assert(wire.encode(schema,binding,1,{
 {record=control,field=fields.visible,value=true},{record=control,field=fields.types,value=1}},{full=true})))do
 assert(f.runtime.receive(0,packet))
end
f.pump();local bulk_binding=f.runtime.bulk_binding(0)
assert(f.runtime.publish_bulk_static(0,'a',1,{epoch=bulk_binding.epoch,base_revision=bulk_binding.revision,on_complete=function()
 f.runtime.reset();assert(f.runtime.receive(0,assert(wire.encode_resync(schema,bootstrap,0,1))))
end}))
initial=#f.packets;f.tick()
assert(#f.packets==initial+1 and next(f.slots)~=nil,'old completion drain must not send new-world hello')
f.pump();assert(f.runtime.is_bound(0))

-- A synchronous native send may close/disconnect/reset the world. Old jobs
-- cannot re-enter the new queues or invalidate a fresh replacement transaction.
for _,kind in ipairs({'disconnect','replace','reset'})do
 f=fixture();f.open(0);initial=#f.packets
 f.emit_hook=function()
  f.emit_hook=nil
  if kind=='disconnect'then f.runtime.disconnect(0)
  elseif kind=='reset'then f.runtime.reset()
  else assert(f.runtime.publish(0,3,ops(2),{full=true}))end
 end
 assert(f.runtime.publish(0,3,large,{full=true}));f.pump()
 assert(f.runtime.queue_depth(0,3)==0)
 if kind~='replace'then assert(#f.packets-initial==1)end
 assert(f.runtime.inspect().frames==#f.packets,'successful native calls remain counted during reentrant cancellation')
end

-- Driver callback failures and cancel->after reentry also leave no old native
-- installation that can unregister the replacement via a late nil return.
f=fixture();local calls=0
f.driver.after(0,function()error('expected_driver_callback_error')end,'compact_ui_dispatch')
f.tick();assert(next(f.slots)==nil)
f.driver.after(0,function()
 f.driver.cancel('compact_ui_dispatch')
 f.driver.after(0,function()calls=calls+1 end,'compact_ui_dispatch')
end,'compact_ui_dispatch')
f.tick();assert(calls==0 and next(f.slots)~=nil);f.tick();assert(calls==1 and next(f.slots)==nil)
print('COMPACT_DISPATCH_DRIVER_PASS real_transport_codec,elapsed_budget,actor_failure,install_failure,drain_failure,close,reset,stale_world,mode_replacement,destroy,reentrant_cancel')
