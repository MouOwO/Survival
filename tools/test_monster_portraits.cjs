// Exercise the production renderer and real combat selection/update functions.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const {setup}=require('./test_combat_stats_callbacks.cjs');
const catalog=fs.readFileSync('panorama/src/scripts/custom_game/monster_portrait_scenes.js','utf8');
const renderer=fs.readFileSync('panorama/src/scripts/custom_game/monster_portrait_renderer.js','utf8');
function fixture(){
 const t=setup({portrait:true});let now=1000;
 t.Panel.prototype.DeleteAsync=function(){this.alive=false;if(this.parent)this.parent.children=this.parent.children.filter(c=>c!==this)};
 t.Panel.prototype.BHasClass=function(name){return !!(this.classNames&&this.classNames.has(name))};
 t.panorama.RegisterEventHandler=(event,p,callback)=>{p[event]=callback};
 const ctx={$:t.panorama,GameUI:{CustomUIConfig:()=>t.cfg},Date:{now:()=>now}};
 vm.runInNewContext(catalog,ctx);vm.runInNewContext(renderer,ctx);
 t.reload=()=>vm.runInNewContext(renderer,ctx);t.advance=n=>now+=n;
 t.ready=scene=>{scene.AddClass('SceneLoaded');scene.parent.FindChildTraverse('Background').ImageLoaded()};
 return t;
}
const t=fixture(),r=t.cfg.SurvivalMonsterPortraitRenderer,assets=Object.keys(t.cfg.SurvivalMonsterPortraitScenes);
assert.equal(assets.length,197);
assert.equal(r.ResolveAsset('',t.cfg.SurvivalMonsterPortraitScenes.worker_lumberjack.model),'worker_lumberjack');
assert.equal(r.ResolveAsset('',t.cfg.SurvivalMonsterPortraitScenes.world_resource_tree.model),'world_resource_tree');
assert.equal(r.ResolveAsset('', 'models/unknown.vmdl'),'','unknown appearances must remain native');
assert.equal(r.ResolveAsset('', '', 'npc_survival_wave_named_humanoid_white_melee'),'monster_undying');
assert.equal(r.ResolveAsset('', 'models/heroes/undying/undying.vmdl_c'), 'monster_undying');
assert.equal(r.ResolveAsset('', 'models/unknown.vmdl', 'npc_survival_wave_named_humanoid_white_melee'),'','an explicit different model must reject the named-wave alias');
assert.equal(r.ResolveAsset('', '', 'npc_survival_wave_monster'),'','shared generic identities cannot guess an outfit');
const asset=assets[0],entry=r.Prepare(t.overlay,asset);
assert.equal(entry.ready,false);assert.equal(entry.scene.parent.values.visibility,'visible','loading scenes must render before SceneLoaded');
assert.equal(entry.scene.attributes.drawbackground,'true');assert.equal(entry.scene.attributes.map,t.cfg.SurvivalMonsterPortraitScenes[asset].map);
t.ready(entry.scene);assert.equal(r.Prepare(t.overlay,asset).ready,true);
for(let i=0;i<300;i++){t.advance(100);assert.equal(r.Prepare(t.overlay,asset).scene,entry.scene)}
assert.equal(t.metrics.created.filter(x=>x.type==='DOTAScenePanel').length,1,'stable identity must reuse its map');
r.Hide();assert.equal(entry.scene.parent.values.visibility,'collapse');
r.Prepare(t.overlay,asset);assert.equal(entry.scene.parent.values.visibility,'visible');
for(const id of assets){t.advance(100);const v=r.Prepare(t.overlay,id);assert(v);t.ready(v.scene);assert.equal(r.Prepare(t.overlay,id).ready,true);assert(r.Inspect().cached<=188)}
assert.equal(t.metrics.setUnit.length,0,'world component maps must never be replaced by naked SetUnit heroes');
const last=r.Prepare(t.overlay,assets.at(-1));
const nextParent=new t.Panel('RebuiltOverlay',t.context);assert.equal(r.Prepare(nextParent,assets.at(-1)).scene,last.scene,'ready scenes reparent without reloading the world');
const slowFixture=fixture(),slowRenderer=slowFixture.cfg.SurvivalMonsterPortraitRenderer;
const slow=slowRenderer.Prepare(slowFixture.overlay,assets[0]);slowFixture.advance(10001);assert.equal(slowRenderer.Prepare(slowFixture.overlay,assets[0]),null);assert.equal(slow.scene.parent.alive,false);assert.equal(slowRenderer.Prepare(slowFixture.overlay,assets[0]),null,'failed resources must not thrash every sentinel tick');
assert.equal(r.Prepare(nextParent,'__proto__'),null);assert.equal(r.HasAsset('constructor'),false);
const broken=new t.Panel('Released',t.context);broken.alive='throw';assert.doesNotThrow(()=>r.Prepare(broken,assets[2]));
t.reload();assert.equal(r.Inspect().cached,0);assert.equal(r.Prepare(nextParent,assets[1]),null,'old owner cannot recreate resources after reload');
// Actual combat integration: authoritative entity matching, native camera scale,
// repeated snapshots, pending selection, multiselect and player Juggernaut.
const c=fixture(),cr=c.cfg.SurvivalMonsterPortraitRenderer;
const rebirth=assets.filter(a=>a.startsWith('monster_boss_rebirth_'));assert.equal(rebirth.length,10);
let version=0;
for(const id of [...rebirth,...assets.filter(a=>!rebirth.includes(a))]){
 const spec=c.cfg.SurvivalMonsterPortraitScenes[id];c.select(8,'npc_survival_wave_monster');
 const snap={entindex:8,refresh_version:++version,model_asset_id:id,portrait_unit_name:spec.unit};
 const warmed=cr.Prepare(c.overlay,id);c.ready(warmed.scene);
 c.api.updateSnapshot(snap);const state=c.api.portraitState();assert.equal(state.mode,'monster_scene',id);assert(state.scene);
 assert.equal(state.scene.values.transform,'scale3d(1, 1, 1)','official camera must not receive tower enlargement');
 c.ready(state.scene);for(let n=0;n<4;n++)c.api.updateSnapshot({...snap,refresh_version:++version});
 assert.equal(c.api.portraitState().scene,state.scene);assert(cr.Inspect().cached<=188);
 c.setMulti(true);c.api.portraitUpdate(snap);assert.equal(c.overlay.values.visibility,'collapse');c.setMulti(false);
 c.api.portraitUpdate(snap);assert.equal(c.api.portraitState().scene,state.scene);
}
assert.equal(c.metrics.setUnit.length,0);
const old=c.api.portraitState().snapshot;c.select(7,'npc_dota_hero_juggernaut');c.api.portraitTransition('pending_hero');assert.equal(c.api.portraitState().scene.parent.values.visibility,'collapse');
c.api.updateSnapshot({entindex:7,refresh_version:++version,model_asset_id:'hero_permanent_hero_blademaster',portrait_unit_name:'npc_dota_hero_juggernaut'});
assert.equal(c.api.portraitState().mode,'monster_scene');assert.equal(c.metrics.setUnit.length,0,'owned Juggernaut uses its exact decorated world scene');
c.api.updateSnapshot({...old,refresh_version:++version});assert.equal(c.api.portraitState().entity,7,'late monster snapshot cannot replace player hero');
c.api.shutdown('test_done');
// Sequential background warmup must not allocate worlds again on first selection.
const w=fixture(),wr=w.cfg.SurvivalMonsterPortraitRenderer;
wr.Prewarm(w.nativeHost());
for(let step=0;step<500&&w.jobs.size;step++){
 w.advance(60);w.run([...w.jobs.keys()][0]);
 for(const item of w.metrics.created.filter(x=>x.type==='DOTAScenePanel'))if(item.panel&&item.panel.alive)w.ready(item.panel);
 // CreatePanel metrics contain the real fixture handle under `panel`.
 const stage=w.nativeHost().FindChildTraverse('SurvivalPortraitPrewarm');
 if(stage)for(const host of stage.children){const scene=host.FindChildTraverse('Scene');if(scene)w.ready(scene);}
}
assert.equal(wr.Inspect().loaded,188);assert.equal(wr.Inspect().queued,0);
const warmStage=w.nativeHost().FindChildTraverse('SurvivalPortraitPrewarm'),stageParent=warmStage.GetParent();
wr.Prewarm(warmStage.children[0]);assert.equal(warmStage.GetParent(),stageParent,'reject a stage/child parenting cycle');
const allocations=wr.Inspect().created;
for(const id of assets){const ready=wr.Prepare(w.overlay,id);assert(ready.ready,id);assert.equal(ready.scene.parent.GetParent(),w.overlay);}
assert.equal(wr.Inspect().created,allocations,'first clicks reuse every prewarmed world');
wr.Shutdown();
// A click overtakes background work. Its loading host must remain renderable
// through Hide(), and time spent paused in the queue is not a load timeout.
const p=fixture(),pr=p.cfg.SurvivalMonsterPortraitRenderer;
pr.Prewarm(p.nativeHost());p.run([...p.jobs.keys()][0]);
const firstWarm=pr.Inspect().warming;
const selected=assets.find(a=>a!==firstWarm&&p.cfg.SurvivalMonsterPortraitScenes[a].map!==p.cfg.SurvivalMonsterPortraitScenes[firstWarm].map);
const priority=pr.Prepare(p.overlay,selected);pr.Hide();
assert.equal(pr.Inspect().warming,selected);
assert.equal(priority.scene.parent.values.visibility,'visible','pending selected scene renders behind the opaque transition cover');
const pause=pr.Prepare(p.overlay,firstWarm);p.advance(10001);
assert(pr.Prepare(p.overlay,selected),'an entry paused in the queue does not fail because wall time passed');
assert.equal(pr.Inspect().warming,selected);
p.ready(priority.scene);assert(pr.Prepare(p.overlay,selected).ready);pr.Hide();
assert.equal(priority.scene.parent.values.visibility,'collapse','a completed warming scene is not retained over the next unit');
pr.Shutdown();
console.log('MONSTER_PORTRAITS_PASS: 197 identities / 188 worlds; sequential prewarm, zero first-click allocations, persistent reuse, timeout/native fallback, HUD rebuild/reload, multiselect and all six heroes');
