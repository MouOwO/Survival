const assert = require('assert');
const {setup} = require('./test_combat_stats_callbacks.cjs');
const snapshot = version => ({entindex:7,refresh_version:version,
 model_asset_id:'builder_io_benevolent_companion',portrait_unit_name:'npc_dota_hero_wisp',
 portrait_item_def:'9235',attack_min:1,health:1000,max_health:1000});
{
 const t=setup({portrait:true});t.select(7,'npc_survival_builder_proxy');
 t.api.portraitTransition('builder_selected');
 assert.equal(t.native().values.opacity,'0','mask the invisible proxy until its snapshot arrives');
 t.api.updateSnapshot(snapshot(1));
 assert.deepStrictEqual(t.metrics.setUnit.map(call=>call.args),[['npc_dota_hero_wisp','default',false]]);
 assert.equal(t.overlay.values.visibility,'visible');assert.equal(t.overlay.GetParent(),t.nativeHost());
 t.api.cosmeticPortraitSentinel();
 const initial={parents:t.metrics.parents,order:t.metrics.order,geometry:t.metrics.geometryWrites,visibility:t.metrics.visibilityTransitions};
 for(let i=0;i<64;i++){
  t.api.updateSnapshot(snapshot(i+2));t.run([...t.jobs.keys()][0]);
  assert.equal(t.jobs.size,1);assert.equal(t.overlay.values.visibility,'visible');
 }
 assert.equal(t.metrics.setUnit.length,1,'builder stat updates must not reload or flash the portrait');
 assert.deepStrictEqual({parents:t.metrics.parents,order:t.metrics.order,geometry:t.metrics.geometryWrites,visibility:t.metrics.visibilityTransitions},initial);
 t.api.updateSnapshot({...snapshot(999),entindex:8});assert.equal(t.metrics.setUnit.length,1);
 t.setMulti(true);t.run([...t.jobs.keys()][0]);
 assert.equal(t.overlay.values.visibility,'collapse');assert.equal(t.native().values.opacity,'0.35');
 t.setMulti(false);t.api.updateSnapshot(snapshot(66));assert.equal(t.metrics.setUnit.length,1,'returning from hidden selection reuses the loaded builder scene');
 t.select(8,'npc_dota_hero_axe');t.api.portraitTransition('hero_selected');
 assert.equal(t.overlay.values.visibility,'collapse');assert.equal(t.native().values.opacity,'0.35');
 t.api.shutdown('done');assert.equal(t.jobs.size,0);
}
for(const patch of [{model_asset_id:'builder_io_wrong'},{portrait_unit_name:'npc_dota_hero_ogre_magi'}]){
 const t=setup({portrait:true});t.select(7,'npc_survival_builder_proxy');
 t.api.updateSnapshot({...snapshot(1),...patch});assert.equal(t.metrics.setUnit.length,0);
 assert.equal(t.native().values.opacity,'0.35');t.api.shutdown('invalid');
}
{
 const t=setup({portrait:true});t.select(7,'npc_survival_wave_monster');
 t.api.updateSnapshot(snapshot(1));assert.equal(t.metrics.setUnit.length,0,'builder opt-in must not affect other unit roles');
 t.api.shutdown('wrong_role');
}
for(const failure of ['false','throw']){
 const t=setup({portrait:true});t.select(7,'npc_survival_builder_proxy');t.scene.setUnitFailure=failure;
 t.api.portraitTransition('pending');t.api.updateSnapshot(snapshot(1));
 assert.equal(t.native().values.opacity,'0.35');assert.equal(t.overlay.values.visibility,'collapse');
 t.scene.setUnitFailure=null;t.api.updateSnapshot(snapshot(2));assert.equal(t.overlay.values.visibility,'visible');
 t.scene.alive='throw';assert.doesNotThrow(()=>t.api.portraitHide('released'));t.api.shutdown('done');
}
console.log('BUILDER_PORTRAIT_PASS: real production update/transition/sentinel, proxy-to-Io mapping, stable snapshots, strict role, selection and native failure recovery');
