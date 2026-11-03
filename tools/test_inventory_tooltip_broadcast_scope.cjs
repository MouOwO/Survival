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

// Actual v2 tooltip: dynamic values reuse the selected compact lane. A timer
// exists only for the one visible item; it never walks slots or renders art.
const live=setup();let growth={count:0,target:200,growth_attack:0},reads=0,writes=0,art=0,nativeHides=0;
live.cfg.HandoffCombat={ReadWeaponGrowth:(unit,content)=>unit===10&&content==='own_item'?growth:null};
live.data.survival_weapon_snapshot[0]={version:2,main_hand_context:{content_id:'own_item',stage_attack_target:200,is_max_level:0,progress_per_attack:3,forging_hammer_count:2,native_charge_counter:0},tooltip_view_model:{items:{own_item:{quantity:1,fields:[{label:'当前进度',value:'stale'}]}}}};
live.hover(0);live.advance(100);
function dynamicRows(){return JSON.parse(JSON.stringify(live.nodes.CustomInventoryItemFields.__fieldRows.filter(x=>x.visible).map(x=>[x.__left.text,x.__right.text])));}
assert.deepEqual(dynamicRows(),[['当前进度','0 / 200'],['剩余进度','200'],['每次攻击进度','+3'],['锻造锤','2 / 4']]);
for(const p of live.all){let text=p.text,visible=p.visible;Object.defineProperty(p,'text',{configurable:true,get:()=>text,set:v=>{writes++;text=v;}});Object.defineProperty(p,'visible',{configurable:true,get:()=>visible,set:v=>{writes++;visible=v;}});const set=p.SetImage;p.SetImage=function(...args){art++;return set.apply(this,args);};}
const getSlot=live.env.Entities.GetItemInSlot;live.env.Entities.GetItemInSlot=function(...args){reads++;return getSlot(...args);};
live.env.$.DispatchEvent=()=>nativeHides++;
const beforeBindings=live.counts.binds;live.advance(100000);
assert.equal(writes,0);assert.equal(art,0);assert.equal(nativeHides,0);assert.equal(live.counts.binds,beforeBindings);assert.equal(reads,1000,'one active slot read per visible tick, no six-slot scan');
growth={count:7,target:200,growth_attack:.30000000000000004};live.advance(100);
assert(dynamicRows().some(x=>x[0]==='当前进度'&&x[1]==='7 / 200'));assert(dynamicRows().some(x=>x[0]==='累计成长攻击'&&x[1]==='+0.3'));
assert.equal(art,0);assert.equal(nativeHides,0);assert.equal(live.counts.binds,beforeBindings);
const stoppedReads=reads;live.nodes.inventory_slot_0.events.onmouseout();live.advance(1000);assert.equal(reads,stoppedReads,'closed tooltip has no polling');
// Kill progress comes only from the explicit native-remaining path. A zero
// charge for a different weapon must not be mistaken for completed progress.
let charges=150,chargeReads=0;live.env.Items={GetCurrentCharges:item=>{assert.equal(item,100);chargeReads++;return charges;}};
live.data.survival_weapon_snapshot[0].main_hand_context.native_charge_counter=1;growth={count:999,target:200,growth_attack:0};live.hover(0);live.advance(100);
assert(dynamicRows().some(x=>x[0]==='当前进度'&&x[1]==='50 / 200'));charges=0;live.advance(100);assert(dynamicRows().some(x=>x[0]==='当前进度'&&x[1]==='200 / 200'));
live.data.survival_weapon_snapshot[0].main_hand_context.native_charge_counter=0;growth={count:12,target:200,growth_attack:0};live.hover(0);const oldChargeReads=chargeReads;live.advance(100);assert.equal(chargeReads,oldChargeReads);assert(dynamicRows().some(x=>x[0]==='当前进度'&&x[1]==='12 / 200'));
live.data.survival_weapon_snapshot[0].main_hand_context.is_max_level=1;live.hover(0);assert(dynamicRows().some(x=>x[0]==='当前进度'&&x[1]==='MAX'));assert(!dynamicRows().some(x=>x[0]==='剩余进度'||x[0]==='每次攻击进度'));
live.select(20);live.advance(100);assert(live.nodes.CustomInventoryItemTooltip.classes.has('Hidden'));const noSlotReads=reads;live.advance(1000);assert.equal(reads,noSlotReads);
live.data.survival_inventory_item_identity[200]={content_id:'own_item'};live.hover(0);assert.equal(dynamicRows().length,0,'spectated unit must not borrow local growth metadata');
const beforeDisposeReads=reads;live.cfg.SurvivalInventoryTooltip.DisposeTooltip();live.advance(1000);assert.equal(reads,beforeDisposeReads);
console.log('INVENTORY_GROWTH_PASS:1000 stable visible ticks=0 writes/art/hides/rebinds,1slot/tick;closed0;exact progress/growth,killcharges,MAX,spectated/disposed guards');

// Compare the actual display formatter with Lua5.1 tostring, not a second JS
// approximation of the former text. No engine, player or gameplay IO.
const cp=require('node:child_process'),numbers=[0,1,.30000000000000004,1234.567890123456,1e14,1e-5,1e-20,99999999999999.5];
const lua='package.path="scripts/vscripts/?.lua;"..package.path;local x={'+numbers.join(',')+'};local r={};for i,n in ipairs(x)do r[i]=tostring(n)end;io.write(require("core/json_encoder").encode(r))';
const expected=JSON.parse(cp.execFileSync('C:/Program Files/lua/bin/lua5.1.exe',['-e',lua],{encoding:'utf8'}));
const formatter={};vm.runInNewContext(source.slice(source.indexOf('    function luaNumber('),source.indexOf('    function growthFields(')),formatter);
assert.deepEqual(numbers.map(n=>formatter.luaNumber(n)),expected);
console.log('INVENTORY_LUA_NUMBER_TEXT_PASS actual Lua tostring includes scientific exponents and floating growth');
