'use strict';
// Actual production refresh callback; synthetic native objects/counters only.
// No Dota, GUI, source writes, native elapsed-time or FPS claims.
const assert=require('node:assert/strict');
const {setup}=require('./test_combat_stats_callbacks.cjs');

function fixture(noise=0){
 const t=setup(),P=t.Panel,meters={rootTraverse:0,visits:0,parent:0,children:0,valid:0,writes:0};
 const methods={FindChildTraverse:P.prototype.FindChildTraverse,GetParent:P.prototype.GetParent,
  GetChildCount:P.prototype.GetChildCount,IsValid:P.prototype.IsValid};
 P.prototype.FindChildTraverse=function(id){meters.visits++;if(this===t.root)meters.rootTraverse++;return methods.FindChildTraverse.call(this,id);};
 for(const [method,key]of [['GetParent','parent'],['GetChildCount','children'],['IsValid','valid']]){
  P.prototype[method]=function(...args){meters[key]++;return methods[method].apply(this,args);};
 }
 const elements=new P('HUDElements',t.root),lower=new P('lower_hud',elements),center=new P('center_with_stats',lower),block=new P('center_block',center);
 const branch=new P('AbilitiesAndStatBranch',block),abilities=new P('abilities',branch),stat=new P('StatBranch',branch);
 const inventory=new P('inventory',block),slot=new P('inventory_slot_6',inventory);
 const queryUnit=new P('QueryUnit',elements),query=new P('QueryContainer',queryUnit);
 for(const panel of [branch,abilities,stat,slot]){
  const native=panel.style;panel.style=new Proxy(native,{set(target,key,value){meters.writes++;target[key]=value;return true;}});
 }
 const unrelated=new P('UnrelatedDashboard',t.root);for(let i=0;i<noise;i++)new P('Noise'+i,unrelated);
 function reset(){for(const key of Object.keys(meters))meters[key]=0;}
 function tick(){t.api.refreshAbilities();t.jobs.clear();}
 function warm(){tick();tick();reset();}
 return {t,P,meters,elements,lower,center,block,branch,abilities,stat,inventory,slot,query,unrelated,reset,tick,warm};
}

const costs=[];
for(const noise of [0,10000]){
 const f=fixture(noise);f.warm();const traces=[];
 for(let n=0;n<20;n++){f.reset();f.tick();traces.push({...f.meters});}
 assert(traces.every(x=>x.rootTraverse===0),'Missing IDs must be retained as negative hits');
 assert(traces.every(x=>x.visits===0),'Stable inventory/ability lookups must also avoid subtree searches');
 assert(traces.every(x=>x.writes===0),'Known deferred visibility must not be rewritten unchanged');
 costs.push({unrelated_nodes:noise,stable_ticks:20,one_tick:traces[0]});
 assert(traces.every(x=>JSON.stringify(x)===JSON.stringify(traces[0])));
}
assert.deepEqual(costs[0].one_tick,costs[1].one_tick,'Stable native bridge cost must not grow with full HUD N');

// Completely missing native roots stay quiet, then recover on a real root child.
{
 const t=setup(),root=t.root,original=root.FindChildTraverse;let roots=0;
 root.FindChildTraverse=function(id){roots++;return original.call(this,id);};
 t.api.refreshAbilities();t.api.refreshAbilities();roots=0;
 for(let n=0;n<10;n++)t.api.refreshAbilities();assert.equal(roots,0);
 const elements=new t.Panel('HUDElements',root),branch=new t.Panel('AbilitiesAndStatBranch',elements);
 new t.Panel('abilities',branch);const late=new t.Panel('StatBranch',branch);
 t.api.refreshAbilities();assert.equal(late.style.visibility,'collapse');assert(roots>0);
 roots=0;t.api.refreshAbilities();assert.equal(roots,0);
}

// Real creation below a watched native container expires negative entries.
{
 const f=fixture();f.warm();const late=new f.P('AghanimShard',f.block);
 f.tick();assert.equal(late.style.visibility,'collapse');assert(f.meters.rootTraverse>0);
 f.reset();f.tick();assert.equal(f.meters.rootTraverse,0);
 const vertical=new f.P('QueryVertical',f.query);f.tick();assert(f.meters.rootTraverse>0);
 f.reset();f.tick();assert.equal(f.meters.rootTraverse,0);
}

// Same child count, old object alive: identity/parent checks still invalidate.
{
 const f=fixture();f.warm();const old=f.stat;
 old.SetParent(new f.P('Detached'));
 const replacement=new f.P('StatBranch',f.branch);old.style.visibility='visible';
 f.tick();assert.equal(replacement.style.visibility,'collapse');assert.equal(old.style.visibility,'visible');
 f.reset();f.tick();assert.equal(f.meters.rootTraverse,0);
 replacement.alive=false;f.branch.children=f.branch.children.filter(p=>p!==replacement);
 const next=new f.P('StatBranch',f.branch);f.tick();assert.equal(next.style.visibility,'collapse');
 f.reset();f.tick();assert.equal(f.meters.rootTraverse,0);
}

// Inventory aliases retain their original inventory scope despite duplicate IDs.
{
 const f=fixture();const duplicate=new f.P('inventory_slot_6',f.unrelated);duplicate.style.visibility='visible';
 f.warm();assert.equal(f.slot.style.visibility,'collapse');assert.equal(duplicate.style.visibility,'visible');
 f.inventory.SetParent(new f.P('DetachedInventory'));
 const inventory=new f.P('inventory',f.block),lateSlot=new f.P('inventory_slot_6',inventory);
 f.tick();assert.equal(lateSlot.style.visibility,'collapse');
 f.reset();f.tick();assert.equal(f.meters.rootTraverse,0);
}

// An existing nested wrapper can gain a slot without changing inventory.count.
{
 const f=fixture();f.slot.SetParent(new f.P('DetachedOldSlot'));
 const wrapper=new f.P('InventoryItems',f.inventory);f.warm();
 const late=new f.P('inventory_slot_6',wrapper);f.reset();f.tick();
 assert.equal(late.style.visibility,'collapse');assert.equal(late.hittest,false);
 assert.equal(f.meters.rootTraverse,0,'Nested inventory rebuild stays scoped; no full HUD lookup');
 f.reset();f.tick();assert.equal(f.meters.rootTraverse,0);assert.equal(f.meters.visits,0);
 const artwork=new f.P('DynamicItemArtwork',late);new f.P('LargeTooltip',artwork);
 f.reset();f.tick();assert.equal(f.meters.rootTraverse,0);assert.equal(f.meters.visits,0);
}

// Reparented context selects a new root while the old root remains valid.
{
 const f=fixture();f.warm();const old=f.stat;old.style.visibility='visible';
 const root=new f.P('FreshHud');f.t.context.SetParent(root);
 const branch=new f.P('AbilitiesAndStatBranch',root);new f.P('abilities',branch);const fresh=new f.P('StatBranch',branch);
 f.tick();assert.equal(fresh.style.visibility,'collapse');assert.equal(old.style.visibility,'visible');
}

// An ordinary selection alone is not a native-container rebuild.
{
 const f=fixture();f.warm();f.t.api.selectionEvent('selected_unit_event',{PlayerID:0});
 f.reset();f.tick();assert.equal(f.meters.rootTraverse,0);
}

// No retained asynchronous callback may restart lookup after context shutdown.
{
 const f=fixture();f.tick();
 // tick clears its scheduled task; explicitly obtain a real production task.
 f.t.api.refreshAbilities();const retained=[...f.t.jobs.values()][0].fn;
 f.t.api.shutdown('lookup_test');f.reset();retained();
 assert.equal(f.meters.rootTraverse,0);assert.equal(f.t.jobs.size,0);
}
console.log(JSON.stringify({status:'COMBAT_HUD_LOOKUP_LIFECYCLE_PASS',scope:'synthetic production-function call counts, not native FPS',costs,
 cases:['negative stable','scale independence','late native container','samecount alive replacement','invalid known leaf','inventory scope','new root','selection reuse','shutdown old callback']}));
