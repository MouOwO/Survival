"use strict";
const assert=require("node:assert/strict"),fs=require("node:fs"),vm=require("node:vm"),cp=require("node:child_process");
const api=require("../panorama/src/scripts/custom_game/common/compact_lottery_model.js"),cfg={};
vm.runInNewContext(fs.readFileSync("panorama/src/scripts/custom_game/common/ui_static_catalog.js","utf8"),{GameUI:{CustomUIConfig:()=>cfg}});
const C=cfg.SurvivalUICatalog,fixture=JSON.parse(cp.execFileSync(process.env.LUA51||"C:/Program Files/lua/bin/lua5.1.exe",["scripts/vscripts/tests/test_compact_lottery_projection.lua","emit"],{encoding:"utf8"}).trim().split(/\r?\n/).at(-1));
function store(){const values={};return {put(ops){const seen=new Set();for(const op of ops){const row=values[op.record]||(values[op.record]={});if(op.remove)delete row[op.field];else row[op.field]=op.value;seen.add(op.record);}return [...seen];},read:(r,f)=>values[r]&&values[r][f]};}
function subset(a,e,label="snapshot"){if(e===null||typeof e!=="object"){assert.equal(a,e,label);return;}assert.ok(a&&typeof a==="object",label);for(const k of Object.keys(e)){if(["reason","version"].includes(k))continue;subset(a[k],e[k],label+"."+k);}}
let tests=0;function test(name,fn){fn();tests++;console.log("ok",name);}
for(const old of fixture.initial_expected)test("real Lua all dynamic/static fields reconstruct "+old.selected_pool_id,()=>{
 const m=api.Create(C,old.selected_pool_id),s=store();let result=m.Apply({full:true,revision:1},s.put(fixture.initial_ops),s.read);assert.equal(result.known,true);subset(result.snapshot,old);
 const original=result.snapshot,items=original.items;result=m.Apply({full:false,revision:2},s.put(fixture.changed_ops),s.read);subset(result.snapshot,fixture.changed_expected.find(x=>x.selected_pool_id===old.selected_pool_id));assert.equal(result.snapshot,original);assert.equal(result.snapshot.items,items);
 const before=m.Inspect().metrics;for(let n=0;n<1000;n++){result=m.Apply({full:false,revision:n+3},[],s.read);assert.equal(result.changes.items.length,0);assert.equal(result.changes.pools.length,0);assert.equal(result.changes.summary,false);}assert.equal(m.Inspect().metrics.record_visits,before.record_visits);
});
test("receipt matches local intent; pregrant receipt ownership stays distinct",()=>{
 const m=api.Create(C,"map"),s=store();m.Apply({full:true,revision:1},s.put(fixture.initial_ops),s.read);m.Apply({full:false,revision:2},s.put(fixture.changed_ops),s.read);m.BindIntent(51,"local_request");
 let result=m.Apply({full:false,revision:3},s.put(fixture.receipt_ops),s.read);assert.equal(result.result.request_id,"local_request");subset(result.result,fixture.receipt_expected);assert.equal(result.result.results[0].owned_count,0);assert.equal(result.snapshot.items.find(x=>x.id===fixture.receipt_expected.results[0].id).owned_count,1);
 result=m.Apply({full:false,revision:4},[],s.read);assert.equal(result.result,null);
});
test("unknown state and unknown receipt item never fabricate valid reward",()=>{
 const m=api.Create(C,"map"),s=store();assert.equal(m.Apply({full:true,revision:1},[],s.read).known,false);
 m.Apply({full:true,revision:2},s.put(fixture.initial_ops),s.read);m.BindIntent(51,"local_request");const bad=fixture.receipt_ops.map(x=>({...x}));bad.find(x=>x.record===m.Record("lottery:result:1")&&x.field===m.Field("target_record")).value=m.Record("daily:state");
 assert.throws(()=>m.Apply({full:false,revision:3},s.put(bad),s.read),/item_unknown/);
});
console.log("compact lottery model",tests,"tests passed; synthetic reconstruction, no native/FPS measurement");
