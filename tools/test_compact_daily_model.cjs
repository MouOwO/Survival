"use strict";
const assert=require("node:assert/strict"),fs=require("node:fs"),path=require("node:path"),vm=require("node:vm"),cp=require("node:child_process");
const root=path.resolve(__dirname,".."),api=require("../panorama/src/scripts/custom_game/common/compact_daily_model.js"),cfg={};
vm.runInNewContext(fs.readFileSync(path.join(root,"panorama/src/scripts/custom_game/common/ui_static_catalog.js"),"utf8"),{GameUI:{CustomUIConfig:()=>cfg}});
const C=cfg.SurvivalUICatalog,fixture=JSON.parse(cp.execFileSync(process.env.LUA51||"C:/Program Files/lua/bin/lua5.1.exe",["scripts/vscripts/tests/test_compact_daily_projection.lua","emit"],{cwd:root,encoding:"utf8"}).trim().split(/\r?\n/).at(-1));
let checks=0;function test(name,fn){fn();checks++;console.log("ok",name);}
function store(){let rows=Object.create(null);return {put(ops){const changed=[],seen=new Set();for(const op of ops){const r=rows[op.record]||(rows[op.record]=Object.create(null));if(op.remove)delete r[op.field];else r[op.field]=op.value;if(!seen.has(op.record)){seen.add(op.record);changed.push(op.record);}}return changed;},read:(r,f)=>rows[r]&&rows[r][f]};}
function subset(actual,expected,location="snapshot"){
 if(expected===null||typeof expected!=="object"){assert.equal(actual,expected,location);return;}
 assert.ok(actual&&typeof actual==="object",location+" object missing");for(const k of Object.keys(expected))subset(actual[k],expected[k],location+"."+k);
}
const initialOps=fixture.initial_ops_fixture,thresholdOps=fixture.threshold_ops_fixture;
test("real Lua initial and changed projection reconstruct every legacy field",()=>{
 const m=api.Create(C),s=store();let changed=s.put(initialOps),result=m.Apply({full:true,revision:1},changed,s.read);
 assert.equal(result.known,true);subset(result.snapshot,fixture.initial_expected);
 const calendar=result.snapshot.calendar28,first=calendar[0];changed=s.put(thresholdOps);result=m.Apply({full:false,revision:2},changed,s.read);
 subset(result.snapshot,fixture.threshold_expected);assert.equal(result.snapshot.calendar28,calendar);assert.equal(calendar[0],first);
 assert.equal(result.changes.calendar.length,0);assert.equal(result.changes.specials.length,0);assert.ok(result.changes.benefitRows.length<=6);
});
test("stable empty update and unrelated record do not visit catalogue or render regions",()=>{
 const m=api.Create(C),s=store();m.Apply({full:true,revision:1},s.put(initialOps),s.read);const before=m.Inspect().metrics;
 for(let i=0;i<1000;i++){const result=m.Apply({full:false,revision:i+2},[],s.read);assert.equal(result.changes.summary,false);assert.equal(result.changes.benefitRows.length,0);assert.equal(result.changes.calendar.length,0);}
 const after=m.Inspect().metrics;assert.equal(after.record_visits,before.record_visits);assert.equal(after.calendar_updates,before.calendar_updates);assert.equal(after.benefit_updates,before.benefit_updates);
});
test("one unique item ownership updates only its dependent calendar slots",()=>{
 const m=api.Create(C),s=store();m.Apply({full:true,revision:1},s.put(initialOps),s.read);const id=m.Record("daily:state"),field=m.Field("unique_owned_mask"),old=s.read(id,field),next=old%2===1?old-1:old+1;
 const result=m.Apply({full:false,revision:2},s.put([{record:id,field,value:next}]),s.read);
 assert.ok(result.changes.calendar.length<=4);assert.ok(result.changes.specials.length<=1);assert.equal(result.changes.benefitRows.length,0);assert.equal(result.changes.tracks.length,0);
});
test("pending and expiry removal preserve unknown versus zero",()=>{
 const m=api.Create(C),s=store();m.Apply({full:true,revision:1},s.put(initialOps),s.read);const record=m.Record("daily:state");
 let result=m.Apply({full:false,revision:2},s.put([{record,field:m.Field("pending"),value:1},{record,field:m.Field("expires_at"),remove:true}]),s.read);
 assert.equal(result.snapshot.pending,1);assert.equal(result.snapshot.expires_at,"");assert.equal(result.changes.calendar.length,0);
 result=m.Apply({full:false,revision:3},s.put([{record,field:m.Field("known"),value:0}]),s.read);assert.equal(result.known,false);assert.equal(result.snapshot,null);
});
test("typed ACK is bound to local intent token and cannot optimistically alter scores",()=>{
 const m=api.Create(C),s=store();m.Apply({full:true,revision:1},s.put(initialOps),s.read);const original=m.Snapshot().count,rec=m.Record("daily:ack:claim"),day=m.Snapshot().today,period=Number(m.Snapshot().period_id);
 function ack(token,success,pending,terminal){return Object.entries({known:1,request_token:token,day,period,target_record:0,success,pending,terminal,error_code:pending?10:0}).map(([name,value])=>({record:rec,field:m.Field(name),value}));}
 m.BindIntent("claim",7,{target_day:day,period});let result=m.Apply({full:false,revision:2},s.put(ack(8,1,0,1)),s.read);assert.equal(result.changes.acks.length,0);
 result=m.Apply({full:false,revision:3},s.put(ack(7,0,1,0)),s.read);assert.equal(result.snapshot.claim_result.pending,true);assert.equal(result.snapshot.claim_result.ok,false);assert.equal(result.snapshot.count,original);
 result=m.Apply({full:false,revision:4},s.put(ack(7,1,0,1)),s.read);assert.equal(result.snapshot.claim_result.ok,true);assert.equal(result.snapshot.count,original);
 result=m.Apply({full:false,revision:5},[rec],s.read);assert.equal(result.changes.acks.length,0);
});
test("unsigned hi/lo is exact through safe integer boundary",()=>{
 assert.equal(api.JoinUnsigned(4294967295,2097151),9007199254740991);assert.equal(api.JoinUnsigned(0,1),4294967296);assert.throws(()=>api.JoinUnsigned(0,2097152),/daily_uint64_invalid/);
});
test("reset and dispose invalidate intents and dynamic model",()=>{
 const m=api.Create(C),s=store();m.Apply({full:true,revision:1},s.put(initialOps),s.read);const old=m.Inspect().generation;m.Reset();assert.equal(m.Snapshot(),null);assert.ok(m.Inspect().generation>old);m.Dispose();assert.throws(()=>m.Apply({full:false},[],s.read),/daily_model_disposed/);
});
test("repeated full rebuilds retire old dynamic row dependencies",()=>{
 const m=api.Create(C),s=store();s.put(initialOps);let previous;
 for(let revision=1;revision<=100;revision++){const result=m.Apply({full:true,revision},[],s.read);if(previous)assert.notEqual(result.snapshot.calendar28[0],previous);previous=result.snapshot.calendar28[0];}
 const record=m.Record("daily:state"),field=m.Field("unique_owned_mask"),mask=s.read(record,field),next=mask%2===1?mask-1:mask+1;
 const result=m.Apply({full:false,revision:101},s.put([{record,field,value:next}]),s.read);assert.ok(result.changes.calendar.length<=4);assert.equal(m.Inspect().metrics.registry_scans,1);
});
console.log(JSON.stringify({status:"PASS_COMPACT_DAILY_MODEL_SYNTHETIC_NOT_NATIVE",tests:checks,native_calls:0,network_calls:0,timers:0}));
