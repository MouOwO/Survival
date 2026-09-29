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
const names=["monkey","wall","data","turret","implant"],products=names.map(name=>({sku:name+"_test_50_v2",title:name,description:"存档道具",amount_fen:5000,owned:0,enabled:true}));
config.SurvivalPayments.Open();
assert.equal($("#PaymentDialog").Open,true);
assert.equal(topLayer,"payment_shop");assert.equal($("#PaymentScrim").Open,true);
assert.match(fs.readFileSync("panorama/src/scripts/custom_game/topnav_remaining_5d5c1152eb.js","utf8"),/shop:\["SurvivalPayments","Open"\]/);
handler({ok:true,action:"catalog",products:Object.fromEntries(products.map((p,i)=>[i+1,p]))});
assert.equal($("#PaymentProducts").children.length,5);
assert.equal($("#PaymentPrice").text,"¥50.00");
scope.PaymentBuy();scope.PaymentBuy();
assert.equal(requests.filter(x=>x.action==="create").length,1);
assert.deepEqual(Object.keys(requests[1]).sort(),["action","sku"]);
assert.equal(requests[1].sku,"monkey_test_50_v2");
const order={ok:true,action:"create",sku:"monkey_test_50_v2",title:"齐天大圣",amount_fen:5000,state:"pending",order_id:"WX"+"1".repeat(30),
 checkout_url:"https://pay.xiaofengnet.com/checkout?order=WX"+"1".repeat(30)+"&token="+"a".repeat(64)};
handler({...order,qr_matrix:Array(29).fill("0".repeat(29)).join("|")});
assert.equal($("#PaymentQR").style.visibility,"visible");assert.equal($("#PaymentBuy").enabled,false);
assert.equal(urls.length,0);scope.PaymentOpen();assert.equal(urls.length,1);
$("#PaymentProducts").children[1].events.onactivate();
assert.equal($("#PaymentPrice").text,"¥50.00");assert.equal($("#PaymentQR").style.visibility,"collapse");
scope.PaymentBuy();assert.equal(requests.at(-1).sku,"wall_test_50_v2");
handler({...order,sku:"wall_test_50_v2",checkout_url:"https://evil.example/"});scope.PaymentOpen();assert.equal(urls.length,1);
$("#PaymentProducts").children[0].events.onactivate();
handler({...order,action:"status",state:"delivered"});
assert.equal($("#PaymentBuy").enabled,false);assert.equal($("#PaymentQR").style.visibility,"collapse");
assert.match($("#PaymentStatus").text,/齐天大圣/);
handler({ok:true,action:"reset",kind:"refreshmoney"});
handler({ok:true,action:"catalog",products:products.map(p=>({...p,owned:0,enabled:true}))});
assert.equal($("#PaymentBuy").enabled,true,"reset must discard old delivered-order UI state");
scope.PaymentBuy();assert.equal(requests.at(-1).sku,"monkey_test_50_v2");
handler({ok:false,action:"create",error:"purchase_limit_reached"});assert.match($("#PaymentStatus").text,/次数限制/);
handler({ok:false,action:"catalog",error:"test_account_required"});assert.equal($("#PaymentEntry").style.visibility,"collapse");
config.SurvivalPayments.Dispose();assert.equal(topLayer,null);assert.equal($("#PaymentScrim").Open,false);
const count=requests.length;scheduled.forEach(x=>x.fn());assert.equal(requests.length,count,"disposed UI must stop all scheduled requests");
console.log("PAYMENT_UI_PASS: five ¥50 products, SKU selection, bound QR, owned state, reset/rebuy, no client prices");
