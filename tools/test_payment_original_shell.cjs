"use strict";
const fs=require("node:fs"),vm=require("node:vm"),assert=require("node:assert/strict");
const ids={},requests=[],handlers={},timers=new Map(),urls=[];let timerId=0,top=null,topClose=null;
class Panel {
 constructor(type,parent,id){this.type=this.paneltype=type;this.parent=null;this.id=id;this.children=[];this.classes=new Set();this.style={};this.events={};this.enabled=true;this.visible=true;this.actualuiscale_x=this.actualuiscale_y=1;this.SetParent(parent);if(id)ids[id]=this;}
 AddClass(c){this.classes.add(c);}RemoveClass(c){this.classes.delete(c);}SetHasClass(c,v){v?this.AddClass(c):this.RemoveClass(c);}
 SetPanelEvent(k,v){this.events[k]=v;}Children(){return this.children;}RemoveAndDeleteChildren(){this.children.slice().forEach(p=>p.DeleteAsync());}
 SetParent(parent){if(this.parent)this.parent.children=this.parent.children.filter(p=>p!==this);this.parent=parent;if(parent)parent.children.push(this);}
 FindChildTraverse(id){return this.id===id?this:this.children.map(p=>p.FindChildTraverse(id)).find(Boolean);}
 GetPositionWithinWindow(){return {x:0,y:0};}
 SetImage(v){this.image=v;}SetScaling(){}SetAcceptsFocus(){}SetFocus(){}SetAttributeString(k,v){this[k]=v;}IsValid(){return !this.deleted;}
 DeleteAsync(){this.children.slice().forEach(p=>p.DeleteAsync());this.deleted=true;this.SetParent(null);}
}
const root=new Panel("Panel",null,"testRoot");root.actuallayoutwidth=1600;root.actuallayoutheight=900;
function $(id){return ids[id.slice(1)]||null;}
$.CreatePanel=(t,p,id)=>new Panel(t,p,id);$.Schedule=(delay,fn)=>{timers.set(++timerId,fn);return timerId;};$.CancelScheduled=id=>timers.delete(id);$.Msg=()=>{};
$.DispatchEvent=(name,url)=>urls.push(url);$.GetContextPanel=()=>root;
const cfg={SurvivalUILayers:{Open:(id,p,close)=>{top=id;topClose=close;},Close:id=>{if(top===id){top=null;topClose=null;}},Top:()=>top,CloseTop:()=>topClose&&topClose('escape')}};
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
let menuAdoptions=0;cfg.SurvivalMenuV10={Adopt(){menuAdoptions++;throw Error('Checkout must remain a standalone modal');}};
const source=fs.readFileSync("panorama/src/scripts/custom_game/payment_test.js","utf8");vm.runInContext(source,env);
cfg.SurvivalPayments.Checkout("bundle_test");
vm.runInContext(fs.readFileSync("panorama/src/scripts/custom_game/remaining_5d5c1152eb.js","utf8"),env);
const product={sku:"bundle_test",title:"礼包",amount_fen:5000,max_quantity:100,enabled:true,icon:"custom_game/archive_items_v2/lottery_lumber_crystal.png",description:"完整奖励",
 reward_lines:[{kind:"stat",id:"initial_wood",quantity:100,label:"初始木材"},{kind:"entitlement",id:"vip",quantity:1,label:"VIP"}]};
function respond(data){const request=requests.at(-1);handlers.survival_payment_result({request_id:request.request_id,action:request.action,...data});}
respond({ok:true,products:[product],wechat:1,alipay:1});
const dialog=$("#PaymentDialog");
const modal=()=>cfg.SurvivalUI.ModalManager.Get('payment_shop');
assert.equal(menuAdoptions,0);assert(!dialog.BHasClass('MenuV10Page'));assert(!dialog.BHasClass('MenuV10Payment'));
assert.equal(dialog.style.width,'580px');assert.equal(dialog.style.height,'334px');assert.match(dialog.style.transform,/scale3d/);
assert.equal(top,'payment_shop');assert(modal().IsOpen());assert.equal(cfg.SurvivalPayments.Inspect().layout,'compact_checkout');
assert.equal(cfg.SurvivalPayments.Inspect().width,580);assert.equal(cfg.SurvivalPayments.Inspect().height,334);
assert.equal($("#PaymentHeader").visible,true);assert.equal($("#PaymentQuantityInput").paneltype,'TextEntry');assert.equal($("#PaymentQuantityInput").text,'1');
assert.equal($("#PaymentHeading").text,"订单确认");assert.equal($("#PaymentQuantityPlus").enabled,true);
assert.equal($("#PaymentProductArt").image,"file://{images}/"+product.icon);assert.match($("#PaymentValues").text,/VIP/);
$("#PaymentQuantityPlus").events.onactivate();assert.equal(cfg.SurvivalPayments.Inspect().quantity,2);
$("#PaymentQuantityInput").text='0';$("#PaymentQuantityInput").events.ontextentrychange();assert.equal(cfg.SurvivalPayments.Inspect().quantity,1);
$("#PaymentQuantityInput").text='101';$("#PaymentQuantityInput").events.ontextentrychange();assert.equal(cfg.SurvivalPayments.Inspect().quantity,100);
$("#PaymentQuantityInput").text='3';$("#PaymentQuantityInput").events.ontextentrychange();assert.equal(cfg.SurvivalPayments.Inspect().quantity,3);
$("#PaymentAlipay").events.onactivate();assert($("#PaymentAlipay").BHasClass("Selected"));assert(dialog.BHasClass("Open"));
assert.equal(requests.filter(r=>r.action==="create").length,0,"selecting a method must not create an order");
assert.equal(dialog.events.onactivate(),true);assert(dialog.BHasClass("Open"));
top="other_modal";$("#PaymentScrim").events.onactivate();assert(dialog.BHasClass("Open"));top="payment_shop";
$("#PaymentBuy").events.onactivate();$("#PaymentBuy").events.onactivate();assert.equal(requests.filter(r=>r.action==="create").length,1);
assert.equal(requests.at(-1).quantity,3);assert.deepEqual(Object.keys(requests.at(-1)).sort(),['action','provider','quantity','request_id','sku']);
const order={ok:true,sku:product.sku,title:product.title,quantity:3,unit_amount_fen:5000,amount_fen:15000,provider:"alipay",state:"pending",order_id:"AL"+"1".repeat(30),checkout_mode:"qr",
 checkout_url:"https://pay.xiaofengnet.com/checkout/alipay?order=AL"+"1".repeat(30)+"&token="+"a".repeat(64),qr_matrix:Array(29).fill("0".repeat(29)).join("|"),reward_lines:product.reward_lines};
respond(order);assert(dialog.BHasClass("HasOrder"));assert.equal($("#PaymentHeading").text,"扫码支付");assert.equal($("#PaymentQR").style.visibility,"visible");assert.equal($("#PaymentQRState").style.visibility,"collapse");assert.equal(urls.length,0);
assert.equal($("#PaymentQuantityInput").enabled,false,'in-flight quote locks quantity');
cfg.SurvivalUILayers.CloseTop();assert(!dialog.BHasClass("Open"));assert(!dialog.hittestchildren);assert(!modal().IsOpen());
cfg.SurvivalPayments.Checkout(product.sku);assert.equal($("#PaymentQR").style.visibility,"visible","close/reopen must retain the actual order's QR");
$("#PaymentRefresh").events.onactivate();respond({...order,state:"delivered",effect_changes:{},game_entitlements:{vip:{active:true}}});
assert(dialog.BHasClass("Receipt"));assert.equal($("#PaymentHeading").text,"支付结果");assert.equal($("#PaymentQR").style.visibility,"collapse");assert.match($("#PaymentValues").text,/本局已生效/);
cfg.SurvivalPayments.RefreshCatalog(true);respond({ok:true,products:[product],wechat:1,alipay:1});
cfg.SurvivalPayments.Checkout(product.sku);assert.equal(cfg.SurvivalPayments.Inspect().quantity,1);assert.equal($("#PaymentQuantityInput").enabled,true);assert.equal($("#PaymentQuantityPlus").enabled,true);assert(!dialog.BHasClass('Receipt'),'a fresh same-SKU checkout releases the terminal receipt and permits a new quantity');
// Hot reloading keeps one small modal, one input shield, and original XML controls.
const previousModal=modal(),originalBuy=$("#PaymentBuy"),originalInput=$("#PaymentQuantityInput");
vm.runInContext(source,env);cfg.SurvivalPayments.Checkout(product.sku);respond({ok:true,products:[product],wechat:1,alipay:1});
assert.notEqual(modal(),previousModal);assert(!previousModal.IsOpen());assert.equal($("#PaymentQuantityInput"),originalInput);
assert.equal(dialog.Children().filter(p=>p.BHasClass("MenuV10Canvas")).length,0);assert.equal($("#PaymentBuy"),originalBuy);assert.equal(top,"payment_shop");assert(modal().IsOpen());assert.equal(menuAdoptions,0);
assert.equal(dialog.Children().filter(p=>p.BHasClass("UIModalInputShield")).length,1);
$("#PaymentClose").events.onactivate();assert(!dialog.BHasClass("Open"));assert(!modal().IsOpen());assert.equal(top,null);
cfg.SurvivalPayments.Dispose();
assert.equal(dialog.Children().filter(p=>p.BHasClass("MenuV10Canvas")).length,0);
assert.equal(dialog.Children().filter(p=>p.BHasClass("UIModalInputShield")).length,0);
console.log("PAYMENT_ORIGINAL_SHELL_PASS: compact 580x600 ModalShell, late HUD helpers, real XML quantity, input/ESC boundaries, one order, QR/receipt, reload cleanup");
