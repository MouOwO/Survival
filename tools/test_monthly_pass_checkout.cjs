"use strict";
const assert=require("node:assert/strict"),fs=require("node:fs"),vm=require("node:vm");
const panels={},requests=[],scheduled=[],events={};let closedDaily=0;
function panel(){return {style:{},enabled:true,text:"",children:[],events:{},SetHasClass(n,v){this[n]=v;},AddClass(){},BHasClass(n){return !!this[n];},Children(){return this.children;},RemoveAndDeleteChildren(){this.children=[];},SetPanelEvent(n,fn){this.events[n]=fn;}};}
function $(id){return panels[id]||(panels[id]=panel());}
$.CreatePanel=(_,parent)=>{const p=panel();parent.children.push(p);return p;};
$.Schedule=(delay,fn)=>{scheduled.push({delay,fn});return scheduled.length;};
$.DispatchEvent=()=>assert.fail("confirmation cannot launch a browser");
const cfg={SurvivalDaily:{Close(){closedDaily++;}}};
const scope={$,GameUI:{CustomUIConfig:()=>cfg},GameEvents:{Subscribe:(name,fn)=>events[name]=fn,Unsubscribe(){},SendCustomGameEventToServer:(name,payload)=>requests.push({name,...payload})}};
vm.runInNewContext(fs.readFileSync("panorama/src/scripts/custom_game/payment_test.js","utf8"),scope);
const sku="archive_pass_monthly",monthly={sku,title:"签到月卡（30天）",amount_fen:2000,u_coin_price:20000,u_coin_per_yuan:1000,enabled:1,purchase_limit:0,description:"20元开通30天，续费保留剩余天数",reward_lines:[{kind:"entitlement",id:"archive_pass",quantity:1,duration_days:30,label:"签到月卡30天"}]};
function reply(data,request=requests.at(-1)){events.survival_payment_result({action:request.action,request_id:request.request_id,...data});}
events.survival_payment_open({sku});
assert.equal(closedDaily,1);assert.equal($("#PaymentDialog").Open,true);
assert.equal(requests.length,1);assert.equal(requests[0].action,"catalog","opening a month cannot create an order");
reply({ok:true,products:[{sku:"other_product",title:"其他商品",amount_fen:5000,enabled:1},monthly],wechat:1});
assert.equal($("#PaymentTitle").text,monthly.title,"the monthly entry must select the monthly SKU, even when another row sorts first");
assert.equal($("#PaymentPrice").text,"合计 ¥20.00");assert.match($("#PaymentValues").text,/30天/);assert.equal($("#PaymentBuy").enabled,true);
assert.equal(requests.filter(r=>r.action==="create").length,0);
scope.PaymentBuy();const first=requests.at(-1);
assert.equal(first.action,"create");assert.equal(first.sku,sku);
assert.deepEqual(Object.keys(first).sort(),["action","name","provider","quantity","request_id","sku"]);
reply({ok:true,sku,title:monthly.title,amount_fen:2000,u_coin_price:20000,u_coin_per_yuan:1000,state:"pending",order_id:"WX"+"1".repeat(30),reward_lines:monthly.reward_lines});
events.survival_payment_open({sku});scope.PaymentBuy();
assert.equal(requests.at(-1),first,"reopening a pending month cannot create another payment");
cfg.SurvivalPayments.RefreshCatalog(true);
reply({ok:true,products:[{...monthly,amount_fen:777,reward_lines:[{...monthly.reward_lines[0],label:"已改为7天",duration_days:7}]}],wechat:1});
assert.equal($("#PaymentPrice").text,"合计 ¥20.00","pending receipt must keep its original quoted cash price");
assert.match($("#PaymentValues").text,/30天/);
events.survival_payment_result({ok:true,action:"status",sku,title:monthly.title,amount_fen:2000,state:"delivered",order_id:"WX"+"1".repeat(30),reward_lines:monthly.reward_lines,game_entitlements:{archive_pass:{active:1}}});
assert.match($("#PaymentValues").text,/本局已生效/,"numeric game-event entitlement flags must show immediate activation");
cfg.SurvivalPayments.RefreshCatalog(true);reply({ok:true,products:[{...monthly,owned:1,enabled:1}],wechat:1});
assert.equal($("#PaymentBuy").enabled,true,"a server-authorized finite pass can renew after delivery");
scope.PaymentBuy();assert.equal(requests.at(-1).action,"create");assert.notEqual(requests.at(-1).request_id,first.request_id);
reply({ok:false,error:"payment_busy"},first);
assert.equal($("#PaymentBuy").enabled,false,"an old callback cannot release a newer renewal request");
reply({ok:false,error:"payment_unavailable"});
cfg.SurvivalPayments.Dispose();
// The daily entry keeps the accepted short label; its tooltip retains the
// authoritative price. The request still carries no client price or SKU.
const daily=require("./tests/fixtures/menus_v10_harness.cjs").createHarness();
daily.load("daily_remaining_5d5c1152eb.js");daily.cfg.SurvivalDaily.Open(false);
const snapshot={ok:true,sequence:1,today:25004,count:0,pending:0,has_pass:0,purchase_enabled:1,price:"20元",duration_days:30,ordinary_status:"claimable",calendar28:[],cycle:[],specials:[],missed:[]};
daily.emit("survival_daily_snapshot",snapshot);
assert.equal(daily.nodes.PassPurchaseText.text,"开通月卡");assert.equal(daily.nodes.PassPurchase.enabled,true);
assert.match(daily.nodes.PassPrice.text,/20元/);
daily.click(daily.nodes.PassPurchase);assert.equal(daily.sent.at(-1).name,"survival_pass_purchase");assert.deepEqual(Object.keys(daily.sent.at(-1).payload),[]);
daily.emit("survival_daily_snapshot",{...snapshot,sequence:2,has_pass:1,expires_at:2000000000});
assert.equal(daily.nodes.PassPurchaseText.text,"续费月卡");
console.log("MONTHLY_CHECKOUT_UI_PASS: correct SKU, authoritative ¥20, 30 days, no implicit orders, immutable pending quote, renewal and request correlation");
