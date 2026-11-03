'use strict';
// Reuse the real controller/XML/renderer fixture, stopping before its broad
// historical visual assertions. No SDK, native input, draw or player data.
const fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
const existing=fs.readFileSync('tools/tests/lottery_gw2.test.cjs','utf8');
const start=existing.indexOf('const setup=`')+'const setup=`'.length;
const end=existing.indexOf('const realReward=');
if(start<12||end<=start)throw new Error('The shared production fixture boundary changed');
let setup=vm.runInNewContext('`'+existing.slice(start,end)+'`');
const insert='const source=fs.readFileSync(\'panorama/src/scripts/custom_game/lottery_gw2.js\',\'utf8\');';
if(setup.split(insert).length!==2)throw new Error('The renderer fixture anchor changed');
setup=setup.replace(insert,`const originalConfirm=()=>{confirmCalls++;current.CloseResult();};let confirmCalls=0;
nodes.LotteryConfirm.SetPanelEvent('onactivate',originalConfirm);
${insert}`);
setup+=`
function descendants(node){return [node,...node.Children().flatMap(descendants)];}
function badge(card){return descendants(card).find(n=>n.BHasClass('LotteryGW2Ownership'));}
function cardByItem(host,id){return host.Children().find(card=>card.__lotteryItem&&card.__lotteryItem.id===id);}
function rect(node){const a=String(node.style.position).split(' ');return{x:parseFloat(a[0])||0,y:parseFloat(a[1])||0,w:parseFloat(node.style.width),h:parseFloat(node.style.height)};}
function data(){const value=snapshot('map',40);value.items=[
 {id:'held',name:'已持有奖励',quality:'sr',icon:'item_blink',owned_count:3,max_owned:5},
 {id:'fresh',name:'未持有奖励',quality:'sr',icon:'item_blink',owned_count:0,owned:false,count:20},
 {id:'flag',name:'持有标记奖励',quality:'sr',icon:'item_blink',owned:true},
 {id:'unknown',name:'未知库存奖励',quality:'sr',icon:'item_blink',count:99}
];return value;}
current.Open();const authoritative=data();events.ui_lottery_snapshot(authoritative);
const previews=['held','fresh','flag','unknown'].map(id=>Object.values(nodes).find(n=>n.BHasClass('LotteryGW2PreviewCard')&&n.IsValid()&&n.__lotteryItem.id===id));
assert(previews.every(Boolean));
for(const [index,card]of previews.entries()){
 const tag=badge(card);assert(tag,'Each real preview has a reusable independent text label');
 assert.equal(tag.paneltype,'Label');assert.equal(tag.hittest,false);assert.equal(tag.hittestchildren,false);
 assert.equal(tag.visible,index===0||index===2);assert.equal(tag.text,tag.visible?'已拥有':'');
 const b=rect(tag),well=rect(card.Children().find(n=>n.BHasClass('LotteryGW2PreviewWell')));
 assert(b.x>=well.x&&b.x+b.w<=well.x+well.w&&b.y+b.h<=well.y+well.h,'Ownership is contained at the image bottom');
 assert(b.y>=well.y+well.h-24,'The ownership row belongs to the image bottom');
}
const previewRefs=previews.slice(),ownedNodes=presentation.Inspect().trackedOwned;
presentation.Snapshot(authoritative);assert.equal(presentation.Inspect().trackedOwned,ownedNodes);
assert(previewRefs.every(card=>card.IsValid()),'An unchanged snapshot retains the four current cards');

current.Feature('details');let detail=cardByItem(nodes.LotteryInfoList,'held');assert(detail&&detail.__lotteryGW2Cell);
let tag=badge(detail),sameLabel=tag;assert.equal(tag.visible,true);assert.equal(tag.text,'已拥有');
assert(rect(detail.__lotteryGW2Cell.count).y+rect(detail.__lotteryGW2Cell.count).h<=rect(tag).y,'Quantity does not cover ownership');
detail.__lotteryItem={...detail.__lotteryItem,owned_count:0,owned:false};presentation.Compact(nodes.LotteryInfoList,detail);
assert.strictEqual(badge(detail),sameLabel);assert.equal(tag.visible,false);assert.equal(tag.text,'','A real ownership removal clears stale copy');
detail.__lotteryItem={...detail.__lotteryItem,owned_count:1,owned:true};presentation.Compact(nodes.LotteryInfoList,detail);
assert.strictEqual(badge(detail),sameLabel);assert.equal(tag.visible,true);
let textWrites=0,visibilityWrites=0,styleWrites=0,currentText=tag.text,currentVisible=tag.visible;
Object.defineProperty(tag,'text',{get(){return currentText;},set(v){textWrites++;currentText=v;},configurable:true});
Object.defineProperty(tag,'visible',{get(){return currentVisible;},set(v){visibilityWrites++;currentVisible=v;},configurable:true});
tag.style=new Proxy(tag.style,{set(target,key,value){styleWrites++;target[key]=value;return true;}});
const timersBefore=queue.length,trackedBefore=presentation.Inspect().trackedOwned;
for(let index=0;index<5;index++)presentation.Compact(nodes.LotteryInfoList,detail);
assert.equal(textWrites,0);assert.equal(visibilityWrites,0);assert.equal(styleWrites,0,'Stable ownership does not repeat native text/style writes');
assert.equal(queue.length,timersBefore,'Ownership adds no timer');assert.equal(presentation.Inspect().trackedOwned,trackedBefore,'Stable cards do not create more labels');

// The production grouped prize model also uses the same real snapshot items.
vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/lottery_gw2_data.js','utf8'),env);
current.Feature('details');const grouped=cardByItem(nodes.LotteryInfoList,'held');assert(grouped&&grouped.__lotteryPrizeFace);
const groupedTag=grouped.__lotteryPrizeFace.ownership;assert.equal(groupedTag.visible,true);assert.equal(groupedTag.text,'已拥有');
assert.equal(groupedTag.paneltype,'Label');assert(rect(groupedTag).y+rect(groupedTag).h<=72);
assert.equal(cardByItem(nodes.LotteryInfoList,'fresh').__lotteryPrizeFace.ownership.visible,false);
current.CloseInfo();

const grants=[
 {id:'new_result',name:'本次新奖励',quality:'sr',icon:'item_blink',owned_count:0,owned:false,duplicate:false,count:1},
 {id:'duplicate_result',name:'真实重复奖励',quality:'sr',icon:'item_blink',owned_count:1,owned:true,duplicate:true,count:1},
 {id:'stack_result',name:'可叠加库存',quality:'n',icon:'item_blink',owned_count:7,duplicate:false,count:1},
 {id:'old_result',name:'兼容旧重复回执',quality:'n',icon:'item_blink',duplicate:1,count:1},
 {id:'unknown_result',name:'数量不是库存',quality:'n',icon:'item_blink',count:100}
];
events.ui_lottery_result({ok:1,request_id:'ownership_fixture_many',pool_id:'map',count:grants.length,results:grants,snapshot:authoritative});
current.SkipReveal();const resultCards=nodes.LotteryItemList.Children();assert.equal(resultCards.length,grants.length);
for(const [index,card]of resultCards.entries()){
 const t=card.__lotteryGW2Cell.ownership;assert(t);assert.equal(t.visible,[false,true,true,true,false][index]);
 const box=rect(t),well=rect(card.__lotteryGW2Cell.well);assert(box.y+box.h<=well.y+well.h);
 if(t.visible)assert(rect(card.__lotteryGW2Cell.count).y+rect(card.__lotteryGW2Cell.count).h<=box.y,'The result award quantity stays above its independent ownership row');
}
assert.strictEqual(nodes.LotteryConfirm.events.onactivate,originalConfirm,'The existing confirm callback is retained');
assert.equal(nodes.LotteryConfirm.style.width,'220px');assert.equal(nodes.LotteryConfirm.style.height,'84px');
assert.equal(nodes.LotteryConfirm.style.backgroundColor,'#172b20','The entire clickable confirmation area has an opaque backing');
const confirmSkin=nodes.LotteryConfirm.Children().find(n=>n.BHasClass('LotteryGW2ButtonSurface'));
assert.equal(confirmSkin.style.width,'100%');assert.equal(confirmSkin.style.height,'100%');assert.equal(confirmSkin.style.position,'0px 0px 0px');
assert.equal(confirmSkin.style.backgroundColor,'#172b20');assert(confirmSkin.style.backgroundImage.includes('buyback_button'),'The existing native secondary artwork remains');
assert.equal(confirmSkin.hittest,false);assert.equal(confirmSkin.hittestchildren,false);
function resolvedFill(node,width,height){const box=rect(node);return{x:box.x,y:box.y,w:String(node.style.width).endsWith('%')?parseFloat(node.style.width)*width/100:box.w,h:String(node.style.height).endsWith('%')?parseFloat(node.style.height)*height/100:box.h};}
for(const [width,height]of [[220,84],[300,96]]){
 const painted=resolvedFill(confirmSkin,width,height);
 assert.deepEqual(painted,{x:0,y:0,w:width,h:height},'Opaque fill covers every edge of the real clickable rectangle, including a resized result control');
}
assert.equal(nodes.LotteryConfirm.style.padding,'0px');assert.equal(nodes.LotteryConfirm.style.border,'0px');
assert.equal(nodes.LotteryConfirm.style.minWidth,'0px');assert.equal(nodes.LotteryConfirm.style.minHeight,'0px');
const requestCount=requests.length;nodes.LotteryConfirm.events.onactivate();assert.equal(confirmCalls,1);
assert.equal(requests.length,requestCount,'Confirmation does not create a draw/grant request');assert(!nodes.LotteryWindow.BHasClass('LotteryResultsShown'));

events.ui_lottery_result({ok:1,request_id:'ownership_fixture_single',pool_id:'map',count:1,results:[grants[1]],snapshot:authoritative});current.SkipReveal();
const single=nodes.LotteryItemList.Children()[0],singleTag=single.__lotteryGW2Cell.ownership;
assert.equal(singleTag.text,'已拥有');assert.equal(singleTag.visible,true);assert.equal(singleTag.style.fontSize,'18px');
assert.strictEqual(nodes.LotteryConfirm.events.onactivate,originalConfirm);
assert(!requests.some(r=>r.n==='ui_lottery_draw_request'||r.n==='ui_lottery_exchange_request'),'Synthetic rendering tests never request a real draw or exchange');
current.Close();presentation.Dispose();
console.log('LOTTERY_GW2_OWNERSHIP_PASS: authoritative count/flag/duplicate, unowned and unknown rejection, four previews, compact/grouped details, single/many results, stable labels/zero timer work, full confirmation backing and unchanged callbacks');
`;
const loader=fs.readFileSync('tools/test_lottery_updates.cjs','utf8').split('suite+=')[0];
vm.runInNewContext(loader+'suite+='+JSON.stringify(setup)+';vm.runInNewContext(suite,{require:require("node:module").createRequire(require("path").resolve("tools/test_lottery_ui.js")),console});',{
 require:require('node:module').createRequire(path.resolve('tools/test_lottery_gw2_ownership.cjs')),console
});
