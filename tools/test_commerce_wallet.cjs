"use strict";
const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const requests=[],clientEvents=[],handlers={},timers=[],panels=[];let snapshot;
class Panel {
 constructor(type,parent){this.type=type;this.parent=parent;this.children=[];this.style={};this.events={};this.classes=new Set();this.enabled=true;panels.push(this);if(parent)parent.children.push(this);}
 AddClass(c){this.classes.add(c);}SetHasClass(c,v){v?this.classes.add(c):this.classes.delete(c);}
 RemoveClass(c){this.classes.delete(c);}Children(){return this.children;}
 GetPositionWithinWindow(){const origin=this.parent?this.parent.GetPositionWithinWindow():{x:0,y:0},parts=String(this.style.position||'0px 0px').split(/\s+/);return {x:origin.x+(parseFloat(parts[0])||0),y:origin.y+(parseFloat(parts[1])||0)};}
 SetPanelEvent(k,v){this.events[k]=v;}SetImage(){}SetScaling(){}IsValid(){return !this.deleted;}
 SetParent(p){if(this.parent)this.parent.children=this.parent.children.filter(c=>c!==this);this.parent=p;if(p)p.children.push(this);}
 DeleteAsync(){this.children.slice().forEach(p=>p.DeleteAsync());this.deleted=true;this.SetParent(null);}RemoveAndDeleteChildren(){this.children.slice().forEach(p=>p.DeleteAsync());}
}
const root=new Panel('Panel');function $(){};$.CreatePanel=(t,p)=>new Panel(t,p);$.GetContextPanel=()=>root;$.Schedule=(delay,fn)=>timers.push({delay,fn});
const cfg={SurvivalUI:{ModalShell:{Adopt:()=>({Open(){},Close(){},Dispose(){}})},ActionButton:(p,o)=>{const b=new Panel('Button',p);b.events.onactivate=o.action;return b;},
 ProductCard:(p,o)=>{const b=new Panel('Panel',p);b.prices=o.prices;return b;}},RemainingHandoff:{Action(){},Window(){},SizeWindow(){},Box(){},Tab(){},Image(){}},
 SurvivalCommerceView:{UpdateWalletCatalog:c=>snapshot=c,Dispose(){}}};
const env={$,Game:{},GameUI:{CustomUIConfig:()=>cfg},GameEvents:{Subscribe:(n,f)=>{(handlers[n]||(handlers[n]=[])).push(f);return {n,f};},Unsubscribe:token=>{handlers[token.n]=(handlers[token.n]||[]).filter(f=>f!==token.f);},SendCustomGameEventToServer:(name,body)=>requests.push({name,...body}),SendEventClientSide:(name,payload)=>clientEvents.push({name,payload})}};
vm.createContext(env);
require('./load_shared_ui_test.cjs')(env,Panel,root);
for(const file of ['common/item_resources.js','common/vip_badges.js','reward_presentation.js','archive_v10_data.js','common/menu_v10.js'])vm.runInContext(fs.readFileSync('panorama/src/scripts/custom_game/'+file,'utf8'),env);
const script=fs.readFileSync('panorama/src/scripts/custom_game/commerce_wallet.js','utf8');
vm.runInContext(script,env);
const product={sku:'points_item',title:'积分道具',description:'开局木材+200',enabled:1,price:6800,currency:'shop_points',currency_name:'积分',purchase_method:'wallet',category_id:'technology',purchase_limit:1};
function respond(data){const r=requests.at(-1);for(const fn of handlers.survival_commerce_result||[])fn({action:r.action,request_id:r.request_id,...data});}
function catalog(balance,item){if(!arguments.length)balance=10000;item=item||product;const balances={u_coin:10000,shop_gold:100};if(balance!==undefined)balances.shop_points=balance;
 cfg.SurvivalCommerceWallet.Refresh();respond({ok:1,part:'begin',count:1,balances,categories:[{id:'technology',label:'科技'}]});
 respond({ok:1,part:'product',index:1,product:item});respond({ok:1,part:'end'});}
catalog();assert.equal(snapshot.products.length,1);assert.equal(snapshot.products[0].price,6800);
assert(cfg.SurvivalCommerceWallet.Checkout(product.sku));
assert(panels.some(p=>p.classes.has('CommerceConfirmCopy')&&p.text.includes('售价：6800 商城积分')),
 'the actual exchange confirmation retains the server-owned price');
function buy(){return panels.filter(p=>p.classes.has('CommerceConfirmBuy') && !p.deleted).at(-1);}
buy().events.onactivate();buy().events.onactivate();assert.equal(requests.filter(r=>r.action==='purchase').length,1);
const first=requests.at(-1);assert(!('price' in first));assert(!('balance' in first));assert(!('provider' in first));
respond({ok:0,error:'commerce_busy',terminal:0});buy().events.onactivate();assert.equal(requests.at(-1).request_id,first.request_id);
respond({ok:0,error:'archive_pending',terminal:0});
// A Panorama hot reload must retain an uncertain purchase token.
vm.runInContext(script,env);catalog(0);cfg.SurvivalCommerceWallet.Checkout(product.sku);buy().events.onactivate();assert.equal(requests.at(-1).request_id,first.request_id,'Low balance cannot prevent querying the original uncertain purchase');
respond({ok:1,terminal:1,sku:product.sku,currency:'shop_points',price:6800,balance:3200});assert.equal(cfg.SurvivalCommercePending,null);
assert.equal(cfg.SurvivalCommerceWallet.GetCatalog().balances.shop_points,3200);
const nativeMessages=[];
cfg.SurvivalTooltipPosition={ShowNativeError(source,message){assert.equal(source,root);nativeMessages.push(message);env.GameEvents.SendEventClientSide('dota_hud_error_message',{reason:80,message});}};
function purchaseCount(){return requests.filter(r=>r.action==='purchase').length;}
function assertNativePoints(before){assert.equal(clientEvents.length,before+1);assert.deepEqual(JSON.parse(JSON.stringify(clientEvents.at(-1))),{name:'dota_hud_error_message',payload:{reason:80,message:'您的积分不足'}});}
for(const disabled_reason of ['commerce_balance_insufficient','insufficient_balance']){
 catalog(0,{...product,enabled:0,disabled_reason});const before=clientEvents.length,panelsBefore=panels.length,requestsBefore=purchaseCount();
 assert.equal(cfg.SurvivalCommerceWallet.Checkout(product.sku),false);assertNativePoints(before);
 assert.equal(panels.length,panelsBefore,'Rejected checkout does not prepare or open another confirmation');assert.equal(purchaseCount(),requestsBefore);assert.equal(cfg.SurvivalCommercePending,null);
}
catalog(0);let errorsBefore=clientEvents.length,requestsBefore=purchaseCount();
assert.equal(cfg.SurvivalCommerceWallet.Checkout(product.sku),false,'A stale enabled flag cannot override the known insufficient balance');assertNativePoints(errorsBefore);assert.equal(purchaseCount(),requestsBefore);
for(const unknown of [undefined,null,'0',NaN]){
 catalog(unknown);errorsBefore=clientEvents.length;
 assert(cfg.SurvivalCommerceWallet.Checkout(product.sku),'An unknown or malformed balance is not interpreted as zero');assert.equal(clientEvents.length,errorsBefore);
}
catalog(6800);assert(cfg.SurvivalCommerceWallet.Checkout(product.sku),'Balance equal to price is sufficient');
catalog(0,{...product,enabled:0,disabled_reason:'commerce_balance_insufficient'});errorsBefore=clientEvents.length;requestsBefore=purchaseCount();
assert.equal(buy().enabled,true,'A confirmation left open while the balance falls can report the native error on click');
buy().events.onactivate();assertNativePoints(errorsBefore);assert.equal(purchaseCount(),requestsBefore);assert.equal(cfg.SurvivalCommercePending,null);
assert(!panels.filter(p=>p.classes.has('CommerceConfirmStatus')&&!p.deleted).at(-1).text.includes('不足'),'The confirmation has no persistent insufficient-balance message');
catalog();assert(cfg.SurvivalCommerceWallet.Checkout(product.sku));buy().events.onactivate();errorsBefore=clientEvents.length;
respond({ok:0,terminal:1,error:'commerce_balance_insufficient'});assertNativePoints(errorsBefore);assert.equal(cfg.SurvivalCommercePending,null);
assert.equal(nativeMessages.length,5,'Both entry guards, the late balance guard and terminal refusal use the native layer helper');
assert(!panels.filter(p=>p.classes.has('CommerceConfirmStatus')&&!p.deleted).at(-1).text.includes('不足'),'A terminal server refusal also uses only the native notice');
catalog(6800);assert(cfg.SurvivalCommerceWallet.Checkout(product.sku),'A refreshed sufficient balance restores checkout');buy().events.onactivate();
respond({ok:1,terminal:1,sku:product.sku,currency:'shop_points',price:6800,balance:0});
// The real storefront keeps cash products and routes wallet products to the exchange controller.
let cashCheckout=null,walletCheckout=null;
// This routing fixture explicitly opts into the developer cash catalog. The
// distributed disabled-cash branch is covered by test_daily_wallet_refresh.
cfg.SurvivalDevelopmentPayments=true;
cfg.SurvivalPayments={IsRealMoneyEnabled:()=>true,GetCatalog:()=>({products:[{sku:'cash_sku',title:'现金商品',amount_fen:5000,
 currency:'u_coin',u_coin_price:5000,u_coin_per_yuan:100,category_id:'technology',enabled:1}],
 categories:[{id:'technology',label:'科技'}]}),Checkout:sku=>cashCheckout=sku};
cfg.SurvivalCommerceWallet.Checkout=sku=>{walletCheckout=sku;return true;};
vm.runInContext(fs.readFileSync('panorama/src/scripts/custom_game/common/commerce_components.js','utf8'),env);
vm.runInContext(fs.readFileSync('panorama/src/scripts/custom_game/commerce_remaining_5d5c1152eb.js','utf8'),env);
const descendants=p=>[p,...p.Children().flatMap(descendants)];
const cards=()=>panels.filter(p=>p.classes.has('RCProduct')&&!p.deleted);
const purchase=card=>(descendants(card).find(p=>p.classes.has('BLMarketBuy'))||card).events.onactivate();
for(const card of cards()){
 const body=descendants(card.__purpleDetail).find(p=>p.classes.has('MenuV10CommerceDetailBody'));
 assert.deepEqual(body.Children().map(p=>[...p.classes][0]),['MenuV10CommerceDetailContent']);
 const content=body.Children()[0];
 assert.deepEqual(content.Children().map(p=>[...p.classes][0]),['RCPurpleDetailTitle','RCPurpleDetailQuality','RCProductEffect']);
 assert(content.Children().every(p=>p.type==='Label'),'fallback tooltip content contains only three information labels');
}
purchase(cards().at(-2));assert.equal(walletCheckout,product.sku);
cfg.SurvivalCommerceView.Open();
purchase(cards().at(-1));assert.equal(cashCheckout,'cash_sku');
console.log('COMMERCE_WALLET_UI_PASS: currency routing, native points notices, current balance guards, unknown balances, recovery, repeated clicks and uncertain retry across hot reload');
