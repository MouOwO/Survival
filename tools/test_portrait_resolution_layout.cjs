// Exercise the real combat_stats source through its existing callback seam.
// Optional argv2 selects a reviewed source candidate; no output files are written.
// Synthetic panel calls are not native timings, pixels or FPS measurements.
'use strict';
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),Module=require('node:module');
const root=process.cwd(),sourcePath=path.resolve(process.argv[2]||'panorama/src/scripts/custom_game/combat_stats.js');
process.argv[2]=sourcePath;
const source=fs.readFileSync(sourcePath,'utf8');
assert(source.includes('function portraitCandidateGeometry('),
 'Resolution-aware portrait guard is not applied; pass an explicitly reviewed candidate source as argv2.');
const harnessPath=path.join(root,'tools/test_combat_stats_callbacks.cjs');
let harness=fs.readFileSync(harnessPath,'utf8');
const seam='portraitAnchor:officialPortraitPanel,';
assert.equal(harness.split(seam).length,2);
harness=harness.replace(seam,seam+'portraitGeometry:portraitCandidateGeometry,portraitReject:queryPortraitRejection,');
const mod=new Module(harnessPath,module);mod.filename=harnessPath;mod.paths=Module._nodeModulePaths(path.dirname(harnessPath));mod._compile(harness,harnessPath);
const {setup}=mod.exports;
function fixture({height=1080,scale=height/1080,rootScale=scale,player=1,noise=0,leafScale=true,rootScalePresent=true}={}){
 const t=setup({portrait:true,game:{GetLocalPlayerID:()=>player},players:{GetLocalPlayerPortraitUnit:()=>t.nativeUnit}});
 t.nativeUnit=653;t.native().paneltype='DOTAPortrait';t.root.actuallayoutwidth=1600;t.root.actuallayoutheight=height;
 if(rootScalePresent)t.root.actualuiscale_x=t.root.actualuiscale_y=rootScale;
 if(leafScale)t.native().actualuiscale_x=t.native().actualuiscale_y=scale;
 t.native().actuallayoutwidth=t.native().actuallayoutheight=264*scale;
 t.native().point={x:555,y:height*.84};
 for(let p=t.native();p;p=p.GetParent())p.values.opacity=null;
 new t.Panel('QueryContainer',t.root);
 const noiseRoot=new t.Panel('Noise',t.root);for(let n=0;n<noise;n++)new t.Panel('Other'+n,noiseRoot);
 t.select(653,'npc_survival_named_ten_sin_03');
 const P=t.Panel,m={rootFind:0,recursiveVisits:0,writes:0,parent:0,valid:0,childCount:0,position:0,layoutReads:0};
 const orig={};
 for(const [name,key]of [['GetParent','parent'],['IsValid','valid'],['GetChildCount','childCount'],['GetPositionWithinWindow','position']]){
  orig[name]=P.prototype[name];P.prototype[name]=function(...args){m[key]++;return orig[name].apply(this,args)};
 }
 orig.FindChildTraverse=P.prototype.FindChildTraverse;P.prototype.FindChildTraverse=function(id){m.recursiveVisits++;if(this===t.root)m.rootFind++;return orig.FindChildTraverse.call(this,id)};
 function wrap(panel){const st=panel.style;panel.style=new Proxy(st,{set(o,k,v){m.writes++;o[k]=v;return true}});for(const c of panel.children)wrap(c)}wrap(t.root);
 for(const panel of [t.root,t.native()])for(const key of ['actuallayoutwidth','actuallayoutheight','actualuiscale_x','actualuiscale_y']){
  if(!Object.prototype.hasOwnProperty.call(panel,key))continue;
  const desc=Object.getOwnPropertyDescriptor(panel,key);if(!desc.configurable)continue;
  let v=panel[key];Object.defineProperty(panel,key,{configurable:true,get(){m.layoutReads++;return v},set(next){v=next}});
 }
 t.cfg.SurvivalMonsterPortraitRenderer={HasAsset:()=>true,ResolveAsset:id=>id,Prepare:()=>({ready:true,presentable:true,key:'fixed',scene:t.scene}),Prewarm:()=>{},Hide:()=>{}};
 const snapshot={entindex:653,model_asset_id:'monster_boss_ten_sin_03_fixture',portrait_unit_name:'npc_dota_hero_alchemist',portrait_item_def:''};
 function enter(){t.api.selectionEvent('query_unit_event',{PlayerID:player});t.jobs.clear();return t.api.portraitAnchor()}
 function clear(){for(const k in m)m[k]=0}
 function stable(ticks,update=false){clear();for(let i=0;i<ticks;i++)update?t.api.portraitUpdate(snapshot):t.api.portraitAnchor();return {...m}}
 return {t,m,enter,clear,stable,snapshot};
}

function runLayoutTests(){
 const results=[];
// Run real production entry points across viewport, native-scale and player identities.
for(const player of [0,1])for(const height of [900,1000,1080,1440,2160])for(const dpi of [1,1.25,1.5,2]){
 const scale=height/1080*dpi,f=fixture({height,scale,player});
 assert.equal(f.enter(),f.t.native());assert.equal(f.t.api.portraitReject(f.t.native(),f.t.root),'usable');
 assert.equal(f.t.api.portraitGeometry(f.t.native(),f.t.root).logicalHeight,264);
 results.push({case:'viewport_scale_player',height,dpi,player,pixels:264*scale,logical_height:264});
}
for(const options of [
 {height:1000,scale:1000/1080,leafScale:false,rootScalePresent:false},
 {height:1440,scale:.75,rootScale:2},
 {height:900,scale:.75,rootScale:.75,leafScale:false}
]){const f=fixture(options);assert.equal(f.enter(),f.t.native());results.push({case:'scale_precedence_fallback',...options});}
for(const scale of [0,-1,NaN,Infinity,'invalid']){
 const f=fixture();f.t.native().actualuiscale_x=f.t.native().actualuiscale_y=scale;
 assert.equal(f.enter(),null);assert.equal(f.t.api.portraitReject(f.t.native(),f.t.root),'leaf_scale');
 results.push({case:'explicit_invalid_scale_rejected',scale:String(scale)});
}
for(const pixels of [0,1,NaN,Infinity,700,1e20]){
 const f=fixture();f.t.native().actuallayoutwidth=f.t.native().actuallayoutheight=pixels;
 assert.equal(f.enter(),null);results.push({case:'bad_size_rejected',pixels:String(pixels)});
}
// Reject huge native placeholders even if a forged scale would normalize them.
{
 const f=fixture({scale:1e8});assert.equal(f.enter(),null);results.push({case:'huge_placeholder_scale_pair'});
}
for(const height of [0,NaN,Infinity]){
 const f=fixture();f.t.root.actuallayoutheight=height;assert.equal(f.enter(),null);results.push({case:'invalid_root_height',height:String(height)});
}
for(const kind of ['hidden_leaf','collapsed_leaf','hidden_ancestor','zero_opacity_ancestor','wrong_identity']){
 const f=fixture();if(kind==='hidden_leaf')f.t.native().visible=false;
 if(kind==='collapsed_leaf')f.t.native().values.visibility='collapse';
 if(kind==='hidden_ancestor')f.t.nativeHost().visible=false;
 if(kind==='zero_opacity_ancestor')f.t.nativeHost().values.opacity='0';
 if(kind==='wrong_identity')f.t.nativeUnit=654;
 assert.equal(f.enter(),null);results.push({case:kind});
}
// Same HUD identity, no selection/root child-count change: repair late layout once.
for(const mode of ['leaf_size','leaf_scale','viewport_scale']){
 const f=fixture({height:1000});const leaf=f.t.native();
 if(mode==='leaf_size')leaf.actuallayoutwidth=leaf.actuallayoutheight=0;
 if(mode==='leaf_scale')leaf.actualuiscale_x=leaf.actualuiscale_y=0;
 if(mode==='viewport_scale'){delete leaf.actualuiscale_x;delete leaf.actualuiscale_y;f.t.root.actualuiscale_x=f.t.root.actualuiscale_y=0;}
 assert.equal(f.enter(),null);assert.equal(f.stable(300).rootFind,0);
 if(mode==='leaf_size')leaf.actuallayoutwidth=leaf.actuallayoutheight=264*1000/1080;
 if(mode==='leaf_scale')leaf.actualuiscale_x=leaf.actualuiscale_y=1000/1080;
 if(mode==='viewport_scale')f.t.root.actualuiscale_x=f.t.root.actualuiscale_y=1000/1080;
 f.clear();assert.equal(f.t.api.portraitAnchor(),leaf);assert(f.m.rootFind>0);const rebuild={...f.m};
 const stable=f.stable(10000);assert.equal(stable.rootFind,0);assert.equal(stable.recursiveVisits,0);assert.equal(stable.writes,0);
 results.push({case:'same_hud_recovery',mode,rebuild,stable_10000:stable});
}
// Existing main may resize without any re-discovery; shared identity stays exact.
{
 const f=fixture({height:900});assert.equal(f.enter(),f.t.native());f.clear();
 for(const height of [1000,1080,1440,2160,900]){
  f.t.root.actuallayoutheight=height;f.t.root.actualuiscale_x=f.t.root.actualuiscale_y=height/1080;
  f.t.native().actualuiscale_x=f.t.native().actualuiscale_y=height/1080;
  f.t.native().actuallayoutwidth=f.t.native().actuallayoutheight=264*height/1080;f.t.native().point.y=height*.84;
  assert.equal(f.t.api.portraitAnchor(),f.t.native());
 }
 assert.equal(f.m.rootFind,0);results.push({case:'positive_cached_resize',counts:{...f.m}});
}
// Unrelated scene count cannot affect stable bridge cost; real render updates write nothing unchanged.
const stableCosts=[];
for(const noise of [0,10000]){
 const f=fixture({height:1000,noise});assert.equal(f.enter(),f.t.native());
 assert.equal(f.t.api.portraitUpdate(f.snapshot),true);assert.equal(f.t.api.portraitUpdate(f.snapshot),true);
 const warm300=f.stable(300,true);assert.equal(warm300.rootFind,0);assert.equal(warm300.writes,0);
 const warm10000=f.stable(10000,true);assert.equal(warm10000.rootFind,0);assert.equal(warm10000.writes,0);
 stableCosts.push({noise,warm300,warm10000});
}
assert.deepEqual(stableCosts[0].warm300,stableCosts[1].warm300);assert.deepEqual(stableCosts[0].warm10000,stableCosts[1].warm10000);
// Peer-review counterexample: still-valid missing leaf moves to an unrelated
// alive parent/ancestor pool; same-count native replacement must expire once.
for(const mode of ['direct_parent','ancestor_detached','ancestor_reparented_inside_root']){
 const f=fixture({height:1000}),old=f.t.native(),host=old.GetParent(),group=host.GetParent();old.actualuiscale_x=old.actualuiscale_y=0;
 const retainedPool=mode==='ancestor_reparented_inside_root'?new f.t.Panel('RetainedPool',f.t.root):null;
 assert.equal(f.enter(),null);assert.equal(f.stable(300).rootFind,0);
 const rootCount=f.t.root.GetChildCount(),hostCount=host.GetChildCount();
 if(mode==='direct_parent'){
  old.SetParent(new f.t.Panel('DetachedAlivePool'));
 }else{
  const pool=retainedPool||new f.t.Panel('DetachedAlivePool');
  host.SetParent(pool);
 }
 let nextHost=host;
 if(mode!=='direct_parent')nextHost=new f.t.Panel('PortraitContainer',group);
 const leaf=new f.t.Panel('portraitHUD',nextHost,'DOTAPortrait');leaf.actuallayoutwidth=leaf.actuallayoutheight=264*1000/1080;
 leaf.actualuiscale_x=leaf.actualuiscale_y=1000/1080;leaf.point={x:555,y:840};leaf.values.opacity=null;
 if(mode==='direct_parent')assert.equal(hostCount,host.GetChildCount());
 assert.equal(rootCount,f.t.root.GetChildCount());
 assert.equal(f.t.api.portraitReject(leaf,f.t.root),'usable');f.clear();assert.equal(f.t.api.portraitAnchor(),leaf);assert(f.m.rootFind>0);
 const recovery={...f.m},quiet=f.stable(10000);assert.equal(quiet.rootFind,0);assert.equal(quiet.writes,0);
 results.push({case:'alive_probe_reparent_recovery',mode,recovery,quiet_10000:quiet});
}
// Destroyed remembered leaf and same-count replacement recover without a root mutation.
{
 const f=fixture({height:1000});const old=f.t.native(),host=old.GetParent();old.actualuiscale_x=old.actualuiscale_y=0;
 assert.equal(f.enter(),null);const rootCount=f.t.root.GetChildCount(),hostCount=host.GetChildCount();
 old.alive=false;host.children=host.children.filter(p=>p!==old);const leaf=new f.t.Panel('portraitHUD',host,'DOTAPortrait');
 leaf.actuallayoutwidth=leaf.actuallayoutheight=264*1000/1080;leaf.actualuiscale_x=leaf.actualuiscale_y=1000/1080;leaf.point={x:555,y:840};leaf.values.opacity=null;
 assert.equal(rootCount,f.t.root.GetChildCount());assert.equal(hostCount,host.GetChildCount());
 assert.equal(f.t.api.portraitAnchor(),leaf);const quiet=f.stable(300);assert.equal(quiet.rootFind,0);assert.equal(quiet.writes,0);results.push({case:'destroyed_probe_samecount_replacement',quiet});
}
// A real context/root replacement discards old-root aliases; no stale native leaf is reused.
{
 const f=fixture({height:1000});assert.equal(f.enter(),f.t.native());
 const next=new f.t.Panel('NextHud');next.actuallayoutwidth=1600;next.actuallayoutheight=1000;next.actualuiscale_x=next.actualuiscale_y=1000/1080;
 f.t.context.SetParent(next);const group=new f.t.Panel('PortraitGroup',next),host=new f.t.Panel('PortraitContainer',group),leaf=new f.t.Panel('portraitHUD',host,'DOTAPortrait');
 leaf.actuallayoutwidth=leaf.actuallayoutheight=264*1000/1080;leaf.actualuiscale_x=leaf.actualuiscale_y=1000/1080;leaf.point={x:555,y:840};
 for(let p=leaf;p;p=p.GetParent())p.values.opacity=null;new f.t.Panel('QueryContainer',next);
 assert.equal(f.t.api.portraitAnchor(),leaf);assert.notEqual(leaf,f.t.native());results.push({case:'root_replacement'});
}
return {kind:'PRODUCTION_FUNCTION_REPLAY_NOT_NATIVE_FPS',cases:results.length,results,stable_costs:stableCosts,
 native_api_calls:0,gui_actions:0,runtime_source_modified:false};
}
module.exports={fixture,runLayoutTests,sourcePath};
if(require.main===module){
 const report=runLayoutTests();
 console.log(JSON.stringify({status:'PORTRAIT_RESOLUTION_LAYOUT_PASS',scope:report.kind,cases:report.cases,stable_costs:report.stable_costs}));
}
