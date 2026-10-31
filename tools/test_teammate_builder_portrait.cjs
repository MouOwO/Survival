// Real combat portrait controller/renderer; only native panels and entities are mocked.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const {setup}=require('./test_combat_stats_callbacks.cjs');
function fixture(){
 let now=1000;
 const t=setup({portrait:true,date:{now:()=>now},events:{SendCustomGameEventToServer(){}}});
 t.Panel.prototype.DeleteAsync=function(){this.alive=false};
 t.Panel.prototype.BHasClass=function(name){return !!this.classNames?.has(name)};
 t.panorama.RegisterEventHandler=(event,p,fn)=>p[event]=fn;
 const ctx={$:t.panorama,GameUI:{CustomUIConfig:()=>t.cfg},Date:{now:()=>now}};
 for(const name of ['monster_portrait_scenes','monster_portrait_renderer'])
  vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/'+name+'.js','utf8'),ctx);
 t.advance=n=>now+=n;
 t.ready=e=>{e.scene.AddClass('SceneLoaded');e.scene.parent.FindChildTraverse('Background').ImageLoaded()};
 t.builder=id=>({entindex:id,model_asset_id:'builder_io_benevolent_companion',portrait_unit_name:'npc_dota_hero_wisp',portrait_item_def:'9235',portrait_model_name:'models/heroes/wisp/wisp.vmdl'});
 t.addQuery=()=>{
  const vertical=new t.Panel('QueryVertical',t.root),middle=new t.Panel('MidSection',vertical);
  const host=new t.Panel('PortraitContainer',middle),native=new t.Panel('QueryUnitHeroPortrait',host,'DOTAPortrait');
  native.point={x:120,y:820};host.point={x:100,y:800};
  return {vertical,host,native};
 };
 return t;
}
const t=fixture(),query=t.addQuery(),r=t.cfg.SurvivalMonsterPortraitRenderer;
t.select(101,'npc_survival_builder_proxy');
const prepared=r.Prepare(t.overlay,'builder_io_benevolent_companion');t.ready(prepared);
t.api.updateSnapshot(t.builder(101));t.advance(101);t.api.portraitUpdate(t.builder(101));
assert.equal(t.overlay.parent,t.nativeHost(),'own builder mounts at the main native portrait');
t.select(202,'npc_survival_builder_proxy');
t.api.selectionEvent('query_unit_event',{PlayerID:0});
t.api.updateSnapshot(t.builder(202));t.advance(101);t.api.portraitUpdate(t.builder(202));
assert.equal(t.overlay.parent,query.host,'a teammate builder must mount inside the inspected-unit portrait');
assert.equal(t.api.portraitState().entity,202);assert.equal(t.overlay.values.visibility,'visible');
assert.equal(query.native.__survivalPortraitDimmed,true,'query native anchor belongs to the custom overlay');
assert.equal(query.native.values.opacity,'1','keep the native query portrait input and pixels available beneath the overlay');
assert.equal(t.native().values.opacity,'0.35','main native portrait opacity is restored');
const scene=t.api.portraitState().scene,created=r.Inspect().created;
let anchorSearches=0;
const find=t.root.FindChildTraverse;
t.root.FindChildTraverse=function(id){if(['PortraitGroup','QueryUnitHeroPortrait'].includes(id))anchorSearches++;return find.call(this,id)};
for(let i=0;i<300;i++){t.advance(100);t.api.portraitUpdate(t.builder(202))}
assert.equal(anchorSearches,0,'stable query updates must not repeat full HUD anchor searches');
assert.equal(r.Inspect().created,created,'all player builders share one loaded appearance');
assert.equal(t.api.portraitState().scene,scene);
// A stale response from our own builder cannot replace the inspected teammate.
t.api.updateSnapshot(t.builder(101));assert.equal(t.api.portraitState().entity,202);
t.select(303,'npc_survival_builder_proxy');t.api.updateSnapshot(t.builder(303));
assert.equal(t.overlay.parent,query.host);assert.equal(t.api.portraitState().entity,303);
// Native query reconstruction invalidates exactly the old cached panel.
query.native.alive=false;query.vertical.alive=false;
t.root.children=t.root.children.filter(panel=>panel!==query.vertical);query.vertical.parent=null;
const rebuilt=t.addQuery();t.api.portraitUpdate(t.builder(303));
assert.equal(t.overlay.parent,rebuilt.host,'recreated query portrait receives the retained scene');
const afterRebuild=anchorSearches;
for(let i=0;i<300;i++)t.api.portraitUpdate(t.builder(303));
assert.equal(anchorSearches,afterRebuild,'one reconstruction must not turn into repeated scans');
rebuilt.vertical.visible=false;t.api.portraitUpdate(t.builder(303));
assert.equal(t.overlay.values.visibility,'collapse','a hidden query branch cannot host a visible scene');
rebuilt.vertical.visible=true;t.api.portraitUpdate(t.builder(303));
assert.equal(t.overlay.parent,rebuilt.host,'showing the same branch reuses its cached anchor');
t.select(101,'npc_survival_builder_proxy');t.api.selectionEvent('selected_unit_event',{PlayerID:0});
t.api.updateSnapshot(t.builder(101));
assert.equal(t.overlay.parent,t.nativeHost(),'returning to our builder restores the main anchor');
assert.equal(r.Inspect().created,created);assert.equal(t.metrics.setUnit.length,0);
t.api.shutdown('teammate_portrait_done');
const late=fixture();late.select(404,'npc_survival_builder_proxy');
late.api.selectionEvent('query_unit_event',{PlayerID:0});
const pending=late.cfg.SurvivalMonsterPortraitRenderer.Prepare(late.overlay,'builder_io_benevolent_companion');
late.ready(pending);late.api.updateSnapshot(late.builder(404));
const arrived=late.addQuery();
// The native child arrived during the controller's bounded selection retry window.
const retry=[...late.jobs].find(([,job])=>job.delay===0.2);assert(retry);
late.run(retry[0]);late.api.portraitUpdate(late.builder(404));
assert.equal(late.overlay.parent,arrived.host,'a late native query child is discovered during bounded event retries');
late.api.shutdown('late_query_done');
const cold=fixture(),coldQuery=cold.addQuery();cold.select(505,'npc_survival_builder_proxy');
cold.api.selectionEvent('query_unit_event',{PlayerID:0});cold.api.updateSnapshot(cold.builder(505));
assert.equal(cold.overlay.parent,coldQuery.host,'first cold teammate selection covers the query portrait');
const loading=cold.cfg.SurvivalMonsterPortraitRenderer.Prepare(cold.overlay,'builder_io_benevolent_companion');
cold.ready(loading);cold.advance(101);cold.api.portraitUpdate(cold.builder(505));
cold.advance(101);cold.api.portraitUpdate(cold.builder(505));
assert.equal(cold.api.portraitState().mode,'monster_scene');
assert.equal(cold.api.portraitState().entity,505);assert.equal(cold.overlay.parent,coldQuery.host);
cold.api.shutdown('cold_query_done');
console.log('TEAMMATE_BUILDER_PORTRAIT_PASS '+JSON.stringify({stable_updates:600,stable_anchor_searches:0,created_scenes:created,rebuild_anchor_searches:afterRebuild}));
