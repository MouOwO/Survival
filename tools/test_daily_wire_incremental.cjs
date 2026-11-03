"use strict";
// Real production daily controller + local model in the Panorama fixture.
// Only the native bridge/runtime delivery is synthetic; no player transactions.
const assert=require("node:assert/strict"),fs=require("node:fs"),vm=require("node:vm"),cp=require("node:child_process");
const {createHarness}=require("./tests/fixtures/menus_v10_harness.cjs"),model=require("../panorama/src/scripts/custom_game/common/compact_daily_model.js");
const config={};vm.runInNewContext(fs.readFileSync("output/ui_static_catalog_20261103/panorama/src/scripts/custom_game/common/ui_static_catalog.js","utf8"),{GameUI:{CustomUIConfig:()=>config}});
const fixture=JSON.parse(cp.execFileSync(process.env.LUA51||"C:/Program Files/lua/bin/lua5.1.exe",["scripts/vscripts/tests/test_compact_daily_projection.lua","emit"],{encoding:"utf8"}).trim().split(/\r?\n/).at(-1));
let checks=0;function test(name,fn){fn();checks++;console.log("ok",name);}
function setup(){
 const h=createHarness(),rows=Object.create(null),controls=[],intents=[];let options,opened=false,token=0,revision=0,disposed=false;
 h.cfg.SurvivalUICatalog=config.SurvivalUICatalog;h.cfg.SurvivalCompactDailyModel=model;
 h.cfg.SurvivalCompactRuntime={CreateView(name,opts){assert.equal(name,"daily");options=opts;return {Open(){controls.push("open");opened=true;},Close(){controls.push("close");opened=false;},Probe(){controls.push("probe");},Dispose(){controls.push("dispose");disposed=true;opened=false;},Read:(r,f)=>rows[r]&&rows[r][f],SendIntent(action,args){intents.push({action,args,request_token:++token});return {sent:true,request_token:token};},Inspect(){return {opened,disposed};}};}};
 for(const source of ["archive_theme_tokens.js","archive_parchment_data.js","archive_handoff_180de7e38b.js","archive_v10_semantics.js","common/archive_tooltip.js","daily_gw2_data.js","daily_remaining_5d5c1152eb.js"])h.load(source);
 return {h,controls,intents,deliver(ops,{full=false,force=false}={}){const changed=[],seen=new Set();for(const op of ops){const row=rows[op.record]||(rows[op.record]=Object.create(null));if(op.remove)delete row[op.field];else row[op.field]=op.value;if(!seen.has(op.record)){seen.add(op.record);changed.push(op.record);}}if((opened&&!disposed)||force)options.onCommit({full,revision:++revision},changed,(r,f)=>rows[r]&&rows[r][f]);},hint(flag){options.onHint(flag);}};
}
test("closed entry probes only flags; open uses shared runtime without full-page polling",()=>{
 const t=setup();t.h.setLoading({admission_complete:1});assert.deepEqual(t.controls,["probe"]);assert.equal(t.h.sent.length,0);
 t.h.cfg.SurvivalDaily.Open(false);assert.deepEqual(t.controls,["probe","open"]);
 assert.equal(t.h.scheduled.filter(x=>x.delay===3).length,0);assert.equal(t.h.sent.filter(x=>x.name==="survival_daily_request").length,0);
 t.deliver(fixture.initial_ops_fixture,{full:true});assert.equal(t.h.cfg.SurvivalDaily.Inspect().days,28);assert.equal(t.h.cfg.SurvivalDaily.Inspect().count,fixture.initial_expected.count);
});
test("a threshold delta keeps all calendar and unrelated benefit native panels",()=>{
 const t=setup();t.h.cfg.SurvivalDaily.Open(false);t.deliver(fixture.initial_ops_fixture,{full:true});const cards=t.h.nodes.DailyCards.Children().slice(),first=t.h.nodes.DailyGW2Benefit_daily_wins_daily_win_1,before={...t.h.counts};
 t.deliver(fixture.threshold_ops_fixture);assert.deepEqual(t.h.nodes.DailyCards.Children(),cards);assert.equal(t.h.nodes.DailyGW2Benefit_daily_wins_daily_win_1,first);
 assert.ok(t.h.counts.deleted-before.deleted<100,"Only affected benefit rows are rebuilt");assert.equal(t.h.cfg.SurvivalDaily.Inspect().days,28);
});
test("1000 unchanged dynamic deliveries perform zero panel/tree/style/text writes",()=>{
 const t=setup();t.h.cfg.SurvivalDaily.Open(false);t.deliver(fixture.initial_ops_fixture,{full:true});const before={...t.h.counts};
 for(let i=0;i<1000;i++)t.deliver([]);
 for(const key of ["created","deleted","text","style","tree"])assert.equal(t.h.counts[key],before[key],key);
});
test("close stops full stream, preserves hint and does not render reward panels",()=>{
 const t=setup();t.h.setLoading({admission_complete:1});t.h.cfg.SurvivalDaily.Open(false);t.deliver(fixture.initial_ops_fixture,{full:true});t.h.cfg.SurvivalDaily.Close();assert.equal(t.controls.at(-1),"close");const before={...t.h.counts};
 t.hint({known:1,claimable:1});assert.equal(t.h.cfg.SurvivalDaily.HasClaimable(),true);t.hint({known:0,claimable:0});assert.equal(t.h.cfg.SurvivalDaily.HasClaimable(),true);
 let classWrites=0;const entry=t.h.nodes.DailyEntry,set=entry.SetHasClass;entry.SetHasClass=function(...args){classWrites++;return set.apply(this,args);};
 for(let i=0;i<100;i++)t.hint({known:1,claimable:1});assert.equal(classWrites,0);assert.equal(t.h.counts.created,before.created);assert.equal(t.h.counts.deleted,before.deleted);assert.equal(t.h.counts.text,before.text);assert.equal(t.h.counts.style,before.style);
});
test("claim intent uses numeric compact target and no legacy request or optimistic count",()=>{
 const t=setup();t.h.cfg.SurvivalDaily.Open(false);t.deliver(fixture.initial_ops_fixture,{full:true});const before=t.h.cfg.SurvivalDaily.Inspect().count;
 t.h.click(t.h.nodes.DailyClaim);assert.equal(t.intents.at(-1).action,"daily_claim");assert.equal(typeof t.intents.at(-1).args.target_day,"number");assert.equal(t.h.cfg.SurvivalDaily.Inspect().count,before);assert.equal(t.h.sent.length,0);
});
test("pending and failed save cannot extinguish the prior entry hint",()=>{
 const t=setup();t.h.setLoading({admission_complete:1});t.h.cfg.SurvivalDaily.Open(false);t.deliver(fixture.initial_ops_fixture,{full:true});assert.equal(t.h.cfg.SurvivalDaily.HasClaimable(),true);
 t.h.click(t.h.nodes.DailyClaim);t.hint({known:1,claimable:0});assert.equal(t.h.cfg.SurvivalDaily.HasClaimable(),true);
 const C=config.SurvivalUICatalog.Data,F=Object.fromEntries(C.fields.map(f=>[f.name,f.id])),record=key=>C.records.find(r=>r.key===key).id,state=record("daily:state"),ack=record("daily:ack:claim"),intent=t.intents.at(-1),expected=fixture.initial_expected;
 const ops=Object.entries({known:1,request_token:intent.request_token,day:intent.args.target_day,period:Number(expected.period_id),target_record:0,pending:0,success:0,terminal:1,error_code:8}).map(([key,value])=>({record:ack,field:F[key],value}));
 ops.push({record:state,field:F.pending,value:0});t.deliver(ops);assert.equal(t.h.cfg.SurvivalDaily.Inspect().waiting,false);t.hint({known:1,claimable:0});assert.equal(t.h.cfg.SurvivalDaily.HasClaimable(),true);
});
test("disposed old runtime callbacks cannot access destroyed native panels",()=>{
 const t=setup();t.h.cfg.SurvivalDaily.Open(false);t.deliver(fixture.initial_ops_fixture,{full:true});t.h.cfg.SurvivalDaily.Dispose();t.h.root.DeleteAsync();assert.doesNotThrow(()=>t.deliver(fixture.threshold_ops_fixture,{force:true}));assert.equal(t.controls.at(-1),"dispose");
});
console.log(JSON.stringify({status:"PASS_DAILY_COMPACT_CONTROLLER_SYNTHETIC_NOT_NATIVE",tests:checks,network_calls:0,transactions:0,stable_panel_writes:0,periodic_polls:0}));
