'use strict';
// Independent Chrome component QA. Every case records failure and continues.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const {browser,sleep}=require('../archive_official_variants_20261019/browser.cjs');
const {seedLotteryLayout}=require('./lottery_fixture.cjs');
const root=path.resolve(__dirname,'../..'),base=path.join(root,'output/ui_qa_20261025/browser');
const arg=(n,d)=>{const i=process.argv.indexOf(n);return i<0?d:process.argv[i+1];};
const label=arg('--label','baseline'),discover=process.argv.includes('--discover');
if(!/^[a-z0-9_-]{1,40}$/.test(label))throw Error('Invalid label');
const folder=path.join(base,label),preview=path.join(folder,'preview/index.html');
const snapshot=JSON.parse(fs.readFileSync(path.join(folder,'preview/snapshot.json'),'utf8'));
const digestFile=file=>crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const reportName=arg('--report',discover?'discovery':'browser_matrix');if(!/^[a-z0-9_-]{1,50}$/.test(reportName))throw Error('Invalid report name');
const filename=path.join(folder,reportName+'.json');
const result={schema:1,label,at:new Date().toISOString(),scope:'real_production_components_in_Chrome_synthetic_data_not_native_Dota',
 sourceDigest:snapshot.sourceDigest,helpers:snapshot.helpers,sourceGraph:snapshot.sourceAssembly.sourceGraph,
 fixtureProvenance:{runnerSha256:digestFile(__filename),previewIndexSha256:digestFile(preview),styleSha256:digestFile(path.join(folder,'preview/style.css')),nativeIconManifestSha256:fs.existsSync(path.join(folder,'native_icons.json'))?digestFile(path.join(folder,'native_icons.json')):null,extensions:snapshot.explicitFixtureExtensions},
 publicNetworkAllowed:false,realOrdersOrAccounts:false,nativeGames:0,cases:[],networkAttempts:[],passed:false,
 limitations:snapshot.limitations};
const menus=['archive','shop','commerce','lottery','daily','treasure','collection_friend','collection_ex','collection_beast','vip'];
const selectors={archive:'#ArchiveWindow',shop:'#CustomShopWindow',commerce:'.BLMarketWindow,.CommercePurple',lottery:'#LotteryMainCanvas',daily:'#DailyWindow',treasure:'#TreasureWindow',collection_friend:'#CollectionWindow',collection_ex:'#CollectionWindow',collection_beast:'#CollectionWindow',vip:'#VIPWindow',wallet_checkout:'.MenuV10Exchange',paid_checkout:'#PaymentDialog'};
function save(){fs.writeFileSync(filename,JSON.stringify(result,null,2));}
process.on('beforeExit',()=>{if(!result.finishedAt&&!result.infrastructureError){result.infrastructureError='runner_exited_before_completion_at_'+String(result.stage);save();console.error(result.infrastructureError);process.exitCode=1;}});
function inspection(page){return `(()=>{
 const shown=e=>{if(!e)return false;let p=e;while(p){const s=getComputedStyle(p);if(s.display==='none'||s.visibility==='hidden'||s.opacity==='0'||p.hidden)return false;p=p.parentElement;}const r=e.getBoundingClientRect();return r.width>0&&r.height>0;};
 const box=e=>e?e.getBoundingClientRect().toJSON():null;
 const matches=[...document.querySelectorAll(${JSON.stringify(selectors[page])})];
 let target=matches.find(shown)||matches[0];
 if(${JSON.stringify(page)}==='commerce'&&!shown(target)){const p=cfg.SurvivalCommerceView.Inspect().path[0];if(p&&p.classes)target=[...document.querySelectorAll('.panel')].find(e=>p.classes.every(c=>e.classList.contains(c))&&shown(e))||target;}
 const visibleImages=[...document.images].filter(e=>shown(e)&&e.src);
 const missingImages=visibleImages.filter(e=>!e.complete||!e.naturalWidth).map(e=>({id:e.id,src:e.src,bounds:box(e)}));
 const controls=[...document.querySelectorAll('.button,.PurpleTab,.PaymentAction,.CommerceConfirmBuy,.CommerceConfirmBack')].filter(shown).slice(0,120).map(e=>{const r=box(e),x=r.x+r.width/2,y=r.y+r.height/2,top=document.elementFromPoint(x,y);return {id:e.id,classes:e.className,text:e.textContent.slice(0,80),bounds:r,inViewport:x>=0&&x<innerWidth&&y>=0&&y<innerHeight,centerHit:!!top&&(top===e||e.contains(top)),top:top?{id:top.id,classes:top.className}:null};});
 const tips=[...document.querySelectorAll('#ArchiveTooltip,#ShopEntryTooltip,.RCPurpleDetail,#DailyTooltip,#TreasureTooltip,#LotteryItemTooltip,#LotteryGW2Tooltip,#VIPTooltip,.ArchiveSharedTooltipHost')].filter(shown).map(e=>({id:e.id,classes:e.className,bounds:box(e)}));
 const panelTree=function all(p){return [p,...p.Children().flatMap(all)];}(root),labelChildMismatches=panelTree.filter(p=>p.type==='Label'&&shown(p.el)&&p.Children().some(child=>!p.el.contains(child.el))).slice(0,20).map(p=>({id:p.id,text:p.text.slice(0,60)}));
 return {ready:previewState.ready,failure:previewState.failure||null,windowShown:shown(target),window:box(target),errors:previewErrors,missingImages,visibleImageCount:visibleImages.length,
 font:cfg.SurvivalArchiveFontV36&&cfg.SurvivalArchiveFontV36.Inspect?cfg.SurvivalArchiveFontV36.Inspect():null,fontBridge:window.__uiqaFontBridge===true,fontImageEvents:window.__uiqaImageEvents||[],
 vipStatus:cfg.SurvivalVIPStatus&&cfg.SurvivalVIPStatus.Inspect?cfg.SurvivalVIPStatus.Inspect():null,
 controls,tips,labelChildMismatches,nativeTooltipText:window.previewNativeTooltip||null,layer:cfg.SurvivalUILayers?cfg.SurvivalUILayers.Top():null,
 payment:cfg.SurvivalPayments&&cfg.SurvivalPayments.Inspect?cfg.SurvivalPayments.Inspect():null,
 calls:previewCalls.map(c=>({name:c.name,method:c.method,payload:c.payload})),
 scriptResults:previewScriptResults,geometryModels:window.previewGeometryModels||[]};
})()`;}
let active;
const run=(fn,...args)=>active.run('('+fn.toString()+')('+args.map(x=>JSON.stringify(x)).join(',')+')');
async function clickControl(selector){
 const point=await run(selector=>{const e=[...document.querySelectorAll(selector)].find(e=>{const r=e.getBoundingClientRect();return r.width>0&&r.height>0&&getComputedStyle(e).display!=='none';});if(!e)return null;const r=e.getBoundingClientRect(),x=r.x+r.width/2,y=r.y+r.height/2,hit=document.elementFromPoint(x,y);return {x,y,hit:!!hit&&(hit===e||e.contains(hit)),top:hit?.id||hit?.className,selector};},selector);
 test(point,'visible action missing: '+selector);test(point.hit,'action center is obstructed: '+selector+' by '+point.top);
 await active.click(point.x,point.y);await active.run('syncLayout();true');return point;
}
async function walletCancel(){
 const before=await run(()=>previewCalls.filter(c=>c.name==='survival_commerce_request'&&c.payload.action==='purchase').length);
 const cancelPoint=await clickControl('.CommerceConfirmBack');
 const cancelled=await run(()=>({purchases:previewCalls.filter(c=>c.name==='survival_commerce_request'&&c.payload.action==='purchase').length,top:cfg.SurvivalUILayers.Top()}));
 test(cancelled.purchases===before,'wallet cancel submitted a purchase');test(cancelled.top==='commerce','wallet cancel did not return to storefront');
 await run(()=>{const balances=cfg.SurvivalCommerceWallet.GetCatalog().balances;const p=cfg.SurvivalCommerceWallet.GetCatalog().products.find(p=>p.enabled!==false&&Number(p.price)<=Number(balances[p.currency]||0));window.__uiqaWallet=p;cfg.SurvivalCommerceWallet.Checkout(p.sku);syncLayout();});
 return {cancelPoint,cancelled,reopened:true,kind:'physical_cancel_no_purchase'};
}
async function walletCloseSuccess(){
 await run(()=>{const api=cfg.SurvivalCommerceWallet,catalog=structuredClone(api.GetCatalog());catalog.balances={u_coin:20000,shop_points:20000,shop_gold:0};api.Refresh();const request=previewCalls.filter(c=>c.name==='survival_commerce_request'&&c.payload.action==='catalog').at(-1).payload,base={ok:true,action:'catalog',request_id:request.request_id};emit('survival_commerce_result',{...base,part:'begin',categories:catalog.categories,balances:catalog.balances,count:catalog.products.length});catalog.products.forEach((product,i)=>emit('survival_commerce_result',{...base,part:'product',index:i+1,product}));emit('survival_commerce_result',{...base,part:'end'});const product=catalog.products.find(p=>p.enabled!==false&&Number(p.price)<=Number(catalog.balances[p.currency]||0));api.Checkout(product.sku);syncLayout();});
 const seed=await run(()=>{const c=cfg.SurvivalCommerceWallet.GetCatalog(),p=c.products.find(p=>p.enabled!==false&&Number(p.price)<=Number(c.balances[p.currency]||0));window.__uiqaWallet=p;window.__uiqaRecoveryCatalog=structuredClone(c);return {sku:p.sku,currency:p.currency,price:Number(p.price),balance:Number(c.balances[p.currency]),before:previewCalls.filter(c=>c.name==='survival_commerce_request'&&c.payload.action==='purchase').length,catalogRequestIds:previewCalls.filter(c=>c.name==='survival_commerce_request'&&c.payload.action==='catalog').map(c=>c.payload.request_id)};});
 const buyPoint=await clickControl('.CommerceConfirmBuy');
 await run(()=>{const p=root.FindChildrenWithClassTraverse('CommerceConfirmBuy')[0];if(p?.events.onactivate)p.events.onactivate();});
 const pending=await run(()=>{const calls=previewCalls.filter(c=>c.name==='survival_commerce_request'&&c.payload.action==='purchase');return {count:calls.length,request:calls.at(-1)?.payload};});
 test(pending.count===seed.before+1,'double confirm submitted more than one wallet purchase');
 const closePoint=await clickControl('.CommerceConfirmBack');
 const reply={ok:true,action:'purchase',request_id:pending.request.request_id,currency:seed.currency,balance:seed.balance-seed.price,terminal:true};
 await run(reply=>{emit('survival_commerce_result',reply);emit('survival_commerce_result',reply);syncLayout();},reply);
 const readClosed=()=>run(()=>({top:cfg.SurvivalUILayers.Top(),balance:cfg.SurvivalCommerceWallet.GetCatalog().balances[__uiqaWallet.currency],pending:cfg.SurvivalCommercePending,purchases:previewCalls.filter(c=>c.name==='survival_commerce_request'&&c.payload.action==='purchase').length}));
 const immediate=await readClosed();
 test(immediate.top==='commerce'&&!immediate.pending&&immediate.purchases===seed.before+1,'late wallet result reopened or duplicated the purchase');
 // Reopening the storefront can invalidate the in-flight purchase generation.
 // Its success must not override newer authority. Answer the real recovery
 // catalogue requests instead of assuming one purchase reply settles the view.
 const answered=new Set(seed.catalogRequestIds),recoveryReplies=[];
 for(let i=0;i<60;i++){
  await sleep(100);
  const request=await run(ids=>previewCalls.filter(c=>c.name==='survival_commerce_request'&&c.payload.action==='catalog'&&!ids.includes(c.payload.request_id)).map(c=>c.payload).at(0)||null,[...answered]);
  if(!request)continue;answered.add(request.request_id);
  await run((id,currency,balance)=>{const catalog=structuredClone(__uiqaRecoveryCatalog);catalog.balances[currency]=balance;const base={ok:true,action:'catalog',request_id:id};for(let replay=0;replay<2;replay++){emit('survival_commerce_result',{...base,part:'begin',categories:catalog.categories,balances:catalog.balances,count:catalog.products.length});catalog.products.forEach((product,i)=>emit('survival_commerce_result',{...base,part:'product',index:i+1,product}));emit('survival_commerce_result',{...base,part:'end'});}syncLayout();},request.request_id,seed.currency,seed.balance-seed.price);
  const observed=await readClosed();recoveryReplies.push({request_id:request.request_id,balance:observed.balance,top:observed.top});
  if(observed.balance===seed.balance-seed.price)break;
 }
 test(recoveryReplies.length>0,'wallet never requested its authoritative recovery catalogue');
 const closed=await readClosed();
 test(closed.top==='commerce','background wallet success reopened exchange');test(closed.balance===seed.balance-seed.price,'wallet success/replay produced wrong balance');test(!closed.pending,'wallet success left uncertain purchase token');test(closed.purchases===seed.before+1,'wallet replay created purchase');
 await run(()=>{cfg.SurvivalCommerceWallet.Checkout(__uiqaWallet.sku);syncLayout();});
 return {seed,buyPoint,closePoint,pending,immediate,recoveryReplies,closed,reopened:true,kind:'physical_wallet_confirm_double_click_close_synthetic_success_and_catalog_replay_reopen'};
}
async function cashPending(){
 const buyPoint=await clickControl('#PaymentBuy');
 await run(()=>PaymentBuy());
 const state=await run(()=>{const calls=previewCalls.filter(c=>c.name==='survival_payment_request'&&c.payload.action==='create'),request=calls.at(-1)?.payload,p=cfg.SurvivalPayments.GetCatalog().products.find(p=>p.sku===request?.sku);return {count:calls.length,request,product:p};});
 test(state.count===1&&state.request&&state.product,'cash double confirm did not produce exactly one synthetic create');
 const p=state.product,q=state.request.quantity||1;
 const order={...p,ok:true,action:'create',request_id:state.request.request_id,sku:p.sku,order_id:'WX'+'7'.repeat(30),state:'pending',provider:'wechat',quantity:q,unit_amount_fen:p.amount_fen,amount_fen:p.amount_fen*q,unit_u_coin_price:p.u_coin_price,u_coin_price:p.u_coin_price? p.u_coin_price*q:undefined,checkout_mode:'qr',qr_matrix:Array.from({length:29},(_,y)=>Array.from({length:29},(_,x)=>(x+y)%3?'0':'1').join('')).join('|')};
 await run(order=>{window.__uiqaCashOrder=order;emit('survival_payment_result',order);syncLayout();},order);
 test(await run(()=>cfg.SurvivalPayments.Inspect().pending===''),'synthetic create response was not consumed');
 return {buyPoint,sku:p.sku,request:state.request,kind:'unpayable_synthetic_order_no_gateway'};
}
async function cashCancel(){
 const pending=await cashPending();
 const cancelPoint=await clickControl('#PaymentCancel');
 const request=await run(()=>previewCalls.filter(c=>c.name==='survival_payment_request'&&c.payload.action==='cancel').at(-1)?.payload);
 test(request,'cash cancel did not send one synthetic cancel intention');
 await run(request=>{emit('survival_payment_result',{...__uiqaCashOrder,action:'cancel',request_id:request.request_id,state:'closed'});syncLayout();},request);
 test(await run(()=>cfg.SurvivalPayments.Inspect().pending===''),'cancel reply did not retire active request');
 return {pending,cancelPoint,cancelled:true};
}
async function cashCloseSuccess(){
 const pending=await cashPending();
 await run(()=>{if(cfg.SurvivalPayments.Inspect().opened)PaymentToggle();syncLayout();});
 test(await run(()=>!cfg.SurvivalPayments.Inspect().opened),'cash close did not close');
 let request;
 for(let i=0;i<32;i++){request=await run(()=>previewCalls.filter(c=>c.name==='survival_payment_request'&&c.payload.action==='status').at(-1)?.payload);if(request)break;await sleep(250);}
 test(request,'closed cash panel stopped pending-order reconciliation');
 const walletsBefore=await run(()=>previewCalls.filter(c=>c.name==='survival_commerce_request'&&c.payload.action==='catalog').length);
 await run(request=>{const reply={...__uiqaCashOrder,action:'status',request_id:request.request_id,state:'delivered'};emit('survival_payment_result',reply);emit('survival_payment_result',reply);syncLayout();},request);
 await sleep(200);
 const delivered=await run(()=>({opened:cfg.SurvivalPayments.Inspect().opened,creates:previewCalls.filter(c=>c.name==='survival_payment_request'&&c.payload.action==='create').length,wallets:previewCalls.filter(c=>c.name==='survival_commerce_request'&&c.payload.action==='catalog').length}));
 test(!delivered.opened,'background cash delivery reopened checkout');test(delivered.creates===1,'cash delivery/replay created a second order');test(delivered.wallets===walletsBefore+1,'cash delivery did not request exactly one accepted wallet refresh');
 await run(()=>{cfg.SurvivalPayments.Checkout(__uiqaCashOrder.sku);syncLayout();});
 return {pending,statusRequest:request,delivered,reopened:true,kind:'physical_create_close_background_status_synthetic_delivery_replay_wallet_refresh'};
}
async function navigation(entry){
 await run(()=>{const wallet=cfg.SurvivalCommerceWallet,payments=cfg.SurvivalPayments;archive();shop();commerce();daily();treasure();lottery();cfg.SurvivalCommerceWallet=wallet;cfg.SurvivalPayments=payments;window.__uiqaRealWallet=wallet;closeWindows();walletCheckout();syncLayout();});
 test(await run(()=>cfg.SurvivalCommerceWallet===__uiqaRealWallet&&!/previewCalls\.push/.test(cfg.SurvivalCommerceWallet.Checkout.toString())),'navigation fixture replaced production wallet API');
 const mutating=await run(()=>previewCalls.filter(c=>/purchase|draw|claim|promote|equip/.test(c.payload?.action||c.name||'')).length);
 const transitions=[];
 entry.navigationProgress=[];
 for(const target of ['treasure','archive','lottery','commerce','daily_rewards']){
  const attempt=await run(()=>{const c=cfg.SurvivalCommerceWallet.GetCatalog(),p=c.products.find(p=>p.enabled!==false&&Number(p.price)<=Number(c.balances[p.currency]||0)),before=cfg.SurvivalUILayers.Top(),opened=cfg.SurvivalCommerceWallet.Checkout(p.sku);syncLayout();return {sku:p.sku,before,opened,after:cfg.SurvivalUILayers.Top(),pending:cfg.SurvivalCommercePending,exchange:[...document.querySelectorAll('.MenuV10Exchange')].map(e=>({rect:e.getBoundingClientRect().toJSON(),parents:function(){const rows=[];for(let p=e;p;p=p.parentElement){const s=getComputedStyle(p);rows.push({id:p.id,classes:p.className,display:s.display,opacity:s.opacity,visibility:s.visibility});}return rows;}()}))};});
  entry.navigationProgress.push({target,attempt});
  const point=await clickControl('[id$="_Top_'+target+'"]');
  const actual=await run(()=>({top:cfg.SurvivalUILayers.Top(),mutating:previewCalls.filter(c=>/purchase|draw|claim|promote|equip/.test(c.payload?.action||c.name||'')).length,errors:previewErrors}));
  test(actual.top===target,'physical navigation selected wrong layer: '+target);test(actual.mutating===mutating,'navigation sent a transaction');test(actual.errors.length===0,'navigation caused component error');
  const shot=path.join(folder,'screenshots',entry.width+'x'+entry.height+'_navigation_'+target+'.png');await active.shot(shot,{x:0,y:0,width:entry.width,height:entry.height});
  transitions.push({target,point,actual,screenshot:path.relative(root,shot).replaceAll('\\','/')});
 }
 await run(()=>{const c=cfg.SurvivalCommerceWallet.GetCatalog(),p=c.products.find(p=>p.enabled!==false&&Number(p.price)<=Number(c.balances[p.currency]||0));cfg.SurvivalCommerceWallet.Checkout(p.sku);syncLayout();});
 return {transitions,kind:'physical_shared_menu_navigation_synthetic_read_snapshots_no_transactions'};
}
async function physicalHover(page){
 const selector={archive:'.ArchiveCard',shop:'.ShopShelfSlot',commerce:'.CJProduct',lottery:'.LotteryDetailRow',daily:'.DailyGW2Day,.DailyReward',treasure:'.TreasureCard',collection_friend:'.CollectionGW2Slot',collection_ex:'.CollectionGW2Slot',collection_beast:'.CollectionGW2Slot'}[page];
 if(!selector)return {kind:'passive_status_no_modal_hover'};
 const source=await run((selector,page)=>{const values=[...document.querySelectorAll(selector)].filter(e=>{const r=e.getBoundingClientRect();return r.width>0&&r.height>0&&r.x>=0&&r.right<=innerWidth&&r.y>=0&&r.bottom<=innerHeight;});let e=values[page==='archive'?Math.min(3,values.length-1):0];if(!e)return null;function all(p){return [p,...p.Children().flatMap(all)];}const panels=all(root),owner=panels.find(p=>p.el===e),bound=owner&&(owner.events.onmouseover?owner:all(owner).find(p=>p.events.onmouseover));if(bound)e=bound.el;const r=e.getBoundingClientRect(),x=r.x+r.width/2,y=r.y+r.height/2,top=document.elementFromPoint(x,y);return {x,y,rect:r.toJSON(),selector,handlerBound:!!bound,hit:!!top&&(top===e||e.contains(top)),top:top?.id||top?.className};},selector,page);
 test(source,'visible hover source missing: '+page);test(source.hit,'hover source center obstructed: '+page+' by '+source.top);
 source.attempts=[];
 const r=source.rect,points=[[source.x,source.y],[r.x+5,r.y+5],[r.right-5,r.y+5],[r.x+5,r.bottom-5],[r.right-5,r.bottom-5]];
 for(const [x,y]of points){await run(()=>{window.previewNativeTooltip=null;});await active.move(2,2);await active.move(x,y);await sleep(250);await active.run('syncLayout();true');const m=await active.run(inspection(page));source.attempts.push({x,y,tooltips:m.tips.map(t=>({id:t.id,bounds:t.bounds})),nativeTooltipText:m.nativeTooltipText});if(m.tips.length||page==='treasure'&&m.nativeTooltipText){source.x=x;source.y=y;break;}}
 return source;
}
async function navigate(page,state){
 const fixturePage=page.startsWith('collection_')?'archive':page,category=page.startsWith('collection_')?page.slice('collection_'.length):null;
 await active.go(preview,'?page='+fixturePage+'&state='+state+(category?'&category='+category:'')+(page==='paid_checkout'?'&cash_fixture=1':''));
 const ready=await active.run('previewReady');
 await active.run('syncLayout();true');
 return ready;
}
function test(value,message){if(!value)throw Error(message);}
async function backgroundAudit(){
 return run(async()=>{const shown=e=>{for(let p=e;p;p=p.parentElement){const s=getComputedStyle(p);if(s.display==='none'||s.visibility==='hidden'||s.opacity==='0'||p.hidden)return false;}const r=e.getBoundingClientRect();return r.width>0&&r.height>0;},urls=new Set();for(const e of document.querySelectorAll('.panel'))if(shown(e)){const s=getComputedStyle(e);for(const value of [s.backgroundImage,s.maskImage])for(const m of String(value).matchAll(/url\(["']?([^"')]+)["']?\)/g))urls.add(m[1]);}const decoded=await Promise.all([...urls].map(src=>new Promise(resolve=>{const image=new Image();image.onload=()=>resolve({src,ok:!!image.naturalWidth});image.onerror=()=>resolve({src,ok:false});image.src=src;})));return {count:decoded.length,missing:decoded.filter(x=>!x.ok),decoded:decoded.filter(x=>x.ok).map(x=>x.src)};});
}
async function one(name,page,state,size,action){
 const [width,height]=size,entry={name,page,fixturePage:page.startsWith('collection_')?'archive':page,state,width,height,passed:false,checks:[]};
 result.cases.push(entry);
 try{
  await active.viewport(width,height);
  const ready=await navigate(page,state);
  if(page==='lottery'&&['long','empty'].includes(state))entry.layoutFixture=await run(seedLotteryLayout,state);
  if(state==='hover')entry.physicalHover=await physicalHover(page);
  entry.metrics=await active.run(inspection(page));
  test(ready&&entry.metrics.ready,'component fixture did not become ready');entry.checks.push('fixture_ready');
  if(action)entry.actions=await action(entry);
  entry.metrics=await active.run(inspection(page));
  entry.metrics.backgrounds=await backgroundAudit();
  test(entry.metrics.errors.length===0,'browser component script errors');entry.checks.push('no_script_errors');
  test(entry.metrics.labelChildMismatches.length===0,'browser adapter detached Label child panels');entry.checks.push('native_label_child_panel_contract');
  if(entry.metrics.font){test(entry.metrics.fontBridge&&entry.metrics.font.pages.every(state=>state==='ready'),'font atlas PNGs did not actually decode in the task-owned DOM bridge');entry.checks.push('browser_font_atlas_images_loaded_not_native_event_proof');}
  if(page==='vip'){test(entry.metrics.vipStatus&&entry.metrics.vipStatus.known&&entry.metrics.vipStatus.level===5,'passive VIP status did not apply fixture');test(!entry.metrics.windowShown,'retired VIP window reopened');entry.checks.push('passive_vip_status_and_retired_modal');}
  else {test(entry.metrics.windowShown,'expected component is not visible');entry.checks.push('window_visible');}
  const r=entry.metrics.window;
  if(page!=='vip'){test(r.x>=-2&&r.y>=-2&&r.right<=width+2&&r.bottom<=height+2,'component window outside viewport');entry.checks.push('window_inside_viewport');}
  if(entry.metrics.missingImages.length||entry.metrics.backgrounds.missing.length){entry.assetStatus='MISSING_BROWSER_EXPORT_OR_SOURCE';entry.assetFailures=entry.metrics.missingImages.length+entry.metrics.backgrounds.missing.length;}else entry.assetStatus='VISIBLE_IMAGES_AND_BACKGROUNDS_DECODED';
  for(const t of entry.metrics.tips){const r=t.bounds;test(r.x>=-2&&r.y>=-2&&r.right<=width+2&&r.bottom<=height+2,'visible tooltip outside viewport');}
  if(state==='hover'&&page!=='vip'){entry.hoverTooltipCount=entry.metrics.tips.length;if(page==='treasure'){test(entry.metrics.nativeTooltipText,'physical hover did not dispatch the native text tooltip');entry.checks.push('native_tooltip_API_capture_not_native_pixels');}else{test(entry.hoverTooltipCount>0,'physical hover did not reveal a custom tooltip');entry.checks.push('physical_hover_revealed_tooltip');}}
  entry.checks.push('visible_tooltips_inside_viewport');entry.passed=true;
 }catch(error){entry.error=String(error.message||error);try{entry.metrics=await active.run(inspection(page));}catch(_){} }
 try{const shot=path.join(folder,'screenshots',width+'x'+height+'_'+name+'.png');await active.shot(shot,{x:0,y:0,width,height});entry.screenshot=path.relative(root,shot).replaceAll('\\','/');}catch(error){entry.screenshotError=String(error.message||error);entry.passed=false;}
 const attempts=active.events.filter(e=>e.method==='Network.requestWillBeSent'&&/^https?:|^wss?:/.test(e.params.request.url)).map(e=>({url:e.params.request.url.split('?')[0],method:e.params.request.method}));
 if(attempts.length){entry.blockedNetworkAttempts=attempts;entry.passed=false;entry.error='component attempted forbidden network';result.networkAttempts.push(...attempts);}
 active.events.length=0;save();
 console.log(JSON.stringify({case:name,size:width+'x'+height,passed:entry.passed,assets:entry.assetStatus||'NOT_CHECKED',error:entry.error||null}));
}
async function initialize(){
 result.stage='launch_isolated_chrome';
 active=await browser({output:path.join(base,'chrome'),width:1600,height:900});
 result.stage='enable_page_network_inspection';
 await active.call('Network.enable');
 result.stage='block_page_external_network';
 await active.call('Network.setBlockedURLs',{urls:['http://*','https://*','ws://*','wss://*']});
}
async function main(){
 await initialize();
 try{
  const sizeArg=arg('--size',null),flowOnly=process.argv.includes('--flows-only'),navOnly=process.argv.includes('--navigation-only'),hoverOnly=process.argv.includes('--hover-only');
  const selectedPages=arg('--pages',null)?.split(',')||menus;test(selectedPages.every(p=>menus.includes(p)),'Invalid page selection');
  const sizes=sizeArg?[sizeArg.split('x').map(Number)]:discover?[[1600,900]]:[[1280,720],[1600,900],[1920,1080],[2560,1440]];
  test(sizes.every(s=>s.length===2&&s.every(v=>Number.isInteger(v)&&v>=600&&v<=4096)),'Invalid viewport');
  for(const size of sizes){
   result.stage='cases';
   if(!flowOnly&&!navOnly){
    for(const page of selectedPages)for(const state of (hoverOnly?['hover']:discover?['normal']:['normal','hover','long','empty']))await one(page+'_'+state,page,state,size);
    if(!hoverOnly)
    for(const page of ['wallet_checkout','paid_checkout'])for(const state of (discover?['normal']:page==='wallet_checkout'?['normal','disabled','pending','receipt']:['normal','disabled']))await one(page+'_'+state,page,state,size);
   }
   if(!discover&&!hoverOnly&&!navOnly){
    await one('wallet_cancel_reopen','wallet_checkout','normal',size,walletCancel);
    await one('wallet_closed_success_replay','wallet_checkout','normal',size,walletCloseSuccess);
    await one('cash_confirm_cancel','paid_checkout','normal',size,cashCancel);
    await one('cash_closed_success_replay','paid_checkout','normal',size,cashCloseSuccess);
    await one('shared_menu_navigation','wallet_checkout','normal',size,navigation);
   }
   if(navOnly)await one('shared_menu_navigation','wallet_checkout','normal',size,navigation);
  }
  result.functionalPassed=result.cases.every(x=>x.passed);result.assetFailures=result.cases.reduce((n,c)=>n+(c.metrics?.missingImages?.length||0)+(c.metrics?.backgrounds?.missing?.length||0),0);result.passed=result.functionalPassed&&result.assetFailures===0;
  result.functionalFailures=result.cases.filter(x=>!x.passed).length;result.finishedAt=new Date().toISOString();save();
  console.log(JSON.stringify({status:'BROWSER_MATRIX_COMPLETE',label,discover,cases:result.cases.length,functionalFailures:result.functionalFailures,assetFailures:result.assetFailures,report:path.relative(root,filename)}));
 }finally{await active.close();}
}
main().catch(error=>{result.infrastructureError=String(error.message||error);save();console.error(JSON.stringify({error:result.infrastructureError,report:filename}));process.exitCode=1;});
