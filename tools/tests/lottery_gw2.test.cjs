const fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
const loader=fs.readFileSync('tools/test_lottery_updates.cjs','utf8').split('suite+=')[0];
const setup=`
Object.defineProperty(Panel.prototype,'paneltype',{get(){return this.type;}});
Panel.prototype.SetParent=function(parent){if(this.parent)this.parent.children=this.parent.children.filter(c=>c!==this);this.parent=parent;parent.children.push(this);this.reparented=true;};
Panel.prototype.DeleteAsync=function(){this.deleted=true;if(this.parent)this.parent.children=this.parent.children.filter(c=>c!==this);for(const c of [...this.children])c.DeleteAsync();};
Panel.prototype.RemoveAndDeleteChildren=function(){for(const c of [...this.children])c.DeleteAsync();};
Panel.prototype.IsValid=function(){return !this.deleted;};
Panel.prototype.SetScaling=function(value){this.scaling=value;};
// Deliberately stricter than the browser's global ID table. Native compiled
// descendants may no longer resolve through root after SetParent.
Panel.prototype.FindChildTraverse=function(id){if(this.reparented)return null;if(this.id===id)return this;for(const c of this.children){if(c.reparented)continue;if(c.id===id)return c;const hit=c.FindChildTraverse(id);if(hit)return hit;}return null;};
Panel.prototype.GetPositionWithinWindow=function(){let x=0,y=0;for(let p=this;p;p=p.parent){let v=String(p.style.position||'0px 0px 0px').split(' ');x+=parseFloat(v[0])||0;y+=parseFloat(v[1])||0;}return{x,y};};
// The legacy harness initially creates a flat ID index. Restore the active XML
// lottery ancestry so icon scoping cannot pass merely by a matching node ID.
for(const [parent,ids]of Object.entries({LotteryWindow:['LotteryMainCanvas','LotterySceneBackground','LotterySceneShade','LotteryInfoOverlay'],LotteryMainCanvas:['LotteryCelestialHeader','LotteryHeroCopy','LotteryCelestialFooter','LotteryResultStage','LotteryRevealStage','LotterySkipReveal','LotteryStatus','LotteryPoolTabs','LotteryReadingMask','LotteryUnlockNotice'],LotteryCelestialHeader:['LotteryTicketPurchase','LotteryCloseButton'],LotteryHeroCopy:['LotteryTitle','LotteryTaglineBounds','LotteryGuaranteeRow','LotteryAnnouncement'],LotteryTaglineBounds:['LotteryTagline'],LotteryCelestialFooter:['LotterySingleButton','LotteryTenButton','LotteryDrawPity','LotterySkipAnimation','LHDetails','LHHistory'],LotteryResultStage:['LotteryItemList','LotteryResultHeading','LotteryResultActions'],LotteryResultActions:['LotteryAgain','LotteryConfirm'],LotteryInfoOverlay:['LotteryInfoDialog'],LotteryInfoDialog:['LotteryInfoHeader','LotteryInfoNote','LotteryInfoBody','LotteryInfoFooter','LotteryInfoTabs','LotteryPoolGuarantee'],LotteryInfoBody:['LotteryInfoList','LotteryPoolSelection'],LotteryPoolSelection:['LotterySelectedIcon'],LotteryInfoFooter:['LotteryInfoRules','LotteryInfoConfirm']}))for(const id of ids){nodes[id].SetParent(nodes[parent]);nodes[id].reparented=false;}
root.actuallayoutwidth=1920;root.actuallayoutheight=1080;root.actualuiscale_x=1;root.actualuiscale_y=1;
// Retain the production controller's existing inline-info feature detection,
// and reject any accidental use of the old shared navigation shell.
config.SurvivalMenuV10={Adopt(){throw new Error('independent lottery must not adopt shared menus')}};
for(const name of ['common/item_resources','reward_presentation','common/tooltip_dismiss','native_ui_icons','item_art_remaining_5d5c1152eb','black_lion_market'])vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/'+name+'.js','utf8'),env);
vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/lottery_ui_remaining_5d5c1152eb.js','utf8'),env);
const current=config.SurvivalLottery;
const originalDialog=config.RemainingHandoff.LotteryDialog,originalReward=config.RemainingHandoff.RewardCard;
const originalIcon=config.SurvivalRewardPresentation.CreateIcon;
const originalParents=new Map(['LotteryInfoOverlay','LotteryHeroCopy','LotterySceneBackground','LotteryCelestialFooter','LotteryAnnouncement','LotteryTicketPurchase','LotteryCloseButton'].map(id=>[nodes[id],nodes[id].parent]));
// The fixture has flat XML anchors; preserve actual native action ownership.
const nativeSingle=nodes.LotterySingleButton,nativeTen=nodes.LotteryTenButton;
nativeSingle.SetPanelEvent('onactivate',current.DrawSingle);nativeTen.SetPanelEvent('onactivate',current.DrawTen);
const singleEvent=nativeSingle.events.onactivate,tenEvent=nativeTen.events.onactivate;
const source=fs.readFileSync('panorama/src/scripts/custom_game/lottery_gw2.js','utf8');
vm.runInNewContext(source,env);
let presentation=config.SurvivalPurpleLottery;
const realReward={id:'lottery_hippogryph_onslaught',item_id:'lottery_hippogryph_onslaught',name:'角鹰魔攻',description:'英雄初始攻击+10',quality:'ssr',icon:'item_greater_crit',count:1};
const realArt=config.SurvivalItemArt.Lookup(realReward);assert(realArt&&realArt.runtime_uri.includes('custom_game/reward_art_v5/'));
const outside=config.SurvivalRewardPresentation.CreateIcon(root,realReward,'OtherWindowIcon');assert.equal(outside.image,realArt.runtime_uri,'every menu uses the same item resource');
const oldTipIcon=config.SurvivalRewardPresentation.CreateIcon(nodes.LotteryTooltipIconHost,realReward,'LotteryRewardIcon');assert.equal(oldTipIcon.image,realArt.runtime_uri,'an external tooltip also shares the canonical item icon');
const inside=config.SurvivalRewardPresentation.CreateIcon(nodes.LotteryInfoList,realReward,'LotteryRewardIcon');assert.equal(inside.image,realArt.runtime_uri,'lottery uses the existing named reward art');
const unknown=config.SurvivalRewardPresentation.CreateIcon(nodes.LotteryInfoList,{id:'not_a_known_reward',icon:'item_blink'},'LotteryRewardIcon');assert.equal(unknown.type,'DOTAItemImage','unknown mapping retains the native item control');assert.equal(unknown.itemname,'item_blink');
const notLottery=config.SurvivalRewardPresentation.CreateIcon(nodes.LotteryInfoList,{id:'shadow_01',icon:'item_branches'},'LotteryRewardIcon');assert.equal(notLottery.image,config.SurvivalItemResources.Resolve('shadow_01'),'a known shadow item retains its canonical resource in every UI');
nodes.LotteryInfoList.RemoveAndDeleteChildren();
assert.equal(nodes.LotteryMainCanvas.style.width,'1536px');assert.equal(nodes.LotteryMainCanvas.style.height,'864px');
assert.equal(nodes.LotteryMainCanvas.style.transformOrigin,'50% 50%');
assert.equal(nodes.LotteryGW2Content.style.position,'342px 118px 0px');assert.equal(nodes.LotteryGW2Content.style.width,'1113px');assert.equal(nodes.LotteryGW2Content.style.height,'669px');
assert.equal(nodes.LotteryInfoOverlay.parent,nodes.LotteryGW2DetailLayer);assert.equal(nodes.LotteryCelestialFooter.parent,nodes.LotteryGW2Content);
assert.equal(nodes.LotteryGW2Tooltip.parent,nodes.LotteryGW2DetailLayer,'tooltip shares the layer raised by details instead of sitting behind its ancestry');
assert.equal(root.FindChildTraverse('LotteryHeroCopy'),null,'native-style traversal cannot find moved controls');
assert.equal(nodes.LotteryCelestialHeader.style.visibility,'collapse');assert.equal(nodes.LotteryPoolTabs.style.visibility,'collapse');
assert.strictEqual(nodes.LotterySingleButton,nativeSingle);assert.strictEqual(nativeSingle.events.onactivate,singleEvent);assert.strictEqual(nativeTen.events.onactivate,tenEvent);
assert.equal(config.SurvivalUILayers.Top(),null,'presentation registration does not open a modal');
current.Open();assert(presentation.Inspect().open);assert.equal(config.SurvivalUILayers.Top(),'lottery');
function data(pool='map',tickets=20){const d=snapshot(pool,tickets);d.shop_points=825;d.pools=['map','cultivation','dragon_knight','summer'].map(id=>({id,display_name:id,ticket_name:id==='map'||id==='cultivation'?'普通抽奖券':'金色抽奖券'}));d.items=Array.from({length:17},(_,i)=>({id:'r'+i,name:'正式奖励'+i,quality:i%2?'sr':'n',icon:'item_blink',description:'效果'+i,owned_count:i===0?undefined:i===1?0:2,max_owned:i===2?5:undefined}));return d;}
events.ui_lottery_snapshot(data());
assert.equal(nodes.LotteryGW2Title.text,'抽奖');assert(nodes.LotteryGW2TicketBalance.text.includes('20'));assert.equal(nodes.LotteryGW2Points.text,'商城积分  825');assert.equal(nodes.LotteryGW2StarjoyPoints.text,'星悦积分  10');
const absent=data();delete absent.shop_points;events.ui_lottery_snapshot(absent);assert.equal(nodes.LotteryGW2Points.text,'商城积分  —');events.ui_lottery_snapshot({...data(),shop_points:0});assert.equal(nodes.LotteryGW2Points.text,'商城积分  0');events.ui_lottery_snapshot(data());
assert.equal(presentation.Inspect().pools,4);assert.equal(nodes.LotteryGW2Sidebar.children.length,4);
assert.equal(nodes.LotteryGW2PreviewItems.children.length,4);assert.equal(nodes.LotterySceneBackground.style.opacity,'1','retain the existing pool illustration');
const otherModal=new Panel('Panel',root,'UnrelatedModal');config.SurvivalUILayers.Open('unrelated_modal',otherModal,()=>{});
const beforeForeign=requests.length;nodes.LotteryGW2Back.events.onactivate();nodes.LotteryGW2Pool_summer.events.onactivate();nodes.LotteryGW2Preview_0.events.onactivate();nodes.LotteryGW2Preview_0.events.onmouseover();
assert.equal(requests.length,beforeForeign,'new controls cannot act through an unrelated modal');assert.equal(config.SurvivalUILayers.Top(),'unrelated_modal');assert.equal(presentation.Inspect().selected,'map');assert(!nodes.LotteryGW2Tooltip.visible);assert(presentation.Inspect().open);
config.SurvivalUILayers.Close('unrelated_modal');
current.Feature('details');assert.equal(nodes.LotteryInfoOverlay.style.position,'342px 118px 0px');
assert.equal(config.SurvivalUILayers.Top(),'lottery_info','Escape closes the details layer owned by the controller');
assert.equal(nodes.LotteryInfoDialog.style.width,'1113px');assert.equal(nodes.LotteryInfoDialog.style.transform,'none');
assert.equal(nodes.LotteryCelestialFooter.style.visibility,'collapse');
const cells=nodes.LotteryInfoList.children.filter(c=>c.BHasClass('LotteryDetailRow'));
assert.equal(cells.length,17);assert(cells.every(c=>c.__lotteryGW2Cell),'decorate every existing reward');
assert.equal(cells[0].__lotteryGW2Cell.count.text,'0','quality sorting keeps real zero');
assert(cells.some(c=>c.__lotteryGW2Cell.count.text==='—'),'unknown quantity is not zero');
assert(cells.some(c=>c.__lotteryGW2Cell.count.text==='2/5'),'only actual maximum is shown');
presentation.Fit();const steady=presentation.Inspect();
for(let i=0;i<30;i++){current.Feature('details');presentation.Fit();assert(presentation.Inspect().trackedOwned<=steady.trackedOwned,'deleted reward visuals cannot accumulate');assert(presentation.Inspect().trackedMoved<=steady.trackedMoved,'deleted native icons cannot accumulate');}
const first=nodes.LotteryInfoList.children.find(c=>c.BHasClass('LotteryDetailRow')),before=requests.length;first.events.onmouseover();assert.equal(requests.length,before,'hover is read-only');
assert(nodes.LotteryGW2Tooltip.visible);assert(nodes.LotteryGW2TooltipDescription.text.includes('效果'));nodes.LotteryGW2Tooltip.events.onmouseover();assert(!nodes.LotteryGW2Tooltip.visible,'Entering the tooltip dismisses it immediately');first.events.onmouseover();assert(!nodes.LotteryGW2Tooltip.visible,'The dismissed source cannot immediately reopen its tooltip');assert(nodes.LotteryItemTooltip.BHasClass('Hidden'),'A consumed tooltip request cannot fall through to the old XML tooltip');first.events.onmouseout();assert(!nodes.LotteryGW2Tooltip.visible);
assert(nodes.LotteryGW2Tooltip.BHasClass('BLMarketDetail'),'Lottery uses the actual market tooltip skin');
assert(nodes.LotteryGW2Tooltip.children.some(child=>child.BHasClass('BLMarketDetailSurface')));
assert(!nodes.LotteryGW2TooltipFrame&&!nodes.LotteryGW2TooltipBacking,'No independent blue frame or backing remains');
env.GameUI.GetCursorPosition=()=>[1800,1000];
for(const [description,expected]of [
 ['攻击+1,000；护甲+5 | 生命+20%（每秒恢复+1；持续10秒）',['攻击+1,000','护甲+5','生命+20%（每秒恢复+1；持续10秒）']],
 ['伐木工攻速+20% 箭塔攻击成长+1 墙减伤+5% 每1级地图等级，墙生命加成+1% 墙每秒生命+5 星悦积分+200',['伐木工攻速+20%','箭塔攻击成长+1','墙减伤+5%','每1级地图等级，墙生命加成+1%','墙每秒生命+5','星悦积分+200']],
 ['英雄最终伤害+25%英雄攻击减甲+25英雄全属性加成+25%星悦积分+200获得英雄翅膀:赛博主宰（后续再做皮肤） 购买后自动激活',['英雄最终伤害+25%','英雄攻击减甲+25','英雄全属性加成+25%','星悦积分+200','获得英雄翅膀:赛博主宰（后续再做皮肤）','购买后自动激活']],
 ['解锁英雄：魔法少女 星悦积分+200 英雄全属性加成+30%，攻击减甲+20 减少0.1攻击间隔 开局自带1转技能',['解锁英雄：魔法少女','星悦积分+200','英雄全属性加成+30%','攻击减甲+20','减少0.1攻击间隔','开局自带1转技能']],
 ['每持有一种UR道具额外增加4%英雄最终伤害（包含自身，重复分解不计）',['每持有一种UR道具额外增加4%英雄最终伤害（包含自身，重复分解不计）']]
]){
 presentation.Tooltip({name:'分行检查',description},first);
 assert.deepEqual(nodes.LotteryGW2TooltipDescription.text.split(String.fromCharCode(10)),expected);
 assert.equal(nodes.LotteryGW2Tooltip.hittest,false,'Short market-style tooltip is passive');
}
let tooltipCursor=[1800,1000];env.GameUI.GetCursorPosition=()=>tooltipCursor;
const scrollTip=nodes.LotteryGW2Tooltip,scrollDescription=nodes.LotteryGW2TooltipDescription,scrollViewport=nodes.LotteryGW2TooltipScroll;
Object.defineProperty(scrollDescription,'actuallayoutheight',{get(){return Math.max(24,Math.ceil(String(this.text||'').length/17)*23);}});
Object.defineProperty(scrollViewport,'actuallayoutheight',{get(){return parseFloat(this.style.height)||0;}});
Object.defineProperty(scrollTip,'actuallayoutwidth',{get(){return parseFloat(this.style.width)||366;}});
Object.defineProperty(scrollTip,'actuallayoutheight',{get(){return parseFloat(this.style.height)||0;}});
const longReward={id:'long-tooltip-readonly',name:'完整奖励',description:'完整的长奖励说明'.repeat(150)};
presentation.Tooltip(longReward,first);assert(scrollDescription.actuallayoutheight>scrollViewport.actuallayoutheight);
const longTipIcon=nodes.LotteryGW2TooltipIconStage.children[0],longAt=scrollTip.GetPositionWithinWindow(),longRequests=requests.length;
first.events.onmouseout();assert(scrollTip.visible,'The controller source leave delegates a grace period for long tooltips');
tooltipCursor=[longAt.x+30,longAt.y+130];scrollTip.events.onmouseover();advance(.2);
assert(scrollTip.visible,'Entering the scroll surface cancels source leave and survives shared geometry checks');
assert.strictEqual(nodes.LotteryGW2TooltipIconStage.children[0],longTipIcon,'Scrolling reuses the existing tooltip content and icon');
scrollTip.events.onmouseout();advance(.2);assert(scrollTip.visible,'Child leave events cannot hide while still in the long tooltip');
tooltipCursor=[1800,1000];scrollTip.events.onmouseout();advance(.2);assert(!scrollTip.visible,'Leaving the source and scroll surface hides after grace');
presentation.Tooltip(longReward,first);first.events.onmouseout();first.events.onmouseover();advance(.2);assert(scrollTip.visible,'A new source hover invalidates a previous long-tooltip leave callback');
assert(!requests.slice(longRequests).some(r=>/draw|purchase|checkout|claim/.test(r.n)),'Long-tooltip input cannot submit a transactional request');
scrollTip.events.onmouseover();assert(!scrollTip.visible,'Returning to short content retains immediate passive surface dismissal');
delete env.GameUI.GetCursorPosition;
const retiredModal=config.SurvivalUI.ModalManager.Get('lottery_info');assert(!retiredModal||!retiredModal.IsOpen(),'no second details modal');
const mainTitle=nodes.LotteryTitle.text,mainTickets=nodes.LotteryGW2TicketBalance.text;
nodes.LotteryGW2Pool_summer.events.onactivate();
const detailReq=requests.at(-1).p;assert.equal(detailReq.snapshot_scope,'details');
events.ui_lottery_snapshot({...data('summer',2),snapshot_scope:'details',snapshot_request_id:detailReq.snapshot_request_id});
assert.equal(nodes.LotteryTitle.text,mainTitle);assert.equal(nodes.LotteryGW2TicketBalance.text,mainTickets,'details retain the active draw-pool balance');
current.CloseInfo();assert.equal(nodes.LotteryCelestialFooter.style.visibility,'visible');assert.equal(config.SurvivalUILayers.Top(),'lottery');
nodes.LotterySkipAnimation.checked=true;current.SetSkipAnimation();nativeTen.events.onactivate();const drawReq=requests.at(-1);assert.equal(drawReq.n,'ui_lottery_draw_request');
nativeTen.events.onactivate();nodes.LotteryGW2Pool_summer.events.onactivate();assert.strictEqual(requests.at(-1),drawReq,'double click and pool switch remain blocked while drawing');
current.Close();current.Open();nativeTen.events.onactivate();assert.equal(requests.filter(r=>r.n==='ui_lottery_draw_request').length,1,'ordinary reopen preserves controller pending');
events.ui_lottery_result({ok:1,request_id:drawReq.p.request_id,pool_id:'map',count:10,results:results(10),snapshot:data('map',10)});
const rewards=nodes.LotteryItemList.children;assert.equal(rewards.length,10);assert(rewards.every(c=>c.__lotteryGW2Cell));
assert.equal(new Set(rewards.map(c=>c.style.position)).size,10,'all ten server results retain distinct slots');
assert.equal(nodes.LotteryCelestialFooter.style.visibility,'collapse');
current.Feature('history');assert.equal(nodes.LotteryGW2Title.text,'抽奖记录');assert(nodes.LotteryInfoList.children.some(c=>c.BHasClass('RHHistoryRow')));
current.CloseInfo();current.CloseResult();current.Feature('announcement');assert.equal(nodes.LotteryGW2Title.text,'开奖公告');
current.CloseInfo();const requestCount=requests.length;current.Feature('privilege');assert.equal(requests.length,requestCount,'unavailable privilege cannot transact');
current.CloseInfo();
const artSnapshot=data();artSnapshot.items=[realReward];events.ui_lottery_snapshot(artSnapshot);
assert.equal(nodes.LotteryGW2Preview_0.children.find(n=>n.BHasClass('LotteryGW2PreviewIcon')).image,realArt.runtime_uri,'main preview uses the actual catalog');
events.ui_lottery_result({ok:1,request_id:'isolated_art_result',pool_id:'map',count:1,results:[realReward],snapshot:artSnapshot});
const artCard=nodes.LotteryItemList.children[0];assert.equal(artCard.__lotteryGW2Cell.stage.children[0].image,realArt.runtime_uri,'result retains original Image with approved source');
artCard.events.onactivate();const frame=nodes.LotteryInfoList.children.find(n=>n.BHasClass('LotteryDetailIcon'));assert(frame);assert.equal(frame.children.find(n=>n.BHasClass('LotteryRewardIcon')).image,realArt.runtime_uri,'reward details use the exact passed item, not a name guess');
current.CloseInfo();current.CloseResult();events.ui_lottery_snapshot(data());
const shell=nodes.LotteryGW2Root,buttons=nodes.LotteryGW2Sidebar.children.slice();
for(let i=0;i<12;i++){current.Close();current.Open();assert.strictEqual(nodes.LotteryGW2Root,shell);assert.deepEqual(nodes.LotteryGW2Sidebar.children,buttons);}
for(const [w,h,s] of [[1280,720,1],[1920,1080,1],[2560,1440,1.5],[3440,1440,1],[1366,768,1]]){root.actuallayoutwidth=w;root.actuallayoutheight=h;root.actualuiscale_x=s;root.actualuiscale_y=s;presentation.Fit();assert.equal(nodes.LotteryMainCanvas.style.transform,'scale3d('+Math.min(w/s/1536,h/s/864)+','+Math.min(w/s/1536,h/s/864)+',1)');}
root.actuallayoutwidth=0;root.actuallayoutheight=0;presentation.Fit();assert.equal(nodes.LotteryMainCanvas.style.opacity,'0','unmeasured root cannot flash full-size');
root.actuallayoutwidth=1920;root.actuallayoutheight=1080;presentation.Fit();
current.Close();assert(!presentation.Inspect().open);assert.equal(config.SurvivalUILayers.Top(),null);
presentation.Dispose();for(const [node,parent]of originalParents){assert.strictEqual(node.parent,parent,'restore business anchor '+node.id);assert(node.IsValid());}
assert.strictEqual(config.RemainingHandoff.LotteryDialog,originalDialog);assert.strictEqual(config.RemainingHandoff.RewardCard,originalReward);
assert.strictEqual(config.SurvivalRewardPresentation.CreateIcon,originalIcon,'dispose restores the icon factory rather than nesting wrappers');
assert.strictEqual(nativeSingle.events.onactivate,singleEvent);assert.strictEqual(nativeTen.events.onactivate,tenEvent);
vm.runInNewContext(source,env);presentation=config.SurvivalPurpleLottery;current.Open();events.ui_lottery_snapshot(data());current.Feature('details');assert.equal(nodes.LotteryInfoList.children.length,17,'presentation reload still uses authoritative controller');current.CloseInfo();current.Close();presentation.Dispose();
// Source 2 retains CustomUIConfig while replacing layout children. The XML loads
// the controller before the presentation, so that old presentation is observable
// while the next controller runs its initial close/update calls.
function loadPresentation(){const before=new Set(root.Children());vm.runInNewContext(source,env);const marker=root.Children().find(n=>!before.has(n));assert(marker,'production renderer owns a layout lifetime marker');return {api:config.SurvivalPurpleLottery,marker};}
function verifyReopenedController(previous){
 const replacement=config.SurvivalLottery;
 assert.notStrictEqual(replacement,previous,'controller initialization replaces the disposed API');
 assert(replacement.IsAlive());assert(!previous.IsAlive());
 const renderer=loadPresentation();const before=requests.length;
 replacement.Open();assert(requests.slice(before).some(r=>r.n==='ui_lottery_snapshot_request'),'a real entry click requests the uncached snapshot');
 assert(nodes.LotteryWindow.BHasClass('LotteryOpen'));assert(!nodes.LotteryWindow.BHasClass('LotteryClosed'));assert.equal(config.SurvivalUILayers.Top(),'lottery');
 events.ui_lottery_snapshot(data());assert(renderer.api.Inspect().open);assert(nodes.LotteryGW2Root.visible);
 replacement.Feature('details');assert.equal(nodes.LotteryInfoList.children.length,17);assert.equal(nodes.LotteryGW2Title.text,'奖池详情');assert.equal(config.SurvivalUILayers.Top(),'lottery_info');
 replacement.CloseInfo();replacement.Close();assert(!renderer.api.Inspect().open);assert(nodes.LotteryWindow.BHasClass('LotteryClosed'));assert.equal(config.SurvivalUILayers.Top(),null);
 return {controller:replacement,renderer};
}
const staleProduction=loadPresentation();current.Dispose();staleProduction.marker.deleted=true;
assert(!staleProduction.api.IsAlive(),'the prior layout is dead while its API remains in CustomUIConfig');
assert.doesNotThrow(()=>vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/lottery_ui_remaining_5d5c1152eb.js','utf8'),env),'controller-first reload must survive the dead production presentation');
const renewed=verifyReopenedController(current);
// A client may still execute the previous, unfixed compiled renderer. Fail at
// that dependency boundary if initialization calls any rendering method before
// disposing it; no renderer implementation is duplicated in this fixture.
renewed.renderer.marker.deleted=true;let legacyDisposed=false;
const legacyApi={};for(const key of Object.keys(renewed.renderer.api))if(typeof renewed.renderer.api[key]==='function')legacyApi[key]=function(){assert(legacyDisposed,'dead legacy presentation must be disposed before rendering: '+key);};
legacyApi.IsAlive=()=>false;legacyApi.Dispose=function(){legacyDisposed=true;renewed.renderer.api.Dispose();};config.SurvivalPurpleLottery=legacyApi;
assert.doesNotThrow(()=>vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/lottery_ui_remaining_5d5c1152eb.js','utf8'),env),'controller upgrade releases the previous compiled presentation before closing the old controller');
assert(legacyDisposed);const upgraded=verifyReopenedController(renewed.controller);upgraded.controller.Dispose();upgraded.renderer.api.Dispose();
console.log('LOTTERY_LAYOUT_RELOAD_PASS: dead production lifetime, controller-first XML order, disposed API replacement, fresh snapshot request, real shell/details/close and previous compiled renderer transition');
console.log('LOTTERY_GW2_PASS: independent shell, native controls, four authoritative pools, scoped actual art/fallback/details, zero/unknown counts, ten results, pending/foreign-modal guards, 30 rebuilds without stale refs, five fits, 12 opens, restored parents/factories and renderer reload');
`;
vm.runInNewContext(loader+'suite+='+JSON.stringify(setup)+';vm.runInNewContext(suite,{require:require("node:module").createRequire(require("path").resolve("tools/test_lottery_ui.js")),console});',{require:require('node:module').createRequire(path.resolve('tools/tests/lottery_gw2.test.cjs')),console});
