const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const dir='panorama/src/scripts/custom_game/';
for(const filename of ['shop_remaining_5d5c1152eb.js','shop_ui.js']) {
 const source=fs.readFileSync(dir+filename,'utf8'),sent=[],notices=[];
 const env={currentMode:'research',researchSourceEntindex:123,pendingTechnologyPurchases:{},
  drawerOpened:true,snapshotMatchesContext:()=>true,
  earlyFinalCooldownRemaining:()=>0,technologyCooldownRemaining:()=>30,technologyCooldownSource:()=> 'attack',
  setStatus:message=>notices.push(message),requestId:()=> 'test',snapshot:{},
  GameEvents:{SendCustomGameEventToServer:(event,payload)=>sent.push({event,payload})},
  GameUI:{CustomUIConfig:()=>({RemainingHandoff:{UpdateShopPrices(){},ShopStock:()=>null}})},
  lockBadgeText:()=>'',updateCooldownOverlay(){},contentSignature:JSON.stringify,
  setProperty(panel,key,value){if(panel)panel[key]=value},
  setClass(panel,name,on){if(panel)panel.SetHasClass(name,on)}};
 vm.runInNewContext(source.slice(source.indexOf('    function usesTechnologyPrerequisites('),source.indexOf('    function toggleAutoResearch(')),env);
 const updateStart=source.indexOf('    function updateEntryCard(');
 vm.runInNewContext(source.slice(updateStart,source.indexOf('    function ',updateStart+1)),env);
 const card={classes:new Set(),BHasClass(name){return this.classes.has(name)},
  SetHasClass(name,on){on?this.classes.add(name):this.classes.delete(name)}};
 const base={entry_id:'attack_2',purchase_entry_id:'attack_3',content_type:'technology',name:'攻击科技',
  technology_group:'attack',prerequisite_met:1,resource_check_on_cast:1,purchasable:0};
 for(const disabled_reason_code of ['research_queue_full','queued_max_level','insufficient_wood','insufficient_gold']) {
  const entry={...base,disabled_reason_code};
  env.updateEntryCard(card,entry);
  for(const name of ['Unavailable','PrerequisiteLocked','ResourceLocked','PurchaseCooldownLocked'])
   assert(!card.classes.has(name),filename+': '+disabled_reason_code+' must not become '+name);
  assert.equal(card.visible,true);
  env.pendingTechnologyPurchases={};const before=sent.length;env.purchase(entry);
  assert.equal(sent.length,before+1,filename+': unlocked research reaches server despite stale queue/wallet and active research');
  assert.equal(sent.at(-1).event,'ui_shop_purchase_request');assert.equal(sent.at(-1).payload.source_entindex,123);
  assert.equal(sent.at(-1).payload.entry_id,'attack_3');
  env.purchase(entry);assert.equal(sent.length,before+1,'in-flight duplicate protection remains');
 }
 const locked={...base,prerequisite_met:0,purchasable:1};env.pendingTechnologyPurchases={};
 env.updateEntryCard(card,locked);assert(card.classes.has('Unavailable'));assert(card.classes.has('PrerequisiteLocked'));
 let before=sent.length;env.purchase(locked);assert.equal(sent.length,before,'missing prerequisite cannot send request');
 const complete={...base,completed:1};env.updateEntryCard(card,complete);assert.equal(card.visible,false);
 env.purchase(complete);assert.equal(sent.length,before,'completed technology remains hidden and blocked');
 const removed={...base,removed:1};env.updateEntryCard(card,removed);assert.equal(card.visible,false);
 env.purchase(removed);assert.equal(sent.length,before);
 const item={...base,content_type:'item',disabled_reason:'余额不足'};env.updateEntryCard(card,item);
 assert(card.classes.has('Unavailable'));env.purchase(item);assert.equal(sent.length,before,'ordinary purchases keep their original guard');
 env.updateEntryCard(card,{...base,purchasable:1});assert.equal(card.visible,true,'replacement technology becomes visible');
 env.currentMode='shop';env.purchase({...base,purchasable:1});assert.equal(sent.length,before,'nonqueue technology retains execution cooldown');
 console.log('PASS '+filename+': prerequisite tint, queued purchase dispatch, duplicate protection, completed removal and ordinary product guard');
}
// Exercise the actual tooltip controller, whose grayscale is independent of
// the product card. Cost and description rendering must remain functional.
const nodes={};
for(const id of ['ShopEntryTooltip','ShopTooltipIconHost','ShopTooltipFields','CustomShopWindow','ShopTooltipTitle','ShopTooltipWoodCost','ShopTooltipGoldCost','ShopTooltipType','ShopTooltipDescription','ShopTooltipCondition','ShopTooltipOwned','ShopTooltipStatus']) {
 nodes[id]={style:{},visible:true,classes:new Set(),parent:{visible:true},GetParent(){return this.parent},
  RemoveAndDeleteChildren(){},SetHasClass(name,on){on?this.classes.add(name):this.classes.delete(name)},RemoveClass(){},AddClass(){}};
}
const $=id=>nodes[id.slice(1)];$.Schedule=()=>{};
const cfg={SurvivalItemArt:{Create:()=>true}};
vm.runInNewContext(fs.readFileSync(dir+'shop_tooltip_remaining_5d5c1152eb.js','utf8'),{
 $,GameUI:{CustomUIConfig:()=>cfg},CustomNetTables:{GetTableValue:()=>({})}
});
const tip=cfg.SurvivalShopTooltip;
tip.Show({content_type:'technology',name:'科技',description:'当前科技效果',prerequisite_met:1,purchasable:0,wood_cost:100});
assert(!nodes.ShopEntryTooltip.classes.has('Unavailable'));assert(!nodes.ShopEntryTooltip.classes.has('PrerequisiteLocked'));
assert.equal(nodes.ShopTooltipDescription.text,'当前科技效果');assert.equal(nodes.ShopTooltipWoodCost.text,'100');
tip.Show({content_type:'technology',prerequisite_met:0,purchasable:1});
assert(nodes.ShopEntryTooltip.classes.has('Unavailable'));assert(nodes.ShopEntryTooltip.classes.has('PrerequisiteLocked'));
tip.Show({content_type:'item',purchasable:1});assert(!nodes.ShopEntryTooltip.classes.has('PrerequisiteLocked'));
const css=fs.readFileSync('panorama/src/styles/custom_game/remaining_5d5c1152eb.css','utf8');
assert(css.includes('.ShopShelfSlot.Technology.PrerequisiteLocked:hover .ShopItemIcon { saturation:0; brightness:0.45; }'),
 'locked technology must retain its tint through the approved original-icon hover override');
console.log('SHOP_PREREQUISITES_PASS: actual/backup shop controller, tooltip and scoped prerequisite-only hover styling');
