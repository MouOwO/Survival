"use strict";
const assert=require("node:assert/strict"),fs=require("node:fs"),vm=require("node:vm");
const panels={},requests=[],scheduled=[],events={};let closedDaily=0;
function panel(){return {style:{},enabled:true,text:"",children:[],events:{},IsValid(){return !this.deleted;},DeleteAsync(){this.deleted=true;if(this.parent)this.parent.children=this.parent.children.filter(child=>child!==this);},SetHasClass(n,v){this[n]=v;},AddClass(){},BHasClass(n){return !!this[n];},Children(){return this.children;},RemoveAndDeleteChildren(){this.children=[];},SetPanelEvent(n,fn){this.events[n]=fn;}};}
function $(id){return panels[id]||(panels[id]=panel());}
$.CreatePanel=(_,parent)=>{const p=panel();p.parent=parent;parent.children.push(p);return p;};
$.Schedule=(delay,fn)=>{scheduled.push({delay,fn});return scheduled.length;};
$.DispatchEvent=()=>assert.fail("confirmation cannot launch a browser");
const cfg={SurvivalDevelopmentPayments:true,SurvivalDaily:{Close(){closedDaily++;}}};
const scope={$,GameUI:{CustomUIConfig:()=>cfg},GameEvents:{Subscribe:(name,fn)=>events[name]=fn,Unsubscribe(){},SendCustomGameEventToServer:(name,payload)=>requests.push({name,...payload})}};
vm.runInNewContext(fs.readFileSync("panorama/src/scripts/custom_game/payment_test.js","utf8"),scope);
const sku="archive_pass_monthly",monthly={sku,title:"签到月卡（30天）",amount_fen:2000,u_coin_price:20000,u_coin_per_yuan:1000,enabled:1,purchase_limit:0,description:"20元开通30天，续费保留剩余天数",reward_lines:[{kind:"entitlement",id:"archive_pass",quantity:1,duration_days:30,label:"签到月卡30天"}]};
function reply(data,request=requests.at(-1)){events.survival_payment_result({action:request.action,request_id:request.request_id,...data});}
events.survival_payment_open({sku});
assert.equal(closedDaily,0,"monthly checkout must keep the daily rewards underneath open");assert.equal($("#PaymentDialog").Open,true);
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
for(const source of ["common/ui_registry.js","common/ui_components.js","ui_layers.js","archive_theme_tokens.js","archive_parchment_data.js","archive_handoff_180de7e38b.js","archive_v10_semantics.js","common/archive_tooltip.js","daily_gw2_data.js"])daily.load(source);
daily.load("daily_remaining_5d5c1152eb.js");daily.cfg.SurvivalDaily.Open(false);
const snapshot={ok:true,sequence:1,today:25004,count:7,pending:0,has_pass:0,purchase_enabled:1,price:"20元",duration_days:30,ordinary_status:"claimed",calendar28:[],cycle:[],
 specials:[{id:"daily_wealth_talisman",day:7,name:"聚财古符",description:"开局金币+50",owned:0}],missed:[]};
daily.emit("survival_daily_snapshot",snapshot);
assert.equal(daily.nodes.PassPurchaseText.text,"开通月卡");assert.equal(daily.nodes.PassPurchase.enabled,true);
assert.match(daily.nodes.PassPrice.text,/20元/);
daily.click(daily.nodes.PassPurchase);assert.equal(daily.sent.at(-1).name,"survival_pass_purchase");assert.deepEqual(Object.keys(daily.sent.at(-1).payload),[]);
// Mount the real checkout XML beside the real daily renderer and shared modal
// stack. Only native panels and event transport are fixtures; no financial
// request leaves this process, and no receipt can mint a daily entitlement.
const NativePanel=daily.root.constructor,xml=fs.readFileSync("panorama/src/layout/custom_game/payment_test.xml","utf8"),stack=[daily.root];
for(const tag of xml.matchAll(/<(\/?)(Panel|Button|Label|Image|TextEntry)\b([^>]*)>/g)){
 if(tag[1]){stack.pop();continue;}
 const attrs=Object.fromEntries([...tag[3].matchAll(/([\w-]+)="([^"]*)"/g)].map(x=>[x[1],x[2]]));
 const node=new NativePanel(tag[2],stack.at(-1),attrs.id||"");if(attrs.class)node.AddClass(attrs.class);if(attrs.text)node.text=attrs.text;
 if(!tag[3].endsWith("/"))stack.push(node);
}
const paymentEvents={},paymentCalls=[];
function payment$(id){return daily.nodes[id.slice(1)]||null;}
payment$.GetContextPanel=()=>daily.root;
payment$.CreatePanel=(type,parent,id)=>new NativePanel(type,parent,id||"");
payment$.Schedule=(delay,fn)=>{scheduled.push({delay,fn});return scheduled.length;};payment$.CancelScheduled=()=>{};
payment$.DispatchEvent=()=>assert.fail("monthly confirmation cannot open an external browser");
const paymentScope={$:payment$,GameUI:{CustomUIConfig:()=>daily.cfg},GameEvents:{Subscribe:(name,fn)=>{paymentEvents[name]=fn;return name;},Unsubscribe(name){delete paymentEvents[name];},SendCustomGameEventToServer:(name,payload)=>paymentCalls.push({name,...payload})}};
vm.runInNewContext(fs.readFileSync("panorama/src/scripts/custom_game/payment_test.js","utf8"),paymentScope);
function paymentReply(value,request=paymentCalls.at(-1)){paymentEvents.survival_payment_result({action:request.action,request_id:request.request_id,...value});}
function assertDailyLocked(message){
 assert(daily.cfg.SurvivalDaily.Inspect().open,message+": daily remains open");assert.equal(daily.nodes.DailyWindow.visible,true);
 assert.equal(daily.cfg.SurvivalDaily.Inspect().hasPass,false,message+": purchase event cannot grant a pass");
 assert(daily.nodes.DailyGW2Special_daily_wealth_talisman.BHasClass("DailyGW2Locked"),message+": milestone stays locked");
 assert.equal(daily.nodes.PassPurchaseText.text,"开通月卡");
}
assertDailyLocked("before checkout");assert.equal(daily.cfg.SurvivalUILayers.Top(),"daily_rewards");
paymentEvents.survival_payment_open({sku});assertDailyLocked("opening checkout");
assert.equal(daily.cfg.SurvivalUILayers.Top(),"payment_shop");assert(daily.cfg.SurvivalPayments.Inspect().opened);
assert.equal(paymentCalls.filter(call=>call.action==="create").length,0,"opening a monthly confirmation creates no order");
paymentReply({ok:true,products:[monthly],wechat:1});
paymentScope.PaymentBuy();paymentReply({ok:false,error:"payment_unavailable"});assertDailyLocked("failed order creation");
paymentScope.PaymentBuy();
const monthlyOrder={ok:true,sku,title:monthly.title,amount_fen:2000,u_coin_price:20000,u_coin_per_yuan:1000,quantity:1,
 state:"pending",order_id:"WX"+"3".repeat(30),reward_lines:monthly.reward_lines};
paymentReply(monthlyOrder);assertDailyLocked("pending order");
paymentScope.PaymentRefresh();paymentReply({...monthlyOrder,state:"paid_review",game_entitlements:{archive_pass:{active:1}}});
assertDailyLocked("unconfirmed review");
// Even a delivered payment response does not substitute for the daily
// service's authoritative entitlement snapshot or grant a milestone reward.
paymentScope.PaymentRefresh();paymentReply({...monthlyOrder,state:"delivered",game_entitlements:{archive_pass:{active:1}}});
assertDailyLocked("payment receipt before daily snapshot");
daily.emit("survival_daily_snapshot",{...snapshot,sequence:2,has_pass:1,expires_at:2000000000});
assert.equal(daily.nodes.PassPurchaseText.text,"续费月卡");assert(daily.cfg.SurvivalDaily.Inspect().open);
assert(!daily.nodes.DailyGW2Special_daily_wealth_talisman.BHasClass("DailyGW2Locked"),"the committed daily snapshot unlocks the qualified monthly reward");
assert(!daily.nodes.DailyGW2Special_daily_wealth_talisman.BHasClass("DailyGW2Owned"),"unlocking a pass cannot fabricate an already-granted reward");
assert.equal(daily.cfg.SurvivalUILayers.Top(),"payment_shop","refreshing daily rewards cannot steal checkout focus");
daily.click(daily.nodes.PaymentClose);
assert.equal(daily.cfg.SurvivalPayments.Inspect().opened,false);assert(daily.cfg.SurvivalDaily.Inspect().open);
assert.equal(daily.cfg.SurvivalUILayers.Top(),"daily_rewards","closing checkout returns to the still-open daily calendar");
assert.equal(daily.nodes.DailyWindow.visible,true);assert.equal(daily.nodes.DailyCards.GetChildCount(),28);
// Late delivery after the player closes the calendar must not reopen it.
daily.cfg.SurvivalDaily.Close();daily.emit("survival_daily_snapshot",{...snapshot,sequence:3,has_pass:1,expires_at:2000000000});
assert.equal(daily.cfg.SurvivalDaily.Inspect().open,false);assert.equal(daily.cfg.SurvivalUILayers.Top(),null);
daily.cfg.SurvivalPayments.Dispose();daily.cfg.SurvivalDaily.Dispose();
console.log("MONTHLY_CHECKOUT_UI_PASS: correct SKU, authoritative price, unchanged immutable orders and renewal; real daily/checkout/modal stack, failure/pending/review never grant, authoritative daily unlock, checkout close preserves calendar, late delivery never reopens");

// Unlike a single handler slot, native custom events retain each subscription
// until it is explicitly removed. Keep that contract when a deleted native
// shell throws during teardown and a new controller takes over the same HUD.
function lifecycleHarness(){
 const nodes={},bindings=new Map(),calls=[],jobs=[],created=[],modals=[];let closed=0;
 function nativePanel(type="Panel",parent=null){
  const node={paneltype:type,parent,style:{},enabled:true,text:"",children:[],events:{},deleted:false,
   IsValid(){return !this.deleted;},SetHasClass(name,value){this[name]=value;},AddClass(name){this[name]=true;},RemoveClass(name){delete this[name];},BHasClass(name){return !!this[name];},
   Children(){return this.children;},GetChildCount(){return this.children.length;},GetParent(){return this.parent;},RemoveAndDeleteChildren(){this.children=[];},
   SetPanelEvent(name,fn){this.events[name]=fn;},DeleteAsync(){this.deleted=true;if(this.parent)this.parent.children=this.parent.children.filter(child=>child!==this);}};
  if(parent)parent.children.push(node);created.push(node);return node;
 }
 function lookup(id){return nodes[id]||(nodes[id]=nativePanel());}
 lookup.GetContextPanel=()=>lookup("#Root");lookup.CreatePanel=(type,parent)=>nativePanel(type,parent);
 lookup.Schedule=(delay,fn)=>{jobs.push({delay,fn});return jobs.length;};lookup.CancelScheduled=()=>{};lookup.DispatchEvent=()=>assert.fail("lifecycle checks never open a browser");lookup.Msg=()=>{};
 const config={SurvivalDevelopmentPayments:true,SurvivalDaily:{Close(){closed++;}},SurvivalUI:{ModalShell:{Adopt(){
  const modal={throwOnClose:false,Open(){},Close(){if(this.throwOnClose)throw Error("Underlying panel is deleted");},Dispose(){this.Close();}};modals.push(modal);return modal;
 }}}};
 const context=vm.createContext({$:lookup,GameUI:{CustomUIConfig:()=>config},GameEvents:{
  Subscribe(name,fn){const listeners=bindings.get(name)||[];listeners.push(fn);bindings.set(name,listeners);return fn;},
  Unsubscribe(fn){for(const [name,listeners]of bindings)bindings.set(name,listeners.filter(listener=>listener!==fn));},
  SendCustomGameEventToServer(name,payload){calls.push({name,payload});}}});
 const source=fs.readFileSync("panorama/src/scripts/custom_game/payment_test.js","utf8");
 const load=()=>vm.runInContext(source,context);
 return {cfg:config,calls,jobs,created,modals,nodes,load,listeners:name=>bindings.get(name)||[],closed:()=>closed};
}
{
 const h=lifecycleHarness();h.load();h.cfg.SurvivalPayments.Checkout(sku);
 const retired=h.cfg.SurvivalPayments,oldOpen=h.listeners("survival_payment_open")[0],oldTimers=h.jobs.slice();
 h.modals[0].throwOnClose=true;
 assert.doesNotThrow(()=>h.load(),"a deleted previous shell cannot abort the replacement controller");
 assert.notEqual(h.cfg.SurvivalPayments,retired);
 for(const name of ["survival_payment_open","survival_payment_result"])
  assert.equal(h.listeners(name).length,1,"teardown must remove old "+name+" subscriptions before native close can throw");
 let forwarded=0;const current=h.cfg.SurvivalPayments,checkout=current.Checkout;
 current.Checkout=function(...args){forwarded++;return checkout(...args);};
 const before=h.calls.length;
 oldOpen({sku});for(const job of oldTimers)job.fn();
 assert.equal(forwarded,0,"a captured retired callback cannot forward to the current API");
 assert.equal(h.calls.length,before,"retired callbacks and timers cannot submit requests");assert.equal(h.closed(),0);
 const liveOpen=h.listeners("survival_payment_open")[0];liveOpen({sku});
 assert.equal(forwarded,1,"exactly the current subscription opens the confirmation");assert.equal(h.closed(),0);
 let newerForwards=0;h.cfg.SurvivalPayments={Checkout(){newerForwards++;}};
 liveOpen({sku});assert.equal(newerForwards,0,"a superseded but still-valid native context cannot forward to another controller");
 h.cfg.SurvivalPayments=current;
 // Panorama can retire layout children while preserving its native root and
 // even its outer dialog. The child marker must invalidate this generation.
 const markers=h.created.filter(node=>node.parent===h.nodes["#PaymentDialog"]&&node.paneltype==="Panel"&&node.IsValid());
 assert(markers.length,"checkout lifecycle has a child marker independent of the surviving dialog");
 const marker=markers.at(-1);marker.deleted=true;const after=h.calls.length;
 liveOpen({sku});
 assert.equal(forwarded,1,"a dead layout marker prevents forwarding through an otherwise-current API");assert.equal(h.calls.length,after);assert.equal(h.closed(),0);
 h.cfg.SurvivalPayments.Dispose();
 assert.equal(h.listeners("survival_payment_open").length,0);assert.equal(h.listeners("survival_payment_result").length,0);
}
console.log("MONTHLY_CHECKOUT_LIFECYCLE_PASS: native close failure unsubscribes first; one current callback; retired handlers/timers and dead layout markers cannot reopen checkout or close daily rewards");
