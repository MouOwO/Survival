'use strict';
// Reuse the actual compact cache/controller/GW2 fixture. Only native media events
// and time are simulated; no financial/native runtime acceptance is claimed.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
let text=fs.readFileSync('tools/tests/lottery_preview_controller.test.cjs','utf8');
const candidate=process.env.SURVIVAL_MOVIE_CANDIDATE_DIR&&process.env.SURVIVAL_MOVIE_CANDIDATE_DIR.replaceAll('\\','/');
const scriptDirectory=candidate||'panorama/src/scripts/custom_game',layoutDirectory=candidate||'panorama/src/layout/custom_game';
text=text.replace("const cinemaSource=fs.readFileSync('panorama/src/scripts/custom_game/lottery_cinematic_v1.js','utf8');",'const cinemaSource=fs.readFileSync('+JSON.stringify(scriptDirectory+'/lottery_cinematic_v1.js')+',\'utf8\');');
text=text.replace("const controllerSource=fs.readFileSync('panorama/src/scripts/custom_game/lottery_ui_remaining_5d5c1152eb.js','utf8');",'const controllerSource=fs.readFileSync('+JSON.stringify(scriptDirectory+'/lottery_ui_remaining_5d5c1152eb.js')+',\'utf8\');');
const marker=" assert(names[uri]);if(layoutFailure)return false;";
assert(text.includes(marker));
text=text.replace(marker," for(const pool of ['map','cultivation','dragon_knight','summer','bad_media_probe'])names['file://{resources}/layout/custom_game/lottery_movie_'+pool+'.xml']='lottery_movie_'+pool+'.xml';\n"+marker);
text=text.replace("fs.readFileSync('panorama/src/layout/custom_game/'+names[uri],'utf8')",'fs.readFileSync((names[uri].includes(\'_ab_\')?\'panorama/src/layout/custom_game/\':'+JSON.stringify(layoutDirectory+'/')+')+names[uri],\'utf8\')');
const clockMarker='let uiPreview=reloadController(),film=reloadCinema();';
assert(text.includes(clockMarker));
text=text.replace(clockMarker,String.raw`
const ExistingDate=env.Date;env.Date=class extends ExistingDate {static now(){return now*1000;}};let nativeSyncEnd=false;
const existingRegisterEvent=$.RegisterEventHandler;
$.RegisterEventHandler=function(name,panel,callback){if(!['VideoPlayerInitalized','VideoPlayerEnded'].includes(name))return typeof existingRegisterEvent==='function'?existingRegisterEvent.apply($,arguments):undefined;if(!panel.nativeMovieEvents)panel.nativeMovieEvents={};panel.nativeMovieEvents[name]=callback;if(nativeSyncEnd&&name==='VideoPlayerEnded')callback({});};
function emitMovie(name,panel){panel=panel||nodes.LotteryCinematicMovie;assert(panel&&panel.nativeMovieEvents&&panel.nativeMovieEvents[name]);panel.nativeMovieEvents[name]({});}
`+clockMarker);
text=text.replace('assert(film.PreviewPlayerAB(mode));','if(!film.PreviewPlayerAB(mode))throw Error("AB_START_FAILED "+mode+" "+JSON.stringify(logs.slice(-8)));');
function addCase(name,body){text+='run('+JSON.stringify(name)+','+JSON.stringify(body)+');\n';}
addCase('candidate_four_pools_preview_native_end_and_no_requests',String.raw`
for(const pool of ['map','cultivation','dragon_knight','summer']){
 assertIdleClosed();const before=counts();assert(film.Preview(pool));assertNoDraw();assert.equal(counts(),before);
 const movie=nodes.LotteryCinematicMovie;assert.equal(movie.type,'MoviePanel');assert(movie.movieSource.endsWith('/'+pool+'.webm'));
 emitMovie('VideoPlayerInitalized');advance(7);emitMovie('VideoPlayerEnded');assertIdleClosed();assert(!movie.IsValid());assert.equal(counts(),before);
}
`);
addCase('candidate_bad_preview_passive_updates_no_award_or_request',String.raw`
uiPreview.Open();uiPreview.Close();assertIdleClosed();const before=counts();assert(film.PreviewBufferedDecoderProbe());assertNoDraw();pushSnapshot();assert.equal(counts(),before);
const movie=nodes.LotteryCinematicMovie;emitMovie('VideoPlayerEnded');assertIdleClosed();assert(!movie.IsValid());assert.equal(counts(),before);
emitMovie('VideoPlayerInitalized',movie);emitMovie('VideoPlayerEnded',movie);advance(15);assertIdleClosed();assert.equal(counts(),before);
assert(logs.some(x=>x.includes('reason=ended_before_initialized')&&x.includes('action=return_to_preview_idle')));
`);
addCase('candidate_paid_receipt_failure_shows_existing_result_without_second_draw',String.raw`
uiPreview.Open();pushSnapshot();uiPreview.DrawSingle();const intent=testRuntime.intents.filter(x=>x.action==='lottery_draw').at(-1);assert(intent);
testRuntime.deliver('map',testProjection.receipt_ops.map(op=>({...op,value:op.field===testFields.request_token?intent.request_token:op.value})));
const movie=nodes.LotteryCinematicMovie;assert(movie&&movie.IsValid());const wire=requests.length,intents=testRuntime.intents.length,draws=calls.draw;
emitMovie('VideoPlayerEnded');assert(!movie.IsValid());assert.equal(requests.length,wire);assert.equal(testRuntime.intents.length,intents);assert.equal(calls.draw,draws);
assert(nodes.LotteryConfirm.enabled);assert(nodes.LotteryItemList.children.every(card=>!card.BHasClass('LotteryCardCovered')&&!card.BHasClass('LotteryCardEntering')&&!card.BHasClass('LotteryCardNarrow')));
assert.equal(film.Preview('map'),false,'Unconfirmed existing result remains protected');uiPreview.CloseResult();assert(uiPreview.CanPreviewCinematic());uiPreview.Close();assertIdleClosed();
assert(logs.some(x=>x.includes('reason=ended_before_initialized')&&x.includes('action=return_to_received_results')));
`);
addCase('candidate_synchronous_failure_receipt_race',String.raw`
for(const kind of ['layout','native_end']){
 uiPreview.Open();pushSnapshot();uiPreview.DrawSingle();const intent=testRuntime.intents.filter(x=>x.action==='lottery_draw').at(-1);assert(intent);
 const requestsBefore=requests.length,drawsBefore=calls.draw;
 layoutFailure=kind==='layout';nativeSyncEnd=kind==='native_end';
 testRuntime.deliver('map',testProjection.receipt_ops.map(op=>({...op,value:op.field===testFields.request_token?intent.request_token:op.value})));
 assert.equal(requests.length,requestsBefore);assert.equal(calls.draw,drawsBefore);assert(!nodes.LotteryWindow.BHasClass('LotteryCinematicPlaying'));
 assert(nodes.LotteryConfirm.enabled);assert(nodes.LotteryItemList.children.every(card=>!card.BHasClass('LotteryCardCovered')));
 assert.equal(film.Preview('map'),false,'Synchronous failure still leaves the existing result awaiting confirmation');
 layoutFailure=false;nativeSyncEnd=false;uiPreview.CloseResult();assert(uiPreview.CanPreviewCinematic());uiPreview.Close();assertIdleClosed();
}
`);
addCase('candidate_normal_end_keeps_existing_card_reveal',String.raw`
uiPreview.Open();pushSnapshot();uiPreview.DrawSingle();const intent=testRuntime.intents.filter(x=>x.action==='lottery_draw').at(-1);
testRuntime.deliver('map',testProjection.receipt_ops.map(op=>({...op,value:op.field===testFields.request_token?intent.request_token:op.value})));
emitMovie('VideoPlayerInitalized');advance(7);emitMovie('VideoPlayerEnded');assert(!nodes.LotteryConfirm.enabled,'Normal completion retains ordinary reveal timing');
assert(nodes.LotteryItemList.children.some(card=>card.BHasClass('LotteryCardCovered')));advance(1.7);assert(nodes.LotteryConfirm.enabled);assert(nodes.LotteryItemList.children.every(card=>!card.BHasClass('LotteryCardCovered')));
`);
vm.runInNewContext(text,{require:require('node:module').createRequire(path.resolve('tools/tests/lottery_preview_controller.test.cjs')),console,process},{filename:'candidate_real_controller.cjs'});
