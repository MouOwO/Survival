'use strict';
// Actual HUD tooltip owners and shared policy, with local cursor/timer state only.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const dir='panorama/src/scripts/custom_game/';
function harness(){
 let time=0,serial=0,cursor=[0,0];const jobs=new Map(),nodes={},cfg={},requests=[];
 class Panel{
  constructor(type,parent,id){this.id=id||'';this.paneltype=type;this.parent=parent;this.children=[];this.events={};this.style={};this.classes=new Set();this.visible=true;this.valid=true;this.actuallayoutwidth=64;this.actuallayoutheight=64;this.actualuiscale_x=this.actualuiscale_y=1;this.position={x:100,y:500};if(parent)parent.children.push(this);if(id)nodes[id]=this;}
  IsValid(){return this.valid;}GetParent(){return this.parent;}GetPositionWithinWindow(){return this.position;}Children(){return this.children;}FindChildTraverse(id){return this.id===id?this:this.children.map(p=>p.FindChildTraverse(id)).find(Boolean);}
  AddClass(c){this.classes.add(c);}RemoveClass(c){this.classes.delete(c);}BHasClass(c){return this.classes.has(c);}SetHasClass(c,on){on?this.AddClass(c):this.RemoveClass(c);}SetPanelEvent(e,fn){this.events[e]=fn;}SetImage(v){this.image=v;}SetScaling(){}RemoveAndDeleteChildren(){this.children.forEach(p=>p.valid=false);this.children=[];}
 }
 const root=new Panel('Panel',null,'root');root.actuallayoutwidth=1920;root.actuallayoutheight=1080;root.position={x:0,y:0};
 const make=id=>new Panel('Panel',root,id),$=id=>nodes[id.slice(1)];
 Object.assign($,{GetContextPanel:()=>root,CreatePanel:(t,p,id)=>new Panel(t,p,id),Localize:s=>s,Msg(){},DispatchEvent(){},Schedule:(delay,fn)=>{jobs.set(++serial,{at:time+delay,fn});return serial;},CancelScheduled:id=>jobs.delete(id)});
 const env={$,GameUI:{CustomUIConfig:()=>cfg,GetCursorPosition:()=>cursor},Game:{GetLocalPlayerID:()=>0},Players:{GetLocalPlayerPortraitUnit:()=>1,GetPlayerHeroEntityIndex:()=>1},Entities:{GetUnitName:()=> 'building_city'},Abilities:{GetBehavior:()=>4,GetLevel:()=>1,GetManaCost:()=>0,GetCooldownLength:()=>0},CustomNetTables:{GetTableValue:table=>table==='survival_ability_runtime'?{owner_entindex:1,ability_entindex:10,available:1,current_level:1}:{}},GameEvents:{SendCustomGameEventToServer:(...v)=>requests.push(v)}};
 vm.createContext(env);const load=(file,source)=>vm.runInContext(source||fs.readFileSync(dir+file,'utf8'),env,{filename:file});
 load('common/tooltip_dismiss.js');
 function advance(dt){const end=time+dt;let n=0;while(true){const next=[...jobs].filter(([,j])=>j.at<=end).sort((a,b)=>a[1].at-b[1].at)[0];if(!next)break;assert(++n<10000);jobs.delete(next[0]);time=next[1].at;next[1].fn();}time=end;}
 return {cfg,nodes,make,env,load,advance,setCursor:p=>cursor=p,requests};
}

{
 const h=harness();
 for(const id of ['ShopEntryTooltip','ShopTooltipFrame','ShopTooltipIconHost','ShopTooltipFields','CustomShopWindow','ShopTooltipTitle','ShopTooltipWoodCost','ShopTooltipGoldCost','ShopTooltipType','ShopTooltipDescription','ShopTooltipCondition','ShopTooltipOwned','ShopTooltipStatus'])h.make(id);
 h.cfg.SurvivalItemArt={Create:()=>true};let purchases=0;
 h.cfg.SurvivalShop={PurchaseEntry:()=>purchases++,ToggleAutoPurchaseEntry:()=>purchases++};
 h.load('shop_tooltip_remaining_5d5c1152eb.js');
 const api=h.cfg.SurvivalShopTooltip,tip=h.nodes.ShopEntryTooltip,card=h.make('card'),entry={entry_id:'local_sample',name:'样例商品',purchasable:1};
 card.position={x:100,y:500};tip.position={x:90,y:480};tip.actuallayoutwidth=350;tip.actuallayoutheight=240;
 h.setCursor([110,510]);api.Show(entry,card,true);assert(api.Inspect().pinned);
 assert.equal(h.nodes.ShopTooltipPurchase,undefined,'Shop tooltip has no purchase control');
 assert.equal(h.nodes.ShopTooltipAutoPurchase,undefined,'Shop tooltip has no automatic-purchase control');
 assert.equal(api.Inspect().actions,false,'Shop tooltip is informational');
 tip.events.onmouseover();assert(tip.BHasClass('Hidden'),'Pinned tooltip dismisses immediately');
 assert.equal(api.Inspect().entry,null);assert.equal(api.Inspect().pinned,false);
 api.UpdateAutoPurchaseState();assert.equal(purchases,0,'Dismissed informational tooltip cannot transact');
 api.Show(entry,card);api.UpdateEntry(entry);h.advance(.5);
 assert(tip.BHasClass('Hidden'),'Hover and authoritative entry updates cannot revive a dismissed tooltip');
 h.setCursor([1800,900]);h.advance(.04);tip.position={x:300,y:100};h.setCursor([110,510]);api.Show(entry,card);
 assert(!tip.BHasClass('Hidden'));h.setCursor([310,110]);h.advance(.04);assert(tip.BHasClass('Hidden'));
 h.load('shop_tooltip_remaining_5d5c1152eb.js');assert.equal(h.cfg.SurvivalTooltipDismiss.Inspect().owners,0,'Hot reload disposes the old shop owner');
 assert.equal(h.requests.length,0);
}

{
 const h=harness();
 for(const id of ['CustomAbilityTooltip','CustomAbilityFields','CustomAbilityExtensionLabel','CustomAbilityTitle','CustomAbilityLevel','CustomAbilityDescription','CustomAbilityCostRow','CustomAbilityGoldCost','CustomAbilityWoodCost','CustomAbilityType','CustomAbilityStatus'])h.make(id);
 // Expose actual owner functions before starting unrelated HUD survey/tick loops.
 // Tooltip show/hide, owner guards, rendering and native suppression stay intact.
 const source=fs.readFileSync(dir+'hud_takeover.js','utf8'),seam='    config.SurvivalAbilityTakeover = tooltipApi = {';
 assert(source.includes(seam));let api;
 h.env.__takeoverTooltip=tool=>api=tool;
 h.load('hud_takeover.js',source.replace(seam,'    __takeoverTooltip({Show:showTooltip,Hide:hideTooltip,Inspect:function(){return {active:activeAbility,panel:activePanel};}});return;\n'+seam));
 const tip=h.nodes.CustomAbilityTooltip,card=h.make('ability'),entry={ability:10,name:'ability_upgrade_city'};
 tip.position={x:90,y:480};tip.actuallayoutwidth=337;tip.actuallayoutheight=200;
 h.setCursor([110,510]);api.Show(entry,card);tip.events.onmouseover();
 assert(tip.BHasClass('Hidden'));assert.equal(api.Inspect().active,-1);
 api.Show(entry,card);h.advance(.1);assert(tip.BHasClass('Hidden'),'Full takeover is covered by the same physical-exit guard');
 h.setCursor([1800,900]);h.advance(.04);tip.position={x:300,y:100};api.Show(entry,card);
 assert(!tip.BHasClass('Hidden'));
 tip.__survivalTooltipOwner='selective_proxy';tip.events.onmouseover();
 assert(!tip.BHasClass('Hidden'),'A foreign owner is never dismissed by the stale takeover registration');
 assert.equal(tip.__survivalTooltipOwner,'selective_proxy');
 tip.__survivalTooltipOwner='full_takeover';tip.events.onmouseover();assert(tip.BHasClass('Hidden'));
 assert.equal(h.requests.length,0);
}
console.log('HUD_TOOLTIP_DISMISS_PASS: informational pinned shop and full takeover, immediate dismissal, blocked hover/refresh, physical exit, reload and foreign-owner protection');
