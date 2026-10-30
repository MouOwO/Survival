// Execute the production selection event, metadata update and scene renderer.
// The first check runs before any scheduled retry can conceal a native flash.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const {setup}=require('./test_combat_stats_callbacks.cjs');
function fixture(){
 let now=1000;
 const date={now:()=>now},t=setup({portrait:true,date,events:{SendCustomGameEventToServer(){}}});
 t.Panel.prototype.DeleteAsync=function(){this.alive=false};
 t.Panel.prototype.BHasClass=function(name){return !!this.classNames?.has(name)};
 t.panorama.RegisterEventHandler=(event,p,fn)=>p[event]=fn;
 const ctx={$:t.panorama,GameUI:{CustomUIConfig:()=>t.cfg},Date:date};
 for(const name of ['monster_portrait_scenes','monster_portrait_renderer'])
  vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/'+name+'.js','utf8'),ctx);
 t.advance=n=>now+=n;
 t.ready=p=>{p.scene.AddClass('SceneLoaded');p.scene.parent.FindChildTraverse('Background').ImageLoaded()};
 t.renderer=t.cfg.SurvivalMonsterPortraitRenderer;
 t.asset=Object.keys(t.cfg.SurvivalMonsterPortraitScenes).find(a=>a.startsWith('monster_boss_rebirth_04_'));
 t.snap=(id,asset=t.asset,version=1)=>({entindex:id,refresh_version:version,model_asset_id:asset,
  portrait_unit_name:t.cfg.SurvivalMonsterPortraitScenes[asset]?.unit||''});
 return t;
}
const cold=fixture(),asset=cold.asset;
cold.select(8,'npc_survival_named_rebirth_boss_04');
cold.api.selectionEvent('selected_unit_event',{PlayerID:0});
assert.equal(cold.overlay.values.visibility,'visible','cover native pixels in the selection event, before deferred retries');
assert.equal(cold.native().hittest,true,'native portrait mouse handlers remain available');
assert.equal(cold.native().values.opacity,'1','the native input leaf retains its original active opacity');
cold.api.updateSnapshot({entindex:8,refresh_version:1,health:99});
assert.equal(cold.overlay.values.visibility,'visible','an early stats-only reply does not reveal the native body before identity arrives');
cold.api.updateSnapshot(cold.snap(8));
assert.equal(cold.overlay.values.visibility,'visible','cold scene must never restore the undecorated native body');
assert.equal(cold.overlay.FindChildTraverse('SurvivalPortraitTransitionBackground0').image,
 cold.cfg.SurvivalMonsterPortraitScenes[asset].background,'pending scene uses its matching background');
const loading=cold.renderer.Prepare(cold.overlay,asset);cold.ready(loading);
cold.api.updateSnapshot(cold.snap(8,asset,2));
assert.equal(cold.api.portraitState().mode,'monster_scene');
assert.equal(cold.overlay.values.visibility,'visible');
const cover=cold.overlay.FindChildTraverse('SurvivalPortraitTransitionCover');
assert.equal(cover.values.visibility,'visible','cover the cached scene while its render target resumes');
assert.equal(cover.hittest,false);assert.equal(cover.hittestchildren,false);
cold.advance(101);cold.api.portraitUpdate(cold.snap(8,asset,2));
assert.equal(cover.values.visibility,'collapse','reveal the complete scene after the render target settles');
// A response can arrive before the first deferred name/stat retry. That retry
// must not discard the new entity's accepted identity and enter pending again.
cold.api.refreshHeroPanel();
assert.equal(cold.api.portraitState().snapshot.entindex,8);
assert.equal(cold.api.portraitState().acceptedVersion,2);
assert.equal(cold.api.portraitState().scene,loading.scene);

const warm=fixture(),hero='hero_permanent_hero_blademaster';
for(const id of [warm.asset,hero]){const p=warm.renderer.Prepare(warm.overlay,id);warm.ready(p)}
warm.select(8,'npc_survival_named_rebirth_boss_04');warm.api.updateSnapshot(warm.snap(8));
const created=warm.renderer.Inspect().created;
warm.select(9,'npc_dota_hero_juggernaut');warm.runtime.player_0=warm.snap(9,hero);
warm.api.selectionEvent('selected_unit_event',{PlayerID:0});
assert.equal(warm.api.portraitState().entity,9,'already received identity switches to the warm outfit synchronously');
assert.equal(warm.overlay.values.visibility,'visible');
assert.equal(warm.renderer.Inspect().created,created,'selection event reuses the preloaded scene');
const current=warm.api.portraitState().scene;
warm.api.selectionEvent('query_unit_event',{PlayerID:1});assert.equal(warm.api.portraitState().scene,current);
warm.api.updateSnapshot(warm.snap(8));assert.equal(warm.api.portraitState().entity,9,'late previous-unit reply cannot reveal its body');
warm.setMulti(true);warm.api.portraitTransition('multi');assert.equal(warm.overlay.values.visibility,'collapse');
assert.equal(warm.native().values.opacity,'0.35','multiselect restores the previous native style');

const missing=fixture();missing.select(10,'npc_survival_wave_monster');missing.api.portraitTransition('pending');
assert.equal(missing.overlay.values.visibility,'visible');missing.advance(1501);missing.api.portraitTransition('pending');
assert.equal(missing.overlay.values.visibility,'collapse','missing metadata releases the bounded transition cover');
const unsupported=fixture();unsupported.select(11,'building_unknown');unsupported.api.portraitTransition('pending');
unsupported.api.updateSnapshot({entindex:11,refresh_version:1,model_asset_id:'unknown'});
assert.equal(unsupported.overlay.values.visibility,'collapse','authoritative unsupported units restore native immediately');
const failed=fixture();failed.select(12,'npc_survival_named_rebirth_boss_04');failed.api.updateSnapshot(failed.snap(12));
assert.equal(failed.overlay.values.visibility,'visible');failed.advance(10001);failed.api.portraitUpdate(failed.snap(12));
assert.equal(failed.overlay.values.visibility,'collapse','failed scene loading restores native instead of a permanent blank');
console.log('PORTRAIT_SELECTION_TRANSITION_PASS: synchronous warm selection, cold cover, early metadata retention, stale/remote/multiselect isolation and bounded native fallback');
