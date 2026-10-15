"use strict";
const fs = require("node:fs"), vm = require("node:vm"), path = require("node:path");
// Reuse the existing native-panel fixture, but execute the active production
// controller and cinematic instead of the retired lottery_ui.js implementation.
let suite = fs.readFileSync("tools/test_lottery_ui.js", "utf8").split("ui.Open();assert.equal")[0];
suite = suite.replace("vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/lottery_ui.js','utf8'),env);", `
Panel.prototype.Children=function(){return this.children;};
Panel.prototype.MoveChildBefore=function(child,before){this.children.splice(this.children.indexOf(child),1);this.children.splice(this.children.indexOf(before),0,child);};
Panel.prototype.FindChildTraverse=function(id){return nodes[id]||null;};
Panel.prototype.DeleteAsync=function(){this.deleted=true;};
Panel.prototype.SetMovie=function(s){this.movieSource=s;};
Panel.prototype.SetControls=Panel.prototype.SetRepeat=Panel.prototype.SetPlaybackVolume=function(){};
Panel.prototype.Play=function(){this.playing=true;};Panel.prototype.Stop=function(){this.playing=false;};
const effects=[],owners=[];
config.SurvivalUI.RewardFX={Create(host,options){
 assert.equal(host.id,'RewardTestGW2Content');assert.equal(options.channel,'lottery');
 assert.equal(options.getScale,undefined,'The helper reads the fitted ancestor exactly once');
 const instance={cleared:0,disposed:false,Play(event){assert(!this.disposed);effects.push(event);},Clear(){this.cleared++;},Dispose(){this.disposed=true;}};
 owners.push(instance);return instance;
}};
['reference_windows','ui_snapshot_cache','lottery_scene_transition','lottery_handoff_bb9968eef7','remaining_5d5c1152eb','lottery_cinematic_v1','lottery_ui_remaining_5d5c1152eb'].forEach(function(file){vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/'+file+'.js','utf8'),env);});
`);
suite += `
root.actuallayoutwidth=1920;root.actuallayoutheight=1080;root.actualuiscale_x=1;root.actualuiscale_y=1;
nodes.LotteryMainCanvas.AddClass('LotteryV10');
const content=new Panel('Panel',nodes.LotteryMainCanvas,'RewardTestGW2Content');
content.style.width='1113px';content.style.height='669px';
config.SurvivalPurpleLottery={Apply(){},Content:()=>content,Fit(){config.SurvivalUI.Fit(nodes.LotteryMainCanvas,root,1536,864,{reference:[1536,864]});return true;}};
ui.Open();events.ui_lottery_snapshot(snapshot('map',99));assert.equal(effects.length,0);
function begin(count=1){if(count===10)ui.DrawTen();else ui.DrawSingle();return requests.filter(row=>row.n==='ui_lottery_draw_request').at(-1).p;}
function answer(request,extra={}){events.ui_lottery_result({ok:1,request_id:request.request_id,pool_id:'map',count:request.count,results:results(request.count),snapshot:snapshot('map',99),...extra});}

const normal=begin(10);answer(normal);
assert(nodes.LotteryWindow.BHasClass('LotteryCinematicPlaying'));assert.equal(effects.length,0,'Success waits for the existing film and flip sequence');
advance(7.1);assert.equal(effects.length,0,'The film finishing alone does not cover the card reveal');
advance(2);assert.equal(effects.length,1);assert.equal(effects[0].key,normal.request_id);assert.equal(effects[0].text,'获得 10 件奖励');
assert.equal(effects[0].anchor,nodes.LotteryItemList,'Ten rewards use one central feedback effect');
answer(normal);ui.SkipReveal();advance(2);assert.equal(effects.length,1,'Duplicate packets and repeated skip do not replay');

const skipped=begin();answer(skipped);ui.SkipCinematic();
assert.equal(effects.length,2);assert.equal(effects[1].anchor,nodes.LotteryItemList.children[0]);assert.equal(effects[1].text,'物品0');
advance(10);assert.equal(effects.length,2,'Cancelled film callbacks cannot replay the success');

const buttonSkip=begin();answer(buttonSkip);nodes.LotterySkipReveal.events.onactivate();assert.equal(effects.length,3);
const preferenceDuring=begin();answer(preferenceDuring);nodes.LotterySkipAnimation.checked=true;ui.SetSkipAnimation();assert.equal(effects.length,4);
const preference=begin();answer(preference);assert.equal(effects.length,5,'Skip preference retains a short native success feedback');assert(!nodes.LotteryWindow.BHasClass('LotteryAnimating'));

const failure=begin();answer(failure,{ok:0,error:'lottery_ticket_insufficient'});assert.equal(effects.length,5,'Failed draws have no reward feedback');
const clears=owners.at(-1).cleared;ui.Close();assert(owners.at(-1).cleared>clears);ui.Open();assert.equal(effects.length,5,'Opening existing results does not replay');

const hidden=begin();ui.Close();answer(hidden);advance(10);assert.equal(effects.length,5);ui.Open();assert.equal(effects.length,5);
const reopened=begin();ui.Close();ui.Open();answer(reopened);advance(10);assert.equal(effects.length,5,'A delayed reply from a closed request cannot play after reopening');

nodes.LotterySkipAnimation.checked=false;ui.SetSkipAnimation();
const cancelled=begin();answer(cancelled);ui.Close();advance(10);assert.equal(effects.length,5,'Closing during the film discards its pending feedback');
ui.Open();const reset=begin();answer(reset);ui.CloseResult();advance(10);assert.equal(effects.length,5,'Resetting the draw stage does not celebrate a cancelled presentation');
const mismatch=begin();answer({...mismatch,request_id:'unrelated'});assert.equal(effects.length,5);answer(mismatch);ui.SkipReveal();assert.equal(effects.length,6,'An unrelated result cannot consume the matching request receipt');

const draws=requests.filter(row=>row.n==='ui_lottery_draw_request');
assert(draws.every(row=>Object.keys(row.p).sort().join(',')==='count,pool_id,request_id'),'Feedback never changes purchase payloads');
const beforeDispose=effects.length;ui.Dispose();advance(10);ui.SkipReveal();ui.Open();assert.equal(effects.length,beforeDispose);assert(owners.at(-1).disposed);
console.log('LOTTERY_REWARD_FEEDBACK_PASS: real film and flips, normal/single/ten/skip paths, failed/duplicate/unrelated/hidden responses, reset, cleanup and unchanged purchase payloads');
`;
vm.runInNewContext(suite, { require: require("node:module").createRequire(path.resolve("tools/test_lottery_ui.js")), console, __dirname: path.resolve("tools") }, { filename: "lottery_reward_feedback.cjs" });
