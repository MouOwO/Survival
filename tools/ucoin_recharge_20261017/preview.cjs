'use strict';
// Assemble the real checkout component with local, explicit recharge fixtures.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),{spawnSync}=require('node:child_process');
const out='design_refs/ucoin_recharge_20261017/preview';
const built=spawnSync(process.execPath,['tools/menus_v10/preview.cjs','--out',out],{encoding:'utf8',windowsHide:true});
if(built.status!==0)throw Error(built.stdout+built.stderr);
const entry=path.join(out,'index.html');let html=fs.readFileSync(entry,'utf8');
const mark='window.PREVIEW_LAYOUTS=',next=';window.PREVIEW_SOURCES=',start=html.indexOf(mark)+mark.length,end=html.indexOf(next,start);
const allLayouts=JSON.parse(html.slice(start,end)),layouts=allLayouts.filter(l=>l.rel==='layout/custom_game/payment_test.xml');
if(layouts.length!==1)throw Error('Production checkout layout missing');
const cssPath=path.join(out,'style.css'),allCss=fs.readFileSync(cssPath,'utf8'),following=allLayouts[1]&&allLayouts[1].styles[0];
if(following){let cursor=0;for(const rel of layouts[0].styles){const at=allCss.indexOf('/* '+rel+' */',cursor);if(at<0)throw Error('Missing CSS '+rel);cursor=at+rel.length+6;}const cut=allCss.indexOf('/* '+following+' */',cursor);if(cut<0)throw Error('Cannot isolate checkout CSS');fs.writeFileSync(cssPath,allCss.slice(0,cut));}
layouts[0].scripts=layouts[0].scripts.filter(p=>/\/(?:item_resources|reward_presentation|vip_badges|ui_registry|ui_components|ui_layers|commerce_components|payment_test)\.js$/.test(p));
html=html.slice(0,start)+JSON.stringify(layouts)+html.slice(end);
html=html.replace(/<script src="[^"]*tools\/menus_v10\/state\.js"><\/script>/,'<script src="state.js"></script>');
html=html.replace(/(<div id="PreviewCaption">)[\s\S]*?(<\/div>)/,'$1U币充值 · 生产 XML / JS / CSS 浏览器预览 · 本地样例，未连接账号、游戏或支付$2');
html=html.replace('</style>','input.panel{font-family:inherit;outline:none;border-radius:0;padding:0;text-align:center}.PreviewContext input{pointer-events:auto}</style>');
fs.writeFileSync(entry,html);
const state=String.raw`'use strict';
// These corrections bridge Panorama TextEntry to real browser input events only.
const textDescriptor=Object.getOwnPropertyDescriptor(Panel.prototype,'text');
Object.defineProperty(Panel.prototype,'text',{configurable:true,get(){return this.type==='TextEntry'?this.el.value:textDescriptor.get.call(this)},set(v){textDescriptor.set.call(this,v)}});
const enabledDescriptor=Object.getOwnPropertyDescriptor(Panel.prototype,'enabled');
Object.defineProperty(Panel.prototype,'enabled',{configurable:true,get(){return enabledDescriptor.get.call(this)},set(v){enabledDescriptor.set.call(this,v);if(this.type==='TextEntry')this.el.disabled=v===false;}});
const nativeSetEvent=Panel.prototype.SetPanelEvent;
Panel.prototype.SetPanelEvent=function(name,fn){
 if(this.type!=='TextEntry'||name!=='ontextentrychange')return nativeSetEvent.call(this,name,fn);
 const old=this.events[name];if(old)this.el.removeEventListener('input',old);
 const wrapped=()=>{try{fn();syncLayout()}catch(error){previewErrors.push({scope:'quantity input',message:String(error),stack:error.stack})}};
 this.events[name]=wrapped;this.el.addEventListener('input',wrapped);
};
window.rechargePreview={kind:'production_component_browser_preview',account:'explicit local fixture',real_orders_created:0};
window.rechargeProduct={sku:'u_coin_recharge',title:'U币充值',product_type:'recharge',purchase_method:'cash',amount_fen:100,unit_amount_fen:100,max_quantity:999999,recharge_u_coin_per_unit:100,enabled:1,owned:0,icon:'s2r://panorama/images/custom_game/shop_v10_v1/balance_u_icon_png.vtex',description:'每份1元，到账100U币。',reward_lines:[{kind:'wallet',id:'u_coin',quantity:100,label:'U币'}]};
window.rechargeRespond=function(data){const request=[...previewCalls].reverse().find(c=>c.name==='survival_payment_request');emit('survival_payment_result',{request_id:request&&request.payload.request_id,action:request&&request.payload.action,...data});syncLayout()};
window.rechargeFixtureOrder=function(state='pending'){
 const q=cfg.SurvivalPayments.Inspect().quantity||1,request=[...previewCalls].reverse().find(c=>c.name==='survival_payment_request'),provider=request.payload.provider||'wechat';
 rechargeRespond({...rechargeProduct,ok:1,quantity:q,amount_fen:100*q,provider,state,order_id:(provider==='alipay'?'AL':'WX')+'1'.repeat(30),checkout_mode:'qr',checkout_url:'https://pay.xiaofengnet.com/checkout'+(provider==='alipay'?'/alipay':'')+'?order='+(provider==='alipay'?'AL':'WX')+'1'.repeat(30)+'&token='+'a'.repeat(64),qr_matrix:Array.from({length:29},(_,y)=>Array.from({length:29},(_,x)=>(x<7&&y<7||x>21&&y<7||x<7&&y>21||(x*3+y*5)%7<3)?'1':'0').join('')).join('|'),reward_lines:[{kind:'wallet',id:'u_coin',quantity:100*q,label:'U币'}]});
};
window.rechargeReady=previewLoad().then(async()=>{
 cfg.SurvivalPayments.Checkout(rechargeProduct.sku);
 rechargeRespond({ok:1,action:'catalog',products:[rechargeProduct],wechat:1,alipay:1});
 await document.fonts.ready;await Promise.all([...document.images].map(i=>i.decode().catch(()=>false)));syncLayout();return true;
}).catch(error=>{previewErrors.push({scope:'recharge fixture',message:String(error),stack:error.stack});return false});
`;
fs.writeFileSync(path.join(out,'state.js'),state);
const assembly=JSON.parse(fs.readFileSync(path.join(out,'assembly.json'),'utf8'));
assembly.layouts=layouts.map(({rel,scripts,styles})=>({rel,scripts,styles}));
assembly.validation_scope='Actual production checkout XML/JS/CSS assembled in a browser adapter; catalog, account and QR/order snapshots are explicit offline fixtures. Not a native-game screenshot. No real orders or external services.';
assembly.previewHarness=['tools/ucoin_recharge_20261017/preview.cjs','tools/archive_v10/adapter.js'].map(file=>({path:file,sha256:crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex')}));
fs.writeFileSync(path.join(out,'assembly.json'),JSON.stringify(assembly,null,2));
console.log('UCOIN_RECHARGE_PREVIEW '+out);
