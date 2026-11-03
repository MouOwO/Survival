-- Real codec + real static schema; scheduler/native emitter are deterministic
-- doubles. Uses measured length calibration, not a new native/FPS measurement.
package.path="scripts/vscripts/?.lua;"..package.path
local wire=require("ui/compact_wire")
local transport=require("ui/compact_ui_transport")
local lookup=dofile("scripts/vscripts/config/generated/ui_static_catalog_lookup.lua")
local budget=dofile("scripts/vscripts/config/generated/ui_compact_wire_budget.lua")
local schema=assert(wire.compile_lookup(lookup,1))
local tasks,packets,handles={}, {}, {[0]={},[1]={}}
local ready={[0]=true,[1]=true}
local cpu=0
local runtime=transport.new({lookup=lookup,budget=budget,
    player=function(id)return handles[id]end,authorize=function(id)return ready[id]==true end,
    session_token=function(id)return 900+id end,cpu_ms=function()return cpu end,
    after=function(delay,fn,key)assert(delay==0);tasks[key]=fn end,cancel=function(key)tasks[key]=nil end,
    emit=function(id,event,payload)
        assert(event=="cw" and #payload.d<=24 and #payload.d+25<=50)
        packets[#packets+1]={id=id,packet=payload};return true
    end})
local fields=lookup.field_by_name
local state=lookup.by_key["daily:state"]
local control=lookup.by_key["wire:control"]
local requests,closed,probes=0,0,0
local function snapshot()
    return {{record=state,field=fields.known,value=true},{record=state,field=fields.day,value=25004}}
end
runtime.register_view(3,{snapshot=snapshot,open=function()return snapshot()end,
    close=function()closed=closed+1 end,probe=function()probes=probes+1 end,
    intent=function(id,action,args)requests=requests+1;assert(id==0 and action=="daily_claim"and args.arg_a==25004 and args.request_token==1);return true end})
local function pump()
    for count=1,1000 do
        local fn=tasks.compact_ui_dispatch;if not fn then return end
        cpu=cpu+16
        tasks.compact_ui_dispatch=nil;fn()
    end
    error("dispatch failed to become idle")
end
local bootstrap={schema=1,schema_sha256=lookup.sha256,session=1,epoch=1,view=1}
assert(runtime.receive(0,assert(wire.encode_resync(schema,bootstrap,0,1))))
pump()
local header=assert(wire.peek_header(packets[1].packet))
assert(header.view==1 and header.session==900)
local hello=assert(wire.new_receiver(schema,{schema=1,schema_sha256=lookup.sha256,session=900,epoch=1,view=1}))
local tx
for _,row in ipairs(packets)do tx=assert(hello.accept(row.packet))end
assert(not tx.pending and #tx.changes==8);assert(hello.commit(tx));packets={}
local client_binding={schema=1,schema_sha256=lookup.sha256,session=900,epoch=1,view=3}
local revision=0
local function command(changes)
    revision=revision+1
    local frames=assert(wire.encode(schema,client_binding,revision,changes,{full=revision==1}))
    for _,packet in ipairs(frames)do assert(runtime.receive(0,packet))end
end
command({{record=control,field=fields.visible,value=true}});pump()
assert(runtime.is_open(0,3))
local out_header=assert(wire.peek_header(packets[1].packet));assert(out_header.epoch==1)
local receiver=assert(wire.new_receiver(schema,{schema=1,schema_sha256=lookup.sha256,session=900,epoch=1,view=3}))
for _,row in ipairs(packets)do tx=assert(receiver.accept(row.packet))end
assert(not tx.pending and #tx.changes==2);assert(receiver.commit(tx));packets={}
command({{record=control,field=fields.action_code,value=1},{record=control,field=fields.arg_a,value=25004},
    {record=control,field=fields.request_token,value=1}})
assert(requests==1,"only the explicit intent reaches the original business handler")
-- Multiple queued changes for one view must never interleave revision fragments.
for index=1,4 do
    cpu=cpu+1
    assert(runtime.publish(0,3,{{record=state,field=fields.count,value=index}},{priority=false}))
end
pump();local expected=1
for _,row in ipairs(packets)do
    tx=assert(receiver.accept(row.packet))
    if not tx.pending then assert(tx.changes[1].value==expected);expected=expected+1;assert(receiver.commit(tx))end
end
assert(expected==5 and next(tasks)==nil);packets={}
local frames_before=runtime.inspect().frames
for _=1,1000 do assert(runtime.publish(0,3,{},{}).unchanged)end
assert(runtime.inspect().frames==frames_before and next(tasks)==nil,"stable state adds no dispatch/timer/send")
-- Close invalidates pending full transactions instead of finishing them hidden.
assert(runtime.publish(0,3,snapshot(),{full=true,priority=false}))
command({{record=control,field=fields.visible,value=false},{record=control,field=fields.known,value=false}})
pump();assert(closed==1 and #packets==0 and not runtime.is_open(0,3))
command({{record=control,field=fields.visible,value=false},{record=control,field=fields.known,value=true}})
assert(probes==1 and #packets==0)
ready[0]=false
assert(not runtime.receive(0,assert(wire.encode_resync(schema,bootstrap,0,1))))
assert(not runtime.is_open(0,3));ready[0]=true
handles[0]={};runtime.disconnect(0)
assert(not runtime.publish(0,3,snapshot(),{full=true}))
runtime.reset();assert(next(tasks)==nil)
-- Missing native CPU clock keeps one global work quota until the real next
-- scheduler dispatch; concurrent calls cannot each replenish eight frames.
local fallback_tasks,fallback_frames={},0
local fallback=transport.new({lookup=lookup,budget=budget,
    player=function(id)return handles[id]end,authorize=function()return true end,
    session_token=function(id)return 1000+id end,
    after=function(_,fn,key)fallback_tasks[key]=fn end,cancel=function(key)fallback_tasks[key]=nil end,
    emit=function()fallback_frames=fallback_frames+1;return true end})
for _=1,100 do assert(fallback.receive(0,assert(wire.encode_resync(schema,bootstrap,0,1))))end
assert(fallback_frames<=8,"clockless synchronous publishers share one quota")
local fn=fallback_tasks.compact_ui_dispatch;assert(fn);fallback_tasks.compact_ui_dispatch=nil;fn()
assert(fallback_frames<=16,"only a scheduler dispatch replenishes the clockless quota")
fallback.reset();assert(next(fallback_tasks)==nil)
print("COMPACT_RUNTIME_SYNTHETIC_PASS: measured49-byte boundary, exact SHA hello, authorized numeric intents, ordered per-view tx,1000 idle updates0sends/timers,close cancellation,probe,disconnect/reset")
