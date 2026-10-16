"use strict";
const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const requests=[],handlers={},timers=[],panels=[];let snapshot;
class Panel {
 constructor(type,parent){this.type=type;this.parent=parent;this.children=[];this.style={};this.events={};this.classes=new Set();this.enabled=true;panels.push(this);if(parent)parent.children.push(this);}
 AddClass(c){this.classes.add(c);}SetHasClass(c,v){v?this.classes.add(c):this.classes.delete(c);}
 RemoveClass(c){this.classes.delete(c);}Children(){return this.children;}
 SetPanelEvent(k,v){this.events[k]=v;}SetImage(){}SetScaling(){}IsValid(){return !this.deleted;}
 SetParent(p){if(this.parent)this.parent.children=this.parent.children.filter(c=>c!==this);this.parent=p;if(p)p.children.push(this);}
 DeleteAsync(){this.children.slice().forEach(p=>p.DeleteAsync());this.deleted=true;this.SetParent(null);}RemoveAndDeleteChildren(){this.children.slice().forEach(p=>p.DeleteAsync());}
}
const root=new Panel('Panel');function $(){};$.CreatePanel=(t,p)=>new Panel(t,p);$.GetContextPanel=()=>root;$.Schedule=(delay,fn)=>timers.push({delay,fn});
const cfg={SurvivalUI:{ModalShell:{Adopt:()=>({Open(){},Close(){},Dispose(){}})},ActionButton:(p,o)=>{const b=new Panel('Button',p);b.events.onactivate=o.action;return b;},
 ProductCard:(p,o)=>{const b=new Panel('Panel',p);b.prices=o.prices;return b;}},RemainingHandoff:{Action(){},Window(){},SizeWindow(){},Box(){},Tab(){},Image(){}},
 SurvivalCommerceView:{UpdateWalletCatalog:c=>snapshot=c,Dispose(){}}};
const env={$,Game:{},GameUI:{CustomUIConfig:()=>cfg},GameEvents:{Subscribe:(n,f)=>{(handlers[n]||(handlers[n]=[])).push(f);return {n,f};},Unsubscribe:token=>{handlers[token.n]=(handlers[token.n]||[]).filter(f=>f!==token.f);},SendCustomGameEventToServer:(name,body)=>requests.push({name,...body})}};
vm.createContext(env);
require('./load_shared_ui_test.cjs')(env,Panel,root);
for(const file of ['archive_v10_data.js','common/menu_v10.js'])vm.runInContext(fs.readFileSync('panorama/src/scripts/custom_game/'+file,'utf8'),env);
const script=fs.readFileSync('panorama/src/scripts/custom_game/commerce_wallet.js','utf8');
vm.runInContext(script,env);
const product={sku:'points_item',title:'积分道具',description:'开局木材+200',enabled:1,price:6800,currency:'shop_points',currency_name:'积分',purchase_method:'wallet',category_id:'technology',purchase_limit:1};
function respond(data){const r=requests.at(-1);for(const fn of handlers.survival_commerce_result||[])fn({action:r.action,request_id:r.request_id,...data});}
function catalog(){cfg.SurvivalCommerceWallet.Refresh();respond({ok:1,part:'begin',count:1,balances:{u_coin:10000,shop_points:10000,shop_gold:100},categories:[{id:'technology',label:'科技'}]});
 respond({ok:1,part:'product',index:1,product});respond({ok:1,part:'end'});}
catalog();assert.equal(snapshot.products.length,1);assert.equal(snapshot.products[0].price,6800);
assert(cfg.SurvivalCommerceWallet.Checkout(product.sku));
assert(panels.some(p=>p.classes.has('CommerceConfirmCopy')&&p.text.includes('售价：6800 积分')),
 'the actual exchange confirmation retains the server-owned price');
function buy(){return panels.filter(p=>p.classes.has('CommerceConfirmBuy') && !p.deleted).at(-1);}
buy().events.onactivate();buy().events.onactivate();assert.equal(requests.filter(r=>r.action==='purchase').length,1);
const first=requests.at(-1);assert(!('price' in first));assert(!('balance' in first));assert(!('provider' in first));
respond({ok:0,error:'commerce_busy',terminal:0});buy().events.onactivate();assert.equal(requests.at(-1).request_id,first.request_id);
respond({ok:0,error:'archive_pending',terminal:0});
// A Panorama hot reload must retain an uncertain purchase token.
vm.runInContext(script,env);catalog();cfg.SurvivalCommerceWallet.Checkout(product.sku);buy().events.onactivate();assert.equal(requests.at(-1).request_id,first.request_id);
respond({ok:1,terminal:1,sku:product.sku,currency:'shop_points',price:6800,balance:3200});assert.equal(cfg.SurvivalCommercePending,null);
assert.equal(cfg.SurvivalCommerceWallet.GetCatalog().balances.shop_points,3200);
// The real storefront keeps cash products and routes wallet products to the exchange controller.
let cashCheckout=null,walletCheckout=null;
cfg.SurvivalPayments={GetCatalog:()=>({products:[{sku:'cash_sku',title:'现金商品',amount_fen:5000,category_id:'technology',enabled:1}],categories:[{id:'technology',label:'科技'}]}),Checkout:sku=>cashCheckout=sku};
cfg.SurvivalCommerceWallet.Checkout=sku=>{walletCheckout=sku;return true;};
vm.runInContext(fs.readFileSync('panorama/src/scripts/custom_game/common/commerce_components.js','utf8'),env);
vm.runInContext(fs.readFileSync('panorama/src/scripts/custom_game/commerce_remaining_5d5c1152eb.js','utf8'),env);
const descendants=p=>[p,...p.Children().flatMap(descendants)];
const cards=()=>panels.filter(p=>p.classes.has('RCProduct')&&!p.deleted);
const purchase=card=>(descendants(card).find(p=>p.classes.has('BLMarketBuy'))||card).events.onactivate();
for(const card of cards()){
 const body=descendants(card.__purpleDetail).find(p=>p.classes.has('MenuV10CommerceDetailBody'));
 assert.deepEqual(body.Children().map(p=>[...p.classes][0]),['RCPurpleDetailTitle','RCPurpleDetailQuality','RCProductEffect']);
 assert(body.Children().every(p=>p.type==='Label'),'fallback tooltip contains only three information labels');
}
purchase(cards().at(-2));assert.equal(walletCheckout,product.sku);
cfg.SurvivalCommerceView.Open();
purchase(cards().at(-1));assert.equal(cashCheckout,'cash_sku');
console.log('COMMERCE_WALLET_UI_PASS: currency routing, chunk assembly, repeated clicks, uncertain retry and hot reload');
