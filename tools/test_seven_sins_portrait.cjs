// Reuse the existing full-production-module Panorama fixture. No stubs for
// hide, mount, geometry, update or sentinel; only native engine APIs are mocked.
const assert=require('assert');
const {setup}=require('./test_combat_stats_callbacks.cjs');
const cases=[
 ['hero_permanent_hero_doom','npc_dota_hero_doom_bringer',''],
 ['hero_permanent_hero_blademaster','npc_dota_hero_juggernaut',''],
 ['tower_keeper_of_the_light','npc_dota_hero_tinker',''],
 ['monster_boss_ten_sin_01_murid_divine','npc_dota_hero_necrolyte',''],
 ['monster_wave_humanoid_red_axe','npc_dota_hero_axe',''],
 ['monster_archive_shadow_1','npc_dota_hero_shadow_demon',''],
 ['challenge_monster_terrorblade_fractal_horns','npc_dota_hero_terrorblade',''],
 ['challenge_monster_beastmaster_legacy','npc_dota_hero_beastmaster','21396'],
 ['challenge_monster_morphling','npc_dota_hero_morphling',''],
 ['challenge_monster_ember_searing_path','npc_dota_hero_ember_spirit','21383'],
 ['challenge_monster_primal_beast_svarog','npc_dota_hero_primal_beast','26799'],
 ['challenge_monster_spectre_phantom_advent','npc_dota_hero_spectre','21361']
];
for(const [asset,unit,item]of cases){
 const t=setup({portrait:true});t.select(7,unit);
 const snapshot={entindex:7,refresh_version:1,model_asset_id:asset,portrait_unit_name:unit,portrait_item_def:item};
 t.api.updateSnapshot(snapshot);
 assert.deepStrictEqual(t.metrics.setUnit.map(call=>call.args),[[unit,'default',false]]);
 assert.equal(t.overlay.values.visibility,'visible');assert.equal(t.scene.values.visibility,'visible');
 assert.equal(t.overlay.GetParent(),t.nativeHost());assert.equal(t.native().values.opacity,'1');assert.equal(t.native().values.washColor,undefined);
 const initial={parents:t.metrics.parents,order:t.metrics.order,geometryWrites:t.metrics.geometryWrites,visibility:t.metrics.visibilityTransitions};
 t.api.cosmeticPortraitSentinel();
 for(let frame=0;frame<64;frame++){
  t.api.updateSnapshot({...snapshot,refresh_version:frame+2});t.run([...t.jobs.keys()][0]);
  assert.equal(t.jobs.size,1);
 }
 assert.equal(t.metrics.setUnit.length,1,asset+' must keep one Scene load for complete stable snapshots');
 assert.equal(t.metrics.econHero.length,0);assert.equal(t.metrics.econItem.length,0,'nonbuilder assets must not enter the Io econ path');
 assert.deepStrictEqual({parents:t.metrics.parents,order:t.metrics.order,geometryWrites:t.metrics.geometryWrites,visibility:t.metrics.visibilityTransitions},initial,
  asset+' must not repeatedly return home, hide or remount');
 assert(!t.messages.some(m=>m.includes('HIDE ')||m.includes('TRANSITION_MASK')),asset);
 t.setMulti(true);t.run([...t.jobs.keys()][0]);
 assert.equal(t.overlay.values.visibility,'collapse');assert.equal(t.overlay.GetParent(),t.context);
 assert.equal(t.native().values.opacity,'0.35');assert.equal(t.api.portraitState().scene,null);
 t.api.shutdown('matrix_done');assert.equal(t.jobs.size,0);
}
// The exact challenge allowlist and native hero-name contract remain strict.
for(const patch of [
 {model_asset_id:'challenge_monster_terrorblade_fractal_horns_wrong'},
 {model_asset_id:'hero_permanent_hero_lina'},
 {model_asset_id:''},{portrait_unit_name:''},{portrait_unit_name:'npc_survival_builder_proxy'}
]){
 const t=setup({portrait:true});
 const valid={entindex:7,refresh_version:1,model_asset_id:cases[0][0],portrait_unit_name:cases[0][1]};
 t.api.updateSnapshot(valid);t.api.updateSnapshot({...valid,...patch,refresh_version:2});
 assert.equal(t.api.portraitState().key,'');assert.equal(t.overlay.values.visibility,'collapse');
 assert.equal(t.native().values.opacity,'0.35');assert.equal(t.overlay.GetParent(),t.context);
 assert.equal(t.metrics.setUnit.length,1);t.api.shutdown('invalid_done');
}
// Selection validation belongs to the real update entry, so a late old payload
// cannot clear a different selected hero or mutate its accepted snapshot.
{
 const t=setup({portrait:true}),valid={entindex:7,refresh_version:1,model_asset_id:cases[0][0],portrait_unit_name:cases[0][1]};
 t.api.updateSnapshot(valid);const prior=t.api.portraitState().snapshot;
 t.api.updateSnapshot({...valid,entindex:8,refresh_version:999});
 assert.equal(t.api.portraitState().snapshot,prior);assert.equal(t.metrics.setUnit.length,1);
 assert.equal(t.overlay.values.visibility,'visible');t.api.shutdown('late_done');
}
// Read the actual ten rebirth identities so staged previews and live bosses
// exercise the same production path, before and after snapshot delivery.
const fs=require('fs');
const archetypes=fs.readFileSync('scripts/vscripts/config/generated/monster_archetypes.lua','utf8');
const rebirths=[...archetypes.matchAll(/archetype_id = "rebirth_boss_(\d+)"[^\r\n]+unit_name = "([^"]+)"[^\r\n]+default_wearable_asset_id = "([^"]+)"/g)];
assert.equal(rebirths.length,10);
for(const [,rank,unit,asset] of rebirths){
 const t=setup({portrait:true});
 const jugg={entindex:7,refresh_version:1,model_asset_id:'hero_permanent_hero_blademaster',portrait_unit_name:'npc_dota_hero_juggernaut'};
 t.api.updateSnapshot(jugg);assert.equal(t.overlay.values.visibility,'visible');
 t.select(8,unit);t.api.portraitTransition('selection_changed');
 assert.equal(t.overlay.values.visibility,'collapse',rank+' must restore native immediately, before a snapshot');
 assert.equal(t.native().values.opacity,'0.35');
 const snapshot={entindex:8,refresh_version:2,model_asset_id:asset,portrait_unit_name:'npc_dota_hero_undying'};
 for(let frame=0;frame<64;frame++)t.api.updateSnapshot({...snapshot,refresh_version:frame+2});
 assert.equal(t.metrics.setUnit.length,1,'rebirth must never load our replacement scene');
 assert.equal(t.overlay.values.visibility,'collapse');assert.equal(t.overlay.GetParent(),t.context);
 assert.equal(t.api.portraitState().key,'');
 t.api.portraitTransition('same_selection');assert.equal(t.overlay.values.visibility,'collapse','no black transition mask');
 t.setMulti(true);t.api.cosmeticPortraitSentinel();assert.equal(t.overlay.values.visibility,'collapse');
 t.setMulti(false);t.api.cosmeticPortraitSentinel();assert.equal(t.overlay.values.visibility,'collapse');
 t.select(7,'npc_dota_hero_juggernaut');t.api.updateSnapshot({...jugg,refresh_version:100});
 assert.equal(t.overlay.values.visibility,'visible','player Juggernaut keeps the existing isolated portrait');
 t.api.updateSnapshot({...snapshot,refresh_version:999});
 assert.equal(t.overlay.values.visibility,'visible','late boss response must not clear the selected Juggernaut');
 t.api.shutdown('rebirth_done');assert.equal(t.jobs.size,0);
}
console.log('SEVEN_SINS_PORTRAIT_PASS: 12 existing split portraits and all 10 configured native rebirth portraits; pending/late snapshots, 64 stable updates, selection, multiselect and Juggernaut restoration');

// A Tools reload may retain the old outfit table. Its complete real metadata
// must never switch these entities back to an independent default-hero Scene.
const config={};require('vm').runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/rebirth_portrait_outfits.js','utf8'),{GameUI:{CustomUIConfig:()=>config}});
const outfits=config.SurvivalRebirthPortraitOutfits;
assert.equal(Object.keys(outfits).length,10);
for(const [,rank,unit,asset] of rebirths){
 const outfit=outfits[asset];assert(outfit);
 const t=setup({portrait:true,config:{SurvivalRebirthPortraitOutfits:outfits}});
 t.select(8,unit);t.api.portraitTransition('pending_snapshot');
 assert.equal(t.overlay.values.visibility,'collapse','native stays visible while metadata is pending');
 const snapshot={entindex:8,refresh_version:1,model_asset_id:asset,portrait_unit_name:outfit.source_unit};
 t.api.updateSnapshot(snapshot);
 assert.equal(t.overlay.values.visibility,'collapse',rank+' stays native when the real outfit snapshot arrives');
 assert.equal(t.overlay.FindChildTraverse('SurvivalRebirthOutfitPortraitSceneV1'),null);
 assert.equal(t.metrics.setUnit.length,0);assert.equal(t.metrics.econItem.length,0);assert.equal(t.metrics.econHero.length,0);
 for(let frame=0;frame<64;frame++){
  t.api.updateSnapshot({...snapshot,refresh_version:frame+2});t.api.portraitTransition('same_selection');
  assert.equal(t.overlay.values.visibility,'collapse','no replacement or transition mask after repeated snapshots');
 }
 // A stats-only payload keeps the real identity, while a late old payload is
 // still rejected by the shared selected-entity guard.
 t.api.updateSnapshot({entindex:8,refresh_version:70,health:123});
 assert.equal(t.overlay.values.visibility,'collapse');assert.equal(t.api.portraitState().snapshot.model_asset_id,asset);
 t.setMulti(true);t.api.cosmeticPortraitSentinel();assert.equal(t.overlay.values.visibility,'collapse');
 t.setMulti(false);t.api.cosmeticPortraitSentinel();assert.equal(t.overlay.values.visibility,'collapse');
 // Legacy generic unit identities use the same native policy once the
 // authoritative rebirth asset is known.
 t.select(8,'npc_survival_wave_monster');t.api.updateSnapshot({...snapshot,refresh_version:100});
 assert.equal(t.overlay.values.visibility,'collapse');assert.equal(t.metrics.setUnit.length,0);
 t.select(7,'npc_dota_hero_juggernaut');
 t.api.updateSnapshot({entindex:7,refresh_version:101,model_asset_id:'hero_permanent_hero_blademaster',portrait_unit_name:'npc_dota_hero_juggernaut'});
 assert.equal(t.metrics.setUnit.length,1,'player Juggernaut retains its prior path');assert.equal(t.metrics.econItem.length,0);
 t.api.updateSnapshot({...snapshot,refresh_version:999});assert.equal(t.api.portraitState().entity,7,'late outfit cannot dress the wrong unit');
 t.api.shutdown('outfit_done');assert.equal(t.jobs.size,0);
}
// Retire an already visible trial node left under Valve's HUD by a live Tools
// reload, so reusing the overlay for our builder/other units cannot reveal it.
{
 const t=setup({portrait:true}),trial=new t.Panel('SurvivalRebirthOutfitPortraitSceneV1',t.overlay,'DOTAScenePanel');
 let retired=0;trial.style.visibility='visible';trial.DeleteAsync=()=>{retired++;trial.alive=false;};
 const [,rank,unit,asset]=rebirths[0];t.select(8,unit);t.api.portraitTransition('layout_reload');
 assert.equal(retired,1);assert.equal(trial.values.visibility,'collapse');assert.equal(t.overlay.values.visibility,'collapse');
 t.api.updateSnapshot({entindex:8,refresh_version:1,model_asset_id:asset,portrait_unit_name:outfits[asset].source_unit});
 t.select(7,'npc_dota_hero_juggernaut');
 t.api.updateSnapshot({entindex:7,refresh_version:2,model_asset_id:'hero_permanent_hero_blademaster',portrait_unit_name:'npc_dota_hero_juggernaut'});
 assert.equal(t.overlay.values.visibility,'visible');assert.equal(t.scene.values.visibility,'visible');assert.equal(retired,1);
 assert.equal(t.overlay.FindChildTraverse('SurvivalRebirthOutfitPortraitSceneV1'),null);
 t.api.shutdown('retired_done');
}
assert(!fs.readFileSync('panorama/src/layout/custom_game/survival_hud.xml','utf8').includes('/rebirth_portrait_outfits.js'),
 'the retired outfit trial is no longer loaded by the production HUD');
console.log('REBIRTH_NATIVE_PORTRAIT_PASS: ten real outfit snapshots and legacy identities stay native; stats-only, multiselect, late responses and retained trial cleanup');
