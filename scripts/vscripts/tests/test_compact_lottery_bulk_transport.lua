package.path='scripts/vscripts/?.lua;'..package.path
-- Pure transport simulation. No native/API, transaction, account or filesystem writes.
local T=require('ui/compact_ui_transport')
local W=require('ui/compact_wire')
local B=require('ui/compact_grid_bulk_wire')
local source=require('config/generated/ui_static_catalog_lookup')
local L={};for k,v in pairs(source)do L[k]=v end;L.lottery_receipt={wire_version=1}
local schema=assert(W.compile_lookup(L,1));local F=L.field_by_name;local R=L.by_key
local budget=require('config/generated/ui_compact_wire_budget')
local function setup(lookup)
 local tasks,out,cpu,handle,fail={}, {},0,{},false
 local rt=T.new({lookup=lookup or L,budget=budget,player=function()return handle end,authorize=function()return true end,
  session_token=function()return 900 end,cpu_ms=function()return cpu end,
  after=function(_,fn,key)tasks[key]=fn end,cancel=function(key)tasks[key]=nil end,
  emit=function(_,name,p)if fail then return false end;out[#out+1]={event=name,packet=p};return true end})
 local function flush()for _=1,10000 do local fn=tasks.compact_ui_dispatch;if not fn then return end;tasks.compact_ui_dispatch=nil;cpu=cpu+16;fn()end;error('dispatch did not finish')end
 local revisions={}
 local function control(view,values)
  revisions[view]=(revisions[view]or 0)+1;local ops={}
  for name,value in pairs(values)do ops[#ops+1]={record=R['wire:control'],field=F[name],value=value}end
  local packets=assert(W.encode(schema,{schema=1,schema_sha256=L.sha256,session=900,epoch=1,view=view},revisions[view],ops,{full=true}))
  local result,why;for _,p in ipairs(packets)do result,why=rt.receive(0,p);assert(result,why)end
 end
 local function snapshot()return{{record=R['daily:state'],field=F.count,value=141}}end
 for view=201,204 do rt.register_view(view,{snapshot=snapshot,bulk_lottery=true})end
 rt.register_view(6,{snapshot=snapshot,bulk_static=true})
 assert(rt.receive(0,assert(W.encode_resync(schema,{schema=1,schema_sha256=L.sha256,session=1,epoch=1,view=1},0,1))))
 flush()
 return rt,out,flush,control,function(value)fail=value end,tasks
end
local rt,out,flush,control,setfail,tasks=setup()
local ok=pcall(rt.register_view,200,{snapshot=function()return{}end,bulk_lottery=true});assert(not ok)
control(201,{visible=1,known=0,types=2});flush()
local first=assert(rt.bulk_lottery_binding(0,201));assert(first.base_revision==1 and first.epoch==1)
local raw=string.rep(string.char(0,127,255),800)
local packet_first=#out+1
assert(rt.publish_bulk_lottery(0,201,raw,17,{epoch=first.epoch,base_revision=1,next_revision=2})==true)
local after_bulk=assert(rt.bulk_lottery_binding(0,201));assert(after_bulk.base_revision==2)
assert(not rt.publish_bulk_lottery(0,201,raw,17,{epoch=first.epoch,base_revision=1,next_revision=2}))
assert(not rt.publish_bulk_lottery(0,201,raw,0,{epoch=first.epoch,base_revision=2,next_revision=3}))
assert(not rt.publish_bulk_lottery(0,201,raw,18,{epoch=first.epoch,base_revision=2,next_revision=4}))
assert(rt.bulk_lottery_binding(0,201).base_revision==2)
assert(rt.publish(0,201,{{record=R['daily:state'],field=F.count,value=111}}))
flush();assert(not next(tasks),'stable dispatch must own no timer')
local packets={};local seen_cw=false
for n=packet_first,#out do local item=out[n]
 if item.event=='gb'then assert(not seen_cw,'per-view FIFO must finish bulk before cw');local h=assert(B.Decode(item.packet));assert(h.view==201 and h.base_revision==1 and h.scope==17);packets[#packets+1]=item.packet
 else seen_cw=true;assert(W.peek_header(item.packet).revision==3)end
end
assert(#packets==4 and seen_cw)
-- Full recovery invalidates a queued receipt and resets its atomic epoch.
local before=#out;local current=assert(rt.bulk_lottery_binding(0,201))
assert(rt.publish_bulk_lottery(0,201,raw,18,{epoch=current.epoch,base_revision=3,next_revision=4}))
assert(rt.publish(0,201,{{record=R['daily:state'],field=F.count,value=111}},{full=true}))
local after_recovery=#out;flush()
for n=after_recovery+1,#out do assert(out[n].event=='cw')end
assert(rt.bulk_lottery_binding(0,201).epoch==2)
-- Close cancels queued frames, disables capability, and never retries a draw.
current=assert(rt.bulk_lottery_binding(0,201));assert(rt.publish_bulk_lottery(0,201,raw,19,{epoch=current.epoch,base_revision=1,next_revision=2}))
control(201,{visible=0,known=0});before=#out;flush();assert(#out==before and not rt.bulk_lottery_enabled(0,201))
assert(not rt.publish_bulk_lottery(0,201,raw,19,{epoch=2,base_revision=2,next_revision=3}))
-- Failed native send marks recovery required. Never reserve a second gb delta.
control(201,{visible=1,types=2});flush();current=assert(rt.bulk_lottery_binding(0,201));setfail(true)
local accepted,failed=rt.publish_bulk_lottery(0,201,raw,20,{epoch=current.epoch,base_revision=1,next_revision=2})
assert(not accepted and failed=='native_send_failed','synchronous failure must not report accepted');flush()
assert(not rt.bulk_lottery_binding(0,201));setfail(false)
assert(rt.publish(0,201,{{record=R['daily:state'],field=F.count,value=111}}));flush();assert(rt.bulk_lottery_binding(0,201).base_revision==1)
-- A queued receipt behind a failed CW predecessor recovers once without a
-- consumptive command or an unrelated future profile publication.
local retry,qout,qflush,qcontrol,qfail,qtasks=setup();qcontrol(201,{visible=1,types=2});qflush()
local predecessor={};for n=1,20 do predecessor[n]={record=R['wire:hello:'..((n-1)%8+1)],field=n<=8 and F.count or n<=16 and F.arg_a or F.arg_b,value=n}end
assert(retry.publish(0,201,predecessor));local bound=assert(retry.bulk_lottery_binding(0,201));local recoveries=0
assert(retry.publish_bulk_lottery(0,201,raw,22,{epoch=bound.epoch,base_revision=bound.base_revision,next_revision=bound.base_revision+1,
 on_failure=function(reason)
  assert(reason=='native_send_failed');recoveries=recoveries+1;qfail(false)
  assert(retry.publish(0,201,{{record=R['daily:state'],field=F.count,value=111}},{full=true}))
 end}))
qfail(true);qflush();assert(recoveries==1 and retry.bulk_lottery_binding(0,201).base_revision==1 and not next(qtasks))
assert(W.peek_header(qout[#qout].packet).kind=='full','one automatic recovery must be a new full epoch')
-- Missing local codec manifest cannot negotiate despite an incoming types=2.
local old={};for k,v in pairs(L)do old[k]=v end;old.lottery_receipt=nil
local legacy,_,drain,open=setup(old);open(201,{visible=1,types=2});drain();assert(not legacy.bulk_lottery_enabled(0,201))
-- All four pools use the same private channel; grid stays on types=1/tag0x21.
for view=202,204 do control(view,{visible=1,types=2});flush();assert(rt.bulk_lottery_enabled(0,view))end
-- A cw predecessor and successor share the same FIFO with an urgent receipt.
local changes={};for n=1,20 do changes[n]={record=R['wire:hello:'..((n-1)%8+1)],field=n<=8 and F.count or n<=16 and F.arg_a or F.arg_b,value=n}end
before=#out;assert(rt.publish(0,202,changes));current=assert(rt.bulk_lottery_binding(0,202))
assert(current.base_revision==2);assert(rt.publish_bulk_lottery(0,202,raw,21,{epoch=current.epoch,base_revision=2,next_revision=3}))
assert(rt.publish(0,202,{{record=R['daily:state'],field=F.count,value=101}}));flush()
local phase=1;local saw_bulk,saw_successor=false,false
for n=before+1,#out do local item=out[n]
 if item.event=='gb'then assert(phase<=2);phase=2;saw_bulk=true
 else local h=assert(W.peek_header(item.packet));if h.revision==2 then assert(phase==1)else assert(h.revision==4 and saw_bulk);phase=3;saw_successor=true end end
end
assert(saw_bulk and saw_successor)
-- Eight per-view jobs bound retained blobs even when the global driver is busy.
for token=30,37 do current=assert(rt.bulk_lottery_binding(0,203));assert(rt.publish_bulk_lottery(0,203,string.rep('x',16384),token,
 {epoch=current.epoch,base_revision=current.base_revision,next_revision=current.base_revision+1}))end
assert(rt.queue_depth(0,203)==8);current=assert(rt.bulk_lottery_binding(0,203))
assert(not rt.publish_bulk_lottery(0,203,raw,38,{epoch=current.epoch,base_revision=current.base_revision,next_revision=current.base_revision+1}))
assert(rt.bulk_lottery_binding(0,203).base_revision==current.base_revision)
control(203,{visible=0});flush();assert(rt.queue_depth(0,203)==0)
control(6,{visible=1,types=1});flush();assert(rt.bulk_static_enabled(0))
local grid=assert(rt.bulk_binding(0));local g=assert(B.Encode(grid,3,'terrain'));assert(B.Decode(g[1]).view==6)
local value={binding=first,scope=17,raw_hex=(raw:gsub('.',function(c)return string.format('%02x',string.byte(c))end)),packets=packets,
 report={bulk_frames=#packets,raw_bytes=#raw,native_measured=false},status='PASS_LOTTERY_BULK_TRANSPORT_LUA_SYNTHETIC_NOT_NATIVE'}
print(require('core/json_encoder').encode(value))
