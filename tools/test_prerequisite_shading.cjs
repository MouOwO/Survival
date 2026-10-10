// Execute production native/fallback rendering and tooltip input against panel
// doubles. This checks behavior, not Workshop pixel rendering.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const dir='panorama/src/scripts/custom_game/';
const combat=fs.readFileSync(dir+'combat_stats.js','utf8');
const takeover=fs.readFileSync(dir+'hud_takeover.js','utf8');
const tooltip=fs.readFileSync(dir+'ability_tooltip.js','utf8');
let runtime={};
function panel(){return {style:{brightness:'1',saturation:'1'},classes:new Set(),
 SetHasClass(name,on){on?this.classes.add(name):this.classes.delete(name)},BHasClass(name){return this.classes.has(name)}};}
const nativeImage=panel(),native=panel();native.FindChildTraverse=name=>name==='AbilityImage'?nativeImage:null;
const nativeEnv={abilityRuntime:()=>runtime,validPortraitPanel:value=>!!value,
 abilityPanelStyleValue:(p,key)=>String(p.style[key]||'')};
vm.runInNewContext(combat.slice(combat.indexOf('    function setAbilityRuntimeDisabled('),combat.indexOf('    function abilityPanelStyleValue(')),nativeEnv);
const fallback={panel:panel(),image:panel(),hotkey:{},level:{},mana:{},cooldown:{},shade:panel()};
const fallbackEnv={runtimeFor:()=>runtime,hotkeyForEntry:()=> 'Q',abilityLevel:()=>1,manaCost:()=>0,
 cooldownRemaining:()=>0,cooldownLength:()=>0,Abilities:{GetBehavior:()=>4}};
vm.runInNewContext(takeover.slice(takeover.indexOf('    function isPassiveAbility('),takeover.indexOf('    function hotkeyForEntry(')),fallbackEnv);
vm.runInNewContext(takeover.slice(takeover.indexOf('    function updateSlot('),takeover.indexOf('    function hideUnused(')),fallbackEnv);
for(const name of ['ability_research_tower_attack','ability_tower_class_1','ability_upgrade_tower','ability_fuse_lumberjack_01']) {
 for(const state of [
  {available:0,prerequisite_met:1,can_afford:0},
  {available:1,prerequisite_met:0,can_afford:1},
  {available:1,prerequisite_met:1,can_afford:1},
  {available:0,can_afford:1}
 ]) {
  runtime={...state,resource_check_on_cast:1,ability_name:name};
  const locked=state.prerequisite_met!==undefined?state.prerequisite_met===0:state.available===0;
  nativeEnv.applyAbilityRuntime(native,100);
  fallbackEnv.updateSlot(fallback,{ability:100,name},0);
  assert.equal(native.classes.has('DOTADisabled'),locked,name+': native tint uses learning gate');
  assert.equal(fallback.panel.classes.has('Unavailable'),locked,name+': fallback tint matches native');
  assert.equal(fallback.panel.classes.has('ResourceLow'),false,name+': wallet projection cannot change border color');
  assert.equal(nativeImage.style.saturation,locked?'0':'1');
  assert.equal(native.hittest,true,'locked icons retain hover information');
 }
}
runtime={prerequisite_met:1,completed:1};nativeEnv.applyAbilityRuntime(native,100);
assert.equal(native.style.opacity,'0');assert.equal(native.hittest,false);
runtime={prerequisite_met:1,completed:0};nativeEnv.applyAbilityRuntime(native,100);
assert.equal(native.style.opacity,'1');assert.equal(native.hittest,true);
const sent=[],input={readTooltipTable:()=>runtime,unitOwnsAbility:()=>true,selectedUnit:()=>20,
 $:{Msg(){}},Abilities:{GetAbilityName:()=>runtime.ability_name||'ability_tower_class_1',GetBehavior:()=>4},
 GameUI:{CustomUIConfig:()=>({})},selectedEntindexesForRequest:()=>[20],
 GameEvents:{SendCustomGameEventToServer:(event,payload)=>sent.push({event,payload})}};
vm.runInNewContext(tooltip.slice(tooltip.indexOf('    function isPassiveAbility('),tooltip.indexOf('    GameUI.CustomUIConfig().SurvivalAbilityInput =')),input);
runtime={owner_entindex:20,available:0,prerequisite_met:1,can_afford:0};
assert.equal(input.executeAbility(100),true,'unlocked action reaches server despite old availability/wallet');
assert.equal(sent.length,1);assert.equal(sent[0].event,'ui_ability_cast_request');
runtime.prerequisite_met=0;assert.equal(input.executeAbility(100),false);assert.equal(sent.length,1);
runtime.prerequisite_met=1;runtime.completed=1;assert.equal(input.executeAbility(100),false);assert.equal(sent.length,1);
console.log('PREREQUISITE_SHADING_PASS: native/fallback parity, unlock restoration, completed hiding and authoritative click admission');

// Native AbilityN/AbilityImage nodes are reused for different units. Research
// hover, native disabled styling or a child rebuild may leave an inline gray
// value without the renderer's own flag. The current tower runtime must win.
function trackedPanel(initialStyle={brightness:'1',saturation:'1'}) {
 const values={...initialStyle}; let styleWrites=0, classWrites=0;
 const value={classes:new Set(),
  style:new Proxy(values,{set(target,key,next){styleWrites++;target[key]=next;return true}}),
  SetHasClass(name,on){classWrites++;on?this.classes.add(name):this.classes.delete(name)},
  BHasClass(name){return this.classes.has(name)},
  writes(){return {style:styleWrites,classes:classWrites}},
  resetWrites(){styleWrites=0;classWrites=0}};
 return value;
}
function nativeSlot(initialImageStyle) {
 const root=trackedPanel(),image=trackedPanel(initialImageStyle);
 root.image=image;root.FindChildTraverse=id=>id==='AbilityImage'?root.image:null;
 return root;
}
function currentRuntime(name, prerequisite=1) {
 return {ability_name:name,ability_entindex:100,owner_entindex:20,
  prerequisite_met:prerequisite,available:1,can_afford:1,resource_check_on_cast:1};
}
function assertNormal(slot,reason) {
 assert.equal(slot.classes.has('DOTADisabled'),false,reason+': current runtime is unlocked');
 assert.equal(slot.image.style.saturation,'1',reason+': icon regains its color');
 assert.equal(slot.image.style.brightness,'1',reason+': icon regains normal brightness');
}
for(let route=1;route<=7;route++) {
 const name='ability_tower_class_'+route;
 const reused=nativeSlot({brightness:'0.45',saturation:'0'});
 runtime=currentRuntime('ability_research_tower_attack',0);
 nativeEnv.applyAbilityRuntime(reused,100);
 runtime=currentRuntime(name,1);
 nativeEnv.applyAbilityRuntime(reused,100);
 assertNormal(reused,name+' research-to-tower reuse with a polluted saved tint');
 const externalGray=nativeSlot({brightness:'0.45',saturation:'0'});
 nativeEnv.applyAbilityRuntime(externalGray,100);
 assertNormal(externalGray,name+' external gray without renderer metadata');
 const rebuilt=nativeSlot();runtime=currentRuntime(name,0);
 nativeEnv.applyAbilityRuntime(rebuilt,100);
 rebuilt.image=trackedPanel({brightness:'0.45',saturation:'0'});
 runtime=currentRuntime(name,1);nativeEnv.applyAbilityRuntime(rebuilt,100);
 assertNormal(rebuilt,name+' AbilityImage replacement during unlock');
 reused.resetWrites();reused.image.resetWrites();
 for(let index=0;index<40;index++) nativeEnv.applyAbilityRuntime(reused,100);
 assert.equal(reused.image.writes().style,0,name+': stable unlocked refresh has no color writes');
 assert.equal(reused.writes().classes,0,name+': stable unlocked refresh has no class writes');
 runtime=currentRuntime(name,0);nativeEnv.applyAbilityRuntime(reused,100);
 reused.resetWrites();reused.image.resetWrites();
 for(let index=0;index<40;index++) nativeEnv.applyAbilityRuntime(reused,100);
 assert.equal(reused.image.writes().style,0,name+': stable locked refresh has no color writes');
 assert.equal(reused.writes().classes,0,name+': stable locked refresh has no class writes');
}
const hovered=nativeSlot();
const hoverConfig={};
const hoverEnv={
 externalAbilityRuntime:()=>runtime,selectedUnit:()=>20,
 tooltipError(stage,error){throw error},
 GameUI:{CustomUIConfig:()=>hoverConfig},
 readTooltipTable:()=>runtime,
};
vm.runInNewContext(tooltip.slice(tooltip.indexOf('    function externalAbilityHighlightTarget('),tooltip.indexOf('    function acquireSelectiveTooltip(')),hoverEnv);
const proxy={__survivalAbilityIndex:100,__survivalVisualAnchor:hovered,
 IsValid:()=>true};
hovered.IsValid=()=>true;hovered.image.IsValid=()=>true;
runtime=currentRuntime('ability_research_tower_attack',0);
hoverEnv.setExternalProxyHighlight(proxy,true);
// This is the ordering that previously saved the hover's gray value as an
// original icon style and restored it on selecting an unlocked tower.
nativeEnv.applyAbilityRuntime(hovered,100);
runtime=currentRuntime('ability_tower_class_3',1);
hoverEnv.setExternalProxyHighlight(proxy,false);
nativeEnv.applyAbilityRuntime(hovered,100);
assertNormal(hovered,'research hover release after tower rebinding');
hoverEnv.setExternalProxyHighlight(proxy,true);
assert.equal(hovered.image.style.saturation,'1.35','unlocked tower remains colored during hover');
hoverEnv.setExternalProxyHighlight(proxy,false);
nativeEnv.applyAbilityRuntime(hovered,100);
assertNormal(hovered,'tower hover release');
console.log('TOWER_CLASS_TINT_REUSE_PASS: all 7 routes, external gray, research reuse, child replacement, hover, zero-write stable refresh');

// Capacity is an explicit training-button gate for repairers. Both current
// HUDs must shade this gate while retaining hover, then restore it after the
// worker event publishes a below-cap runtime. Wallet-only shortages stay open.
for(const name of ['ability_train_repairer','ability_train_advanced_repairer']) {
 for(const locked of [false,true,false]) {
  runtime={ability_name:name,ability_entindex:100,owner_entindex:20,
   available:locked?0:1,prerequisite_met:locked?0:1,can_afford:0,
   status_text:locked?'修理工数量已达上限':'当前修理工数量'};
  if(!locked)runtime.resource_check_on_cast=1;
  nativeEnv.applyAbilityRuntime(hovered,100);
  fallbackEnv.updateSlot(fallback,{ability:100,name},0);
  assert.equal(hovered.classes.has('DOTADisabled'),locked,name+': native repairer cap tint');
  assert.equal(fallback.panel.classes.has('Unavailable'),locked,name+': fallback repairer cap tint');
  assert.equal(hovered.image.style.saturation,locked?'0':'1',name+': cap changes icon color');
  assert.equal(hovered.image.style.brightness,locked?'0.45':'1',name+': cap changes icon brightness');
  assert.notEqual(hovered.style.opacity,'0',name+': a full cap leaves the button visible');
  assert.equal(hovered.hittest,true,name+': the full-cap button retains tooltip hover');
  assert.equal(fallback.panel.enabled,true,name+': fallback retains tooltip hover');
  assert.equal(fallback.panel.classes.has('ResourceLow'),false,name+': wallet-only shortage cannot shade a below-cap button');
  const before=sent.length;
  assert.equal(input.executeAbility(100),!locked,name+': full cap blocks casts and removal restores input');
  assert.equal(sent.length,before+(locked?0:1),name+': blocked cap sends no cast request');
  hoverEnv.setExternalProxyHighlight(proxy,true);
  assert.equal(hovered.image.style.saturation,locked?'0':'1.35',name+': tooltip hover preserves the cap tint');
  hoverEnv.setExternalProxyHighlight(proxy,false);
  nativeEnv.applyAbilityRuntime(hovered,100);
  assert.equal(hovered.image.style.saturation,locked?'0':'1',name+': hover exit restores the current cap state');
 }
}
console.log('REPAIRER_CAPACITY_SHADING_PASS: ordinary/advanced native-fallback parity, visible hover, empty wallet, cast rejection and restoration');

// Tower occupancy is a construction gate rather than permanent completion.
// Both native and fallback buttons must remain visible and retain their tooltip
// at seven occupied slots, then restore color and input when a slot is released.
fallbackEnv.config={SurvivalAbilityInput:{ExecuteAbility:ability=>input.executeAbility(ability)}};
vm.runInNewContext(takeover.slice(takeover.indexOf('    function activate('),takeover.indexOf('    function ensureSlot(')),fallbackEnv);
fallbackEnv.selectedUnit=()=>20;
fallbackEnv.unitAbilityCount=()=>1;
fallbackEnv.Entities={GetAbility:()=>100};
fallbackEnv.Abilities.GetAbilityName=()=>runtime.ability_name;
fallbackEnv.Abilities.IsHidden=()=>false;
fallbackEnv.utilityHotkeys={};fallbackEnv.utilityDisplayOrder={};
vm.runInNewContext(takeover.slice(takeover.indexOf('    function visibleAbilities('),takeover.indexOf('    function rememberOfficial(')),fallbackEnv);
fallback.panel.style.visibility='visible';
for(const count of [6,7,6]) {
 const name='ability_build_arrow_tower',locked=count>=7;
 runtime={ability_name:name,ability_entindex:100,owner_entindex:20,
  available:locked?0:1,prerequisite_met:locked?0:1,can_afford:1,
  completed:0,removed:0,resource_check_on_cast:1,cost_wood:300,cost_gold:100};
 nativeEnv.applyAbilityRuntime(hovered,100);
 fallbackEnv.updateSlot(fallback,{ability:100,name},0);
 assert.equal(hovered.classes.has('DOTADisabled'),locked,count+' towers: native construction tint');
 assert.equal(fallback.panel.classes.has('Unavailable'),locked,count+' towers: fallback construction tint');
 assert.equal(hovered.image.style.saturation,locked?'0':'1',count+' towers: current cap owns the icon color');
 assert.equal(hovered.image.style.brightness,locked?'0.45':'1',count+' towers: current cap owns icon brightness');
 assert.notEqual(hovered.style.opacity,'0',count+' towers: native construction remains visible');
 assert.equal(hovered.hittest,true,count+' towers: native construction retains tooltip hover');
 assert.equal(fallbackEnv.visibleAbilities().length,1,count+' towers: fallback keeps the native construction entrance');
 assert.equal(fallback.panel.style.visibility,'visible',count+' towers: fallback construction remains visible');
 assert.equal(fallback.panel.enabled,true,count+' towers: fallback construction retains tooltip hover');
 const before=sent.length;
 assert.equal(input.executeAbility(100),!locked,count+' towers: the construction cap controls cast admission');
 assert.equal(sent.length,before+(locked?0:1),count+' towers: capped construction sends no cast request');
 const fallbackBefore=sent.length;
 fallbackEnv.activate(fallback.entry);
 assert.equal(sent.length,fallbackBefore+(locked?0:1),count+' towers: fallback activation rejects the cap and restores after release');
 hoverEnv.setExternalProxyHighlight(proxy,true);
 assert.equal(hovered.image.style.saturation,locked?'0':'1.35',count+' towers: tooltip hover preserves cap tint');
 hoverEnv.setExternalProxyHighlight(proxy,false);
 nativeEnv.applyAbilityRuntime(hovered,100);
 assert.equal(hovered.image.style.saturation,locked?'0':'1',count+' towers: hover release restores current capacity color');
}
runtime.can_afford=0;
nativeEnv.applyAbilityRuntime(hovered,100);
fallbackEnv.updateSlot(fallback,{ability:100,name:runtime.ability_name},0);
assert.equal(hovered.classes.has('DOTADisabled'),false,'below-cap empty wallet keeps native construction colored');
assert.equal(fallback.panel.classes.has('Unavailable'),false,'below-cap empty wallet keeps fallback construction colored');
assert.equal(fallback.panel.classes.has('ResourceLow'),false,'wallet projection cannot change construction border color');
const towerWalletRequests=sent.length;
assert.equal(input.executeAbility(100),true,'below-cap empty-wallet construction reaches authoritative resource validation');
assert.equal(sent.length,towerWalletRequests+1,'empty-wallet construction sends the validation request');
console.log('TOWER_BUILD_CAPACITY_SHADING_PASS: 6/7/6 native-fallback parity, visible tooltip hover, cast rejection and restoration, empty wallet');

// Exercise the real tooltip commit/reset ordering, including same native
// AbilityButton reuse. The new identity must own the new highlight.
function hoverBinding(ability=100) {
 const visual=nativeSlot();visual.IsValid=()=>true;visual.image.IsValid=()=>true;
 visual.id='AbilityButton';
 const proxy={style:{},IsValid:()=>true,__survivalVisualAnchor:visual,
  __survivalAbilityIndex:ability,__survivalAbilityName:'ability_research_tower_attack',
  __survivalBindingKey:'old',__survivalHoverSerial:0};
 return {proxy,visual};
}
const byAbility={
 100:currentRuntime('ability_research_tower_attack',0),
 200:{...currentRuntime('ability_tower_class_3',1),ability_entindex:200},
};
const commitEnv={activeSourcePanel:null,tooltipDiagnostics:false,
 selectedUnit:()=>20,customConfig:{},externalProxies:[],
 readTooltipTable:(table,id)=>byAbility[Number(id)]||{},
 GameUI:{CustomUIConfig:()=>({})},tooltipError(stage,error){throw error},
 scheduleExternalGeometryDiagnostic(){},hideAllTooltips() {}}
vm.runInNewContext(tooltip.slice(tooltip.indexOf('    function externalAbilityHighlightTarget('),tooltip.indexOf('    function acquireSelectiveTooltip(')),commitEnv);
vm.runInNewContext(tooltip.slice(tooltip.indexOf('    function commitExternalAbility('),tooltip.indexOf('    function bindOfficialAbilities(')),commitEnv);
vm.runInNewContext(tooltip.slice(tooltip.indexOf('    function disableExternalProxies('),tooltip.indexOf('    function proxyCursorState(')),commitEnv);
function bindingFor(proxy,anchor,identity=200) {
 return {proxy,entry:{anchor},key:'new-'+identity,abilityIndex:identity,
  abilityName:byAbility[identity].ability_name,displayIndex:2,engineSlot:2,
  position:'0px 0px 0px',proxyWidth:'40px',proxyHeight:'40px',windowWidth:40,windowHeight:40};
}
const same=hoverBinding();commitEnv.activeSourcePanel=same.proxy;
commitEnv.setExternalProxyHighlight(same.proxy,true);
commitEnv.commitExternalAbility(bindingFor(same.proxy,same.visual));
assert.equal(same.proxy.__survivalAbilityIndex,200,'reused hover proxy binds the tower identity');
assert.equal(same.visual.image.style.saturation,'1.35','same-anchor rebound uses new unlocked tower runtime');
assert.equal(same.visual.image.style.brightness,'1.25','same-anchor rebound preserves unlocked hover brightness');
runtime=byAbility[200];
nativeEnv.applyAbilityRuntime(same.visual,200);
assert.equal(same.visual.image.style.saturation,'1.35','managed renderer preserves matching tower hover');
assert.equal(same.visual.image.style.brightness,'1.25','managed renderer preserves matching hover brightness');
same.visual.image.resetWrites();same.visual.resetWrites();
for(let index=0;index<40;index++) nativeEnv.applyAbilityRuntime(same.visual,200);
assert.equal(same.visual.image.writes().style,0,'stable matching hover incurs no managed color writes');
assert.equal(same.visual.writes().classes,0,'stable matching hover incurs no managed class writes');
commitEnv.setExternalProxyHighlight(same.proxy,false);
nativeEnv.applyAbilityRuntime(same.visual,200);
assertNormal(same.visual,'hover exits after identity rebinding');
const changed=hoverBinding(),newVisual=nativeSlot();
newVisual.IsValid=()=>true;newVisual.image.IsValid=()=>true;newVisual.id='AbilityButton';
commitEnv.activeSourcePanel=changed.proxy;commitEnv.setExternalProxyHighlight(changed.proxy,true);
commitEnv.commitExternalAbility(bindingFor(changed.proxy,newVisual));
assert.equal(changed.visual.image.style.saturation,'0','old locked anchor retains its lock when released');
assert.equal(newVisual.image.style.saturation,'1.35','new anchor receives the tower hover color');
assert.equal(newVisual.image.style.brightness,'1.25','new anchor receives matching hover brightness');
for(const operation of ['disableExternalProxies','disableUnusedExternalProxies']) {
 const stale=hoverBinding();commitEnv.activeSourcePanel=null;
 commitEnv.setExternalProxyHighlight(stale.proxy,true);
 commitEnv.externalProxies=[stale.proxy];
 if(operation==='disableExternalProxies') commitEnv.disableExternalProxies();
 else commitEnv.disableUnusedExternalProxies([]);
 assert.equal(stale.visual.image.style.saturation,'0',operation+': release occurs while locked research identity is still known');
 assert.equal(stale.visual.image.style.brightness,'0.45',operation+': old lock remains visually consistent');
 assert.equal(stale.proxy.__survivalAbilityIndex,-1,operation+': proxy identity is cleared after releasing hover');
 assert.equal(stale.proxy.__survivalHighlightTarget,null,operation+': no stale hover target survives');
}
console.log('TOWER_CLASS_HOVER_BINDING_PASS: actual same/new anchor commits, identity reset ordering, stable hover zero-write refresh');

// Panorama reads scalar style values back in canonical numeric formatting,
// e.g. assigning "1" reads as "1.000". Repeated refreshes must compare numbers.
function formattedPanel(initial={brightness:'1.0',saturation:'1.0'}) {
 const result=trackedPanel(initial),baseStyle=result.style;
 result.style=new Proxy(baseStyle,{
  get(target,key) {
   const value=target[key];
   return (key==='saturation'||key==='brightness') && Number.isFinite(parseFloat(value))
    ? parseFloat(value).toFixed(3) : value;
  },
  set(target,key,value) {
   target[key]=(key==='saturation'||key==='brightness') && Number.isFinite(parseFloat(value))
    ? parseFloat(value).toFixed(3) : value;
   return true;
  }
 });
 return result;
}
function formattedSlot(initial) {
 const root=formattedPanel(),image=formattedPanel(initial);
 root.image=image;root.IsValid=()=>true;image.IsValid=()=>true;root.id='AbilityButton';
 root.FindChildTraverse=id=>id==='AbilityImage'?root.image:null;
 return root;
}
function assertTintNumber(slot,saturation,brightness,reason) {
 assert.equal(parseFloat(slot.image.style.saturation),saturation,reason+': saturation');
 assert.equal(parseFloat(slot.image.style.brightness),brightness,reason+': brightness');
}
function checkStableWrites(slot,ability,reason) {
 slot.resetWrites();slot.image.resetWrites();
 for(let index=0;index<40;index++) nativeEnv.applyAbilityRuntime(slot,ability);
 assert.equal(slot.image.writes().style,0,reason+': canonical style formatting causes no additional writes');
 assert.equal(slot.writes().classes,0,reason+': no repeated class writes');
}
for(const name of ['ability_builder_blink','ability_destroy_arrow_tower','ability_arrow_tower_piercing']) {
 const known=formattedSlot({brightness:'0.450',saturation:'0.0'});
 runtime={ability_name:name,ability_entindex:100,owner_entindex:20,available:1,can_afford:1};
 nativeEnv.applyAbilityRuntime(known,100);
 assertTintNumber(known,1,1,name+' known identity restores gray without explicit prerequisite');
 checkStableWrites(known,100,name+' unlocked');
 runtime.available=0;nativeEnv.applyAbilityRuntime(known,100);
 assertTintNumber(known,0,0.45,name+' locked');
 checkStableWrites(known,100,name+' locked');
 runtime.available=1;nativeEnv.applyAbilityRuntime(known,100);
 assertTintNumber(known,1,1,name+' reenabled');
 checkStableWrites(known,100,name+' reenabled');
}
const unknown=formattedSlot({saturation:'0.630',brightness:'0.820'});
runtime={};nativeEnv.applyAbilityRuntime(unknown,100);
assertTintNumber(unknown,0.63,0.82,'unknown native ability preserves its own appearance');
checkStableWrites(unknown,100,'unknown native stable');
runtime={ability_entindex:999,available:1};nativeEnv.applyAbilityRuntime(unknown,100);
assertTintNumber(unknown,0.63,0.82,'mismatched runtime identity cannot recolor native image');
runtime={available:0};nativeEnv.applyAbilityRuntime(unknown,100);
assertTintNumber(unknown,0,0.45,'unknown disabled appearance is temporarily owned');
nativeEnv.restoreAbilityRuntime(unknown);
assertTintNumber(unknown,0.63,0.82,'unknown native cleanup restores sampled styles');
runtime={};checkStableWrites(unknown,100,'unknown native after owned cleanup');
const formattedHover=formattedSlot({saturation:'0.0',brightness:'0.450'});
const numericProxy={style:{},IsValid:()=>true,__survivalVisualAnchor:formattedHover,
 __survivalAbilityIndex:100,__survivalBindingKey:'numeric'};
runtime={ability_name:'ability_destroy_arrow_tower',ability_entindex:100,available:1};
const numericHoverEnv={selectedUnit:()=>20,readTooltipTable:()=>runtime,
 GameUI:{CustomUIConfig:()=>({})},tooltipError(stage,error){throw error}};
vm.runInNewContext(tooltip.slice(tooltip.indexOf('    function externalAbilityHighlightTarget('),tooltip.indexOf('    function acquireSelectiveTooltip(')),numericHoverEnv);
numericHoverEnv.setExternalProxyHighlight(numericProxy,true);
assertTintNumber(formattedHover,1.35,1.25,'formatted known-identity hover uses colored emphasis');
nativeEnv.applyAbilityRuntime(formattedHover,100);
assertTintNumber(formattedHover,1.35,1.25,'formatted managed renderer retains matching hover');
checkStableWrites(formattedHover,100,'formatted stable hovered ability');
numericHoverEnv.setExternalProxyHighlight(numericProxy,false);
assertTintNumber(formattedHover,1,1,'hover release ignores saved 0.0/0.450 gray on known identity');
checkStableWrites(formattedHover,100,'formatted stable hover release');
// Unknown hover-only actions still normalize legacy gray numeric strings. This
// checks the scalar comparison independently of managed identity admission.
const legacyHover=formattedSlot({saturation:'0.0',brightness:'0.450'});
const legacyProxy={style:{},IsValid:()=>true,__survivalVisualAnchor:legacyHover,__survivalAbilityIndex:300};
runtime={available:1};numericHoverEnv.setExternalProxyHighlight(legacyProxy,true);
numericHoverEnv.setExternalProxyHighlight(legacyProxy,false);
assertTintNumber(legacyHover,1,1,'legacy hover release compares saved gray values numerically');
console.log('PANORAMA_NUMERIC_TINT_PASS: canonical getters, known identity without prerequisites, native style preservation, hover release, stable zero writes');
