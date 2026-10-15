const assert = require('assert');
const {setup} = require('./test_combat_stats_callbacks.cjs');
const snapshot = version => ({entindex:7,refresh_version:version,
 model_asset_id:'builder_io_benevolent_companion',portrait_unit_name:'npc_dota_hero_wisp',
 portrait_item_def:'9235',attack_min:1,health:1000,max_health:1000});
function mapLoads(t,count,setUnits=0){
 assert.equal(t.metrics.setUnit.length,setUnits,'builder must use its self-contained map instead of bare SetUnit');
 assert.equal(t.metrics.econHero.length,0);assert.equal(t.metrics.econItem.length,0,'builder must not depend on an account econ loadout');
 const creations=t.metrics.created.filter(call=>call.id==='SurvivalBuilderIoPortraitScene');assert.equal(creations.length,count);
 for(const call of creations){
  assert.equal(call.type,'DOTAScenePanel');assert.strictEqual(call.parent,t.overlay);
  assert.deepStrictEqual(call.attributes,{map:'portraits/builder_io_companion_v1',camera:'builder_io_camera',particleonly:'false',antialias:'true','animate-during-pause':'true'});
  assert(call.panel.classNames.has('SurvivalTowerPortraitScene'),'the lazy map receives the real shared Scene sizing class');
  assert.equal(call.panel.hittest,false);assert.equal(call.panel.hittestchildren,false);
 }
}
function builderScene(t){return t.overlay.FindChildTraverse('SurvivalBuilderIoPortraitScene')}
{
 const t=setup({portrait:true});t.select(7,'npc_survival_builder_proxy');
 t.api.portraitTransition('builder_selected');
 assert.equal(t.native().values.opacity,'1','keep the native portrait input until its snapshot arrives');
 assert.equal(t.native().values.washColor,undefined,'keep the native proxy tint untouched');
 t.api.updateSnapshot(snapshot(1));
 mapLoads(t,1);assert.strictEqual(t.api.portraitState().scene,builderScene(t));assert.equal(t.scene.values.visibility,'collapse');
 assert.equal(t.overlay.values.visibility,'visible');assert.equal(t.overlay.GetParent(),t.nativeHost());
 t.api.cosmeticPortraitSentinel();
 const initial={parents:t.metrics.parents,order:t.metrics.order,geometry:t.metrics.geometryWrites,visibility:t.metrics.visibilityTransitions};
 for(let i=0;i<64;i++){
  t.api.updateSnapshot(snapshot(i+2));t.run([...t.jobs.keys()][0]);
  assert.equal(t.jobs.size,1);assert.equal(t.overlay.values.visibility,'visible');
 }
 mapLoads(t,1);
 assert.deepStrictEqual({parents:t.metrics.parents,order:t.metrics.order,geometry:t.metrics.geometryWrites,visibility:t.metrics.visibilityTransitions},initial);
 t.api.updateSnapshot({...snapshot(999),entindex:8});mapLoads(t,1);
 t.setMulti(true);t.run([...t.jobs.keys()][0]);
 assert.equal(t.overlay.values.visibility,'collapse');assert.equal(t.native().values.opacity,'0.35');
 assert.equal(builderScene(t).values.visibility,'collapse');assert.equal(t.scene.values.visibility,'collapse');
 t.setMulti(false);t.api.updateSnapshot(snapshot(66));mapLoads(t,1);
 t.select(8,'npc_dota_hero_axe');t.api.portraitTransition('hero_selected');
 assert.equal(t.overlay.values.visibility,'collapse');assert.equal(t.native().values.opacity,'0.35');
 t.api.shutdown('done');assert.equal(t.jobs.size,0);assert.equal(builderScene(t).values.visibility,'collapse');assert.equal(t.scene.values.visibility,'collapse');
}
for(const patch of [{model_asset_id:'builder_io_wrong'},{portrait_unit_name:'npc_dota_hero_ogre_magi'},
 {portrait_item_def:''},{portrait_item_def:'9236'},{portrait_item_def:null},{portrait_item_def:undefined}]){
 const t=setup({portrait:true});t.select(7,'npc_survival_builder_proxy');
 t.api.updateSnapshot({...snapshot(1),...patch});mapLoads(t,0);
 assert.equal(t.native().values.opacity,'0.35');t.api.shutdown('invalid');
}
{
 const t=setup({portrait:true});t.select(7,'npc_survival_wave_monster');
 t.api.updateSnapshot(snapshot(1));mapLoads(t,0);
 t.api.shutdown('wrong_role');
}
// Numeric item configuration is normalized before the strict 9235 opt-in.
{
 const t=setup({portrait:true});t.select(7,'npc_survival_builder_proxy');
 t.api.updateSnapshot({...snapshot(1),portrait_item_def:9235});mapLoads(t,1);t.api.shutdown('numeric_item');
}
// A destroyed map Scene is recreated, while replacing only the native anchor
// must reuse the same loaded model and leave the released handles alone.
{
 const t=setup({portrait:true});t.select(7,'npc_survival_builder_proxy');t.api.updateSnapshot(snapshot(1));
 const old=builderScene(t),styles=JSON.stringify(old.values);old.alive='throw';
 t.api.updateSnapshot(snapshot(2));const next=builderScene(t);mapLoads(t,2);assert.notStrictEqual(next,old);assert.strictEqual(t.api.portraitState().scene,next);
 assert.equal(JSON.stringify(old.values),styles);
 const anchor=t.native();anchor.GetParent().children=anchor.GetParent().children.filter(child=>child!==anchor);anchor.parent=null;
 const replacement=t.mountNative();t.api.updateSnapshot(snapshot(3));mapLoads(t,2);
 assert.equal(anchor.values.opacity,'0.35');assert.equal(replacement.values.opacity,'1');assert.equal(t.overlay.GetParent(),replacement.GetParent());
 t.api.shutdown('scene_rebuild');assert.equal(replacement.values.opacity,'0.35');
}
// A native creation failure during the real sentinel cannot stop its next job
// or turn an invalid Scene into a reusable loaded portrait.
for(const failure of ['throw','null','invalid']){
 const t=setup({portrait:true});t.select(7,'npc_survival_builder_proxy');t.api.updateSnapshot(snapshot(1));
 t.api.cosmeticPortraitSentinel();const old=builderScene(t);old.alive=false;
 const create=t.panorama.CreatePanel;let failedAttempts=0;
 t.panorama.CreatePanel=(type,parent,id,attributes)=>{
  if(id==='SurvivalBuilderIoPortraitScene'&&failedAttempts===0){
   failedAttempts++;
   if(failure==='throw')throw Error('native map creation unavailable');
   if(failure==='null')return null;
   return {IsValid:()=>false};
  }
  return create(type,parent,id,attributes);
 };
 assert.doesNotThrow(()=>t.run([...t.jobs.keys()][0]),failure+' must not abort the scheduled sentinel');
 assert.equal(failedAttempts,1);assert.equal(t.jobs.size,1);assert.equal(t.api.portraitState().scene,null);assert.equal(t.api.portraitState().key,'');
 assert.equal(t.overlay.values.visibility,'collapse');assert.equal(t.native().values.opacity,'0.35');mapLoads(t,1);
 assert.doesNotThrow(()=>t.run([...t.jobs.keys()][0]));const recovered=builderScene(t);
 assert(recovered&&recovered!==old);assert.strictEqual(t.api.portraitState().scene,recovered);
 assert.equal(recovered.values.visibility,'visible');assert.equal(t.overlay.values.visibility,'visible');assert.equal(t.jobs.size,1);mapLoads(t,2);
 for(let tick=0;tick<64;tick++)t.run([...t.jobs.keys()][0]);
 assert.strictEqual(builderScene(t),recovered);assert.equal(t.jobs.size,1);mapLoads(t,2);
 t.api.shutdown('creation_failure_'+failure);assert.equal(t.jobs.size,0);
}
// Hero and builder scenes switch visibility while the loaded Io map stays alive.
{
 const t=setup({portrait:true});t.select(7,'npc_survival_builder_proxy');t.api.updateSnapshot(snapshot(1));const originalMap=builderScene(t);
 t.select(8,'npc_dota_hero_doom_bringer');t.api.portraitTransition('hero_selected');
 t.api.updateSnapshot({entindex:8,refresh_version:1,model_asset_id:'hero_permanent_hero_doom',portrait_unit_name:'npc_dota_hero_doom_bringer'});
 assert.deepStrictEqual(t.metrics.setUnit.map(call=>call.args),[['npc_dota_hero_doom_bringer','default',false]]);
 assert.equal(builderScene(t).values.visibility,'collapse');assert.equal(t.scene.values.visibility,'visible');
 t.select(7,'npc_survival_builder_proxy');t.api.portraitTransition('builder_return');t.api.updateSnapshot(snapshot(2));
 mapLoads(t,1,1);assert.strictEqual(builderScene(t),originalMap);assert.equal(builderScene(t).values.visibility,'visible');assert.equal(t.scene.values.visibility,'collapse');
 t.api.cosmeticPortraitSentinel();for(let i=3;i<67;i++){t.api.updateSnapshot(snapshot(i));t.run([...t.jobs.keys()][0])}
 mapLoads(t,1,1);
 assert.equal(t.overlay.values.visibility,'visible');t.api.shutdown('builder_hero_round_trip');
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
 t.api.updateSnapshot(snapshot(1));visible(overlayZ);assert.equal(builderScene(t).values.visibility,'visible');
 t.api.cosmeticPortraitSentinel();visible(overlayZ);
 // A same-node Valve layer rewrite is repaired without reloading the model.
 native.values.zIndex='9.0';t.run([...t.jobs.keys()][0]);
 assert.equal(Number(t.overlay.values.zIndex),10);assert.equal(native.values.zIndex,'9.0');
 mapLoads(t,1);assert.equal(builderScene(t).values.visibility,'visible');
 t.api.shutdown('builder_layer_complete');assert.equal(native.values.opacity,'0.35');assert.equal(native.values.washColor,'#345678cc');
}
console.log('BUILDER_PORTRAIT_PASS: actual lazy map node and creation attributes, no SetUnit/econ calls, strict role/asset/item, 64 stable ticks, Scene/anchor replacement, timer-safe throw/null/invalid creation retry, two-Scene selection/multi/shutdown visibility and native input/tint preservation; rendered pixels not simulated');
