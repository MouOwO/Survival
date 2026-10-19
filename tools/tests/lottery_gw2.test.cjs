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
// Use the current production asset registration for renderer readiness. This
// suite exercises compact detail cards; grouped preview has its own acceptance.
vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/lottery_gw2_data.js','utf8').split('// Display-only projection')[0],env);
vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/lottery_ui_remaining_5d5c1152eb.js','utf8'),env);
const current=config.SurvivalLottery;
const originalDialog=config.RemainingHandoff.LotteryDialog,originalReward=config.RemainingHandoff.RewardCard;
const originalIcon=config.SurvivalRewardPresentation.CreateIcon;
const originalParents=new Map(['LotteryInfoOverlay','LotteryHeroCopy','LotterySceneBackground','LotteryCelestialFooter','LotteryAnnouncement','LotteryTicketPurchase','LotteryCloseButton'].map(id=>[nodes[id],nodes[id].parent]));
// The fixture has flat XML anchors; preserve actual native action ownership.
const nativeSingle=nodes.LotterySingleButton,nativeTen=nodes.LotteryTenButton,nativeTicketPurchase=nodes.LotteryTicketPurchase;
nativeSingle.SetPanelEvent('onactivate',current.DrawSingle);nativeTen.SetPanelEvent('onactivate',current.DrawTen);
nativeTicketPurchase.SetPanelEvent('onactivate',()=>current.Feature('purchase'));
const singleEvent=nativeSingle.events.onactivate,tenEvent=nativeTen.events.onactivate,ticketEvent=nativeTicketPurchase.events.onactivate;
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
assert.equal(nodes.LotteryMainCanvas.style.width,'1672px');assert.equal(nodes.LotteryMainCanvas.style.height,'941px');
assert.equal(nodes.LotteryMainCanvas.style.transformOrigin,'50% 50%');
assert.equal(nodes.LotteryGW2Content.style.position,'334px 123px 0px');assert.equal(nodes.LotteryGW2Content.style.width,'1309px');assert.equal(nodes.LotteryGW2Content.style.height,'681px');
assert.equal(nodes.LotteryInfoOverlay.parent,nodes.LotteryGW2DetailLayer);assert.equal(nodes.LotteryCelestialFooter.parent,nodes.LotteryGW2Root);
for(const [id,x,y,w,h]of [['LotteryGW2HeaderSkin',35,45,1608,74],['LotteryGW2SidebarSkin',35,123,299,746],['LotteryGW2FooterSkin',334,804,1309,65]]){
 const node=nodes[id];assert.equal(node.style.position,x+'px '+y+'px 0px',id+' shares the accepted boundary');assert.equal(node.style.width,w+'px');assert.equal(node.style.height,h+'px');
 assert.equal(node.parent,nodes.LotteryGW2Root,'each material is an independent decorative layer');assert(node.style.opacity===undefined||node.style.opacity==='1','alpha belongs to the background material only');
 for(const textId of ['LotteryGW2Title','LotteryGW2TicketBalance','LotteryTitle','LotterySingleText','LotteryTenText'])for(let ancestor=nodes[textId];ancestor;ancestor=ancestor.parent)assert.notStrictEqual(ancestor,node,'background opacity must never include dynamic text');
}
assert.equal(nodes.LotteryGW2SidebarSkin.style.backgroundColor,'#0000004d','only the sidebar backing is 70% transparent');
assert.equal(nodes.LotteryGW2FooterSkin.style.backgroundColor,'#10191d','the footer backing is fully opaque');
assert(!nodes.LotteryGW2Points&&!nodes.LotteryGW2StarjoyPoints,'neither points balance is built in the lottery header');
assert.strictEqual(nodes.LotteryTicketPurchase,nativeTicketPurchase,'reuse the controller-owned ticket purchase button');
assert.strictEqual(nativeTicketPurchase.events.onactivate,ticketEvent,'restyling retains the ticket purchase callback');
assert.strictEqual(nativeTicketPurchase.parent,nodes.LotteryGW2TicketCurrency);
assert.equal(nodes.LotteryGW2TicketCurrency.hittestchildren,true,'the balance container admits clicks on its purchase button');
assert.equal(nativeTicketPurchase.style.width,'32px');assert.equal(nativeTicketPurchase.style.height,'32px');
assert.equal(nodes.LotteryGW2PurchasePlus.type,'Image');
assert.equal(nodes.LotteryGW2PurchasePlus.image,'file://{images}/control_icons/24px/plus.svg');
assert(!nodes.LotteryGW2PurchaseLabel,'the acquisition text is replaced by an icon');
assert.equal(nodes.LotteryCelestialFooter.style.position,'334px 123px 0px');assert.equal(nodes.LotteryCelestialFooter.style.width,'1309px');assert.equal(nodes.LotteryCelestialFooter.style.height,'746px');
assert.equal(nodes.LotterySceneBackground.parent,nodes.LotteryGW2Root);assert.equal(nodes.LotterySceneBackground.style.position,'35px 123px 0px');assert.equal(nodes.LotterySceneBackground.style.width,'1608px');assert.equal(nodes.LotterySceneBackground.style.height,'746px');
assert.equal(nodes.LotteryGW2Tooltip.parent,nodes.LotteryGW2DetailLayer,'tooltip shares the layer raised by details instead of sitting behind its ancestry');
assert.equal(root.FindChildTraverse('LotteryHeroCopy'),null,'native-style traversal cannot find moved controls');
assert.equal(nodes.LotteryCelestialHeader.style.visibility,'collapse');assert.equal(nodes.LotteryPoolTabs.style.visibility,'collapse');
assert.strictEqual(nodes.LotterySingleButton,nativeSingle);assert.strictEqual(nativeSingle.events.onactivate,singleEvent);assert.strictEqual(nativeTen.events.onactivate,tenEvent);
assert.equal(config.SurvivalUILayers.Top(),null,'presentation registration does not open a modal');
current.Open();assert(presentation.Inspect().open);assert.equal(config.SurvivalUILayers.Top(),'lottery');
function data(pool='map',tickets=20){const d=snapshot(pool,tickets);d.shop_points=825;d.pools=['map','cultivation','dragon_knight','summer'].map(id=>({id,display_name:id,ticket_name:id==='map'||id==='cultivation'?'普通抽奖券':'金色抽奖券'}));d.items=Array.from({length:17},(_,i)=>({id:'r'+i,name:'正式奖励'+i,quality:i%2?'sr':'n',icon:'item_blink',description:'效果'+i,owned_count:i===0?undefined:i===1?0:2,max_owned:i===2?5:undefined}));return d;}
function ticketAlignment(){
 const host=nodes.LotteryGW2TicketCurrency,icon=nodes.LotteryGW2TicketIcon,count=nodes.LotteryGW2TicketBalance,plus=nativeTicketPurchase,close=nodes.LotteryCloseButton;
 const x=node=>parseFloat(node.style.position),y=node=>parseFloat(node.style.position.split(' ')[1]),w=node=>parseFloat(node.style.width),h=node=>parseFloat(node.style.height);
 assert.equal(host.style.position,'1142px 8px 0px');assert.equal(host.style.width,'372px');assert.equal(host.style.height,'58px');assert.equal(host.style.flowChildren,'none','the currency uses explicit coordinates');
 assert.equal(x(close)-(x(host)+w(host)),24,'the currency group sits directly left of the close button');
 for(const node of [icon,count,plus]){assert.strictEqual(node.parent,host);assert(x(node)>=0&&x(node)+w(node)<=w(host),'each currency control stays inside its bounded header group');assert.equal(y(node)+h(node)/2,h(host)/2,'the icon, count and plus share the header center');}
 assert.equal(x(count)-(x(icon)+w(icon)),8);assert.equal(x(plus)-(x(count)+w(count)),8,'large balances cannot overlap the plus');assert.equal(x(plus)+w(plus),w(host),'the plus stays next to the close button for every count');
 assert.equal(icon.style.width,'72px');assert.equal(icon.style.height,'58px');assert.equal(count.style.whiteSpace,'nowrap');assert.equal(count.style.textOverflow,'shrink');
 assert.strictEqual(plus.events.onactivate,ticketEvent,'layout preserves the controller purchase callback');
}
function poolNavigation(active){
 assert.strictEqual(nodes.LotteryGW2OfficialFrame.parent,nodes.LotteryGW2DetailLayer,'the outer border shares the raised details ancestry');assert.equal(nodes.LotteryGW2OfficialFrame.hittest,false,'the border never intercepts navigation');
 const buttons=nodes.LotteryGW2Sidebar.children,selectedButtons=buttons.filter(button=>button.BHasClass('Selected'));assert.equal(selectedButtons.length,1);assert.equal(selectedButtons[0].id,'LotteryGW2Pool_'+active);
 for(const button of buttons){
  const title=button.children.find(child=>child.BHasClass('LotteryGW2PoolTitle')),state=button.children.find(child=>child.BHasClass('LotteryGW2PoolLock')),marks=button.children.filter(child=>child.BHasClass('LotteryGW2PoolSelectionMark'));
  const width=parseFloat(button.style.width),height=parseFloat(button.style.height),at=title.style.position.split(' ');
  assert.equal(parseFloat(at[0])+parseFloat(title.style.width)/2,width/2,'every pool title is horizontally centered');assert.equal(parseFloat(at[1])+parseFloat(title.style.height)/2,height/2,'every pool title is vertically centered');assert.equal(title.style.textAlign,'center');assert.equal(title.style.whiteSpace,'nowrap');assert.equal(title.style.textOverflow,'shrink');
  assert.equal(marks.length,2,'selection is indicated on both sides of the title');for(const mark of marks){assert.equal(mark.text,'◆');assert.equal(mark.style.visibility,button.BHasClass('Selected')?'visible':'collapse','gold markers follow the selected pool');}
  assert(!button.children.some(child=>/普通抽奖券|金色抽奖券/.test(String(child.text||''))),'pool buttons omit ticket subtitles');
  if(state.style.visibility==='collapse')assert.equal(state.text,'','unlocked pools have no subtitle');
 }
}
events.ui_lottery_snapshot(data());
assert.equal(nodes.LotteryGW2Title.text,'抽奖');assert(nodes.LotteryGW2TicketBalance.text.includes('20'));
for(const tickets of [0,20,Number.MAX_SAFE_INTEGER,Number.MAX_VALUE]){events.ui_lottery_snapshot(data('map',tickets));ticketAlignment();assert.equal(nodes.LotteryGW2TicketBalance.text,String(tickets),'the full count remains available while its rectangle stays bounded');}
events.ui_lottery_snapshot(data());poolNavigation('map');
const lockData=data(),cultivationAction=nodes.LotteryGW2Pool_cultivation.events.onactivate;Object.assign(lockData.pools[1],{unlocked:false,unlock_progress:3,unlock_required:10});events.ui_lottery_snapshot(lockData);poolNavigation('map');
const lockCaption=nodes.LotteryGW2Pool_cultivation.children.find(child=>child.BHasClass('LotteryGW2PoolLock'));assert.equal(lockCaption.text,'未解锁  3 / 10');assert.equal(lockCaption.style.visibility,'visible','real unlock requirements remain available');
events.ui_lottery_snapshot(data());assert.equal(lockCaption.style.visibility,'collapse');assert.strictEqual(nodes.LotteryGW2Pool_cultivation.events.onactivate,cultivationAction,'unlock updates keep the actual tab callback');
const absent=data();delete absent.shop_points;events.ui_lottery_snapshot(absent);events.ui_lottery_snapshot({...data(),shop_points:0});assert(!nodes.LotteryGW2Points&&!nodes.LotteryGW2StarjoyPoints,'balance snapshots do not recreate removed header balances');events.ui_lottery_snapshot(data());
const ticketPurchases=[];config.SurvivalCommerceView={OpenTicketPurchase:pool=>{ticketPurchases.push(pool);return true;}};
for(const id of ['map','summer']){
 current.SelectPool(id);const ticketData=data(id);ticketData.selected_pool.ticket_content_id=id==='map'?'lottery_ticket':'special_lottery_ticket';events.ui_lottery_snapshot(ticketData);
 ticketAlignment();poolNavigation(id);
 nativeTicketPurchase.events.onactivate();const purchase=ticketPurchases.at(-1);assert.equal(purchase.id,id,'the plus button routes the selected pool');assert.equal(purchase.ticket_content_id,ticketData.selected_pool.ticket_content_id,'the correct ticket type reaches the existing purchase flow');
}
delete config.SurvivalCommerceView;current.SelectPool('map');events.ui_lottery_snapshot(data());
assert.equal(presentation.Inspect().pools,4);assert.equal(nodes.LotteryGW2Sidebar.children.length,4);
assert.equal(nodes.LotteryGW2PreviewItems.children.length,4);assert.equal(nodes.LotterySceneBackground.style.opacity,'1','retain the existing pool illustration');
function previewAlignment(){
 const cards=nodes.LotteryGW2PreviewItems.children,w=parseFloat(nodes.LotteryGW2PreviewItems.style.width),last=cards.at(-1);
 assert.equal((parseFloat(cards[0].style.position)+parseFloat(last.style.position)+parseFloat(last.style.width))/2,w/2,'The preview row is centered for the actual item count');
 for(const card of cards){
  const host=card.children.find(n=>n.BHasClass('LotteryGW2PreviewNameHost')),caption=host.children[0],icon=card.children.find(n=>n.BHasClass('LotteryGW2PreviewIcon'));
  assert.equal(parseFloat(String(icon.style.position).split(' ')[0])+parseFloat(icon.style.width)/2,parseFloat(host.style.width)/2,'Caption host and icon share one center axis');
  assert.equal(caption.style.width,'fit-children');assert.equal(caption.style.height,'fit-children');assert.equal(caption.style.horizontalAlign,'center');assert.equal(caption.style.verticalAlign,'center');
 }
}
previewAlignment();
for(const count of [1,2,3]){const sample=data();sample.items=sample.items.slice(0,count);events.ui_lottery_snapshot(sample);previewAlignment();}
events.ui_lottery_snapshot(data());
const otherModal=new Panel('Panel',root,'UnrelatedModal');config.SurvivalUILayers.Open('unrelated_modal',otherModal,()=>{});
const beforeForeign=requests.length;nodes.LotteryGW2Back.events.onactivate();nodes.LotteryGW2Pool_summer.events.onactivate();nodes.LotteryGW2Preview_0.events.onactivate();nodes.LotteryGW2Preview_0.events.onmouseover();
assert.equal(requests.length,beforeForeign,'new controls cannot act through an unrelated modal');assert.equal(config.SurvivalUILayers.Top(),'unrelated_modal');assert.equal(presentation.Inspect().selected,'map');assert(!nodes.LotteryGW2Tooltip.visible);assert(presentation.Inspect().open);
config.SurvivalUILayers.Close('unrelated_modal');
function infoBounds(bodyTop,details=false){
 const footerTop=details?746:658,footerHeight=details?0:88;
 const expected={LotteryInfoOverlay:[334,123,1309,746],LotteryInfoDialog:[0,0,1309,746],LotteryInfoBody:[0,bodyTop,1309,footerTop-bodyTop],LotteryInfoList:[0,0,1309,footerTop-bodyTop],LotteryInfoFooter:[0,footerTop,1309,footerHeight],LotteryInfoRules:[18,0,1072,84]};
 for(const [id,[x,y,w,h]]of Object.entries(expected)){
  const n=nodes[id];assert(n,id+' exists');assert.equal(n.style.position,x+'px '+y+'px 0px',id+' fills the right-side layout');assert.equal(n.style.width,w+'px',id+' width');assert.equal(n.style.height,h+'px',id+' height');
 }
 assert.equal(nodes.LotteryInfoNote.style.width,'1273px','the note uses the full right-side width');
 assert.equal(parseFloat(nodes.LotteryInfoOverlay.style.position)+parseFloat(nodes.LotteryInfoOverlay.style.width),1643,'details meet the same right edge as the accepted content');
 assert.equal(parseFloat(nodes.LotteryInfoBody.style.position.split(' ')[1])+parseFloat(nodes.LotteryInfoBody.style.height),footerTop,'the list uses all space above the current footer');
 assert.equal(nodes.LotteryInfoFooter.style.visibility,details?'collapse':'visible','only details remove the footer and its explanatory text');
 for(const id of ['LotteryGW2FooterSkin','LotteryGW2FooterRule'])assert.equal(nodes[id].style.visibility,details?'collapse':'visible','the removed details footer leaves no blank backing or divider');
 assert.equal(nodes.LotteryPoolGuarantee.style.visibility,'collapse');
 assert.equal(nodes.LotteryInfoList.style.overflow,'squish scroll','the taller list retains vertical scrolling');
 assert(!nodes.LotteryGW2InfoBack,'the duplicate bottom return button is never created');
}
current.Feature('details');infoBounds(18,true);
assert.equal(config.SurvivalUILayers.Top(),'lottery_info','Escape closes the details layer owned by the controller');
assert.equal(nodes.LotteryInfoDialog.style.width,'1309px');assert.equal(nodes.LotteryInfoDialog.style.transform,'none');
assert.equal(nodes.LotteryCelestialFooter.style.visibility,'collapse');
const detailMainTitle=nodes.LotteryTitle.text,detailMainTickets=nodes.LotteryGW2TicketBalance.text,detailSwitchStart=requests.length;
for(const id of ['map','cultivation','dragon_knight','summer']){
 const start=requests.length;nodes['LotteryGW2Pool_'+id].events.onactivate();
 const read=requests.slice(start).find(r=>r.n==='ui_lottery_snapshot_request'&&r.p.snapshot_scope==='details');
 if(read){
  assert.equal(read.p.pool_id,id,'each uncached detail tab requests its own pool');
  const sample=data(id);if(id==='cultivation')sample.items=Array.from({length:80},(_,i)=>({...sample.items[i%17],id:'scroll_reward_'+i}));
  events.ui_lottery_snapshot({...sample,snapshot_scope:'details',snapshot_request_id:read.p.snapshot_request_id});
 }
 assert.equal(presentation.Inspect().selected,id,'each of the four detail tabs selects its authoritative pool');poolNavigation(id);ticketAlignment();infoBounds(18,true);
 if(id==='cultivation'){
  const scrollCards=nodes.LotteryInfoList.children.filter(c=>c.BHasClass('LotteryDetailRow'));
  assert.equal(scrollCards.length,80,'a long prize list retains all controller-owned rewards');
  const last=scrollCards.at(-1);assert(parseFloat(last.style.position.split(' ')[1])+parseFloat(last.style.height)>parseFloat(nodes.LotteryInfoList.style.height),'the scroll content extends past the enlarged viewport');
 }
 assert.equal(nodes.LotteryTitle.text,detailMainTitle);assert.equal(nodes.LotteryGW2TicketBalance.text,detailMainTickets,'detail pool switches preserve the main draw balance');
}
assert(!requests.slice(detailSwitchStart).some(r=>/draw|purchase|checkout|claim/.test(r.n)),'detail tabs remain read-only');
nodes.LotteryGW2Back.events.onactivate();assert.equal(config.SurvivalUILayers.Top(),'lottery','the upper-left return closes only the details layer');
assert.equal(presentation.Inspect().mode,'');assert.equal(nodes.LotteryGW2Title.text,'抽奖');assert.equal(presentation.Inspect().selected,'map');
assert.equal(nodes.LotteryGW2FooterSkin.style.visibility,'visible','upper-left return restores the main draw footer');
current.Feature('details');infoBounds(18,true);
const cells=nodes.LotteryInfoList.children.filter(c=>c.BHasClass('LotteryDetailRow'));
assert.equal(cells.length,17);assert(cells.every(c=>c.__lotteryGW2Cell),'decorate every existing reward');
assert.equal(cells[0].__lotteryGW2Cell.count.text,'0','quality sorting keeps real zero');
assert(cells.some(c=>c.__lotteryGW2Cell.count.text==='—'),'unknown quantity is not zero');
assert(cells.some(c=>c.__lotteryGW2Cell.count.text==='2/5'),'only actual maximum is shown');
presentation.Fit();const steady=presentation.Inspect();
for(let i=0;i<30;i++){current.Feature('details');presentation.Fit();assert(presentation.Inspect().trackedOwned<=steady.trackedOwned,'deleted reward visuals cannot accumulate');assert(presentation.Inspect().trackedMoved<=steady.trackedMoved,'deleted native icons cannot accumulate');}
const first=nodes.LotteryInfoList.children.find(c=>c.BHasClass('LotteryDetailRow')),before=requests.length;first.events.onmouseover();assert.equal(requests.length,before,'hover is read-only');
// Reapplying the real modal stack raises the details ancestry after Info().
const layerProbe=new Panel('Panel',root,'LotteryTooltipLayerProbe');
config.SurvivalUILayers.Open('tooltip_layer_probe',layerProbe,()=>{});config.SurvivalUILayers.Close('tooltip_layer_probe');
first.events.onmouseover();
assert(Number(nodes.LotteryGW2Tooltip.style.zIndex)>Number(nodes.LotteryInfoOverlay.style.zIndex),'Tooltip must stay above details after modal layers are reapplied');
const oldContentZ=String(Number(nodes.LotteryGW2Content.style.zIndex)||0);nodes.LotteryGW2Content.style.zIndex='100010';
first.events.onmouseover();assert(Number(nodes.LotteryGW2DetailLayer.style.zIndex)>100010,'The tooltip ancestry must also clear raised preview content');nodes.LotteryGW2Content.style.zIndex=oldContentZ;
assert.equal(nodes.LotteryGW2TooltipName.GetParent(),nodes.LotteryGW2TooltipTitleRow);assert.equal(nodes.LotteryGW2TooltipName.style.verticalAlign,'center');
layerProbe.DeleteAsync();
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
const scrollSurface=scrollTip.children.find(node=>node.BHasClass('BLMarketDetailSurface'));
Object.defineProperty(scrollSurface,'actuallayoutwidth',{get(){return parseFloat(this.style.width)||368;}});
Object.defineProperty(scrollSurface,'actuallayoutheight',{get(){return parseFloat(this.style.height)||0;}});
// No timer/frame is advanced between the physical exit and the next hover.
const fastRoot=[root.actuallayoutwidth,root.actuallayoutheight],fastCanvas=presentation.Inspect().canvas;
root.actuallayoutwidth=fastCanvas[0];root.actuallayoutheight=fastCanvas[1];presentation.Fit();
const fastA=new Panel('Panel',root,''),fastB=new Panel('Panel',root,'');
for(const node of [fastA,fastB]){node.actuallayoutwidth=72;node.actuallayoutheight=72;}
fastA.style.position='120px 160px 0px';fastB.style.position='240px 160px 0px';
const fastItem={id:'fast-hover',name:'快速悬停',description:'攻击+1'},fastRequests=requests.length;
function sourceExit(){if(!presentation.RequestTooltipHide())presentation.HideTooltip();}
function insideFast(node){const at=node.GetPositionWithinWindow();tooltipCursor=[at.x+2,at.y+2];}
tooltipCursor=[1800,1000];presentation.HideTooltip();insideFast(fastA);presentation.Tooltip(fastItem,fastA);
assert(scrollTip.visible);insideFast(scrollTip);scrollTip.events.onmouseover();assert(!scrollTip.visible);
// A dismissed popup remains suppressed until a real source exit.
insideFast(fastA);presentation.Tooltip(fastItem,fastA);assert(!scrollTip.visible);
tooltipCursor=[1800,1000];sourceExit();insideFast(fastA);presentation.Tooltip(fastItem,fastA);
assert(scrollTip.visible,'Fast source exit/re-entry must reopen before the 30ms watcher tick');
let lastFast=fastA;const fastOwners=config.SurvivalTooltipDismiss.Inspect().owners;
for(let i=0;i<50;i++){
 const oldAt=scrollTip.GetPositionWithinWindow();insideFast(scrollTip);scrollTip.events.onmouseover();assert(!scrollTip.visible);
 tooltipCursor=[1800,1000];sourceExit();
 const next=i%2?fastA:fastB;next.style.position=(oldAt.x+12)+'px '+(oldAt.y+12)+'px 0px';insideFast(next);
 presentation.Tooltip({...fastItem,name:'切换 '+i},next);
 assert(scrollTip.visible,'A new icon inside the old popup footprint must show without a frame');
 assert.equal(nodes.LotteryGW2TooltipName.text,'切换 '+i);
 lastFast.events.onmouseout();assert(scrollTip.visible,'A late leave from the old icon cannot close the newly shown tooltip');lastFast=next;
}
advance(.4);assert(scrollTip.visible,'The latest hover survives finite layout callbacks and the passive watcher');
assert.equal(config.SurvivalTooltipDismiss.Inspect().owners,fastOwners,'Rapid switches do not retain dismissed owners');
tooltipCursor=[1800,1000];sourceExit();fastA.DeleteAsync();fastB.DeleteAsync();
root.actuallayoutwidth=fastRoot[0];root.actuallayoutheight=fastRoot[1];presentation.Fit();
assert(!requests.slice(fastRequests).some(r=>/draw|purchase|checkout|claim/.test(r.n)),'Rapid hover remains read-only');
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
current.Feature('history');assert.equal(nodes.LotteryGW2Title.text,'抽奖记录');infoBounds(64);
const fullHistory=nodes.LotteryInfoList.children.filter(c=>c.BHasClass('RHHistoryRow'));assert.equal(fullHistory.length,10,'the offline result flow supplies real controller-owned history rows');
for(const row of fullHistory){
 assert.equal(row.style.width,'1286px','each newly assembled history row fills the enlarged list');
 const name=row.children.find(c=>c.BHasClass('RHHistoryName')),quality=row.children.find(c=>c.BHasClass('RHHistoryQuality')),quantity=row.children.find(c=>c.BHasClass('RHHistoryQuantity'));
 assert.equal(name.style.width,'656px','reward names use the extra horizontal space');
 assert.equal(quality.style.position,'978px 0px 0px');assert.equal(quantity.style.position,'1134px 0px 0px');
 assert(parseFloat(quantity.style.position)+94<=parseFloat(row.style.width),'the final history column stays inside the row');
}
current.CloseInfo();current.CloseResult();current.Feature('announcement');assert.equal(nodes.LotteryGW2Title.text,'开奖公告');infoBounds(64);
assert.equal(nodes.LotteryInfoNote.text,'当前奖池规则','the shared announcement note remains visible');
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
for(const [w,h,s] of [[1280,720,1],[1920,1080,1],[2560,1440,1.5],[3440,1440,1],[1366,768,1],[1920,1200,1],[2560,1080,1]]){root.actuallayoutwidth=w;root.actuallayoutheight=h;root.actualuiscale_x=s;root.actualuiscale_y=s;presentation.Fit();assert.equal(nodes.LotteryMainCanvas.style.transform,'scale3d('+Math.min(w/s/1672,h/s/941)+','+Math.min(w/s/1672,h/s/941)+',1)');}
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
// A still-live renderer from the retired shell, or from another HUD owner,
// must never be accepted simply because it exposes the historical API names.
const controllerSource=fs.readFileSync('panorama/src/scripts/custom_game/lottery_ui_remaining_5d5c1152eb.js','utf8');
function mountController(){vm.runInNewContext(controllerSource,env);return config.SurvivalLottery;}
function allPanels(node){return [node,...node.Children().flatMap(allPanels)];}
function assertGateHidden(message){assert(!nodes.LotteryWindow.BHasClass('LotteryOpen'),message);assert(nodes.LotteryWindow.BHasClass('LotteryClosed'));assert.equal(nodes.LotteryWindow.visible,false);assert(nodes.LotteryItemTooltip.BHasClass('Hidden'));}
function mainReadsSince(index){return requests.slice(index).filter(r=>r.n==='ui_lottery_snapshot_request'&&!r.p.snapshot_scope&&!r.p.prefetch);}
function drawRequestsSince(index){return requests.slice(index).filter(r=>r.n==='ui_lottery_draw_request');}
const savedMenu=config.SurvivalMenuV10,savedAdopt=config.SurvivalUI.ModalShell.Adopt,savedRHWindow=config.RemainingHandoff.Window,savedOldActions=config.RemainingHandoff.LotteryActions;
config.SurvivalMenuV10=null;
config.SurvivalUI.ModalShell.Adopt=function(){throw Error('The retired lottery modal must never be recreated');};
config.RemainingHandoff.Window=function(){throw Error('No legacy lottery window fallback');};
config.RemainingHandoff.LotteryActions=function(){throw Error('No retired lottery NineSlice actions');};
for(const rejected of ['retired-version','foreign-owner','not-ready']){
 let oldCalls=0,oldDisposed=false;
 const stale={Version:rejected==='retired-version'?'lottery_retired_1536':'lottery_current_20261018',
  IsAlive:()=>!oldDisposed,Owns:()=>rejected!=='foreign-owner',IsReady:()=>rejected!=='not-ready',Dispose(){oldDisposed=true;}};
 for(const method of ['Open','Apply','Fit','Close','CloseInfo','Pools','Snapshot','Compact','StyleTabs','HideTooltip','Tooltip','Info'])stale[method]=function(){oldCalls++;throw Error('Rejected renderer was invoked: '+rejected+' '+method);};
 config.SurvivalPurpleLottery=stale;
 const gated=mountController(),start=requests.length;
 nodes.LotteryItemTooltip.RemoveClass('Hidden');gated.Open();gated.Open();gated.Feature('details');
 advance(.4);assertGateHidden(rejected+' stays hidden while awaiting the current renderer');
 assert.equal(requests.length,start,'waiting neither requests a snapshot nor submits a transaction');assert.equal(oldCalls,0);
 assert.equal(gated.PresentationReady(stale),false,'an old readiness notification cannot complete the entry intent');
 const installed=loadPresentation();
 assert.equal(installed.api.Version,'lottery_current_20261018');assert(installed.api.Owns(root)&&installed.api.IsReady());
 assert(!installed.api.Owns(new Panel('Panel',root,'')),'owner equality is checked against the HUD root');
 assert(nodes.LotteryWindow.BHasClass('LotteryOpen')&&nodes.LotteryWindow.visible);
 assert.equal(mainReadsSince(start).length,1,'delayed registration resumes exactly one uncached open');
 gated.PresentationReady(installed.api);gated.Open();advance(.4);
 assert.equal(mainReadsSince(start).length,1,'repeat entry/readiness does not duplicate the request');
 assert(!requests.slice(start).some(r=>r.p.prefetch),'the first open subsumes the delayed prefetch');
 assert.equal(allPanels(root).filter(n=>n.BHasClass('LotteryGW2Shell')).length,1,'only the current renderer shell is attached');
 gated.Close();gated.Dispose();installed.api.Dispose();
}
// Closing or replacing a waiting controller cancels its single entry intent;
// an eventual current renderer cannot resurrect the old user's click.
for(const cancel of ['close','dispose','replace-controller','shop-open']){
 config.SurvivalPurpleLottery=null;
 const waiting=mountController(),start=requests.length;
 if(cancel==='shop-open')waiting.OpenFromShop();else{waiting.Open();waiting.Open();}
 if(cancel==='close'||cancel==='shop-open')waiting.Close();else waiting.Dispose();
 const replacement=cancel==='replace-controller'?mountController():null;
 const installed=loadPresentation();advance(.4);
 assertGateHidden(cancel+' cancels the waiting entry');assert.equal(mainReadsSince(start).length,0);
 if(replacement){replacement.Open();assert.equal(mainReadsSince(start).length,1);replacement.Close();replacement.Dispose();}
 else waiting.Dispose();
 installed.api.Dispose();
}
config.SurvivalMenuV10=savedMenu;config.SurvivalUI.ModalShell.Adopt=savedAdopt;config.RemainingHandoff.Window=savedRHWindow;config.RemainingHandoff.LotteryActions=savedOldActions;
// Presentation-only reload does not replace the business controller or issue
// another snapshot, even before the original reply or during an in-flight draw.
config.SurvivalPurpleLottery=null;
const preserved=mountController(),firstCurrent=loadPresentation(),preservedStart=requests.length;
preserved.Open();assert.equal(mainReadsSince(preservedStart).length,1);
const beforeReply=loadPresentation();assert.strictEqual(config.SurvivalLottery,preserved);
assert(!firstCurrent.api.IsAlive()&&beforeReply.api.IsAlive());assert(nodes.LotteryWindow.BHasClass('LotteryOpen'));
assert.equal(mainReadsSince(preservedStart).length,1,'renderer-only reload keeps the original snapshot in flight');
events.ui_lottery_snapshot(data('map',100));nodes.LotterySkipAnimation.checked=true;preserved.SetSkipAnimation();
preserved.DrawTen();const pendingDraw=drawRequestsSince(preservedStart).at(-1);assert(pendingDraw);
const whileDrawing=loadPresentation();preserved.Open();preserved.DrawTen();preserved.DrawSingle();
assert.strictEqual(config.SurvivalLottery,preserved);assert(whileDrawing.api.Inspect().open);
assert.equal(drawRequestsSince(preservedStart).length,1,'renderer reload and reopen retain the existing draw guard');
assert.equal(mainReadsSince(preservedStart).length,1,'restoring presentation does not refetch the snapshot');
const accepted={ok:1,request_id:pendingDraw.p.request_id,pool_id:'map',count:10,results:results(10),snapshot:data('map',90)};
events.ui_lottery_result(accepted);events.ui_lottery_result(accepted);
assert.equal(nodes.LotteryItemList.children.length,10);
preserved.Feature('history');assert.equal(nodes.LotteryInfoList.children.filter(n=>n.BHasClass('RHHistoryRow')).length,10,'a duplicate result cannot append another history entry after a renderer reload');
assert.equal(drawRequestsSince(preservedStart).length,1);
assert.equal(allPanels(root).filter(n=>n.BHasClass('LotteryGW2Shell')).length,1);
const historyPresentation=loadPresentation();
assert.equal(config.SurvivalUILayers.Top(),'lottery_info','renderer-only reload restores the active inline details layer above the main window');
assert.equal(nodes.LotteryInfoList.children.filter(n=>n.BHasClass('RHHistoryRow')).length,10);
assert.equal(mainReadsSince(preservedStart).length,1,'restoring an inline view does not issue another page snapshot');
preserved.Close();preserved.Dispose();historyPresentation.api.Dispose();
console.log('LOTTERY_CURRENT_RENDERER_GATE_PASS: live retired/foreign/unready rejection, one deferred open, close/dispose/reload cancellation, no legacy modal and pending draw/result identity through renderer-only replacement');
console.log('LOTTERY_LAYOUT_RELOAD_PASS: dead production lifetime, controller-first XML order, disposed API replacement, fresh snapshot request, real shell/details/close and previous compiled renderer transition');
console.log('LOTTERY_GW2_PASS: independent shell, native controls, four authoritative pools, scoped actual art/fallback/details, zero/unknown counts, ten results, pending/foreign-modal guards, 30 rebuilds without stale refs, seven fits, 12 opens, restored parents/factories and renderer reload');
`;
vm.runInNewContext(loader+'suite+='+JSON.stringify(setup)+';vm.runInNewContext(suite,{require:require("node:module").createRequire(require("path").resolve("tools/test_lottery_ui.js")),console});',{require:require('node:module').createRequire(path.resolve('tools/tests/lottery_gw2.test.cjs')),console});
