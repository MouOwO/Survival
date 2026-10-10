const fs=require('fs'),vm=require('vm');
let suite=fs.readFileSync('tools/test_lottery_ui.js','utf8').split('ui.Open();assert.equal')[0];
suite=suite.replace('panorama/src/layout/custom_game/lottery_window.xml','panorama/src/layout/custom_game/survival_hud.xml');
suite=suite.replace("vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/lottery_ui.js','utf8'),env);",`
Panel.prototype.Children=function(){return this.children;};
Panel.prototype.MoveChildBefore=function(child,before){this.children.splice(this.children.indexOf(child),1);this.children.splice(this.children.indexOf(before),0,child);};
Panel.prototype.FindChildTraverse=function(id){return nodes[id]||null;};
Panel.prototype.DeleteAsync=function(){this.deleted=true;};
Panel.prototype.SetMovie=function(s){this.movieSource=s;};
Panel.prototype.SetControls=Panel.prototype.SetRepeat=Panel.prototype.SetPlaybackVolume=function(){};
Panel.prototype.Play=function(){this.playing=true;};Panel.prototype.Stop=function(){this.playing=false;};
['reference_windows','ui_snapshot_cache','lottery_scene_transition','lottery_handoff_bb9968eef7','remaining_5d5c1152eb','lottery_cinematic_v1','lottery_ui_remaining_5d5c1152eb'].forEach(function(file){vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/'+file+'.js','utf8'),env);});
`);
suite+=`
root.actuallayoutwidth=1920;root.actuallayoutheight=1080;root.actualuiscale_x=1;root.actualuiscale_y=1;
ui.Open();events.ui_lottery_snapshot(snapshot('map',20));
const n=requests.length;
events.ui_lottery_result({ok:1,request_id:'film1',pool_id:'map',count:10,results:results(10)});
assert(nodes.LotteryWindow.BHasClass('LotteryCinematicPlaying'));
// The existing open-window timer must resize an already playing movie, without
// recreating it, restarting playback or completing the draw early.
const playingMovie=nodes.LotteryCinematicMovie;
for(const [width,height,uiScale] of [[3440,1440,1],[1024,768,1.25],[1600,900,1.5],[962,409,1],[1080,1920,1]]){
 root.actuallayoutwidth=width;root.actuallayoutheight=height;
 root.actualuiscale_x=uiScale;root.actualuiscale_y=uiScale;
 advance(.3);
 assert.equal(nodes.LotteryCinematicMovie,playingMovie,'resize keeps the current movie');
 assert(playingMovie.playing);
 const w=width/uiScale,h=height/uiScale;
 const mw=parseFloat(playingMovie.style.width),mh=parseFloat(playingMovie.style.height);
 assert(mw<=w+.01&&mh<=h+.01,'resized film stays entirely inside the viewport');
 assert(Math.abs(mw-w)<.01||Math.abs(mh-h)<.01,'film fills one axis');
 assert(Math.abs(mw/mh-16/9)<.00001,'no stretching');
}
advance(4.5);assert(nodes.LotteryWindow.BHasClass('LotteryCinematicPlaying'));
assert(!nodes.LotteryTenButton.enabled,'cannot submit another draw during movie');
advance(3);assert(!nodes.LotteryWindow.BHasClass('LotteryCinematicPlaying'));assert.equal(nodes.LotteryItemList.children.length,10);
assert(!requests.slice(n).some(r=>r.n==='ui_lottery_draw_request'),'movie never spends another ticket');
events.ui_lottery_result({ok:1,request_id:'film2',pool_id:'map',count:1,results:results(1)});
assert(nodes.LotteryCinematicMovie.playing);ui.SkipCinematic();assert(!nodes.LotteryCinematicMovie.playing);assert.equal(nodes.LotteryItemList.children.length,1);advance(9);assert.equal(nodes.LotteryItemList.children.length,1);
events.ui_lottery_result({ok:1,request_id:'film3',pool_id:'map',count:10,results:results(10)});ui.Close();assert(!nodes.LotteryCinematicMovie.playing);advance(9);assert(nodes.LotteryWindow.BHasClass('LotteryClosed'));
ui.Open();nodes.LotterySkipAnimation.checked=true;ui.SetSkipAnimation();events.ui_lottery_result({ok:1,request_id:'film4',pool_id:'map',count:10,results:results(10)});assert(!nodes.LotteryWindow.BHasClass('LotteryCinematicPlaying'));assert.equal(nodes.LotteryItemList.children.length,10);
console.log('LOTTERY_FILM_FLOW_PASS: server result -> movie -> real cards; repeat draw blocked; skip/close/skip preference; no extra draw requests.');
`;
vm.runInNewContext(suite,{require:require('node:module').createRequire(require('path').resolve('tools/test_lottery_ui.js')),console,__dirname:require('path').resolve('tools')},{filename:'lottery_film_flow.cjs'});
