'use strict';
// Production renderer with a fake bridge/clock. Native FPS and render worlds
// are deliberately not inferred from these logical residency/call counters.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const {setup}=require('./test_combat_stats_callbacks.cjs');
const catalog=fs.readFileSync('panorama/src/scripts/custom_game/monster_portrait_scenes.js','utf8');
const source=fs.readFileSync('panorama/src/scripts/custom_game/monster_portrait_renderer.js','utf8');
function fixture(extra=0){
 const t=setup({portrait:true});let now=1000,serial=0,originCalls=0;
 const events=new Map(),unsubscribed=[],counts={enumerations:0,parents:0,styleWrites:0};
 t.Panel.prototype.DeleteAsync=function(){
  const dispose=p=>{p.alive=false;p.children.forEach(dispose);};dispose(this);
  if(this.parent)this.parent.children=this.parent.children.filter(p=>p!==this);
 };
 t.Panel.prototype.BHasClass=function(name){return !!this.classNames?.has(name);};
 const parent=t.Panel.prototype.GetParent;
 t.Panel.prototype.GetParent=function(){counts.parents++;return parent.call(this);};
 t.panorama.RegisterEventHandler=(event,p,callback)=>{p[event]=callback;};
 const create=t.panorama.CreatePanel;
 t.panorama.CreatePanel=function(...args){
  const panel=create.apply(this,args),style=panel.style;
  panel.style=new Proxy(style,{set:(target,key,value)=>{counts.styleWrites++;target[key]=value;return true;}});
  return panel;
 };
 const object=Object.create(Object);
 object.keys=value=>{counts.enumerations++;return Object.keys(value);};
 const ctx={$:t.panorama,GameUI:{CustomUIConfig:()=>t.cfg},Date:{now:()=>now},Object:object,
  Game:{GetLocalPlayerID:()=>0},GameEvents:{
   Subscribe:(name,callback)=>{const id=++serial;events.set(id,{name,callback});return id;},
   Unsubscribe:id=>{assert(events.has(id));unsubscribed.push(id);events.delete(id);}},
  Entities:{GetAbsOrigin:()=>{originCalls++;return [now,0,0];}}};
 vm.runInNewContext(catalog,ctx);
 const seed=t.cfg.SurvivalMonsterPortraitScenes.monster_boss_rebirth_05_lucid_torment;
 for(let i=0;i<extra;i++)t.cfg.SurvivalMonsterPortraitScenes['synthetic_'+i]={...seed,
  map:'portraits/monster_'+i.toString(16).padStart(20,'0')+'_v1',modelFallback:false};
 vm.runInNewContext(source,ctx);
 const r=t.cfg.SurvivalMonsterPortraitRenderer;
 const scenes=()=>t.metrics.created.filter(p=>p.type==='DOTAScenePanel'&&p.panel.alive).map(p=>p.panel);
 const ready=value=>{const scene=value.scene||value;scene.AddClass('SceneLoaded');scene.parent.FindChildTraverse('Background').ImageLoaded();};
 const advance=ms=>now+=ms;
 const tick=()=>{now+=50;const id=[...t.jobs.keys()][0];assert(id!==undefined);t.run(id);};
 const event=(name='dota_player_update_selected_unit',player=0)=>{
  for(const item of [...events.values()])if(item.name===name)item.callback({PlayerID:player});
 };
 const sane=()=>{
  const state=r.Inspect();
  for(const key of ['cached','loaded','created','queued','visible','evictions','retries','failures'])assert(Number.isInteger(state[key])&&state[key]>=0,key);
  assert(state.cached<=4);assert(state.loaded<=state.cached);assert(state.visible<=2);assert(state.queued<=1);
  assert(scenes().length<=4,'only four logically live fake native scenes');
  return state;
 };
 for(const key of ['Prepare','Prewarm','Hide','Shutdown']){
  const original=r[key];r[key]=function(...args){const result=original.apply(this,args);sane();return result;};
 }
 const unique=[];for(const asset of Object.keys(t.cfg.SurvivalMonsterPortraitScenes))
  if(!unique.some(other=>t.cfg.SurvivalMonsterPortraitScenes[other].map===t.cfg.SurvivalMonsterPortraitScenes[asset].map))unique.push(asset);
 return {t,r,counts,events,unsubscribed,scenes,ready,advance,tick,event,sane,unique,originCalls:()=>originCalls};
}

const f=fixture(),{t,r}=f;
assert.equal(f.events.size,2,'two selection subscriptions, independent of catalog size');
for(let i=0;i<300;i++){f.advance(100);r.Prewarm(t.nativeHost());}
assert.equal(r.Inspect().created,0,'bare startup anchor allocates no catalog worlds');
assert.equal(t.jobs.size,0,'no recurring catalog polling while idle or moving');
assert.equal(f.originCalls(),0,'no selected-unit movement bridge for nonexistent background work');
const first=f.unique[0];r.Prewarm(t.nativeHost(),first);f.tick();
const cold=r.Prepare(t.overlay,first);assert(cold&&!cold.ready);
r.Hide();assert.equal(cold.scene.parent.values.visibility,'visible','selected loading world remains renderable behind cover');
f.ready(cold);const mounted=r.Prepare(t.overlay,first);assert(mounted.ready&&!mounted.presentable);
f.advance(99);assert(!r.Prepare(t.overlay,first).presentable);f.advance(1);assert(r.Prepare(t.overlay,first).presentable);
while(t.jobs.size)f.tick();assert.equal(r.Inspect().created,1);
for(const asset of f.unique.slice(1,4)){const value=r.Prepare(t.overlay,asset);f.ready(value);r.Prepare(t.overlay,asset);}
assert.equal(r.Inspect().cached,4);
const retained=r.Prepare(t.overlay,first).scene;
const second=r.Prepare(t.overlay,f.unique[4]);f.ready(second);r.Prepare(t.overlay,f.unique[4]);
assert.equal(r.Inspect().evictions,1);
assert.equal(r.Prepare(t.overlay,first).scene,retained,'touch updates LRU and preserves recent world');
const replaced=r.Prepare(t.overlay,f.unique[1]);assert(!replaced.ready,'least recent unprotected world was evicted');
f.ready(replaced);r.Prepare(t.overlay,f.unique[1]);

// Rapid explicit prewarm has a one-item pending queue, not a second catalog.
const q=fixture();q.r.Prewarm(q.t.nativeHost());
for(const asset of q.unique)q.r.Prewarm(q.t.nativeHost(),asset);
assert.equal(q.r.Inspect().queued,1);assert.equal(q.r.Inspect().created,0);
q.tick();assert.equal(q.r.Inspect().warming,q.unique.at(-1));
const paused=q.r.Inspect().warming;
const priority=q.r.Prepare(q.t.overlay,q.unique[0]);assert(priority&&!priority.ready);
assert.equal(q.r.Inspect().warming,q.unique[0]);assert.equal(q.r.Inspect().queued,0);
q.r.Hide();assert.equal(priority.scene.parent.values.visibility,'visible');q.ready(priority);q.r.Prepare(q.t.overlay,q.unique[0]);
while(q.t.jobs.size)q.tick();assert.equal(q.r.Inspect().warming,'');
assert.equal(q.r.Inspect().created,2,'preempted load is not automatically resumed');
assert.notEqual(paused,q.unique[0]);

// A later ready selection cancels a queued obsolete request. During eviction,
// both the displayed world and one in-flight load are protected.
const protect=fixture();protect.r.Prewarm(protect.t.nativeHost());
for(const id of protect.unique.slice(0,4)){const value=protect.r.Prepare(protect.t.overlay,id);protect.ready(value);protect.r.Prepare(protect.t.overlay,id);}
const display=protect.r.Prepare(protect.t.overlay,protect.unique[3]).scene;
protect.r.Prewarm(protect.t.nativeHost(),protect.unique[4]);assert.equal(protect.r.Inspect().queued,1);
protect.r.Prewarm(protect.t.nativeHost(),protect.unique[3]);assert.equal(protect.r.Inspect().queued,0);
protect.r.Prewarm(protect.t.nativeHost(),protect.unique[4]);protect.tick();
const inFlight=protect.scenes().find(scene=>scene.attributes.map===protect.t.cfg.SurvivalMonsterPortraitScenes[protect.unique[4]].map);
const urgent=protect.r.Prepare(protect.t.overlay,protect.unique[5]);assert(urgent);
assert(display.alive&&inFlight.alive,'current and warming survive the allocation eviction');
protect.ready(urgent);protect.r.Prepare(protect.t.overlay,protect.unique[5]);
protect.r.Prewarm(protect.t.nativeHost(),protect.unique[6]);protect.event();
assert.equal(protect.r.Inspect().queued,0,'new real selection invalidates obsolete queued metadata work');

// Every real identity still resolves to its complete configured background map.
const all=fixture();let visited=0;
for(const asset of Object.keys(all.t.cfg.SurvivalMonsterPortraitScenes)){
 const spec=all.t.cfg.SurvivalMonsterPortraitScenes[asset],value=all.r.Prepare(all.t.overlay,asset);assert(value);
 assert.equal(value.scene.attributes.map,spec.map);all.ready(value);assert(all.r.Prepare(all.t.overlay,asset).ready);visited++;
}
assert.equal(visited,197);assert.equal(all.r.Inspect().cached,4);assert.equal(all.t.metrics.setUnit.length,0);
const bane='monster_boss_rebirth_05_lucid_torment',baneSpec=all.t.cfg.SurvivalMonsterPortraitScenes[bane];
assert.equal(baneSpec.components,4);assert.equal(baneSpec.map,'portraits/monster_326b73b164e21d7f1a07_v1');
const baneAgain=all.r.Prepare(all.t.overlay,bane);assert.equal(baneAgain.scene.attributes.map,baneSpec.map);
all.ready(baneAgain);assert(all.r.Prepare(all.t.overlay,bane).ready);

// Failed loads cannot retry on timer/Prepare ticks, even after long elapsed time.
// New local selection and explicit Retry each permit one new bounded attempt.
const retry=fixture(),asset=retry.unique[0];retry.r.Prewarm(retry.t.nativeHost());
let attempt=retry.r.Prepare(retry.t.overlay,asset);retry.advance(10001);assert.equal(retry.r.Prepare(retry.t.overlay,asset),null);
assert.equal(retry.r.Inspect().failures,1);assert.equal(retry.r.Inspect().created,1);
retry.event('dota_player_update_selected_unit',1);retry.advance(100000);
for(let i=0;i<100;i++)assert.equal(retry.r.Prepare(retry.t.overlay,asset),null);
while(retry.t.jobs.size)retry.tick();assert.equal(retry.r.Inspect().created,1,'remote selections and idle ticks do not retry');
retry.event();attempt=retry.r.Prepare(retry.t.overlay,asset);assert(attempt);assert.equal(retry.r.Inspect().created,2);
retry.advance(10001);assert.equal(retry.r.Prepare(retry.t.overlay,asset),null);
retry.event('dota_player_update_query_unit');retry.advance(9999);assert.equal(retry.r.Prepare(retry.t.overlay,asset),null);
retry.advance(1);attempt=retry.r.Prepare(retry.t.overlay,asset);assert(attempt);assert.equal(retry.r.Inspect().created,3);
retry.advance(10001);assert.equal(retry.r.Prepare(retry.t.overlay,asset),null);
assert(retry.r.Retry(asset));retry.advance(29999);assert.equal(retry.r.Prepare(retry.t.overlay,asset),null);
retry.advance(1);attempt=retry.r.Prepare(retry.t.overlay,asset);assert(attempt);assert.equal(retry.r.Inspect().created,4);
retry.ready(attempt);assert(retry.r.Prepare(retry.t.overlay,asset).ready);assert(!retry.r.Retry(asset),'success clears failure state');
assert.equal(retry.r.Inspect().retries,3);

// Initial 2-second backoff is also mandatory after a new real selection.
const fast=fixture();let initial=fast.r.Prepare(fast.t.overlay,fast.unique[0]);fast.advance(10001);
assert.equal(fast.r.Prepare(fast.t.overlay,fast.unique[0]),null);fast.event();fast.advance(1999);
assert.equal(fast.r.Prepare(fast.t.overlay,fast.unique[0]),null);fast.advance(1);assert(fast.r.Prepare(fast.t.overlay,fast.unique[0]));

// Prewarm starts before Prepare receives the current selection. Its eventual
// failure must use that selection's epoch, with no idle failed-load timer loop.
const ahead=fixture(),aheadAsset=ahead.unique[0];ahead.r.Prewarm(ahead.t.nativeHost(),aheadAsset);ahead.tick();
assert(ahead.r.Prepare(ahead.t.overlay,aheadAsset));ahead.advance(10001);assert.equal(ahead.r.Prepare(ahead.t.overlay,aheadAsset),null);
while(ahead.t.jobs.size)ahead.tick();ahead.advance(100000);
for(let i=0;i<100;i++){ahead.r.Prewarm(ahead.t.nativeHost(),aheadAsset);assert.equal(ahead.r.Prepare(ahead.t.overlay,aheadAsset),null);}
assert.equal(ahead.r.Inspect().created,1);assert.equal(ahead.t.jobs.size,0,'unchanged failed request cannot keep scheduling native warmup work');

// Compare real production function counts with 197 vs1970 catalog identities.
function steady(extra){
 const sample=fixture(extra);sample.r.Prewarm(sample.t.nativeHost());
 for(const id of sample.unique.slice(0,4)){const p=sample.r.Prepare(sample.t.overlay,id);sample.ready(p);sample.r.Prepare(sample.t.overlay,id);}
 const id=sample.unique[3];sample.advance(100);sample.r.Prepare(sample.t.overlay,id);
 const before={...sample.counts},created=sample.r.Inspect().created;
 for(let i=0;i<300;i++){sample.advance(100);sample.r.Prewarm(sample.t.nativeHost(),id);sample.r.Prepare(sample.t.overlay,id);}
 const delta=Object.fromEntries(Object.keys(before).map(key=>[key,sample.counts[key]-before[key]]));
 assert.equal(sample.r.Inspect().created,created);assert.equal(delta.enumerations,0);assert.equal(delta.styleWrites,0);
 return delta;
}
const small=steady(0),large=steady(1773);assert.deepEqual(large,small,'steady native/mock bridge costs cannot grow with catalog size');

// Destroyed handles, old image callbacks, old selection callbacks and timers.
const dead=fixture();dead.r.Prewarm(dead.t.nativeHost(),dead.unique[0]);dead.tick();
let value=dead.r.Prepare(dead.t.overlay,dead.unique[0]);const oldEntry=value.scene.__survivalMonsterPortraitEntry;
const imageCallback=value.scene.parent.FindChildTraverse('Background').ImageLoaded;
value.scene.parent.DeleteAsync(0);assert.equal(dead.r.Prepare(dead.t.overlay,dead.unique[0]),null);
assert(dead.r.Prepare(dead.t.overlay,dead.unique[0]));imageCallback();assert.equal(oldEntry.imageReady,false);
const oldSelections=[...dead.events.values()].map(row=>row.callback);dead.r.Shutdown();dead.r.Shutdown();
assert.equal(dead.events.size,0);assert.equal(dead.unsubscribed.length,2);
const epoch=dead.r.Inspect().selectionEpoch;oldSelections.forEach(fn=>fn({PlayerID:0}));imageCallback();
while(dead.t.jobs.size)dead.tick();assert.equal(dead.r.Inspect().selectionEpoch,epoch);
assert.equal(dead.r.Inspect().cached,0);assert.equal(dead.r.Inspect().loaded,0);assert.equal(dead.scenes().length,0);
assert.equal(dead.r.Prepare(dead.t.overlay,dead.unique[0]),null);
for(const sample of [f,q,protect,all,retry,fast,ahead]){sample.r.Shutdown();while(sample.t.jobs.size)sample.tick();}
const report={status:'PASS',scope:'Production renderer; fake Panorama/entity bridge and virtual time. No native FPS/rendering proof.',
 coverage:{identities:visited,distinct_maps:188,bane_components:4,resident_limit:4},steady_300_refreshes:{catalog_197:small,catalog_1970:large},
 failures:{attempts:4,retries:3,backoff_ms:[2000,10000,30000],same_epoch_retry_allocations:0},subscriptions_removed:2};
fs.mkdirSync('output/portrait_recovery_20261031/bounded_pool',{recursive:true});
fs.writeFileSync('output/portrait_recovery_20261031/bounded_pool/logical_report.json',JSON.stringify(report,null,2)+'\n');
console.log('BOUNDED_PORTRAIT_POOL_PASS: 197 identities/188 maps; <=4 resident, O(1)LRU, latest-only explicit warmup, full Bane spec,2/10/30s selection retries,100ms cover, no steady catalog scans/writes, old callback disposal');
