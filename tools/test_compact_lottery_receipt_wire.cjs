"use strict";
// Actual codec/model/projection functions, offline only. No player or HTTP I/O.
const assert=require("node:assert/strict"),fs=require("node:fs"),vm=require("node:vm"),cp=require("node:child_process"),os=require("node:os"),path=require("node:path");
const api=require("../panorama/src/scripts/custom_game/common/compact_lottery_receipt_wire.js"),model=require("../panorama/src/scripts/custom_game/common/compact_lottery_model.js"),cfg={};
vm.runInNewContext(fs.readFileSync("panorama/src/scripts/custom_game/common/ui_static_catalog.js","utf8"),{GameUI:{CustomUIConfig:()=>cfg}});
const C=cfg.SurvivalUICatalog.Data,codec=api.Create(C),R=Object.fromEntries(C.records.map(r=>[r.key,r.id])),F=Object.fromEntries(C.fields.map(f=>[f.name,f.id]));
const lua=process.env.LUA51||"C:/Program Files/lua/bin/lua5.1.exe";
const fixture=JSON.parse(cp.execFileSync(lua,["scripts/vscripts/tests/test_compact_lottery_projection.lua","emit"],{encoding:"utf8"}));
const item=C.auxiliary.lottery_public.snapshots[0].items[0],vectors=[];let tests=0;
function test(name,fn){fn();tests++;console.log("ok",name);}
function encode(receipt,changes=[],view=201){const raw=codec.Encode(view,2,receipt,changes);vectors.push({view,revision:2,receipt,changes,hex:Buffer.from(raw,"latin1").toString("hex")});return raw;}
function receipt(count=10){return{count,guarantee_quality:3,guarantee_satisfied:true,results:Array.from({length:count},(_,i)=>({record:R["lottery:item:"+item.id],owned_count:i?1:0,duplicate:!!i,converted_points:i?item.duplicate_points||0:0}))};}
function store(){const values={};return {put(ops){const ids=new Set();for(const op of ops){const row=values[op.record]||(values[op.record]={});if(op.remove)delete row[op.field];else row[op.field]=op.value;ids.add(op.record);}return [...ids];},read:(r,f)=>values[r]&&values[r][f],values};}
test("ten result receipt uses local immutable definitions and exact exception values",()=>{
 const r=receipt(),changes=[{record:R["lottery:pool:map"],field:F.tickets,value:90},{record:R["lottery:currency:lottery_ticket"],field:F.owned_count,value:90}];
 const raw=encode(r,changes),d=codec.Decode(201,raw);assert.deepEqual(d.receipt,r);assert.deepEqual(d.changes,changes.slice().sort((a,b)=>a.record-b.record));assert(raw.length<80);
 const m=model.Create(C,"map"),s=store();m.Apply({full:true,revision:1},s.put(fixture.initial_ops),s.read);m.BindIntent(31,"same-local-request",10);
 const result=m.Apply({full:false,revision:2},s.put(codec.Operations(201,31,d)),s.read);
 assert.equal(result.result.results.length,10);assert.equal(result.result.request_id,"same-local-request");assert.equal(result.snapshot.tickets,90);
 assert.equal(result.result.results[0].id,item.id);assert.equal(result.result.results[0].owned_count,0);assert.equal(m.HasIntent(31),false);
 assert.equal(m.Apply({full:false,revision:3},[],s.read).result,null);
});
test("single result, safe53 counters and explicit optional zero preserve absence",()=>{
 const r=receipt(1);r.results[0]={...r.results[0],owned_count:Number.MAX_SAFE_INTEGER,converted_points:Number.MAX_SAFE_INTEGER,granted_count:4294967295,overflow_count:0};
 assert.deepEqual(codec.Decode(201,encode(r)).receipt,r);
 const d=codec.Decode(201,encode(receipt(1))),ops=codec.Operations(201,2,d);
 assert(ops.some(o=>o.record===R["lottery:result:1"]&&o.field===F.granted_count&&o.remove));
 assert(ops.some(o=>o.record===R["lottery:result:10"]&&o.field===F.known&&o.value===0));
});
test("malformed, sparse, wrong pool and duplicate state fields cannot decode valid state",()=>{
 const r=receipt(),raw=encode(r);
 assert.throws(()=>codec.Decode(201,raw+"\0"),/trailing/);assert.throws(()=>codec.Decode(201,raw.slice(0,-1)),/truncated/);
 assert.throws(()=>codec.Decode(201,String.fromCharCode(2)),/version/);assert.throws(()=>codec.Encode(201,2,{...r,count:2},[]),/count/);
 const sparse=receipt();delete sparse.results[1];assert.throws(()=>codec.Encode(201,2,sparse,[]),/row_invalid/);
 const op={record:R["lottery:state"],field:F.balance,value:2};assert.throws(()=>codec.Encode(201,2,r,[op,op]),/duplicate/);
 assert.throws(()=>codec.Encode(201,2,r,[{record:R["lottery:receipt"],field:F.known,value:1}]),/forbidden/);
 assert.throws(()=>codec.Encode(201,2,{...r,results:[{...r.results[0],record:R["daily:state"]},...r.results.slice(1)]},[]),/record/);
 const selected=new Set(C.auxiliary.lottery_public.snapshots[0].items.map(i=>i.id));
 const foreign=C.auxiliary.lottery_public.snapshots.flatMap(s=>s.items).find(i=>!selected.has(i.id));
 assert(foreign);assert.throws(()=>codec.Encode(201,2,r,[{record:R['lottery:item:'+foreign.id],field:F.owned_count,value:1}]),/not_in_pool/);
 assert.throws(()=>codec.Decode(205,raw),/view/);
});
test("pending count, close/reopen retention and genuine world reset remain explicit",()=>{
 const m=model.Create(C,"map");m.BindIntent(91,"request",10);assert.equal(m.HasIntent(91,1),false);assert.equal(m.HasIntent(91,10),true);
 // Closing a view never disposes the shared model: its full read-only recovery
 // may still resolve the original intent. Only a genuine world reset clears it.
 assert.equal(m.HasIntent(91),true);m.ResetIntents();assert.equal(m.HasIntent(91),false);
 m.BindIntent(91,"new-world",1);m.Dispose();assert.equal(m.HasIntent(91),false);
});
test("steady codec calls perform zero registry scans and do not schedule work",()=>{
 const before=codec.Inspect(),r=receipt(1);for(let i=0;i<1000;i++){const raw=codec.Encode(201,2,r,[]);codec.Decode(201,raw);}
 assert.deepEqual(codec.Inspect(),before);assert.equal(before.steady_registry_visits,0);
});
test("production Lua server lookup matches JS bytes for every vector",()=>{
 const seed={wire_version:1,pools:[],duplicate_points:{}};
 for(const s of C.auxiliary.lottery_public.snapshots){seed.pools.push({id:s.selected_pool_id,items:s.items.map(i=>i.id)});for(const i of s.items)seed.duplicate_points[i.id]=i.duplicate_points||0;}
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),"lottery-wire-")),file=path.join(dir,"vectors.json");
 try{fs.writeFileSync(file,JSON.stringify({seed,vectors}));const result=cp.execFileSync(lua,["scripts/vscripts/tests/test_compact_lottery_receipt_wire.lua",file],{encoding:"utf8"});assert.match(result,/LUA_PARITY_PASS/);}finally{fs.unlinkSync(file);fs.rmdirSync(dir);}
});
console.log(JSON.stringify({status:"PASS_PRODUCTION_CODEC_OFFLINE_NOT_NATIVE",tests,vectors:vectors.length,stable_registry_scans:0,network_calls:0,player_transactions:0}));
