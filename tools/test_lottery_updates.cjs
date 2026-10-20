const fs=require('fs'),vm=require('vm'),path=require('path');
let suite=fs.readFileSync('tools/test_lottery_ui.js','utf8').split('ui.Open();assert.equal')[0];
suite=suite.replace("panorama/src/layout/custom_game/lottery_window.xml","panorama/src/layout/custom_game/survival_hud.xml");
suite=suite.replace("vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/lottery_ui.js','utf8'),env);",`Panel.prototype.Children=function(){return this.children;};
Panel.prototype.DeleteAsync=function(){this.deleted=true;if(this.parent)this.parent.children=this.parent.children.filter(c=>c!==this);};
Panel.prototype.MoveChildBefore=function(child,before){this.children.splice(this.children.indexOf(child),1);this.children.splice(this.children.indexOf(before),0,child);};
// The XML fixture stores named panels in a flat index.
Panel.prototype.FindChildTraverse=function(id){return nodes[id]||null;};
['reference_windows','ui_snapshot_cache','common/lottery_cache','lottery_scene_transition','lottery_handoff_bb9968eef7','remaining_5d5c1152eb','lottery_ui_remaining_5d5c1152eb'].forEach(function(file){vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/'+file+'.js','utf8'),env);});`);
// These are isolated business tests. Their presentation stub delegates to the
// actual shared fit primitive; the production V10 renderer has its own suite.
suite+=`config.SurvivalPurpleLottery={Version:'lottery_current_20261018',Owns(owner){return owner===root;},IsAlive(){return true;},IsReady(){return true;},Open(){},Close(){},Apply:function(){},Fit:function(){
const viewport=config.LotteryHandoff.Viewport(),canvas=nodes.LotteryMainCanvas;
if(!viewport){canvas.style.opacity='0';return false;}
config.SurvivalUI.Fit(canvas,root,1672,941,{reference:[1672,941]});canvas.style.backgroundImage='none';canvas.style.opacity='1';return true;
}};`;
suite+=`
function updated(pool,rev){const x=snapshot(pool);x.selected_pool.revision=rev;x.selected_pool.update_unread=true;x.selected_pool.notice_unread=true;x.selected_pool.update_notice={title:'奖励更新公告',summary:'新奖池'};x.pools=[x.selected_pool];x.items=['n','sr','ur','r','ssr'].map(q=>({id:q,name:q,quality:q,icon:'item_blink'}));return x;}
root.actuallayoutwidth=1920;root.actuallayoutheight=1080;root.actualuiscale_x=1.15;root.actualuiscale_y=1.15;
nodes.LotteryWindow.actuallayoutwidth=0;nodes.LotteryWindow.actuallayoutheight=0;
ui.Open();assert(!requests.some(r=>r.n==='ui_lottery_snapshot_request'),'opening uses login cache; it never requests a page');assert(!requests.some(r=>r.n==='ui_lottery_read_ack'&&!r.p.revision),'unknown revisions are never marked read');
const firstScale=nodes.LotteryMainCanvas.style.transform;
assert.equal(firstScale,'scale3d('+Math.min(1920/1.15/1672,1080/1.15/941)+','+Math.min(1920/1.15/1672,1080/1.15/941)+',1)');
assert.equal(nodes.LotteryMainCanvas.style.opacity,'1');
nodes.LotteryWindow.actuallayoutwidth=1920;nodes.LotteryWindow.actuallayoutheight=1080;nodes.LotteryWindow.actualuiscale_x=1.15;nodes.LotteryWindow.actualuiscale_y=1.15;
advance(.3);assert.equal(nodes.LotteryMainCanvas.style.transform,firstScale,'first frame and later frame must use the same viewport');
events.ui_lottery_snapshot(updated('map','v1'));
assert(nodes.LotteryInfoOverlay.BHasClass('LotteryInfoHidden'),'updates must only show a red dot');
assert(nodes.LotteryUpdateDot.visible);
assert(nodes.LotteryPoolTabs.children.every(t=>!t.children.some(c=>c.BHasClass('LotteryUpdateDot'))),'chest tabs must not contain dots');
assert.equal(requests.at(-1).n,'ui_lottery_read_ack');assert.equal(requests.at(-1).p.read_action,'visit');
ui.CloseInfo();ui.SelectPool('map');events.ui_lottery_snapshot(updated('map','v1'));
assert(nodes.LotteryInfoOverlay.BHasClass('LotteryInfoHidden'),'same notice must not reopen');
ui.Feature('details');assert.equal(requests.at(-1).n,'ui_lottery_read_ack');assert.equal(requests.at(-1).p.read_action,'details');
assert(nodes.LotteryInfoTabs.children.every(t=>!t.children.some(c=>c.BHasClass('LotteryUpdateDot'))),'detail tabs must not contain dots');
assert.deepEqual(nodes.LotteryInfoList.children.map(p=>p.children.find(c=>c.BHasClass('LotteryDetailCopy')).children[0].text.split(' · ')[0]),['UR','SSR','SR','R','N']);
const read=updated('map','v1');read.selected_pool.update_unread=false;read.snapshot_scope='read';events.ui_lottery_snapshot(read);assert(!nodes.LotteryUpdateDot.visible);
ui.CloseInfo();ui.SelectPool('map');events.ui_lottery_snapshot(updated('map','v2'));assert(nodes.LotteryInfoOverlay.BHasClass('LotteryInfoHidden'));assert(nodes.LotteryUpdateDot.visible);
ui.CloseInfo();ui.SelectPool('summer');events.ui_lottery_snapshot(updated('summer','v1'));assert.equal(requests.at(-1).p.pool_id,'summer');
ui.Close();events.ui_lottery_snapshot(updated('summer','v2'));assert(nodes.LotteryInfoOverlay.BHasClass('LotteryInfoHidden'));
ui.Open();
['cultivation','dragon_knight','summer','map'].forEach(id=>{
 ui.SelectPool(id);assert.equal(nodes.LotteryMainCanvas.style.backgroundImage,'none','pool switching preserves shared window background');assert(nodes.LotterySceneBackground.BHasClass('LotteryScene_'+id),'full-screen scene changes immediately on selection');assert.equal(['map','cultivation','dragon_knight','summer'].filter(k=>nodes.LotterySceneBackground.BHasClass('LotteryScene_'+k)).length,1,'only selected scene is active');
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
assert(requests.slice(beforeCache).every(r=>r.n==='ui_lottery_read_ack'),'cached switches only acknowledge reading, never fetch page data');
events.ui_lottery_snapshot({snapshot_scope:'cache_patch',selected_pool_id:'map',cache_sequence:3,base_sequence:1,chunk:1,chunks:1,changes:[{path:['selected_pool','tickets'],value:999}]});
assert(nodes.LotteryTicketValue.text.includes('999'),'delta refreshes current pool');
console.log('LOTTERY_CACHE_PASS: login-cached tab switching without data fetch and incremental ticket update');
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

// A rejected background refresh preserves the last valid local display. It
// revokes authority until a replacement arrives; opening the UI never retries.
const currentUI=config.SurvivalLottery;
currentUI.CloseInfo();
const beforeFailure=requests.length;
events.ui_lottery_snapshot({selected_pool_id:'map',ok:false,error:'archive_config_mismatch'});
currentUI.Feature('details');
assert.equal(nodes.LotteryInfoList.children.filter(c=>c.BHasClass('LotteryDetailRow')).length,5,'a failed refresh retains the verified local rewards');
assert(!/正在加载|正在切换/.test(nodes.LotteryInfoRules.text||''),'local details never fall back to a loading page');
assert(!nodes.LotterySingleButton.enabled,'failed authority cannot enable drawing');
assert.equal(config.SurvivalLotteryCache.IsAuthoritative('map'),false);
assert(requests.slice(beforeFailure).some(r=>r.n==='ui_lottery_cache_resync'&&r.p.pool_id==='map'),'recovery runs through the background cache transport');
currentUI.CloseInfo();const beforeReopen=requests.length;currentUI.Feature('details');
assert.equal(nodes.LotteryInfoList.children.filter(c=>c.BHasClass('LotteryDetailRow')).length,5,'reopening still displays the valid local catalogue');
assert(!requests.slice(beforeReopen).some(r=>r.n==='ui_lottery_snapshot_request'||r.n==='ui_lottery_cache_resync'),'opening does not fetch or retry');
events.ui_lottery_snapshot(timed('map',2001));
assert.equal(nodes.LotteryInfoList.children.length,5,'a successful push restores authoritative data');
assert.equal(config.SurvivalLotteryCache.IsAuthoritative('map'),true);
currentUI.SelectPool('summer');
const summerFailure=requests.length;
events.ui_lottery_snapshot({selected_pool_id:'summer',ok:false,error:'archive_config_mismatch'});
assert.equal(nodes.LotteryInfoList.children.filter(c=>c.BHasClass('LotteryDetailRow')).length,5,'a failed detail-pool refresh preserves that pool local rewards');
assert.equal(config.SurvivalLotteryCache.IsAuthoritative('summer'),false);
assert(requests.slice(summerFailure).some(r=>r.n==='ui_lottery_cache_resync'&&r.p.pool_id==='summer'));
currentUI.SelectPool('map');
events.ui_lottery_snapshot({...timed('map',2001),snapshot_scope:'cache',cache_sequence:4});
assert.equal(nodes.LotteryInfoList.children.length,5,'a different valid tab is unaffected');
assert.equal(config.SurvivalLotteryCache.IsAuthoritative('map'),true);
console.log('LOTTERY_REFRESH_RECOVERY_PASS: retained catalogue, authority guard, background recovery, reopen without fetching and independent detail tabs');
currentUI.CloseInfo();currentUI.SelectPool('summer');events.ui_lottery_snapshot(timed('summer',2001));
let ticketPool=null;
config.SurvivalCommerceView={OpenTicketPurchase:pool=>{ticketPool=pool.id;return true;}};
currentUI.Feature('purchase');assert.equal(ticketPool,'summer');
config.SurvivalCommerceView.OpenTicketPurchase=()=>false;
currentUI.Feature('purchase');assert(nodes.LotteryStatus.text.includes('抽奖券购买暂未开放'));
delete config.SurvivalCommerceView;
console.log('LOTTERY_TICKET_ENTRY_PASS: special-pool routing and visible unavailable message');
`;
// Optional read-only HTTP fixture: verify the actual server payload through the
// same Panorama presenter, without issuing a draw, exchange or purchase.
if(process.env.LOTTERY_SNAPSHOT_FIXTURE){
suite+=`
const live=JSON.parse(fs.readFileSync(${JSON.stringify(path.resolve(process.env.LOTTERY_SNAPSHOT_FIXTURE))},'utf8'));
assert.equal(live.ok,true);assert.equal(live.snapshots.length,4);
const liveUI=config.SurvivalLottery;liveUI.CloseInfo();
live.snapshots.forEach((data,index)=>{
 assert.equal(data.items.length,88,'existing enabled rewards must remain complete');
 events.ui_lottery_snapshot({...data,snapshot_scope:'cache',cache_sequence:100+index});
 liveUI.SelectPool(data.selected_pool_id);liveUI.Feature('details');
 assert.equal(nodes.LotteryInfoList.children.length,data.items.length);
 assert(nodes.LotterySelectedName.text.length>0);
 assert(!nodes.LotteryInfoRules.text.includes('加载失败'));
 liveUI.CloseInfo();
});
assert(!requests.some(r=>r.n==='ui_lottery_draw_request'||r.n==='ui_lottery_exchange_request'));
console.log('LOTTERY_LIVE_SNAPSHOT_PASS: 4 pools, 88 real rewards each, no draw/exchange/purchase');
`;
}
suite+=`
config.SurvivalLottery.CloseInfo();config.SurvivalLottery.Open();
const closeStyles=fs.readFileSync('panorama/src/styles/custom_game/lottery_handoff_bb9968eef7.css','utf8');
assert(/#LotteryMainCanvas #LotteryCloseButton \{[^}]*align:right top/.test(closeStyles),'close button must stay inside the resized canvas');
assert(/#LotteryMainCanvas #LotteryCloseButton \\.LHCloseGlyph \{[^}]*visibility:visible/.test(closeStyles),'override the old style that hides close labels');
assert(nodes.LotteryCloseButton.enabled && nodes.LotteryCloseButton.hittest);
assert.equal(nodes.LotteryCloseButton.children[0].text,'×');
assert.equal(nodes.LotteryCloseButton.hittestchildren,false);
nodes.LotteryCloseButton.events.onactivate();
assert(nodes.LotteryWindow.BHasClass('LotteryClosed'));
console.log('LOTTERY_CLOSE_PASS: visible glyph, enabled button and close callback');
`;
vm.runInNewContext(suite,{require:require('module').createRequire(path.resolve('tools/test_lottery_ui.js')),console},{filename:'lottery_updates_behavior.cjs'});
