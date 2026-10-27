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
const count=()=>requests.filter(r=>r.action==='purchase').length;
const node=cls=>panels.filter(p=>p.classes.has(cls)&&!p.deleted).at(-1);
const retry=()=>node('CommerceResultPrimary');
assert(cfg.SurvivalCommerceWallet.Checkout(product.sku));
assert.equal(count(),1,'The existing marketplace exchange button submits directly');
assert(node('CommerceResultCopy').text.includes('售价：6800 商城积分'));
assert(!node('MenuV10Exchange')&&!node('CommerceConfirmBuy'),'No legacy page or second purchase confirmation is created');
const first=requests.at(-1);assert(!('price' in first));assert(!('balance' in first));assert(!('provider' in first));
assert(cfg.SurvivalCommerceWallet.Checkout(product.sku));assert.equal(count(),1,'Repeated clicks only restore pending feedback');
respond({ok:0,error:'commerce_busy',terminal:0});assert.equal(cfg.SurvivalCommerceWallet.Inspect().result,'unknown');
assert(retry().visible&&retry().enabled);
catalog(10000,{...product,price:7000});assert(node('CommerceResultCopy').text.includes('售价：6800 商城积分'),'An unsettled operation retains its original quote across catalog changes');
retry().events.onactivate();assert.equal(requests.at(-1).request_id,first.request_id);
respond({ok:0,error:'archive_pending',terminal:0});
// An uncertain operation survives a HUD reload and a newly low balance.
vm.runInContext(script,env);catalog(0);assert(cfg.SurvivalCommerceWallet.Checkout(product.sku));
assert.equal(requests.at(-1).request_id,first.request_id,'Recovery keeps the durable operation identity');
respond({ok:1,terminal:1,sku:product.sku,currency:'shop_points',price:6800,balance:3200});
assert.equal(cfg.SurvivalCommercePending,null);assert.equal(snapshot.balances.shop_points,3200);
assert.equal(cfg.SurvivalCommerceWallet.Inspect().result,'success');assert(!retry().visible);
const beforeStale=count();retry().events.onactivate();assert.equal(count(),beforeStale,'A retired retry cannot create a second debit');
for(const disabled_reason of ['commerce_balance_insufficient','insufficient_balance']){
 catalog(0,{...product,enabled:0,disabled_reason});const before=count();
 assert.equal(cfg.SurvivalCommerceWallet.Checkout(product.sku),false);
 assert.equal(cfg.SurvivalCommerceWallet.Inspect().result,'failure');assert(node('CommerceResultStatus').text.includes('积分不足'));
 assert.equal(count(),before);assert.equal(cfg.SurvivalCommercePending,null);
}
catalog(0);const knownLow=count();assert.equal(cfg.SurvivalCommerceWallet.Checkout(product.sku),false);
assert.equal(count(),knownLow,'A stale enabled flag cannot override a known insufficient balance');
for(const unknown of [undefined,null,'0',NaN]){
 catalog(unknown);const before=count();assert(cfg.SurvivalCommerceWallet.Checkout(product.sku));
 assert.equal(count(),before+1,'Unknown balances are submitted to the authoritative server, never guessed as zero');
 assert(node('CommerceResultCopy').text.includes('商城余额：—'));
 respond({ok:0,terminal:1,error:'commerce_balance_insufficient'});
 assert.equal(cfg.SurvivalCommerceWallet.Inspect().result,'failure');assert.equal(cfg.SurvivalCommercePending,null);
}
assert.equal(clientEvents.length,0,'Exchange feedback uses only our result panel');
catalog(6800);assert(cfg.SurvivalCommerceWallet.Checkout(product.sku));
const outstanding=requests.at(-1);respond({ok:1,action:'catalog',request_id:outstanding.request_id,part:'end'});
assert.equal(cfg.SurvivalCommerceWallet.Inspect().inflight,'purchase','An incorrect action cannot unlock the current operation');
cfg.SurvivalCommerceWallet.CloseResult();assert.equal(cfg.SurvivalCommerceWallet.Inspect().opened,false);
respond({ok:1,terminal:1,sku:product.sku,currency:'shop_points',price:6800,balance:0});
assert.equal(cfg.SurvivalCommerceWallet.Inspect().result,'success');assert.equal(cfg.SurvivalCommerceWallet.Inspect().opened,false,'A late result updates data without stealing focus');
assert.equal(snapshot.balances.shop_points,0);assert.equal(cfg.SurvivalCommercePending,null);
assert(requests.every(row=>row.name==='survival_commerce_request'),'No wallet operation requests cash or HTTP checkout');
cfg.SurvivalCommerceWallet.Dispose();assert(!node('CommerceResult'));
console.log('COMMERCE_WALLET_UI_PASS: direct purchase, owned result panel, same-ID recovery, no duplicate debit, unknown balances, closed/late result, action correlation and no cash requests');
