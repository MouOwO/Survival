'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),cp=require('node:child_process');
// Run from the repository root; optional argv[2] selects an explicit source checkout.
// All runtime modules below come from that checkout. Child Lua emits into memory
// only: no generated fixture files, native client, HTTP or running-world writes.
const ROOT=path.resolve(process.argv[2]||process.cwd());process.chdir(ROOT);
const LUA=process.env.LUA||'C:/Program Files/lua/bin/lua5.1.exe';
const LUA_TEST=path.join(__dirname,'test_compact_research_prepared.lua');
function runLua(file,args=[]){return JSON.parse(cp.execFileSync(LUA,[file,...args],{cwd:ROOT,encoding:'utf8',timeout:30000,maxBuffer:16*1024*1024}));}
const W=require(path.join(ROOT,'panorama/src/scripts/custom_game/common/compact_wire.js'));
const M=require(path.join(ROOT,'panorama/src/scripts/custom_game/common/compact_production_model.js'));
const API=require(path.join(ROOT,'panorama/src/scripts/custom_game/common/compact_ui_runtime.js')),PREP=require(path.join(ROOT,'panorama/src/scripts/custom_game/common/compact_research_prepared.js'));
const cfg={};vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/common/ui_static_catalog.js','utf8'),{GameUI:{CustomUIConfig:()=>cfg}});
const C=cfg.SurvivalUICatalog.Data,SCHEMA=W.CompileLookup(C,1),F=Object.fromEntries(C.fields.map(r=>[r.name,r.id])),R=Object.fromEntries(C.records.filter(r=>!r.tombstone).map(r=>[r.key,r.id]));
assert.ok(C.auxiliary.production,'committed production catalog required; no experimental fallback');
const fixture=runLua('scripts/vscripts/tests/test_compact_production.lua',['emit']);
const serverCases=[1,2,4].map(n=>runLua(LUA_TEST,[String(n),ROOT]));
let checks=0;function check(value,label){assert.ok(value,label);checks++;}
function encode(ops,view,epoch=1,revision=1,session=900,full=true){return W.Encode(SCHEMA,{schema:1,schema_sha256:C.sha256,session,view,epoch},revision,ops,{full}).packets;}
function hello(session=900){return encode(Array.from({length:8},(_,i)=>({record:R['wire:hello:'+(i+1)],field:F.count,value:parseInt(C.sha256.slice(i*8,i*8+8),16)})),1,1,1,session);}
function hintOps(known,entity,selection){return [{record:R['production:state'],field:F.known,value:known?1:0},{record:R['production:state'],field:F.production_entity,value:entity},{record:R['production:state'],field:F.production_selection,value:selection}];}
const advancedRecords=new Set(C.auxiliary.production.research.filter(r=>r.mapping.building_id==="building_advanced_research_lab").map(r=>R["production:research:"+r.group]));
function researchOps(entity,selection,extra=[]){const base=fixture.research_ops.filter(op=>op.record===R['production:state']?[F.known,F.production_entity,F.production_selection].includes(op.field):advancedRecords.has(op.record)&&[F.level,F.production_flags].includes(op.field)).map(op=>op.field===F.production_flags?{...op,value:Math.floor(op.value/2)%2*2}:op).map(op=>op.record===R['production:state']&&op.field===F.production_entity?{...op,value:entity}:op.record===R['production:state']&&op.field===F.production_selection?{...op,value:selection}:{...op});
 for(const op of extra){const index=base.findIndex(v=>v.record===op.record&&v.field===op.field);if(index>=0)base[index]=op;else base.push(op);}return base;}
function harness(viewer=0,createPrepared=true){
 const h={viewer,sent:[],timers:[],changes:[],loading:{admission_complete:1,profiles_ready:1,session_id:'prepared_world_A'}};let listener,loadingListener;
 h.runtime=API.CreateRuntime({wire:W,catalogue:C,send(name,p){check(name==='cw'&&p.d.length<=24,'all real codec controls <=49 calibrated native bytes');h.sent.push(p);return true;},
  subscribe(name,fn){listener=fn;return 1;},unsubscribe(){},getLoading:()=>h.loading,subscribeLoading(fn){loadingListener=fn;return 2;},unsubscribeLoading(){},now:()=>0,
  schedule(ms,fn){const t={ms,fn,canceled:false};h.timers.push(t);return t;},cancel(t){t.canceled=true;}});
 if(createPrepared)h.prep=PREP.Create({runtime:h.runtime,model:M,catalogue:cfg.SurvivalUICatalog,viewerId:()=>h.viewer,onChanged:entity=>h.changes.push(entity)});
 h.feed=packets=>packets.forEach(p=>{check(p.d.length<=24,'all real codec server packets <=49 calibrated native bytes');listener(p);});
 h.hello=(session=900)=>h.feed(hello(session));h.hint=(slot,known,entity,sequence,epoch=1,session=900)=>h.feed(encode(hintOps(known,entity,sequence),11+slot,epoch,1,session));
 h.full=(slot,entity,sequence,epoch=2,extra=[],session=900)=>h.feed(encode(researchOps(entity,sequence,extra),11+slot,epoch,1,session));
 h.world=(identity)=>{h.loading={admission_complete:1,profiles_ready:1,session_id:identity};loadingListener();};return h;
}
const ability=Object.keys(fixture.research_expected.research.abilities_by_name)[0];

{
 const h=harness();h.hello();const count=h.sent.length;
 check(h.prep.Inspect().slots.length===3,'only the three foreign-owner slots exist');
 check(h.prep.Inspect().slots.map(s=>s.view).join(',')==='13,14,15','no own view12 or basic view11');
 check(!h.sent.some(p=>[11,12].includes(W.PeekHeader(p).view)),'no own prepared controls');
 for(let n=0;n<1000;n++)check(h.prep.GetPrerequisite(30,ability)===null,'unknown remains absent');
 check(h.sent.length===count,'stable unknown reads do not resend probes');
 h.hint(2,true,30,1);check(h.prep.GetPrerequisite(30,ability)===null,'hint not treated as a full prerequisite row');
 h.full(2,30,1);const row=h.prep.GetPrerequisite(30,ability),expected=fixture.research_expected.research.abilities_by_name[ability];
 check(row.current_level===expected.current_level&&row.prerequisite_met===expected.prerequisite_met,'actual authoritative level and prerequisite reconstructed');
 check(Object.keys(row).sort().join(',')==='_prepared_partial,current_level,prerequisite_met,research_prerequisite_known','partial cannot impersonate cost/auto/availability/queue model');
 check(!('GetResearchRuntime' in h.prep),'no misleading full-runtime API');
 const display=h.prep.DisplaySnapshot(30);check(display.partial&&Object.keys(display.research).join(',')==='abilities_by_name','display has no queue or job handles');
 const sent=h.sent.length,timers=h.timers.length,changed=h.changes.length;
 for(let n=0;n<1000;n++)h.prep.GetPrerequisite(30,ability);
 check(h.sent.length===sent&&h.timers.length===timers&&h.changes.length===changed,'1000 known reads add no sends/timers/updates');
 h.feed(encode(hintOps(false,0,2),13,3));check(h.prep.GetPrerequisite(30,ability)===null,'destroy removes partial display');
 h.hint(2,true,30,3,4);h.full(2,30,3,5);check(!!h.prep.GetPrerequisite(30,ability),'ABA requires fresh slot generation');
 const prior=h.changes.length;h.full(2,30,1,6);check(h.changes.length===prior,'late old slot generation rejected despite higher packet epoch');
 h.prep.Dispose();h.full(2,30,3,7);check(h.prep.GetPrerequisite(30,ability)===null,'disposed callbacks cannot resurrect cache');
}
{
 const h=harness();h.hello();const n=h.sent.length;
 h.feed(encode([{record:R['production:state'],field:F.known,value:1},{record:R['production:state'],field:F.production_entity,value:30},{record:R['production:state'],field:F.production_kind,value:2}],13));
 check(h.sent.length===n,'closed hint rejects unknown third field');h.feed(encode(hintOps(false,30,1),13,2));check(h.sent.length===n,'inconsistent empty hint does not open');
 h.hint(2,true,30,1,3);
 const def=C.auxiliary.production.research.find(r=>r.ability_name===ability),record=R['production:research:'+def.group];
 h.full(2,30,1,4,[{record,field:F.production_flags,value:3}]);check(h.prep.GetPrerequisite(30,ability)===null,'available bit cannot leak into prerequisite-only flags');
 h.full(2,30,1,5);check(!!h.prep.GetPrerequisite(30,ability),'valid same identity recovers after rejected full');
 h.full(2,30,1,6,[{record,field:F.wood,value:123}]);check(h.prep.GetPrerequisite(30,ability)===null,'cost field forbidden in slim model');
}
{
 const a=harness(0),b=harness(1);a.hello();b.hello();a.hint(3,true,30,1);b.hint(3,true,30,1);
 const def=C.auxiliary.production.research.find(r=>r.ability_name===ability),record=R['production:research:'+def.group];
 a.full(3,30,1,2,[{record,field:F.production_flags,value:0}]);b.full(3,30,1,2,[{record,field:F.production_flags,value:2}]);
 check(a.prep.GetPrerequisite(30,ability).prerequisite_met===0&&b.prep.GetPrerequisite(30,ability).prerequisite_met===1,'shared building has separate current-viewer prerequisites');
 a.viewer=1;check(a.prep.GetPrerequisite(30,ability)===null,'viewer switch immediately clears previous account');
 const sent=a.sent.length;a.hint(3,true,30,2,3);check(a.sent.length===sent,'old runtime cannot reopen after viewer switch');
 b.world('prepared_world_B');check(b.prep.GetPrerequisite(30,ability)===null,'world reset clears private flags');b.hello(901);b.hint(3,true,30,1,1,901);b.full(3,30,1,2,[],901);
 const changed=b.changes.length;b.full(3,30,2,4,[],900);check(b.changes.length===changed,'old-session full rejected');
}
{
 const h=harness();h.hello();assert.throws(()=>h.runtime.CreateView('research_prepared:0',{}),/compact_view_key_unknown/);
 const v=h.runtime.CreateView('research_prepared:4',{});v.Open();
 check(v.SendInput(1,{production_entity:30,production_selection:1}).error==='input_view_mismatch','prepared typed input forbidden');
 for(const action of ['production_train','production_research','production_auto','production_cancel'])check(v.SendIntent(action,{entity:30,selection:1,definition_record:1,job_handle:1}).error==='action_view_mismatch','prepared action forbidden');
}
{
 const h=harness(0,false),nodes={},events={},native=[];let unit=30,owner=1;
 function panel(type,parent,id){const p={id,style:{},children:[],IsValid:()=>true,FindChildTraverse:k=>nodes[k],AddClass(){},SetHasClass(){},RemoveAndDeleteChildren(){this.children=[];},SetPanelEvent(k,v){this[k]=v;},SetImage(){}};if(parent)parent.children.push(p);if(id)nodes[id]=p;return p;}
 const ctx=panel('Panel',null,'ctx');panel('Panel',ctx,'SurvivalProductionPanel');panel('Panel',ctx,'SurvivalResearchAutoMarkers');
 const local={SurvivalUICatalog:cfg.SurvivalUICatalog,SurvivalCompactProductionModel:M,SurvivalPreparedResearchModel:PREP,
  SurvivalCompactRuntime:h.runtime,SurvivalSelectionResolver:{ResolveDisplayUnit:()=>unit},SurvivalUILayers:{Top:()=>false}};
 const original={...fixture.research_expected.research.abilities_by_name[ability],ability_name:ability,owner_entindex:30,ability_entindex:300,prerequisite_met:1,available:1};
 const $=()=>{};$.GetContextPanel=()=>ctx;$.CreatePanel=panel;$.DispatchEvent=()=>{};$.Schedule=()=>{};$.Msg=()=>{};
 vm.runInNewContext(fs.readFileSync(path.join(ROOT,'panorama/src/scripts/custom_game/production_progress.js'),'utf8'),{
  $,GameUI:{CustomUIConfig:()=>local},Game:{GetLocalPlayerID:()=>h.viewer,GetGameTime:()=>100},Players:{GetLocalPlayerPortraitUnit:()=>unit},
  Entities:{GetUnitName:()=> 'building_advanced_research_lab',IsValidEntity:()=>true,IsAlive:()=>true,GetPlayerOwnerID:()=>owner},Abilities:{GetAbilityName:()=>ability},
  CustomNetTables:{GetTableValue:()=>original,SubscribeNetTableListener:()=>1,UnsubscribeNetTableListener(){}},
  GameEvents:{Subscribe:(name,fn)=>events[name]=fn,SendCustomGameEventToServer:(...args)=>native.push(args)}});
 const hud=local.SurvivalProductionHUD,unknown=hud.GetResearchRuntime(300,30,original);
 check(unknown.research_prerequisite_known===0&&unknown.prerequisite_met===undefined&&unknown.available===0,'unknown is neutral pending, not assumed locked/unlocked');
 h.hello();h.hint(2,true,30,1);const def=C.auxiliary.production.research.find(r=>r.ability_name===ability),record=R['production:research:'+def.group];
 h.full(2,30,1,2,[{record,field:F.production_flags,value:0}]);const locked=hud.GetResearchRuntime(300,30,original);
 check(locked.research_prerequisite_known===1&&locked.prerequisite_met===0&&locked._prepared_partial,'shared first paint uses actual current-viewer prerequisite');
 h.full(2,30,1,3,[{record,field:F.production_flags,value:2}]);const unlocked=hud.GetResearchRuntime(300,30,original);
 check(unlocked.prerequisite_met===1&&unlocked.research_status_code==='syncing'&&unlocked.available===0,'known prerequisite is not represented as complete execution state');
 check(hud.QueueResearch(300,30)===false&&hud.CancelResearch({job_id:123})===false,'partial view never authorizes operations or cancellation handles');
 owner=0;const own=hud.GetResearchRuntime(300,30,original);check(!own._prepared_partial&&own.available===1,'own native authoritative row stays preferred without prewarm');owner=1;
 const seq=local.SurvivalProductionSelectionSerial,ops=fixture.research_ops.map(op=>op.record===R['production:state']&&op.field===F.production_selection?{...op,value:seq}:{...op});
 h.feed(encode(ops,7));const actual=hud.GetResearchRuntime(300,30,original);
 check(!actual._prepared_partial&&actual.research_prerequisite_known===1&&actual.cost_wood===original.cost_wood,'real view7 replaces partial and restores complete tooltip');
 check(native.length===0,'no legacy server calls added');hud.Dispose();const n=h.sent.length;h.full(2,30,1,4);check(h.sent.length===n,'disposed controller rejects prepared callbacks');
}
{
 const actual=serverCases.find(row=>row.players===4);
 const clients=Array.from({length:4},(_,id)=>{const h=harness(id);h.hello(600+id);return h;});
 check(actual.hint_vectors.length===24&&actual.vectors.length===144,'actual Lua vectors include all private discovery and full frames');
 actual.hint_vectors.forEach(v=>clients[v.id].feed([v.packet]));
 clients.forEach(h=>check(h.prep.Inspect().slots.every(s=>!s.ready),'actual hint never impersonates full state'));
 actual.vectors.forEach(v=>{const header=W.PeekHeader(v.packet),entity=30+header.view-12;
  clients[v.id].feed([v.packet]);
  if(header.index<header.count)check(clients[v.id].prep.GetPrerequisite(entity,'ability_research_ars_10')===null,'actual Lua half transaction remains invisible');
  else check(clients[v.id].prep.GetPrerequisite(entity,'ability_research_ars_10').current_level===0,'actual Lua full commits zero starting level');
 });
 clients.forEach((h,id)=>{check(h.prep.Inspect().slots.every(s=>s.ready),'three foreign views ready after real Lua frames');
  for(let owner=0;owner<4;owner++)if(owner!==id){const row=h.prep.GetPrerequisite(30+owner,'ability_research_ars_10');check(row.research_prerequisite_known===1&&row.current_level===0,'viewer-specific actual initial row');}
 });
 actual.update_vectors.forEach(v=>clients[v.id].feed([v.packet]));
 clients.forEach((h,id)=>{for(let owner=0;owner<4;owner++)if(owner!==id)check(h.prep.GetPrerequisite(30+owner,'ability_research_ars_10').current_level===(id===0?1:0),'actual single-viewer Lua delta cannot change another viewer');});
 check(actual.update_vectors.every(v=>W.PeekHeader(v.packet).kind==='delta'&&v.id===0),'unmodified Lua delta bytes only target current viewer');
 actual.lifecycle_vectors.forEach(stage=>{
  stage.frames.forEach(v=>clients[v.id].feed([v.packet]));
  for(const id of [0,2,3]){
   const row=clients[id].prep.GetPrerequisite(31,'ability_research_ars_10');
   if(stage.name.endsWith('_restore'))check(row&&row.current_level===(id===0?1:0),'actual post-Probe hint/Open restore returns private level');
   else check(row===null,'actual revoke and hint-only restore remain unavailable');
  }
 });
 clients.forEach(h=>h.prep.Dispose());
}
// The smaller actual-server populations exercise the same receiver with no
// made-up frames. Budgets concern simulation + calibrated wire sizes only.
for(const actual of serverCases){
 const n=actual.players,pairs=n*(n-1);
 check(actual.status==='SLIM_PREPARED_REAL_TRANSPORT_PASS'&&actual.failures.length===0,'actual Lua server checks pass');
 check(actual.pairs===pairs&&actual.forbidden_reads===0&&actual.list_calls===1,'one index/bootstrap and no wallets or queue reads');
 check(actual.hints.frames===pairs*2&&actual.initial.frames===pairs*12,'1/2/4 player discovery/full frame budgets remain bounded');
 check(actual.hints.max_calibrated_native_bytes<=50&&actual.initial.max_calibrated_native_bytes<=50,'all per-player prepared frames respect calibrated50');
 check(actual.hints.calibrated_native_bytes<=pairs*100&&actual.initial.calibrated_native_bytes<=pairs*600,'total bytes scale only with live foreign player pairs');
 check(actual.metrics.service.metrics.errors===0&&actual.metrics.service.metrics.max_pass_work<=2,'real dispatch has no swallowed error or unbounded pass');
 check(actual.simulation_clock_paused===true&&actual.network_RTT_ms===0,'simulation pauses and zero RTT are explicitly labelled');
 if(n===4)continue; // Full lifecycle/atomicity above already consumes this run.
 const clients=Array.from({length:n},(_,id)=>{const h=harness(id);h.hello(600+id);return h;});
 actual.hint_vectors.forEach(row=>clients[row.id].feed([row.packet]));
 actual.vectors.forEach(row=>clients[row.id].feed([row.packet]));
 for(let viewer=0;viewer<n;viewer++){
  const h=clients[viewer];
  check(h.prep.GetPrerequisite(30+viewer,'ability_research_ars_10')===null,'own lab is not prewarmed or read from a foreign scope');
  for(let owner=0;owner<n;owner++)if(owner!==viewer){
   const row=h.prep.GetPrerequisite(30+owner,'ability_research_ars_10');
   check(row&&row.research_prerequisite_known===1&&row.current_level===0,'actual1/2 player private initial state reconstructs');
  }
 }
 actual.update_vectors.forEach(row=>clients[row.id].feed([row.packet]));
 for(let viewer=0;viewer<n;viewer++)for(let owner=0;owner<n;owner++)if(owner!==viewer){
  check(clients[viewer].prep.GetPrerequisite(30+owner,'ability_research_ars_10').current_level===(viewer===0?1:0),'actual smaller-population update remains private');
 }
 for(const stage of actual.lifecycle_vectors){
  stage.frames.forEach(row=>clients[row.id].feed([row.packet]));
  for(let viewer=0;viewer<n;viewer++)if(viewer!==1){
   const row=clients[viewer].prep.GetPrerequisite(31,'ability_research_ars_10');
   check(stage.name.endsWith('_restore')?row&&row.current_level===(viewer===0?1:0):row===null,'actual smaller-population revoke/restore and entity reuse stay isolated');
  }
 }
 clients.forEach(h=>h.prep.Dispose());
}
console.log(JSON.stringify({status:'PASS_RESEARCH_PREPARED_ACTUAL_LUA_JS_RUNTIME',checks,
 lua_cases:serverCases.map(r=>({players:r.players,checks:r.checks,hint_packets:r.hints.frames,full_packets:r.initial.frames,delta_packets:r.update_vectors.length})),
 prepared_fields_per_technology:2,live_calls:0,network_calls:0,fixture_files_written:0,ordinary_validation:false}));


