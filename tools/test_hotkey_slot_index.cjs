// Read-only targeted regression through the production combat functions.
const assert=require('node:assert/strict');
const {setup}=require('./test_combat_stats_callbacks.cjs');
const requests=[];let clears=0;
const t=setup({portrait:true,
 entities:{GetAbility:(unit,slot)=>unit===7&&slot<2?100+slot:-1},
 abilities:{GetAbilityName:id=>'ability_index_fixture_'+id,IsHidden:()=>false,GetBehavior:()=>16,IsPassive:()=>false},
 config:{HandoffClearHotkey:()=>clears++},
 events:{SendCustomGameEventToServer:(name,payload)=>requests.push({name,payload})}});
t.select(7,'npc_survival_builder_proxy');
t.runtime['unit:7']={owner_entindex:7,ability_count:2};
for(let i=0;i<2;i++)t.runtime[100+i]={owner_entindex:7,ability_entindex:100+i,builder_slot_order:i+1,available:1,prerequisite_met:1};
t.Panel.prototype.SetPanelEvent=function(name,fn){this[name]=fn;};
t.Panel.prototype.BHasClass=function(name){return !!(this.classNames&&this.classNames.has(name));};
const branch=new t.Panel('AbilitiesAndStatBranch',t.root),queryBranch=new t.Panel('QueryVertical',t.root);
let main=new t.Panel('abilities',branch);
const query=new t.Panel('abilities',new t.Panel('AbilitiesHealthMana',queryBranch));
function mount(host,id,index,opacity='0.35'){
 const wrapper=new t.Panel('Wrapper_'+id,host),panel=new t.Panel(id,wrapper);
 const anchor=new t.Panel('AbilityButton',panel);anchor.point={x:600+index*80,y:920};
 new t.Panel('AbilityImage',anchor);const native=new t.Panel('HotkeyContainer',panel);
 native.values.opacity=opacity;native.hittest=true;native.hittestchildren=false;
 return {wrapper,panel,anchor,native};
}
let p0=mount(main,'Ability0',0),fake01=mount(main,'Ability01',1),p1=mount(main,'Ability1',1);
// Hidden wrappers and a high supported slot must still be checked/cleared.
let high=mount(main,'Ability63',63);high.panel.visible=false;high.wrapper.visible=false;
const beyond=mount(main,'Ability64',64);beyond.panel.visible=false;
const q0=mount(query,'Ability0',0),q63=mount(query,'Ability63',63);
q63.wrapper.visible=false;
const stale=new t.Panel('SurvivalAbilityHotkey',q0.anchor);stale.text='OLD';stale.values.visibility='visible';
const key=p=>{const label=p.panel.FindChildTraverse('SurvivalAbilityHotkey');return label&&label.values.visibility!=='collapse'?label.text:'';};
t.api.refreshHotkeys(false);
assert.equal(key(p0),'Q');assert.equal(key(p1),'W','canonical Ability1 is not shadowed by Ability01');
assert.equal(key(fake01),'','noncanonical IDs are not treated as an indexed native slot');
assert.equal(high.native.values.opacity,'0','Ability63 trailing placeholder is suppressed');
assert.equal(q0.native.values.opacity,'0');assert.equal(q63.native.values.opacity,'0','hidden query Ability63 also cleared');
assert.equal(stale.text,'');assert.equal(stale.values.visibility,'collapse');
assert.equal(beyond.native.values.opacity,'0.35','same upper bound 0..63 is preserved');
assert.equal(key(p0),'Q','main-tree key survives query-tree clearing in the same refresh');
let before=clears;t.api.refreshHotkeys(false);assert.equal(clears,before,'new labels are found on the next stable check');
q63.native.values.opacity='1';before=clears;t.api.refreshHotkeys(false);assert(clears>before,'query high-slot rewrite is detected');
assert.equal(q63.native.values.opacity,'0');assert.equal(key(p0),'Q');
high.native.values.opacity='1';before=clears;t.api.refreshHotkeys(false);assert(clears>before,'main high-slot rewrite is detected');
assert.equal(high.native.values.opacity,'0');
// Reparenting an existing label is repaired without a cross-refresh index.
const oldLabel=p1.panel.FindChildTraverse('SurvivalAbilityHotkey');oldLabel.SetParent(p1.panel);
t.api.refreshHotkeys(false);assert.equal(oldLabel.GetParent(),p1.anchor);assert.equal(key(p1),'W');
function dispose(p){p.alive=false;p.children.forEach(dispose);}
dispose(main);branch.children=branch.children.filter(p=>p!==main);
main=new t.Panel('abilities',branch);p0=mount(main,'Ability0',0);p1=mount(main,'Ability1',1);high=mount(main,'Ability63',63);high.panel.visible=false;
t.api.refreshHotkeys(false);assert.equal(key(p0),'Q');assert.equal(key(p1),'W');assert.equal(high.native.values.opacity,'0');
// Shutdown restores exactly the currently attached native nodes, not cached old ones.
t.api.shutdown('test_scoped_index');
assert.equal(p0.native.values.opacity,'0.35');assert.equal(p0.native.hittest,true);assert.equal(p0.native.hittestchildren,false);
assert.equal(q0.native.values.opacity,'0.35');assert.equal(q63.native.values.opacity,'0.35');
assert.equal(requests.length,0,'scoped lookups never issue network requests');

function queryFixture(withQuery){
 const f=setup({portrait:true,entities:{GetAbility:(unit,slot)=>unit===7&&slot===0?100:-1},
  abilities:{GetAbilityName:()=> 'ability_query_fixture',IsHidden:()=>false,GetBehavior:()=>16,IsPassive:()=>false},
  events:{SendCustomGameEventToServer:()=>{}}});
 f.select(7,'npc_survival_builder_proxy');f.runtime['unit:7']={owner_entindex:7,ability_count:1};
 f.runtime[100]={owner_entindex:7,ability_entindex:100,builder_slot_order:1,available:1,prerequisite_met:1};
 f.Panel.prototype.SetPanelEvent=function(name,fn){this[name]=fn;};
 f.Panel.prototype.BHasClass=function(name){return !!(this.classNames&&this.classNames.has(name));};
 function slot(host,id){
  const panel=new f.Panel(id,host),anchor=new f.Panel('AbilityButton',panel),native=new f.Panel('HotkeyContainer',panel);
  anchor.point={x:600,y:920};new f.Panel('AbilityImage',anchor);native.values.opacity='0.35';
  native.hittest=true;native.hittestchildren=false;
  return {panel,anchor,native};
 }
 const main=slot(new f.Panel('abilities',new f.Panel('AbilitiesAndStatBranch',f.root)),'Ability0');
 function addQuery(){
  const branch=new f.Panel('QueryVertical',f.root),host=new f.Panel('abilities',new f.Panel('AbilitiesHealthMana',branch));
  const q=slot(host,'Ability0'),label=new f.Panel('SurvivalAbilityHotkey',q.anchor);
  label.text='STALE';label.values.visibility='visible';return {...q,branch,label};
 }
 return {f,main,addQuery,query:withQuery?addQuery():null};
}
// A query tree missing through every bounded selection retry is rediscovered
// by a later real query/selection event, without adding perpetual missing probes.
const late=queryFixture(false);
late.f.api.beginNameTransition('initial_missing_query');
for(const id of [...late.f.jobs.keys()])late.f.run(id);
assert.equal(late.f.jobs.size,0,'the original bounded retry window has ended');
const lateQuery=late.addQuery();
for(let i=0;i<10;i++)late.f.api.refreshHotkeys(false);
assert.equal(lateQuery.native.values.opacity,'0.35','regular polling does not endlessly search for a missing query root');
assert.equal(lateQuery.label.text,'STALE');
late.f.api.selectionEvent('query_unit_event',{PlayerID:0});
assert(late.f.jobs.size>0,'a new query event starts the existing bounded recovery window');
for(const id of [...late.f.jobs.keys()])late.f.run(id);
assert.equal(lateQuery.native.values.opacity,'0');assert.equal(lateQuery.label.text,'');
assert.equal(lateQuery.label.values.visibility,'collapse');
assert.equal(late.main.panel.FindChildTraverse('SurvivalAbilityHotkey').text,'Q','query recovery preserves main-tree binding');
late.f.api.shutdown('late_query_done');assert.equal(lateQuery.native.values.opacity,'0.35');

// An entire query ancestor branch can leave the active HUD while all its node
// handles remain valid. Parent-chain validation must find the new same-ID tree.
const detached=queryFixture(true);detached.f.api.refreshHotkeys(false);
const oldQuery=detached.query;assert.equal(oldQuery.native.values.opacity,'0');
const detachedHost=new detached.f.Panel('DetachedHost');oldQuery.branch.SetParent(detachedHost);
assert.equal(oldQuery.branch.IsValid(),true);assert.equal(oldQuery.panel.IsValid(),true);
oldQuery.native.values.opacity='0.88';oldQuery.label.text='DETACHED';
const replacementQuery=detached.addQuery();
detached.f.api.refreshHotkeys(false);
assert.equal(replacementQuery.native.values.opacity,'0');assert.equal(replacementQuery.label.text,'');
assert.equal(replacementQuery.label.values.visibility,'collapse');
assert.equal(oldQuery.native.values.opacity,'0.88','detached valid tree is no longer treated as the active query HUD');
assert.equal(oldQuery.label.text,'DETACHED');
assert.equal(detached.main.panel.FindChildTraverse('SurvivalAbilityHotkey').text,'Q');
detached.f.api.shutdown('detached_query_done');assert.equal(replacementQuery.native.values.opacity,'0.35');
console.log('HOTKEY_SCOPED_INDEX_PASS: dual trees, slot63/canonical IDs, labels/rebuild, exact native-state restoration, late query after bounded retries and valid-but-detached ancestor replacement');
