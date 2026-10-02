// Execute the production module through a seam that only suppresses unrelated
// startup work. Native portrait hide/mount/position/update/sentinel are real.
const fs=require('fs'),vm=require('vm'),assert=require('assert');
const source=fs.readFileSync(process.argv[2]||'panorama/src/scripts/custom_game/combat_stats.js','utf8');
const seam='    // NetTable is the single regular synchronization path.';
assert(source.includes(seam));
const instrumented=source.replace(seam,`    __test({applyAbilityRuntime:applyAbilityRuntime,scheduleActive:scheduleActive, cosmeticPortraitSentinel:cosmeticPortraitSentinel,
        resetScale:resetTowerPortraitContentScale, applyScale:applyTowerPortraitContentScale,
        restoreHotkey:restoreNativeAbilityHotkey, suppressHotkey:suppressNativeAbilityHotkey,
        refreshAbilities:refreshAbilities, shutdown:shutdownCombatContext,
        positionNumber:positionRelativeToNativeNumber, positionRow:positionRelativeToStatRow,
        positionAttributes:positionLogicalAttributeOverlay, positionPortrait:positionCosmeticPortrait,
        portraitRect:portraitRect, portraitUpdate:updateCosmeticPortrait, updateSnapshot:update,
        portraitHide:hideCosmeticPortrait, portraitTransition:transitionCosmeticPortrait,
        portraitState:function(){return {key:activePortraitKey,mode:activePortraitMode,unit:activePortraitUnit,
            entity:activePortraitEntity,scene:activePortraitScene,geometry:portraitGeometrySignature,
            snapshot:selectedUnitSnapshot,acceptedVersion:acceptedSnapshotVersion};},
        subscribeTable:subscribeCombatTable, subscribeEvent:subscribeCombatEvent});
    return;
`+seam);
function setup(options={}){
 const cfg={},jobs=new Map(),messages=[],subscriptions=new Map();let serial=0,api,time=0,selected=options.portrait?7:-1,multi=false;
 const runtime={},unitNames=new Map([[7,'npc_dota_hero_doom_bringer']]);
 const metrics={setUnit:[],parents:0,order:0,geometryWrites:0,visibilityTransitions:0};
 class Panel{
  constructor(id,parent,type='Panel'){
   this.id=id;this.parent=parent;this.paneltype=type;this.children=[];this.alive=true;this.visible=true;
   this.hittest=true;this.hittestchildren=true;this.values={};this.actualuiscale_x=this.actualuiscale_y=1;
   this.actuallayoutwidth=this.actuallayoutheight=128;this.point={x:0,y:0};
   if(parent)parent.children.push(this);
   this.style=new Proxy(this.values,{set:(o,k,v)=>{
    if(this.alive!==true)throw Error('native panel destroyed');
    if(v===null||v===undefined||/NaN|Infinity/.test(String(v)))throw Error('native style rejected '+k+'='+v);
    if(['position','width','height'].includes(k)&&this.id==='SurvivalTowerPortraitOverlay'){
     const numbers=String(v).match(/[-+]?(?:\d+\.?\d*|\.\d+)(?:e[-+]?\d+)?/gi)||[];
     assert(numbers.every(n=>Number.isFinite(Number(n))&&Math.abs(Number(n))<1e6),'invalid portrait layout must not reach native setter');
     metrics.geometryWrites++;
    }
    if(k==='visibility'&&o[k]!==v&&['SurvivalTowerPortraitOverlay','SurvivalTowerPortraitScene'].includes(this.id))metrics.visibilityTransitions++;
    o[k]=v;return true;
   }});
  }
  IsValid(){if(this.alive==='throw')throw Error('native handle released');return this.alive}
  GetParent(){return this.parent}
  FindChildTraverse(id){if(this.alive!==true)return null;if(this.id===id)return this;for(const c of this.children){const p=c.FindChildTraverse(id);if(p)return p;}return null}
  GetPositionWithinWindow(){if(this.point==='throw')throw Error('layout not ready');return this.point}
  SetParent(parent){assert(parent&&parent.alive===true);if(this.parent)this.parent.children=this.parent.children.filter(c=>c!==this);this.parent=parent;parent.children.push(this);metrics.parents++}
  MoveChildAfter(child,anchor){this.children=this.children.filter(c=>c!==child);this.children.splice(this.children.indexOf(anchor)+1,0,child);metrics.order++}
  SetUnit(...args){assert(this.alive===true);metrics.setUnit.push({panel:this,args});if(this.setUnitFailure==='throw')throw Error('SetUnit unavailable');if(this.setUnitFailure==='false')return false}
  AddClass(){}SetHasClass(){}SetImage(uri){this.image=uri}
  GetChildCount(){return this.children.length}GetChild(i){return this.children[i]}
 }
 const root=new Panel('Hud');root.actuallayoutwidth=1920;root.actuallayoutheight=1080;
 const context=new Panel('Context',root),overlay=new Panel('SurvivalTowerPortraitOverlay',context),scene=new Panel('SurvivalTowerPortraitScene',overlay,'DOTAScenePanel');
 let nativeHost,nativeScene;
 function mountNative(){
  nativeHost=new Panel('PortraitContainer',new Panel('PortraitGroup',root));
  nativeHost.point={x:100,y:800};nativeScene=new Panel('portraitHUD',nativeHost,'DOTAScenePanel');
  nativeScene.point={x:120,y:820};nativeScene.values.opacity='0.35';
  return nativeScene;
 }
 if(options.portrait)mountNative();
 cfg.SurvivalSelectionResolver={Resolve:()=>selected,ResolveDisplayUnit:()=>selected};
 cfg.SurvivalMultiSelectionPortraits={IsActive:()=>multi};
 const $=id=>context.FindChildTraverse(id.slice(1));
 $.CreatePanel=(type,parent,id)=>new Panel(id,parent,type);$.GetContextPanel=()=>context;
 $.Schedule=(delay,fn)=>{const id=++serial;jobs.set(id,{delay,fn});return id};$.CancelScheduled=id=>jobs.delete(id);
 $.Msg=(...s)=>messages.push(s.join(''));$.Warning=$.Msg;$.Localize=s=>s;
 const subscribe=(name,fn)=>{const id=++serial;subscriptions.set(id,{name,fn});return id};
 vm.runInNewContext(instrumented,{$,GameUI:{CustomUIConfig:()=>cfg},Game:{GetLocalPlayerID:()=>0,GetGameTime:()=>time},
  Players:{GetPlayerHeroEntityIndex:()=>selected},
  Entities:{GetUnitName:id=>unitNames.get(Number(id))||'npc_dota_hero_test',GetAbility:()=>-1,GetLevel:()=>1,IsHero:()=>true},
  CustomNetTables:{GetTableValue:(name,key)=>runtime[key]||null,SubscribeNetTableListener:subscribe,UnsubscribeNetTableListener:id=>subscriptions.delete(id)},
  GameEvents:{Subscribe:subscribe,Unsubscribe:id=>subscriptions.delete(id)},__test:x=>api=x},{filename:'combat_stats.js'});
 function run(id){const job=jobs.get(id);assert(job);jobs.delete(id);job.fn()}
 return {api,root,context,overlay,scene,cfg,jobs,messages,subscriptions,run,Panel,runtime,metrics,mountNative,
  native:()=>nativeScene,nativeHost:()=>nativeHost,setTime:t=>time=t,select:(id,name)=>{selected=id;if(name)unitNames.set(id,name)},setMulti:value=>{multi=value}};
}
module.exports={setup};
if(require.main===module){
// The reported callback entry is used by the 0.1s portrait sentinel. Hiding a
// scene must not pass null to a native style setter or kill the next tick.
const a=setup();a.api.applyScale(a.scene);
assert.doesNotThrow(()=>a.run(a.api.scheduleActive(.1,a.api.cosmeticPortraitSentinel)));
assert.equal(a.scene.values.transform,'scale3d(1, 1, 1)');assert.equal(a.scene.values.transformOrigin,'50% 50%');assert.equal(a.scene.values.visibility,'collapse');assert.equal(a.jobs.size,1);
// Resetting a released Scene and shutting down a released context must not touch
// the stale style bridge, even if IsValid itself throws.
a.scene.alive='throw';assert.doesNotThrow(()=>a.api.resetScale(a.scene));
a.context.alive='throw';assert.doesNotThrow(()=>a.run([...a.jobs.keys()][0]));assert.equal(a.jobs.size,0);
// Empty inline opacity restores visibility; explicitly recorded zero stays zero.
for(const original of ['', '0', '0.35']){
 const b=setup(),button=new b.Panel('Ability0',b.root),hotkey=new b.Panel('HotkeyContainer',button);hotkey.values.opacity=original;hotkey.hittestchildren=false;
 b.api.suppressHotkey(button);assert.equal(hotkey.values.opacity,'0');
 b.api.restoreHotkey(button);assert.equal(hotkey.values.opacity,original||'1');assert.equal(hotkey.hittest,true);assert.equal(hotkey.hittestchildren,false);
}
// The no-selection polling branch must be cancelled together with other jobs.
const c=setup();c.api.refreshAbilities();assert.equal(c.jobs.size,1);const late=[...c.jobs.values()][0].fn;
c.api.shutdown('replacement_context');assert.equal(c.jobs.size,0);assert.doesNotThrow(late);assert.equal(c.jobs.size,0);
let called=false;assert.equal(c.api.scheduleActive(.1,()=>{called=true}),null);assert(!called);
// A generation change prevents old callbacks from executing against the new HUD.
const d=setup(),id=d.api.scheduleActive(.1,()=>{called=true});d.cfg.SurvivalInputLifecycleGeneration=1;d.run(id);assert(!called);assert.equal(d.jobs.size,0);
// Unexpected errors retain their identity/stack and gain the originating task.
const e=setup(),failure=Error('intentional native failure'),errorJob=e.api.scheduleActive(.1,()=>{throw failure},'portrait_probe');
assert.throws(()=>e.run(errorJob),x=>x===failure);assert(e.messages.some(s=>s.includes('[COMBAT_STATS_CALLBACK_ERROR] task=portrait_probe')&&s.includes('intentional native failure')&&s.includes('stack=')));assert.equal(e.jobs.size,0);
// Native coordinates can be indexed vectors. Verify the real positioning paths
// at two HUD scales, then unavailable geometry followed by a successful retry.
for (const scale of [1, 0.75]) for (const indexed of [false, true]) {
 const t=setup(),parent=new t.Panel('stats_container',t.root),stat=new t.Panel('Damage',parent),number=new t.Panel('DamageLabel',stat),label=new t.Panel('Overlay',parent);
 const point=(x,y)=>indexed?[x,y,0]:{x,y};
 parent.GetPositionWithinWindow=()=>point(100,200);parent.actualuiscale_x=scale;parent.actualuiscale_y=scale;
 stat.GetPositionWithinWindow=()=>point(120,240);stat.actuallayoutheight=20;stat.actuallayoutwidth=16;
 number.GetPositionWithinWindow=()=>point(120,260);number.actuallayoutheight=20;
 assert(t.api.positionNumber(stat,parent,label,['DamageLabel']));assert.equal(label.values.position,`0px ${60/scale}px 0px`);
 assert(t.api.positionRow(stat,parent,label));assert.equal(label.values.position,`0px ${40/scale}px 0px`);
 for(const bad of [{},null,[0],{x:0,y:NaN},{x:0,y:Infinity}]) {
  number.GetPositionWithinWindow=()=>bad;stat.GetPositionWithinWindow=()=>bad;
  const before=JSON.stringify(label.values);
  assert.equal(t.api.positionNumber(stat,parent,label,['DamageLabel']),false);
  assert.equal(t.api.positionRow(stat,parent,label),false);
  assert.doesNotThrow(()=>t.api.positionAttributes(parent,label));
  assert.equal(JSON.stringify(label.values),before);
  assert.equal(t.api.positionPortrait(label,stat,t.scene),false);
 }
 stat.GetPositionWithinWindow=()=>point(120,240);number.GetPositionWithinWindow=()=>point(120,260);
 for(const badScale of [0,-1,NaN,Infinity,'invalid']) {
  parent.actualuiscale_y=badScale;
  assert.equal(t.api.positionNumber(stat,parent,label,['DamageLabel']),false);
  assert.equal(t.api.positionRow(stat,parent,label),false);
 }
 parent.actualuiscale_y=scale;assert(t.api.positionNumber(stat,parent,label,['DamageLabel']));
 const row=new t.Panel('SurvivalLogicalStrengthRow',label);
 t.api.positionAttributes(parent,label);assert.equal(row.values.position,`${20/scale-65}px ${40/scale+68}px 0px`);
}
for (const reason of ['shutdown','released','generation']) {
 const t=setup();let received=0;
 const id=t.api.subscribeTable('survival_combat_stats',(name,key,value)=>{assert.equal(name,'survival_combat_stats');assert.equal(key,'player_0');assert.equal(value.entindex,7);received++;});
 const event=t.api.subscribeEvent('ui_selected_unit_stats_snapshot',()=>received++);
 const listener=t.subscriptions.get(id).fn, eventListener=t.subscriptions.get(event).fn;
 listener('survival_combat_stats','player_0',{entindex:7});assert.equal(received,1);
 if(reason==='shutdown')t.api.shutdown('test');
 if(reason==='released')t.context.alive='throw';
 if(reason==='generation')t.cfg.SurvivalInputLifecycleGeneration=1;
 assert.doesNotThrow(()=>listener('survival_combat_stats','player_0',{entindex:7}));
 assert.doesNotThrow(()=>eventListener({entindex:7}));
 assert.equal(received,1);assert.equal(t.subscriptions.size,0);
 assert.equal(t.api.subscribeTable('late',()=>{}),null);
}
const f=setup(),eventError=Error('native event failure');
const eventId=f.api.subscribeEvent('stats_probe',()=>{throw eventError});
assert.throws(()=>f.subscriptions.get(eventId).fn(),x=>x===eventError);
assert(f.messages.some(s=>s.includes('[COMBAT_STATS_EVENT_ERROR] event=stats_probe')&&s.includes('native event failure')));
console.log('COMBAT_CALLBACK_TEST_PASS: timer/event lifecycle, stale queued snapshots, unsubscribe, native styles, coordinate vectors, scaling and recovery');

const talentUI=setup(),button=new talentUI.Panel('TalentButton',talentUI.root);
new talentUI.Panel('AbilityImage',button);
talentUI.runtime[42]={talent_pending:1,icon_name:'survival/native/talent_question'};
talentUI.api.applyAbilityRuntime(button,42);
const icon=button.__survivalTalentIcon,brightness=icon.style.brightness;
assert(icon.visible && !icon.hittest && !icon.hittestchildren,'art must preserve the native button input');
talentUI.setTime(.3);talentUI.api.applyAbilityRuntime(button,42);
assert.notEqual(icon.style.brightness,brightness,'unselected talent pulses over time');
talentUI.runtime[42]={talent_pending:0,icon_name:'survival/native/talent_wall_recovery'};
talentUI.api.applyAbilityRuntime(button,42);
assert(icon.image.endsWith('/talent_wall_recovery.png') && icon.style.brightness==='1','successful selection switches icon and stops flashing');
talentUI.api.applyAbilityRuntime(button,43);assert(!icon.visible,'native slot reuse must hide stale talent art');
icon.alive='throw';talentUI.api.applyAbilityRuntime(button,42);
assert(button.__survivalTalentIcon!==icon && button.__survivalTalentIcon.visible,'a released image handle can be recreated safely');
console.log('TALENT_NATIVE_ICON_PASS: input isolation, pulse, selection, slot reuse, stale handle');

// Stable authoritative updates and the existing sentinel share one real scene.
const doomSnapshot=(version=1)=>({entindex:7,refresh_version:version,model_asset_id:'hero_permanent_hero_doom',
 portrait_unit_name:'npc_dota_hero_doom_bringer',portrait_item_def:'',attack_min:10,attack_max:10});
function portraitGeometry(panel){return {position:panel.values.position,width:panel.values.width,height:panel.values.height}}
{
 const t=setup({portrait:true});t.api.updateSnapshot(doomSnapshot());
 assert.equal(t.metrics.setUnit.length,1);assert.equal(t.overlay.GetParent(),t.nativeHost());
 assert.equal(t.native().values.opacity,'0');assert.equal(t.overlay.values.visibility,'visible');
 const baseline={parents:t.metrics.parents,order:t.metrics.order,geometryWrites:t.metrics.geometryWrites,visibility:t.metrics.visibilityTransitions};
 t.api.cosmeticPortraitSentinel();assert.equal(t.jobs.size,1);
 for(let frame=0;frame<300;frame++){
  t.setTime((frame+1)*.1);t.api.updateSnapshot(doomSnapshot(frame+2));t.run([...t.jobs.keys()][0]);
  assert.equal(t.jobs.size,1);
 }
 assert.equal(t.metrics.setUnit.length,1,'stable updates/sentinel must not restart SetUnit');
 assert.deepStrictEqual({parents:t.metrics.parents,order:t.metrics.order,geometryWrites:t.metrics.geometryWrites,visibility:t.metrics.visibilityTransitions},baseline,
  'stable frames cannot reparent home, reorder, hide or rewrite geometry');
 assert(!t.messages.some(m=>m.includes('HIDE ')||m.includes('TRANSITION_MASK')));
 const before=t.api.portraitState();
 for(const snapshot of [null,{...doomSnapshot(300),model_asset_id:''},{...doomSnapshot(500),entindex:8}]){
  t.api.updateSnapshot(snapshot);
  assert.equal(t.api.portraitState().snapshot,before.snapshot,'null/stale/other-selection snapshot must not supersede accepted data');
 }
 assert.equal(t.api.portraitState().acceptedVersion,301);
 // A genuinely accepted unsupported snapshot still restores the native portrait;
 // this fix does not invent metadata or keep a stale custom portrait indefinitely.
 t.api.updateSnapshot({entindex:7,refresh_version:302});
 assert.equal(t.api.portraitState().key,'');assert.equal(t.api.portraitState().scene,null);
 assert.equal(t.overlay.GetParent(),t.context);assert.equal(t.native().values.opacity,'0.35');
 assert.equal(t.overlay.values.visibility,'collapse');
 t.api.updateSnapshot(doomSnapshot(303));assert.equal(t.metrics.setUnit.length,2);
 t.api.shutdown('test');assert.equal(t.jobs.size,0);
}
// Unlaid-out finite sentinels and overflow from tiny scale cannot reach styles
// or replace the last accepted geometry signature. A valid next frame recovers.
for(const scale of [1,.75]){
 const t=setup({portrait:true});t.nativeHost().actualuiscale_x=t.nativeHost().actualuiscale_y=scale;
 t.api.updateSnapshot(doomSnapshot());const anchor=t.native(),host=t.nativeHost();
 const original={point:anchor.point,width:anchor.actuallayoutwidth,height:anchor.actuallayoutheight,hostPoint:host.point};
 const before=portraitGeometry(t.overlay),signature=t.api.portraitState().geometry;
 for(const point of [null,{},[0],{x:0,y:NaN},{x:Infinity,y:820},{x:1.95e38,y:820},{x:-1.95e38,y:820},
  {x:1000000,y:820},{x:120,y:-1000000},'throw']){
  anchor.point=point;assert.equal(t.api.positionPortrait(t.overlay,anchor,t.scene),false);
  assert.deepStrictEqual(portraitGeometry(t.overlay),before);assert.equal(t.api.portraitState().geometry,signature);
 }
 anchor.point=original.point;
 for(const [field,value]of [['actuallayoutwidth',0],['actuallayoutheight',0],['actuallayoutwidth',NaN],
  ['actuallayoutheight',Infinity],['actuallayoutwidth',1.95e38],['actuallayoutheight',1000000]]){
  anchor[field]=value;assert.equal(t.api.positionPortrait(t.overlay,anchor,t.scene),false);
  assert.deepStrictEqual(portraitGeometry(t.overlay),before);
  anchor.actuallayoutwidth=original.width;anchor.actuallayoutheight=original.height;
 }
 for(const bad of [0,-1,NaN,Infinity,'invalid',1e-12]){
  host.actualuiscale_x=host.actualuiscale_y=bad;assert.equal(t.api.positionPortrait(t.overlay,anchor,t.scene),false);
  assert.deepStrictEqual(portraitGeometry(t.overlay),before);assert.equal(t.api.portraitState().geometry,signature);
 }
 host.actualuiscale_x=host.actualuiscale_y=scale;
 anchor.point={x:900000,y:820};host.point={x:-900000,y:800};
 assert.equal(t.api.positionPortrait(t.overlay,anchor,t.scene),false,'individually finite coordinates can overflow the computed layout');
 assert.deepStrictEqual(portraitGeometry(t.overlay),before);
 anchor.point=original.point;host.point=original.hostPoint;
 assert(t.api.positionPortrait(t.overlay,anchor,t.scene));
 const sets=t.metrics.setUnit.length;t.api.updateSnapshot(doomSnapshot(2));assert.equal(t.metrics.setUnit.length,sets);
 // Collapsed/hidden/released and finite enormous diagnostics read as none.
 for(const panel of [t.overlay,t.scene]){
  for(const mode of ['collapse','hidden','position','width','released']){
   const point=panel.point,width=panel.actuallayoutwidth,visible=panel.visible,visibility=panel.values.visibility;
   if(mode==='collapse')panel.values.visibility='collapse';
   if(mode==='hidden')panel.visible=false;
   if(mode==='position')panel.point={x:1.95e38,y:1.95e38};
   if(mode==='width')panel.actuallayoutwidth=1.95e38;
   if(mode==='released')panel.alive='throw';
   assert.equal(t.api.portraitRect(panel),null);
   panel.alive=true;panel.point=point;panel.actuallayoutwidth=width;panel.visible=visible;panel.values.visibility=visibility;
  }
 }
 t.overlay.point={x:1.95e38,y:1.95e38};t.scene.point={x:1.95e38,y:1.95e38};
 assert(t.api.positionPortrait(t.overlay,anchor,t.scene),'invalid actual diagnostics do not turn a valid anchor placement into a scene reset');
 assert(t.messages.some(m=>m.includes('overlay_actual=none')&&m.includes('scene_rect=none')));
 assert(!t.messages.some(m=>/1\.95e\+?38/.test(m)));
 t.api.shutdown('test');
}
// Recreated Scene objects require one SetUnit despite identical asset identity.
{
 const t=setup({portrait:true});t.api.updateSnapshot(doomSnapshot());
 const old=t.scene,before=JSON.stringify(old.values);old.alive=false;
 const scene=new t.Panel('SurvivalTowerPortraitScene',t.overlay,'DOTAScenePanel');
 t.api.updateSnapshot(doomSnapshot(2));
 assert.equal(t.metrics.setUnit.length,2);assert.equal(t.metrics.setUnit[1].panel,scene);
 assert.equal(t.api.portraitState().scene,scene);assert.equal(JSON.stringify(old.values),before);
 for(let frame=3;frame<30;frame++)t.api.updateSnapshot(doomSnapshot(frame));
 assert.equal(t.metrics.setUnit.length,2);assert.equal(t.metrics.parents,1);
 t.api.shutdown('test');
}
// Anchor replacement restores a still-valid old leaf and dims the new leaf,
// without recreating the same Scene or returning the overlay to its home.
{
 const t=setup({portrait:true});t.api.updateSnapshot(doomSnapshot());const old=t.native();
 old.GetParent().children=old.GetParent().children.filter(child=>child!==old);old.parent=null;
 const next=t.mountNative();t.api.updateSnapshot(doomSnapshot(2));
 assert.equal(old.values.opacity,'0.35');assert.equal(next.values.opacity,'0');
 assert.equal(t.overlay.GetParent(),next.GetParent());assert.equal(t.metrics.setUnit.length,1);
 assert.equal(t.metrics.parents,2);assert.equal(t.metrics.order,2);
 t.api.shutdown('test');assert.equal(next.values.opacity,'0.35');
}
// Real unit and multi-selection transitions must release the native layer;
// late old snapshots and scheduled callbacks cannot resurrect the old view.
{
 const t=setup({portrait:true});t.api.updateSnapshot(doomSnapshot());
 t.select(8,'npc_dota_hero_juggernaut');t.api.portraitTransition('selection_transition');
 t.api.updateSnapshot({entindex:8,refresh_version:1,model_asset_id:'hero_permanent_hero_blademaster',portrait_unit_name:'npc_dota_hero_juggernaut'});
 assert.equal(t.metrics.setUnit.length,2);assert.equal(t.api.portraitState().entity,8);
 t.api.updateSnapshot(doomSnapshot(1000));assert.equal(t.metrics.setUnit.length,2);
 t.setMulti(true);t.api.cosmeticPortraitSentinel();
 assert.equal(t.overlay.values.visibility,'collapse');assert.equal(t.overlay.GetParent(),t.context);
 assert.equal(t.native().values.opacity,'0.35');assert.equal(t.api.portraitState().scene,null);
 t.setMulti(false);t.select(9,'npc_dota_hero_lina');t.api.updateSnapshot({entindex:9,refresh_version:1,model_asset_id:'hero_permanent_hero_lina'});
 assert.equal(t.overlay.values.visibility,'collapse');assert.equal(t.metrics.setUnit.length,2);
 t.select(-1);t.api.portraitTransition('no_selection');assert.equal(t.native().values.opacity,'0.35');
 const late=[...t.jobs.values()][0].fn;t.api.shutdown('test');late();
 assert.equal(t.jobs.size,0);assert.equal(t.metrics.setUnit.length,2);
}
console.log('PORTRAIT_FLICKER_CLIENT_PASS: real metadata updates/sentinel, 300 stable frames, unsupported and stale snapshot semantics, finite layout sentinels, recovery, Scene/anchor replacement and true transition cleanup; rendered pixels not simulated');

}
