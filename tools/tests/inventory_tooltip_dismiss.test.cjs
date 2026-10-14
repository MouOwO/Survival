'use strict';
// Actual inventory tooltip owner and shared dismiss policy; no account or game.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const directory='panorama/src/scripts/custom_game/';
const source=fs.readFileSync(directory+'inventory_tooltip.js','utf8');
let time=0,serial=0,cursor=[0,0];
const jobs=new Map(),nodes={},listeners={},cfg={};
class Panel{
 constructor(type,parent,id){this.id=id||'';this.paneltype=type;this.parent=parent;this.children=[];this.events={};this.style={};this.classes=new Set();this.visible=true;this.alive=true;this.position={x:100,y:500};this.actuallayoutwidth=64;this.actuallayoutheight=64;if(parent)parent.children.push(this);if(id)nodes[id]=this;}
 IsValid(){return this.alive;}GetParent(){return this.parent;}Children(){return this.children;}
 GetPositionWithinWindow(){return this.position;}
 FindChildTraverse(id){return this.id===id?this:this.children.map(p=>p.FindChildTraverse(id)).find(Boolean);}
 AddClass(c){this.classes.add(c);}RemoveClass(c){this.classes.delete(c);}BHasClass(c){return this.classes.has(c);}
 SetPanelEvent(name,fn){this.events[name]=fn;}SetImage(uri){this.image=uri;}SetScaling(){}
}
const root=new Panel('Panel',null,'Hud'),context=new Panel('Panel',root,'Context'),inventory=new Panel('Panel',root,'inventory');
for(let i=0;i<6;i++){const slot=new Panel('Panel',inventory,'inventory_slot_'+i);new Panel('DOTAItemImage',slot,'Image'+i);}
for(const id of ['CustomInventoryItemTooltip','CustomInventoryItemFields','CustomInventoryItemIcon','CustomInventoryItemTitle','CustomInventoryItemType','CustomInventoryItemLevel','CustomInventoryItemDescription','CustomInventoryItemStatus'])new Panel('Panel',context,id);
const tables={survival_inventory_item_identity:{100:{content_id:'sample_item'}},survival_item_tooltips:{sample_item:{displayname:'样例道具',description:'本地测试说明'}},survival_weapon_snapshot:{0:{}}};
const $=id=>nodes[id.slice(1)];Object.assign($,{GetContextPanel:()=>context,CreatePanel:(type,parent,id)=>new Panel(type,parent,id),Localize:s=>s,Msg(){},DispatchEvent(){},Schedule:(delay,fn)=>{jobs.set(++serial,{at:time+delay,fn});return serial;},CancelScheduled:id=>jobs.delete(id)});
const env={$,
 Game:{GetLocalPlayerID:()=>0},GameUI:{CustomUIConfig:()=>cfg,GetCursorPosition:()=>cursor},
 Players:{GetLocalPlayerPortraitUnit:()=>10,GetPlayerHeroEntityIndex:()=>10},
 Entities:{GetItemInSlot:(_,slot)=>slot===0?100:-1},Abilities:{GetAbilityName:()=> 'item_sample'},
 CustomNetTables:{GetTableValue:(table,key)=>(tables[table]||{})[key],SubscribeNetTableListener:(table,fn)=>(listeners[table]||(listeners[table]=[])).push(fn)},
 GameEvents:{Subscribe(){},SendCustomGameEventToServer(){throw Error('Tooltip must not transact');}}};
vm.createContext(env);vm.runInContext(fs.readFileSync(directory+'common/tooltip_dismiss.js','utf8'),env);vm.runInContext(source,env);
function advance(dt){const end=time+dt;let count=0;while(true){const next=[...jobs].filter(([,job])=>job.at<=end).sort((a,b)=>a[1].at-b[1].at)[0];if(!next)break;assert(++count<10000,'Timers converge');jobs.delete(next[0]);time=next[1].at;next[1].fn();}time=end;}
function hover(){nodes.inventory_slot_0.events.onmouseover();}
advance(1.1);
const tip=nodes.CustomInventoryItemTooltip;tip.position={x:90,y:480};tip.actuallayoutwidth=350;tip.actuallayoutheight=240;
cursor=[110,510];hover();assert(!tip.BHasClass('Hidden'));
tip.events.onmouseover();assert(tip.BHasClass('Hidden'),'Entering the tip hides it immediately');
hover();cfg.SurvivalInventoryTooltip.RefreshVisible();
for(const listener of listeners.survival_weapon_snapshot)listener('survival_weapon_snapshot','0',{});
advance(.3);assert(tip.BHasClass('Hidden'),'Anchor hover and snapshot refresh do not revive it within the dismissed union');
cursor=[900,900];advance(.035);tip.position={x:300,y:100};cursor=[110,510];hover();
assert(!tip.BHasClass('Hidden'),'Physical exit permits the next inventory hover');
cursor=[310,110];advance(.035);
assert(tip.BHasClass('Hidden'),'Geometry detects entry when native tooltip hit testing is disabled');
const previous=cfg.SurvivalInventoryTooltip;vm.runInContext(source,env);
assert.notStrictEqual(cfg.SurvivalInventoryTooltip,previous);
assert.equal(cfg.SurvivalTooltipDismiss.Inspect().owners,0,'Reload disposes the retired owner watch');
advance(.4);assert(tip.BHasClass('Hidden'),'Retired scheduled callbacks do not reopen a tooltip');
console.log('INVENTORY_TOOLTIP_DISMISS_PASS: immediate entry hide, blocked hover/snapshot refresh, physical exit, native geometry and reload disposal');
