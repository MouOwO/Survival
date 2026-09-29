"use strict";
const assert=require("node:assert/strict"),fs=require("node:fs"),vm=require("node:vm");
const panels={},requests=[],urls=[],scheduled=[],subscriptions={};
function panel(){return {style:{},enabled:true,text:"",children:[],events:{},SetHasClass(name,value){this[name]=value;},
 RemoveAndDeleteChildren(){this.children=[];},AddClass(){},SetPanelEvent(name,fn){this.events[name]=fn;}};}
function $(id){return panels[id]||(panels[id]=panel());}
$.CreatePanel=(_,parent)=>{const child=panel();parent.children.push(child);return child;};
$.Schedule=(delay,fn)=>{scheduled.push({delay,fn});return scheduled.length;};
$.DispatchEvent=(name,url)=>urls.push(url);
let topLayer=null;
const config={SurvivalUILayers:{Open:(id)=>topLayer=id,Close:()=>topLayer=null}};
const scope={$,GameUI:{CustomUIConfig:()=>config},GameEvents:{SendCustomGameEventToServer:(name,data)=>requests.push(data),Subscribe:(name,fn)=>subscriptions[name]=fn,Unsubscribe:()=>{}}};
vm.createContext(scope);vm.runInContext(fs.readFileSync("panorama/src/scripts/custom_game/payment_test.js","utf8"),scope);
const handler=subscriptions.survival_payment_result;
const names=["wood_100","gold_100","wall_armor_100","wall_health_100","tower_attack_100"],products=names.map(name=>({sku:name+"_test_50_v3",title:name,description:"存档道具",amount_fen:5000,owned:0,enabled:true,stat_preview:[{field_id:"initial_wood",value:80,delta:100,after:180}]}));
config.SurvivalPayments.Open();
assert.equal($("#PaymentDialog").Open,true);
assert.equal(topLayer,"payment_shop");assert.equal($("#PaymentScrim").Open,true);
assert.match(fs.readFileSync("panorama/src/scripts/custom_game/topnav_remaining_5d5c1152eb.js","utf8"),/shop:\["SurvivalPayments","Open"\]/);
handler({ok:true,action:"catalog",products:Object.fromEntries(products.map((p,i)=>[i+1,p])),game_values:{initial_wood:80},wallet:{wood:110000000}});
assert.equal($("#PaymentProducts").children.length,5);
assert.equal($("#PaymentPrice").text,"¥50.00");
assert.match($("#PaymentValues").text,/80 → 180/);assert.match($("#PaymentValues").text,/110000000/);
scope.PaymentBuy();scope.PaymentBuy();
assert.equal(requests.filter(x=>x.action==="create").length,1);
assert.deepEqual(Object.keys(requests[1]).sort(),["action","sku"]);
assert.equal(requests[1].sku,"wood_100_test_50_v3");
const order={ok:true,action:"create",sku:"wood_100_test_50_v3",title:"初始木材 +100",amount_fen:5000,state:"pending",order_id:"WX"+"1".repeat(30),
 checkout_url:"https://pay.xiaofengnet.com/checkout?order=WX"+"1".repeat(30)+"&token="+"a".repeat(64)};
handler({...order,qr_matrix:Array(29).fill("0".repeat(29)).join("|")});
assert.equal($("#PaymentQR").style.visibility,"visible");assert.equal($("#PaymentBuy").enabled,false);
assert.equal(urls.length,0);scope.PaymentOpen();assert.equal(urls.length,1);
$("#PaymentProducts").children[1].events.onactivate();
assert.equal($("#PaymentPrice").text,"¥50.00");assert.equal($("#PaymentQR").style.visibility,"collapse");
scope.PaymentBuy();assert.equal(requests.at(-1).sku,"gold_100_test_50_v3");
handler({...order,sku:"gold_100_test_50_v3",checkout_url:"https://evil.example/"});scope.PaymentOpen();assert.equal(urls.length,1);
$("#PaymentProducts").children[0].events.onactivate();
handler({...order,action:"status",state:"delivered",effect_changes:{initial_wood:{before:80,after:180,delta:100}},game_values:{initial_wood:180},wallet:{wood:110000100}});
assert.match($("#PaymentValues").text,/本单存档：80 → 180/);assert.match($("#PaymentValues").text,/110000100/);
assert.equal($("#PaymentBuy").enabled,false);assert.equal($("#PaymentQR").style.visibility,"collapse");
assert.match($("#PaymentStatus").text,/初始木材 \+100/);
handler({ok:true,action:"reset",kind:"refreshmoney"});
handler({ok:true,action:"catalog",products:products.map(p=>({...p,owned:0,enabled:true,stat_preview:[{field_id:"initial_wood",value:80,delta:100,after:180}]}))});
assert.equal($("#PaymentBuy").enabled,true,"reset must discard old delivered-order UI state");
scope.PaymentBuy();assert.equal(requests.at(-1).sku,"wood_100_test_50_v3");
handler({ok:false,action:"create",error:"purchase_limit_reached"});assert.match($("#PaymentStatus").text,/次数限制/);
handler({ok:false,action:"catalog",error:"test_account_required"});assert.equal($("#PaymentEntry").style.visibility,"collapse");
const bundle={sku:"mixed_bundle",title:"完整礼包",description:"全部发放",amount_fen:777,enabled:true,owned:0,
 reward_lines:[{kind:"stat",id:"initial_wood",quantity:100,label:"初始木材"},{kind:"stat",id:"wall_armor",quantity:100,label:"城墙护甲"},{kind:"entitlement",id:"vip",quantity:1,label:"VIP权限"}],
 stat_preview:[{field_id:"initial_wood",value:10,after:110,delta:100},{field_id:"wall_armor",value:0,after:100,delta:100}]};
handler({ok:true,action:"catalog",products:[bundle]});
assert.equal($("#PaymentPrice").text,"¥7.77");assert.match($("#PaymentValues").text,/10 → 110/);assert.match($("#PaymentValues").text,/0 → 100/);assert.match($("#PaymentValues").text,/VIP权限/);
scope.PaymentBuy();assert.equal(requests.at(-1).sku,"mixed_bundle");
const bundleOrder={...order,...bundle,effects:{initial_wood:100,wall_armor:100}};
handler(bundleOrder);
handler({ok:true,action:"catalog",products:[{...bundle,amount_fen:999,title:"已修改的新商品",reward_lines:[]}]});
assert.equal($("#PaymentPrice").text,"¥7.77","pending checkout must keep its original price");assert.equal($("#PaymentTitle").text,"完整礼包");assert.match($("#PaymentValues").text,/VIP权限/);
handler({ok:true,action:"catalog",products:[]});
assert.equal($("#PaymentProducts").children.length,1,"delisting cannot hide an existing checkout");
handler({...bundleOrder,action:"status",state:"delivered",effect_changes:{initial_wood:{before:10,after:110,delta:100},wall_armor:{before:0,after:100,delta:100}},game_entitlements:{vip:{active:true}}});
assert.match($("#PaymentValues").text,/本单存档：10 → 110/);assert.match($("#PaymentValues").text,/本单存档：0 → 100/);assert.match($("#PaymentValues").text,/本局已生效/);
handler({ok:true,action:"catalog",products:[{...bundle,owned:1,enabled:true}]});
assert.equal($("#PaymentBuy").enabled,true,"server may permit another purchase of a repeatable product");
scope.PaymentBuy();assert.equal(requests.at(-1).sku,"mixed_bundle");
let storeOpened=false;config.SurvivalCommerceView={Open:()=>{storeOpened=true;}};
scope.PaymentShop();assert(storeOpened);assert.equal($("#PaymentDialog").Open,false);
config.SurvivalPayments.Dispose();assert.equal(topLayer,null);assert.equal($("#PaymentScrim").Open,false);
const count=requests.length;scheduled.forEach(x=>x.fn());assert.equal(requests.length,count,"disposed UI must stop all scheduled requests");
console.log("PAYMENT_UI_PASS: variable prices, complete bundle receipts, immutable pending checkout, delisting recovery, repeat purchases, shop routing, trusted QR");
