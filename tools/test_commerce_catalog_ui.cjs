"use strict";
const fs=require("fs"),vm=require("vm"),assert=require("node:assert/strict");
class Panel {
 constructor(type,parent,id){this.type=type;this.parent=parent;this.id=id;this.children=[];this.classes=new Set();this.style={};this.events={};if(parent)parent.children.push(this);}
 AddClass(c){this.classes.add(c);}RemoveClass(c){this.classes.delete(c);}SetHasClass(c,on){on?this.AddClass(c):this.RemoveClass(c);}
 SetPanelEvent(n,fn){this.events[n]=fn;}RemoveAndDeleteChildren(){this.children.slice().forEach(p=>p.DeleteAsync());}Children(){return this.children;}
 SetParent(p){if(this.parent)this.parent.children=this.parent.children.filter(c=>c!==this);this.parent=p;if(p)p.children.push(this);}
 SetScaling(){}IsValid(){return !this.deleted;}DeleteAsync(){this.children.slice().forEach(p=>p.DeleteAsync());this.deleted=true;this.SetParent(null);}FindChildTraverse(){return null;}
}
const root=new Panel("Panel",null,"root");root.actuallayoutwidth=1920;root.actuallayoutheight=1080;
function $(){return null;}$.CreatePanel=(t,p,id)=>new Panel(t,p,id);$.Schedule=()=>1;$.CancelScheduled=()=>{};$.Msg=()=>{};
const requests=[],cfg={};let refreshes=0;
const product={sku:"configured_bundle",title:"组合礼包",category_id:"bundles",product_type:"bundle",amount_fen:777,enabled:true,owned:0,purchase_limit:1,icon:"custom_game/archive_items_v2/lottery_attribute_crystal.png",
 reward_lines:[{id:"initial_wood",label:"木材",quantity:100},{id:"vip",label:"VIP",quantity:1},{id:"special_lottery_ticket",label:"金色抽奖券",quantity:10}]};
const catalog={catalog_hash:"a",categories:[{id:"technology",label:"科技"},{id:"bundles",label:"礼包"}],products:[product]};
const configuredData=JSON.stringify(catalog);
let currentCatalog=catalog;
cfg.SurvivalPayments={GetCatalog:()=>currentCatalog,RefreshCatalog:()=>refreshes++,Checkout:sku=>requests.push(sku)};
const env={$,GameUI:{CustomUIConfig:()=>cfg},GameEvents:{Subscribe:()=>1,Unsubscribe:()=>{}},Game:{}};
require("./load_shared_ui_test.cjs")(env,Panel,root);
cfg.RemainingHandoff={Window:()=>{},SizeWindow:()=>{},Box:()=>{},Tab:()=>{},Action:()=>{},Image:()=>{}};
for(const file of ["common/item_resources.js","common/vip_badges.js","reward_presentation.js","archive_v10_data.js","common/menu_v10.js","black_lion_market_model.js","black_lion_market.js"])vm.runInNewContext(fs.readFileSync("panorama/src/scripts/custom_game/"+file,"utf8"),env);
vm.runInNewContext(fs.readFileSync("panorama/src/scripts/custom_game/common/commerce_components.js","utf8"),env);
vm.runInNewContext(fs.readFileSync("panorama/src/scripts/custom_game/commerce_remaining_5d5c1152eb.js","utf8"),env);
const all=()=>{const out=[];function walk(p){out.push(p);p.children.forEach(walk);}walk(root);return out;};
const descendants=p=>[p,...p.Children().flatMap(descendants)];
const purchase=card=>(descendants(card).find(p=>p.BHasClass('BLMarketBuy'))||card).events.onactivate();
cfg.SurvivalCommerceView.Open();assert.equal(refreshes,1);assert.equal(requests.length,0,"opening the shop must never create an order");
const market=cfg.SurvivalBlackLionMarket.GetWindow();
assert.equal(market.panel.style.width,"1120px");assert.equal(market.panel.style.height,"790px");
assert.equal(market.layout,"black_lion_list");assert(!all().some(p=>p.BHasClass("MenuV10Sidebar")),"the market is independent of the archive sidebar");
assert.deepEqual(all().filter(p=>p.BHasClass("BLMarketTab")).map(p=>p.id),["BLMarketSection_home","BLMarketSection_bundles","BLMarketSection_promotions","BLMarketSection_vip","BLMarketSection_all"]);
assert.equal(cfg.SurvivalCommerceView.Inspect().category,"home");
const stableCard=all().find(p=>p.BHasClass("RCProduct"));
const detailBody=descendants(stableCard.__purpleDetail).find(p=>p.BHasClass('MenuV10CommerceDetailBody'));
assert.deepEqual(detailBody.Children().map(p=>[...p.classes][0]),['RCPurpleDetailTitle','RCPurpleDetailQuality','RCProductEffect']);
assert(detailBody.Children().every(p=>p.type==='Label'),'tooltip has only name, quality and effect labels');
assert.equal(detailBody.Children()[1].text,'');assert.equal(detailBody.Children()[1].visible,false,'unknown quality stays hidden');
assert.equal(detailBody.Children()[2].text,'木材 ×100\nVIP ×1\n金色抽奖券 ×10','every configured bundle reward remains in the effect text');
assert.equal(descendants(stableCard).find(p=>p.BHasClass('BLMarketPriceMain')).text,'¥7.77','the product row retains the server price');
cfg.SurvivalCommerceView.Close();cfg.SurvivalCommerceView.Open();
assert.equal(all().find(p=>p.BHasClass("RCProduct")),stableCard,"unchanged catalog must survive close/reopen without rebuilding cards");
cfg.SurvivalCommerceView.SetNotice("正在重试同步");
assert.equal(all().find(p=>p.BHasClass("RCProduct")),stableCard,"network notices must not destroy products");
cfg.SurvivalCommerceView.UpdateCatalog({...catalog,products:[{...product,stat_preview:[{value:42}]}]});
assert.equal(all().find(p=>p.BHasClass("RCProduct")),stableCard,"numeric preview refresh must preserve hovered cards");
purchase(stableCard);assert.deepEqual(requests,[product.sku]);
assert.equal(cfg.SurvivalCommerceView.Inspect().opened,false);
cfg.SurvivalCommerceView.UpdateCatalog({...catalog,products:[{...product,enabled:false,owned:1}]});
assert(!all().some(p=>p.BHasClass('BLMarketRow')),'an owned unique product is removed from the list');
assert.equal(cfg.SurvivalCommerceView.Inspect().productCount,0,'owned unique products do not contribute to counts');
cfg.SurvivalCommerceView.UpdateCatalog({...catalog,catalog_hash:"b",products:[{...product,title:"服务端新礼包",enabled:true,owned:0,amount_fen:900}]});
assert(all().some(p=>p.text==="服务端新礼包"));assert(all().some(p=>p.BHasClass('BLMarketPriceMain')&&p.text==='¥9.00'));
all().find(p=>p.id==="BLMarketSection_promotions").events.onactivate();assert(all().some(p=>p.text==="本分类暂无上架商品"));
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
assert.equal(JSON.stringify(catalog),configuredData,"UI assembly cannot rewrite authoritative prices, quantities or upgrade data");
const fractionalProduct={...product,sku:"wall_growth_display",category_id:"technology",product_type:"single",reward_lines:[
 {kind:"stat",id:"wall_armor_per_second",label:"墙每秒护甲",quantity:0.20000000298023224},
 {kind:"stat",id:"wall_health_per_second",label:"墙每秒生命",quantity:1},
 {kind:"stat",id:"negative_stat",label:"负值",quantity:-0.20000000298023224}
]};
const fractionalData=JSON.stringify(fractionalProduct),beforeDisplay=requests.length;
currentCatalog={catalog_hash:"fractional_display",categories:[{id:"technology",label:"科技"}],products:[fractionalProduct]};
cfg.SurvivalCommerceView.UpdateCatalog(currentCatalog);cfg.SurvivalCommerceView.Open();
all().find(p=>p.id==="BLMarketSection_all").events.onactivate();
assert(all().some(p=>p.text==="墙每秒护甲 +0.2\n墙每秒生命 +1.0\n负值 -0.2"),"The real product tooltip rounds network floats to one decimal and displays additive bonuses");
assert.equal(JSON.stringify(fractionalProduct),fractionalData,"Formatting never changes server reward amounts");
assert.equal(requests.length,beforeDisplay,"Displaying rounded rewards cannot start checkout");
cfg.SurvivalCommerceView.Dispose();
assert(!market.panel.IsValid(),"disposing the shop deletes the new market window");
assert(!all().some(p=>p.BHasClass("BLMarketWindow")));
console.log("COMMERCE_CATALOG_UI_PASS: independent five-tab list, bundle contents, server prices, checkout routing, empty/owned states, no fake orders");
