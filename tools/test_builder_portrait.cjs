const assert = require('assert');
const {setup} = require('./test_combat_stats_callbacks.cjs');
const snapshot = version => ({entindex:7,refresh_version:version,
 model_asset_id:'builder_io_benevolent_companion',portrait_unit_name:'npc_dota_hero_wisp',
 portrait_item_def:'9235',attack_min:1,health:1000,max_health:1000});
{
 const t=setup({portrait:true});t.select(7,'npc_survival_builder_proxy');
 t.api.portraitTransition('builder_selected');
 assert.equal(t.native().values.opacity,'1','keep the native portrait input until its snapshot arrives');
 assert.equal(t.native().values.washColor,undefined,'keep the native proxy tint untouched');
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
// Native style getters return decimal z-index strings, not just integer text.
// Keep the Io scene above the native proxy while all native input stays intact.
for(const [nativeZ,overlayZ] of [['0.0',1],['4.0',5],['2.5',3.5],['-2.5',-1.5],['invalid',1],['Infinity',1],[undefined,1]]){
 const t=setup({portrait:true});t.select(7,'npc_survival_builder_proxy');const native=t.native();
 native.values.zIndex=nativeZ;native.values.washColor='#345678cc';
 native.SetPanelEvent=()=>{throw Error('builder portrait must not replace native input handlers')};
 const input={hittest:native.hittest,hittestchildren:native.hittestchildren};
 function visible(z){
  assert.equal(Number(t.overlay.values.zIndex),z);assert.equal(native.values.zIndex,nativeZ);
  if(Number.isFinite(Number(nativeZ)))assert(Number(t.overlay.values.zIndex)>Number(nativeZ),'the custom Io scene must paint above DOTAPortrait');
  assert.equal(native.values.opacity,'1');assert.equal(native.values.washColor,'#345678cc');assert.equal(t.metrics.nativeWashWrites,0);
  assert.equal(native.hittest,input.hittest);assert.equal(native.hittestchildren,input.hittestchildren);
  assert.equal(t.overlay.hittest,false);assert.equal(t.overlay.hittestchildren,false);assert.equal(t.scene.hittest,false);
 }
 t.api.portraitTransition('builder_layer_pending');visible(overlayZ);
 t.api.updateSnapshot(snapshot(1));visible(overlayZ);assert.equal(t.scene.values.visibility,'visible');
 t.api.cosmeticPortraitSentinel();visible(overlayZ);
 // A same-node Valve layer rewrite is repaired without reloading the model.
 native.values.zIndex='9.0';t.run([...t.jobs.keys()][0]);
 assert.equal(Number(t.overlay.values.zIndex),10);assert.equal(native.values.zIndex,'9.0');
 assert.equal(t.metrics.setUnit.length,1);assert.equal(t.scene.values.visibility,'visible');
 t.api.shutdown('builder_layer_complete');assert.equal(native.values.opacity,'0.35');assert.equal(native.values.washColor,'#345678cc');
}
console.log('BUILDER_PORTRAIT_PASS: real production update/transition/sentinel, proxy-to-Io mapping, stable snapshots, strict role, selection/failure recovery, decimal/nonzero/invalid native layers, same-anchor layer repair and native input/tint preservation');
