// Reuse the existing full-production-module Panorama fixture. No stubs for
// hide, mount, geometry, update or sentinel; only native engine APIs are mocked.
const assert=require('assert');
const {setup}=require('./test_combat_stats_callbacks.cjs');
const cases=[
 ['hero_permanent_hero_doom','npc_dota_hero_doom_bringer',''],
 ['hero_permanent_hero_blademaster','npc_dota_hero_juggernaut',''],
 ['tower_keeper_of_the_light','npc_dota_hero_tinker',''],
 ['monster_boss_rebirth_01_phalanx','npc_dota_hero_undying',''],
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
 assert.equal(t.overlay.GetParent(),t.nativeHost());assert.equal(t.native().values.opacity,'0');
 const initial={parents:t.metrics.parents,order:t.metrics.order,geometryWrites:t.metrics.geometryWrites,visibility:t.metrics.visibilityTransitions};
 t.api.cosmeticPortraitSentinel();
 for(let frame=0;frame<64;frame++){
  t.api.updateSnapshot({...snapshot,refresh_version:frame+2});t.run([...t.jobs.keys()][0]);
  assert.equal(t.jobs.size,1);
 }
 assert.equal(t.metrics.setUnit.length,1,asset+' must keep one Scene load for complete stable snapshots');
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
console.log('SEVEN_SINS_PORTRAIT_PASS: real shared update/hide/mount/position/sentinel; 12 assets including Doom/Juggernaut/tower/boss/wave/archive/6 challenges, 64 stable frames each, exact allowlist and multi-selection cleanup');
