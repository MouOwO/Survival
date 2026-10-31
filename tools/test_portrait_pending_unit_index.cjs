// Production pending-metadata path: catalog enumeration is initialization only.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const {setup}=require('./test_combat_stats_callbacks.cjs');
const catalogSource=fs.readFileSync('panorama/src/scripts/custom_game/monster_portrait_scenes.js','utf8');
const rendererSource=fs.readFileSync('panorama/src/scripts/custom_game/monster_portrait_renderer.js','utf8');
function fixture(mode){
 let now=1000,scans=0;
 const t=setup({portrait:true,date:{now:()=>now}});
 const ctx={$:t.panorama,GameUI:{CustomUIConfig:()=>t.cfg},Date:{now:()=>now}};
 vm.runInNewContext(catalogSource,ctx);
 const catalog=t.cfg.SurvivalMonsterPortraitScenes;
 const counted=()=>new Proxy(catalog,{ownKeys(target){scans++;return Reflect.ownKeys(target);}});
 t.cfg.SurvivalMonsterPortraitScenes=counted();
 if(mode==='real')vm.runInNewContext(rendererSource,ctx);
 else if(mode==='legacy')t.cfg.SurvivalMonsterPortraitRenderer={Hide(){},HasAsset(){return false;}};
 t.select(7,'npc_dota_hero_axe');
 const initialized=scans;
 for(let i=0;i<300;i++){now++;t.api.portraitTransition('metadata_pending');t.jobs.clear();assert.equal(t.overlay.values.visibility,'visible');}
 const waitingScans=scans-initialized;
 assert.equal(waitingScans,mode==='real'?0:1,mode+' repeats must not rescan197 assets');
 if(mode==='real'){
  const r=t.cfg.SurvivalMonsterPortraitRenderer;
  assert(r.HasUnitName('npc_dota_hero_axe'));
  assert(!r.HasUnitName('__proto__'));assert(!r.HasUnitName('npc_unlisted_fixture'));
  for(let i=0;i<300;i++)assert(r.HasUnitName('npc_dota_hero_axe'));
  assert.equal(scans,initialized,'direct unit-name lookups are indexed');
 }else{
  t.cfg.SurvivalMonsterPortraitScenes=counted();now++;
  t.api.portraitTransition('new_catalog');
  assert.equal(scans-initialized,2,'a new catalog identity builds exactly once');
  for(let i=0;i<100;i++)t.api.portraitTransition('same_new_catalog');
  assert.equal(scans-initialized,2);
 }
 return {mode,initial_catalog_scans:initialized,pending_calls:300,pending_catalog_scans:waitingScans};
}
const results=['real','legacy','missing'].map(fixture);
console.log('PORTRAIT_PENDING_UNIT_INDEX_PASS '+JSON.stringify(results));
