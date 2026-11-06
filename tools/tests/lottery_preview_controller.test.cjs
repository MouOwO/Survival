'use strict';
// Real controller, cache, handoff, GW2 renderer and HUD IDs. Only native panels,
// clocks and media are simulated: this is not evidence that native video plays.
const fs=require('node:fs'),vm=require('node:vm'),path=require('node:path'),assert=require('node:assert/strict');
let loader=fs.readFileSync('tools/test_lottery_updates.cjs','utf8').split('suite+=')[0];
// Reuse the existing numeric transport fixture, actual projection/model and
// static catalogue. Do not accidentally initialize the retired legacy cache:
// its startup retry would be unrelated to (and mask) preview network assertions.
const compact={require:require('node:module').createRequire(path.resolve('tools/test_compact_lottery_cache.cjs')),console,process};
vm.runInNewContext(fs.readFileSync('tools/test_compact_lottery_cache.cjs','utf8').split('function cacheFixture')[0]+';globalThis.testFixtures={runtime,Model,C,F,R,data};',compact);
const transport=compact.testFixtures;
loader=loader.replace("['reference_windows','ui_snapshot_cache','common/lottery_cache'",`config.SurvivalCompactRuntime=testRuntime;config.SurvivalCompactLotteryModel=testModel;config.SurvivalUICatalog=testCatalog;
['reference_windows','ui_snapshot_cache','common/lottery_cache'`);
const rendererSuite=fs.readFileSync('tools/tests/lottery_gw2.test.cjs','utf8');
const match=/const setup=`([\s\S]*?)`;\r?\nvm\.runInNewContext/.exec(rendererSuite);
assert(match,'Use the existing actual-renderer fixture');
const rendererSetup=match[1].split('const realReward=')[0];
const fixture=String.raw`
$.Schedule=function(seconds,cb){const job={at:now+seconds,cb};queue.push(job);return job;};
$.CancelScheduled=function(job){const index=queue.indexOf(job);if(index>=0)queue.splice(index,1);};
let mediaFailure=false,layoutFailure=false;
Panel.prototype.SetControls=Panel.prototype.SetRepeat=Panel.prototype.SetPlaybackVolume=function(){};
Panel.prototype.SetMovie=function(uri){this.movieSource=uri;if(mediaFailure)throw Error('synthetic decoder error');};
Panel.prototype.Play=function(){this.playing=true;};Panel.prototype.Stop=function(){this.playing=false;};
Panel.prototype.BLoadLayout=function(uri){
 const names={'file://{resources}/layout/custom_game/lottery_movie_ab_direct.xml':'lottery_movie_ab_direct.xml','file://{resources}/layout/custom_game/lottery_movie_ab_buffered.xml':'lottery_movie_ab_buffered.xml'};
 assert(names[uri]);if(layoutFailure)return false;
 const text=fs.readFileSync('panorama/src/layout/custom_game/'+names[uri],'utf8');
 assert(/<Panel\s[^>]*>[\s\S]*<MoviePanel\s/.test(text));
 const child=new Panel('MoviePanel',this,'LotteryCinematicMovie');child.movieSource=/src="([^"]+)"/.exec(text)[1];child.playing=true;return true;
};
const commands=[];env.Game={AddCommand:(name,fn)=>commands.push({name,fn}),IsInToolsMode:()=>false};
const cache=config.SurvivalLotteryCache,calls={open:0,close:0,read:0,snapshot:0,draw:0};let cacheNotify;
const subscribe=cache.Subscribe;cache.Subscribe=function(cb){cacheNotify=cb;return subscribe(cb);};
assert.equal(cache.Compact,true,'Exercise the production compact branch');
const getSnapshot=cache.Snapshot,readAck=cache.ReadAck,cacheOpen=cache.Open,cacheClose=cache.Close,cacheDraw=cache.Draw;
cache.Snapshot=function(){calls.snapshot++;return getSnapshot.apply(cache,arguments);};
cache.ReadAck=function(){calls.read++;return readAck.apply(cache,arguments);};
cache.Open=function(){calls.open++;return cacheOpen.apply(cache,arguments);};cache.Close=function(){calls.close++;return cacheClose.apply(cache,arguments);};
cache.Draw=function(){calls.draw++;return cacheDraw.apply(cache,arguments);};
const controllerSource=fs.readFileSync('panorama/src/scripts/custom_game/lottery_ui_remaining_5d5c1152eb.js','utf8');
function reloadController(){vm.runInNewContext(controllerSource,env);return config.SurvivalLottery;}
const cinemaSource=fs.readFileSync('panorama/src/scripts/custom_game/lottery_cinematic_v1.js','utf8');
function reloadCinema(){vm.runInNewContext(cinemaSource,env);return config.LotteryCinematic;}
let uiPreview=reloadController(),film=reloadCinema();uiPreview.Close();
assert(!nodes.LotteryRefreshButton,'The actual HUD/GW2 creates no refresh button');
assert(config.SurvivalPurpleLottery.IsReady());
function counts(){return JSON.stringify({calls,requests:requests.length,intents:testRuntime.intents.length,controls:testRuntime.controls.length});}
let snapshotSerial=0;
function pushSnapshot(tickets){if(tickets===undefined)tickets=50+(++snapshotSerial);const ops=testProjection.initial_ops.map(op=>({...op,value:op.field===testFields.tickets?tickets:op.value}));testRuntime.deliver('map',ops,true);}
function assertIdleClosed(){assert(uiPreview.CanPreviewCinematic());assert(nodes.LotteryWindow.BHasClass('LotteryClosed'));assert.equal(nodes.LotteryWindow.visible,false);assert.equal(config.SurvivalUILayers.Top(),null);}
function assertNoDraw(){assert.equal(nodes.LotterySingleButton.enabled,false);assert.equal(nodes.LotteryTenButton.enabled,false);assert.equal(nodes.LotteryAgain.enabled,false);const before=counts();uiPreview.DrawSingle();uiPreview.DrawTen();uiPreview.DrawAgain();uiPreview.Refresh();uiPreview.Feature('details');uiPreview.SelectPool('summer');uiPreview.CloseInfo();assert.equal(counts(),before);}
`;
function run(name,body){
 const text=rendererSetup+fixture+body;
 const outer=loader+'suite+='+JSON.stringify(text)+';vm.runInNewContext(suite,{require:require("node:module").createRequire(require("path").resolve("tools/test_lottery_ui.js")),console,testRuntime,testModel,testCatalog,testProjection,testFields});';
 vm.runInNewContext(outer,{require:require('node:module').createRequire(path.resolve('tools/tests/lottery_gw2.test.cjs')),console,testRuntime:transport.runtime(),testModel:transport.Model,testCatalog:transport.C,testProjection:transport.data,testFields:transport.F},{filename:name});
 console.log('PREVIEW_CONTROLLER_CASE_PASS '+name);
}
run('closed_without_login_three_modes_no_requests',String.raw`
for(const mode of ['wrapper','direct','buffered']){
 assertIdleClosed();const before=counts();assert(film.PreviewPlayerAB(mode));assert(nodes.LotteryWindow.visible);assertNoDraw();
 assert.equal(counts(),before,'no cache materialization/read/open or event request');
 const movie=nodes.LotteryCinematicMovie;assert(movie.IsValid());assert.equal(movie.type,mode==='wrapper'?'Movie':'MoviePanel');
 assert.equal(film.PreviewPlayerAB('wrapper'),false);assert.equal(film.PreviewDecoderProbe(),false);assert.equal(film.Preview('summer'),false);
 advance(7.2);assert(!movie.IsValid());assertIdleClosed();assert.equal(counts(),before);
}
assert.equal(logs.filter(x=>x.includes('[LOTTERY_MOVIE_AB] stage=begin')).length,3);
const before=calls.open;uiPreview.Open();assert.equal(calls.open,before+1,'normal open still uses the real data path');uiPreview.Close();
`);
run('existing_window_and_passive_cache_notification',String.raw`
uiPreview.Open();pushSnapshot();assert(nodes.LotteryTenButton.enabled);const before=counts();
assert(film.PreviewPlayerAB('buffered'));assertNoDraw();assert.equal(counts(),before);
const reads=calls.read,opens=calls.open,snapshots=calls.snapshot,wire=requests.length;
const movie=nodes.LotteryCinematicMovie;pushSnapshot(43);
assert.equal(calls.read,reads);assert.equal(calls.open,opens);assert.equal(calls.snapshot,snapshots);assert.equal(requests.length,wire);assert.equal(nodes.LotteryCinematicMovie,movie);
advance(7.2);assert(nodes.LotteryWindow.visible);assert.equal(config.SurvivalUILayers.Top(),'lottery');assert(nodes.LotteryTenButton.enabled);
assert.equal(calls.read,reads,'restore materializes locally without read acknowledgement');assert.equal(calls.snapshot,snapshots+1,'coalesced into one cached refresh');assert.equal(requests.length,wire);
assert(nodes.LotteryTicketValue.text.includes('43'));assert(uiPreview.CanPreviewCinematic());uiPreview.Close();
`);
run('closed_passive_update_cancel_skip_failure_and_world_reset',String.raw`
uiPreview.Open();uiPreview.Close();
for(const stop of ['finish','cancel','skip','reset']){
 const before=counts();assert(film.PreviewPlayerAB('direct'));const movie=nodes.LotteryCinematicMovie;pushSnapshot();assert.equal(counts(),before);
 if(stop==='finish')advance(7.2);else if(stop==='cancel')film.Cancel();else if(stop==='skip')nodes.LotteryCinematicSkip.events.onactivate();else cacheNotify('',{reset:true});
 assert(!movie.IsValid());assertIdleClosed();assert.equal(counts(),before);advance(8);assertIdleClosed();
}
layoutFailure=true;assert.equal(film.PreviewPlayerAB('buffered'),false);assertIdleClosed();layoutFailure=false;
mediaFailure=true;const before=counts();assert(film.PreviewDecoderProbe());advance(3.8);assertIdleClosed();assert.equal(counts(),before);mediaFailure=false;
for(const pool of ['map','cultivation','dragon_knight','summer']){const before=counts();assert(film.Preview(pool));film.Cancel();assertIdleClosed();assert.equal(counts(),before);}
`);
run('pending_receipt_result_and_other_modal_reject',String.raw`
uiPreview.Open();pushSnapshot();uiPreview.DrawSingle();assert.equal(calls.draw,1);const before=counts();
assert.equal(film.PreviewPlayerAB('direct'),false);assert.equal(film.PreviewDecoderProbe(),false);assert.equal(counts(),before);
cacheNotify('map',{receipt_waiting:true});assert.equal(film.PreviewPlayerAB('wrapper'),false,'active request survives pending=false receipt wait');assert.equal(calls.draw,1);
const intent=testRuntime.intents.filter(x=>x.action==='lottery_draw').at(-1);
testRuntime.deliver('map',testProjection.receipt_ops.map(op=>({...op,value:op.field===testFields.request_token?intent.request_token:op.value})));
assert.equal(film.PreviewPlayerAB('wrapper'),false,'real result presentation cannot be replaced');advance(8);assert.equal(film.PreviewPlayerAB('wrapper'),false,'unconfirmed result remains protected');
uiPreview.CloseResult();assert(uiPreview.CanPreviewCinematic());uiPreview.Feature('history');assert.equal(film.PreviewPlayerAB('wrapper'),false);uiPreview.CloseInfo();uiPreview.Close();
config.SurvivalUILayers.Open('other_test_modal',new Panel('Panel',root,'OtherTestModal'),()=>{});
const n=counts();assert.equal(film.PreviewPlayerAB('direct'),false);assert.equal(counts(),n);config.SurvivalUILayers.Close('other_test_modal');assertIdleClosed();
`);
run('cached_pool_unready_disposed_and_reload',String.raw`
uiPreview.Open();pushSnapshot();uiPreview.SelectPool('summer');assert(film.PreviewPlayerAB('wrapper'),'local static pool changes have no pending request');film.Cancel();uiPreview.Close();
uiPreview=reloadController();assertIdleClosed();const presenter=config.SurvivalPurpleLottery;config.SurvivalPurpleLottery=null;
const before=counts();assert.equal(film.PreviewPlayerAB('direct'),false);assert.equal(counts(),before);config.SurvivalPurpleLottery=presenter;assertIdleClosed();
assert(film.PreviewPlayerAB('direct'));const old=film;film=reloadCinema();assertIdleClosed();assert.equal(old.PreviewPlayerAB('direct'),false);assert.equal(old.PreviewDecoderProbe(),false);
assert(film.PreviewPlayerAB('wrapper'));uiPreview.Close();assertIdleClosed();advance(8);assertIdleClosed();
assert(film.PreviewPlayerAB('buffered'));uiPreview.Dispose();assert.equal(film.PreviewPlayerAB('direct'),false);assert.equal(nodes.LotteryWindow.visible,false);
uiPreview=reloadController();assertIdleClosed();assert(film.PreviewPlayerAB('wrapper'));uiPreview=reloadController();assertIdleClosed();advance(8);assertIdleClosed();
`);
console.log('LOTTERY_PREVIEW_CONTROLLER_PASS: actual HUD/controller/cache/GW2; local-only entry, coalesced passive updates, transaction/modal/lifetime guards; native frames still unverified');
