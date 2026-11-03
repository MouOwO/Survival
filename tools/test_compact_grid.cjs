"use strict";
const fs=require("node:fs"),vm=require("node:vm"),cp=require("node:child_process"),assert=require("node:assert/strict");
const API=require("../panorama/src/scripts/custom_game/common/compact_grid_model.js");
const W=require("../panorama/src/scripts/custom_game/common/compact_wire.js");
const cfg={};vm.runInNewContext(fs.readFileSync("panorama/src/scripts/custom_game/common/ui_static_catalog.js","utf8"),{GameUI:{CustomUIConfig:()=>cfg}});
const C=cfg.SurvivalUICatalog,F=C.FieldIds,R=C.ByKey;
const fixture=JSON.parse(cp.execFileSync("C:/Program Files/lua/bin/lua5.1.exe",["scripts/vscripts/tests/test_compact_grid_projection.lua","emit"],{encoding:"utf8"}));
assert.equal(fixture.schema_sha256,C.Data.sha256);
let tests=0;function test(name,fn){fn();tests++;console.log("ok",name);}
function feed(model){const values=new Map();return function(ops,full=false){const ids=new Set();for(const op of ops){const key=op.record+":"+op.field;if(op.remove)values.delete(key);else values.set(key,op.value);ids.add(op.record);}return model.Apply({full},[...ids],(id,f)=>values.get(id+":"+f));};}
test("real Lua full/delta reconstruct exact legacy geometry and authority result",()=>{
 const model=API.Create(C),apply=feed(model),first=apply(fixture.initial_ops,true);assert.equal(first.profiles.profiles,C.Data.auxiliary.grid.profiles);
 assert.equal(first.validation.world_z,384);assert.equal(first.validation.cells.length,fixture.expected.cells.length);assert.equal(first.validation.success,1);
 const changed=apply(fixture.delta_ops),expected=fixture.expected;
 for(const name of ["session_id","request_id","ability_name","building_id","world_x","world_y","world_z","anchor_x","anchor_y","request_anchor_x","request_anchor_y","success","error"])assert.equal(changed.validation[name],expected[name],name);
 assert.deepEqual(JSON.parse(JSON.stringify(changed.validation.cells)),expected.cells);
 assert.ok(fixture.metrics.max_native_bytes<=49);assert.equal(fixture.metrics.delta_packets,1);
});
test("stable transactions read zero fields and one area word touches at most16 cells",()=>{
 const model=API.Create(C),apply=feed(model);apply(fixture.initial_ops,true);const before={...model.Inspect().metrics};
 for(let n=0;n<1000;n++)apply([]);assert.deepEqual(model.Inspect().metrics,before);
 const changed=apply(fixture.area_ops);assert.equal(model.Inspect().metrics.word_visits,before.word_visits+1);assert.ok(changed.area.changes.length<=16);assert.equal(model.Inspect().metrics.container_rebuilds,before.container_rebuilds);
});
test("native-derived candidate stays unknown until live confirmation; K0 reads zero word records",()=>{
 const model=API.Create(C),apply=feed(model);assert.deepEqual(Object.keys(apply([])),[]);
 const before=model.Inspect().metrics.word_visits,first=apply(fixture.static_initial_ops,true),candidate=C.Data.auxiliary.grid.atlases[0];
 assert.equal(first.static.base,1);assert.equal(first.static.w,96);assert.equal(first.static.h,96);assert.equal(model.Inspect().metrics.word_visits,before);
 const bits=candidate.area.split("|")[7];for(let n=0;n<96*96;n++)assert.equal(first.static.states[n],(parseInt(bits[Math.floor(n/2)],16)>>>((n%2)*2))&3);
 assert.ok(fixture.metrics.static_k0_bytes<fixture.metrics.static_legacy_area_bytes/10);assert.equal(fixture.metrics.static_live_words,576);
 const changed=apply(fixture.static_delta_ops);assert.equal(changed.static.changes.length,1);assert.equal(model.Inspect().metrics.word_visits,before+1);
 const zero=apply(fixture.static_zero_ops);assert.ok(zero.static.states.slice(0,16).every(n=>n===0),"explicit zero must override a nonzero candidate word");
});
test("mode scope replacement retires the ordinary atlas and rejects its late word updates",()=>{
 const model=API.Create(C),apply=feed(model);apply(fixture.static_initial_ops,true);
 const layout=fixture.initial_ops.filter(op=>op.record===R["grid:state"]||C.ById[op.record].key.startsWith("grid:layout:"));
 const changed=layout.map(op=>op.record===R["grid:state"]&&op.field===F.grid_scope?{...op,value:2}:op);
 const result=apply(changed,true);assert.equal(result.static,undefined);assert.equal(model.Inspect().scope,2);
 const stale=apply(fixture.static_delta_ops);assert.equal(stale.static,undefined);assert.equal(model.Inspect().scope,2);
});
test("same catalogue shares all capacity indexes across controller/model lifetimes",()=>{
 const isolated={module:{exports:{}}};vm.runInNewContext(fs.readFileSync("panorama/src/scripts/custom_game/common/compact_grid_model.js","utf8"),isolated);
 let reads=0;const records=new Proxy(C.ByKey,{get(object,key){reads++;return object[key];}}),catalogue={Data:C.Data,ByKey:records,FieldIds:C.FieldIds};
 isolated.module.exports.Create(catalogue);assert.ok(reads>4352);reads=0;for(let n=0;n<100;n++)isolated.module.exports.Create(catalogue);assert.ok(reads<=500,"reopens must not visit the 4352 word capacity again");
});
test("four owners share immutable indexes while native atlas overrides remain isolated",()=>{
 const models=Array.from({length:4},()=>API.Create(C)),feeds=models.map(feed),atlases=feeds.map(apply=>apply(fixture.static_initial_ops,true).static);
 const before=atlases[0].states[0];assert.notEqual(atlases[0].states,atlases[1].states);
 feeds[2](fixture.static_delta_ops);assert.notEqual(atlases[2].states[0],before);
 for(const n of [0,1,3])assert.equal(atlases[n].states[0],before);
});
test("input retains full IEEE754 values and independent uint32 preview counters",()=>{
 const model=API.Create(C),input=model.Input(1,{session_id:999999,request_id:2000000,ability_name:"ability_build_arrow_tower",entindex:123,ability_entindex:456,x:-0,y:Math.PI,z:384.125});
 assert.equal(input.grid_request,2000000);assert.equal(input.grid_profile,R["grid:profile:ability_build_arrow_tower"]);assert.equal(input.request_token,undefined);
 for(const [axis,want]of [["x",-0],["y",Math.PI],["z",384.125]]){const buffer=new ArrayBuffer(8),data=new DataView(buffer);data.setUint32(0,input["grid_"+axis+"_hi"]);data.setUint32(4,input["grid_"+axis+"_lo"]);assert.ok(Object.is(data.getFloat64(0),want));}
 const normal=model.Input(2,{session_id:999999,request_id:2000000,ability_name:"ability_build_arrow_tower",entindex:123,ability_entindex:456,x:128,y:-256,z:384});normal.grid_action=2;
 const ops=Object.keys(normal).map(name=>({record:R["grid:input"],field:F[name],value:normal[name]}));
 const encoded=W.Encode(W.CompileLookup(C.Data,1),{schema:1,schema_sha256:C.Data.sha256,session:900,epoch:1,view:4},10000,ops,{full:true,value_budget:24});
 fixture.metrics.input_packets=encoded.packets.length;fixture.metrics.input_calibrated_bytes=encoded.packets.reduce((sum,p)=>sum+25+p.d.length,0);assert(encoded.packets.every(p=>p.d.length+25<=49));
});
test("area spatial-index patches visit affected columns rather than a whole atlas",()=>{
 const shared={};vm.runInNewContext(fs.readFileSync("panorama/src/scripts/custom_game/survival_grid_state.js","utf8"),{GameUI:{CustomUIConfig:()=>shared}});
 const api=shared.SurvivalGridState,source={size:64,x:0,y:0,w:49,h:49,z:384,states:new Array(49*49).fill(0)};
 let index=api.patchColumns(source,null,[]);const visits=index.visits;source.states[17]=1;index=api.patchColumns(source,index,[17]);assert.equal(index.visits-visits,50);assert.equal(Object.keys(index.columns).length,49);
 const unchanged=index.visits;api.patchColumns(source,index,[]);assert.equal(index.visits,unchanged);
});
test("actual loaded controller opens two views and emits no legacy grid event",()=>{
 const legacy=fs.readFileSync("tools/test_grid_placement_client.cjs","utf8"),at=legacy.indexOf("vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/survival_grid_placement.js'");assert.ok(at>0);
 const prefix=legacy.slice(0,at),source=fs.readFileSync("panorama/src/scripts/custom_game/survival_grid_placement.js","utf8");
 const body=`
const catalogueConfig={};vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/common/ui_static_catalog.js','utf8'),{GameUI:{CustomUIConfig:()=>catalogueConfig}});
shared.SurvivalUICatalog=catalogueConfig.SurvivalUICatalog;shared.SurvivalCompactGridModel=require('../panorama/src/scripts/custom_game/common/compact_grid_model.js');
const views={},inputs=[];shared.SurvivalCompactRuntime={CreateView(key,options){const v={options,opened:0,Open(){v.opened++;return {sent:true};},Dispose(){},SendInput(code,args){inputs.push({code,args});return {sent:true};}};views[key]=v;return v;}};
vm.runInNewContext(${JSON.stringify(source)},{ $,Particles,ParticleAttachment_t:{PATTACH_WORLDORIGIN:6},Game:{GetGameTime:()=>now,WorldToScreenX:x=>x+1000,WorldToScreenY:(_,y)=>y+1000},GameUI:{CustomUIConfig:()=>shared,GetCursorPosition:()=>[500,500],GetScreenWorldPosition:()=>world},GameEvents:{Subscribe:(name,fn)=>listeners[name]=fn,SendCustomGameEventToServer:(name,data)=>sent.push({name,data}),SendEventClientSide(){}},Abilities:{GetLocalPlayerActiveAbility:()=>-1,GetAbilityName:()=>'',GetCooldownTimeRemaining:()=>0},Entities:{GetUnitName:()=> 'builder'},CustomNetTables:{GetTableValue:()=>null}});
assert(views.grid&&views.grid_static);assert.equal(sent.length,0);assert.equal(Object.keys(listeners).filter(n=>n.startsWith('ui_grid_')).length,0);
const values=new Map(),ops=${JSON.stringify(fixture.initial_ops)};for(const op of ops)values.set(op.record+':'+op.field,op.value);
views.grid.options.onCommit({full:true},[...new Set(ops.map(o=>o.record))],(id,f)=>values.get(id+':'+f));
shared.SurvivalPointTargetState.name='ability_build_arrow_tower';const update=scheduled.find(fn=>fn.name==='updateLoop');update();
assert.equal(sent.length,0);assert(inputs.some(i=>i.code===1));assert(inputs.every(i=>i.args.request_token===undefined));
`;
 new Function("require",prefix+body)(require);
});
console.log(JSON.stringify({status:"PASS_COMPACT_GRID_SYNTHETIC_NOT_NATIVE",tests,metrics:fixture.metrics,native_calls:0,transactions:0}));
