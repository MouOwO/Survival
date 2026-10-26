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
 const ids={},jobs=[],callbacks=[],network=[],messages=[],unsubscribed=[];let map={map_name:options.map===undefined?'template_map':options.map},cachedReads=0,oldOpens=0;
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
 let lease=null,snapshot=null,viewOpens=0,viewCloses=0;
 const commerceDialog=new Panel('OriginalCommerceWindow',host);commerceDialog.visible=false;
 function installView(){
  const view={OpenReadonly(data,owner){lease=owner;snapshot=data;viewOpens++;commerceDialog.visible=true;
   cfg.SurvivalUILayers.Open('commerce',commerceDialog,()=>{lease=null;commerceDialog.visible=false;});return true;},
   CloseReadonly(owner){if(lease!==owner)return false;lease=null;viewCloses++;commerceDialog.visible=false;cfg.SurvivalUILayers.Close('commerce');return true;},
   IsReadonlyOpen(owner){return lease===owner&&commerceDialog.visible;}};
  cfg.SurvivalCommerceView=view;return view;
 }
 if(options.view!==false)installView();
 if(!options.skipScript)vm.runInNewContext(logic,ctx);
 const visible=node=>{for(let n=node;n;n=n.parent)if(!n.live||!n.visible||n.style.visibility==='collapse')return false;return true;};
 return {cfg,ctx,root,native,host,ids,network,messages,callbacks,unsubscribed,originalOpen,installLayers,
  reads(){return cachedReads;},oldOpens(){return oldOpens;},setMap(v){map=v;},
  monitor(){while(jobs.length){const j=jobs.shift();if(!j.cancelled){j.fn();return;}}throw new Error('no scheduled monitor');},
  installView,viewVisible(){return commerceDialog.visible;},snapshot(){return snapshot;},viewOpens(){return viewOpens;},viewCloses(){return viewCloses;},visible(id){return visible(ids[id]);},receive(raw){callbacks.at(-1).fn('survival_arcade_multiplayer_test','state',raw);},
  click(id){ids[id].handlers.onactivate();},reload(){vm.runInNewContext(logic,ctx);},dispose(){cfg.SurvivalArcadeReadOnlyShop.Dispose();}};
}
const initial=harness({skipScript:true});
check(!initial.visible('ArcadeTestCard'),'XML status card defaults collapsed without script');
check(/\.ArcadeTestCard\s*\{[^}]*visibility:\s*collapse/.test(css),'CSS status card also defaults collapsed');
check(!/ArcadeTestPurchase\b|ArcadeTestDialog\b|ArcadeTestProducts\b/.test(xml+css),'temporary rectangular catalog layout and styles are removed');
check(!/\.ArcadeTestContext\s*\{[^}]*(?:background|border|box-shadow)/.test(css),'status-card root has no full-screen overlay');
check(xml.indexOf('arcade_shop_catalog.js')<xml.indexOf('arcade_multiplayer_test.js'),'public catalog loads before controller');
check(xml.includes('ui_layers.js'),'shared layer manager remains available');
let h=harness();
check(!h.visible('ArcadeTestCard')&&!h.root.hittestchildren&&h.reads()===0,'cached state never activates UI');
check(h.cfg.SurvivalPayments.Open===h.originalOpen,'original menu untouched before fresh state');
for(const map of ['ws4_lobby','template_map_extra','maps/template_map','maps/template_map.vpk_extra','']){
 const t=harness({map});t.receive(state);
 check(!t.visible('ArcadeTestCard')&&!t.viewVisible()&&t.cfg.SurvivalPayments.Open===t.originalOpen,'wrong map never opens own storefront');
}
for(const map of ['template_map','maps/template_map.vpk']){const t=harness({map});t.receive(state);check(t.visible('ArcadeTestCard'),'both exact native map names activate with fresh state');}
const bad=[null,{},Object.fromEntries(Object.entries(state).filter(([k])=>k!=='sequence')),{...state,sequence:0},{...state,sequence:2147483648},{...state,sequence:1.5},{...state,sequence:'1'},{...state,schema_version:2},{...state,enabled:0},{...state,session_only:false},{...state,online_players:0},{...state,online_players:5},{...state,capacity:2},{...state,host_player_id:-2},{...state,host_player_id:24},{...state,http_phase:'__proto__'},{...state,account_id:'fake'},Object.create(state)];
for(const raw of bad){const t=harness();t.receive(state);t.click('ArcadeTestPurchaseOpen');t.receive(raw);check(!t.visible('ArcadeTestCard')&&!t.viewVisible()&&t.cfg.SurvivalUILayers.Top()===null&&t.cfg.SurvivalPayments.Open===t.originalOpen,'invalid state closes the owned original storefront and restores menu');}
h.receive(state);
check(h.ids.ArcadeTestPlayers.text==='在线：2 / 4'&&h.ids.ArcadeTestHTTP.text==='HTTP：当前不可用','status remains honest about capacity and HTTP');
h.receive({...state,host_player_id:-1});check(h.ids.ArcadeTestHost.text==='房主：尚未识别','unknown host is not invented');
h.click('ArcadeTestToggle');check(!h.visible('ArcadeTestBody')&&h.visible('ArcadeTestCard'),'status card collapses separately');h.click('ArcadeTestToggle');
h.click('ArcadeTestPurchaseOpen');
check(h.viewVisible()&&h.cfg.SurvivalUILayers.Top()==='commerce','controller opens the existing commerce modal API');
check(h.snapshot().products.length===173&&h.snapshot().checkout_enabled===false&&h.snapshot().schema_version===1,'all 173 public quotes reach the storefront with checkout disabled');
check(h.snapshot().products!==h.cfg.SurvivalArcadeShopCatalog.products,'validated public projection is detached from source');
const duplicate=actualCatalog.products.find(x=>x.currency==='CNY'&&actualCatalog.products.some(y=>y.sku===x.sku&&y.currency!=='CNY'));
check(h.snapshot().products.filter(x=>x.sku===duplicate.sku).length===2,'controller never collapses cash and wallet quotes sharing a SKU');
check(h.snapshot().products.some(x=>x.sku==='archive_pass_monthly'&&x.price===5800)&&h.snapshot().products.some(x=>x.sku==='special_lottery_ticket_single'&&x.price===2500),'monthly and ticket formal amounts survive unchanged');
check(!h.snapshot().products.some(x=>'enabled' in x||'owned' in x||'balances' in x),'public data never fabricates account eligibility or ownership');
check(h.cfg.SurvivalWorldOverlayVisibility.Capture().blocked,'existing modal still suppresses world titles');
check(Number(h.native.style.zIndex)>=100000&&Number(h.host.style.zIndex)>=100000,'existing modal raises native ancestors');
const opened=h.viewOpens();h.monitor();h.receive({...state,sequence:2});check(h.viewOpens()===opened,'heartbeats do not reopen or reset the user storefront');
h.cfg.SurvivalArcadeReadOnlyShop.Close();
check(!h.viewVisible()&&h.cfg.SurvivalUILayers.Top()===null&&!h.cfg.SurvivalWorldOverlayVisibility.Capture().blocked,'explicit Close releases own original commerce modal');
check(h.native.style.zIndex==='5'&&h.host.style.zIndex==='8','modal close restores original native ancestor levels');
h.cfg.SurvivalPayments.Open();check(h.viewVisible()&&h.oldOpens()===0,'original top menu opens own storefront only in marked session');
h.cfg.SurvivalUILayers.CloseTop();check(!h.viewVisible(),'shared Escape callback closes existing storefront');h.monitor();check(!h.viewVisible(),'monitor never reopens a user-closed storefront');
h.click('ArcadeTestPurchaseOpen');h.setMap({map_name:'normal_map'});h.monitor();
check(!h.viewVisible()&&!h.visible('ArcadeTestCard')&&!h.root.hittestchildren&&h.cfg.SurvivalPayments.Open===h.originalOpen,'leaving map closes storefront and restores ordinary input/menu');
h.setMap({map_name:'template_map'});h.monitor();check(!h.visible('ArcadeTestCard'),'returning map requires fresh server event');
h.receive(state);const newerOpen=()=> 'new-payment-api',newer={Open:newerOpen};h.cfg.SurvivalPayments=newer;h.monitor();check(newer.Open!==newerOpen,'payment API reload obtains a fresh narrow top-menu hook');
h.dispose();check(newer.Open===newerOpen&&h.unsubscribed.length===1,'dispose restores owned hook and unsubscribes');
const external=harness();external.receive(state);const replacement=()=> 'external-owner';external.cfg.SurvivalPayments.Open=replacement;external.dispose();check(external.cfg.SurvivalPayments.Open===replacement,'dispose preserves externally replaced menu hook');
const dead=harness();dead.receive(state);dead.click('ArcadeTestPurchaseOpen');dead.root.invalidate();dead.monitor();check(!dead.viewVisible()&&dead.cfg.SurvivalUILayers.Top()===null&&dead.unsubscribed.length===1,'dead status context releases surviving original storefront');
const reload=harness();reload.receive(state);reload.click('ArcadeTestPurchaseOpen');reload.reload();check(!reload.viewVisible()&&reload.cfg.SurvivalPayments.Open===reload.originalOpen,'controller reload releases own lease and waits for fresh event');
const stale=harness();stale.receive(state);const staleClick=stale.ids.ArcadeTestPurchaseOpen.handlers.onactivate,staleApi=stale.cfg.SurvivalArcadeReadOnlyShop,staleWrapper=stale.cfg.SurvivalPayments.Open;stale.reload();stale.receive(state);stale.click('ArcadeTestPurchaseOpen');const count=stale.viewOpens();staleClick();staleApi.Close();staleWrapper();check(stale.viewVisible()&&stale.viewOpens()===count,'retired callbacks cannot close or reopen a replacement controller storefront');
const viewReload=harness();viewReload.receive(state);viewReload.click('ArcadeTestPurchaseOpen');const oldView=viewReload.cfg.SurvivalCommerceView;viewReload.installView();viewReload.monitor();check(!oldView.IsReadonlyOpen(viewReload.cfg.SurvivalArcadeReadOnlyShop),'commerce API reload closes the old owned view');viewReload.click('ArcadeTestPurchaseOpen');check(viewReload.viewVisible(),'replacement own storefront opens after explicit user action');
const stacked=harness();stacked.receive(state);stacked.click('ArcadeTestPurchaseOpen');const other=stacked.ctx.$.CreatePanel('Panel',stacked.root,'IndependentModal');stacked.cfg.SurvivalUILayers.Open('another_modal',other,()=>{});stacked.cfg.SurvivalArcadeReadOnlyShop.Close();check(stacked.cfg.SurvivalUILayers.Top()==='another_modal'&&stacked.cfg.SurvivalWorldOverlayVisibility.Capture().blocked,'closing storefront preserves an independent modal');
const failing=harness();failing.receive(state);const realOpen=failing.cfg.SurvivalCommerceView.OpenReadonly;failing.cfg.SurvivalCommerceView.OpenReadonly=function(...args){realOpen(...args);throw Error('native failure');};check(failing.cfg.SurvivalPayments.Open()===false&&!failing.viewVisible()&&failing.cfg.SurvivalUILayers.Top()===null,'partial original-modal opening failure releases owned lease');
const late=harness({missingCatalog:true});late.receive(state);late.click('ArcadeTestPurchaseOpen');check(!late.viewVisible(),'missing catalog cannot open');late.cfg.SurvivalArcadeShopCatalog=clone(actualCatalog);late.monitor();late.click('ArcadeTestPurchaseOpen');check(late.viewVisible(),'late valid catalog recovers');
const noView=harness({view:false});noView.receive(state);noView.click('ArcadeTestPurchaseOpen');check(!noView.viewVisible(),'missing own storefront disables opening');noView.installView();noView.monitor();noView.click('ArcadeTestPurchaseOpen');check(noView.viewVisible(),'late own storefront recovers');
const noLayers=harness({layers:false});noLayers.receive(state);noLayers.click('ArcadeTestPurchaseOpen');check(!noLayers.viewVisible(),'missing layer manager disables opening');noLayers.installLayers();noLayers.monitor();noLayers.click('ArcadeTestPurchaseOpen');check(noLayers.viewVisible(),'late layer manager recovers');
for(const mutation of [c=>c.checkout_enabled=true,c=>c.schema_version=2,c=>c.catalog_sha256='bad',c=>c.products[0].currency='USD',c=>c.products[0].price=-1,c=>c.products[0].price=1.5,c=>c.products[0].offer_id='wallet:'+c.products[0].sku,c=>c.products.push(clone(c.products[0])),c=>c.products[0].category_id='unknown',c=>c.products[0].required_vip_level=-1,c=>c.products[0].reward_lines[0].quantity=NaN,c=>c.categories.push(clone(c.categories[0]))]){
 const catalog=clone(actualCatalog);mutation(catalog);const t=harness({catalog});t.receive(state);t.click('ArcadeTestPurchaseOpen');check(!t.viewVisible()&&t.cfg.SurvivalUILayers.Top()===null,'invalid catalog cannot imply a valid order quote or leak owned modal');
}
const changed=harness();changed.receive(state);changed.click('ArcadeTestPurchaseOpen');changed.cfg.SurvivalArcadeShopCatalog.checkout_enabled=true;changed.monitor();check(!changed.viewVisible(),'checkout flag mutation revokes original storefront lease');
const mapError=harness();mapError.receive(state);mapError.setMap(new Error('map unavailable'));mapError.click('ArcadeTestPurchaseOpen');check(!mapError.visible('ArcadeTestCard')&&mapError.cfg.SurvivalPayments.Open===mapError.originalOpen,'map API errors fail closed on click');
check(!/SendCustomGameEventToServer|SendEventClientSide|CreateHTTPRequest|AsyncWebRequest|SendToConsole|DispatchEvent|checkout_url/.test(logic),'controller has no transport, order token or external-browser fallback');
check(xml.includes('收款未开放')&&xml.includes('打开商城'),'status card keeps an honest own-storefront entry');
const diagnostics=harness();diagnostics.receive({...state,http_phase:'SECRET_DATA'});diagnostics.receive({...state,http_phase:'SECRET_DATA'});check(diagnostics.messages.filter(x=>x.includes('phase=reject_http_phase')).length===1&&!diagnostics.messages.some(x=>x.includes('SECRET_DATA')),'bounded diagnostics never emit raw state');
diagnostics.setMap({map_name:'maps/template_map.vpk\r\n[Injected]'});diagnostics.monitor();check(!diagnostics.messages.some(x=>/[\r\n]/.test(x)||x.includes('[Injected]')),'map diagnostics cannot inject lines');
console.log(JSON.stringify({status:'PASS',checks,formal_offers:actualCatalog.products.length,scope:'Controller lifecycle/API projection with real shared layer manager in mocked Panorama. Actual commerce components are tested separately. Native visual/two-account regression NOT_RUN.'},null,2));
