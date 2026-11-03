"use strict";
const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),cp=require('node:child_process');
const fixture=JSON.parse(cp.execFileSync('C:/Program Files/lua/bin/lua5.1.exe',['scripts/vscripts/tests/test_compact_grid_bulk.lua','emit'],{encoding:'utf8'}).trim());
const config={};vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/common/ui_static_catalog.js','utf8'),{GameUI:{CustomUIConfig:()=>config}});
const C=config.SurvivalUICatalog,W=require('../panorama/src/scripts/custom_game/common/compact_wire.js'),B=require('../panorama/src/scripts/custom_game/common/compact_grid_bulk_wire.js'),M=require('../panorama/src/scripts/custom_game/common/compact_grid_model.js');
assert.equal(C.Data.sha256,fixture.schema_sha256);const F=C.FieldIds,R=C.ByKey,schema=W.CompileLookup(C,1);
function rig(metadata=fixture.metadata){const model=M.Create(C),outputs=[];const client=W.NewClient(schema,fixture.binding,{onCommit(tx,ids,read){outputs.push(model.Apply(tx,ids,read));}});function put(ops,rev,full=false){for(const p of W.Encode(schema,fixture.binding,rev,ops,{full}).packets){const result=client.Accept(p);assert(!result.error,result.error);}return outputs.at(-1);}put(metadata,1,true);return{model,client,outputs,put,read:client.Read};}
function body(){const receiver=B.NewReceiver(fixture.binding,{scope:1});let value;for(const packet of [...fixture.packets].reverse())value=receiver.Accept(packet);assert(value.raw);return value;}
function expected(){return Array.from({length:fixture.raw_hex.length*2},(_,n)=>(parseInt(fixture.raw_hex.charAt(Math.floor(n/2)),16)>>>((n%2)*2))&3);}
let tests=0;function test(name,fn){fn();tests++;console.log('ok',name);}
test('actual authoritative area becomes four private bitmap frames and a bounded local decode',()=>{
 const r=rig(),value=body();assert.equal(r.outputs[0].static.empty_initial,true);assert.equal(r.outputs[0].static.complete,false);assert.equal(r.model.AcceptBulk(value.header),true);
 let time=0,applies=0;const task=r.model.BeginBulk(value.header,value.raw,r.read,{now:()=>time,apply(atlas){applies++;assert(atlas.changes.length<=16);time+=.03;}});
 let result;for(let n=0;n<1000;n++){result=task.Step();if(result.done)break;assert(n<999);}assert(result.done);const stats=task.Inspect();assert(stats.max_step_cells<=512);assert(stats.max_step_ms<=2.1);assert(applies>0);assert.deepEqual(Array.from(r.outputs[0].static.states),expected());assert.equal(r.outputs[0].static.complete,false);
 r.put(fixture.complete,2);assert.equal(r.outputs.at(-1).static.complete,true);assert.equal(task.Step().done,true);
});
test('real cw receiver observes explicit0 before bulk and the late base never overwrites current deltas',()=>{
 const r=rig(),value=body();const before=r.model.Inspect().metrics.word_visits;r.put(fixture.zero,2);assert(r.model.Inspect().metrics.word_visits>before,'explicit0 changes an absent cw field and reaches the indexed model');
 r.put(fixture.complete,3);const task=r.model.BeginBulk(value.header,value.raw,r.read);for(let n=0;n<1000&&!task.Step().done;n++)assert(n<999);
 const values=expected();values.fill(0,0,16);assert.deepEqual(Array.from(r.outputs[0].static.states),values);assert.equal(r.outputs[0].static.complete,true);
 const b=r.model.Inspect().metrics.word_visits;for(let n=0;n<1000;n++)r.model.Apply({full:false,revision:3},[],r.read);assert.equal(r.model.Inspect().metrics.word_visits,b,'stable traffic does not rescan bitmap or capacity');
});
test('scope/full replacement cancels local work and malformed states never paint a partial unverified bitmap',()=>{
 const r=rig(),value=body();let applied=0;const bad=String.fromCharCode(255)+value.raw.slice(1),task=r.model.BeginBulk(value.header,bad,r.read,{apply(){applied++;}});assert.throws(()=>task.Step(),/cell_state_invalid/);assert.equal(applied,0);
 assert.throws(()=>r.model.BeginBulk(value.header,value.raw.slice(1),r.read),/byte_length/);assert.equal(r.model.AcceptBulk({...value.header,scope:2}),false);
 const old=r.model.BeginBulk(value.header,value.raw,r.read);old.Step();const meta=fixture.metadata.map(op=>op.field===F.grid_scope?{...op,value:2}:op);
 // A full view has a new receiver/epoch in production. Apply its metadata to
 // prove the model independently invalidates its pending local callback.
 const replacement=rig(meta);const fresh=r.model.Apply({full:true,revision:1},[R['grid:static:meta']],replacement.read);assert.equal(fresh.static_reset,true,'new full retires indexes that were filtered by the previous static bitmap');assert.equal(old.Current(),false);assert.equal(old.Step().cancelled,true);
});
test('maximum skinny bitmap remains <=512 cells per temporary batch and isolates each owner',()=>{
 const metadata=fixture.metadata.map(op=>op.field===F.grid_width?{...op,value:1}:op.field===F.grid_height?{...op,value:65536}:op),r=rig(metadata),value=body(),other=rig();
 const task=r.model.BeginBulk(value.header,String.fromCharCode(85).repeat(16384),r.read);let result;
 for(let n=0;n<1000;n++){result=task.Step();if(result.done)break;assert(n<999);}assert(result.done);assert(task.Inspect().max_step_cells<=512);assert.equal(r.outputs[0].static.states.length,65536);assert.equal(other.outputs[0].static.states[0],0);
});
test('actual grid controller owns finite local work, rejects a replaced loading world and sends no legacy snapshot',()=>{
 const legacy=fs.readFileSync('tools/test_grid_placement_client.cjs','utf8'),at=legacy.indexOf("vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/survival_grid_placement.js'");assert(at>0);
 const prefix=legacy.slice(0,at),source=fs.readFileSync('panorama/src/scripts/custom_game/survival_grid_placement.js','utf8');
 const body=`
const catalogueConfig={};vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/common/ui_static_catalog.js','utf8'),{GameUI:{CustomUIConfig:()=>catalogueConfig}});
shared.SurvivalUICatalog=catalogueConfig.SurvivalUICatalog;shared.SurvivalCompactGridModel=require('../panorama/src/scripts/custom_game/common/compact_grid_model.js');
const bulkCodec=require('../panorama/src/scripts/custom_game/common/compact_grid_bulk_wire.js'),values=new Map(),views={},owner={active:true,ready:true,loading_identity:'grid_bulk_owner_A',session:7};
shared.SurvivalCompactRuntime={ScopeIdentity:()=>owner,CreateView(key,options){const v={options,active:true,Open(){return{sent:true};},Dispose(){v.active=false;},Read:(r,f)=>values.get(r+':'+f),Inspect:()=>({active:v.active,epoch:1}),SendInput(){return{sent:true};},Resync(){throw new Error('unexpected valid bulk resync');}};views[key]=v;return v;}};
vm.runInNewContext(${JSON.stringify(source)},{ $,Particles,ParticleAttachment_t:{PATTACH_WORLDORIGIN:6},Game:{GetGameTime:()=>now,WorldToScreenX:x=>x+1000,WorldToScreenY:(_,y)=>y+1000},GameUI:{CustomUIConfig:()=>shared,GetCursorPosition:()=>[500,500],GetScreenWorldPosition:()=>world},GameEvents:{Subscribe:(n,f)=>listeners[n]=f,SendCustomGameEventToServer:(...a)=>sent.push(a),SendEventClientSide(){}},Abilities:{GetLocalPlayerActiveAbility:()=>-1,GetAbilityName:()=>'',GetCooldownTimeRemaining:()=>0},Entities:{GetUnitName:()=> 'builder'},CustomNetTables:{GetTableValue:()=>null}});
const ops=${JSON.stringify(fixture.metadata)},binding=${JSON.stringify(fixture.binding)};for(const op of ops)values.set(op.record+':'+op.field,op.value);
views.grid_static.options.onCommit({full:true,revision:1},[...new Set(ops.map(o=>o.record))],views.grid_static.Read);
const receiver=bulkCodec.NewReceiver(binding,{scope:1});let completed;for(const packet of ${JSON.stringify(fixture.packets)})completed=receiver.Accept(packet);
assert(views.grid_static.options.acceptBulk(completed.header));views.grid_static.options.onBulk(completed.header,completed.raw);
for(let n=0;n<1000;n++){const index=scheduled.findIndex(fn=>fn.name==='step');if(index<0)break;scheduled.splice(index,1)[0]();assert(n<999);}
assert(shared.SurvivalGridBulkPerformance.steps>1);assert(shared.SurvivalGridBulkPerformance.max_step_cells<=512);assert.equal(sent.length,0);
views.grid_static.options.onBulk(completed.header,completed.raw);owner.loading_identity='grid_bulk_owner_B';const pending=scheduled.findIndex(fn=>fn.name==='step');assert(pending>=0);scheduled.splice(pending,1)[0]();assert(shared.SurvivalGridBulkPerformance.cancelled>0);
shared.SurvivalGridUnsubscribe();assert.equal(sent.length,0);
`;
 new Function('require',prefix+body)(require);
});
console.log(JSON.stringify({status:'PASS_GRID_BULK_MODEL_SYNTHETIC_NOT_NATIVE',tests,metrics:fixture.metrics}));
