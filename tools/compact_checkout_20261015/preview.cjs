'use strict';
// Offline assembly of the actual payment XML, JavaScript and CSS. No account or gateway.
const fs=require('fs'),path=require('path'),crypto=require('crypto'),{spawnSync}=require('child_process');
const out='design_refs/compact_checkout_20261015/final/preview';
const built=spawnSync(process.execPath,['tools/menus_v10/preview.cjs','--out',out],{encoding:'utf8',windowsHide:true});
if(built.status!==0)throw Error(built.stdout+built.stderr);
const entry=path.join(out,'index.html');let html=fs.readFileSync(entry,'utf8');
const mark='window.PREVIEW_LAYOUTS=',next=';window.PREVIEW_SOURCES=',start=html.indexOf(mark)+mark.length,end=html.indexOf(next,start);
const allLayouts=JSON.parse(html.slice(start,end)),layouts=allLayouts.filter(l=>l.rel==='layout/custom_game/payment_test.xml');
if(layouts.length!==1)throw Error('Active payment layout missing');
// The generic builder concatenates all layout CSS. Keep only the payment context's exact include order.
const cssPath=path.join(out,'style.css'),allCss=fs.readFileSync(cssPath,'utf8');
const following=allLayouts[1]&&allLayouts[1].styles[0];
if(following){let cursor=0;for(const rel of layouts[0].styles){const marker='/* '+rel+' */',at=allCss.indexOf(marker,cursor);if(at<0)throw Error('Payment CSS include missing: '+rel);cursor=at+marker.length;}const cut=allCss.indexOf('/* '+following+' */',cursor);if(cut<0)throw Error('Cannot isolate payment CSS context');fs.writeFileSync(cssPath,allCss.slice(0,cut));}

layouts[0].scripts=layouts[0].scripts.filter(p=>/\/(?:ui_registry|ui_components|ui_layers|payment_test)\.js$/.test(p));
html=html.slice(0,start)+JSON.stringify(layouts)+html.slice(end);
html=html.replace(/<script src="[^"]*tools\/menus_v10\/state\.js"><\/script>/,'<script src="state.js"></script>');
html=html.replace(/(<div id="PreviewCaption">)[\s\S]*?(<\/div>)/,'$1紧凑购买窗 · 实际生产 XML / JS / CSS · 数量与账号为离线样例 · 未连接游戏或支付$2');
html=html.replace('</style>','input.panel{font-family:inherit;outline:none;border-radius:0;padding:0;text-align:center}.PreviewContext input{pointer-events:auto}</style>');
fs.writeFileSync(entry,html);
const state=String.raw`'use strict';
// Adapter correction is local to this acceptance preview; production and shared adapter are unchanged.
const textDescriptor=Object.getOwnPropertyDescriptor(Panel.prototype,'text');
Object.defineProperty(Panel.prototype,'text',{configurable:true,get(){return this.type==='TextEntry'?this.el.value:textDescriptor.get.call(this)},set(v){textDescriptor.set.call(this,v)}});
const enabledDescriptor=Object.getOwnPropertyDescriptor(Panel.prototype,'enabled');
Object.defineProperty(Panel.prototype,'enabled',{configurable:true,get(){return enabledDescriptor.get.call(this)},set(v){enabledDescriptor.set.call(this,v);if(this.type==='TextEntry')this.el.disabled=v===false;}});
const nativeSetEvent=Panel.prototype.SetPanelEvent;
Panel.prototype.SetPanelEvent=function(name,fn){
 if(this.type!=='TextEntry'||!['ontextentrychange','oninputsubmit','ontextentrysubmit'].includes(name))return nativeSetEvent.call(this,name,fn);
 const event=name==='ontextentrychange'?'input':'keydown',old=this.events[name];if(old)this.el.removeEventListener(event,old);
 const wrapped=e=>{if(event==='keydown'&&e.key!=='Enter')return;try{fn();syncLayout()}catch(error){previewErrors.push({scope:'quantity input',message:String(error),stack:error.stack})}};
 this.events[name]=wrapped;this.el.addEventListener(event,wrapped);
};
const params=new URLSearchParams(location.search),state=params.get('state')||'normal';
window.compactState={state,kind:'production_component_browser_preview',account:'explicit offline fixture',orders_created:0};
window.compactProduct={sku:'compact_fixture_red_ticket',title:'红色抽奖券',amount_fen:120,u_coin_price:1200,u_coin_per_yuan:1000,max_quantity:100,enabled:true,owned:0,icon:'custom_game/lottery_handoff_v1/ticket_illustrated.png',description:'获得1张特殊抽奖券，用于本项目特殊奖池。奖池道具及概率以游戏内公示为准。',reward_lines:[{kind:'archive_item',id:'fixture_red_ticket',quantity:1,label:'特殊抽奖券'}]};
if(state==='limit1'){compactProduct.max_quantity=1;compactProduct.title='限购外观礼包';compactProduct.description='每个账号限购一份。此处仅验证服务端返回的数量上限。';}
if(state==='long')compactProduct.description=Array.from({length:20},(_,i)=>'奖励说明第'+(i+1)+'行：保留完整效果文本，超出区域可以滚动查看。').join('\n');
function compactRequest(action){return [...previewCalls].reverse().find(c=>c.name==='survival_payment_request'&&c.payload.action===action)}
window.compactRespond=function(data){const request=[...previewCalls].reverse().find(c=>c.name==='survival_payment_request');emit('survival_payment_result',{request_id:request&&request.payload.request_id,action:request&&request.payload.action,...data});syncLayout()};
window.compactCatalog=function(){compactRespond({ok:true,action:'catalog',products:[compactProduct],wechat:1,alipay:1,game_values:{initial_wood:80},wallet:{wood:110000000}})};
window.compactOrder=function(orderState='pending'){
 const q=cfg.SurvivalPayments.Inspect().quantity||1;
 compactRespond({ok:true,action:'create',sku:compactProduct.sku,title:compactProduct.title,description:compactProduct.description,quantity:q,unit_amount_fen:120,unit_u_coin_price:1200,amount_fen:120*q,u_coin_price:1200*q,u_coin_per_yuan:1000,provider:'wechat',state:orderState,order_id:'WX'+'1'.repeat(30),checkout_mode:'qr',checkout_url:'https://pay.xiaofengnet.com/checkout?order=WX'+'1'.repeat(30)+'&token='+'a'.repeat(64),qr_matrix:Array.from({length:29},(_,y)=>Array.from({length:29},(_,x)=>(x<7&&y<7||x>21&&y<7||x<7&&y>21||(x*3+y*5)%7<3)?'1':'0').join('')).join('|'),reward_lines:[{kind:'archive_item',id:'fixture_red_ticket',quantity:q,label:'特殊抽奖券'}]});
};
window.compactReady=previewLoad().then(async()=>{
 cfg.SurvivalPayments.Checkout(compactProduct.sku);compactCatalog();
 if(state==='qr'||state==='receipt'){PaymentBuy();compactOrder(state==='qr'?'pending':'delivered');}
 await document.fonts.ready;await Promise.all([...document.images].map(i=>i.decode().catch(()=>false)));syncLayout();return true;
}).catch(error=>{previewErrors.push({scope:'compact fixture',message:String(error),stack:error.stack});return false});
`;
fs.writeFileSync(path.join(out,'state.js'),state);
const assembly=JSON.parse(fs.readFileSync(path.join(out,'assembly.json'),'utf8'));
assembly.layouts=layouts.map(({rel,scripts,styles})=>({rel,scripts,styles}));
assembly.validation_scope='Actual production payment component in browser adapter; account, catalog, quantity limits and QR are explicit local fixtures. No real orders, account, server, gateway, or native-game verification.';
assembly.previewHarness=['tools/compact_checkout_20261015/preview.cjs','tools/archive_v10/adapter.js'].map(file=>({path:file,sha256:crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex')}));
assembly.adapterCorrections=['TextEntry.text reads DOM input value','TextEntry enabled mirrors disabled input state','ontextentrychange uses DOM input; enter submits only on Enter'];
fs.writeFileSync(path.join(out,'assembly.json'),JSON.stringify(assembly,null,2));
console.log('COMPACT_CHECKOUT_PREVIEW '+out);
