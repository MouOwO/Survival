"use strict";
// Codec, runtime and real Lua queue integration. Synthetic, not native latency/FPS.
const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),cp=require('node:child_process');
const W=require('../panorama/src/scripts/custom_game/common/compact_wire.js');
const B=require('../panorama/src/scripts/custom_game/common/compact_grid_bulk_wire.js');
const API=require('../panorama/src/scripts/custom_game/common/compact_ui_runtime.js');
const cfg={};vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/common/ui_static_catalog.js','utf8'),{GameUI:{CustomUIConfig:()=>cfg}});
const source=cfg.SurvivalUICatalog.Data,C={...source,auxiliary:{...source.auxiliary,lottery_receipt_wire_version:1}},schema=W.CompileLookup(C,1);
const F=Object.fromEntries(C.fields.map(x=>[x.name,x.id])),R=Object.fromEntries(C.records.filter(x=>!x.tombstone).map(x=>[x.key,x.id]));
const key='lottery:'+C.auxiliary.lottery_public.snapshots[0].selected_pool.id;
const binding=(view=201,epoch=1)=>({schema:1,schema_sha256:C.sha256,session:900,view,epoch});
const ops=value=>[{record:R['daily:state'],field:F.count,value}];
const cw=(value,{view=201,epoch=1,revision=1,full=true}={})=>W.Encode(schema,binding(view,epoch),revision,Array.isArray(value)?value:ops(value),{full}).packets;
const gb=(raw='receipt',scope=17,base=1,epoch=1)=>B.Encode({...binding(201,epoch),base_revision:base},scope,raw).packets;
let tests=0;function test(name,fn){fn();tests++;console.log('ok',name);}
function setup({cap=true,manifest=true,bulk=true}={}){
 const listeners={},sent=[],timers=[];let now=0;
 const rt=API.CreateRuntime({wire:W,bulk:bulk?B:undefined,lotteryReceiptWire:cap?{}:undefined,catalogue:manifest?C:{...C,auxiliary:{...C.auxiliary,lottery_receipt_wire_version:undefined}},
  send(event,p){assert.equal(event,'cw');assert.ok(p.d.length<=24);sent.push(p);return true;},
  subscribe(event,fn){listeners[event]=fn;return event;},unsubscribe(){},getLoading:()=>({admission_complete:1,profiles_ready:1,session_id:'lottery_bulk_test_world'}),
  now:()=>now,schedule(ms,fn){const t={ms,fn,due:now+ms,cancelled:false,fired:false};timers.push(t);return t;},cancel(t){t.cancelled=true;}});
 const feed=packets=>packets.forEach(listeners.cw),feedBulk=packets=>packets.forEach(listeners.gb);
 const hello=()=>feed(cw(Array.from({length:8},(_,i)=>({record:R['wire:hello:'+(i+1)],field:F.count,value:parseInt(C.sha256.slice(i*8,i*8+8),16)})),{view:1}));
 return{rt,sent,timers,feed,feedBulk,hello,expire(){now+=5001;timers.forEach(t=>{if(!t.cancelled&&!t.fired&&t.due<=now){t.fired=true;t.fn();}});}};
}
function opened(t,callbacks={}){const v=t.rt.CreateView(key,{bulkLottery:true,acceptBulk:h=>h.scope===17,onBulkDecode:h=>({revision:h.base_revision+1,changes:ops(131)}),...callbacks});v.Open();t.hello();t.feed(cw(141));return v;}
test('Lua and JS lottery framing agree, queues reserve one exact revision and preserve grid bytes',()=>{
 const fixture=JSON.parse(cp.execFileSync(process.env.LUA51||'C:/Program Files/lua/bin/lua5.1.exe',['scripts/vscripts/tests/test_compact_lottery_bulk_transport.lua'],{encoding:'utf8'}));
 const raw=Buffer.from(fixture.raw_hex,'hex').toString('binary');assert.deepEqual(B.Encode(fixture.binding,17,raw).packets,fixture.packets);assert.equal(fixture.packets.length,4);
 const rx=B.NewReceiver(fixture.binding,{scope:17});let result;for(const p of [...fixture.packets].reverse())result=rx.Accept(p);assert.equal(result.raw,raw);
 for(const view of [6,201,202,203,204]){const p=B.Encode({...binding(view),base_revision:1},17,'x').packets[0],buf=Buffer.from(p.d,'base64url');assert.equal(buf[0],view===6?33:34);buf[0]=view===6?34:33;assert.throws(()=>B.Decode({d:buf.toString('base64url')}),/header_invalid/);}
 for(const view of [200,205,1])assert.throws(()=>B.Encode({...binding(view),base_revision:1},17,'x'),/binding_invalid/);
});
test('ApplyExternal uses the same typed staging/validation and exact revision as cw',()=>{
 let reject=false,commits=0,resync=0;const c=W.NewClient(schema,binding(),{validate:()=>!reject,onCommit:()=>commits++,onResync:()=>resync++});cw(141).forEach(c.Accept);
 assert.equal(c.ApplyExternal(1,2,ops(131)).committed,true);assert.equal(c.Read(R['daily:state'],F.count),131);assert.equal(c.Inspect().receiver.revision,2);
 assert.equal(c.ApplyExternal(1,2,ops(99)).stale,true);assert.equal(resync,0);assert.equal(commits,2);
 reject=true;assert.equal(c.ApplyExternal(2,3,ops(99)).error,'application_rejected');assert.equal(c.Read(R['daily:state'],F.count),131);assert.equal(c.Inspect().receiver.revision,2);
 reject=false;for(const changes of [[...ops(1),...ops(2)],[{record:R['daily:state'],field:F.count,value:-1}],[{record:R['daily:state'],field:F.count,value:1,extra:true}]])assert.ok(c.ApplyExternal(2,3,changes).error);
 assert.equal(c.Inspect().receiver.revision,2);assert.equal(resync,1);assert.ok(c.ApplyExternal(4,5,ops(3)).error);assert.equal(resync,1);
 cw(131,{epoch:1,revision:4}).forEach(c.Accept);assert.equal(c.Inspect().resync_pending,false);
 assert.equal(c.ApplyExternal(4,5,ops(131)).committed,true);assert.equal(commits,3,'unchanged external values do not repaint');
});
test('receipt capability requires codec, bulk transport, manifest and per-view opt-in',()=>{
 for(const missing of [{cap:false},{manifest:false},{bulk:false},{}]){
  const t=setup(missing),v=opened(t);const r=W.NewReceiver(schema,binding());let values=[];
  for(const p of t.sent){if(W.PeekHeader(p).view===201){const tx=r.Accept(p);if(!tx.pending){values=tx.changes;r.Commit(tx);}}}
  assert.equal(values.find(x=>x.field===F.types)?.value,Object.keys(missing).length?undefined:2);assert.equal(t.rt.Inspect().bulk_lottery_enabled,!Object.keys(missing).length);v.Dispose();
 }
 const t=setup();opened(t,{bulkLottery:false});const packets=t.sent.filter(p=>W.PeekHeader(p).view===201),rx=W.NewReceiver(schema,binding());let tx;packets.forEach(p=>{tx=rx.Accept(p);});assert.ok(!tx.changes.some(c=>c.field===F.types));
});
test('bulk commit advances the shared cw base once; duplicate token and old packets remain silent',()=>{
 const t=setup();let pending=true,commits=0,decode=0;const v=opened(t,{acceptBulk:h=>pending&&h.scope===17,onBulkDecode(h){decode++;return{revision:h.base_revision+1,changes:ops(131)};},onCommit(tx){commits++;if(!tx.full)pending=false;}});
 const sent=t.sent.length;t.feedBulk(gb());assert.equal(v.Read(R['daily:state'],F.count),131);assert.equal(v.Inspect().receiver.receiver.revision,2);assert.equal(decode,1);
 for(let i=0;i<1000;i++)t.feedBulk(gb());assert.equal(t.sent.length,sent);assert.equal(decode,1);assert.equal(commits,2);
 t.feed(cw(121,{revision:3,full:false}));assert.equal(v.Read(R['daily:state'],F.count),121);assert.equal(v.Inspect().receiver.receiver.revision,3);
 assert.equal(t.timers.filter(t=>!t.cancelled&&!t.fired).length,0);
});
test('stale token is ignored; scope replacement cannot combine fragments from different transactions',()=>{
 const t=setup();let token=17,decodes=0;const v=opened(t,{acceptBulk:h=>h.scope===token,onBulkDecode:h=>{decodes++;return{revision:h.base_revision+1,changes:ops(131)};}});
 const before=t.sent.length;t.feedBulk(gb('old receipt',16,20));assert.equal(t.sent.length,before,'an unrequested token cannot provoke recovery even with a future base');
 const p=gb('x'.repeat(2400)),q=gb('y'.repeat(2400),18);t.feedBulk([p[0]]);token=18;t.feedBulk([q[0]]);t.feedBulk(p.slice(1));assert.equal(decodes,0);
 t.feedBulk(q.slice(1));assert.equal(decodes,1);assert.equal(v.Inspect().receiver.receiver.revision,2);assert.equal(t.rt.Inspect().counters.resyncs,0);
});
test('malformed decoder and typed changes never advance state and cause one coalesced resync',()=>{
 for(const decode of [()=>null,()=>{throw Error('bad_receipt');},h=>({revision:h.base_revision+2,changes:ops(1)}),h=>({revision:h.base_revision+1,changes:[...ops(1),...ops(2)]})]){
  const t=setup(),v=opened(t,{onBulkDecode:decode});const before=t.sent.length;for(let i=0;i<20;i++)t.feedBulk(gb());
  assert.equal(v.Inspect().receiver.receiver.revision,1);assert.equal(v.Read(R['daily:state'],F.count),141);assert.equal(t.sent.length,before+1);assert.equal(t.rt.Inspect().counters.resyncs,1);
  t.feed(cw(131,{epoch:2}));assert.equal(v.Inspect().resync_pending,false);
 }
});
test('future base, partial cw collision, deadline, close and dispose do not leak partial state or timers',()=>{
 const t=setup(),v=opened(t);let before=t.sent.length;for(let i=0;i<20;i++)t.feedBulk(gb('x',17,3));assert.equal(t.sent.length,before+1);assert.equal(v.Read(R['daily:state'],F.count),141);
 t.feed(cw(141,{epoch:2}));const large=Array.from({length:20},(_,i)=>({record:C.records.filter(r=>!r.tombstone)[i].id,field:F.count,value:i+1}));
 const parts=cw(large,{epoch:2,revision:2,full:false});assert.ok(parts.length>1);t.feed([parts[0]]);before=t.sent.length;t.feedBulk(gb('x',17,1,2));assert.equal(t.sent.length,before+1);assert.equal(v.Inspect().receiver.receiver.revision,1);
 t.feed(cw(141,{epoch:3}));t.feedBulk([gb('x'.repeat(2400),17,1,3)[0]]);before=t.sent.length;t.expire();assert.equal(t.sent.length,before+1);assert.equal(v.Read(R['daily:state'],F.count),141);
 t.feed(cw(141,{epoch:4}));const p=gb('x'.repeat(2400),17,1,4);t.feedBulk([p[0]]);v.Close();before=t.sent.length;t.feedBulk(p.slice(1));t.expire();assert.equal(t.sent.length,before);assert.equal(t.timers.filter(t=>!t.cancelled&&!t.fired).length,0);
 v.Open();t.feed(cw(141,{epoch:5}));t.feedBulk([gb('x'.repeat(2400),17,1,5)[0]]);t.rt.Dispose();before=t.sent.length;t.expire();assert.equal(t.sent.length,before);assert.equal(t.timers.filter(t=>!t.cancelled&&!t.fired).length,0);
});
console.log(JSON.stringify({status:'PASS_LOTTERY_BULK_TRANSPORT_JS_LUA_SYNTHETIC_NOT_NATIVE',tests,native_calls:0,network_calls:0,sdk_calls:0,paid_transactions:0,native_fps_measured:false}));
