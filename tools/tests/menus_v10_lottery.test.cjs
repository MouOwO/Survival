const fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
const loader=fs.readFileSync('tools/test_lottery_updates.cjs','utf8').split('suite+=')[0];
const setup=`
Object.defineProperty(Panel.prototype,'paneltype',{get(){return this.type;}});
Panel.prototype.SetParent=function(parent){if(this.parent)this.parent.children=this.parent.children.filter(c=>c!==this);this.parent=parent;parent.children.push(this);this.reparented=true;};
Panel.prototype.DeleteAsync=function(){this.deleted=true;if(this.parent)this.parent.children=this.parent.children.filter(c=>c!==this);for(const c of [...this.children])c.DeleteAsync();};
Panel.prototype.IsValid=function(){return !this.deleted;};
Panel.prototype.SetScaling=function(value){this.scaling=value;};
// Model native lookup losing reparented compiled-layout descendants. Cached
// authoritative controls must remain usable; the browser's global ID map must
// not be able to conceal this failure.
Panel.prototype.FindChildTraverse=function(id){if(this.reparented)return null;if(this.id===id)return this;for(const c of this.children){if(c.reparented)continue;if(c.id===id)return c;const hit=c.FindChildTraverse(id);if(hit)return hit;}return null;};
Panel.prototype.GetPositionWithinWindow=function(){let x=0,y=0;for(let p=this;p;p=p.parent){let v=String(p.style.position||'0px 0px 0px').split(' ');x+=parseFloat(v[0])||0;y+=parseFloat(v[1])||0;}return{x,y};};
root.actuallayoutwidth=1920;root.actuallayoutheight=1080;root.actualuiscale_x=1;root.actualuiscale_y=1;
for(const name of ['archive_v10_data','common/tooltip_dismiss','common/menu_v10'])vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/'+name+'.js','utf8'),env);
// Reload the same business controller now that the shared shell is available.
vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/lottery_ui_remaining_5d5c1152eb.js','utf8'),env);
vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/menu_purple.js','utf8'),env);
const current=config.SurvivalLottery,presentation=config.SurvivalPurpleLottery;
const view=config.SurvivalMenuV10.Entries().find(e=>e.panel===nodes.LotteryMainCanvas);
assert(view);assert.equal(view.shell,null,'one shell; no separate nested modal');
assert.equal(view.panel.style.width,'1672px');assert.equal(view.panel.style.height,'941px');
assert.equal(nodes.LotteryInfoOverlay.parent,view.detailLayer);
assert.equal(nodes.LotteryCelestialFooter.parent,view.actions);
assert.equal(root.FindChildTraverse('LotteryHeroCopy'),null,'native-style traversal cannot find moved controls');
assert.equal(nodes.LotteryCelestialHeader.style.visibility,'collapse');assert.equal(nodes.LotteryPoolTabs.style.visibility,'collapse');
current.Open();assert(view.IsOpen());
function data(pool='map',tickets=20){const d=snapshot(pool,tickets);d.pools=['map','summer'].map(id=>({id,display_name:id}));d.items=Array.from({length:17},(_,i)=>({id:'r'+i,name:'正式奖励'+i,quality:i%2?'sr':'n',icon:'item_blink',description:'效果'+i,owned_count:i===0?undefined:i===1?0:2,max_owned:i===2?5:undefined}));return d;}
events.ui_lottery_snapshot(data());
assert(view.title.text.includes('地图'));assert.equal(view.resources[0].text.text,'20');assert.equal(view.resources[1].text.text,'10');
assert.equal(view.resources[0].icon.image,config.ArchiveV10Data.assets.ticket.file);
assert.equal(view.sidebar.children.filter(c=>c.BHasClass('MenuV10Button')).length,2);
current.Feature('details');assert.equal(nodes.LotteryInfoOverlay.style.position,'407px 213px 0px');
assert.equal(config.SurvivalUILayers.Top(),'lottery_info','Escape closes only the right details view');
assert.equal(nodes.LotteryInfoDialog.style.width,'1113px');assert.equal(nodes.LotteryInfoDialog.style.transform,'none');
assert.equal(nodes.LotteryCelestialFooter.style.visibility,'collapse');
const cells=nodes.LotteryInfoList.children.filter(c=>c.BHasClass('LotteryDetailRow'));
assert.equal(cells.length,17);assert(cells.every(c=>c.__menuV10Cell),'all cells reuse approved V10 components');
assert.equal(cells[0].__menuV10Cell.count.text,'0','quality sorting keeps the real zero quantity');
assert(cells.some(c=>c.__menuV10Cell.count.text==='—'),'unknown quantity is not zero');
assert(cells.some(c=>c.__menuV10Cell.count.text==='2/5'),'use only real max-owned');
const first=cells[0],before=requests.length;first.events.onmouseover();assert.equal(requests.length,before,'tooltips only read');
const tip=view.detailLayer.children.find(c=>c.BHasClass('MenuV10Tooltip'));assert(tip&&tip.visible);first.events.onmouseout();assert(!tip.visible);
const retiredModal=config.SurvivalUI.ModalManager.Get('lottery_info');assert(!retiredModal||!retiredModal.IsOpen(),'details never open the retired window');
const mainTitle=nodes.LotteryTitle.text,mainTickets=nodes.LotteryTicketValue.text;
const summer=view.sidebar.children.find(c=>c.id.includes('Section_summer'));summer.events.onactivate();
const detailReq=requests.at(-1).p;assert.equal(detailReq.snapshot_scope,'details');
events.ui_lottery_snapshot({...data('summer',2),snapshot_scope:'details',snapshot_request_id:detailReq.snapshot_request_id});
assert.equal(nodes.LotteryTitle.text,mainTitle);assert.equal(nodes.LotteryTicketValue.text,mainTickets,'details retain draw-pool identity');
current.CloseInfo();assert.equal(nodes.LotteryCelestialFooter.style.visibility,'visible');
assert.equal(config.SurvivalUILayers.Top(),'lottery');
nodes.LotterySkipAnimation.checked=true;current.SetSkipAnimation();current.DrawTen();const drawReq=requests.at(-1);assert.equal(drawReq.n,'ui_lottery_draw_request');
events.ui_lottery_result({ok:1,request_id:drawReq.p.request_id,pool_id:'map',count:10,results:results(10),snapshot:data('map',10)});
const rewards=nodes.LotteryItemList.children;assert.equal(rewards.length,10);assert(rewards.every(c=>c.__menuV10Cell));
assert.equal(new Set(rewards.map(c=>c.style.position)).size,10,'every ten-draw reward has a distinct slot');
assert.equal(nodes.LotteryCelestialFooter.style.visibility,'collapse');
current.Feature('history');assert.equal(view.title.text,'抽奖记录');assert(nodes.LotteryInfoList.children.some(c=>c.BHasClass('RHHistoryRow')));
current.CloseInfo();current.CloseResult();current.Feature('announcement');assert.equal(view.title.text,'开奖公告');
current.CloseInfo();const requestCount=requests.length;current.Feature('privilege');assert.equal(requests.length,requestCount,'unavailable privilege cannot transact');
current.Close();assert(!view.IsOpen());assert.equal(config.SurvivalUILayers.Top(),null);
presentation.Dispose();assert.equal(nodes.LotteryInfoOverlay.parent,root,'dispose restores the original business anchors');
console.log('MENU_V10_LOTTERY_PASS: one shell, 17 authoritative rewards, zero/unknown/max quantity, shared cells and tooltip, independent details pool, 10 distinct results, history/notice/placeholder, lifecycle');
`;
vm.runInNewContext(loader+'suite+='+JSON.stringify(setup)+';vm.runInNewContext(suite,{require:require("node:module").createRequire(require("path").resolve("tools/test_lottery_ui.js")),console});',{require:require('node:module').createRequire(path.resolve('tools/tests/menus_v10_lottery.test.cjs')),console});
