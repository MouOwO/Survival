"use strict";
const fs=require("node:fs"),vm=require("node:vm"),assert=require("node:assert/strict");
const jobs=new Map(),checkouts=[];let jobId=0;
const clipCases=[];
const wheelDeliveries=[];
class Panel{
 constructor(type,parent,id){this.type=type;this.parent=parent;this.id=id;this.children=[];this.classes=new Set();this.style={};this.events={};this.visible=true;this.enabled=true;if(parent)parent.children.push(this);}
 AddClass(c){this.classes.add(c);}RemoveClass(c){this.classes.delete(c);}SetHasClass(c,v){v?this.AddClass(c):this.RemoveClass(c);}BHasClass(c){return this.classes.has(c);}
 SetPanelEvent(n,fn){this.events[n]=fn;}GetParent(){return this.parent;}GetChildCount(){return this.children.length;}GetChild(i){return this.children[i];}Children(){return this.children;}
 RemoveAndDeleteChildren(){function remove(p){p.deleted=true;p.children.forEach(remove);}this.children.forEach(remove);this.children=[];}
 IsValid(){return !this.deleted;}SetScaling(){}SetImage(v){this.image=v;}SetAcceptsFocus(){}SetFocus(){}DeleteAsync(){this.RemoveAndDeleteChildren();this.deleted=true;if(this.parent)this.parent.children=this.parent.children.filter(p=>p!==this);}
 assertValid(){assert(!this.deleted,"native method invoked on a deleted Panel");}
 get actuallayoutwidth(){this.assertValid();return this.measuredWidth!==undefined?this.measuredWidth:this.parent?parseFloat(this.style.width)||188:1920;}get actuallayoutheight(){this.assertValid();return this.measuredHeight!==undefined?this.measuredHeight:this.parent?parseFloat(this.style.height)||300:1080;}
 get actualuiscale_x(){this.assertValid();return this.scale||1;}get actualuiscale_y(){this.assertValid();return this.scale||1;}GetPositionWithinWindow(){return this.position||{x:100,y:100};}
 get enabled(){this.assertValid();return this._enabled;}set enabled(value){this.assertValid();this._enabled=value;}
}
// Native Panorama throws when methods are invoked after deleting a panel subtree.
for(const name of ["AddClass","RemoveClass","SetHasClass","BHasClass","SetPanelEvent","GetParent","GetChildCount","GetChild","Children","RemoveAndDeleteChildren","SetScaling","SetImage","SetAcceptsFocus","SetFocus","DeleteAsync","GetPositionWithinWindow"]){const original=Panel.prototype[name];Panel.prototype[name]=function(...args){this.assertValid();return original.apply(this,args);};}
const root=new Panel("Panel",null,"root"),cfg={RemainingHandoff:{}};
let purpleDisposals=0;
cfg.SurvivalPurpleShell={Adopt:()=>({Dispose:()=>{purpleDisposals++;}})};
function $(){return null;}$.GetContextPanel=()=>root;$.CreatePanel=(t,p,id)=>new Panel(t,p,id);$.Msg=()=>{};$.DispatchEvent=()=>{};$.RegisterEventHandler=()=>{};
$.Schedule=(d,fn)=>{jobs.set(++jobId,{d,fn});return jobId;};$.CancelScheduled=id=>jobs.delete(id);
function tick(d){for(const[id,t]of [...jobs])if(t.d===d){jobs.delete(id);t.fn();}}
// A native wheel can reach only a live hit-test target with eligible ancestors.
// This records input routing; it deliberately does not manufacture Label scrolling.
function mockWheel(from,delta){
 let target=from;while(target&&target.IsValid()&&target.hittest!==true)target=target.GetParent();
 if(!target||!target.IsValid()||target.visible===false)return null;
 for(let ancestor=target.GetParent();ancestor;ancestor=ancestor.GetParent())if(!ancestor.IsValid()||ancestor.visible===false||ancestor.hittestchildren===false)return null;
 wheelDeliveries.push({target:target.type,classes:[...target.classes],delta});return target;
}
const first={sku:"configured_1",title:"成长之剑",category_id:"weapon",product_type:"single",enabled:true,owned:3,purchase_method:"paid",amount_fen:1234,icon:"custom_game/archive_items_v2/lottery_attribute_crystal.png",reward_lines:[{label:"攻击力",quantity:100}]};
const second={...first,sku:"configured_2",title:"铁甲 · 永久",owned:0};
let catalog={categories:[{id:"weapon",label:"武器与装备"}],products:[first,second],catalog_hash:"initial"};
cfg.SurvivalPayments={GetCatalog:()=>catalog,RefreshCatalog:()=>{},Checkout:sku=>{checkouts.push(sku);return true;}};
const env={$,GameUI:{CustomUIConfig:()=>cfg},GameEvents:{Subscribe:()=>1,Unsubscribe:()=>{}},Game:{}};
require("../load_shared_ui_test.cjs")(env,Panel,root);
vm.runInNewContext(fs.readFileSync("panorama/src/scripts/custom_game/ui_layers.js","utf8"),env);
for(const file of ["common/commerce_components.js","commerce_remaining_5d5c1152eb.js"])vm.runInNewContext(fs.readFileSync("panorama/src/scripts/custom_game/"+file,"utf8"),env);
function all(){const a=[];function walk(p){a.push(p);p.children.forEach(walk);}walk(root);return a;}
const cards=()=>all().filter(p=>p.BHasClass("CommercePurpleProduct"));
cfg.SurvivalCommerceView.Open();
assert.equal(checkouts.length,0,"opening the authenticated catalog never checks out");
const [a,b]=cards(),tipA=a.__purpleDetail,tipB=b.__purpleDetail;
const layer=tipA.GetParent(),commerceWindow=layer.GetParent();assert(layer.BHasClass('CommercePurpleDetailLayer'));assert(commerceWindow.BHasClass('CommercePurple'));assert.equal(tipB.GetParent(),layer);assert.equal(tipA.__purpleSource,a);assert(!a.children.includes(tipA),'floating detail is outside the compact card paint subtree');assert.equal(layer.hittest,false);assert.equal(layer.hittestchildren,true,'overlay permits original purchase children without intercepting blank catalog space');layer.position={x:320,y:140};
function liveDetails(){return all().filter(p=>p.BHasClass('RCPurpleDetail'));}function assertOwnedDetails(){assert.equal(liveDetails().length,cards().length);assert(liveDetails().every(t=>t.GetParent().BHasClass('CommercePurpleDetailLayer')&&t.__purpleSource.IsValid()),'only current live cards own floating details');}
assertOwnedDetails();assert.equal(tipA.children.find(p=>p.BHasClass('RCProductEffect')).text,'攻击力 ×100');assert.equal(tipA.children.find(p=>p.BHasClass('CJPrice')).children[0].children.find(p=>p.BHasClass('CJPriceValue')).text,'12.34 元','real checkout price body is unchanged');
assert.equal(b.children.find(p=>p.BHasClass("RCProductName")).text,"铁甲","compact captions omit repeated permanence suffix");assert.equal(tipB.children.find(p=>p.BHasClass("RCPurpleDetailTitle")).text,second.title,"full authoritative title remains inside detail");
assert.equal(a.style.width,"188px");assert.equal(a.style.height,"172px");assert.equal(a.children.filter(p=>p.BHasClass("RCProductName")).length,1);
const nativeCaption=a.children.find(p=>p.BHasClass("RCProductName"));
assert.equal(nativeCaption.style.width,"fit-children");assert.equal(nativeCaption.style.maxWidth,"188px");assert.equal(nativeCaption.style.horizontalAlign,"center");
assert.equal(nativeCaption.style.verticalAlign,"top");assert.equal(nativeCaption.style.position,"0px 140px 0px");assert.equal(nativeCaption.style.textAlign,"center");
assert(a.children[0].children.some(p=>p.BHasClass("RCStockState")&&p.text==="3"),"owned quantity is the optional corner marker");
assert.equal(a.children.filter(p=>p.BHasClass("CJPrice")).length,0,"price stays inside detail");
a.position={x:1780,y:990};a.events.onmouseover();assert(tipA.BHasClass("Visible"));assert.equal(checkouts.length,0);
assert.equal(a.style.zIndex,"30","selected tooltip sits above later catalog cards");
let [left,top]=tipA.style.position.split(' ').map(parseFloat);assert(left+layer.position.x<a.position.x,'right-edge tooltip flips to the left');assert(left+layer.position.x>=12&&left+layer.position.x+312<=1920-12);assert(top+layer.position.y>=12&&top+layer.position.y+300<=1080-12,'layer position is bounded in real screen coordinates');
for(const scale of [.6666667,.8333333,1,1.25]){
 layer.scale=scale;a.measuredWidth=188*scale;tipA.measuredWidth=312*scale;tipA.measuredHeight=300*scale;
 for(const at of [{x:20,y:20},{x:1780,y:990},{x:900,y:990}]){a.position=at;a.events.onmouseover();tick(.03);const [x,y]=tipA.style.position.split(' ').map(parseFloat),screenX=layer.position.x+x*scale,screenY=layer.position.y+y*scale,pad=12*scale;assert(screenX>=pad-1&&screenX+tipA.measuredWidth<=1920-pad+1);assert(screenY>=pad-1&&screenY+tipA.measuredHeight<=1080-pad+1,'real scale conversion preserves lower/left/right screen bounds');}
 a.position={x:layer.position.x+100*scale,y:layer.position.y+180*scale};a.events.onmouseover();tick(.03);const [x,y]=tipA.style.position.split(' ').map(parseFloat);assert(Math.abs(x-(100+188+12))<=1&&Math.abs(y-180)<=1,'nonzero layer origin and native UI scale convert the same source anchor correctly');
}
layer.scale=1;delete a.measuredWidth;delete tipA.measuredWidth;delete tipA.measuredHeight;a.position={x:1780,y:990};a.events.onmouseover();
// Native clips window-owned floating details even when the full viewport has space.
// Exercise the actual fifth-column anchors, both rows, and measured long-body height.
for(const viewport of [{width:1280,height:720},{width:1600,height:900},{width:1920,height:1080},{width:2560,height:1440},{width:2560,height:1080}]){
 const scale=Math.min(viewport.width/1920,viewport.height/1080),origin={x:(viewport.width-1280*scale)/2,y:(viewport.height-800*scale)/2};
 root.measuredWidth=viewport.width;root.measuredHeight=viewport.height;layer.scale=scale;layer.position=origin;commerceWindow.position=origin;commerceWindow.measuredWidth=1280*scale;commerceWindow.measuredHeight=800*scale;a.measuredWidth=188*scale;tipA.measuredWidth=312*scale;
 for(const row of [0,2])for(const logicalHeight of [300,540]){
  tipA.measuredHeight=logicalHeight*scale;a.position={x:origin.x+1040*scale,y:origin.y+(174+row*184)*scale};a.events.onmouseover();tick(.03);
  const [x,y]=tipA.style.position.split(' ').map(parseFloat),bounds={left:origin.x+x*scale,top:origin.y+y*scale,right:origin.x+(x+312)*scale,bottom:origin.y+(y+logicalHeight)*scale},pad=12*scale;
  assert(bounds.right<=origin.x+commerceWindow.measuredWidth-pad+1,'native window right clip applies even when viewport has unused space');assert(bounds.left>=Math.max(pad,origin.x+pad)-1);assert(bounds.top>=Math.max(pad,origin.y+pad)-1);assert(bounds.bottom<=Math.min(viewport.height-pad,origin.y+commerceWindow.measuredHeight-pad)+1,'bottom-row long detail remains wholly inside native window clip');
  assert(bounds.right<a.position.x,'fifth-column detail flips to the left with the same hover gap');assert.equal(checkouts.length,0);clipCases.push({viewport,scale,row,logicalHeight,source:a.position,window:{...origin,width:commerceWindow.measuredWidth,height:commerceWindow.measuredHeight},tooltip:bounds,pass:true});
 }
}
// Screen safety still wins if a window is partially outside the viewport.
root.measuredWidth=1920;root.measuredHeight=1080;layer.scale=1;layer.position={x:-100,y:-50};commerceWindow.position=layer.position;commerceWindow.measuredWidth=1280;commerceWindow.measuredHeight=800;a.measuredWidth=188;tipA.measuredWidth=312;tipA.measuredHeight=540;a.position={x:0,y:0};a.events.onmouseover();tick(.03);let [safeX,safeY]=tipA.style.position.split(' ').map(parseFloat);assert(layer.position.x+safeX>=12);assert(layer.position.y+safeY>=12);assert(layer.position.x+safeX+312<=1180-12);assert(layer.position.y+safeY+540<=750-12);clipCases.push({partiallyOffscreen:true,pass:true});
delete root.measuredWidth;delete root.measuredHeight;layer.scale=1;layer.position={x:320,y:140};commerceWindow.position=layer.position;commerceWindow.measuredWidth=1280;commerceWindow.measuredHeight=800;delete a.measuredWidth;delete tipA.measuredWidth;delete tipA.measuredHeight;a.position={x:1780,y:990};a.events.onmouseover();
a.events.onmouseout();tipA.events.onmouseover();tick(.18);assert(tipA.BHasClass("Visible"),"entering purchase tooltip cancels gap timeout");
a.events.onactivate();a.events.onmouseout();tick(.18);assert(tipA.BHasClass("Visible"),"selected cell pins the detail without buying");
b.events.onmouseover();assert(!tipA.BHasClass("Visible"));assert(tipB.BHasClass("Visible"),"one detail owns hover");
assert.equal(a.style.zIndex,"0","old selected card releases its stacking priority");
tipB.events.onmouseout();tick(.18);assert(!tipB.BHasClass("Visible"));
b.events.onmouseover();tipB.children.find(p=>p.BHasClass("RCProductBuy")).events.onactivate();
assert.deepEqual(checkouts,[second.sku]);assert.equal(cfg.SurvivalCommerceView.IsOpen(),false);assert(!tipB.IsValid(),'checkout closes and destroys its floating detail');assert.equal(liveDetails().length,0,'closed windows retain no floating detail children');
cfg.SurvivalCommerceView.Open();assertOwnedDetails();assert.equal(cards()[0],a,'same-catalog reopen preserves the original source card');assert.equal(cards()[1],b);assert(cards().every(c=>c.__purpleDetail!==tipA&&c.__purpleDetail!==tipB),'same-catalog reopen rebuilds only disposed details');
const removedSource=cards()[0],removedTip=removedSource.__purpleDetail,stalePurchase=removedTip.children.find(p=>p.BHasClass('RCProductBuy')).events.onactivate;removedSource.events.onmouseover();removedSource.DeleteAsync();tick(.03);tick(.18);assert(!removedTip.IsValid(),'source-card deletion is cleaned by the pending placement callback');assert.doesNotThrow(stalePurchase,'a captured old purchase callback cannot read a deleted native button');assert.equal(checkouts.length,1);assert(liveDetails().every(t=>t.__purpleSource.IsValid()),'source deletion leaves no orphan tip');
cfg.SurvivalCommerceView.UpdateCatalog({...catalog,catalog_hash:"changed",products:[{...first,title:"服务端最新名称"}]});tick(.18);tick(.03);
assert.equal(cards().length,1);assert(all().some(p=>p.text==="服务端最新名称"));assert.equal(checkouts.length,1,"late hide callbacks and catalog refresh never order");
assertOwnedDetails();cfg.SurvivalCommerceView.Close();assert.equal(cfg.SurvivalUILayers.Top(),null);assert.equal(liveDetails().length,0);
const shortCatalog=catalog,longDescription=Array.from({length:50},(_,i)=>`第${i+1}行真实说明滚动压力样例`).join('\n'),longCatalog={...catalog,catalog_hash:'long-effect',products:[{...first,reward_lines:[{label:longDescription,quantity:100}]}]},longBefore=JSON.stringify(longCatalog);catalog=longCatalog;
cfg.SurvivalCommerceView.UpdateCatalog(longCatalog);cfg.SurvivalCommerceView.Open();const longCard=cards()[0],longTip=longCard.__purpleDetail;longCard.events.onmouseover();tick(.03);const longEffect=longTip.children.find(p=>p.BHasClass('RCProductEffect'));assert.equal(longEffect.text,longDescription+' ×100','long real-controller effect is complete, never truncated to fit the new clip');assert.equal(JSON.stringify(longCatalog),longBefore);const commerceCSS=fs.readFileSync('panorama/src/styles/custom_game/common/commerce_purple.css','utf8');assert(/\.CommercePurple \.RCProductEffect \{[^}]*max-height:180px[^}]*overflow:squish scroll/.test(commerceCSS),'long effects retain their original inner scrollbar');assert(/\.CommercePurple \.RCPurpleDetail \{[^}]*max-height:540px[^}]*overflow:squish scroll/.test(commerceCSS),'outer long bundle/details retain their original capped scrollbar');
assert.ok(mockWheel(longEffect,-120)===longEffect,'physical wheel targeting must honor the effect Label hittest, not call ScrollToBottom directly');assert.equal(longEffect.text,longDescription+' ×100');assert.equal(longTip.children.find(p=>p.BHasClass('CJPrice')).children[0].children.find(p=>p.BHasClass('CJPriceValue')).text,'12.34 元');assert(longTip.children.find(p=>p.BHasClass('RCProductBuy')));longTip.hittestchildren=false;assert.equal(mockWheel(longEffect,-120),null,'a hidden/disallowed tooltip cannot receive a wheel through its children');longTip.hittestchildren=true;assert.ok(mockWheel(longEffect,120)===longEffect);assert.equal(checkouts.length,1,'wheel routing never buys');cfg.SurvivalCommerceView.Close();assert.equal(mockWheel(longEffect,-120),null,'a deleted effect receives no late wheel');catalog=shortCatalog;cfg.SurvivalCommerceView.UpdateCatalog(catalog);
// Exercise every real technology SKU through the original merged-catalog presenter,
// both pages, and hover details. Only its known legacy placeholder is replaced.
const {csv}=require("../shop_ui_12h/catalog.cjs"),technology=csv("data/csv/商城兑换系统/commerce_products.csv").filter(p=>p.enabled==="1"&&p.category_id==="technology").sort((a,b)=>Number(a.sort_order)-Number(b.sort_order));
const realProducts=technology.map(p=>({sku:p.sku,title:p.display_name,description:p.description,category_id:p.category_id,product_type:p.product_type,icon:p.icon,
 enabled:true,owned:0,purchase_method:"wallet",currency:p.currency,currency_name:"U币",price:Number(p.price),reward_lines:[]}));
assert.equal(realProducts.length,25,"actual enabled CSV technology products form the native catalog");
const originalCatalog=JSON.stringify(realProducts),beforeIconCheckout=checkouts.length,J=cfg.SurvivalCommerceComponents;
cfg.SurvivalCommerceView.UpdateWalletCatalog({products:realProducts,categories:[{id:"technology",label:"科技与服务"}],balances:{u_coin:0}});
cfg.SurvivalCommerceView.Open();all().find(p=>p.BHasClass("CommercePurpleNav")&&p.children.some(c=>c.text==="科技与服务")).events.onactivate();
const shown=new Map();function checkMappedPage(){for(const card of cards()){
 const title=card.__purpleDetail.children.find(p=>p.BHasClass("RCPurpleDetailTitle")).text,item=realProducts.find(p=>p.title===title);assert(item);
 const icon=card.children[0].children.find(p=>p.BHasClass("RCProductArt")),detailIcon=card.__purpleDetail.children.find(p=>p.BHasClass("RCPurpleDetailIcon"));
 assert(icon.image.startsWith("file://{images}/items/")||icon.image.startsWith("file://{images}/spellicons/"));assert.equal(detailIcon.image,icon.image,"compact and detail share the canonical art");
 assert(!icon.image.includes("lottery_attribute_crystal"),"real SKU must not retain the shared attribute crystal");
 const caption=card.children.find(p=>p.BHasClass("RCProductName"));assert.equal(caption.style.width,"fit-children");assert.equal(caption.style.horizontalAlign,"center");assert.equal(caption.style.maxWidth,"188px");
 card.events.onmouseover();assert(card.__purpleDetail.BHasClass("Visible"));assert.equal(checkouts.length,beforeIconCheckout,"new art and hover never check out");shown.set(item.sku,icon.image);
}}
assert.equal(cards().length,15);assertOwnedDetails();checkMappedPage();const previousPageDetails=liveDetails();all().find(p=>p.BHasClass("CJPageAction")&&p.children.some(c=>c.text==="下一页")).events.onactivate();assert.equal(cards().length,10);assert(previousPageDetails.every(t=>!t.IsValid()),'paging destroys every old window-layer detail');assertOwnedDetails();checkMappedPage();
assert.equal(shown.size,25);assert(new Set(shown.values()).size>15,"actual technology rights have distinct existing native art");assert.equal(JSON.stringify(realProducts),originalCatalog,"presentation leaves authoritative SKU/title/icon/price/reward fields unchanged");
const mapped=realProducts[0],dedicated={...mapped,icon:"custom_game/archive_items_v2/lottery_lumber_crystal.png"};
assert.equal(J.ProductIcon(dedicated),dedicated.icon,"a future dedicated server icon takes precedence over the local placeholder mapping");
assert.equal(J.ProductIcon({...mapped,sku:"unconfigured_future_right"}),mapped.icon,"unknown SKU retains its authoritative icon");
assert.equal(J.ProductIcon({...mapped,sku:"constructor"}),mapped.icon,"inherited object keys are not canonical commerce SKUs");
assert.equal(J.ProductIcon({...mapped,icon:""}),J.ProductIcon(mapped),"known canonical SKU can supply missing art without altering product data");
const technologyDetails=liveDetails();all().find(p=>p.BHasClass('CommercePurpleNav')&&p.children.some(c=>c.text==='武器与装备')).events.onactivate();assert(technologyDetails.every(t=>!t.IsValid()),'changing category destroys old floating bodies');assertOwnedDetails();cfg.SurvivalCommerceView.Close();assert.equal(liveDetails().length,0);cfg.SurvivalCommerceView.UpdateWalletCatalog({products:[],categories:[],balances:{}});
cfg.SurvivalCommerceView.Open();cards()[0].events.onmouseover();cards()[0].events.onmouseout();
const oldView=cfg.SurvivalCommerceView,oldTip=cards()[0].__purpleDetail;
root.RemoveAndDeleteChildren();assert(!oldTip.IsValid(),"hot reload deletes the entire old native subtree");
assert.throws(()=>oldTip.BHasClass("Visible"),/deleted Panel/,"the harness enforces native deleted-panel access");
assert.doesNotThrow(()=>{oldView.Close();oldView.Open();oldView.SetNotice("late notice");oldView.UpdateCatalog(catalog);oldView.Inspect();},"late old-context actions never read deleted native panels");
for(const file of ["common/commerce_components.js","commerce_remaining_5d5c1152eb.js"])vm.runInNewContext(fs.readFileSync("panorama/src/scripts/custom_game/"+file,"utf8"),env);
assert.notEqual(cfg.SurvivalCommerceView,oldView);assert.equal(purpleDisposals,1,"reload disposes the previous shared chrome registration");
assert.doesNotThrow(()=>{tick(.03);tick(.18);},"pending old tooltip timers tolerate native deletion");
cfg.SurvivalCommerceView.Open();assert.equal(cards().length,2,"the fresh controller initializes its authenticated catalog after deleted-panel reload");
assert.equal(cfg.SurvivalCommerceView.Inspect().valid,true);assert.equal(checkouts.length,1,"reload never checks out");
assertOwnedDetails();cfg.SurvivalCommerceView.Dispose();cfg.SurvivalCommerceView.Dispose();assert.equal(purpleDisposals,2);assert.equal(cfg.SurvivalUILayers.Top(),null);assert.equal(cards().length,0);assert.equal(liveDetails().length,0,'disposing a native window clears all independently parented details');
cfg.SurvivalCommerceView={Dispose(){throw new Error("Underlying panel is deleted");}};
assert.doesNotThrow(()=>vm.runInNewContext(fs.readFileSync("panorama/src/scripts/custom_game/commerce_remaining_5d5c1152eb.js","utf8"),env),"upgrading an older controller recovers the exact deleted-native-panel cleanup error");
cfg.SurvivalCommerceView.Open();assert.equal(cards().length,2);assert.equal(checkouts.length,1);cfg.SurvivalCommerceView.Dispose();
const unexpected=new Error("unexpected cleanup failure");cfg.SurvivalCommerceView={Dispose(){throw unexpected;}};
assert.throws(()=>vm.runInNewContext(fs.readFileSync("panorama/src/scripts/custom_game/commerce_remaining_5d5c1152eb.js","utf8"),env),error=>error===unexpected,"unrelated cleanup failures remain visible");
fs.mkdirSync('design_refs/purple_ui_10h/work/qa',{recursive:true});fs.writeFileSync('design_refs/purple_ui_10h/work/qa/commerce_a17_clip_report.json',JSON.stringify({kind:'strict_native_mock',actual_game:false,at:new Date().toISOString(),cases:clipCases,longEffect:{lines:50,complete:true,innerScrollPreserved:true,outerScrollPreserved:true},lifecycle:'PASS',actual_transactions:0},null,2));
fs.writeFileSync('design_refs/purple_ui_10h/work/qa/commerce_a18_wheel_report.json',JSON.stringify({kind:'strict_native_mock_input_routing',actual_game:false,at:new Date().toISOString(),wheelDeliveries,effectEligible:true,ancestorChildrenGuard:true,deletedTargetGuard:true,completeEffectLines:50,priceAndPurchaseBodyUnchanged:true,directScrollToBottomUsed:false,nativeLabelScroll:'pending real wheel validation; routing mock does not prove native Label scrollability',allOriginalCommerceRegression:'PASS',actual_transactions:0},null,2));
console.log("COMMERCE_PURPLE_PASS: owned window-layer details, real layer-origin/UI-scale viewport and window-clip intersection across fifth-column top/bottom/long-body cases, complete 50-line effects and original scrollbars, hover gap/pin/purchase bodies, source deletion/category/page/close/reopen/deleted-reload disposal without orphans, compact native-centered captions, all 25 real technology SKUs on original 15/10 pages with canonical native art and immutable catalog data, original purchase routing/hover guards, no visual/reload checkout");
