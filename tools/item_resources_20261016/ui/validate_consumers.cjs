'use strict';
// Real production factories, isolated panels and read-only formal catalog data.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const repo=path.resolve(__dirname,'../../..'),base=path.join(repo,'panorama/src/scripts/custom_game');
const hash=f=>crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
const json=f=>JSON.parse(fs.readFileSync(path.join(repo,f),'utf8').replace(/^\uFEFF/,''));
const cfg={},loaded=[],events=[],timers=[];let serial=0;
class Panel{
 constructor(type,parent,id=''){this.paneltype=this.type=type;this.id=id;this.classes=new Set();this.style={};this.children=[];this.events={};this.attrs={};this.visible=true;this.SetParent(parent);}
 IsValid(){return !this.deleted;} AddClass(c){String(c).split(/\s+/).forEach(v=>this.classes.add(v));}RemoveClass(c){this.classes.delete(c);}BHasClass(c){return this.classes.has(c);}SetHasClass(c,on){on?this.AddClass(c):this.RemoveClass(c);}
 SetParent(p){if(this.parent)this.parent.children=this.parent.children.filter(c=>c!==this);this.parent=p;if(p)p.children.push(this);}GetParent(){return this.parent;}Children(){return this.children;}GetChildCount(){return this.children.length;}GetChild(i){return this.children[i];}
 FindChildTraverse(id){return this.id===id?this:this.children.map(c=>c.FindChildTraverse(id)).find(Boolean);}SetImage(s){this.image=s;}SetScaling(s){this.scaling=s;}SetPanelEvent(n,f){this.events[n]=f;}SetAttributeString(n,v){this.attrs[n]=v;}GetAttributeString(n,f){return this.attrs[n]===undefined?f:this.attrs[n];}
 DeleteAsync(){this.children.slice().forEach(c=>c.DeleteAsync());this.SetParent(null);this.deleted=true;}RemoveAndDeleteChildren(){this.children.slice().forEach(c=>c.DeleteAsync());}GetPositionWithinWindow(){return{x:0,y:0};}MoveChildBefore(){}SetFocus(){}SetAcceptsFocus(){}
}
const root=new Panel('Panel',null,'UnifiedResourceConsumerTest');root.actuallayoutwidth=1920;root.actuallayoutheight=1080;
function $(id){return root.FindChildTraverse(String(id).replace(/^#/,''));}
$.CreatePanel=(t,p,id)=>new Panel(t,p,id);$.GetContextPanel=()=>root;$.Schedule=(delay,fn)=>{timers.push({delay,fn});return ++serial;};$.CancelScheduled=()=>{};$.Msg=$.DispatchEvent=$.RegisterEventHandler=$.RegisterForUnhandledEvent=()=>{};
const env=vm.createContext({$,GameUI:{CustomUIConfig:()=>cfg},Game:{GetLocalPlayerID:()=>0,GetGameTime:()=>0,IsInToolsMode:()=>false},GameEvents:{Subscribe:(name,fn)=>{events.push({name,fn});return ++serial;},Unsubscribe(){},SendCustomGameEventToServer(){throw Error('Visual tests must not order or mutate saves');}},CustomNetTables:{GetTableValue:()=>null,SubscribeNetTableListener:()=>++serial,UnsubscribeNetTableListener(){}}});
function load(relative){const file=path.join(base,relative);vm.runInContext(fs.readFileSync(file,'utf8'),env,{filename:file});loaded.push({relative,sha256:hash(file)});}
['common/item_resources.js','common/ui_registry.js','common/ui_components.js','common/tooltip_dismiss.js','ui_layers.js','archive_v10_data.js','common/menu_v10.js','common/vip_badges.js','reward_presentation.js','native_ui_icons.js','item_art_remaining_5d5c1152eb.js','common/commerce_components.js','shop_v10_assets.js','black_lion_market_model.js','black_lion_market.js'].forEach(load);
const all=n=>[n,...n.Children().flatMap(all)],has=(n,c)=>all(n).find(v=>v.BHasClass(c));
const resource=cfg.SurvivalItemResources,presentation=cfg.SurvivalRewardPresentation,J=cfg.SurvivalCommerceComponents;
const current=json('server/bundles/current.json').hash,bundle=json('server/bundles/'+current+'/bundle.json');
const wallet=bundle.configs.commerce_catalog.rows,cash=json('design_refs/shop_functional_20261016/release_v2/payment_catalog.json').products;
const products=new Map([...wallet,...cash].map(row=>[row.sku,row]));
const results=[];
function assertIcon(icon,row,caption){
 if(row.kind==='vip'){
  assert.equal(icon.paneltype,'Panel',caption+' keeps composed VIP control');
  assert(icon.__survivalVIPBadge,caption+' includes VIP level renderer');
  assert.equal(icon.__survivalVIPBadge.image.image,row.uri,caption+' uses canonical VIP artwork');
  assert.equal(icon.__survivalVIPBadge.number.text,String(row.vip_level),caption+' includes VIP number');
 }else if(row.kind==='hero'){
  assert.equal(icon.paneltype,'DOTAHeroImage',caption+' keeps hero control');assert.equal(icon.heroname,row.hero_name);
 }else assert.equal(icon.image,row.uri,caption+' uses canonical URI');
}
for(const product of products.values()){
 const row=resource.Lookup(product);assert(row&&row.uri,product.sku+' resolves a canonical image');
 assert.equal(J.ProductIcon(product),row.uri,product.sku+' commerce chooses the table URI');
 assert.equal(J.ProductIcon({...product,icon:'file://{images}/items/recipe.png'}),row.uri,product.sku+' cannot bypass the table with an arbitrary server icon');
 const rewards=product.reward_lines||product.grants&&product.grants.lines||[];
 const market=cfg.SurvivalBlackLionMarket.Row(root,product,{index:0,catalog:{categories:[]},rewards,action(){throw Error('No purchase');}});
 assertIcon(market.__menuCell.iconPanel.Children()[0],row,product.sku+' market row');
 const card=J[product.product_type==='bundle'?'Bundle':'Product'](root,product,{rewards});
 assertIcon(has(card,'RCProductArt'),row,product.sku+' product detail');
 if(card.__purpleDispose)card.__purpleDispose();card.DeleteAsync();if(market.__purpleDispose)market.__purpleDispose();market.DeleteAsync();
 results.push({sku:product.sku,id:row.id,uri:row.uri});
}
const muramasa=[{sku:'video_p042'},{item_id:'lottery_muramasa'},{id:'lottery_muramasa'},{ownership_id:'commerce_p042'},'video_p042'];
const canonicalMuramasa=resource.Lookup('lottery_muramasa');
assert(canonicalMuramasa&&canonicalMuramasa.id==='lottery_muramasa'&&canonicalMuramasa.uri);
const expected=canonicalMuramasa.uri;
muramasa.forEach(item=>assert.equal(resource.Resolve(item),expected,'Muramasa identity resolves consistently'));
const backing=new Panel('Panel',root);
for(const item of muramasa.filter(v=>typeof v==='object')){
 const icon=presentation.CreateIcon(backing,{...item,icon_type:'image',icon:'items/recipe.png'},'ActualReward');assert.equal(icon.image,expected,'Lottery/common factory ignores stale icon');
 const art=cfg.SurvivalItemArt.Create(backing,{...item,icon:'item_recipe'},'ActualArchive');assert.equal(art.image,expected,'Legacy ItemArt entry point uses canonical table');
}
const spirit=resource.Resolve({sku:'video_p151'});assert(spirit&&spirit!==expected,'Different katana SKU retains its own identity');
const endless=presentation.CreateRegisteredIcon(backing,{id:'endless_51'},'ActualEndless');
assert(endless.BHasClass('ArchiveEndlessEmblem'));assert.equal(endless.Children().length,2);
assert(endless.Children().every(r=>r.BHasClass('ArchiveEndlessRing')),'The shared factory preserves both endless rings');
const unknown=presentation.CreateIcon(backing,{id:'not_a_formal_item',icon_type:'ability',icon:'test_unknown_ability'},'Fallback');assert.equal(unknown.paneltype,'DOTAAbilityImage');assert.equal(unknown.abilityname,'test_unknown_ability');
cfg.SurvivalItemResources={Lookup:()=>({id:'isolated_hero',kind:'hero',hero_name:'npc_dota_hero_wisp',uri:'not-used'})};
const hero=presentation.CreateRegisteredIcon(backing,{},'HeroResource');assert.equal(hero.paneltype,'DOTAHeroImage');assert.equal(hero.heroname,'npc_dota_hero_wisp');assert.equal(hero.image,undefined);
cfg.SurvivalItemResources={Lookup:()=>({id:'isolated_animated_title',kind:'layered_title',uri:'not-used'})};
assert.equal(presentation.CreateRegisteredIcon(backing,{},'LayeredTitle'),null,'Layered title uses its original renderer');
cfg.SurvivalItemResources=resource;
for(const file of ['archive.xml','survival_hud.xml','payment_test.xml','rogue_reward_ui.xml']){
 const text=fs.readFileSync(path.join(repo,'panorama/src/layout/custom_game',file),'utf8');
 const scripts=[...text.matchAll(/<include src="file:\/\/\{resources\}\/scripts\/custom_game\/([^"]+)"\s*\/>/g)].map(m=>m[1]);
 assert.equal(scripts.filter(v=>v==='common/item_resources.js').length,1,file+' loads one registry');
 for(const consumer of ['reward_presentation.js','item_art_remaining_5d5c1152eb.js','common/commerce_components.js','native_ui_icons.js'])if(scripts.includes(consumer))assert(scripts.indexOf('common/item_resources.js')<scripts.indexOf(consumer),file+' loads registry before '+consumer);
}
const report={status:'PASS',sourceHash:resource.sourceHash,syntheticPanels:true,notGameCapture:true,productCount:products.size,products:results,muramasa:expected,distinctSpiritKatana:spirit,checks:['all formal wallet/cash products share canonical card/market art and real VIP numbers','server images cannot redirect registered goods','Muramasa commerce/archive/lottery identity consistency','distinct spirit katana identity','hero panel kind retained','endless shared two-ring emblem retained','layered title retains its dedicated renderer','unknown native ability fallback retained','XML loads one registry before consumers'],sources:loaded};
const out=path.join(repo,'design_refs/item_resources_20261016');fs.mkdirSync(out,{recursive:true});fs.writeFileSync(path.join(out,'ui_consumer_validation.json'),JSON.stringify(report,null,2));console.log('ITEM_RESOURCE_UI_CONSUMERS_PASS '+products.size+' products');
