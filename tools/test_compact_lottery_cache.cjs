"use strict";
const assert=require("node:assert/strict"),fs=require("node:fs"),vm=require("node:vm"),cp=require("node:child_process");
const Model=require("../panorama/src/scripts/custom_game/common/compact_lottery_model.js"),config={};
vm.runInNewContext(fs.readFileSync("panorama/src/scripts/custom_game/common/ui_static_catalog.js","utf8"),{GameUI:{CustomUIConfig:()=>config}});
const C=config.SurvivalUICatalog,F=Object.fromEntries(C.Data.fields.map(f=>[f.name,f.id])),R=Object.fromEntries(C.Data.records.map(r=>[r.key,r.id]));
const data=JSON.parse(cp.execFileSync(process.env.LUA51||"C:/Program Files/lua/bin/lua5.1.exe",["scripts/vscripts/tests/test_compact_lottery_projection.lua","emit"],{encoding:"utf8"}));
function runtime(){const views={},intents=[],controls=[];let token=50;return {views,intents,controls,Inspect:()=>({ready:true}),CreateView(key,options){const state=views[key]={options,values:{},revision:0,open:false};return {Open(){state.open=true;controls.push([key,"open"]);return {sent:true};},Close(){state.open=false;controls.push([key,"close"]);},Dispose(){state.open=false;},Resync(){controls.push([key,"resync"]);return {sent:true};},SendIntent(action,args){intents.push({key,action,args,request_token:++token});return {sent:true,request_token:token};}};},deliver(pool,ops,full=false){const state=views["lottery:"+pool],ids=[],seen=new Set();for(const op of ops){const row=state.values[op.record]||(state.values[op.record]={});if(op.remove)delete row[op.field];else row[op.field]=op.value;if(!seen.has(op.record)){seen.add(op.record);ids.push(op.record);}}state.options.onCommit({full,revision:++state.revision},ids,(r,f)=>state.values[r]&&state.values[r][f]);}};}
function cacheFixture(bulk=false){const rt=runtime(),catalog=bulk?{Data:{...C.Data,auxiliary:{...C.Data.auxiliary,lottery_receipt_wire_version:1}}}:C,cfg={SurvivalCompactRuntime:rt,SurvivalCompactLotteryModel:Model,SurvivalUICatalog:catalog},events={},sent=[],env={GameUI:{CustomUIConfig:()=>cfg},GameEvents:{Subscribe(name,fn){events[name]=fn;return name;},Unsubscribe(){},SendCustomGameEventToServer(n,p){sent.push({n,p});}},$:{Msg(){}}};if(bulk)cfg.SurvivalCompactLotteryReceiptWire=require('../panorama/src/scripts/custom_game/common/compact_lottery_receipt_wire.js');vm.runInNewContext(fs.readFileSync("panorama/src/scripts/custom_game/common/lottery_cache.js","utf8"),env);return {rt,cfg,events,sent,env,api:cfg.SurvivalLotteryCache};}
let tests=0;function test(name,fn){fn();tests++;console.log("ok",name);}
test("static catalogue is local and unknown tickets cannot authorize a free draw",()=>{
 const t=cacheFixture();assert.equal(t.api.Compact,true);assert.equal(t.sent.length,0);assert.equal(t.api.IsAuthoritative("map"),false);assert.equal(t.api.Snapshot("map").selected_pool.tickets,undefined);assert.equal(t.api.Draw("map",1,"unknown").sent,false);
 t.api.Open("map");t.rt.deliver("map",data.initial_ops,true);assert.equal(t.api.IsAuthoritative("map"),true);assert.equal(t.api.Snapshot("map").tickets,100);assert.equal(t.sent.length,0);
});
test("draw and read use numeric runtime intents; receipt restores the original local request id",()=>{
 const t=cacheFixture(),packets=[];t.api.Subscribe((id,p)=>packets.push(p));t.api.Open("map");t.rt.deliver("map",data.initial_ops,true);
 const sent=t.api.Draw("map",1,"original-local-id",false);assert.equal(sent.request_token,51);assert.equal(t.rt.intents.at(-1).action,"lottery_draw");assert.equal(t.rt.intents.at(-1).args.pool_record,R["lottery:pool:map"]);
 t.rt.deliver("map",data.changed_ops);t.rt.deliver("map",data.receipt_ops);assert.equal(packets.at(-1).result.request_id,"original-local-id");assert.equal(packets.at(-1).result.results.length,1);
 t.api.ReadAck(t.api.Snapshot("map").selected_pool,"details");assert.equal(t.rt.intents.at(-1).action,"lottery_read");assert.equal(t.rt.intents.at(-1).args.read_action,2);assert.equal(t.sent.length,0);
});
test("stable deltas notify zero listeners; pool switches close the prior subscription",()=>{
 const t=cacheFixture();let calls=0;t.api.Subscribe(()=>calls++);t.api.Open("map");t.rt.deliver("map",data.initial_ops,true);const before=calls,rev=t.api.Revision("map");for(let n=0;n<1000;n++)t.rt.deliver("map",[]);assert.equal(calls,before);assert.equal(t.api.Revision("map"),rev);
 t.api.Open("summer");assert.equal(t.rt.views["lottery:map"].open,false);assert.equal(t.rt.views["lottery:summer"].open,true);t.api.Close();assert.equal(t.rt.views["lottery:summer"].open,false);
});
test("redemption invalidates authority and requests one recovery, never credits guessed tickets",()=>{
 const t=cacheFixture();t.api.Open("map");t.rt.deliver("map",data.initial_ops,true);const before=t.api.Snapshot("map").tickets;t.events.survival_commerce_result({action:"redeem",ok:1,request_id:"r1"});t.events.survival_commerce_result({action:"redeem",ok:1,request_id:"r1"});assert.equal(t.api.Snapshot("map").tickets,before);assert.equal(t.api.IsAuthoritative("map"),false);assert.equal(t.rt.controls.filter(x=>x[1]==="resync").length,1);
});
test("real cache decodes bulk once, preserves pending close/reopen and checks count",()=>{
 const t=cacheFixture(true),packets=[];t.api.Subscribe((id,p)=>packets.push(p));t.api.Open('map');t.rt.deliver('map',data.initial_ops,true);
 const draw=t.api.Draw('map',1,'bulk-request'),state=t.rt.views['lottery:map'],header={view:201,scope:draw.request_token};
 assert.equal(state.options.bulkLottery,true);assert.equal(state.options.acceptBulk(header),true);
 const values={};for(const op of data.receipt_ops)if(!op.remove)values[op.record+'.'+op.field]=op.value;
 const val=(key,name)=>values[R[key]+'.'+F[name]],codec=t.cfg.SurvivalCompactLotteryReceiptWire.Create(t.cfg.SurvivalUICatalog);
 const receipt={count:1,guarantee_quality:val('lottery:receipt','quality_code'),guarantee_satisfied:val('lottery:receipt','guarantee_satisfied')===1,results:[{
  record:val('lottery:result:1','target_record'),owned_count:val('lottery:result:1','owned_count'),converted_points:val('lottery:result:1','converted_points'),duplicate:val('lottery:result:1','duplicate')===1}]};
 const raw=codec.Encode(201,2,receipt,[]);
 t.api.Close();assert.equal(state.options.acceptBulk(header),false);t.api.Open('map');assert.equal(state.options.acceptBulk(header),true);
 const bad=codec.Encode(201,2,{...receipt,count:10,results:Array(10).fill(receipt.results[0])},[]);
 assert.throws(()=>state.options.onBulkDecode(header,bad),/count_mismatch/);
 const tx=state.options.onBulkDecode(header,raw);t.rt.deliver('map',tx.changes);assert.equal(packets.at(-1).result.request_id,'bulk-request');
 assert.equal(state.options.acceptBulk(header),false);assert.throws(()=>state.options.onBulkDecode(header,raw),/intent_missing/);
 assert.equal(t.rt.intents.filter(x=>x.action==='lottery_draw').length,1);assert.equal(t.sent.length,0);
});
test("one pending receipt timeout requests only one read-only recovery and preserves the original token",()=>{
 const t=cacheFixture(true),timers=[],packets=[];t.env.$.Schedule=(seconds,fn)=>{const timer={seconds,fn,canceled:false};timers.push(timer);return timer;};t.env.$.CancelScheduled=timer=>{timer.canceled=true;};
 t.api.Subscribe((id,packet)=>packets.push(packet));t.api.Open('map');t.rt.deliver('map',data.initial_ops,true);
 assert.equal(timers.length,0);t.api.Draw('map',1,'late-request');assert.equal(timers.length,1);assert.equal(timers[0].seconds,5);
 timers[0].fn();for(let i=0;i<1000;i++)timers[0].fn();
 assert.equal(t.rt.controls.filter(x=>x[1]==='resync').length,1);assert.equal(packets.filter(p=>p.receipt_waiting).length,1);
 assert.equal(t.api.Draw('map',1,'must-not-redraw').sent,false);assert.equal(t.rt.intents.filter(x=>x.action==='lottery_draw').length,1);
 t.api.Close();t.api.Open('map');t.rt.deliver('map',data.initial_ops,true);assert.equal(t.api.IsAuthoritative('map'),false,'an unrelated full cannot confirm an uncertain draw');assert.equal(timers.length,1);
 t.rt.deliver('map',data.receipt_ops);assert.equal(packets.at(-1).result.request_id,'late-request');assert.equal(t.api.IsAuthoritative('map'),true);
 assert.equal(t.rt.intents.filter(x=>x.action==='lottery_draw').length,1);
});
test("close, completion and disposal cancel the only temporary receipt timer",()=>{
 for(const action of ['close','complete','dispose']){
  const t=cacheFixture(),timers=[];t.env.$.Schedule=(seconds,fn)=>{const timer={fn,canceled:false};timers.push(timer);return timer;};t.env.$.CancelScheduled=timer=>{timer.canceled=true;};
  t.api.Open('map');t.rt.deliver('map',data.initial_ops,true);t.api.Draw('map',1,'timer-'+action);
  if(action==='close')t.api.Close();else if(action==='complete')t.rt.deliver('map',data.receipt_ops);else t.api.Dispose();
  assert(timers[0].canceled);timers[0].fn();assert.equal(t.rt.controls.filter(x=>x[1]==='resync').length,0);
  if(action==='close'){t.api.Open('map');assert.equal(timers.length,2);t.rt.deliver('map',data.receipt_ops);timers[1].fn();assert.equal(t.rt.controls.filter(x=>x[1]==='resync').length,0);}
 }
});
test("actual controller replays three receipts, retains close intent, and clears a genuine new-world pending operation",()=>{
 const rt=runtime();let suite=fs.readFileSync("tools/test_lottery_ui.js","utf8").split("ui.Open();assert.equal")[0];
 suite=suite.replace("vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/lottery_ui.js','utf8'),env);",`
Panel.prototype.Children=function(){return this.children;};
Panel.prototype.MoveChildBefore=function(child,before){this.children.splice(this.children.indexOf(child),1);this.children.splice(this.children.indexOf(before),0,child);};
Panel.prototype.FindChildTraverse=function(id){return nodes[id]||null;};Panel.prototype.DeleteAsync=function(){this.deleted=true;};
Panel.prototype.SetMovie=function(s){this.movieSource=s;};Panel.prototype.SetControls=Panel.prototype.SetRepeat=Panel.prototype.SetPlaybackVolume=function(){};
Panel.prototype.Play=function(){this.playing=true;};Panel.prototype.Stop=function(){this.playing=false;};
config.SurvivalCompactRuntime=testRuntime;config.SurvivalCompactLotteryModel=testModel;config.SurvivalUICatalog=testCatalog;
let fixtureLoading={session_id:'fixture_world_A',setup:{mode_id:'standard'}},fixtureLoadingListener;
env.CustomNetTables={GetTableValue:()=>fixtureLoading,SubscribeNetTableListener:(name,fn)=>{fixtureLoadingListener=fn;return 1;},UnsubscribeNetTableListener:()=>{}};
['reference_windows','ui_snapshot_cache','common/lottery_cache','lottery_scene_transition','lottery_handoff_bb9968eef7','remaining_5d5c1152eb','lottery_cinematic_v1','lottery_ui_remaining_5d5c1152eb'].forEach(function(file){vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/'+file+'.js','utf8'),env);});`);
 suite+=`
root.actuallayoutwidth=1920;root.actuallayoutheight=1080;root.actualuiscale_x=1;root.actualuiscale_y=1;
nodes.LotteryMainCanvas.AddClass('LotteryV10');config.SurvivalPurpleLottery={Version:'lottery_current_20261018',Owns(owner){return owner===root;},IsAlive(){return true;},IsReady(){return true;},Open(){},Close(){},Apply(){},Content:()=>nodes.LotteryMainCanvas,Fit(){return true;}};
ui.Open();testRuntime.deliver('map',testFixture.initial_ops,true);
for(let n=0;n<3;n++){
 ui.DrawTen();const intent=testRuntime.intents.filter(x=>x.action==='lottery_draw').at(-1);assert(intent&&intent.args.count===10);
 const receipt=testFixture.receipt_ops.filter(x=>!(x.record>=testRecords['lottery:result:1']&&x.record<=testRecords['lottery:result:10'])).map(x=>({...x}));
 for(const op of receipt){if(op.record===testRecords['lottery:receipt']&&op.field===testFields.request_token)op.value=intent.request_token;if(op.record===testRecords['lottery:receipt']&&op.field===testFields.count)op.value=10;}
 const first=testFixture.receipt_ops.filter(x=>x.record===testRecords['lottery:result:1']);for(let slot=1;slot<=10;slot++)for(const op of first)receipt.push({...op,record:testRecords['lottery:result:'+slot]});
 testRuntime.deliver('map',receipt);assert.equal(nodes.LotteryItemList.children.length,10);assert(nodes.LotteryWindow.BHasClass('LotteryCinematicPlaying'));ui.SkipReveal();advance(5);
}
assert.equal(testRuntime.intents.filter(x=>x.action==='lottery_draw').length,3);assert.equal(requests.filter(x=>x.n==='ui_lottery_draw_request'||x.n==='ui_lottery_catalog_sync'||x.n==='ui_lottery_cache_resync').length,0);
assert.equal(logs.filter(x=>x.includes('result_count=10')).length,3);
ui.DrawTen();assert.equal(testRuntime.intents.filter(x=>x.action==='lottery_draw').length,4);
advance(5.1);assert(nodes.LotteryStatus.text.includes('尚未确认'));assert.equal(testRuntime.controls.filter(x=>x[1]==='resync').length,1);
ui.Close();ui.Open();ui.DrawTen();assert.equal(testRuntime.intents.filter(x=>x.action==='lottery_draw').length,4,'same-world close retains unresolved receipt');
fixtureLoading=null;fixtureLoadingListener('survival_loading','state');ui.Close();ui.Open();ui.DrawTen();
assert.equal(testRuntime.intents.filter(x=>x.action==='lottery_draw').length,4,'missing metadata must not retire an unconfirmed paid intent');
fixtureLoading={session_id:'fixture_world_B',setup:{mode_id:'standard'}};fixtureLoadingListener('survival_loading','state');
ui.Close();ui.Open();testRuntime.deliver('map',testFixture.initial_ops,true);
ui.DrawTen();assert.equal(testRuntime.intents.filter(x=>x.action==='lottery_draw').length,5,'new world must not keep previous pending');
ui.Close();
`;
 vm.runInNewContext(suite,{require,console,testRuntime:rt,testModel:Model,testCatalog:C,testFixture:data,testRecords:R,testFields:F},{filename:"actual_compact_lottery_controller_fixture"});
});
console.log(JSON.stringify({status:"PASS_COMPACT_LOTTERY_CACHE_REAL_CONTROLLER_SYNTHETIC_NOT_NATIVE",tests,native_calls:0,network_calls:0,transactions:0,stable_notifications:0}));
