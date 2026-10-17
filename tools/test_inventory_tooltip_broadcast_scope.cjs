"use strict";
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const source=fs.readFileSync('panorama/src/scripts/custom_game/inventory_tooltip.js','utf8');
function setup(){
 let now=0,unit=10,seq=0;const nodes={},events={},listeners={},jobs=[],all=[],counts={binds:0};
 const items={10:[100],20:[200]},data={survival_inventory_item_identity:{100:{content_id:'own_item'},200:{content_id:'spectated_item'}},
  survival_item_tooltips:{own_item:{displayname:'本地物品',description:'初始'},spectated_item:{displayname:'查看玩家物品',description:'其他玩家'}},survival_weapon_snapshot:{0:{}}};
 function panel(type,parent,id){const p={id:id||'',paneltype:type,parent,children:[],events:{},style:{},classes:new Set(),visible:true,text:'',alive:true,
  IsValid(){return this.alive;},GetParent(){return this.parent;},Children(){return this.children;},
  FindChildTraverse(key){if(this.id===key&&this.alive)return this;for(const c of this.children){const found=c.FindChildTraverse(key);if(found)return found;}return null;},
  AddClass(c){this.classes.add(c);},RemoveClass(c){this.classes.delete(c);},SetImage(uri){this.image=uri;},SetScaling(){},
  SetPanelEvent(n,fn){counts.binds++;this.events[n]=fn;}};all.push(p);if(parent)parent.children.push(p);if(id)nodes[id]=p;return p;}
 const root=panel('Panel',null,'Hud'),ctx=panel('Panel',root,'Context'),inv=panel('Panel',root,'inventory');
 for(let i=0;i<6;i++){const slot=panel('Panel',inv,'inventory_slot_'+i);panel('DOTAItemImage',slot,'Image'+i);}
 for(const id of ['CustomInventoryItemTooltip','CustomInventoryItemFields','CustomInventoryItemIcon','CustomInventoryItemTitle','CustomInventoryItemType','CustomInventoryItemLevel','CustomInventoryItemDescription','CustomInventoryItemStatus'])panel('Panel',ctx,id);
 const cfg={},$=id=>nodes[id.slice(1)];$.GetContextPanel=()=>ctx;$.CreatePanel=panel;$.Localize=x=>x;$.Msg=()=>{};$.DispatchEvent=()=>{};
 $.Schedule=(sec,fn)=>{const id=++seq;jobs.push({id,at:now+sec*1000,fn});return id;};
 const env={$,Game:{GetLocalPlayerID:()=>0},Players:{GetLocalPlayerPortraitUnit:()=>unit,GetPlayerHeroEntityIndex:()=>10},
  Entities:{GetItemInSlot:(id,slot)=>(items[id]||[])[slot]===undefined?-1:items[id][slot]},Abilities:{GetAbilityName:id=>'item_'+id},
  CustomNetTables:{GetTableValue:(table,key)=>(data[table]||{})[key],SubscribeNetTableListener:(table,fn)=>(listeners[table]||(listeners[table]=[])).push(fn)},
  GameEvents:{Subscribe:(name,fn)=>(events[name]||(events[name]=[])).push(fn)},GameUI:{CustomUIConfig:()=>cfg}};
 vm.createContext(env);vm.runInContext(source,env);
 function advance(ms){const end=now+ms;let steps=0;while(jobs.some(j=>j.at<=end)){jobs.sort((a,b)=>a.at-b.at);const job=jobs.shift();now=job.at;job.fn();assert(++steps<10000,'bounded queued callbacks');}now=end;}
 function emit(table,key,value){if(!data[table])data[table]={};data[table][key]=value;(listeners[table]||[]).forEach(fn=>fn(table,key,value));}
 function event(name,payload){(events[name]||[]).forEach(fn=>fn(payload));}
 advance(1100);return {nodes,all,cfg,counts,items,data,env,inv,advance,emit,event,select:n=>unit=n,
  hover:i=>nodes['inventory_slot_'+i].events.onmouseover(),queued:()=>jobs.filter(j=>j.at===now).length,
  reload:()=>vm.runInContext(source,env),lateImage:i=>panel('DOTAItemImage',nodes['inventory_slot_'+i],'lateImage'+i),newSlot:i=>{const old=nodes['inventory_slot_'+i];old.alive=false;inv.children=inv.children.filter(c=>c!==old);const slot=panel('Panel',inv,'inventory_slot_'+i);panel('DOTAItemImage',slot,'newImage'+i);return slot;}};
}
const t=setup(),api=t.cfg.SurvivalInventoryTooltip;t.counts.binds=0;
for(let i=0;i<1000;i++)t.emit('survival_inventory_item_identity',String(10000+i),{content_id:'foreign_'+i});
assert.equal(t.queued(),0);assert.equal(t.counts.binds,0);assert.equal(api.CacheInspect().counts.identityIgnored,1000,'unrelated owners/item keys cause no rebinding');
for(let i=0;i<1000;i++)t.emit('survival_inventory_item_identity','100',{content_id:'own_item',version:i});
assert.equal(t.queued(),1);t.advance(0);assert.equal(t.counts.binds,24,'one six-slot recovery for the entire burst');
t.hover(0);assert.equal(t.nodes.CustomInventoryItemTitle.text,'本地物品');t.advance(100);const before=api.CacheInspect().counts.refreshed;
for(let i=0;i<500;i++)t.emit('survival_item_tooltips','unrelated_'+i,{description:'foreign'});
assert.equal(t.queued(),0);assert.equal(api.CacheInspect().counts.refreshed,before);
for(let i=0;i<500;i++){t.emit('survival_item_tooltips','own_item',{displayname:'最终道具',description:'最后版本 '+i});t.emit('survival_weapon_snapshot','0',{tooltip_view_model:{items:{own_item:{fields:[{label:'升级',value:i}]}}}});}
assert.equal(t.queued(),1);t.advance(0);assert.equal(t.nodes.CustomInventoryItemTitle.text,'最终道具');assert.equal(t.nodes.CustomInventoryItemDescription.text,'最后版本 499');assert.equal(t.nodes.CustomInventoryItemFields.__fieldRows[0].__right.text,'499','coalescing reads final values, not captured stale payload');
t.advance(100);t.counts.binds=0;t.event('ui_weapon_synthesis_snapshot',{player_id:3});t.event('dota_player_update_selected_unit',{PlayerID:2});assert.equal(t.queued(),0);assert.equal(t.counts.binds,0);
// A native slot rebuilt without identity metadata is still recovered by selection events.
const replacement=t.newSlot(0);t.select(20);for(let i=0;i<1000;i++)t.event('dota_player_update_selected_unit',{PlayerID:0});assert.equal(t.queued(),1);t.advance(0);assert.equal(typeof replacement.events.onmouseover,'function');replacement.events.onmouseover();assert.equal(t.nodes.CustomInventoryItemTitle.text,'查看玩家物品','scope is actual displayed unit, even another owner');
t.advance(100);t.items[20]=[];t.emit('survival_inventory_item_identity','200',{removed:1});t.advance(0);assert(t.nodes.CustomInventoryItemTooltip.classes.has('Hidden'),'hovered item removal hides old tooltip even after native slot is empty');
// Newly replicated own slot keys and queued selection switches use current bindings.
t.items[20]=[201];t.emit('survival_inventory_item_identity','201',{content_id:'new_item'});t.data.survival_item_tooltips.new_item={displayname:'新道具'};t.advance(0);replacement.events.onmouseover();assert.equal(t.nodes.CustomInventoryItemTitle.text,'新道具');t.advance(100);
t.emit('survival_inventory_item_identity','201',{content_id:'new_item'});t.select(10);t.event('dota_player_update_query_unit',{PlayerID:0});t.advance(0);replacement.events.onmouseover();assert.equal(t.nodes.CustomInventoryItemTitle.text,'最终道具','queued callbacks re-evaluate latest selection');t.advance(100);
const old=api.CacheInspect().counts.recovered;t.reload();t.advance(1100);t.emit('survival_inventory_item_identity','100',{content_id:'own_item'});t.advance(0);assert.equal(api.CacheInspect().counts.recovered,old,'superseded contexts do no native recovery');
assert(api.CacheInspect().counts.coalesced>0);
console.log('INVENTORY_TOOLTIP_BROADCAST_SCOPE_PASS: 1000 foreign keys=0 tasks/binds; 1000 own keys=1 recovery; final hover data/upgrade rows, owner-scoped synthesis, native slot rebuild, spectated inventory, removal/new key/latest selection and context reload');

const delayed=setup();delayed.event('dota_player_update_selected_unit',{PlayerID:0});delayed.advance(0);const laterImage=delayed.lateImage(0);assert.equal(laterImage.events.onmouseover,undefined);delayed.advance(210);assert.equal(typeof laterImage.events.onmouseover,'function','bounded trailing recovery binds native image children created after the first frame');laterImage.events.onmouseover();assert.equal(delayed.nodes.CustomInventoryItemTitle.text,'本地物品');
console.log('INVENTORY_NATIVE_LATE_CHILD_PASS: trailing recovery is bounded and binds later native image children');
