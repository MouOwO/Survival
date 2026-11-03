"use strict";
// Executes the real Lua encoder and the shipped pure JS decoder. Synthetic
// counters are not an engine/network byte or FPS measurement.
const assert=require("node:assert/strict"), fs=require("node:fs"), path=require("node:path"), cp=require("node:child_process");
const root=path.resolve(__dirname,".."), wire=require("../panorama/src/scripts/custom_game/common/compact_wire.js");
const lua=process.env.LUA51 || "C:/Program Files/lua/bin/lua5.1.exe";
const golden=JSON.parse(cp.execFileSync(lua,["scripts/vscripts/tests/test_compact_wire.lua","emit"],{cwd:root,encoding:"utf8"}));
const fields=Object.fromEntries(golden.schema.fields.map((v,i)=>[i+1,v]));
const spec={...golden.schema,fields}, schema=wire.CompileSchema(spec), binding=golden.binding;
let checks=0;
function test(name,fn){fn();checks++;console.log("ok",name);}
function reject(fn,message){assert.throws(fn,e=>e.message===message);}
// Independent test framing, deliberately not a JS production encoder.
function vu(n){const b=[];do{let p=n%128;n=Math.floor(n/128);b.push(p+(n?128:0));}while(n);return b;}
function packet(body,{tag=17,rev=1,index=1,count=1,bind=binding}={}){
 return {d:Buffer.from([tag,...[bind.schema,bind.session,bind.epoch,bind.view,rev,index,count].flatMap(vu),...body]).toString("base64url")};
}
function changes(list){return list.flatMap(c=>[...vu(c.record),...vu(c.field*2+(c.remove?1:0)),...(c.remove?[]:vu(c.value))]);}
const full=golden.golden_full[0];
test("real Lua golden full, multipart signed uint32 delta and resync",()=>{
 assert.deepEqual(wire.Encode(schema,binding,1,[{record:1,field:1,value:7}],{full:true}).packets,golden.golden_full);
 assert.deepEqual(wire.Encode(schema,binding,2,golden.delta_changes).packets,golden.golden_delta);
 const r=wire.NewReceiver(schema,binding);let tx=r.Accept(full);assert.equal(tx.changes[0].value,7);assert.equal(r.Inspect().revision,0);
 reject(()=>r.Accept(full),"commit_required");reject(()=>r.Commit({...tx}),"transaction_not_pending");r.Commit(tx);
 for(const p of [...golden.golden_delta].reverse())tx=r.Accept(p);
 assert.equal(tx.changes[0].value,-2147483647);assert.equal(tx.changes[1].value,4294967295);assert.equal(tx.changes[2].value,1);assert.equal(tx.changes[4].remove,true);r.Commit(tx);
 assert.deepEqual(wire.EncodeResync(schema,binding,0,1),golden.golden_resync);
 assert.deepEqual(wire.DecodeResync(schema,binding,golden.golden_resync),{revision:0,reason:1});
 assert.equal(r.Inspect().revision,2);reject(()=>r.Accept(full),"stale_revision");
});
test("binding and token bounds never truncate uint32",()=>{
 const peek=wire.PeekHeader(full);assert.equal(peek.view,1);assert.equal(peek.session,1);assert.equal(peek.schema,1);assert.equal(peek.body,undefined);
 reject(()=>wire.PeekHeader(packet([],{bind:{...binding,session:16384}})),"binding_token_invalid");
 reject(()=>wire.DecodePacket(schema,{...binding,view:2},full),"stale_binding");
 reject(()=>wire.DecodePacket(schema,{...binding,session:16384},full),"binding_token_invalid");
 reject(()=>wire.DecodePacket(schema,{...binding,schema_sha256:"b".repeat(64)},full),"schema_binding_mismatch");
 reject(()=>wire.DecodePacket(schema,binding,packet([],{bind:{...binding,schema:2}})),"schema_unknown");
 reject(()=>wire.DecodePacket(schema,binding,packet([],{rev:2097152})),"revision_requires_new_epoch");
 reject(()=>wire.DecodePacket(schema,binding,packet([],{index:0})),"fragment_index_invalid");
 reject(()=>wire.DecodePacket(schema,binding,packet([],{count:16384})),"fragment_index_invalid");
});
test("canonical base64url, varints and exact one-key envelope",()=>{
 for(const v of ["!","AA=","A","A+"])reject(()=>wire.DecodePacket(schema,binding,{d:v}),"invalid_base64url");
 reject(()=>wire.DecodePacket(schema,binding,{d:"AB"}),"noncanonical_base64url");
 reject(()=>wire.DecodePacket(schema,binding,{...full,x:1}),"packet_key_unknown");
 reject(()=>wire.DecodePacket(schema,binding,{d:"A".repeat(25)}),"encoded_value_budget_exceeded");
 const raw=Buffer.from(full.d,"base64url");raw[1]=128;
 reject(()=>wire.DecodePacket(schema,binding,{d:Buffer.concat([raw.subarray(0,2),Buffer.from([0]),raw.subarray(2)]).toString("base64url")}),"noncanonical_varint");
 reject(()=>wire.DecodePacket(schema,binding,{d:Buffer.from([17,255,255,255,255,127]).toString("base64url")}),"varint_overflow");
 reject(()=>wire.DecodePacket(schema,binding,{d:Buffer.from([17,128]).toString("base64url")}),"truncated_varint");
});
test("holes, tombstones, enums and unknown defaults",()=>{
 const s=wire.CompileLookup({sha256:spec.sha256,records:{1:{id:1},3:{id:3,tombstone:true}},fields},1);
 const r=wire.NewReceiver(s,binding);reject(()=>r.Accept(packet(changes([{record:3,field:1,value:0}]))),"record_unknown");
 reject(()=>wire.NewReceiver(schema,binding).Accept(packet(changes([{record:1,field:5,value:0}]))),"field_unknown");
 reject(()=>wire.NewReceiver(schema,binding).Accept(packet(changes([{record:1,field:4,value:1}]))),"field_enum_unknown");
 reject(()=>wire.NewReceiver(schema,binding).Accept(packet(changes([{record:1,field:3,value:2}]))),"field_value_range");
 reject(()=>wire.CompileSchema({...spec,records:[1,1]}),"record_registry_invalid");
 reject(()=>wire.CompileLookup({sha256:spec.sha256,records:{2:{id:1}},fields},1),"record_registry_invalid");
 const sparse=[1,,2];reject(()=>wire.CompileSchema({...spec,records:sparse}),"sparse_or_named_array");
 const c=wire.NewClient(wire.CompileSchema({...spec,fields:{1:{kind:"uint",default:null}}}),binding);
 c.Accept(packet([]));assert.equal(c.Read(1,1),undefined);
});
test("append-only fields 128/129/255 preserve old goldens and do not collide",()=>{
 const wide=golden.extended_fields,s=wire.CompileSchema(wide.schema),c=wire.NewClient(s,binding);
 for(const p of wide.packets){assert.ok(p.d.length<=24);c.Accept(p);}
 assert.equal(c.Read(1,129),7);assert.equal(c.Read(2,1),8);
 assert.equal(c.Read(65535,255),4294967295);assert.equal(c.Read(1,128),undefined);
 assert.equal(wire.limits.field_id,255);
 reject(()=>wire.CompileSchema({...wide.schema,fields:{...wide.schema.fields,256:{kind:"uint"}}}),"field_registry_invalid");
 reject(()=>wire.NewReceiver(s,binding).Accept(packet(changes([{record:1,field:254,value:0}]))),"field_unknown");
 reject(()=>wire.NewReceiver(s,binding).Accept(packet(changes([{record:1,field:129,value:1},{record:1,field:129,value:2}]))),"duplicate_changed_index");
 assert.deepEqual(wire.Encode(s,binding,1,wide.changes,{full:true}).packets,wide.packets);
});
test("transaction atomically rejects duplicate fields and bad final fragments",()=>{
 const r=wire.NewReceiver(schema,binding), body=changes([{record:1,field:1,value:9},{record:1,field:1,value:10}]);
 assert.equal(r.Accept(packet(body.slice(0,3),{index:1,count:2})).pending,true);
 reject(()=>r.Accept(packet(body.slice(3),{index:2,count:2})),"duplicate_changed_index");
 assert.equal(r.Inspect().revision,0);assert.equal(r.Inspect().commit_pending,false);assert.equal(r.Inspect().buffered_bytes,0);
});
test("fragments out of order, duplicates, conflicts and bounded memory",()=>{
 const a=packet([1,2],{count:2}),b=packet([7],{index:2,count:2}),r=wire.NewReceiver(schema,binding);
 assert.equal(r.Accept(b).pending,true);assert.equal(r.Accept(b).duplicate,true);const tx=r.Accept(a);assert.equal(tx.changes[0].value,7);r.Commit(tx);
 const c=wire.NewReceiver(schema,binding);c.Accept(a);reject(()=>c.Accept(packet([2,2],{count:2})),"duplicate_fragment_conflict");
 assert.equal(c.Inspect().buffered_bytes,0);
 const d=wire.NewReceiver(schema,binding);d.Accept(a);reject(()=>d.Accept(packet([7],{index:2,count:3})),"fragment_identity_conflict");
 reject(()=>wire.NewReceiver(schema,binding,{assembly_bytes:1}).Accept(a),"assembly_byte_limit");
 reject(()=>wire.NewReceiver(schema,binding,{max_fragments:1}).Accept(a),"assembly_fragment_limit");
});
test("missing base sends only one failure resync; full repairs it",()=>{
 let calls=0,commit=0;const c=wire.NewClient(schema,binding,{onResync:p=>{calls++;assert.equal(Object.keys(p).join(),"d");assert.ok(p.d.length<=24);},onCommit:()=>commit++});
 const delta=packet(changes([{record:1,field:1,value:9}]),{tag:16,rev:2});
 assert.equal(c.Accept(delta).error,"missing_base");c.Accept(delta);assert.equal(calls,1);assert.equal(c.Read(1,1),undefined);
 c.Accept(full);assert.equal(c.Read(1,1),7);assert.equal(commit,1);assert.equal(c.Inspect().resync_pending,false);
 c.Accept(packet([],{tag:16,rev:3}));assert.equal(calls,2);
});
test("same state changes produce zero render callbacks or timers",()=>{
 let renders=0,timers=0;const c=wire.NewClient(schema,binding,{onCommit:()=>renders++,schedule:()=>{timers++;return 1;},cancel:()=>{}});
 c.Accept(full);const row=c.Read(1);for(let rev=2;rev<=1001;rev++)c.Accept(packet(changes([{record:1,field:1,value:7}]),{tag:16,rev}));
 assert.equal(renders,1);assert.equal(timers,0);assert.equal(c.Read(1),row);assert.equal(c.Inspect().counters.changed_fields,1);
});
test("typed removal never manufactures zero and application reject is atomic",()=>{
 let rejectApp=false;const c=wire.NewClient(schema,binding,{validate:()=>!rejectApp});c.Accept(full);rejectApp=true;
 assert.equal(c.Accept(packet(changes([{record:1,field:1,value:8}]),{tag:16,rev:2})).error,"application_rejected");
 assert.equal(c.Read(1,1),7);assert.equal(c.Inspect().receiver.revision,1);rejectApp=false;
 c.Accept(packet(changes([{record:1,field:1,remove:true}]),{tag:16,rev:2}));assert.equal(c.Read(1,1),undefined);
});
test("priority queue bypasses stale background work; queue copies immutable payload",()=>{
 const c=wire.NewClient(schema,binding,{queue_packets:3});const queued={...full};c.Enqueue(queued,false);queued.d="bad";
 c.Enqueue(packet(changes([{record:1,field:1,value:12}]),{rev:5}),true);
 const out=c.Drain(1);assert.equal(out[0].revision,5);assert.equal(c.Read(1,1),12);assert.equal(c.Drain(1)[0].stale,true);
 c.Enqueue(full);c.Enqueue(full);c.Enqueue(full);assert.equal(c.Enqueue(full).error,"queue_limit");
});
test("generation, old session/view packets, rebind and Dispose invalidate work",()=>{
 let resync=0;const c=wire.NewClient(schema,binding,{onResync:()=>resync++});c.Accept(packet([1,2],{count:2}));
 const next={...binding,session:2,epoch:2,view:3};c.Rebind(next);assert.equal(c.Inspect().receiver.buffered_bytes,0);
 assert.equal(c.Accept(full).stale,true);assert.equal(resync,0);c.Accept(packet([1,2,9],{bind:next}));assert.equal(c.Read(1,1),9);
 c.Enqueue(packet([],{bind:next}));c.Dispose();assert.equal(c.Accept(full).error,"disposed");assert.equal(c.Inspect().queued,0);assert.equal(c.Read(1),undefined);
 const r=wire.NewReceiver(schema,binding);const tx=r.Accept(full);r.Rebind(next);reject(()=>r.Commit(tx),"transaction_not_pending");
});
test("assembly failure deadline is one-shot, canceled on completion/dispose",()=>{
 let now=0,callbacks=[],canceled=0,resync=0;const c=wire.NewClient(schema,binding,{now:()=>now,assembly_deadline_ms:100,schedule:(ms,fn)=>{callbacks.push(fn);return callbacks.length;},cancel:()=>canceled++,onResync:()=>resync++});
 c.Accept(packet([1,2],{count:2}));c.Accept(packet([1,2],{count:2}));assert.equal(callbacks.length,1);
 now=101;callbacks[0]();assert.equal(resync,1);callbacks[0]();assert.equal(resync,1);
 c.Accept(packet([1,2],{count:2}));c.Accept(packet([7],{index:2,count:2}));assert.ok(canceled>=1);assert.equal(c.Read(1,1),7);
 c.Accept(packet([1,2],{rev:2,count:2}));c.Dispose();now=500;callbacks.at(-1)();assert.equal(resync,1);
});
test("sparse delta cost independent of 10,000 catalogue records",()=>{
 const big=wire.CompileSchema({...spec,records:Array.from({length:10000},(_,i)=>i+1)});
 const c=wire.NewClient(big,binding);c.Accept(full);let scans=0;const original=Object.keys;
 Object.keys=function(o){scans++;return original(o);};try{for(let rev=2;rev<=1001;rev++)c.Accept(packet([1,2,...vu(rev)],{tag:16,rev}));}finally{Object.keys=original;}
 assert.ok(scans<=3000,`sparse delta scanned registry: ${scans}`);assert.equal(c.Read(1,1),1001);assert.equal(c.Inspect().counters.changed_fields,1001);
});
test("real immutable static catalogue has no unknown record fallback",()=>{
 const p=path.join(root,"data/ui/ui_static_catalog_registry.json");
 const registry=JSON.parse(fs.readFileSync(p,"utf8"));
 const catalogueSource=fs.readFileSync(path.join(root,"panorama/src/scripts/custom_game/common/ui_static_catalog.js"),"utf8");
 const vm=require("node:vm"),cfg={};vm.runInNewContext(catalogueSource,{GameUI:{CustomUIConfig:()=>cfg}});
 const s=wire.CompileLookup(cfg.SurvivalUICatalog,1),b={...binding,schema_sha256:s.sha256};
 assert.equal(s.record_count,registry.records.filter(r=>!r.tombstone).length);assert.ok(s.field_count>=46);
 const id=registry.records.find(r=>r.key==="daily:state").id,c=wire.NewClient(s,b);c.Accept(packet(changes([{record:id,field:1,value:1}]),{bind:b}));assert.equal(c.Read(id,1),1);
});
console.log(JSON.stringify({status:"PASS_COMPACT_WIRE_JS_LUA_SYNTHETIC_NOT_NATIVE",tests:checks,native_calls:0,http_calls:0,sdk_calls:0,stable_timers:0,native_bytes_proven:false}));
