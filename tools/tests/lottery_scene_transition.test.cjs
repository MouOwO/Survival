// Exercise real selection/cache/resize/close paths, not a replacement carousel.
const fs = require('fs'), vm = require('vm');
const fixtureRequire = require('node:module').createRequire(require('path').resolve('tools/test_lottery_ui.js'));
const builder = {require: fixtureRequire};
vm.runInNewContext(fs.readFileSync('tools/test_lottery_updates.cjs', 'utf8').split('suite+=')[0] +
    '\nglobalThis.setup = suite;', builder);
let suite = builder.setup;
suite += String.raw`
const pools=['map','cultivation','dragon_knight','summer'];
root.actuallayoutwidth=1600;root.actuallayoutheight=900;
root.actualuiscale_x=root.actualuiscale_y=1;
ui.Open();events.ui_lottery_snapshot(snapshot('map'));
const track=nodes.LotterySceneTrack, canvas=nodes.LotteryMainCanvas;
function fade(){return ['LotteryPoolFadeA','LotteryPoolFadeB'].filter(c=>canvas.BHasClass(c));}
assert.equal(track.style.transform,'translate3d(0px,0px,0px)');
assert.equal(track.style.transitionDuration,'0s','opening snaps to the selected page');
assert.equal(fade().length,0,'opening does not hide already visible text');
advance(.31); // Complete the UI's existing one-time background prefetch.
for(let i=1;i<pools.length;i++){
 const cached=snapshot(pools[i]);cached.snapshot_scope='cache';cached.cache_sequence=i;
 events.ui_lottery_snapshot(cached);
}
const requestStart=requests.length;
ui.SelectPool('summer');
assert.equal(track.style.transform,'translate3d(-4800px,0px,0px)','jump crosses all intermediate pages');
assert.equal(track.style.transitionDuration,'0.2s','three pages still arrive within 0.2 seconds');
assert.equal(fade().length,1);
const firstFade=fade()[0];
advance(.1); // Refresh during the 200ms transition; must not restart the fade/slide.
events.ui_lottery_snapshot(snapshot('summer',31));
assert(nodes.LotteryTicketValue.text.includes('31'));
ui.SelectPool('summer');
assert.equal(fade()[0],firstFade,'duplicate selection / data refresh preserves the animation');
assert.equal(track.style.transitionDuration,'0.2s');
ui.SelectPool('cultivation');
assert.equal(track.style.transform,'translate3d(-1600px,0px,0px)','rapid reversal targets the requested page');
assert.equal(track.style.transitionDuration,'0.2s','reversal does not queue multiple transitions');
assert.equal(fade().length,1);assert.notEqual(fade()[0],firstFade,'a new selection restarts the native fade');
ui.SelectPool('dragon_knight');
assert.equal(track.style.transform,'translate3d(-3200px,0px,0px)');
assert.equal(track.style.transitionDuration,'0.2s','adjacent and distant switches have the same duration');
assert.equal(fade()[0],firstFade);
assert(requests.slice(requestStart).every(r=>r.p.snapshot_scope==='read'),'switching only acknowledges reads');
assert.equal(requests.filter(r=>r.n==='ui_lottery_draw_request').length,0,'animation never draws or grants');
const queued=queue.length;
for(let i=0;i<20;i++)config.LotterySceneTransition.Select(i%2?'map':'summer');
assert.equal(queue.length,queued,'native slide/fade add no timers or frame loops');
ui.Close();
assert.equal(fade().length,0,'close cancels the fade immediately');
assert.equal(track.style.transitionDuration,'0s');
ui.Open();
assert.equal(fade().length,0,'reopen has no leftover animation');
assert.equal(track.style.transform,'translate3d(-3200px,0px,0px)','reopen restores the actual selected pool');
ui.SelectPool('summer');
assert.equal(track.style.transitionDuration,'0.2s');
for(const [w,h,s] of [[3440,1440,1],[1024,768,1.25],[1600,900,1.5],[1080,1920,1]]){
 root.actuallayoutwidth=w;root.actuallayoutheight=h;root.actualuiscale_x=root.actualuiscale_y=s;
 advance(.3);
 assert.equal(track.style.width,(w/s*4)+'px');
 assert.equal(track.style.height,(h/s)+'px');
 for(const id of pools)assert.equal(nodes['LotteryScenePage_'+id].style.width,(w/s)+'px','each page fills one viewport');
 assert(Math.abs(parseFloat(track.style.transform.slice(12))+3*w/s)<.0001,'resize never leaves a seam or partial page');
}
config.LotterySceneTransition.Resize(NaN,10);
assert.equal(track.style.width,'4320px','invalid/unmeasured viewport cannot corrupt the strip');
ui.SelectPool('map');
ui.Close();
vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/lottery_scene_transition.js','utf8'),env);
ui.Open();assert.equal(fade().length,0,'module reload clears the previous fade');
const oldCanvas=nodes.LotteryMainCanvas,oldTrack=nodes.LotterySceneTrack;
nodes.LotteryMainCanvas=null;nodes.LotterySceneTrack=null;
config.LotterySceneTransition.Select('summer');config.LotterySceneTransition.Close();
nodes.LotteryMainCanvas=oldCanvas;nodes.LotterySceneTrack=oldTrack;
ui.Close();
// Guard native timing and XML hierarchy; VM styles cannot emulate GPU interpolation.
const style=fs.readFileSync('panorama/src/styles/custom_game/lottery_fullscreen_v2.css','utf8');
assert(/#LotteryWindow #LotterySceneTrack[^}]*transition-property:transform;[^}]*transition-duration:0[.]2s;[^}]*transition-timing-function:linear;/.test(style));
for(const name of ['LotteryPoolFadeA','LotteryPoolFadeB']){
 assert(new RegExp('#LotteryMainCanvas\\.'+name+'[^}]*animation-duration:0[.]2s;').test(style));
 assert(new RegExp("@keyframes '"+name+"' \\{ 0% \\{ opacity:0; \\} 100% \\{ opacity:1; \\}").test(style));
}
const sceneMarkup=xml.split('<Panel id="LotterySceneTrack"')[1].split('</Panel>')[0];
assert.deepEqual([...sceneMarkup.matchAll(/id="LotteryScenePage_([^"]+)"/g)].map(m=>m[1]),pools,'all backgrounds are siblings in the same moving layer');
console.log('LOTTERY_SCENE_TRANSITION_PASS: cached clicks, 200ms jumps/reversal/fades, duplicate snapshots, no timers/transactions, close/reload, four viewport sizes');
`;
vm.runInNewContext(suite, {require: fixtureRequire, console}, {filename: 'lottery_scene_transition_integration.cjs'});
