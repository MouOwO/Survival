"use strict";
// Real production functions; synthetic native bridge counts, not native FPS.
const assert=require('node:assert/strict');
const {setup}=require('./test_combat_stats_callbacks.cjs');
function fixture(options={}){
 const count={ability:0,name:0,hidden:0,behavior:0,passive:0,position:0,runtime:0},requests=[];
 const t=setup({entities:{GetAbility:(unit,slot)=>{count.ability++;return slot<4?100+slot:-1;}},
  abilities:{GetAbilityName:id=>{count.name++;return 'ability_test_'+id;},IsHidden:()=>{count.hidden++;return false;},
   GetBehavior:()=>{count.behavior++;return 16;},IsPassive:()=>{count.passive++;return false;}},
  events:{SendCustomGameEventToServer:(name,payload)=>requests.push({name,payload})}});
 t.Panel.prototype.SetPanelEvent=function(){};
 t.Panel.prototype.BHasClass=function(name){return !!(this.classNames&&this.classNames.has(name));};
 const base=t.Panel.prototype.GetPositionWithinWindow;
 t.Panel.prototype.GetPositionWithinWindow=function(){count.position++;return base.call(this);};
 const host=new t.Panel('abilities',new t.Panel('AbilitiesAndStatBranch',t.root)),panels=[];
 if(options.noChildApi){host.GetChildCount=undefined;host.GetChild=undefined;}
 for(let i=0;i<4;i++){
  const panel=new t.Panel('Ability'+i,host),anchor=new t.Panel('AbilityButton',panel);
  anchor.point={x:100+i*80,y:900};new t.Panel('AbilityImage',anchor);new t.Panel('HotkeyContainer',panel);panels.push(panel);
  let value={ability_entindex:100+i,owner_entindex:7,available:1,prerequisite_met:1};
  Object.defineProperty(t.runtime,100+i,{get(){count.runtime++;return value;},set(v){value=v;},configurable:true});
 }
 for(const unit of [7,8])t.runtime['unit:'+unit]={owner_entindex:unit,ability_count:4};
 t.select(7);t.api.refreshHotkeys(false);t.api.refreshHotkeys(false);
 const reset=()=>{Object.keys(count).forEach(k=>count[k]=0);};reset();
 return {t,count,requests,panels,reset};
}
function drain(t){let n=0;while(t.jobs.size){assert(n++<12,'bounded chain must finish');t.run([...t.jobs.keys()][0]);}return n;}

const burst=fixture(),old=[];
for(let i=0;i<40;i++){
 burst.t.select(i%2?7:8);burst.t.api.selectionEvent('selected_unit_event',{PlayerID:0});
 assert.equal(burst.t.jobs.size,1);assert.equal(burst.t.api.ownedJobCount(),1);
 old.push([...burst.t.jobs.values()][0].fn);
}
const before={...burst.count};for(const fn of old.slice(0,-1))fn();assert.deepEqual(burst.count,before,'cancelled native callbacks perform no work');
assert.equal(drain(burst.t),5,'latest identity retains all five late native checks');
assert.equal(burst.requests.length,1);assert.equal(burst.requests[0].payload.entindex,7);
assert.equal(burst.t.api.ownedJobCount(),0);

const duplicate=fixture();duplicate.t.api.selectionEvent('selected_unit_event',{PlayerID:0});
duplicate.t.run([...duplicate.t.jobs.keys()][0]);duplicate.reset();
for(let i=0;i<100;i++)duplicate.t.api.selectionEvent('selected_unit_event',{PlayerID:0});
assert.equal(duplicate.t.jobs.size,1);assert.equal(duplicate.t.api.ownedJobCount(),1);
assert.deepEqual(duplicate.count,{ability:0,name:0,hidden:0,behavior:0,passive:0,position:0,runtime:0},'dedup happens before native/index work');
duplicate.t.api.refreshSelectionHUD();
assert.equal(duplicate.t.jobs.size,1,'later topnav owner shares the running selection chain');
assert.equal(duplicate.count.ability,0);
assert.equal(drain(duplicate.t),4);assert.equal(duplicate.requests.length,1);
duplicate.t.api.selectionEvent('selected_unit_event',{PlayerID:0});assert.equal(drain(duplicate.t),5,'a later real event retains a fresh bounded native repair window');
assert.equal(duplicate.requests.length,1,'same entity native repair does not force a new snapshot');

const stable=fixture();for(let i=0;i<100;i++)stable.t.api.refreshHotkeys(false);
assert.equal(stable.count.position,0,'stable mapping never reprojects/sorts the native row');
for(const key of ['ability','name','hidden','behavior','passive','runtime'])assert.equal(stable.count[key],400,key+': one current read per actual ability/pass');
const stableCounts={...stable.count};stable.reset();
for(let i=0;i<4;i++)stable.t.api.refreshVitalsTick();
assert.equal(stable.count.ability,0,'250ms vitals cannot start a second ability scan chain');
stable.t.api.shutdown('vitals_done');assert.equal(stable.t.jobs.size,0);

const shared=fixture();shared.t.api.withAbilityLookup(function(){
 const a=shared.t.api.nativeEntries(7),b=shared.t.api.nativeEntries(7);
 assert.strictEqual(a,b);shared.t.api.refreshHotkeys(false);
});
assert.equal(shared.count.ability,4);assert.equal(shared.count.runtime,4);
shared.t.api.refreshHotkeys(false);assert.equal(shared.count.ability,8,'snapshot expires at synchronous owner boundary');
shared.reset();shared.panels[0].FindChildTraverse('AbilityButton').actuallayoutwidth=200;
shared.t.api.refreshHotkeys(false);assert.equal(shared.count.position,4,'real size change reprojects the current four slots once');
shared.reset();shared.t.api.refreshHotkeys(false);assert.equal(shared.count.position,0);
shared.panels[0].FindChildTraverse('AbilityButton').point.x=1000;
shared.t.api.refreshHotkeys(true);assert.equal(shared.count.position,4,'explicit force rediscovers moved same-size native anchors');
assert.equal(shared.panels[1].FindChildTraverse('SurvivalAbilityHotkey').text,'Q');
shared.reset();const error=Error('owner failed');
assert.throws(()=>shared.t.api.withAbilityLookup(()=>{shared.t.api.nativeEntries(7);throw error;}),value=>value===error);
shared.t.api.nativeEntries(7);assert.equal(shared.count.ability,8,'throwing owner cannot retain its synchronous snapshot scope');

const fallback=fixture({noChildApi:true});
fallback.panels[0].alive=false;
fallback.panels[0].FindChildTraverse=function(){throw Error('released native slot');};
fallback.panels[0].GetParent=function(){throw Error('released native parent');};
assert.doesNotThrow(()=>fallback.t.api.refreshHotkeys(false),'fallback cache validates panel before native anchor or parent lookup');

const queued=fixture();for(let i=0;i<100;i++)queued.t.api.queueAbilityRefresh();assert.equal(queued.t.jobs.size,1);
const cancelled=[...queued.t.jobs.values()][0].fn;queued.t.api.flushAbilityRefresh();assert.equal(queued.t.jobs.size,0);
const calls=queued.count.ability;cancelled();assert.equal(queued.count.ability,calls,'already consumed queued refresh cannot execute twice');
queued.t.api.queueAbilityRefresh();queued.t.api.shutdown('dispose');assert.equal(queued.t.jobs.size,0);assert.equal(queued.t.api.ownedJobCount(),0);

const prequeued=fixture();prequeued.t.api.refreshSelectionHUD();assert.equal(prequeued.t.jobs.size,1);
prequeued.t.api.selectionEvent('selected_unit_event',{PlayerID:0});assert.equal(prequeued.t.jobs.size,1,'selection replaces an earlier topnav ability job');
prequeued.t.run([...prequeued.t.jobs.keys()][0]);assert.equal(prequeued.count.ability,4,'first frame has one ability pass');
prequeued.t.api.refreshSelectionHUD();assert.equal(prequeued.t.jobs.size,1,'topnav after first frame cannot append duplicate pass');
assert.equal(drain(prequeued.t),4);

const uncancellable=fixture();delete uncancellable.t.panorama.CancelScheduled;
uncancellable.t.api.selectionEvent('selected_unit_event',{PlayerID:0});const staleId=[...uncancellable.t.jobs.keys()][0];
uncancellable.t.select(8);uncancellable.t.api.selectionEvent('selected_unit_event',{PlayerID:0});
assert.equal(uncancellable.t.api.ownedJobCount(),1);const safeBefore={...uncancellable.count};
uncancellable.t.run(staleId);assert.deepEqual(uncancellable.count,safeBefore,'missing native cancellation API still makes old callbacks inert');
assert.equal(drain(uncancellable.t),5);assert.equal(uncancellable.requests.length,1);

const jobs=fixture();const ids=[];for(let i=0;i<1000;i++)ids.push(jobs.t.api.scheduleActive(1,()=>{}));
for(let i=0;i<ids.length;i+=2)jobs.t.api.cancelActive(ids[i]);assert.equal(jobs.t.api.ownedJobCount(),500);
jobs.t.api.shutdown('many_owned_jobs');assert.equal(jobs.t.api.ownedJobCount(),0);assert.equal(jobs.t.jobs.size,0);
console.log(JSON.stringify({status:'COMBAT_SELECTION_COALESCING_PASS_SYNTHETIC',alternating_events:40,maximum_selection_callbacks:1,latest_retry_count:5,same_identity_events:100,duplicate_native_work:0,stable_passes:100,stable_native_counts:stableCounts,stable_scene_geometry_reads:0,owned_jobs_cancelled:1000,native_fps:'unmeasured'}));
