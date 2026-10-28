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

// The native fallback above remains available without the outfit module. With
// its real generated data loaded, all ten use the official slot/item/style API.
const config={};require('vm').runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/rebirth_portrait_outfits.js','utf8'),{GameUI:{CustomUIConfig:()=>config}});
const outfits=config.SurvivalRebirthPortraitOutfits;
assert.equal(Object.keys(outfits).length,10);
let totalItems=0;
for(const [,rank,unit,asset] of rebirths){
 const outfit=outfits[asset];assert(outfit);
 const t=setup({portrait:true,config:{SurvivalRebirthPortraitOutfits:outfits}});
 t.select(8,unit);t.api.portraitTransition('pending_snapshot');
 assert.equal(t.overlay.values.visibility,'collapse','native stays visible while metadata is pending');
 const snapshot={entindex:8,refresh_version:1,model_asset_id:asset,portrait_unit_name:outfit.source_unit};
 t.api.updateSnapshot(snapshot);
 const scene=t.overlay.FindChildTraverse('SurvivalRebirthOutfitPortraitSceneV1');assert(scene);
 assert.equal(scene.attributes.drawbackground,'true');assert.equal(scene.attributes.deferredalpha,'false');
 assert.equal(scene.values.width,'100%');assert.equal(scene.values.height,'100%');
 assert.equal(scene.hittest,false);assert.equal(scene.hittestchildren,false);
 assert.equal(t.overlay.values.visibility,'visible');
 assert.deepEqual(t.metrics.setUnit.map(c=>c.args),[[outfit.unit,'default',false]]);
 assert.deepEqual(t.metrics.econItem.map(c=>c.args),JSON.parse(JSON.stringify(outfit.items)));
 assert.equal(t.metrics.econHero.length,0,'no account loadout binding');
 assert.equal(scene.values.transform,'scale3d(1, 1, 1)','rebirth uses its native portrait framing');
 for(let frame=0;frame<64;frame++)t.api.updateSnapshot({...snapshot,refresh_version:frame+2});
 assert.equal(t.metrics.setUnit.length,1);assert.equal(t.metrics.econItem.length,outfit.items.length,'stable updates do not re-equip');
 t.setMulti(true);t.api.cosmeticPortraitSentinel();assert.equal(t.overlay.values.visibility,'collapse');
 t.setMulti(false);t.api.cosmeticPortraitSentinel();assert.equal(t.overlay.values.visibility,'visible');
 assert.equal(t.metrics.setUnit.length,1,'multiselect round trip reuses the dressed scene');
 scene.alive=false;
 t.api.updateSnapshot({...snapshot,refresh_version:100});
 assert.equal(t.metrics.setUnit.length,2);assert.equal(t.metrics.econItem.length,outfit.items.length*2,'a rebuilt scene must equip again');
 t.select(7,'npc_dota_hero_juggernaut');
 t.api.updateSnapshot({entindex:7,refresh_version:101,model_asset_id:'hero_permanent_hero_blademaster',portrait_unit_name:'npc_dota_hero_juggernaut'});
 assert.equal(t.metrics.econItem.length,outfit.items.length*2,'player Juggernaut retains its prior path');
 t.api.updateSnapshot({...snapshot,refresh_version:999});assert.equal(t.api.portraitState().entity,7,'late outfit cannot dress the wrong unit');
 totalItems+=outfit.items.length;t.api.shutdown('outfit_done');assert.equal(t.jobs.size,0);
}
// Unsupported or rejected native methods must restore Valve's live portrait,
// clear partial cosmetics once and never retry every 0.1 seconds or mask it.
for(const failure of ['missing','throw','false']){
 const t=setup({portrait:true,config:{SurvivalRebirthPortraitOutfits:outfits}});
 const [,rank,unit,asset]=rebirths[0],outfit=outfits[asset];t.select(8,unit);
 const create=t.panorama.CreatePanel;
 t.panorama.CreatePanel=(...args)=>{const scene=create(...args);
  if(scene.id==='SurvivalRebirthOutfitPortraitSceneV1'){
   if(failure==='missing')scene.ReplaceEconItemSlot=null;else scene.econItemFailure=failure;
  }return scene;
 };
 const snapshot={entindex:8,refresh_version:1,model_asset_id:asset,portrait_unit_name:outfit.unit};
 t.api.updateSnapshot(snapshot);
 for(let frame=0;frame<64;frame++){t.api.updateSnapshot({...snapshot,refresh_version:frame+2});t.api.portraitTransition('same_selection');}
 assert.equal(t.overlay.values.visibility,'collapse');assert.equal(t.overlay.GetParent(),t.context);
 assert.equal(t.native().values.opacity,'0.35');assert.equal(t.metrics.clearScene,1);
 assert.equal(t.metrics.econItem.length,failure==='missing'?0:1);
 assert.equal(t.metrics.econHero.length,0);t.api.shutdown('failure_done');
}
console.log('REBIRTH_OUTFIT_SCENE_PASS: ten real outfits, '+totalItems+' official slot replacements, stable reuse/rebuild, no account loadouts, native fallback on missing/false/throw');
