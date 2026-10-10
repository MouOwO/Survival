'use strict';
// Real production portrait callbacks; no Dota/GUI/pixels or source writes.
const assert=require('node:assert/strict'),path=require('node:path');
const candidate=process.argv[2]||'panorama/src/scripts/custom_game/combat_stats.js';
const before=process.argv[3];
const fixture=path.join(process.cwd(),'tools/test_combat_stats_callbacks.cjs');
function run(source){
  process.argv[2]=source;delete require.cache[require.resolve(fixture)];
  const {setup}=require(fixture),traces=[];
  function capture(t,label){
    const native=t.native(),group=native&&native.GetParent().GetParent();
    const state=t.api.portraitState();
    traces.push({label,overlay:{...t.overlay.values},scene:{...t.scene.values},
      native:native?{...native.values}:null,group:group?{...group.values}:null,
      mode:state.mode,key:state.key,entity:state.entity,sceneActive:!!state.scene,
      setUnits:t.metrics.setUnit.length,parent:t.overlay.GetParent()===t.context?'home':'native'});
  }
  const builder=version=>({entindex:7,refresh_version:version,model_asset_id:'builder_io_benevolent_companion',
    portrait_unit_name:'npc_dota_hero_wisp',portrait_item_def:'9235',health:100,max_health:100});
  function rootReads(t){let calls=[];const original=t.root.FindChildTraverse;t.root.FindChildTraverse=function(id){calls.push(id);return original.call(this,id);};return ()=>{const value=calls;calls=[];return value;};}

  // Repeated empty/unsupported/native/portal snapshots still restore external state.
  const t=setup({portrait:true});const reads=rootReads(t);
  t.select(7,'npc_survival_builder_proxy');t.api.updateSnapshot(builder(1));
  t.select(8,'building_main_city');t.api.updateSnapshot({entindex:8,refresh_version:1});
  capture(t,'main_city');reads();
  const stableCalls=[];
  for(let i=0;i<40;i++){t.api.portraitHide('stable_main_city');stableCalls.push(reads().filter(id=>id==='PortraitGroup').length);}
  assert.equal(t.native().values.opacity,'0.35');assert.equal(t.metrics.setUnit.length,1);
  capture(t,'stable_city');
  t.native().values.opacity='0.01';t.api.portraitHide('external_legacy_leaf');
  assert.equal(t.native().values.opacity,'1');capture(t,'legacy_leaf_same_entity');
  const group=t.native().GetParent().GetParent();group.values.opacity='0.01';
  t.native().__survivalPortraitDimmed=true;t.native().__survivalPortraitOriginalOpacity='0';
  t.api.portraitHide('external_markers');
  assert.equal(t.native().values.opacity,'0');assert.equal(group.values.opacity,'1');capture(t,'recorded_zero_and_group');
  group.values.opacity='0.01';group.__survivalPortraitDimmed=true;
  t.api.portraitHide('owned_group');assert.equal(group.values.opacity,'0.01');
  group.__survivalPortraitDimmed=false;capture(t,'owned_group_not_reset');
  for(const [id,name] of [[99,'npc_dota_unit_twin_gate_portal'],[100,'npc_dota_hero_lina'],[-1,'']]){
    t.select(id,name);t.native().values.opacity='0.01';t.api.portraitUpdate(null);
    assert.equal(t.native().values.opacity,'1');assert.equal(t.overlay.values.visibility,'collapse');
    assert.equal(t.api.portraitState().entity,-1);capture(t,'unsupported_'+id);
  }

  // Same entity/generation and a still-valid old panel cannot justify a cross-call earlyout.
  t.select(8,'building_main_city');const old=t.native();
  old.GetParent().children=old.GetParent().children.filter(p=>p!==old);old.parent=null;
  const next=t.mountNative();next.__survivalPortraitDimmed=true;next.__survivalPortraitOriginalOpacity='0.6';next.values.opacity='0';
  t.api.portraitHide('native_replacement_same_entity');assert.equal(next.values.opacity,'0.6');
  capture(t,'replacement_same_entity');
  next.actuallayoutwidth=0;next.values.opacity='0.01';t.api.portraitHide('unlaid_native');
  assert.equal(next.values.opacity,'0.01','An unusable leaf retains the original no-current behavior');capture(t,'unlaid');
  next.actuallayoutwidth=128;t.api.portraitHide('layout_recovers_same_entity');
  assert.equal(next.values.opacity,'1');capture(t,'layout_recovers');
  t.select(7,'npc_survival_builder_proxy');t.api.updateSnapshot(builder(2));
  assert.equal(t.metrics.setUnit.length,1,'Hide lookup reuse cannot invalidate successfully loaded model content');
  assert.equal(t.api.portraitState().entity,7);capture(t,'return_builder_no_reload');
  t.setMulti(true);t.api.cosmeticPortraitSentinel();assert.equal(t.overlay.values.visibility,'collapse');capture(t,'multi');
  t.api.shutdown('end');capture(t,'shutdown');

  // Negative native lookup must be re-evaluated on the next call, even with no selection.
  const missing=setup();const missingReads=rootReads(missing);
  missing.api.portraitHide('missing');const missingQueryCount=missingReads().length;
  const appeared=missing.mountNative();appeared.values.opacity='0.01';missing.api.portraitHide('late_native_same_entity');
  assert.equal(appeared.values.opacity,'1');capture(missing,'late_creation_after_negative');
  // A native scene with original0.01 gets restored then its exact old legacy marker is cleared.
  const legacy=setup({portrait:true});legacy.native().values.opacity='0.01';
  legacy.select(7,'npc_survival_builder_proxy');legacy.api.updateSnapshot(builder(1));legacy.api.portraitHide('legacy_after_owned');
  assert.equal(legacy.native().values.opacity,'1');capture(legacy,'legacy_original');
  return {traces,stableCalls,missingQueryCount};
}
const current=run(candidate);
assert(current.stableCalls.every(count=>count===2),'One native leaf lookup plus one group cleanup per stable hide');
assert.equal(current.missingQueryCount,8,'Seven root ID lookups once plus one group cleanup, no negative cache');
if(before){
  const baseline=run(before);assert.deepEqual(current.traces,baseline.traces,'Exact supported/unsupported/legacy/replacement/zero/layout/portal ownership and visibility trace preserved');
  assert(baseline.stableCalls.every(count=>count===3));assert.equal(baseline.missingQueryCount,15);
  console.log('PORTRAIT_RESTORE_LOOKUP_REUSE_PASS: actual callbacks exact traces, native lookup2->1, missing rootqueries15->8, no cross-call cache, late/replacement/layout/portal/zero/multi/shutdown');
}else console.log('PORTRAIT_RESTORE_LOOKUP_REUSE_PASS: candidate actual callbacks and dynamic counterexamples');
