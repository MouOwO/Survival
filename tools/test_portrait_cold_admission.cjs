'use strict';
// Real renderer + combat callers, virtual scheduler/native bridge. These are
// resource-call counts and lifecycle checks, never native FPS/load-time claims.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const {setup}=require('./test_combat_stats_callbacks.cjs');
const renderer=fs.readFileSync('panorama/src/scripts/custom_game/monster_portrait_renderer.js','utf8');
const catalog=fs.readFileSync('panorama/src/scripts/custom_game/monster_portrait_scenes.js','utf8');
function fixture(){
 let now=1000,next=0,deleted=0;const callbacks=new Map(),date={now:()=>now};
 const t=setup({portrait:true,date,events:{SendCustomGameEventToServer(){}}});
 const schedule=t.panorama.Schedule;
 t.panorama.Schedule=(delay,fn)=>{const id=schedule(delay,fn);t.jobs.get(id).due=now+delay*1000;return id;};
 t.panorama.RegisterEventHandler=(name,p,fn)=>{p[name]=fn;};
 t.Panel.prototype.DeleteAsync=function(){deleted++;const walk=p=>{p.alive=false;p.children.forEach(walk);};walk(this);if(this.parent)this.parent.children=this.parent.children.filter(p=>p!==this);};
 t.Panel.prototype.BHasClass=function(name){return !!this.classNames?.has(name);};
 const context={$:t.panorama,GameUI:{CustomUIConfig:()=>t.cfg},Date:date,Game:{GetLocalPlayerID:()=>0},
  GameEvents:{Subscribe:(name,fn)=>{callbacks.set(++next,{name,fn});return next;},Unsubscribe:id=>callbacks.delete(id)}};
 vm.runInNewContext(catalog,context);vm.runInNewContext(renderer,context);
 const r=t.cfg.SurvivalMonsterPortraitRenderer,assets=Object.keys(t.cfg.SurvivalMonsterPortraitScenes).filter(a=>a.startsWith('tower_'));
 function advance(ms){const end=now+ms;let count=0;while(true){let key=null,due=Infinity;for(const [id,job] of t.jobs)if(job.due<=end&&job.due<due){key=id;due=job.due;}if(key===null)break;assert(++count<1000,'bounded virtual timer drain');now=due;t.run(key);}now=end;}
 function event(player=0){for(const row of [...callbacks.values()])if(row.name==='dota_player_update_selected_unit')row.fn({PlayerID:player});}
 function ready(value){assert(value?.scene,'native scene created before fake load completion');value.scene.AddClass('SceneLoaded');value.scene.parent.FindChildTraverse('Background').ImageLoaded();}
 function settle(asset,parent=t.overlay){const pending=r.Prepare(parent,asset);if(pending?.pending)advance(100);const value=r.Prepare(parent,asset);ready(value);const mounted=r.Prepare(parent,asset);advance(100);return mounted;}
 const state=()=>({created:r.Inspect().created,evictions:r.Inspect().evictions,cached:r.Inspect().cached,deleted});
 return {t,r,assets,advance,event,ready,settle,state,callbacks};
}

const rapid=fixture();rapid.r.Prewarm(rapid.t.nativeHost());
let peak=0;for(let i=0;i<100;i++){
 rapid.event();const value=rapid.r.Prepare(rapid.t.overlay,rapid.assets[i%5]);
 assert(value.pending&&!value.ready&&value.scene===null);
 peak=Math.max(peak,rapid.t.jobs.size);rapid.advance(10);
 assert.equal(rapid.state().created,0,'intermediate selections never allocate or evict a native world');
}
assert.equal(peak,1,'latest-only admission has one pending timer');
rapid.advance(89);assert.equal(rapid.state().created,0);rapid.advance(1);
assert.equal(rapid.state().created,1);const final=rapid.r.Prepare(rapid.t.overlay,rapid.assets[4]);rapid.ready(final);
assert(rapid.r.Prepare(rapid.t.overlay,rapid.assets[4]).ready);rapid.advance(100);
assert.equal(rapid.t.jobs.size,0,'ready state has no renderer polling');

const warm=fixture();warm.r.Prewarm(warm.t.nativeHost());
for(const asset of warm.assets.slice(0,4))warm.settle(asset);
const warmBefore=warm.state();for(let i=0;i<100;i++){
 warm.event();assert(warm.r.Prepare(warm.t.overlay,warm.assets[i%4]).ready);
 assert.equal(warm.t.jobs.size,0,'warm selection is synchronous and starts no timer');
}
assert.deepEqual(warm.state(),warmBefore);
// Repeated cold fifth choices, each superseded by a hot asset, cannot thrash LRU.
for(let i=0;i<50;i++){
 warm.r.Prepare(warm.t.overlay,warm.assets[4]);warm.advance(10);
 assert(warm.r.Prepare(warm.t.overlay,warm.assets[i%4]).ready);warm.advance(10);
}
assert.deepEqual(warm.state(),warmBefore);
warm.settle(warm.assets[4]);assert.equal(warm.state().created,5);assert.equal(warm.state().evictions,1);assert.equal(warm.state().cached,4);

const repeated=fixture();repeated.r.Prewarm(repeated.t.nativeHost());
repeated.r.Prepare(repeated.t.overlay,repeated.assets[0]);
for(let i=0;i<9;i++){repeated.advance(10);repeated.r.Prewarm(repeated.t.nativeHost(),repeated.assets[0]);repeated.r.Prepare(repeated.t.overlay,repeated.assets[0]);}
assert.equal(repeated.state().created,0);repeated.advance(10);assert.equal(repeated.state().created,1,'same-key refresh never resets admission deadline');
repeated.r.Shutdown();assert.equal(repeated.t.jobs.size,0);

const disposed=fixture();disposed.r.Prepare(disposed.t.overlay,disposed.assets[0]);
const old=[...disposed.t.jobs.values()][0].fn;disposed.r.Shutdown();old();disposed.advance(1000);
assert.equal(disposed.state().created,0);assert.equal(disposed.callbacks.size,0);assert.equal(disposed.t.jobs.size,0);
const rebuilt=fixture();rebuilt.r.Prewarm(rebuilt.t.nativeHost());rebuilt.r.Prepare(rebuilt.t.overlay,rebuilt.assets[0]);
rebuilt.t.overlay.alive=false;rebuilt.advance(100);assert.equal(rebuilt.state().created,0,'destroyed requesting overlay cannot transfer a load to the retained stage');
const next=new rebuilt.t.Panel('NextOverlay',rebuilt.t.context);rebuilt.settle(rebuilt.assets[0],next);
assert.equal(rebuilt.state().created,1);assert.equal(rebuilt.r.Prepare(next,rebuilt.assets[0]).scene.parent.GetParent(),next);

const retry=fixture();retry.r.Prewarm(retry.t.nativeHost());retry.r.Prepare(retry.t.overlay,retry.assets[0]);retry.advance(100);
const failedScene=retry.r.Prepare(retry.t.overlay,retry.assets[0]).scene;
const oldImage=failedScene.parent.FindChildTraverse('Background').ImageLoaded;
retry.advance(10050);assert.equal(retry.r.Inspect().failures,1);assert.equal(retry.state().created,1);
retry.advance(100000);for(let i=0;i<100;i++)assert.equal(retry.r.Prepare(retry.t.overlay,retry.assets[0]),null);
assert.equal(retry.t.jobs.size,0);retry.event(1);assert.equal(retry.r.Prepare(retry.t.overlay,retry.assets[0]),null);
retry.event();const again=retry.r.Prepare(retry.t.overlay,retry.assets[0]);assert(again.pending);
assert.equal(retry.state().created,1);retry.advance(100);assert.equal(retry.state().created,2);
oldImage();assert.equal(failedScene.__survivalMonsterPortraitEntry.imageReady,false);
retry.ready(retry.r.Prepare(retry.t.overlay,retry.assets[0]));assert(retry.r.Prepare(retry.t.overlay,retry.assets[0]).ready);
retry.r.Shutdown();assert.equal(retry.t.jobs.size,0);

// Actual combat caller receives pending immediately: existing cover remains,
// accepted unit/name/stats progress, and no SetUnit fallback is triggered.
const joint=fixture(),asset=joint.assets[0],spec=joint.t.cfg.SurvivalMonsterPortraitScenes[asset];
joint.t.select(77,'building_arrow_tower');
const snapshot={entindex:77,refresh_version:1,model_asset_id:asset,portrait_unit_name:spec.unit,attack_min:10,attack_max:10,health:100,max_health:100};
joint.t.api.updateSnapshot(snapshot);assert.equal(joint.state().created,0);assert.equal(joint.t.metrics.setUnit.length,0);
assert.equal(joint.t.api.portraitState().snapshot.entindex,77);assert.equal(joint.t.overlay.values.visibility,'visible');
joint.advance(100);const allocated=joint.r.Prepare(joint.t.overlay,asset);joint.ready(allocated);
joint.t.api.portraitUpdate(snapshot);joint.advance(101);joint.t.api.portraitUpdate(snapshot);
assert.equal(joint.t.api.portraitState().mode,'monster_scene');assert.equal(joint.t.api.portraitState().entity,77);
assert.equal(joint.t.metrics.setUnit.length,0);assert.equal(joint.t.overlay.FindChildTraverse('SurvivalPortraitTransitionCover').values.visibility,'collapse');
for(const f of [rapid,warm,rebuilt,joint]){f.r.Shutdown();f.t.api.shutdown('test_end');}
console.log('PORTRAIT_COLD_ADMISSION_PASS: 100 rapid/5 assets => 1 world, 0 evictions; 100 warm switches => 0 new loads; cold superseded by warm => 0 evictions; eventual fifth => 1; pending <=1; ready idle 0 timers; exact scene/overlay/epoch lifecycle and bounded retry; real combat pending never SetUnit; no native FPS inference');
