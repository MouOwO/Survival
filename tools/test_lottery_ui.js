"use strict";
const fs=require('fs'),vm=require('vm'),assert=require('assert');
const nodes={},events={},requests=[],queue=[],logs=[];let now=0;
// Node supports ICU; Panorama must not depend on it to display awarded items.
class EmbeddedDate extends Date {
 constructor(){super(2026,8,7,9,4,2)}
 toLocaleTimeString(){throw new Error('Native locale formatting must not be called')}
 toLocaleDateString(){throw new Error('Native locale formatting must not be called')}
 toLocaleString(){throw new Error('Native locale formatting must not be called')}
}
class Panel{
 constructor(type,parent,id){this.type=type;this.parent=parent;this.id=id;this.children=[];this.classes=new Set();this.style=new Proxy({}, {set(target,key,value){if(key==='zIndex'&&!/^-?\d+$/.test(String(value)))throw new Error('Invalid Panorama z-index: '+JSON.stringify(value));target[key]=value;return true}});this.events={};this.enabled=true;if(parent)parent.children.push(this);if(id)nodes[id]=this;}
 GetParent(){return this.parent} IsValid(){return true}
 AddClass(c){this.classes.add(c)} RemoveClass(c){this.classes.delete(c)} SetHasClass(c,on){on?this.AddClass(c):this.RemoveClass(c)} BHasClass(c){return this.classes.has(c)}
 RemoveAndDeleteChildren(){this.children=[]} SetPanelEvent(name,cb){this.events[name]=cb} SetImage(path){this.image=path}
}
const root=new Panel('Panel',null,'root');
const xml=fs.readFileSync('panorama/src/layout/custom_game/lottery_window.xml','utf8');
for(const m of xml.matchAll(/id="([^"]+)"/g))new Panel('Panel',root,m[1]);
for(const id of ['LotteryItemTooltip','LotteryTooltipIconHost','LotteryTooltipName','LotteryTooltipType','LotteryTooltipDuration','LotteryTooltipDescription'])new Panel('Panel',root,id);
function $(id){return nodes[id.slice(1)]} $.CreatePanel=(t,p,id)=>new Panel(t,p,id);$.Schedule=(seconds,cb)=>queue.push({at:now+seconds,cb});$.Msg=(message)=>logs.push(message);
const config={};const env={Date:EmbeddedDate,Intl:undefined,$,GameUI:{CustomUIConfig:()=>config},GameEvents:{Subscribe:(n,cb)=>events[n]=cb,SendCustomGameEventToServer:(n,p)=>requests.push({n,p})}};
vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/ui_layers.js','utf8'),env);
vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/reward_presentation.js','utf8'),env);
require('./load_shared_ui_test.cjs')(env,Panel,root);
vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/lottery_ui.js','utf8'),env);
const ui=config.SurvivalLottery;
function advance(seconds){const end=now+seconds;while(true){queue.sort((a,b)=>a.at-b.at);if(!queue.length||queue[0].at>end)break;const x=queue.shift();now=x.at;x.cb()}now=end}
function snapshot(pool='map',tickets=20){return {selected_pool_id:pool,selected_pool:{id:pool,display_name:pool,tickets,single_cost:1,ten_cost:10,ticket_name:'抽奖券',pity:[{label:'10连保底 SR'}]},pools:[{id:'map',display_name:'地图抽奖',pity:[{label:'10连保底 SR'}]},{id:'summer',display_name:'暑期宝箱'}],items:[{id:'one',name:'真实道具',description:'英雄初始攻击+10',quality:'sr',icon:'item_blink',duplicate_points:20}],starjoy_points:10}}
function results(count){return Array.from({length:count},(_,i)=>({id:'item'+i,name:'物品'+i,description:'属性'+i,quality:i===0?'sr':'n',icon:'item_blink',duplicate:i===1,converted_points:20}))}
ui.Open();assert.equal(config.SurvivalUILayers.Top(),'lottery');assert.equal(root.style.zIndex,'100000');assert.equal(requests[0].n,'ui_lottery_snapshot_request');assert(!nodes.LotterySingleButton.enabled);
events.ui_lottery_snapshot(snapshot());assert(nodes.LotteryTenButton.enabled);assert.equal(nodes.LotteryTitle.text,'地图宝箱');
ui.DrawTen();const req=requests.at(-1);ui.DrawTen();ui.SelectPool('summer');assert.equal(requests.at(-1),req);assert(!nodes.LotterySingleButton.enabled);
assert.deepEqual(Object.keys(req.p).sort(),['count','pool_id','request_id']);assert.equal(req.p.count,10);
events.ui_lottery_result({ok:1,request_id:req.p.request_id,pool_id:'map',count:10,results:results(10),snapshot:snapshot('map',10)});
assert(logs.some(s=>s.includes('stage=result_received')));
assert(logs.some(s=>s.includes('stage=cards_ready count=10')));
assert(logs.some(s=>s.includes('stage=reveal_ready animated=true')));
assert(nodes.LotteryWindow.BHasClass('LotteryAnimating'));assert.equal(nodes.LotteryItemList.children.length,10);assert(nodes.LotteryItemList.BHasClass('LotteryTenResults'));
assert(nodes.LotteryItemList.children.every(c=>c.BHasClass('LotteryCardCovered')));assert(!nodes.LotteryAgain.enabled);
advance(1.5);assert(!nodes.LotteryItemList.children[0].BHasClass('LotteryCardCovered'));assert(nodes.LotteryItemList.children[9].BHasClass('LotteryCardCovered'));
ui.SkipReveal();assert(nodes.LotteryItemList.children.every(c=>!c.BHasClass('LotteryCardCovered')));assert(nodes.LotteryAgain.enabled);advance(5);assert(!nodes.LotteryWindow.BHasClass('LotteryAnimating'));
ui.Feature('history');let historyCount=nodes.LotteryInfoList.children.length;events.ui_lottery_result({ok:1,request_id:req.p.request_id,results:results(10)});ui.Feature('history');assert.equal(nodes.LotteryInfoList.children.length,historyCount);
function allText(node){return [node.text||'',...node.children.map(allText)].join(' ')}
assert(allText(nodes.LotteryInfoList).includes('09:04:02'),'history must display zero-padded time without locale support');
ui.CloseInfo();ui.DrawAgain();assert.equal(requests.at(-1).p.count,10);events.ui_lottery_result({ok:0,error:'lottery_ticket_insufficient',snapshot:snapshot('map',0)});assert(!nodes.LotteryAgain.enabled);
ui.CloseResult();events.ui_lottery_snapshot(snapshot());nodes.LotterySkipAnimation.checked=true;ui.SetSkipAnimation();ui.DrawSingle();events.ui_lottery_result({ok:1,request_id:requests.at(-1).p.request_id,pool_id:'map',results:results(1),snapshot:snapshot('map',19)});
assert(nodes.LotteryItemList.BHasClass('LotterySingleResult'));assert(!nodes.LotteryWindow.BHasClass('LotteryAnimating'));assert.equal(nodes.LotteryAgainText.text,'再开一次');
ui.Feature('details');assert.equal(nodes.LotteryInfoList.children.length,1);assert(nodes.LotteryInfoList.children[0].children[1].children.some(c=>c.text==='英雄初始攻击+10'));
const before=requests.length;ui.Feature('purchase');ui.Feature('firstgift');ui.Feature('privilege');assert.equal(requests.length,before);
ui.CloseResult();ui.SelectPool('summer');assert(!nodes.LotterySingleButton.enabled);events.ui_lottery_snapshot(snapshot('map',999));assert(!nodes.LotterySingleButton.enabled);events.ui_lottery_snapshot(snapshot('summer',10));assert(nodes.LotteryTenButton.enabled);
nodes.LotterySkipAnimation.checked=false;ui.SetSkipAnimation();ui.DrawSingle();ui.Close();events.ui_lottery_result({ok:1,request_id:requests.at(-1).p.request_id,pool_id:'summer',results:results(1),snapshot:snapshot('summer',9)});assert(nodes.LotteryWindow.BHasClass('LotteryClosed'));assert(!nodes.LotteryWindow.BHasClass('LotteryAnimating'));ui.Open();assert.equal(nodes.LotteryItemList.children.length,1);
ui.DrawSingle();events.ui_lottery_result({ok:1,request_id:requests.at(-1).p.request_id,pool_id:'summer',results:results(1),snapshot:snapshot('summer',8)});ui.Close();advance(10);assert(nodes.LotteryWindow.BHasClass('LotteryClosed'));assert(!nodes.LotteryWindow.BHasClass('LotteryAnimating'));
for(const match of xml.matchAll(/SurvivalLottery\.([A-Za-z]+)\(/g))assert.equal(typeof ui[match[1]],'function','missing callback '+match[1]);
ui.Close();assert.equal(config.SurvivalUILayers.Top(),null);assert.equal(root.style.zIndex,'0');
ui.Open();ui.CloseResult();
for(const poolId of ['map','cultivation','dragon_knight','summer']){
 ui.SelectPool(poolId);ui.Feature('details');assert.equal(nodes.LotteryInfoList.children.length,0,'no stale pool rewards while loading');
 const data=snapshot(poolId,0);data.selected_pool.single_cost=0;events.ui_lottery_snapshot(data);
 ui.CloseInfo();assert(nodes.LotterySingleButton.enabled);assert.equal(nodes.LotterySingleText.text,'免费开启1个');assert(!nodes.LotteryTenButton.enabled);
 ui.DrawSingle();const request=requests.at(-1);ui.DrawSingle();assert.equal(requests.at(-1),request);
 events.ui_lottery_result({ok:1,request_id:request.p.request_id,pool_id:poolId,results:results(1),snapshot:data});
 advance(2.05);assert(!nodes.LotteryWindow.BHasClass('LotteryAnimating'));const count=requests.length;ui.CloseResult();assert.equal(requests.length,count,'confirmation never grants or draws');
}
console.log('LOTTERY_UI_PASS: single/ten, request guard, server data, replay, skipped/cancelled reveal, stale pools, balance, details, history, placeholders, XML callbacks');
ui.Close();
root.style.zIndex='17';
ui.Open();ui.Feature('details');
assert.equal(config.SurvivalUILayers.Top(),'lottery_info');
config.SurvivalUILayers.CloseTop();
assert.equal(config.SurvivalUILayers.Top(),'lottery');
assert.equal(root.style.zIndex,'100000');
ui.CloseInfo(); // Closing a non-open overlay must not rebuild the layer stack.
ui.Close();ui.Close();
assert.equal(root.style.zIndex,'17','restore explicit preexisting HUD layer');
assert.equal(config.SurvivalUILayers.Top(),null);
console.log('LOTTERY_LAYER_PASS: numeric-only styles, nested modal, repeated close, original layer restored');

ui.Open();ui.CloseResult();
const pools=['map','cultivation','dragon_knight','summer'];
for(const id of pools){
 ui.SelectPool(id); const data=snapshot(id,20);data.pools=pools.map(id=>({id,display_name:id}));
 data.selected_pool.description=id+' rule';data.items=[{id:id+'_a',name:id+' A',description:id+' effect',icon:'item_ogre_axe',quality:'n',owned_count:2,max_owned:5},{id:id+'_b',name:id+' B',description:'second effect',icon:'item_mjollnir',quality:'sr',owned_count:0}];
 events.ui_lottery_snapshot(data);ui.Feature('details');assert.equal(nodes.LotteryInfoTabs.children.length,4);
 assert.equal(nodes.LotterySelectedName.text,id+' A');assert(nodes.LotterySelectedMeta.text.includes('2/5'));
 assert(!nodes.LotterySingleButton.enabled);const before=requests.length;ui.DrawSingle();ui.DrawTen();ui.DrawAgain();assert.equal(requests.length,before,'modal blocks underlying draw requests');
 nodes.LotteryInfoList.children[1].events.onactivate();assert.equal(nodes.LotterySelectedName.text,id+' B');assert.equal(nodes.LotterySelectedDescription.text,'second effect');
 assert.equal(nodes.LotteryInfoTitle.text,'奖池详情');assert.equal(nodes.LotteryInfoList.children.length,2);assert(nodes.LotteryInfoList.children[1].BHasClass('Selected'));
 const cell=nodes.LotteryInfoList.children[1],beforeHover=requests.length;cell.events.onmouseover();assert(nodes.LotteryItemTooltip.BHasClass('LotterySimpleTooltip'));assert(!nodes.LotteryItemTooltip.BHasClass('Hidden'));assert.equal(nodes.LotteryTooltipName.text,id+' B');assert.equal(nodes.LotteryTooltipDescription.text,'second effect');assert.equal(nodes.LotteryTooltipIconHost.children.length,0);assert.equal(requests.length,beforeHover);cell.events.onmouseout();assert(nodes.LotteryItemTooltip.BHasClass('Hidden'));ui.Feature('details');
 ui.SelectPool(id);assert(!nodes.LotteryInfoOverlay.BHasClass('LotteryInfoHidden'),'scrim remains during loading');assert.equal(nodes.LotteryInfoList.children.length,0);assert.equal(nodes.LotterySelectedDescription.text,'');
 events.ui_lottery_snapshot(snapshot('stale',999));assert.equal(nodes.LotteryInfoList.children.length,0);
 events.ui_lottery_snapshot(data);assert.equal(nodes.LotterySelectedName.text,id+' A');
 const count=requests.length;ui.CloseInfo();assert.equal(requests.length,count);assert(nodes.LotterySingleButton.enabled);
}
ui.Feature('details');ui.SelectPool('summer');ui.CloseInfo();events.ui_lottery_snapshot(snapshot('summer'));assert(nodes.LotteryInfoOverlay.BHasClass('LotteryInfoHidden'),'late snapshot must not reopen dismissed modal');
ui.Feature('details');const empty=snapshot('summer');empty.items=[];events.ui_lottery_snapshot(empty);assert.equal(nodes.LotterySelectedName.text,'暂无奖励');assert.equal(nodes.LotteryInfoList.children.length,0);
console.log('LOTTERY_V2_PASS: four pools, real selection, empty/loading/stale states, modal draw guard and close');

ui.CloseInfo();const overlay=root;overlay.actuallayoutwidth=1920;overlay.actuallayoutheight=1080;overlay.actualuiscale_x=1;overlay.actualuiscale_y=1;
ui.Feature('details');const fitAt1080=nodes.LotteryInfoDialog.style.transform;
overlay.actuallayoutwidth=1280;overlay.actuallayoutheight=720;overlay.actualuiscale_x=2/3;overlay.actualuiscale_y=2/3;
ui.Feature('details');assert.equal(nodes.LotteryInfoDialog.style.transform,fitAt1080,'native scaling must be removed exactly once');
const axes=nodes.LotteryInfoDialog.style.transform.match(/scale3d\(([^,]+),([^,]+),1\)/);assert.equal(axes[1],axes[2],'uniform axes');
ui.Feature('history');assert.equal(nodes.LotteryInfoDialog.style.transform,fitAt1080);ui.CloseInfo();advance(1);
console.log('LOTTERY_FIXED_DESIGN_PASS: native scale compensation, uniform transform, shared modal sizing');

ui.Open();ui.CloseResult();events.ui_lottery_snapshot(snapshot('summer',20));ui.Feature('details');

function rewardImages(node){return [...(node.BHasClass('LotteryRewardIcon')?[node]:[]),...node.children.flatMap(rewardImages)]}
const samples=rewardImages(nodes.LotteryInfoList);assert(samples.length>0);assert(samples.every(i=>i.type==='DOTAItemImage'&&!!i.itemname),'pool artwork comes from configured item resources');
ui.CloseInfo();nodes.LotterySkipAnimation.checked=true;ui.SetSkipAnimation();events.ui_lottery_snapshot(snapshot('summer',20));ui.DrawTen();events.ui_lottery_result({ok:1,request_id:requests.at(-1).p.request_id,pool_id:'summer',results:results(10),snapshot:snapshot('summer',10)});
assert.equal(nodes.LotteryItemList.children.length,10);assert(rewardImages(nodes.LotteryItemList).every(i=>i.type==='DOTAItemImage'&&i.itemname==='item_blink'));assert(allText(nodes.LotteryItemList).includes('物品9'),'real result names preserved');
console.log('LOTTERY_REAL_ART_PASS: configured resources on pool/results, real names/counts retained');

ui.CloseResult();ui.CloseInfo();ui.SelectPool('map');events.ui_lottery_snapshot(snapshot('map',20));ui.Feature('details');
const mainTitle=nodes.LotteryTitle.text,mainTicket=nodes.LotteryTicketValue.text;
const summerTab=nodes.LotteryInfoTabs.children.find(b=>b.children.some(c=>c.text==='暑期宝箱'));summerTab.events.onactivate();
const detailReq=requests.at(-1).p;assert.equal(detailReq.snapshot_scope,'details');assert.equal(nodes.LotteryInfoList.children.length,0);
events.ui_lottery_snapshot({...snapshot('summer',3),snapshot_scope:'details',snapshot_request_id:detailReq.snapshot_request_id});
assert.equal(nodes.LotteryTitle.text,mainTitle);assert.equal(nodes.LotteryTicketValue.text,mainTicket);
assert(nodes.LotteryPoolTabs.children[0].BHasClass('Selected'));assert(nodes.LotteryInfoTabs.children[1].BHasClass('Selected'));
ui.CloseInfo();events.ui_lottery_snapshot({...snapshot('summer',0),snapshot_scope:'details',snapshot_request_id:detailReq.snapshot_request_id});
assert.equal(nodes.LotteryTicketValue.text,mainTicket);assert(nodes.LotteryTenButton.enabled);ui.DrawSingle();assert.equal(requests.at(-1).p.pool_id,'map');
assert(nodes.LotteryInfoDialog.BHasClass("UIModal"));assert(!nodes.LotteryNineSlice,"unclean legacy frame slices are not recreated");
console.log('LOTTERY_INDEPENDENT_DETAILS_PASS: modal selection, late response and subsequent draw remain isolated; shared shell; legacy frame removed');
