const assert=require('assert'),fs=require('fs'),path=require('path'),vm=require('vm');
const base=path.resolve(__dirname,'../../panorama/src');
const read=name=>fs.readFileSync(path.join(base,name),'utf8');
const xml=read('layout/custom_game/arcade_multiplayer_test.xml'),css=read('styles/custom_game/arcade_multiplayer_test.css');
const logic=read('scripts/custom_game/arcade_multiplayer_test.js'),layerSource=read('scripts/custom_game/ui_layers.js'),worldSource=read('scripts/custom_game/world_overlay_visibility.js');
const catalogSource=read('scripts/custom_game/arcade_shop_catalog.js'),catalogCfg={};
vm.runInNewContext(catalogSource,{GameUI:{CustomUIConfig(){return catalogCfg;}}});
const actualCatalog=JSON.parse(JSON.stringify(catalogCfg.SurvivalArcadeShopCatalog));
const clone=value=>JSON.parse(JSON.stringify(value));
let checks=0;
function check(value,message){assert.ok(value,message);checks++;}
const state={schema_version:1,enabled:1,session_only:1,online_players:2,capacity:4,host_player_id:0,http_phase:'unavailable',sequence:1};
function harness(options={}){
 const ids={},jobs=[],callbacks=[],network=[],messages=[],unsubscribed=[];let map={map_name:options.map||'template_map'},cachedReads=0,oldOpens=0;
 class Panel{
  constructor(id,parent){this.id=id;this.parent=parent;this.children=[];this.classes={};this.style={};this.visible=true;this.hittest=true;this.hittestchildren=true;this.enabled=true;this.handlers={};this.text='';this.live=true;this.scrolloffset_y=0;this.scrollResetCalls=0;if(parent)parent.children.push(this);if(id)ids[id]=this;}
  IsValid(){return this.live;}GetParent(){return this.parent;}GetChildCount(){return this.children.length;}Children(){return this.children;}
  FindChildTraverse(id){for(const c of this.children){if(c.id===id)return c;const found=c.FindChildTraverse(id);if(found)return found;}return null;}
  AddClass(c){this.classes[c]=true;}SetHasClass(c,v){this.classes[c]=v;}BHasClass(c){return !!this.classes[c];}
  SetPanelEvent(n,f){this.handlers[n]=f;}SetAcceptsFocus(){}SetFocus(){}
  ScrollToTop(){this.scrolloffset_y=0;this.scrollResetCalls++;}
  RemoveAndDeleteChildren(){for(const c of this.children)c.invalidate();this.children=[];}invalidate(){this.live=false;for(const c of this.children)c.invalidate();}
 }
 const native=new Panel('NativeHud',null),host=new Panel('CustomHudHost',native);native.style.zIndex='5';host.style.zIndex='8';
 const stack=[];let root;
 for(const tag of xml.matchAll(/<(\/?)(Panel|Button|Label)\b([^>]*?)(\/?)>/g)){
  if(tag[1]){stack.pop();continue;}
  const attrs=Object.fromEntries([...tag[3].matchAll(/(\w+)="([^"]*)"/g)].map(m=>[m[1],m[2]]));
  const item=new Panel(attrs.id||'',stack.at(-1)||host);if(!root)root=item;
  for(const c of (attrs.class||'').split(/\s+/).filter(Boolean))item.AddClass(c);
  for(const name of ['visible','hittest','hittestchildren'])if(attrs[name])item[name]=attrs[name]==='true';
  if(/visibility\s*:\s*collapse/.test(attrs.style||''))item.style.visibility='collapse';
  if(attrs.text)item.text=attrs.text;
  if(!tag[4])stack.push(item);
 }
 const originalOpen=function(){oldOpens++;return 'old-shop';};
 const cfg={SurvivalPayments:{Open:originalOpen}};
 if(!options.missingCatalog)cfg.SurvivalArcadeShopCatalog=options.catalog===undefined?clone(actualCatalog):options.catalog;
 const ctx={GameUI:{CustomUIConfig(){return cfg;}},Game:{GetMapInfo(){if(map instanceof Error)throw map;return map;}},Players:{GetPlayerName(id){return 'Host <name> '+id;}},
  GameEvents:{SendCustomGameEventToServer(...a){network.push(a);},SendEventClientSide(...a){network.push(a);}},
  CustomNetTables:{GetTableValue(){cachedReads++;return state;},SubscribeNetTableListener(name,fn){callbacks.push({name,fn});return callbacks.length;},UnsubscribeNetTableListener(id){unsubscribed.push(id);}},
  $:{Msg(m){messages.push(m);},GetContextPanel(){return root;},CreatePanel(type,parent,id){return new Panel(id,parent);},Schedule(seconds,fn){const job={fn,cancelled:false};jobs.push(job);return job;},CancelScheduled(job){job.cancelled=true;},RegisterEventHandler(){},DispatchEvent(...a){network.push(a);}}};
 function installLayers(){vm.runInNewContext(layerSource,ctx);vm.runInNewContext(worldSource,ctx);}
 if(options.layers!==false)installLayers();
 if(!options.skipScript)vm.runInNewContext(logic,ctx);
 const visible=node=>{for(let n=node;n;n=n.parent)if(!n.live||!n.visible||n.style.visibility==='collapse')return false;return true;};
 return {cfg,ctx,root,native,host,ids,network,messages,callbacks,unsubscribed,originalOpen,installLayers,
  reads(){return cachedReads;},oldOpens(){return oldOpens;},setMap(v){map=v;},
  monitor(){while(jobs.length){const j=jobs.shift();if(!j.cancelled){j.fn();return;}}throw new Error('no scheduled monitor');},
  visible(id){return visible(ids[id]);},receive(raw){callbacks.at(-1).fn('survival_arcade_multiplayer_test','state',raw);},
  click(id){ids[id].handlers.onactivate();},offer(id){const p=ids.ArcadeTestProducts.Children().find(x=>x.__shopOffer===id);assert.ok(p,'offer exists '+id);p.handlers.onactivate();},
  category(id){const p=ids.ArcadeTestCategories.Children().find(x=>x.__shopCategory===id);assert.ok(p);p.handlers.onactivate();},
  reload(){vm.runInNewContext(logic,ctx);},dispose(){cfg.SurvivalArcadeReadOnlyShop.Dispose();}};
}
for(const id of ['ArcadeTestCard','ArcadeTestPurchase']){
 const h=harness({skipScript:true});h.root.visible=true;
 check(h.ids[id].parent===h.root,'visual layer is independent from host root');check(!h.visible(id),'actual XML defaults collapse even without JS');
 check(new RegExp('\\.'+id+'\\s*\\{[^}]*visibility:\\s*collapse').test(css),'actual CSS also defaults collapse');
}
check(!/\.ArcadeTestContext\s*\{[^}]*(?:background|border|box-shadow)/.test(css),'host root draws no overlay');
check(xml.indexOf('arcade_shop_catalog.js')<xml.indexOf('arcade_multiplayer_test.js'),'generated catalog loads before controller');
check(xml.includes('ui_layers.js'),'real shared layer manager explicitly included');
check(/\.ArcadeTestProducts\s*\{[^}]*overflow:\s*squish scroll/.test(css),'complete product list scrolls vertically');
check(/\.ArcadeTestCategories\s*\{[^}]*overflow:\s*scroll squish/.test(css),'category tabs scroll horizontally');
let h=harness();h.root.visible=true;
check(!h.visible('ArcadeTestCard')&&!h.root.hittestchildren&&h.reads()===0,'no cached state activates UI or input');
check(h.cfg.SurvivalPayments.Open===h.originalOpen,'no server state leaves the original shop untouched');
for(const map of ['ws4_lobby','template_map_extra','maps/template_map','maps/template_map.vpk_extra','']){
 const t=harness();t.setMap({map_name:map});t.receive(state);t.root.visible=true;
 check(!t.visible('ArcadeTestCard')&&!t.root.hittestchildren&&t.cfg.SurvivalPayments.Open===t.originalOpen,'wrong map never mounts or redirects original shop');
}
for(const map of ['template_map','maps/template_map.vpk']){const t=harness({map});t.receive(state);check(t.visible('ArcadeTestCard'),'both exact native map names work only after fresh state');}
const bad=[null,{},Object.fromEntries(Object.entries(state).filter(([k])=>k!=='sequence')),{...state,sequence:0},{...state,sequence:2147483648},{...state,sequence:1.5},{...state,sequence:'1'},{...state,schema_version:2},{...state,enabled:0},{...state,session_only:false},{...state,online_players:0},{...state,online_players:5},{...state,capacity:2},{...state,host_player_id:-2},{...state,host_player_id:24},{...state,http_phase:'__proto__'},{...state,account_id:'fake'},Object.create(state)];
for(const raw of bad){const t=harness();t.receive(state);t.click('ArcadeTestPurchaseOpen');t.receive(raw);check(!t.visible('ArcadeTestCard')&&!t.visible('ArcadeTestPurchase')&&t.cfg.SurvivalUILayers.Top()===null&&t.cfg.SurvivalPayments.Open===t.originalOpen,'invalid state hides and releases modal and original menu hook');}
h.receive(state);
check(h.ids.ArcadeTestPlayers.text==='在线：2 / 4'&&h.ids.ArcadeTestHTTP.text==='HTTP：当前不可用','real count and unavailable HTTP remain honest');
h.receive({...state,host_player_id:-1});check(h.ids.ArcadeTestHost.text==='房主：尚未识别','unknown host is not invented');
h.click('ArcadeTestToggle');check(!h.visible('ArcadeTestBody')&&h.visible('ArcadeTestCard'),'card collapses independently');h.click('ArcadeTestToggle');
h.click('ArcadeTestPurchaseOpen');
check(h.visible('ArcadeTestPurchase')&&h.cfg.SurvivalUILayers.Top()==='arcade_readonly_shop','real modal registers in shared layer manager');
check(Number(h.native.style.zIndex)>=100000&&Number(h.host.style.zIndex)>=100000,'all real ancestor layers are raised');
check(h.cfg.SurvivalWorldOverlayVisibility.Capture().blocked,'world titles and bars see the active modal');
check(h.ids.ArcadeTestProducts.Children().length===actualCatalog.products.length,'all compiler offers are shown, not three hardcoded SKUs');
check(h.ids.ArcadeTestPrice.text.includes('¥58.00')&&h.ids.ArcadeTestPrice.text.includes('收款未开放'),'monthly price is configuration only');
h.offer('cash:special_lottery_ticket_single');check(h.ids.ArcadeTestPrice.text.includes('¥25.00'),'formal cash ticket is displayed');
h.offer('cash:u_coin_recharge');check(h.ids.ArcadeTestPrice.text.includes('¥1.00')&&h.ids.ArcadeTestRewards.text.includes('G币 ×100'),'formal recharge mapping and quantity shown');
const duplicate=actualCatalog.products.find(x=>x.currency==='CNY'&&actualCatalog.products.some(y=>y.sku===x.sku&&y.currency!=='CNY'));
check(!!duplicate,'formal compiler really contains cash and wallet offers sharing a SKU');
const wallet=actualCatalog.products.find(x=>x.sku===duplicate.sku&&x.currency!=='CNY');
h.offer(duplicate.offer_id);const cashText=h.ids.ArcadeTestPrice.text;h.offer(wallet.offer_id);
check(cashText.includes('¥')&&!h.ids.ArcadeTestPrice.text.includes('¥')&&h.ids.ArcadeTestPrice.text.includes('兑换'),'same SKU keeps two distinct offers and currencies');
for(const currency of ['u_coin','shop_points']){
 const product=actualCatalog.products.find(x=>x.currency===currency);check(!!product,'formal catalog includes '+currency);h.offer(product.offer_id);
 check(h.ids.ArcadeTestPrice.text.includes({u_coin:'G币',shop_points:'商城积分',shop_gold:'商城金币'}[currency]),'correct currency label');
}
for(const category of actualCatalog.categories){h.category(category.id);check(h.ids.ArcadeTestProducts.Children().length===actualCatalog.products.filter(x=>x.category_id===category.id).length,'category selection shows its complete offers');}
h.category('*');check(h.ids.ArcadeTestProducts.Children().length===actualCatalog.products.length,'all categories restore every compiler offer');
const scroll=harness();scroll.receive(state);scroll.click('ArcadeTestPurchaseOpen');
const scrollList=scroll.ids.ArcadeTestProducts,scrollDetails=scroll.ids.ArcadeTestProductTitle.GetParent();
scrollList.scrolloffset_y=1900;scrollDetails.scrolloffset_y=280;const beforeTimer=[scrollList.scrollResetCalls,scrollDetails.scrollResetCalls];scroll.monitor();
check(scrollList.scrolloffset_y===1900&&scrollDetails.scrolloffset_y===280&&scrollList.scrollResetCalls===beforeTimer[0]&&scrollDetails.scrollResetCalls===beforeTimer[1],'same-offer timer render preserves user list and detail scroll');
scroll.category('technology');check(scrollList.scrolloffset_y===0&&scrollList.Children()[0].classes.Selected&&scroll.ids.ArcadeTestPrice.text.includes('¥58.00'),'category rebuild resets native list offset and aligns default monthly detail with its visible first row');
scroll.category('*');scrollList.scrolloffset_y=800;scrollDetails.scrolloffset_y=240;scroll.offer('cash:special_lottery_ticket_single');
check(scrollDetails.scrolloffset_y===0&&scrollList.scrolloffset_y===800&&scroll.ids.ArcadeTestPrice.text.includes('¥25.00'),'new offer resets detail scroll while preserving the user list position');
scrollList.scrolloffset_y=1000;scrollDetails.scrolloffset_y=180;const beforeState=[scrollList.scrollResetCalls,scrollDetails.scrollResetCalls];scroll.receive({...state,sequence:2});
check(scrollList.scrolloffset_y===1000&&scrollDetails.scrolloffset_y===180&&scrollList.scrollResetCalls===beforeState[0]&&scrollDetails.scrollResetCalls===beforeState[1],'fresh server heartbeat with same selection does not reset either scroller');
scroll.click('ArcadeTestClose');scroll.click('ArcadeTestPurchaseOpen');check(scrollList.scrolloffset_y===0&&scrollDetails.scrolloffset_y===0&&scrollList.Children()[0].classes.Selected&&scroll.ids.ArcadeTestPrice.text.includes('¥58.00'),'explicit reopening clears old offsets and starts at the selected visible first offer');
scrollDetails.scrolloffset_y=100;scroll.category('weapon');check(scrollList.scrolloffset_y===0&&scrollDetails.scrolloffset_y===0&&scroll.ids.ArcadeTestProductTitle.text==='本分类暂无商品','empty category clears old detail and resets its scroller');
const goldCatalog=clone(actualCatalog),goldRow=goldCatalog.products.find(x=>x.currency==='u_coin');goldRow.currency='shop_gold';const gold=harness({catalog:goldCatalog});gold.receive(state);gold.click('ArcadeTestPurchaseOpen');gold.offer(goldRow.offer_id);check(gold.ids.ArcadeTestPrice.text.includes('商城金币'),'supported shop-gold configuration formats its own currency without inventing a balance');
const limited=actualCatalog.products.find(x=>x.purchase_limit>0||x.required_vip_level>0);check(!!limited,'formal data has eligibility metadata');h.offer(limited.offer_id);
check(h.ids.ArcadeTestLimits.text.includes('配置限购')&&h.ids.ArcadeTestLimits.text.includes('不代表本账号'),'limits do not invent remaining allowance');
h.click('ArcadeTestWebShop');
check(h.network.length===1&&h.network[0][0]==='ExternalBrowserGoToURL'&&h.network[0][1]==='https://pay.xiaofengnet.com/ws4-shop/','only exact fixed HTTPS directory URL is opened, with no query identity or token');
h.click('ArcadeTestClose');
check(!h.visible('ArcadeTestPurchase')&&h.cfg.SurvivalUILayers.Top()===null&&!h.cfg.SurvivalWorldOverlayVisibility.Capture().blocked,'close releases modal and world suppression');
check(h.native.style.zIndex==='5'&&h.host.style.zIndex==='8','close restores exact native ancestor z-index values');
h.click('ArcadeTestWebShop');check(h.network.length===1,'hidden dialog callback cannot open browser');
h.cfg.SurvivalPayments.Open();check(h.visible('ArcadeTestPurchase')&&h.oldOpens()===0,'existing original shop action redirects only in the fresh marked session');
h.click('ArcadeTestScrim');check(!h.visible('ArcadeTestPurchase')&&h.cfg.SurvivalUILayers.Top()===null,'outside click releases modal');
h.click('ArcadeTestPurchaseOpen');h.cfg.SurvivalUILayers.CloseTop();check(!h.visible('ArcadeTestPurchase')&&h.cfg.SurvivalUILayers.Top()===null,'shared Escape/close callback releases local opened state');
h.click('ArcadeTestPurchaseOpen');h.setMap({map_name:'normal_map'});h.monitor();h.root.visible=true;
check(!h.visible('ArcadeTestPurchase')&&!h.visible('ArcadeTestCard')&&!h.root.hittestchildren&&h.cfg.SurvivalPayments.Open===h.originalOpen,'map change leaves ordinary HUD/input and original shop intact');
check(h.cfg.SurvivalUILayers.Top()===null&&h.native.style.zIndex==='5','map transition releases shared layers');
h.setMap({map_name:'template_map'});h.monitor();check(!h.visible('ArcadeTestCard'),'return to map needs fresh server event');
h.receive(state);const newerOpen=()=> 'new-payment-api',newer={Open:newerOpen};h.cfg.SurvivalPayments=newer;h.monitor();check(newer.Open!==newerOpen,'late payment API reload gets a new narrow hook');
h.dispose();check(newer.Open===newerOpen&&h.unsubscribed.length===1,'dispose restores only owned latest hook and unsubscribes');
const external=harness();external.receive(state);const externalReplacement=()=> 'another-owner';external.cfg.SurvivalPayments.Open=externalReplacement;external.dispose();check(external.cfg.SurvivalPayments.Open===externalReplacement,'dispose never overwrites another owner replacement');
const dead=harness();dead.receive(state);dead.click('ArcadeTestPurchaseOpen');dead.root.invalidate();dead.monitor();check(dead.cfg.SurvivalUILayers.Top()===null&&dead.host.style.zIndex==='8'&&dead.unsubscribed.length===1,'destroyed context releases surviving native ancestors and listener');
const reload=harness();reload.receive(state);reload.click('ArcadeTestPurchaseOpen');reload.reload();check(!reload.visible('ArcadeTestPurchase')&&reload.cfg.SurvivalUILayers.Top()===null&&reload.cfg.SurvivalPayments.Open===reload.originalOpen,'controller reload releases old modal/hook and waits for fresh state');
const stale=harness();stale.receive(state);const staleClick=stale.ids.ArcadeTestClose.handlers.onactivate,staleApi=stale.cfg.SurvivalArcadeReadOnlyShop,staleWrapper=stale.cfg.SurvivalPayments.Open;stale.reload();stale.receive(state);stale.click('ArcadeTestPurchaseOpen');staleClick();staleApi.Close();staleWrapper();check(stale.visible('ArcadeTestPurchase')&&stale.cfg.SurvivalUILayers.Top()==='arcade_readonly_shop','retired handlers/API/hook never hide a new controller modal');
const stacked=harness();stacked.receive(state);stacked.click('ArcadeTestPurchaseOpen');const other=stacked.ctx.$.CreatePanel('Panel',stacked.root,'AnotherModal');stacked.cfg.SurvivalUILayers.Open('another_modal',other,()=>{});stacked.cfg.SurvivalArcadeReadOnlyShop.Close();check(stacked.cfg.SurvivalUILayers.Top()==='another_modal'&&stacked.cfg.SurvivalWorldOverlayVisibility.Capture().blocked,'closing our window preserves an independent modal and its world occlusion');stacked.cfg.SurvivalUILayers.Close('another_modal');check(stacked.host.style.zIndex==='8','last independent modal restores original ancestor layer');
const failedLayer=harness();failedLayer.receive(state);const realOpen=failedLayer.cfg.SurvivalUILayers.Open;failedLayer.cfg.SurvivalUILayers.Open=function(...args){realOpen(...args);throw new Error('native failure');};check(failedLayer.cfg.SurvivalPayments.Open()===false&&!failedLayer.visible('ArcadeTestPurchase')&&failedLayer.cfg.SurvivalUILayers.Top()===null,'partial layer-open failure is contained and releases its lease');
const late=harness({missingCatalog:true});late.receive(state);late.click('ArcadeTestPurchaseOpen');check(!late.visible('ArcadeTestPurchase'),'missing generated catalog cannot open modal');late.cfg.SurvivalArcadeShopCatalog=clone(actualCatalog);late.monitor();late.click('ArcadeTestPurchaseOpen');check(late.visible('ArcadeTestPurchase'),'late catalog can recover without freezing initial ready state');
const noLayers=harness({layers:false});noLayers.receive(state);noLayers.click('ArcadeTestPurchaseOpen');check(!noLayers.visible('ArcadeTestPurchase'),'missing layer manager never opens unprotected modal');noLayers.installLayers();noLayers.monitor();noLayers.click('ArcadeTestPurchaseOpen');check(noLayers.visible('ArcadeTestPurchase'),'late layer manager recovers safely');
for(const mutation of [c=>c.checkout_enabled=true,c=>c.schema_version=2,c=>c.catalog_sha256='bad',c=>c.products[0].currency='USD',c=>c.products[0].price=-1,c=>c.products[0].price=1.5,c=>c.products[0].offer_id='wallet:'+c.products[0].sku,c=>c.products.push(clone(c.products[0])),c=>c.products[0].category_id='unknown',c=>c.products[0].required_vip_level=-1,c=>c.products[0].reward_lines[0].quantity=NaN,c=>c.categories.push(clone(c.categories[0]))]){
 const catalog=clone(actualCatalog);mutation(catalog);const t=harness({catalog});t.receive(state);t.click('ArcadeTestPurchaseOpen');check(!t.visible('ArcadeTestPurchase')&&t.cfg.SurvivalUILayers.Top()===null,'invalid catalog cannot imply valid price/checkout or leak modal');
}
const changed=harness();changed.receive(state);changed.click('ArcadeTestPurchaseOpen');changed.cfg.SurvivalArcadeShopCatalog.checkout_enabled=true;changed.monitor();check(!changed.visible('ArcadeTestPurchase')&&changed.cfg.SurvivalUILayers.Top()===null,'checkout flag change revokes active read-only modal');
const mapError=harness();mapError.receive(state);mapError.setMap(new Error('map unavailable'));mapError.click('ArcadeTestPurchaseOpen');check(!mapError.visible('ArcadeTestCard')&&mapError.cfg.SurvivalPayments.Open===mapError.originalOpen,'map API errors fail closed even before monitor');
check(!/SendCustomGameEventToServer|SendEventClientSide|CreateHTTPRequest|AsyncWebRequest|SendToConsole/.test(logic),'shop has no order/request/command transport');
check((logic.match(/DispatchEvent\(/g)||[]).length===1&&!logic.includes('checkout_url'),'only public browser directory route exists');
check(xml.includes('收款未开放')&&xml.includes('云端权益暂不能同步本局')&&xml.includes('不读取账号余额')&&xml.includes('不创建订单、不收款、不发放奖励'),'actual user flow states restrictions and shows no account balances');
const diagnostics=harness();diagnostics.receive({...state,http_phase:'SECRET_DATA'});diagnostics.receive({...state,http_phase:'SECRET_DATA'});
check(diagnostics.messages.filter(x=>x.includes('phase=reject_http_phase')).length===1&&!diagnostics.messages.some(x=>x.includes('SECRET_DATA')),'diagnostics are bounded and do not emit raw state');
diagnostics.setMap({map_name:'maps/template_map.vpk\r\n[Injected]'});diagnostics.monitor();check(!diagnostics.messages.some(x=>/[\r\n]/.test(x)||x.includes('[Injected]')),'map diagnostics cannot inject lines');
console.log(JSON.stringify({status:'PASS',checks,formal_offers:actualCatalog.products.length,categories:actualCatalog.categories.length,scope:'Local XML/CSS, actual generated public catalog, real shared layer manager in mocked Panorama. Native visuals/browser/real two-player regression NOT_RUN.'},null,2));
