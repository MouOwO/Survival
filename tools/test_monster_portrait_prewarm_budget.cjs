// Execute the production renderer with a virtual clock; never connect to Dota.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const path=require('node:path');
const {setup}=require('./test_combat_stats_callbacks.cjs');
const catalog=fs.readFileSync('panorama/src/scripts/custom_game/monster_portrait_scenes.js','utf8');
const source=fs.readFileSync('panorama/src/scripts/custom_game/monster_portrait_renderer.js','utf8');
function fixture(){
 const t=setup({portrait:true});let now=1000,origin=[0,0,384];
 t.select(7,'npc_survival_builder_proxy');
 t.Panel.prototype.DeleteAsync=function(){
  function dispose(p){p.alive=false;p.children.forEach(dispose);}
  dispose(this);if(this.parent)this.parent.children=this.parent.children.filter(p=>p!==this);
 };
 t.Panel.prototype.BHasClass=function(name){return !!(this.classNames&&this.classNames.has(name));};
 t.panorama.RegisterEventHandler=(event,p,callback)=>{p[event]=callback;};
 const ctx={$:t.panorama,GameUI:{CustomUIConfig:()=>t.cfg},Date:{now:()=>now},
  Entities:{GetAbsOrigin:unit=>unit===7?origin.slice():undefined}};
 vm.runInNewContext(catalog,ctx);vm.runInNewContext(source,ctx);
 const r=t.cfg.SurvivalMonsterPortraitRenderer;
 const scenes=()=>t.metrics.created.filter(p=>p.type==='DOTAScenePanel'&&p.panel.alive).map(p=>p.panel);
 const ready=scene=>{scene.AddClass('SceneLoaded');scene.parent.FindChildTraverse('Background').ImageLoaded();};
 function sane(){const s=r.Inspect();for(const k of ['cached','loaded','created','queued','visible','movementPauses','cooldownPauses'])assert(Number.isInteger(s[k])&&s[k]>=0,k+' nonnegative');assert(s.loaded<=s.cached);assert(s.cached<=188);assert(s.created<=188);assert(s.visible<=2,'at most one selected and one warming host after a public return');return s;}
 for(const name of ['Prepare','Hide','Prewarm','Shutdown']){
  const original=r[name];r[name]=function(...args){const value=original.apply(this,args);sane();return value;};
 }
 function tick(move=false,completeAfter=false){
  now+=50;if(move)origin=[origin[0]+8,origin[1]+3,origin[2]];
  const job=[...t.jobs.keys()][0];assert(job!==undefined,'warm timer remains live');t.run(job);
  if(completeAfter)scenes().forEach(ready);return sane();
 }
 function freshAsset(){const maps=new Set(scenes().map(p=>p.attributes.map));return Object.keys(t.cfg.SurvivalMonsterPortraitScenes).find(id=>!maps.has(t.cfg.SurvivalMonsterPortraitScenes[id].map));}
 return {t,r,tick,ready,scenes,sane,freshAsset,now:()=>now};
}
const f=fixture(),{t,r}=f;const stages=[];
r.Prewarm(t.nativeHost());assert.equal(r.Inspect().queued,188,'197 identities deduplicate to188 queued worlds');
for(let i=0;i<20;i++)f.tick(true);
assert.equal(r.Inspect().created,0,'moving selected builder must not start a background scene');
assert(r.Inspect().movementPauses>=20);stages.push({phase:'20 moving ticks',state:r.Inspect()});
for(let i=0;i<4;i++)f.tick();
assert.equal(r.Inspect().created,0,'200ms stationary is below idle threshold');
f.tick();assert.equal(r.Inspect().created,1,'250ms stationary starts one background world');
const first=f.scenes()[0];f.ready(first);f.tick();
assert.equal(r.Inspect().loaded,1);assert.equal(r.Inspect().warming,'');
for(let i=0;i<9;i++){f.tick();assert.equal(r.Inspect().created,1,'500ms cooldown not elapsed');}
f.tick();assert.equal(r.Inspect().created,2,'the next background scene starts at the500ms boundary');
stages.push({phase:'250ms idle and500ms pacing',state:r.Inspect()});
// Moving while a load is in-flight may finish that load, but starts no new load.
for(let i=0;i<20;i++)f.tick(true);
assert.equal(r.Inspect().created,2);
const paused=r.Inspect().warming,coldAsset=f.freshAsset();assert(coldAsset);
const cold=r.Prepare(t.overlay,coldAsset);
assert(cold&&!cold.ready);assert.equal(r.Inspect().created,3,'cold selection allocates immediately while moving');
assert.equal(r.Inspect().warming,coldAsset,'cold selection preempts the in-flight background world');
assert.equal(cold.scene.parent.values.visibility,'visible');r.Hide();
assert.equal(cold.scene.parent.values.visibility,'visible','pending selected load remains renderable through Hide');
assert.equal(r.Prepare(t.overlay,coldAsset).scene,cold.scene);assert.equal(r.Inspect().created,3,'repeated Prepare does not create duplicates');
assert(paused!==coldAsset);f.ready(cold.scene);
const mounted=r.Prepare(t.overlay,coldAsset);assert(mounted.ready);assert.equal(mounted.presentable,false,'ready cached render target is covered before100ms');
f.tick(true);assert.equal(r.Prepare(t.overlay,coldAsset).presentable,false);
f.tick(true);assert.equal(r.Prepare(t.overlay,coldAsset).presentable,true,'100ms ready target becomes presentable');
stages.push({phase:'cold selection overtakes movement',state:r.Inspect()});
// A second cold selection also bypasses the just-established cooldown.
const before=r.Inspect().created,nextAsset=f.freshAsset();assert(nextAsset);
const next=r.Prepare(t.overlay,nextAsset);assert(next&&!next.ready);
assert.equal(r.Inspect().created,before+1);assert.equal(r.Inspect().warming,nextAsset);
f.ready(next.scene);r.Prepare(t.overlay,nextAsset);
// No further movement. Fake completion and sufficient virtual budget must still
// finish the full original catalog, rather than sacrificing prewarm coverage.
let ticks=0;
while(ticks<2500&&t.jobs.size){f.tick(false,true);ticks++;if(r.Inspect().loaded===188&&r.Inspect().queued===0&&!r.Inspect().warming)break;}
const final=f.sane();assert.equal(final.loaded,188);assert.equal(final.cached,188);assert.equal(final.created,188);assert.equal(final.queued,0);assert.equal(final.warming,'');
const maps=f.scenes().map(s=>s.attributes.map);assert.equal(new Set(maps).size,188,'no duplicate world allocations');
const created=final.created;
for(const id of Object.keys(t.cfg.SurvivalMonsterPortraitScenes)){const p=r.Prepare(t.overlay,id);assert(p&&p.ready,id);}
assert.equal(r.Inspect().created,created,'all197 first selections reuse188 warmed worlds');
r.Shutdown();const shutdown=f.sane();assert.equal(shutdown.cached,0);assert.equal(shutdown.loaded,0);assert.equal(shutdown.visible,0);assert.equal(shutdown.warming,'');
assert.equal(f.scenes().length,0);while(t.jobs.size)t.run([...t.jobs.keys()][0]);assert.equal(r.Inspect().created,created,'late callback after Shutdown cannot recreate a scene');
assert.equal(r.Prepare(t.overlay,nextAsset),null);
// Shutdown mid-queue must also dispose the one active world and stop the timer.
const early=fixture();early.r.Prewarm(early.t.nativeHost(),'builder_io_benevolent_companion');early.tick();assert.equal(early.r.Inspect().created,1);
early.r.Shutdown();while(early.t.jobs.size)early.t.run([...early.t.jobs.keys()][0]);
const earlyState=early.sane();assert.equal(earlyState.cached,0);assert.equal(earlyState.loaded,0);assert.equal(earlyState.visible,0);assert.equal(earlyState.warming,'');assert.equal(early.scenes().length,0);
// Released native handles are not retained in the indexed cache. The first
// check reports failure, the next explicit selection may rebuild that world.
const lost=fixture(),lostAsset='builder_io_benevolent_companion';lost.r.Prewarm(lost.t.nativeHost());
let released=lost.r.Prepare(lost.t.overlay,lostAsset);released.scene.parent.DeleteAsync(0);
assert.equal(lost.r.Prepare(lost.t.overlay,lostAsset),null);assert.equal(lost.r.Inspect().cached,0);
let rebuilt=lost.r.Prepare(lost.t.overlay,lostAsset);assert(rebuilt&&!rebuilt.ready);assert.equal(lost.r.Inspect().created,2);
for(let i=0;i<5;i++)assert.equal(lost.r.Prepare(lost.t.overlay,lostAsset).scene,rebuilt.scene);
assert.equal(lost.r.Inspect().created,2);assert.equal(lost.r.Inspect().loaded,0);
rebuilt.scene.DeleteAsync(0);assert.equal(lost.r.Prepare(lost.t.overlay,lostAsset),null);
rebuilt=lost.r.Prepare(lost.t.overlay,lostAsset);assert(rebuilt);lost.ready(rebuilt.scene);
for(let i=0;i<5;i++)assert(lost.r.Prepare(lost.t.overlay,lostAsset).ready);
assert.equal(lost.r.Inspect().loaded,1,'repeated ready checks increment loaded only once');
rebuilt.scene.parent.DeleteAsync(0);assert.equal(lost.r.Prepare(lost.t.overlay,lostAsset),null);
assert.equal(lost.r.Inspect().loaded,0,'removing a ready world decrements loaded once');
assert(lost.r.Prepare(lost.t.overlay,lostAsset));lost.r.Shutdown();lost.r.Shutdown();
while(lost.t.jobs.size)lost.t.run([...lost.t.jobs.keys()][0]);
const releasedState=lost.sane();assert.equal(releasedState.cached,0);assert.equal(releasedState.loaded,0);assert.equal(releasedState.visible,0);assert.equal(releasedState.warming,'');
assert.equal(lost.r.Prepare(lost.t.overlay,lostAsset),null);assert.equal(lost.scenes().length,0);
const report={status:'PASS',scope:'Production renderer; fake Panorama/entity bridge and50ms virtual ticks only. No native rendering/FPS claim.',stages,completion:{ticks,virtual_ms:ticks*50,state:final},shutdown,early_shutdown:earlyState,released_handles_shutdown:releasedState};
const reportPath=path.resolve('output/online_movement_client_20261031/paced_prewarm_report.json');
fs.mkdirSync(path.dirname(reportPath),{recursive:true});fs.writeFileSync(reportPath,JSON.stringify(report,null,2)+'\n');
console.log('PACED_PREWARM_PASS: moving/idle/cooldown budget, cold priority,100ms cover,197→188 dedup, <=2 visible hosts, released host/scene recovery, repeated ready checks and idempotent Shutdown/late timer');
