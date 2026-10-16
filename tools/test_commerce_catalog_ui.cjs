"use strict";
const fs=require("fs"),vm=require("vm"),assert=require("node:assert/strict");
class Panel {
 constructor(type,parent,id){this.type=type;this.parent=parent;this.id=id;this.children=[];this.classes=new Set();this.style={};this.events={};if(parent)parent.children.push(this);}
 AddClass(c){this.classes.add(c);}RemoveClass(c){this.classes.delete(c);}SetHasClass(c,on){on?this.AddClass(c):this.RemoveClass(c);}
 SetPanelEvent(n,fn){this.events[n]=fn;}RemoveAndDeleteChildren(){this.children=[];}Children(){return this.children;}
 SetParent(p){if(this.parent)this.parent.children=this.parent.children.filter(c=>c!==this);this.parent=p;if(p)p.children.push(this);}
 SetScaling(){}IsValid(){return !this.deleted;}DeleteAsync(){this.children.slice().forEach(p=>p.DeleteAsync());this.deleted=true;this.SetParent(null);}FindChildTraverse(){return null;}
}
const root=new Panel("Panel",null,"root");root.actuallayoutwidth=1920;root.actuallayoutheight=1080;
function $(){return null;}$.CreatePanel=(t,p,id)=>new Panel(t,p,id);$.Schedule=()=>1;$.CancelScheduled=()=>{};$.Msg=()=>{};
const requests=[],cfg={};let refreshes=0;
const product={sku:"configured_bundle",title:"组合礼包",category_id:"bundles",product_type:"bundle",amount_fen:777,enabled:true,owned:0,icon:"custom_game/archive_items_v2/lottery_attribute_crystal.png",
 reward_lines:[{id:"initial_wood",label:"木材",quantity:100},{id:"vip",label:"VIP",quantity:1},{id:"special_lottery_ticket",label:"金色抽奖券",quantity:10}]};
const catalog={catalog_hash:"a",categories:[{id:"technology",label:"科技"},{id:"bundles",label:"礼包"}],products:[product]};
let currentCatalog=catalog;
cfg.SurvivalPayments={GetCatalog:()=>currentCatalog,RefreshCatalog:()=>refreshes++,Checkout:sku=>requests.push(sku)};
const env={$,GameUI:{CustomUIConfig:()=>cfg},GameEvents:{Subscribe:()=>1,Unsubscribe:()=>{}},Game:{}};
require("./load_shared_ui_test.cjs")(env,Panel,root);
cfg.RemainingHandoff={Window:()=>{},SizeWindow:()=>{},Box:()=>{},Tab:()=>{},Action:()=>{},Image:()=>{}};
for(const file of ["archive_v10_data.js","common/menu_v10.js"])vm.runInNewContext(fs.readFileSync("panorama/src/scripts/custom_game/"+file,"utf8"),env);
vm.runInNewContext(fs.readFileSync("panorama/src/scripts/custom_game/common/commerce_components.js","utf8"),env);
vm.runInNewContext(fs.readFileSync("panorama/src/scripts/custom_game/commerce_remaining_5d5c1152eb.js","utf8"),env);
const all=()=>{const out=[];function walk(p){out.push(p);p.children.forEach(walk);}walk(root);return out;};
const descendants=p=>[p,...p.Children().flatMap(descendants)];
const purchase=card=>(descendants(card).find(p=>p.BHasClass('BLMarketBuy'))||card).events.onactivate();
cfg.SurvivalCommerceView.Open();assert.equal(refreshes,1);assert.equal(requests.length,0,"opening the shop must never create an order");
assert.equal(cfg.SurvivalCommerceView.Inspect().category,"bundles");
const stableCard=all().find(p=>p.BHasClass("RCProduct"));
const detailBody=descendants(stableCard.__purpleDetail).find(p=>p.BHasClass('MenuV10CommerceDetailBody'));
assert.deepEqual(detailBody.Children().map(p=>[...p.classes][0]),['RCPurpleDetailTitle','RCPurpleDetailQuality','RCProductEffect']);
assert(detailBody.Children().every(p=>p.type==='Label'),'tooltip has only name, quality and effect labels');
assert.equal(detailBody.Children()[1].text,'品级：未配置');
assert.equal(detailBody.Children()[2].text,'木材 ×100\nVIP ×1\n金色抽奖券 ×10','every configured bundle reward remains in the effect text');
cfg.SurvivalCommerceView.Close();cfg.SurvivalCommerceView.Open();
assert.equal(all().find(p=>p.BHasClass("RCProduct")),stableCard,"unchanged catalog must survive close/reopen without rebuilding cards");
cfg.SurvivalCommerceView.SetNotice("正在重试同步");
assert.equal(all().find(p=>p.BHasClass("RCProduct")),stableCard,"network notices must not destroy products");
cfg.SurvivalCommerceView.UpdateCatalog({...catalog,products:[{...product,stat_preview:[{value:42}]}]});
assert.equal(all().find(p=>p.BHasClass("RCProduct")),stableCard,"numeric preview refresh must preserve hovered cards");
purchase(stableCard);assert.deepEqual(requests,[product.sku]);
assert.equal(cfg.SurvivalCommerceView.Inspect().opened,false);
cfg.SurvivalCommerceView.UpdateCatalog({...catalog,products:[{...product,enabled:false,owned:1}]});
assert.equal(all().find(p=>p.BHasClass('RCProduct')).__menuCell.countPanel.text,'1','the product card retains its owned count');
cfg.SurvivalCommerceView.UpdateCatalog({...catalog,catalog_hash:"b",products:[{...product,title:"服务端新礼包",enabled:false,owned:1,amount_fen:900}]});
assert(all().some(p=>p.text==="服务端新礼包"));
all().find(p=>/Section_technology$/.test(p.id)).events.onactivate();assert(all().some(p=>p.text==="本分类暂无上架商品"));
assert.equal(cfg.SurvivalCommerceView.OpenTicketPurchase({id:"map"}),false,"normal gameplay tickets are not sold");
const ticket={...product,sku:"special_lottery_ticket_single",title:"金色抽奖券 ×1",category_id:"item",product_type:"single",amount_fen:5000,
 reward_lines:[{kind:"item",id:"special_lottery_ticket",label:"金色抽奖券",quantity:1}]};
const ticketCatalog={...catalog,catalog_hash:"tickets",products:[product,ticket],categories:[...catalog.categories,{id:"item",label:"道具与材料"}]};
currentCatalog=ticketCatalog;
for(const id of ["cultivation","dragon_knight","summer"]){
 assert(cfg.SurvivalCommerceView.OpenTicketPurchase({id}));
 assert.equal(requests.at(-1),ticket.sku,"open one ticket, never the earlier bundle containing tickets");
}
currentCatalog={products:[],categories:[]};cfg.SurvivalCommerceView.UpdateCatalog(currentCatalog);
const beforeCold=requests.length, beforeRefresh=refreshes;
assert(cfg.SurvivalCommerceView.OpenTicketPurchase("summer"));
assert.equal(requests.length,beforeCold);assert.equal(refreshes,beforeRefresh+1);
assert(all().some(p=>p.text==="正在加载金色抽奖券商品…"));
currentCatalog=ticketCatalog;cfg.SurvivalCommerceView.UpdateCatalog(currentCatalog);
assert.equal(requests.at(-1),ticket.sku);assert.equal(cfg.SurvivalCommerceView.Inspect().opened,false);
currentCatalog=catalog;const beforeMissing=requests.length;
assert(cfg.SurvivalCommerceView.OpenTicketPurchase("summer"));
cfg.SurvivalCommerceView.UpdateCatalog(currentCatalog);
assert.equal(requests.length,beforeMissing,"missing ticket never substitutes a bundle");
assert(all().some(p=>p.text==="金色抽奖券暂未上架，请稍后重试。"));
currentCatalog={products:[],categories:[]};cfg.SurvivalCommerceView.UpdateCatalog(currentCatalog);
cfg.SurvivalCommerceView.OpenTicketPurchase("summer");cfg.SurvivalCommerceView.Close();
currentCatalog=ticketCatalog;cfg.SurvivalCommerceView.UpdateCatalog(currentCatalog);
assert.equal(requests.length,beforeMissing,"late catalog must not reopen a cancelled purchase");
console.log("COMMERCE_TICKET_PASS: single ticket, all special pools, cold load, missing product, cancellation, no automatic order");
cfg.SurvivalCommerceView.Dispose();assert(root.children.filter(p=>p.BHasClass("RCWindow")).every(p=>p.deleted));
console.log("COMMERCE_CATALOG_UI_PASS: original cards and categories, bundle contents, server prices, checkout routing, empty/owned states, no fake orders");
