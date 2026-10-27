"use strict";
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const read=file=>fs.readFileSync('panorama/src/scripts/custom_game/'+file,'utf8');
function harness(options={}){
 let now=100000,slot=0,account=12345,map='template_map',sequence=0;
 let loading={session_id:'test_session_A',players:[{player_id:0,authenticated:true}]};
 const panels={},events=new Map(),requests=[],urls=[],jobs=new Map(),tableHandlers=new Map(),calls={marketRefresh:0,dailyRefresh:0};
 class Panel{
  constructor(type='Panel',parent=null,id=''){this.paneltype=type;this.id=id;this.parent=parent;this.children=[];this.style={};this.enabled=true;this.visible=true;this.text='';this.events={};this.classes=new Set();if(parent)parent.children.push(this);}
  IsValid(){return !this.deleted;}Children(){return this.children;}GetParent(){return this.parent;}AddClass(n){this.classes.add(n);}RemoveClass(n){this.classes.delete(n);}BHasClass(n){return this.classes.has(n);}SetHasClass(n,on){on?this.AddClass(n):this.RemoveClass(n);}
  RemoveAndDeleteChildren(){this.children.slice().forEach(p=>p.DeleteAsync());}DeleteAsync(){this.deleted=true;if(this.parent)this.parent.children=this.parent.children.filter(p=>p!==this);this.children.slice().forEach(p=>p.DeleteAsync());}
  SetPanelEvent(n,fn){this.events[n]=fn;}SetImage(value){this.image=value;}SetScaling(){}SetAcceptsFocus(){}SetFocus(){}
 }
 function $(id){return panels[id]||(panels[id]=new Panel('Panel',null,id));}
 $.GetContextPanel=()=>$('#Root');$.CreatePanel=(type,parent,id)=>new Panel(type,parent,id);
 $.Schedule=(seconds,fn)=>{const id=++sequence;jobs.set(id,{at:now+seconds*1000,fn});return id;};$.CancelScheduled=id=>jobs.delete(id);$.RegisterEventHandler=()=>{};$.Msg=()=>{};$.DispatchEvent=(name,url)=>urls.push({name,url});
 const cfg={SurvivalDevelopmentPayments:options.development===true,SurvivalUI:{},RemainingHandoff:{},SurvivalUILayers:{Open(){},Close(){},Top(){return 'payment_shop';}}};
 cfg.SurvivalUI.ModalShell={Adopt(props){return {Open(){props.panel.visible=true;},Close(){props.panel.visible=false;},Dispose(){this.Close();}};}};
 cfg.SurvivalCommerceView={Open(){return true;},UpdateCatalog(data){this.catalog=data;},RefreshPaymentCapability(){calls.marketRefresh++;}};
 cfg.SurvivalDaily={RefreshPaymentCapability(){calls.dailyRefresh++;}};
 let failCheckoutSubscription=options.failCheckoutSubscription===true;
 const GameEvents={Subscribe(name,fn){if(name==='survival_payment_result'&&failCheckoutSubscription){failCheckoutSubscription=false;throw Error('native subscription unavailable');}const id=++sequence;events.set(id,{name,fn});return id;},Unsubscribe(id){events.delete(id);},SendCustomGameEventToServer(name,payload){requests.push({name,payload});}};
 const ctx=vm.createContext({$,Date:class extends Date{static now(){return now;}},GameUI:{CustomUIConfig:()=>cfg},GameEvents,
  Game:{GetLocalPlayerID:()=>slot,GetMapInfo:()=>({map_name:map}),GetPlayerInfo:()=>({player_steamid:String(76561197960265728n+BigInt(account))}),IsInToolsMode:()=>false},
  Players:options.fallbackOnly?{}:{GetSteamAccountID:()=>account},CustomNetTables:{GetTableValue:()=>loading,SubscribeNetTableListener(name,fn){const id=++sequence;tableHandlers.set(id,fn);return id;},UnsubscribeNetTableListener(id){tableHandlers.delete(id);}}});
 const load=file=>vm.runInContext(read(file),ctx,{filename:file});
 function emit(name,value){for(const row of [...events.values()])if(row.name===name)row.fn(value);}
 function advance(ms){const end=now+ms;let ticks=0;while(true){const entry=[...jobs.entries()].filter(([,j])=>j.at<=end).sort((a,b)=>a[1].at-b[1].at)[0];if(!entry)break;assert(++ticks<10000);jobs.delete(entry[0]);now=entry[1].at;entry[1].fn();}now=end;}
 function latestCapability(){return requests.filter(row=>row.name==='survival_payment_capability_request').at(-1);}
 function capability(extra={}){return {enabled:true,account_id:String(account),player_id:slot,match_session_id:loading.session_id,request_id:latestCapability().payload.request_id,...extra};}
 function setLoading(next){loading=next;for(const fn of [...tableHandlers.values()])fn('survival_loading','state',loading);}
 if(options.loading!==undefined)loading=options.loading;
 if(options.map!==undefined)map=options.map;
 load('payment_capability.js');load('payment_test.js');
 return {cfg,ctx,$,requests,urls,calls,load,emit,advance,capability,latestCapability,setLoading,
  paymentRequests:()=>requests.filter(row=>row.name==='survival_payment_request'),
  capabilityRequests:()=>requests.filter(row=>row.name==='survival_payment_capability_request'),
  setAccount(value){account=value;},setSlot(value){slot=value;},setMap(value){map=value;},handlers(name){return [...events.values()].filter(row=>row.name===name).map(row=>row.fn);},jobs,panels};
}
function approve(h){h.emit('survival_payment_capability',h.capability());assert.equal(h.cfg.SurvivalPayments.IsRealMoneyEnabled(),true);}
function pendingOrder(h,url='https://pay.xiaofengnet.com/ws4-payments/checkout?order=WX'+'1'.repeat(30)+'&token='+'a'.repeat(64),expected=true,provider='wechat'){
 approve(h);h.cfg.SurvivalPayments.RefreshCatalog();let req=h.paymentRequests().at(-1);
 const product={sku:'cash_test_1',title:'测试商品',enabled:true,amount_fen:100,reward_lines:[]};
 h.emit('survival_payment_result',{ok:true,action:'catalog',request_id:req.payload.request_id,products:[product],categories:[],wechat:true,alipay:true,real_money_enabled:true});
 h.cfg.SurvivalPayments.Checkout(product.sku);if(provider==='alipay')h.ctx.PaymentChannel(provider);h.ctx.PaymentBuy();req=h.paymentRequests().at(-1);assert.equal(req.payload.action,'create');
 h.emit('survival_payment_result',{ok:true,action:'create',request_id:req.payload.request_id,sku:product.sku,title:product.title,provider,quantity:1,unit_amount_fen:100,amount_fen:100,state:'pending',order_id:(provider==='alipay'?'AL':'WX')+'1'.repeat(30),
  checkout_url:url,qr_matrix:Array.from({length:29},(_,y)=>'0'.repeat(14)+(y===14?'1':'0')+'0'.repeat(14)).join('|')});
 assert.equal(h.$('#PaymentQR').style.visibility,expected?'visible':'collapse');if(expected)assert(h.$('#PaymentQR').children.length>0);
}
test('Production requests only a private capability before authenticating and never infers payment from a cached startup row',()=>{
 const h=harness();assert.equal(h.capabilityRequests().length,1);assert.deepEqual(Object.keys(h.latestCapability().payload),['request_id']);assert.equal(h.cfg.SurvivalPayments.IsRealMoneyEnabled(),false);
 h.cfg.SurvivalPayments.RefreshCatalog();h.cfg.SurvivalPayments.Checkout('cash_test_1');h.ctx.PaymentBuy();h.advance(14000);assert.equal(h.paymentRequests().length,0);assert.equal(h.capabilityRequests().length,1);
 h.advance(1000);assert.equal(h.capabilityRequests().length,2,'Capability retries are bounded to one per fifteen seconds');
});
test('Only the latest fresh request for this native account, match and slot may initialize the existing cash controller',()=>{
 const h=harness();for(const extra of [{account_id:'67890'},{player_id:1},{match_session_id:'test_session_B'},{request_id:'replayed'},{enabled:'true'},{enabled:2}]){
  h.emit('survival_payment_capability',h.capability(extra));assert.equal(h.cfg.SurvivalPayments.IsRealMoneyEnabled(),false);assert.equal(h.handlers('survival_payment_result').length,0);
 }
 approve(h);assert.equal(h.cfg.SurvivalPayments.Inspect().layout,'compact_checkout');assert.equal(h.handlers('survival_payment_result').length,1);assert.equal(h.paymentRequests().length,0);
 h.advance(5000);assert.equal(h.paymentRequests().length,1);assert.equal(h.paymentRequests()[0].payload.action,'catalog','The original authoritative cash catalog is requested after approval');
});
test('Steam64 fallback is converted exactly without floating-point identity loss',()=>{const h=harness({fallbackOnly:true});approve(h);assert.equal(h.cfg.SurvivalPaymentCapability.IsAllowed(),true);});
test('A response arriving after its request deadline cannot enable payment',()=>{const h=harness(),old=h.capability();h.advance(12000);h.emit('survival_payment_capability',old);assert.equal(h.cfg.SurvivalPayments.IsRealMoneyEnabled(),false);h.advance(3000);h.emit('survival_payment_capability',old);assert.equal(h.cfg.SurvivalPayments.IsRealMoneyEnabled(),false);approve(h);});
test('No valid startup session or wrong map means no request, and a later real startup snapshot can recover',()=>{
 const h=harness({loading:{session_id:'',players:[]}});h.advance(30000);assert.equal(h.requests.length,0);h.setLoading({session_id:'test_session_A',players:[{player_id:0,authenticated:true}]});assert.equal(h.capabilityRequests().length,1);approve(h);
 const wrong=harness({map:'another_map'});wrong.advance(20000);assert.equal(wrong.requests.length,0);
});
test('A private denial tears down pending QR and order callbacks without cancelling or recreating any financial order',()=>{
 const h=harness();pendingOrder(h);const oldHandler=h.handlers('survival_payment_result')[0],oldBuy=h.ctx.PaymentBuy,oldCount=h.paymentRequests().length;
 h.advance(15000);h.emit('survival_payment_capability',h.capability({enabled:0}));assert.equal(h.cfg.SurvivalPayments.IsRealMoneyEnabled(),false);assert.equal(h.$('#PaymentDialog').visible,false);assert.equal(h.$('#PaymentQR').children.length,0);assert.equal(h.$('#PaymentLink').text,'');assert.equal(h.handlers('survival_payment_result').length,0);
 const after=h.paymentRequests().length;oldHandler({ok:true,action:'create',sku:'cash_test_1',state:'pending'});oldBuy();h.ctx.PaymentBuy();assert.equal(h.paymentRequests().length,after);assert(after>=oldCount);
});
test('Native account changes immediately revoke the old account even before a timer or private server reply',()=>{
 const h=harness();pendingOrder(h);const oldCapability=h.capability();h.setAccount(67890);assert.equal(h.cfg.SurvivalPayments.IsRealMoneyEnabled(),false);assert.equal(h.$('#PaymentQR').children.length,0);
 h.emit('survival_payment_capability',oldCapability);assert.equal(h.cfg.SurvivalPayments.IsRealMoneyEnabled(),false);h.advance(1000);approve(h);assert.equal(h.cfg.SurvivalPayments.GetCatalog().products.length,0,'New account never inherits old orders/catalog');
});
test('Match change closes pending checkout and rejects its old lease and response nonce',()=>{
 const h=harness();pendingOrder(h);const old=h.capability();h.setLoading({session_id:'test_session_B',players:[{player_id:0,authenticated:true}]});assert.equal(h.cfg.SurvivalPayments.IsRealMoneyEnabled(),false);assert.equal(h.$('#PaymentQR').children.length,0);h.emit('survival_payment_capability',old);assert.equal(h.cfg.SurvivalPayments.IsRealMoneyEnabled(),false);approve(h);
});
test('Capability expiry and leaving the map revoke payment without accepting stale cached flags',()=>{
 const h=harness();approve(h);h.advance(30000);assert.equal(h.cfg.SurvivalPayments.IsRealMoneyEnabled(),false);const other=harness();approve(other);other.setMap('another_map');assert.equal(other.cfg.SurvivalPayments.IsRealMoneyEnabled(),false);
});
test('Production order results require a matching request correlation while the developer fixture retains its legacy behavior',()=>{
 const h=harness();approve(h);h.cfg.SurvivalPayments.RefreshCatalog();h.emit('survival_payment_result',{ok:true,action:'catalog',products:[{sku:'foreign',enabled:true,amount_fen:1}]});assert.equal(h.cfg.SurvivalPayments.GetCatalog().products.length,0);
 const dev=harness({development:true});assert.equal(dev.cfg.SurvivalPayments.IsRealMoneyEnabled(),true);assert.equal(dev.capabilityRequests().length,0);
});
test('Capability hot reload retires a pending native cash dialog and a replaced payment controller cannot receive its old result',()=>{
 const h=harness();pendingOrder(h);const old=h.capability(),handler=h.handlers('survival_payment_result')[0];h.load('payment_capability.js');h.load('payment_test.js');assert.equal(h.cfg.SurvivalPayments.IsRealMoneyEnabled(),false);assert.equal(h.$('#PaymentQR').children.length,0);h.emit('survival_payment_capability',old);assert.equal(h.cfg.SurvivalPayments.IsRealMoneyEnabled(),false);approve(h);handler({ok:true,action:'create',sku:'cash_test_1',state:'pending'});assert.equal(h.cfg.SurvivalPayments.GetCatalog().products.length,0);
});
test('The actual payment layout loads the private capability before checkout',()=>{
 const xml=fs.readFileSync('panorama/src/layout/custom_game/payment_test.xml','utf8');assert(xml.indexOf('payment_capability.js')<xml.indexOf('payment_test.js'));
});

test('An unsolicited private denial for the latest accepted challenge immediately revokes a visible QR, while replayed approval cannot renew it',()=>{
 const h=harness();pendingOrder(h);const last=h.capability();h.emit('survival_payment_capability',{...last,enabled:false});assert.equal(h.cfg.SurvivalPayments.IsRealMoneyEnabled(),false);assert.equal(h.$('#PaymentQR').children.length,0);h.emit('survival_payment_capability',last);assert.equal(h.cfg.SurvivalPayments.IsRealMoneyEnabled(),false);
});
test('Moving to another native player slot revokes its old account/match receipt and needs a fresh private challenge',()=>{
 const h=harness();approve(h);const old=h.capability();h.setSlot(1);assert.equal(h.cfg.SurvivalPayments.IsRealMoneyEnabled(),false);h.emit('survival_payment_capability',old);assert.equal(h.cfg.SurvivalPayments.IsRealMoneyEnabled(),false);h.setLoading({session_id:'test_session_A',players:[{player_id:1,authenticated:true}]});approve(h);
});

test('Native checkout accepts only the isolated fixed HTTPS WS4 routes and refuses foreign, legacy production and duplicate-query URLs',()=>{
 const wx='https://pay.xiaofengnet.com/ws4-payments/checkout?order=WX'+'1'.repeat(30)+'&token='+'a'.repeat(64);
 const invalid=[wx.replace('https:','http:'),wx.replace('pay.xiaofengnet.com','evil.example'),wx.replace('/ws4-payments/','/'),wx.replace('/checkout?','/checkout/other?'),wx+'&order=WX'+'2'.repeat(30),wx+'#fragment',wx+'&unexpected=1'];
 for(const url of invalid){const h=harness();pendingOrder(h,url,false);h.ctx.PaymentOpen();assert.equal(h.urls.length,0);}
 const h=harness(),alipay='https://pay.xiaofengnet.com/ws4-payments/checkout/alipay?order=AL'+'1'.repeat(30)+'&token='+'a'.repeat(64);pendingOrder(h,alipay,true,'alipay');h.ctx.PaymentOpen();assert.equal(h.urls.length,1);assert.equal(h.urls[0].url,alipay);
});

test('Partial native checkout initialization fails closed and an explicit user action can retry after the native dependency recovers',()=>{
 const h=harness({failCheckoutSubscription:true});h.emit('survival_payment_capability',h.capability());assert.equal(h.cfg.SurvivalPaymentCapability.IsAllowed(),true);assert.equal(h.cfg.SurvivalPayments.IsRealMoneyEnabled(),false);assert.equal(h.handlers('survival_payment_result').length,0);assert.equal(h.paymentRequests().length,0);h.cfg.SurvivalPayments.Open();assert.equal(h.cfg.SurvivalPayments.IsRealMoneyEnabled(),true);assert.equal(h.handlers('survival_payment_result').length,1);
});
