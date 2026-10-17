"use strict";
// Exercise the real production panel with native write counters. No Dota/GUI.
const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const production=fs.readFileSync('panorama/src/scripts/custom_game/production_progress.js','utf8');
function fixture(){
 const nodes={},events={},sent=[],metrics={styles:0,styleReads:0,images:0,abilities:0};let unit=10,time=10;
 function panel(type,parent,id){
  const values={},p={id:id||'',parent,paneltype:type,children:[],handlers:{},classes:new Set(),visible:true,text:'',alive:true,
   IsValid(){return this.alive;},FindChildTraverse(key){return nodes[key]||null;},
   AddClass(c){this.classes.add(c);},SetHasClass(c,on){on?this.classes.add(c):this.classes.delete(c);},
   RemoveAndDeleteChildren(){this.children=[];},SetPanelEvent(n,fn){this.handlers[n]=fn;},
   SetImage(uri){metrics.images++;if(this.failImage){this.failImage=false;throw new Error('native image setter failed');}this.image=uri;}};
  p.style=new Proxy(values,{get(t,k){metrics.styleReads++;return t[k];},set(t,k,v){metrics.styles++;if(p.failStyle===k){p.failStyle=null;throw new Error('native style setter failed');}t[k]=typeof v==='string'?v.replace(/(-?\d+)px/g,'$1.0000px'):v;return true;}});
  Object.defineProperty(p,'abilityname',{get(){return p.ability;},set(v){metrics.abilities++;if(p.failAbility){p.failAbility=false;throw new Error('native ability setter failed');}p.ability=v;}});
  if(parent)parent.children.push(p);if(id)nodes[id]=p;return p;
 }
 const ctx=panel('Panel',null,'ctx');panel('Panel',ctx,'SurvivalProductionPanel');panel('Panel',ctx,'SurvivalResearchAutoMarkers');
 const cfg={SurvivalUILayers:{Top:()=>null},SurvivalSelectionResolver:{ResolveDisplayUnit:()=>unit}};
 const $=id=>nodes[id.slice(1)];$.GetContextPanel=()=>ctx;$.CreatePanel=panel;$.DispatchEvent=()=>{};$.Schedule=()=>{};
 const env={$,GameUI:{CustomUIConfig:()=>cfg},Game:{GetLocalPlayerID:()=>0,GetGameTime:()=>time},Players:{GetLocalPlayerPortraitUnit:()=>unit},
  Entities:{GetUnitName:id=>id===10?'building_main_city':'building_research_lab'},CustomNetTables:{GetTableValue:()=>null},
  GameEvents:{Subscribe:(n,fn)=>events[n]=fn,SendCustomGameEventToServer:(name,payload)=>sent.push({name,payload})}};
 vm.runInNewContext(production,env);const g={x:400,y:700,scale:.5,height:330,minimapSize:220,heroWidth:453,centerWidth:498};
 return {nodes,cfg,events,sent,metrics,g,env,setUnit:v=>unit=v,setTime:v=>time=v,
  refresh(){return cfg.SurvivalProductionHUD.Refresh(g,unit,true,[]);},
  snapshot(data){events.ui_selected_unit_stats_snapshot({success:1,player_id:0,entindex:unit,...data});},
  reload(){vm.runInNewContext(production,env);},reset(){for(const k of Object.keys(metrics))metrics[k]=0;}};
}
function options(){return [1,2,3,4,5].map(level=>({training_id:'worker_'+level,level,count:0,max_count:3,cost_wood:10,available:1,prerequisite_met:1}));}
const f=fixture();f.refresh();f.snapshot({training:{options:options(),queued:[{level:2}],active_job:{level:1,training_id:'worker_1',started_at:10,finish_at:20,duration:10}}});
f.refresh();f.reset();
for(let i=0;i<100;i++)f.refresh();
assert.equal(f.metrics.images,0,'identical current/queued/training portraits do not reissue native SetImage');
assert.equal(f.metrics.abilities,0);assert.equal(f.metrics.styles,0,'normalized native px text must not cause identical custom layout setters');
assert.equal(f.metrics.styleReads,0,'owned stable style assignments avoid native reads');
f.setTime(15);f.refresh();assert.equal(f.nodes.ProductionProgressFill.style.width,'50.0%');assert.equal(f.nodes.ProductionRemaining.text,'5s','clock remains live');
f.setTime(16);f.refresh();assert.equal(f.nodes.ProductionProgressFill.style.width,'60.0%');
const changed=options();changed[0].cost_wood=20;changed[0].count=3;f.snapshot({training:{options:changed,queued:[]}});
assert.equal(Array.from(f.cfg.SurvivalProductionHUD.Inspect().slots)[0],'worker_2','completed training reveals the next level immediately even when the card LV caption is hidden');
f.nodes.ProductionTrainingSlot0.handlers.onactivate();assert.equal(f.sent.at(-1).payload.training_id,'worker_2','cached art must not cache old click identity');
f.g.x=430;f.reset();f.refresh();assert(f.metrics.styles>0,'viewport geometry changes are applied');
f.reset();f.refresh();assert.equal(f.metrics.styles,0,'new geometry stabilizes');
// Failed native setters retry; successful assignments commit cache after success.
const icon=f.nodes.ProductionTrainingSlot0.children[0];delete icon.__productionImage;icon.failImage=true;f.reset();
assert.throws(()=>f.refresh(),/native image setter failed/);f.refresh();assert.equal(f.metrics.images,2);
f.refresh();assert.equal(f.metrics.images,2,'successful retry then stable image');
delete f.nodes.SurvivalProductionPanel.__productionStyle;f.nodes.SurvivalProductionPanel.failStyle='position';
assert.throws(()=>f.refresh(),/native style setter failed/);f.refresh();f.reset();f.refresh();assert.equal(f.metrics.styles,0);
// Research queue refs and cancellation remain authoritative even when art is unchanged.
f.setUnit(20);f.refresh();
function research(id,name='ability_research_worker_attack'){return {researching:1,display_name:'伐木效率',ability_name:name,target_level:2,started_at:10,finish_at:20,duration:10,active_job:{job_id:'active'},queued:[{job_id:id,technology_group:'worker_attack',target_level:3,ability_name:name}]};}
f.snapshot({research:research('first')});f.refresh();f.reset();for(let i=0;i<100;i++)f.refresh();
assert.equal(f.metrics.abilities,0,'same current/queued native ability icons are not reassigned');
f.snapshot({research:research('second')});f.nodes.ProductionQueueSlot0.handlers.onactivate();assert.equal(f.sent.at(-1).payload.job_id,'second','new queue identity still cancels the current task');
f.snapshot({research:research('third','ability_research_tower_attack')});assert.equal(f.nodes.ProductionCurrentIcon.abilityname,'ability_research_tower_attack');assert.equal(f.nodes.ProductionQueueSlot0.icon.abilityname,'ability_research_tower_attack');
delete f.nodes.ProductionCurrentIcon.__productionAbilityName;f.nodes.ProductionCurrentIcon.failAbility=true;f.reset();assert.throws(()=>f.refresh(),/native ability setter failed/);f.refresh();assert.equal(f.metrics.abilities,2);f.refresh();assert.equal(f.metrics.abilities,2);
const beforeGeneration=f.cfg.SurvivalProductionHUD.CacheInspect().generation;f.reload();assert.equal(f.cfg.SurvivalProductionHUD.CacheInspect().generation,beforeGeneration+1);f.snapshot({research:research('new_context')});f.reset();f.refresh();assert(f.metrics.styles>0,'replacement context initializes its own custom geometry');f.reset();f.refresh();assert.equal(f.metrics.styles,0);
assert(f.cfg.SurvivalProductionHUD.CacheInspect().counters.styleSkipped>0);
// Execute the actual topnav refresh with the actual portrait Refresh contract.
const hud=fs.readFileSync('panorama/src/scripts/custom_game/topnav_remaining_5d5c1152eb.js','utf8');
const start=hud.indexOf('    function refreshNow()'),end=hud.indexOf('    function tick()',start);assert(start>=0&&end>start);
const calls={corner:0,portrait:0},group={},root={},cfg={HandoffGeneration:1,SurvivalPortraitPresentation:{RefreshLocalHeroPortrait(p){assert.equal(p,root);calls.corner++;},Refresh(p){assert.equal(p,group);calls.portrait++;this.RefreshLocalHeroPortrait(root);}}};
const env={cfg,ctx:{},generation:1,root,ready:true,geometry:null,currentEntries:[],valid:p=>!!p,native:id=>id==='PortraitGroup'?group:null,
 layout:()=>{},selectedUnit:()=>10,refreshInventoryPresentation:()=>{},fitNativeSkills:()=>{},mirror:()=>{},recoverReadyHotkeyMirror:()=>{},mirrorKeys:()=>{},revealWhenStable:()=>{},$:{Warning:e=>{throw e;}}};
vm.runInNewContext(hud.slice(start,end),env);env.refreshNow();assert.deepEqual(calls,{corner:1,portrait:1},'corner is refreshed once via portrait presentation');
env.ready=false;env.refreshNow();assert.deepEqual(calls,{corner:2,portrait:1},'corner continues while native portrait group is not ready');
env.ready=true;env.native=()=>null;env.refreshNow();assert.deepEqual(calls,{corner:3,portrait:1},'missing native group still keeps live corner fallback');
console.log('UI_OWNED_PRESENTATION_CACHE_PASS: 100 unchanged train/research refreshes=0 image/ability/style setters; live clock/geometry/slot/cancel identities; normalization/errors/reload; one corner refresh with missing-group fallback');
