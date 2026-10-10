// Exercise the real combat module against native-style normalized getters and
// reused/rebuilt AbilityN panels; count clears, not copies of the implementation.
const assert=require('node:assert/strict');
const {setup}=require('./test_combat_stats_callbacks.cjs');

function fixture(){
 const slots=new Map([[7,[100,101]]]),names=new Map([[100,'mock_active'],[101,'mock_passive']]);
 const passive=new Set([101]),requests=[];let clears=0,reads=0;
 const t=setup({portrait:true,entities:{GetAbility:(unit,slot)=>{reads++;return (slots.get(unit)||[])[slot]??-1;}},
  abilities:{GetAbilityName:id=>names.get(id)||'',IsHidden:()=>false,
   GetBehavior:id=>passive.has(id)?2:4,IsPassive:id=>passive.has(id)},
  events:{SendCustomGameEventToServer:(name,payload)=>requests.push({name,payload})}});
 let abilities=new t.Panel('abilities',t.root);const panels=[];
 function mount(index){
  const panel=new t.Panel('Ability'+index,abilities),anchor=new t.Panel('AbilityButton',panel);
  anchor.point={x:100+index*140,y:900};new t.Panel('AbilityImage',anchor);
  const hotkey=new t.Panel('HotkeyContainer',panel);hotkey.values.opacity='0.35';
  // Getter normalization is what Panorama's native bridge can expose.
  hotkey.style=new Proxy(hotkey.values,{get:(o,k)=>k==='opacity'&&o[k]==='0'?'0.0':o[k],
   set:(o,k,v)=>{o[k]=v;return true;}});
  panels[index]=panel;return panel;
 }
 mount(0);mount(1);
 function metadata(unit){t.runtime['unit:'+unit]={owner_entindex:unit,ability_count:(slots.get(unit)||[]).length};}
 metadata(7);t.cfg.HandoffClearHotkey=()=>clears++;
 function key(index){const p=panels[index].FindChildTraverse('SurvivalAbilityHotkey');return p&&p.values.visibility!=='collapse'?p.text:'';}
 function clearCount(){return clears;}
 function replaceAbilities(){
  const old=abilities;old.alive=false;
  function dispose(panel){panel.alive=false;panel.children.forEach(dispose);}
  old.children.forEach(dispose);t.root.children=t.root.children.filter(p=>p!==old);
  abilities=new t.Panel('abilities',t.root);panels.length=0;return abilities;
 }
 return {t,slots,names,passive,abilities,panels,mount,replaceAbilities,metadata,key,clearCount,requests,abilityReads:()=>reads};
}

const f=fixture();f.t.api.refreshHotkeys(false);
assert.equal(f.key(0),'Q');assert.equal(f.key(1),'','passive key remains hidden');
const initial=f.clearCount(),initialReads=f.abilityReads();
for(let i=0;i<20;i++){f.t.api.refreshVitalsTick();f.t.api.refreshAbilities();}
assert.equal(f.clearCount(),initial,'stable .25s/1s recovery checks never clear and rebind all native slots');
assert(f.abilityReads()>initialReads,'ability handles are read again instead of cached across ticks');
assert.equal(f.t.jobs.size,40,'keep each original timer chain; no new polling');
assert.equal(f.requests.length,0,'stable hotkey timers do not add a server request');
f.t.api.refreshHotkeys(true);assert(f.clearCount()>initial,'explicit forced refresh still rebinds');
const stable=f.clearCount();

// Runtime state still changes on a cache hit, without clearing correct keys.
f.t.runtime[100]={ability_entindex:100,owner_entindex:7,available:0,status_text:'locked'};
f.t.api.refreshVitalsTick();assert.equal(f.panels[0].classes.DOTADisabled,true);
f.t.runtime[100].available=1;f.t.api.refreshAbilities();assert.equal(f.panels[0].classes.DOTADisabled,false);
assert.equal(f.clearCount(),stable,'runtime state alone does not require hotkey rebinding');

// The cache checks live opacity and interaction, including exact zero only.
const nativeKey=f.panels[0].FindChildTraverse('HotkeyContainer');
for(const opacity of ['', 'bad', '1e-8', '0.35']){
 nativeKey.values.opacity=opacity;const before=f.clearCount();f.t.api.refreshHotkeys(false);
 assert(f.clearCount()>before,'unset/invalid/nonzero opacity must recover suppression: '+opacity);
 assert.equal(nativeKey.values.opacity,'0');
}
for(const opacity of ['0', '0.0', ' 0.000 ', '-0']){
 nativeKey.values.opacity=opacity;const before=f.clearCount();f.t.api.refreshHotkeys(false);
 assert.equal(f.clearCount(),before,'numeric zero remains a valid suppressed native key: '+opacity);
}
nativeKey.hittest=true;let before=f.clearCount();f.t.api.refreshVitalsTick();
assert(f.clearCount()>before);assert.equal(nativeKey.hittest,false,'interaction drift also invalidates');

// A same-ID replacement invalidates live labels/anchors despite a matching
// unit/ability signature; do not rely on an API object's identity for validity.
const old=f.panels[0];old.alive=false;old.children.forEach(p=>p.alive=false);
f.abilities.children=f.abilities.children.filter(p=>p!==old);const replacement=f.mount(0);
before=f.clearCount();f.t.api.refreshHotkeys(false);assert(f.clearCount()>before);
assert.equal(f.key(0),'Q');assert.strictEqual(replacement.FindChildTraverse('SurvivalAbilityHotkey').GetParent(),replacement.FindChildTraverse('AbilityButton'));
replacement.FindChildTraverse('SurvivalAbilityHotkey').SetParent(replacement);
before=f.clearCount();f.t.api.refreshAbilities();assert(f.clearCount()>before,'reparented label must recover its button anchor');
f.replaceAbilities();f.t.api.refreshVitalsTick();assert.equal(f.panels.length,0,'a rebuilt empty native HUD must remain pending');
f.mount(0);f.mount(1);before=f.clearCount();f.t.api.refreshAbilities();assert(f.clearCount()>before);
assert.equal(f.key(0),'Q');assert.equal(f.key(1),'','new native abilities root is recovered without reviving a passive key');

// Selection/learning/removal still changes the binding; native child arrival
// later than selection remains pending until a subsequent recovery succeeds.
f.t.select(8,'npc_dota_hero_test');f.slots.set(8,[102]);f.names.set(102,'mock_next');f.metadata(8);
f.panels[1].values.visibility='collapse';f.t.api.refreshVitalsTick();assert.equal(f.key(0),'Q');
f.slots.set(8,[102,103]);f.names.set(103,'mock_learned');f.metadata(8);
f.panels[1].values.visibility='collapse';f.t.api.refreshHotkeys(false);
assert.equal(f.key(0),'','incomplete native layout clears stale keys while retry stays pending');
f.panels[1].values.visibility='visible';f.t.api.refreshAbilities();assert.equal(f.key(1),'W','late native child/layout recovers learned ability key');
f.slots.set(8,[102]);f.metadata(8);f.panels[1].values.visibility='collapse';f.t.api.refreshVitalsTick();assert.equal(f.key(1),'','removed ability clears old key');
f.slots.set(8,[]);f.metadata(8);f.panels[0].values.visibility='collapse';f.t.api.refreshAbilities();
assert.equal(f.key(0),'');before=f.clearCount();f.t.api.refreshVitalsTick();assert.equal(f.clearCount(),before,'stable zero-ability selection does not rebind');
f.t.select(-1);f.t.api.refreshVitalsTick();before=f.clearCount();f.t.api.refreshAbilities();assert.equal(f.clearCount(),before,'stable invalid selection also stays cleared');

// Research slot metadata changes the key even though handles/order stay fixed.
const r=fixture();r.slots.set(7,[100]);r.names.set(100,'ability_research_fixture');r.metadata(7);r.panels[1].values.visibility='collapse';
r.t.runtime[100]={ability_entindex:100,owner_entindex:7,research_slot_order:1,research_building_id:'building_research_lab'};
r.t.api.refreshHotkeys(false);assert.equal(r.key(0),'Q');
r.t.runtime[100].research_slot_order=2;r.t.api.refreshVitalsTick();assert.equal(r.key(0),'W');
r.passive.add(100);r.t.api.refreshAbilities();assert.equal(r.key(0),'','active to passive clears key');
r.passive.delete(100);r.t.api.refreshAbilities();assert.equal(r.key(0),'W','passive to active restores runtime slot key');

// Existing five short selection retries continue to use the live checker; an
// in-flight retry cannot leave a key from an earlier selection on reused nodes.
const q=fixture();q.t.api.refreshHotkeys(false);q.t.api.beginNameTransition('test');
q.t.select(9,'npc_dota_hero_test');q.slots.set(9,[104]);q.names.set(104,'mock_changed');q.metadata(9);q.panels[1].values.visibility='collapse';
for(const id of [...q.t.jobs.keys()])q.t.run(id);
assert.equal(q.key(0),'Q');assert.equal(q.key(1),'');
assert(q.requests.length>0);assert(q.requests.every(r=>r.payload.entindex===9),'in-flight retry requests current selected unit only');
q.t.api.shutdown('test');assert.equal(q.t.jobs.size,0,'context disposal still cancels outstanding timers');
console.log('ABILITY_HOTKEY_REFRESH_CACHE_PASS: normalized native zero, stable timer clears avoided, live runtime/passive/research keys, selection/learning/removal, late/replaced/reparented native panels and transition disposal');
