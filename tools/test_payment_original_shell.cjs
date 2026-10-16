"use strict";
const fs=require("node:fs"),vm=require("node:vm"),assert=require("node:assert/strict");
const ids={},requests=[],handlers={},timers=new Map(),urls=[];let timerId=0,top=null;
class Panel {
 constructor(type,parent,id){this.type=this.paneltype=type;this.parent=null;this.id=id;this.children=[];this.classes=new Set();this.style={};this.events={};this.enabled=true;this.visible=true;this.actualuiscale_x=this.actualuiscale_y=1;this.SetParent(parent);if(id)ids[id]=this;}
 AddClass(c){this.classes.add(c);}RemoveClass(c){this.classes.delete(c);}SetHasClass(c,v){v?this.AddClass(c):this.RemoveClass(c);}
 SetPanelEvent(k,v){this.events[k]=v;}Children(){return this.children;}RemoveAndDeleteChildren(){this.children.slice().forEach(p=>p.DeleteAsync());}
 SetParent(parent){if(this.parent)this.parent.children=this.parent.children.filter(p=>p!==this);this.parent=parent;if(parent)parent.children.push(this);}
 FindChildTraverse(id){return this.id===id?this:this.children.map(p=>p.FindChildTraverse(id)).find(Boolean);}
 GetPositionWithinWindow(){return {x:0,y:0};}
 SetImage(v){this.image=v;}SetScaling(){}SetAcceptsFocus(){}IsValid(){return !this.deleted;}
 DeleteAsync(){this.children.slice().forEach(p=>p.DeleteAsync());this.deleted=true;this.SetParent(null);}
}
const root=new Panel("Panel",null,"testRoot");root.actuallayoutwidth=1600;root.actuallayoutheight=900;
function $(id){return ids[id.slice(1)]||null;}
$.CreatePanel=(t,p,id)=>new Panel(t,p,id);$.Schedule=(delay,fn)=>{timers.set(++timerId,{delay,fn});return timerId;};$.CancelScheduled=id=>timers.delete(id);$.Msg=()=>{};
$.DispatchEvent=(name,url)=>urls.push(url);$.GetContextPanel=()=>root;
const cfg={SurvivalUILayers:{Open:id=>top=id,Close:id=>{if(top===id)top=null;},Top:()=>top}};
const env={$,GameUI:{CustomUIConfig:()=>cfg},GameEvents:{Subscribe:(name,fn)=>handlers[name]=fn,Unsubscribe:()=>{},SendCustomGameEventToServer:(name,data)=>requests.push(data)},Game:{}};
vm.createContext(env);
// Build the actual XML's controls, so missing IDs and changed event wiring fail this fixture.
const stack=[root],xml=fs.readFileSync("panorama/src/layout/custom_game/payment_test.xml","utf8");
for(const tag of xml.matchAll(/<(\/?)(Panel|Button|Label|Image|TextEntry)\b([^>]*)>/g)){
 if(tag[1]){stack.pop();continue;}
 const attrs=Object.fromEntries([...tag[3].matchAll(/([\w-]+)="([^"]*)"/g)].map(x=>[x[1],x[2]]));
 const node=new Panel(tag[2],stack.at(-1),attrs.id);(attrs.class||"").split(/\s+/).filter(Boolean).forEach(c=>node.AddClass(c));
 if(attrs.text)node.text=attrs.text;if(attrs.enabled)node.enabled=attrs.enabled!=="false";
 if(attrs.onactivate)node.events.onactivate=()=>vm.runInContext(attrs.onactivate,env);
 if(!tag[3].endsWith("/"))stack.push(node);
}
require("./load_shared_ui_test.cjs")(env,Panel,root);
const source=fs.readFileSync("panorama/src/scripts/custom_game/payment_test.js","utf8");vm.runInContext(source,env);
cfg.SurvivalPayments.Checkout("bundle_test");
vm.runInContext(fs.readFileSync("panorama/src/scripts/custom_game/remaining_5d5c1152eb.js","utf8"),env);
for(const file of ["archive_v10_data.js","common/menu_v10.js"])vm.runInContext(fs.readFileSync("panorama/src/scripts/custom_game/"+file,"utf8"),env);
const product={sku:"bundle_test",title:"礼包",amount_fen:5000,enabled:true,icon:"custom_game/archive_items_v2/lottery_lumber_crystal.png",description:"完整奖励",
 reward_lines:[{kind:"stat",id:"initial_wood",quantity:100,label:"初始木材"},{kind:"entitlement",id:"vip",quantity:1,label:"VIP"}]};
function respond(data){const request=requests.at(-1);handlers.survival_payment_result({request_id:request.request_id,action:request.action,...data});}
respond({ok:true,products:[product],wechat:1,alipay:1});
const dialog=$("#PaymentDialog");
const modal=()=>cfg.SurvivalUI.ModalManager.Get("payment_shop");
const fitOnce=()=>{const timer=[...timers].find(([,t])=>t.delay===.25);assert(timer,"the real ModalShell keeps fitting while open");timers.delete(timer[0]);timer[1].fn();};
assert(dialog.BHasClass("CompactCheckout"));assert(dialog.BHasClass("LeanCheckout"));assert(!dialog.BHasClass("MenuV10Payment"));assert(!dialog.BHasClass("MenuV10Page"));assert.equal(dialog.style.width,"580px");assert(Number.parseFloat(dialog.style.height)>0);assert.match(dialog.style.transform,/scale3d/);
root.actuallayoutwidth=640;root.actuallayoutheight=360;fitOnce();const fitted=Math.min(1,640*.94/580,360*.9/Number.parseFloat(dialog.style.height));assert.equal(dialog.style.transform,"scale3d("+fitted+","+fitted+",1)");
root.actuallayoutwidth=1600;root.actuallayoutheight=900;fitOnce();
assert.equal(dialog.style.transform,"scale3d(1,1,1)","fitting never enlarges the compact checkout");
assert.equal(top,"payment_shop");assert(modal().IsOpen());assert.equal(cfg.SurvivalMenuV10.Entries().length,0,"late shared menu helpers cannot turn checkout into a full menu");
assert.equal($("#PaymentTitle").parent.parent,dialog,"the existing XML business body stays directly in its checkout modal");
assert.equal($("#PaymentHeader").visible,true);assert($("#PaymentBack").parent.BHasClass("PaymentFooter"));assert.equal($("#PaymentBack").parent.parent,$("#PaymentTitle").parent);
assert.equal($("#PaymentHeading").text,"订单确认");assert.equal($("#PaymentQuantityPlus").enabled,false,"quantity cannot exceed the server's single-item contract");
assert.equal($("#PaymentProductArt").image,"file://{images}/"+product.icon);assert.match($("#PaymentValues").text,/VIP/);
$("#PaymentAlipay").events.onactivate();assert($("#PaymentAlipay").BHasClass("Selected"));assert(dialog.BHasClass("Open"));
assert.equal(requests.filter(r=>r.action==="create").length,0,"selecting a method must not create an order");
assert.equal(dialog.events.onactivate(),true);assert(dialog.BHasClass("Open"));
top="other_modal";$("#PaymentScrim").events.onactivate();assert(dialog.BHasClass("Open"));top="payment_shop";
$("#PaymentBuy").events.onactivate();$("#PaymentBuy").events.onactivate();assert.equal(requests.filter(r=>r.action==="create").length,1);
assert.deepEqual(Object.keys(requests.at(-1)).sort(),["action","provider","request_id","sku"],"the single-item server contract stays unchanged");assert.equal(requests.at(-1).provider,"alipay");assert.equal(requests.at(-1).sku,product.sku);
const order={ok:true,sku:product.sku,title:product.title,amount_fen:5000,provider:"alipay",state:"pending",order_id:"AL"+"1".repeat(30),checkout_mode:"qr",
 checkout_url:"https://pay.xiaofengnet.com/checkout/alipay?order=AL"+"1".repeat(30)+"&token="+"a".repeat(64),qr_matrix:Array(29).fill("0".repeat(29)).join("|"),reward_lines:product.reward_lines};
respond(order);assert(dialog.BHasClass("HasOrder"));assert.equal($("#PaymentHeading").text,"扫码支付");assert.equal($("#PaymentQR").style.visibility,"visible");assert.equal($("#PaymentQRState").style.visibility,"collapse");assert.equal(urls.length,0);
assert(Number.parseFloat(dialog.style.height)>0);assert.equal(modal().RequestClose("escape"),true);assert(!modal().IsOpen());assert(!dialog.hittestchildren);assert.equal(top,null);
cfg.SurvivalPayments.Checkout(product.sku);assert(modal().IsOpen());assert.equal($("#PaymentQR").style.visibility,"visible","Escape/reopen preserves the actual order's QR");
$("#PaymentScrim").events.onactivate();assert(!dialog.BHasClass("Open"));assert(!dialog.hittestchildren);
cfg.SurvivalPayments.Checkout(product.sku);assert.equal($("#PaymentQR").style.visibility,"visible","close/reopen must retain the actual order's QR");
$("#PaymentRefresh").events.onactivate();respond({...order,state:"delivered",effect_changes:{},game_entitlements:{vip:{active:true}}});
assert(dialog.BHasClass("Receipt"));assert.equal($("#PaymentHeading").text,"支付结果");assert.equal($("#PaymentQR").style.visibility,"collapse");assert.match($("#PaymentValues").text,/本局已生效/);
// Hot reloading keeps one real modal, one input shield, and the original XML controls.
const previousModal=modal(),previousShield=dialog.Children().find(p=>p.BHasClass("UIModalInputShield")),originalBuy=$("#PaymentBuy");
vm.runInContext(source,env);cfg.SurvivalPayments.Checkout(product.sku);respond({ok:true,products:[product],wechat:1,alipay:1});
assert.equal(cfg.SurvivalMenuV10.Entries().length,0);assert.notEqual(modal(),previousModal);assert(!previousModal.IsOpen());assert(!previousShield.IsValid());
assert.equal(dialog.Children().filter(p=>p.BHasClass("MenuV10Canvas")).length,0);assert.equal($("#PaymentBuy"),originalBuy);assert.equal(top,"payment_shop");assert(modal().IsOpen());
assert.equal(dialog.Children().filter(p=>p.BHasClass("UIModalInputShield")).length,1);
$("#PaymentClose").events.onactivate();assert(!dialog.BHasClass("Open"));assert(!modal().IsOpen());assert.equal(top,null);
cfg.SurvivalPayments.Dispose();
assert.equal(cfg.SurvivalMenuV10.Entries().length,0);assert.equal(dialog.Children().filter(p=>p.BHasClass("MenuV10Canvas")).length,0);
assert.equal(dialog.Children().filter(p=>p.BHasClass("UIModalInputShield")).length,0);
console.log("PAYMENT_ORIGINAL_SHELL_PASS: compact ModalShell, late HUD helpers, real XML bindings, channel/click boundaries, single-item contract, Escape, QR/receipt, reload cleanup");
