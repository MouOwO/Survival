"use strict";
const assert=require("node:assert/strict"),fs=require("node:fs"),vm=require("node:vm");
let now=100000,visible=false,snapshot=null,notice="",updates=0;
const panels={},requests=[],scheduled=[],handlers={};
function panel(){return {style:{},children:[],events:{},SetHasClass(){},AddClass(){},
 RemoveAndDeleteChildren(){this.children=[];},SetPanelEvent(k,v){this.events[k]=v;}};}
function $(id){return panels[id]||(panels[id]=panel());}
$.CreatePanel=(_,p)=>{const c=panel();p.children.push(c);return c;};
$.Schedule=(delay,fn)=>scheduled.push({at:now+delay*1000,fn});
const cfg={SurvivalCommerceView:{
 Open(){visible=true;this.UpdateCatalog(cfg.SurvivalPayments.GetCatalog());cfg.SurvivalPayments.RefreshCatalog();},
 UpdateCatalog(data){snapshot=data;updates++;notice=data.error||"";},SetNotice(s){notice=s;},IsOpen:()=>visible
}};
const scope={$,Date:{now:()=>now},GameUI:{CustomUIConfig:()=>cfg},
 GameEvents:{Subscribe:(k,v)=>handlers[k]=v,Unsubscribe(){},SendCustomGameEventToServer:(_,d)=>requests.push(d)}};
vm.runInNewContext(fs.readFileSync("panorama/src/scripts/custom_game/payment_test.js","utf8"),scope);
function advance(ms){const until=now+ms;let count=0;while(true){scheduled.sort((a,b)=>a.at-b.at);
 if(!scheduled.length||scheduled[0].at>until)break;
 const job=scheduled.shift();now=job.at;job.fn();assert(++count<200,"bounded retry loop");}now=until;}
function respond(data,request=requests.at(-1)){handlers.survival_payment_result({action:request.action,request_id:request.request_id,...data});}
const product={sku:"wood_test",title:"木材",amount_fen:5000,enabled:1,owned:0,category_id:"technology",reward_lines:[]};
const initial={ok:true,catalog_hash:"v1",wechat:1,alipay:1,categories:[{id:"technology",label:"科技"}],products:[product]};
cfg.SurvivalPayments.Open();visible=false;cfg.SurvivalPayments.Open();
assert.equal(requests.length,1,"reopening during a pending catalog must join the same request");
respond(initial);
const card=$("#PaymentProducts").children[0];
for(let i=0;i<5;i++){visible=false;cfg.SurvivalPayments.Open();}
assert.equal(requests.length,1,"fresh catalog reopening must not hit the one-second rate limit");
assert.equal($("#PaymentProducts").children[0],card);
assert(!("panel" in snapshot.products[0]),"cached data must not contain UI handles");
advance(20000);assert.equal(requests.length,2,"visible shop checks for server changes after cache expiry");
respond({ok:false,error:"payment_busy"});
assert.equal(snapshot.products[0].sku,product.sku,"temporary busy response must preserve all rows");
assert.match(notice,/已保留商品/);
advance(3100);assert.equal(requests.length,3,"transient failure retries without another click");
respond(initial);assert.equal($("#PaymentProducts").children[0],card,"unchanged data must preserve panels");
const beforeOld=updates;respond({...initial,catalog_hash:"obsolete",products:[]},requests[0]);
assert.equal(updates,beforeOld,"late old replies cannot overwrite current data");
cfg.SurvivalPayments.RefreshCatalog(true);
respond({...initial,products:[{...product,owned:1,enabled:0}]});
assert.equal(snapshot.catalog_hash,"v1");assert.equal(snapshot.products[0].owned,1,"same config hash must still update player ownership");
assert.equal($("#PaymentBuy").enabled,false);
cfg.SurvivalPayments.RefreshCatalog(true);
respond({...initial,catalog_hash:"v2",products:[{...product,title:"新礼包",amount_fen:6000}]});
assert.equal($("#PaymentPrice").text,"¥60.00","server changes replace the cached price");
cfg.SurvivalPayments.Checkout(product.sku);scope.PaymentBuy();
const create=requests.at(-1);assert.equal(create.action,"create");
respond({ok:false,error:"payment_busy"},requests[0]);scope.PaymentBuy();
assert.equal(requests.at(-1),create,"stale catalog failure must not unlock an active purchase");
respond({ok:false,error:"payment_unavailable"});
scope.PaymentBuy();
respond({ok:true,sku:product.sku,title:product.title,amount_fen:5000,state:"delivered",order_id:"paid_test",effects:{},effect_changes:{}});
advance(1100);assert.equal(requests.at(-1).action,"catalog","delivery bypasses freshness to refresh ownership");
respond({...initial,products:[{...product,enabled:0,owned:1}]});
handlers.survival_payment_result({ok:true,action:"reset"});
advance(1100);assert.equal(requests.at(-1).action,"catalog","reset bypasses freshness so repeat purchases can update");
respond(initial);
scope.PaymentToggle();visible=false;
const closedCount=requests.length;advance(60000);
assert.equal(requests.length,closedCount,"closed shop must stop catalog polling");
cfg.SurvivalPayments.Open();const timedOut=requests.at(-1);
advance(32000);assert.match(notice,/超时/);assert.equal(snapshot.products.length,1);
advance(3100);assert.notEqual(requests.at(-1).request_id,timedOut.request_id);
respond({...initial,products:[]},timedOut);assert.equal(snapshot.products.length,1,"timed-out reply cannot replace the retry");
respond({ok:false,error:"match_session_missing"});
assert.equal(snapshot.products.length,0,"a lost authenticated session must invalidate cached player data");
cfg.SurvivalPayments.Dispose();
const end=requests.length;advance(60000);assert.equal(requests.length,end);
console.log("PAYMENT_CATALOG_CACHE_PASS: reopen/in-flight, TTL, busy/timeout recovery, stale replies, ownership, hot update, reset, session loss");
