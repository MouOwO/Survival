"use strict";
const assert=require("node:assert/strict"),fs=require("node:fs"),vm=require("node:vm"),cp=require("node:child_process"),path=require("node:path");
const Model=require("../panorama/src/scripts/custom_game/common/compact_hud_model.js"),Source=require("../panorama/src/scripts/custom_game/common/compact_hud_source.js"),config={};
vm.runInNewContext(fs.readFileSync("panorama/src/scripts/custom_game/common/ui_static_catalog.js","utf8"),{GameUI:{CustomUIConfig:()=>config}});
const C=config.SurvivalUICatalog.Data,F=Object.fromEntries(C.fields.map(f=>[f.name,f.id])),R=C.records.find(r=>r.key==="hud:state").id;
const fixture=JSON.parse(cp.execFileSync(process.env.LUA51||"C:/Program Files/lua/bin/lua5.1.exe",["scripts/vscripts/tests/test_compact_hud_projection.lua"],{env:{...process.env,COMPACT_HUD_FIXTURE:"1"},encoding:"utf8"}));
let checks=0;function test(name,fn){fn();checks++;console.log("ok",name);}
function store(){const values=Object.create(null);return {put(ops){for(const op of ops){if(op.remove)delete values[op.field];else values[op.field]=typeof op.value==="boolean"?op.value?1:0:op.value;}},read:(r,f)=>r===R?values[f]:undefined};}
function setup(playerId=0){let callback,created=0,opened=0,closed=0,resync=0,now=125.91;const model=Model.Create(C,{playerId,now:()=>now}),values=store();
 const runtime={CreateView(key,opts){assert.equal(key,"hud");created++;callback=opts;return {Open(){opened++;},Close(){closed++;},Dispose(){},Resync(){resync++;return {sent:true};},Inspect(){return {};}};}};
 const source=Source.Create({runtime,model});let revision=0;return {source,model,values,get stats(){return {created,opened,closed,resync};},setNow(n){now=n;},deliver(ops,full=false){values.put(ops);callback.onCommit({changes:ops,full,revision:++revision},[R],values.read);}};
}
test("real Lua typed projection reconstructs scalar HUD, phase, mode and safe currency",()=>{
 const t=setup();let actual;t.source.Subscribe("hud",["*"],s=>actual=s);t.deliver(fixture.operations,true);
 assert.equal(actual.resources.wood,9007199254740991);assert.equal(actual.resources.gold,4294967297);
 for(const field of ["population","max_population"])assert.equal(actual.resources[field],fixture.snapshot.resources[field]);
 for(const field of ["city_level","worker_count","shop_unlocked","research_unlocked","advanced_researcher_unlocked"])assert.equal(actual[field],fixture.snapshot[field]);
 for(const [field,value]of Object.entries(fixture.snapshot.wave)){if(["timer","countdown_deadline","overflow_deadline","challenge_deadline","defeat_reason"].includes(field))continue;assert.equal(actual.wave[field],typeof value==="boolean"?value?1:0:value,field);}
 assert.equal(actual.wave.countdown_deadline,149.124);assert.equal(actual.wave.timer,24);assert.equal(actual.wave.defeat_reason,undefined);
 t.setNow(140.9);assert.equal(actual.wave.timer,9);assert.equal(t.stats.created,1);assert.equal(t.stats.opened,1);
});
test("four owners share one stream and only changed dependency sections notify",()=>{
 const t=setup(),counts={resources:0,wave:0,city:0,unlocks:0},ids={};for(const name of Object.keys(counts))ids[name]=t.source.Subscribe(name,[name],()=>counts[name]++);
 t.deliver(fixture.operations,true);assert.deepEqual(counts,{resources:1,wave:1,city:1,unlocks:1});assert.equal(t.stats.created,1);assert.equal(t.stats.opened,1);
 t.deliver([{record:R,field:F.wave_alive,value:16}]);assert.deepEqual(counts,{resources:1,wave:2,city:1,unlocks:1});
 t.source.Unsubscribe(ids.wave);t.deliver([{record:R,field:F.wave_alive,value:17}]);assert.equal(counts.wave,2);assert.equal(t.stats.closed,0);
 for(const name of ["resources","city","unlocks"])t.source.Unsubscribe(ids[name]);assert.equal(t.stats.closed,1);
});
test("1000 unchanged transactions perform zero field reads, notification and resync",()=>{
 const t=setup();let calls=0;t.source.Subscribe("all",["*"],()=>calls++);t.deliver(fixture.operations,true);const metrics=t.model.Inspect().metrics;
 for(let n=0;n<1000;n++)t.deliver([]);assert.equal(calls,1);assert.equal(t.model.Inspect().metrics.field_reads,metrics.field_reads);assert.equal(t.stats.resync,0);
});
test("four personal HUD models remain isolated across writes and reset",()=>{
 const owners=[0,1,2,3].map(setup);owners.forEach((t,i)=>{t.source.Subscribe(i,["*"],()=>{});t.deliver(fixture.operations,true);t.deliver([{record:R,field:F.gold,value:i},{record:R,field:F.gold_hi,value:0}]);});
 owners.forEach((t,i)=>{assert.equal(t.source.Snapshot().player_id,i);assert.equal(t.source.Snapshot().resources.gold,i);});owners[1].source.Dispose();assert.equal(owners[1].source.Snapshot(),null);assert.equal(owners[2].source.Snapshot().resources.gold,2);
});
test("nil removals and unknown enums preserve uncertainty rather than guessing",()=>{
 const t=setup();t.source.Subscribe("all",["*"],()=>{});t.deliver(fixture.operations,true);t.deliver([{record:R,field:F.wave_game_mode,remove:true},{record:R,field:F.wave_phase,remove:true},{record:R,field:F.defeat_reason,value:10}]);assert.equal(t.source.Snapshot().wave.game_mode,undefined);assert.equal(t.source.Snapshot().wave.status,undefined);assert.equal(t.source.Snapshot().wave.defeat_reason,"unknown");
 assert.throws(()=>t.deliver([{record:R,field:F.wave_phase,value:99}]),/hud_phase_unknown/);assert.throws(()=>Model.JoinUnsigned(0,2097152),/hud_integer_unsafe/);
});
test("actual primary HUD uses one compact source and a wave delta does not refresh wallet",()=>{
 let code=fs.readFileSync("tools/test_startup_loading_ui.js","utf8");code=code.slice(0,code.indexOf("// LAN may replicate loading state"));code=code.replace("nodes, root, authoredRoot, requests, messages, config, nativeRuleCalls, nativePlayerInfoCalls,","nodes, root, authoredRoot, requests, messages, config, nativeRuleCalls, nativePlayerInfoCalls, context, env,");const sandbox={require,console};vm.runInNewContext(code+"\nglobalThis.fixture={harness,ready};",sandbox);
 const t=setup();let wallet=0;const cfg={SurvivalCompactHUDSource:t.source,SurvivalActionResources:{Update(){wallet++;}}};
 const h=sandbox.fixture.harness({hud:true,sharedConfig:cfg,startupState:sandbox.fixture.ready({admission_complete:true})});h.advance(.11);t.deliver(fixture.operations,true);assert.equal(h.nodes.GoldValue.text,"4294967297");const before=wallet;
 t.deliver([{record:R,field:F.wave_alive,value:22}]);assert.equal(wallet,before);assert.equal(h.nodes.AliveValue.text,"存活 22");
 t.deliver([{record:R,field:F.gold,value:7},{record:R,field:F.gold_hi,value:0}]);assert.equal(wallet,before+1);assert.equal(h.nodes.GoldValue.text,"7");
 h.advance(30);assert.equal(h.requests.filter(r=>r.name==="ui_request_full_snapshot").length,0);assert.equal(cfg.SurvivalHUDSnapshotSync.Inspect().counters.polls,0);cfg.SurvivalHUDSnapshotSync.Dispose();assert.equal(t.source.Inspect().owners,0);
});
test("actual purple shell refreshes wallet resources only and releases its own owner",()=>{
 const t=setup();let refresh=0;const cfg={SurvivalCompactHUDSource:t.source,SurvivalMenuV10:{Refresh(){refresh++;}}},owner={IsValid:()=>true};
 const env=vm.createContext({GameUI:{CustomUIConfig:()=>cfg},$:{GetContextPanel:()=>owner},GameEvents:{Subscribe:()=>1,Unsubscribe(){}},CustomNetTables:{},Game:{GetLocalPlayerID:()=>0}});
 vm.runInContext(fs.readFileSync("panorama/src/scripts/custom_game/common/purple_shell.js","utf8"),env);t.deliver(fixture.operations,true);const initial=refresh;t.deliver([{record:R,field:F.wave_alive,value:22}]);assert.equal(refresh,initial);t.deliver([{record:R,field:F.population,value:9}]);assert.equal(refresh,initial);t.deliver([{record:R,field:F.gold,value:8}]);assert.equal(refresh,initial+1);cfg.SurvivalPurpleShell.ReleaseSubscriptions();assert.equal(t.source.Inspect().owners,0);
});
test("actual loaded topnav receives compact model without a legacy snapshot request",()=>{
 const file=path.resolve("tools/test_topnav_refresh_context.cjs");let prefix=fs.readFileSync(file,"utf8").split("function run(code) {")[0];prefix=prefix.replace(/^const before = .*;$/m,'const before = "";');prefix=prefix.replace("    load();\n    return", "    cfg.SurvivalCompactHUDSource=globalThis.injectedHUDSource;\n    load();\n    return").replace("    load();\r\n    return", "    cfg.SurvivalCompactHUDSource=globalThis.injectedHUDSource;\r\n    load();\r\n    return");
 const t=setup(),sandbox={require:require("node:module").createRequire(file),__dirname:path.dirname(file),process,console,injectedHUDSource:t.source};vm.runInNewContext(prefix+"\nglobalThis.makeHUD=()=>fixture(source);",sandbox);const h=sandbox.makeHUD();t.deliver(fixture.operations,true);h.advance(1);assert.equal(h.sent.filter(r=>r.name==="ui_request_full_snapshot").length,0);assert.equal(t.source.Inspect().owners,1);h.load();assert.equal(t.source.Inspect().owners,1,"Reload retires exactly the old topnav subscription");t.deliver([{record:R,field:F.wave_alive,value:19}]);assert.equal(h.warnings.length,0);
});
console.log(JSON.stringify({status:"PASS_COMPACT_HUD_MODEL_SOURCE_AND_REAL_CONTROLLERS_SYNTHETIC_NOT_NATIVE",tests:checks,native_calls:0,network_calls:0,stable_notifications:0,stable_field_reads:0,shared_runtime_views:1}));
