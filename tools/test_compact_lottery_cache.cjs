"use strict";
const assert=require("node:assert/strict"),fs=require("node:fs"),vm=require("node:vm"),cp=require("node:child_process");
const Model=require("../panorama/src/scripts/custom_game/common/compact_lottery_model.js"),config={};
vm.runInNewContext(fs.readFileSync("panorama/src/scripts/custom_game/common/ui_static_catalog.js","utf8"),{GameUI:{CustomUIConfig:()=>config}});
const C=config.SurvivalUICatalog,F=Object.fromEntries(C.Data.fields.map(f=>[f.name,f.id])),R=Object.fromEntries(C.Data.records.map(r=>[r.key,r.id]));
const data=JSON.parse(cp.execFileSync(process.env.LUA51||"C:/Program Files/lua/bin/lua5.1.exe",["scripts/vscripts/tests/test_compact_lottery_projection.lua","emit"],{encoding:"utf8"}));
function runtime(){const views={},intents=[],controls=[];let token=50;return {views,intents,controls,Inspect:()=>({ready:true}),CreateView(key,options){const state=views[key]={options,values:{},revision:0,open:false};return {Open(){state.open=true;controls.push([key,"open"]);return {sent:true};},Close(){state.open=false;controls.push([key,"close"]);},Dispose(){state.open=false;},Resync(){controls.push([key,"resync"]);return {sent:true};},SendIntent(action,args){intents.push({key,action,args,request_token:++token});return {sent:true,request_token:token};}};},deliver(pool,ops,full=false){const state=views["lottery:"+pool],ids=[],seen=new Set();for(const op of ops){const row=state.values[op.record]||(state.values[op.record]={});if(op.remove)delete row[op.field];else row[op.field]=op.value;if(!seen.has(op.record)){seen.add(op.record);ids.push(op.record);}}state.options.onCommit({full,revision:++state.revision},ids,(r,f)=>state.values[r]&&state.values[r][f]);}};}
function cacheFixture(){const rt=runtime(),cfg={SurvivalCompactRuntime:rt,SurvivalCompactLotteryModel:Model,SurvivalUICatalog:C},events={},sent=[],env={GameUI:{CustomUIConfig:()=>cfg},GameEvents:{Subscribe(name,fn){events[name]=fn;return name;},Unsubscribe(){},SendCustomGameEventToServer(n,p){sent.push({n,p});}},$:{Msg(){}}};vm.runInNewContext(fs.readFileSync("panorama/src/scripts/custom_game/common/lottery_cache.js","utf8"),env);return {rt,cfg,events,sent,api:cfg.SurvivalLotteryCache};}
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
test("actual loaded controller replays three ten-result cinematics through typed receipts",()=>{
 const rt=runtime();let suite=fs.readFileSync("tools/test_lottery_ui.js","utf8").split("ui.Open();assert.equal")[0];
 suite=suite.replace("vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/lottery_ui.js','utf8'),env);",`
Panel.prototype.Children=function(){return this.children;};
Panel.prototype.MoveChildBefore=function(child,before){this.children.splice(this.children.indexOf(child),1);this.children.splice(this.children.indexOf(before),0,child);};
Panel.prototype.FindChildTraverse=function(id){return nodes[id]||null;};Panel.prototype.DeleteAsync=function(){this.deleted=true;};
Panel.prototype.SetMovie=function(s){this.movieSource=s;};Panel.prototype.SetControls=Panel.prototype.SetRepeat=Panel.prototype.SetPlaybackVolume=function(){};
Panel.prototype.Play=function(){this.playing=true;};Panel.prototype.Stop=function(){this.playing=false;};
config.SurvivalCompactRuntime=testRuntime;config.SurvivalCompactLotteryModel=testModel;config.SurvivalUICatalog=testCatalog;
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
assert.equal(logs.filter(x=>x.includes('result_count=10')).length,3);ui.Close();
`;
 vm.runInNewContext(suite,{require,console,testRuntime:rt,testModel:Model,testCatalog:C,testFixture:data,testRecords:R,testFields:F},{filename:"actual_compact_lottery_controller_fixture"});
});
console.log(JSON.stringify({status:"PASS_COMPACT_LOTTERY_CACHE_REAL_CONTROLLER_SYNTHETIC_NOT_NATIVE",tests,native_calls:0,network_calls:0,transactions:0,stable_notifications:0}));
