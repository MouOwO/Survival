"use strict";
const assert=require("node:assert/strict"),fs=require("node:fs");
const legacy=fs.readFileSync("tools/test_public_beta_gift_ui.cjs","utf8").replace(/\r\n/g,"\n");
let prefix=legacy.slice(0,legacy.indexOf('test("no query'));
prefix=prefix.replace("function fixture() {","function fixture(configure) {")
 .replace("    load();\n    return {","    if(configure)configure(cfg);load();\n    return {");
const boot=new Function("require",prefix+"\nreturn fixture;")(require);
let tests=0;function test(name,fn){fn();tests++;console.log("ok",name);}
function compact(label){
 const stats={created:0,opens:0,disposed:0,applied:0,resyncs:0,intents:0},callbacks=[];
 const runtime={ScopeIdentity:()=>({active:true,ready:true,loading_identity:label,session:1}),CreateView(key,cb){
  assert.equal(key,"public_beta");stats.created++;callbacks.push(cb);
  return {Open(){stats.opens++;return{sent:true};},Close(){},Dispose(){stats.disposed++;},Resync(){stats.resyncs++;return{sent:true};},SendIntent(){stats.intents++;return{sent:false};}};
 }};
 const model={Create(){return{Apply(){stats.applied++;return{known:false};},HasRequest(){return false;}};}};
 return {stats,callbacks,runtime,model,install(cfg){cfg.SurvivalUICatalog={};cfg.SurvivalCompactRuntime=runtime;cfg.SurvivalCompactPublicBetaModel=model;}};
}

test("independent XML includes every transport dependency before its controller",()=>{
 const xml=fs.readFileSync("panorama/src/layout/custom_game/public_beta_gift.xml","utf8");
 const paths=[...xml.matchAll(/<include src="file:\/\/\{resources\}\/scripts\/custom_game\/(.*?)"/g)].map(m=>m[1]);
 assert.deepEqual(paths,["common/ui_static_catalog.js","common/compact_wire.js","common/compact_grid_bulk_wire.js","common/compact_ui_runtime.js","common/compact_public_beta_model.js","public_beta_gift.js"]);
});
test("runtime-first boot sends one Open at profiles-ready edge and no stable retries",()=>{
 const c=compact("runtime_first"),f=boot(cfg=>c.install(cfg));
 assert.equal(c.stats.created,1);f.admit(true,false);assert.equal(c.stats.opens,0);
 f.admit();assert.equal(c.stats.opens,1);assert.equal(f.queries().length,0);
 for(let n=0;n<1000;n++){f.admit();f.tick();}
 assert.equal(c.stats.created,1);assert.equal(c.stats.opens,1);assert.equal(c.stats.resyncs,0);assert.equal(c.stats.intents,0);
 f.cfg.SurvivalPublicBetaGift.Dispose();
});
test("legacy-first loading notification transfers once and retires queued legacy listener",()=>{
 const f=boot(),c=compact("late_runtime");f.admit();assert.equal(f.queries().length,1);
 const lateLegacy=[...f.events.values()].find(e=>e.name==="survival_public_beta_gift_snapshot").fn;
 c.install(f.cfg);f.admit();assert.equal(c.stats.created,1);assert.equal(c.stats.opens,1);
 assert.equal([...f.events.values()].filter(e=>e.name==="survival_public_beta_gift_snapshot").length,0);
 lateLegacy({ok:1,login_key:"stale_legacy",day_key:"20261104",sequence:1,revision:1,ticket_id:"special_lottery_ticket",ticket_count:2,active:1,eligible:1});
 assert.equal(f.inspect().login_key,"");assert.equal(f.inspect().open,false);
 for(let n=0;n<1000;n++)f.admit();
 assert.equal(c.stats.opens,1);assert.equal(f.queries().length,1,"no new legacy send after compact exists");
 f.cfg.SurvivalPublicBetaGift.Dispose();
});
test("late model attaches on a real loading event without a dependency poll",()=>{
 const c=compact("late_model"),f=boot(cfg=>{cfg.SurvivalCompactRuntime=c.runtime;cfg.SurvivalUICatalog={};});
 f.admit();assert.equal(f.queries().length,0);assert.equal(c.stats.created,0);
 f.cfg.SurvivalCompactPublicBetaModel=c.model;
 for(let n=0;n<1000;n++)f.tick();
 assert.equal(c.stats.created,0,"no timer polls for dependencies");
 f.admit();assert.equal(c.stats.created,1);assert.equal(c.stats.opens,1);
 f.cfg.SurvivalPublicBetaGift.Dispose();
});
test("world runtime replacement retires old view callbacks and disposal removes loading owner",()=>{
 const a=compact("world_a"),b=compact("world_b"),f=boot(cfg=>a.install(cfg));f.admit();
 b.install(f.cfg);f.admit(false);assert.equal(a.stats.disposed,1);assert.equal(b.stats.created,1);assert.equal(b.stats.opens,0);
 a.callbacks[0].onCommit({full:true},[],()=>0);assert.equal(a.stats.applied,0);assert.equal(b.stats.applied,0);
 f.admit();assert.equal(b.stats.opens,1);b.callbacks[0].onCommit({full:true},[],()=>0);assert.equal(b.stats.applied,1);
 const lateLoading=[...f.tables.values()];f.cfg.SurvivalPublicBetaGift.Dispose();
 for(const fn of lateLoading)fn();a.callbacks[0].onCommit({full:true},[],()=>0);b.callbacks[0].onCommit({full:true},[],()=>0);
 assert.equal(b.stats.applied,1);assert.equal(b.stats.disposed,1);assert.equal(f.tables.size,0);assert.equal(f.queries().length,0);
});
console.log(JSON.stringify({status:"PASS_PUBLIC_BETA_STARTUP_SYNTHETIC_NOT_NATIVE",tests}));
