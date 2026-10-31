'use strict';
// Production callbacks against the current Valve QueryUnitGuts snippet shape.
// These are bridge-call/identity tests, not native rendering or FPS evidence.
const assert=require('node:assert/strict');
const {setup}=require('./test_combat_stats_callbacks.cjs');
function fixture(extraNodes=0){
 const t=setup({portrait:true}),container=new t.Panel('QueryContainer',t.root);
 function guts(id,visible=true,opacity='1'){
  const branch=new t.Panel('QueryUnitGutsContainer_'+id,container);
  branch.visible=visible;branch.values.opacity=opacity;
  const vertical=new t.Panel('QueryVertical',branch,'DOTAQueryUnitGuts');
  const mid=new t.Panel('MidSection',vertical);
  const host=new t.Panel('PortraitContainer',mid,'DOTAQueryUnitPortraitContainer');
  const leaf=new t.Panel('QueryUnitHeroPortrait',host,'DOTAScenePanel');
  leaf.point={x:580,y:820};leaf.values.opacity='0.7';
  return {branch,host,leaf};
 }
 const hidden=guts('retained',false),current=guts('active');
 for(let i=0;i<extraNodes;i++)new t.Panel('UnrelatedNativeQuery_'+i,container);
 const calls={rootFind:0,childCount:0,child:0,parent:0};
 const rootFind=t.root.FindChildTraverse.bind(t.root);
 t.root.FindChildTraverse=id=>{calls.rootFind++;return rootFind(id)};
 for(const [name,key] of [['GetChildCount','childCount'],['GetChild','child'],['GetParent','parent']]){
  const original=t.Panel.prototype[name];t.Panel.prototype[name]=function(...args){calls[key]++;return original.apply(this,args)};
 }
 const asset='monster_boss_rebirth_05_lucid_torment',mapScene=new t.Panel('BaneCompleteMap',t.overlay,'DOTAScenePanel');
 t.cfg.SurvivalMonsterPortraitRenderer={HasAsset:a=>a===asset,HasUnitName:()=>true,
  ResolveAsset:a=>a,Prewarm(){},Hide(){},Prepare(){return {scene:mapScene,ready:true,presentable:true,key:'bane5-full'}}};
 function enter(){t.select(653,'npc_survival_named_rebirth_boss_05');t.api.selectionEvent('query_unit_event',{PlayerID:0});t.jobs.clear();}
 function show(){t.api.updateSnapshot({entindex:653,refresh_version:1,model_asset_id:asset,
  portrait_unit_name:'npc_dota_hero_bane',portrait_model_name:'models/heroes/bane/bane.vmdl'});}
 function reset(){for(const key of Object.keys(calls))calls[key]=0;}
 return Object.assign(t,{container,guts,hidden,current,calls,enter,show,reset,mapScene});
}

const duplicate=fixture();duplicate.enter();
assert.equal(duplicate.api.portraitAnchor(),duplicate.current.leaf,'hidden first same-ID snippet cannot own the visible query');
duplicate.show();
assert.equal(duplicate.api.portraitState().entity,653);
assert.equal(duplicate.api.portraitState().scene,duplicate.mapScene);
assert.equal(duplicate.overlay.GetParent(),duplicate.current.host,'complete scene mounts beside the real visible native leaf');
assert.equal(duplicate.native().values.opacity,'0.35','query switching never dims the selected main hero');
assert(duplicate.messages.some(line=>line.includes('SCENE_SET')&&line.includes('lucid_torment')));
assert(!duplicate.messages.some(line=>line.includes('anchor_state=missing_anchor')));

// Retained same-ID leaf still attached, but its native branch changes opacity.
duplicate.current.branch.values.opacity='0';duplicate.hidden.branch.visible=true;
assert.equal(duplicate.api.portraitAnchor(),duplicate.hidden.leaf,'zero-opacity old branch must yield to the now-visible query');
duplicate.reset();for(let i=0;i<300;i++)assert.equal(duplicate.api.portraitAnchor(),duplicate.hidden.leaf);
assert.equal(duplicate.calls.rootFind,0);assert.equal(duplicate.calls.child,0,'steady anchor reads never traverse indexed children');
const diagnosticCount=duplicate.messages.filter(line=>line.includes('QUERY_ANCHOR')).length;
for(let i=0;i<300;i++)duplicate.api.portraitAnchor();
assert.equal(duplicate.messages.filter(line=>line.includes('QUERY_ANCHOR')).length,diagnosticCount,'stable query state does not spam diagnostic logs');

// Native child count can stay equal while a complete guts is replaced.
const same=fixture();same.enter();assert.equal(same.api.portraitAnchor(),same.current.leaf);
const count=same.container.GetChildCount();same.current.branch.SetParent(new same.Panel('DetachedOldGuts'));
const replacement=same.guts('replacement');assert.equal(same.container.GetChildCount(),count);
assert.equal(same.api.portraitAnchor(),replacement.leaf,'same-count replacement invalidates the old attached identity chain');

// Absent query retains main state; a real late native child rebuild recovers.
const missing=setup({portrait:true}),scope=new missing.Panel('QueryContainer',missing.root);
missing.api.selectionEvent('query_unit_event',{PlayerID:0});missing.jobs.clear();
assert.equal(missing.api.portraitAnchor(),null);assert.equal(missing.native().values.opacity,'0.35');
const host=new missing.Panel('PortraitContainer',new missing.Panel('LateGuts',scope));
const late=new missing.Panel('QueryUnitHeroPortrait',host,'DOTAScenePanel');late.point={x:580,y:820};
assert.equal(missing.api.portraitAnchor(),late,'late native snippet is a real container rebuild even without another selection event');

// Changing back to normal selection restores the original native leaf identity.
duplicate.api.selectionEvent('selected_unit_event',{PlayerID:0});duplicate.jobs.clear();
assert.equal(duplicate.api.portraitAnchor(),duplicate.native());
const queued=duplicate.api.scheduleActive(.1,()=>{throw Error('old callback executed')},'old_query_anchor');
const old=duplicate.jobs.get(queued).fn;duplicate.api.shutdown('new_context');
assert.doesNotThrow(old);assert.equal(duplicate.jobs.size,0);

function steadyCost(nodes){
 const t=fixture(nodes);t.enter();assert.equal(t.api.portraitAnchor(),t.current.leaf);t.reset();
 for(let i=0;i<300;i++)assert.equal(t.api.portraitAnchor(),t.current.leaf);
 assert.equal(t.calls.rootFind,0);assert.equal(t.calls.child,0);
 return {...t.calls};
}
const small=steadyCost(0),large=steadyCost(1500);assert.deepEqual(large,small);
// Captured native classic-HUD structure: empty QueryContainer and the active
// Bane portrait in PortraitGroup/PortraitContainer/portraitHUD (DOTAPortrait).
let nativePortrait=233,portraitReads=0,portraitThrows=false;
const classic=setup({portrait:true,players:{GetLocalPlayerPortraitUnit(){portraitReads++;
 if(portraitThrows)throw Error('native API unavailable');return nativePortrait;}}});
new classic.Panel('QueryContainer',classic.root);classic.native().paneltype='DOTAPortrait';
// Actual native getters return null on unset leaf/ancestor opacity. Do not
// turn this default into explicit zero through Number(null).
for(let node=classic.native();node;node=node.GetParent())node.values.opacity=null;
classic.select(233,'npc_survival_named_rebirth_boss_05');
classic.api.selectionEvent('query_unit_event',{PlayerID:0});classic.jobs.clear();
assert.equal(classic.api.portraitAnchor(),classic.native(),'classic query shares only the engine-bound native main leaf');
const scene=new classic.Panel('FullBaneScene',classic.overlay,'DOTAScenePanel');
classic.cfg.SurvivalMonsterPortraitRenderer={HasAsset:()=>true,HasUnitName:()=>true,ResolveAsset:a=>a,
 Prewarm(){},Hide(){},Prepare(){return {scene,ready:true,presentable:true,key:'bane-full'}}};
classic.api.updateSnapshot({entindex:233,refresh_version:1,model_asset_id:'monster_boss_rebirth_05_lucid_torment',
 portrait_unit_name:'npc_dota_hero_bane'});
assert.equal(classic.api.portraitState().entity,233);assert.equal(classic.api.portraitState().scene,scene);
assert.equal(classic.overlay.GetParent(),classic.nativeHost());
assert(classic.messages.some(line=>line.includes('QUERY_ANCHOR')&&line.includes('shared_main')&&line.includes('native_portrait_identity_matches')));
const before=portraitReads;for(let i=0;i<300;i++)assert.equal(classic.api.portraitAnchor(),classic.native());
assert.equal(portraitReads-before,300,'one explicit native portrait-identity read per classic query resolution');
const noIdentity=setup({portrait:true});new noIdentity.Panel('QueryContainer',noIdentity.root);
noIdentity.native().paneltype='DOTAPortrait';noIdentity.select(233,'npc_survival_named_rebirth_boss_05');
noIdentity.api.selectionEvent('query_unit_event',{PlayerID:0});noIdentity.jobs.clear();
assert.equal(noIdentity.api.portraitAnchor(),null,'the classic tree alone cannot authorize fallback without the native identity API');
assert.equal(noIdentity.native().values.opacity,'0.35','an absent identity API cannot alter the own-hero leaf');
nativePortrait=7;assert.equal(classic.api.portraitAnchor(),null,'different own-hero identity never acquires the query overlay');
portraitThrows=true;assert.equal(classic.api.portraitAnchor(),null,'native identity failure is fail-closed');
portraitThrows=false;nativePortrait=233;classic.native().GetParent().values.opacity='0';
assert.equal(classic.api.portraitAnchor(),null,'a hidden main branch cannot be used just because IDs match');
classic.native().GetParent().values.opacity='1';
classic.native().GetParent().values.opacity=0;
assert.equal(classic.api.portraitAnchor(),null,'explicit numeric zero remains hidden');
classic.native().GetParent().values.opacity='1';
const rejected=classic.messages.filter(line=>line.includes('mainRejection')&&line.includes('zero_opacity_ancestor:PortraitContainer'));
assert(rejected.length>0&&rejected.some(line=>line.includes('opacityRaw')&&line.includes('opacityType')),'rejected native chain includes the specific node and raw getter type');
const nativeScope=classic.root.FindChildTraverse('QueryContainer');
const independentHost=new classic.Panel('PortraitContainer',new classic.Panel('IndependentGuts',nativeScope));
const independent=new classic.Panel('QueryUnitHeroPortrait',independentHost,'DOTAScenePanel');independent.point={x:580,y:820};
assert.equal(classic.api.portraitAnchor(),independent,'a visible independent query leaf always takes precedence over shared main');
console.log('PORTRAIT_QUERY_ANCHOR_PASS '+JSON.stringify({scope:'SIMULATED_NATIVE_BRIDGE_COUNTS_NOT_FPS',
 steadyReads:300,queryExtraNodes:[0,1500],small,large,
 classicNativeIdentityReads:300,
 cases:['classic engine-bound DOTAPortrait','native identity mismatch/error','dedicated query priority','duplicate hidden snippet','ancestor opacity transition','same-count replacement','late native query','main switch','stale callback']}));
