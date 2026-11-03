"use strict";
const assert=require("node:assert/strict"),fs=require("node:fs"),vm=require("node:vm"),cp=require("node:child_process");
const cfg={};vm.runInNewContext(fs.readFileSync("panorama/src/scripts/custom_game/common/ui_static_catalog.js","utf8"),{GameUI:{CustomUIConfig:()=>cfg}});
const C=cfg.SurvivalUICatalog,api=require("../panorama/src/scripts/custom_game/common/compact_selected_model.js");
const fixture=JSON.parse(cp.execFileSync("C:/Program Files/lua/bin/lua5.1.exe",["scripts/vscripts/tests/test_compact_selected.lua","emit"],{encoding:"utf8"}).trim());
assert.equal(C.Data.sha256,fixture.schema_sha256);
const F=C.FieldIds||Object.fromEntries(C.Data.fields.map(x=>[x.name,x.id])),R=C.ByKey;
function store(){const values={};return{put(ops){const changed=new Set();for(const o of ops){const row=values[o.record]||(values[o.record]={});if(o.remove)delete row[o.field];else row[o.field]=o.value;changed.add(o.record);}return [...changed];},read:(r,f)=>values[r]&&values[r][f]};}
function get(o,path){for(const k of path.split('.')){if(o===undefined||o===null)return undefined;o=o[/^\d+$/.test(k)?Number(k)-1:k];}return o;}
let tests=0;function test(name,fn){fn();tests++;console.log('ok',name);}
test('actual router DTO all selected numeric/text tooltip fields reconstruct exactly',()=>{
 const m=api.Create(C),s=store();m.Select(90,11);m.Apply({full:true},s.put(fixture.initial_ops),s.read);const result=m.Apply({full:false},s.put(fixture.delta_ops),s.read);assert.equal(result.known,true);
 for(const p of fixture.numeric_paths){const raw=fixture.exact_numeric[p],expected=raw===undefined?undefined:Number(raw);assert.equal(get(result.snapshot,p),expected,p);}
 for(const p of fixture.text_paths)assert.equal(get(result.snapshot,p),get(fixture.source,p),p);
 assert.equal(result.snapshot.stat_tooltips.armor.unit,'war3_display');assert.equal(result.snapshot.entindex,90);
 const before=m.Inspect().metric_visits;for(let n=0;n<1000;n++)m.Apply({full:false},[],s.read);assert.equal(m.Inspect().metric_visits,before);
});
test('A-B-A entity equality cannot admit a previous selection generation',()=>{
 const m=api.Create(C),s=store();s.put(fixture.initial_ops);m.Select(91,12);assert.equal(m.Apply({full:true},[],s.read).stale,true);m.Select(90,13);assert.equal(m.Apply({full:true},[],s.read).stale,true);
 s.put([{record:R['selected:state'],field:F.selected_token,value:13}]);assert.equal(m.Apply({full:true},[],s.read).known,true);
});
test('real asset-catalogue wearable metadata survives without model/name strings on wire',()=>{
 const m=api.Create(C),s=store();m.Select(90,22);const result=m.Apply({full:true},s.put(fixture.portrait_fixture.ops),s.read);
 assert.equal(result.known,true);for(const path of fixture.text_paths)assert.equal(get(result.snapshot,path),get(fixture.portrait_fixture.source,path),path);
 assert.ok(result.snapshot.model_asset_id);assert.ok(result.snapshot.portrait_model_name);
});
test('critical first paint has true zero versus unknown; auxiliary transaction completes tooltips',()=>{
 const m=api.Create(C),s=store();m.Select(90,11);let result=m.Apply({full:true},s.put(fixture.critical_ops),s.read);
 assert.equal(result.known,true);assert.equal(result.snapshot._selected_aux_pending,true);assert.equal(result.snapshot.mana,0);assert.equal(result.snapshot.entindex,90);
 assert.equal(result.snapshot.stat_tooltips.armor.physical_reduction_pct,undefined);
 result=m.Apply({full:false},s.put(fixture.auxiliary_ops),s.read);assert.equal(result.snapshot._selected_aux_pending,false);
 assert.equal(result.snapshot.stat_tooltips.armor.physical_reduction_pct,Number(fixture.exact_numeric['stat_tooltips.armor.physical_reduction_pct']));
 const r=R['selected:metric:mana'];s.put([{record:r,field:F.selected_value_int,value:0}]);assert.throws(()=>m.Apply({full:false},[r],s.read),/representation_conflict/);
});
test('integer, float, positive zero, unknown, large integer and negative zero transition atomically',()=>{
 const m=api.Create(C),s=store();m.Select(90,11);m.Apply({full:true},s.put(fixture.initial_ops),s.read);
 for(const item of fixture.transitions){const result=m.Apply({full:false},s.put(item.ops),s.read);assert.equal(result.snapshot.mana,item.expected==='unknown'?undefined:Number(item.expected),item.expected);}
});
test('unknown static text refuses before changing a previous model',()=>{
 const m=api.Create(C),s=store();m.Select(90,11);const old=m.Apply({full:true},s.put(fixture.initial_ops),s.read).snapshot;
 const record=R['selected:metric:display_name'],field=F.target_record,oldId=s.read(record,field);s.put([{record,field,value:R['daily:state']}]);assert.throws(()=>m.Apply({full:false},[record],s.read),/text_unknown/);assert.equal(old.display_name,get(fixture.source,'display_name'));
 s.put([{record,field,value:oldId}]);assert.equal(m.Apply({full:false},[record],s.read).snapshot,old);
});
test('genuinely unknown resource marks only that field; verified combat values remain',()=>{
 const m=api.Create(C),s=store();m.Select(90,11);m.Apply({full:true},s.put(fixture.initial_ops),s.read);m.Apply({full:false},s.put(fixture.delta_ops),s.read);
 const result=m.Apply({full:false},s.put(fixture.unknown_resource_ops),s.read);assert.equal(result.known,true);assert.equal(result.snapshot.attack_min,Number(fixture.exact_numeric.attack_min));
 assert.equal(result.snapshot.portrait_model_name,'');assert.equal(result.snapshot._selected_unknown_fields.portrait_model_name,true);
});
test('actual cold controller coalesces pre-Hello ABA to one ready request and invalidates disposed callbacks',()=>{
 const source=fs.readFileSync('panorama/src/scripts/custom_game/combat_stats.js','utf8');
 const start=source.indexOf('    function requestSelectedUnitStats('),end=source.indexOf('    function refreshHeroVitals(',start);
 assert.ok(start>=0&&end>start);let callback,ready=false,active=true,unit=90,updates=0,refreshes=0,opens=0;const inputs=[];
 const env={customConfig:{SurvivalUICatalog:C,SurvivalCompactSelectedModel:api,SurvivalCompactRuntime:{CreateView(key,o){assert.equal(key,'selected');callback=o.onCommit;return{Open(){opens++;},Dispose(){active=false;},SendInput(action,args){assert.equal(active,true);if(!ready)return{sent:false,error:'not_ready'};inputs.push({action,args});return{sent:true};}};}}},
  compactSelectedView:null,compactSelectedModel:null,compactSelectedToken:0,lastRequestedUnit:-1,$:{Msg(){}},GameEvents:{SendCustomGameEventToServer(){throw Error('legacy selected send');}},
  contextActive:()=>active,displayUnit:()=>unit,update(s){assert.equal(s.entindex,unit);updates++;},refreshHeroPanel(){refreshes++;}};
 vm.createContext(env);vm.runInContext(source.slice(start,end),env);
 env.requestSelectedUnitStats(90,false);assert.equal(inputs.length,0);assert.equal(env.compactSelectedToken,0);
 unit=91;env.requestSelectedUnitStats(91,false);unit=90;env.requestSelectedUnitStats(90,false);
 assert.equal(inputs.length,0);assert.equal(updates,0);assert.equal(opens,1);assert.equal(env.lastRequestedUnit,-1);
 ready=true;const boot=store();boot.put([{record:R['selected:state'],field:F.known,value:0},{record:R['selected:state'],field:F.selected_entity,value:0},{record:R['selected:state'],field:F.selected_token,value:1}]);callback({full:true},[R['selected:state']],boot.read);
 assert.equal(inputs.length,1);assert.equal(inputs[0].args.selected_entity,90);assert.equal(inputs[0].args.selected_token,1);
 callback({full:true},[R['selected:state']],boot.read);assert.equal(inputs.length,1,'duplicate bootstrap refetched selection');assert.equal(updates,0,'bootstrap displayed an old unit');
 unit=91;env.requestSelectedUnitStats(91,false);unit=90;env.requestSelectedUnitStats(90,false);assert.equal(inputs.length,3);
 const s=store();s.put(fixture.initial_ops);callback({full:true},[],s.read);assert.equal(updates,0,'old A reply crossed A-B-A token');
 s.put([{record:R['selected:state'],field:F.selected_token,value:3}]);callback({full:true},[],s.read);assert.equal(updates,1);assert.equal(refreshes,1);
 env.requestSelectedUnitStats(90,false);assert.equal(inputs.length,3);env.requestSelectedUnitStats(90,true);assert.equal(inputs.length,4);assert.equal(inputs[3].args.selected_token,4);
 env.compactSelectedView.Dispose();unit=91;callback({full:true},[],s.read);env.requestSelectedUnitStats(91,true);
 assert.equal(inputs.length,4);assert.equal(updates,1);assert.equal(opens,1);
 const shutdown=source.slice(source.indexOf('    function shutdownCombatContext('));assert.ok(shutdown.indexOf('contextShutdown = true;')<shutdown.indexOf('compactSelectedView.Dispose()'),'Dispose can reenter a live old context');
});
console.log(JSON.stringify({status:'PASS_REAL_SELECTED_DTO_SYNTHETIC_NOT_NATIVE',tests,native_calls:0,transactions:0}));
