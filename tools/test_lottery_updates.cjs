const fs=require('fs'),vm=require('vm'),path=require('path');
let suite=fs.readFileSync('tools/test_lottery_ui.js','utf8').split('ui.Open();assert.equal')[0];
suite=suite.replace("panorama/src/layout/custom_game/lottery_window.xml","panorama/src/layout/custom_game/survival_hud.xml");
suite=suite.replace("vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/lottery_ui.js','utf8'),env);",`Panel.prototype.Children=function(){return this.children;};
['ui_snapshot_cache','lottery_handoff_bb9968eef7','remaining_5d5c1152eb','lottery_ui_remaining_5d5c1152eb'].forEach(function(file){vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/'+file+'.js','utf8'),env);});`);
suite+=`
function updated(pool,rev){const x=snapshot(pool);x.selected_pool.revision=rev;x.selected_pool.update_unread=true;x.selected_pool.notice_unread=true;x.selected_pool.update_notice={title:'奖励更新公告',summary:'新奖池'};x.pools=[x.selected_pool];x.items=['n','sr','ur','r','ssr'].map(q=>({id:q,name:q,quality:q,icon:'item_blink'}));return x;}
root.actuallayoutwidth=1920;root.actuallayoutheight=1080;root.actualuiscale_x=1.15;root.actualuiscale_y=1.15;
nodes.LotteryWindow.actuallayoutwidth=0;nodes.LotteryWindow.actuallayoutheight=0;
ui.Open();assert.equal(requests.at(-1).p.read_action,'visit');
const firstScale=nodes.LotteryMainCanvas.style.transform;
assert.equal(firstScale,'scale3d('+Math.min(1920/1.15/1672,1080/1.15/941)+','+Math.min(1920/1.15/1672,1080/1.15/941)+',1)');
assert.equal(nodes.LotteryMainCanvas.style.opacity,'1');
nodes.LotteryWindow.actuallayoutwidth=1920;nodes.LotteryWindow.actuallayoutheight=1080;nodes.LotteryWindow.actualuiscale_x=1.15;nodes.LotteryWindow.actualuiscale_y=1.15;
advance(.3);assert.equal(nodes.LotteryMainCanvas.style.transform,firstScale,'first frame and later frame must use the same viewport');
events.ui_lottery_snapshot(updated('map','v1'));
assert(nodes.LotteryInfoOverlay.BHasClass('LotteryInfoHidden'),'updates must only show a red dot');
assert(nodes.LotteryUpdateDot.visible);
assert(nodes.LotteryPoolTabs.children.every(t=>!t.children.some(c=>c.BHasClass('LotteryUpdateDot'))),'chest tabs must not contain dots');
assert.equal(requests.at(-1).p.read_action,'visit');
ui.CloseInfo();ui.SelectPool('map');events.ui_lottery_snapshot(updated('map','v1'));
assert(nodes.LotteryInfoOverlay.BHasClass('LotteryInfoHidden'),'same notice must not reopen');
ui.Feature('details');assert.equal(requests.at(-1).p.read_action,'details');
assert(nodes.LotteryInfoTabs.children.every(t=>!t.children.some(c=>c.BHasClass('LotteryUpdateDot'))),'detail tabs must not contain dots');
assert.deepEqual(nodes.LotteryInfoList.children.map(p=>p.children.find(c=>c.BHasClass('LotteryDetailCopy')).children[0].text.split(' · ')[0]),['UR','SSR','SR','R','N']);
const read=updated('map','v1');read.selected_pool.update_unread=false;read.snapshot_scope='read';events.ui_lottery_snapshot(read);assert(!nodes.LotteryUpdateDot.visible);
ui.CloseInfo();ui.SelectPool('map');events.ui_lottery_snapshot(updated('map','v2'));assert(nodes.LotteryInfoOverlay.BHasClass('LotteryInfoHidden'));assert(nodes.LotteryUpdateDot.visible);
ui.CloseInfo();ui.SelectPool('summer');events.ui_lottery_snapshot(updated('summer','v1'));assert.equal(requests.at(-1).p.pool_id,'summer');
ui.Close();events.ui_lottery_snapshot(updated('summer','v2'));assert(nodes.LotteryInfoOverlay.BHasClass('LotteryInfoHidden'));
ui.Open();
['cultivation','dragon_knight','summer','map'].forEach(id=>{
 ui.SelectPool(id);assert(nodes.LotteryMainCanvas.style.backgroundImage.includes(id==='map'?'lottery_handoff_v1/scene.png':'lottery_pool_scenes_v1/'+id+'.png'),'background changes immediately on selection');
 events.ui_lottery_snapshot(updated(id,'v3'));
});
ui.Close();root.actuallayoutwidth=0;root.actuallayoutheight=0;nodes.LotteryWindow.actuallayoutwidth=0;nodes.LotteryWindow.actuallayoutheight=0;
ui.Open();assert.equal(nodes.LotteryMainCanvas.style.opacity,'0','unmeasured canvas stays hidden instead of flashing at default scale');
root.actuallayoutwidth=2560;root.actuallayoutheight=1440;root.actualuiscale_x=1.5;root.actualuiscale_y=1.5;
config.LotteryHandoff.Ready();assert.equal(nodes.LotteryMainCanvas.style.opacity,'1');ui.Close();
assert(!requests.some(r=>r.p.read_action==='notice'),'no announcement acknowledgement is sent');
console.log('LOTTERY_UPDATES_PASS: details-only dots, four backgrounds, stable first-open scale, unmeasured viewport guard, independent read revisions, quality order');
for(const [pool,seq] of [['map',1],['summer',2]]){const data=updated(pool,'cache-v1');data.snapshot_scope='cache';data.cache_sequence=seq;events.ui_lottery_snapshot(data);}
ui.Open();const beforeCache=requests.length;ui.SelectPool('summer');ui.SelectPool('map');
assert(requests.slice(beforeCache).every(r=>r.p.snapshot_scope==='read'),'cached switches only acknowledge reading, never fetch page data');
events.ui_lottery_snapshot({snapshot_scope:'cache_patch',selected_pool_id:'map',cache_sequence:3,base_sequence:1,chunk:1,chunks:1,changes:[{path:['selected_pool','tickets'],value:999}]});
assert(nodes.LotteryTicketValue.text.includes('999'),'delta refreshes current pool');
console.log('LOTTERY_CACHE_PASS: prefetched tab switching without data fetch and incremental ticket update');
ui.CloseInfo();ui.SelectPool('map');
let wallClock=2000;EmbeddedDate.now=()=>wallClock*1000;
function timed(pool,stamp){const x=updated(pool,'time-'+stamp);x.selected_pool.updated_at=stamp;return x;}
events.ui_lottery_snapshot(timed('map',1900));
// Clear the earlier revision-only test's local record to model first use.
Object.keys(config.SurvivalLotteryDetailReads).forEach(k=>delete config.SurvivalLotteryDetailReads[k]);
events.ui_lottery_snapshot(timed('map',1900));assert(nodes.LotteryUpdateDot.visible);
ui.Feature('details');assert(!nodes.LotteryUpdateDot.visible,'opening details clears immediately, before HTTP acknowledgement');
ui.CloseInfo();events.ui_lottery_snapshot(timed('map',1900));assert(!nodes.LotteryUpdateDot.visible,'stale unread flag cannot restore the dot');
events.ui_lottery_snapshot(timed('map',2000));assert(!nodes.LotteryUpdateDot.visible,'equal timestamp is already read');
events.ui_lottery_snapshot(timed('map',2001));assert(nodes.LotteryUpdateDot.visible,'later pool update is unread');
wallClock=2002;ui.Feature('details');ui.CloseInfo();assert(!nodes.LotteryUpdateDot.visible);
ui.SelectPool('summer');events.ui_lottery_snapshot(timed('summer',1900));assert(nodes.LotteryUpdateDot.visible,'each chest has its own viewing time');
ui.Feature('details');ui.CloseInfo();ui.SelectPool('map');events.ui_lottery_snapshot(timed('map',2001));assert(!nodes.LotteryUpdateDot.visible);
const savedReads=config.SurvivalLotteryDetailReads;
vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/lottery_ui_remaining_5d5c1152eb.js','utf8'),env);
assert.strictEqual(config.SurvivalLotteryDetailReads,savedReads,'panel reload preserves local viewing times');
config.SurvivalLottery.Open();events.ui_lottery_snapshot(timed('map',2001));assert(!nodes.LotteryUpdateDot.visible);
console.log('LOTTERY_READ_TIME_PASS: immediate hide, stale response, equal/new timestamp, pool isolation, UI reload');
`;
vm.runInNewContext(suite,{require:require('module').createRequire(path.resolve('tools/test_lottery_ui.js')),console},{filename:'lottery_updates_behavior.cjs'});
