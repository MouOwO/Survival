const fs=require('fs'),vm=require('vm'),assert=require('assert');
let now=0,selected=7,unitName="unknown_unit";
const cfg={};
vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/portrait_palette.js','utf8'),{GameUI:{CustomUIConfig:()=>cfg}});
vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/portrait_presentation.js','utf8'),{GameUI:{CustomUIConfig:()=>cfg},Players:{GetLocalPlayerPortraitUnit:()=>selected},Entities:{GetUnitName:()=>unitName},Date:{now:()=>now}});
class Panel {
 constructor(id,parent){this.id=id;this.parent=parent;this.children=[];this.style={};this.hittest=true;this.hittestchildren=true;if(parent)parent.children.push(this);}
 IsValid(){return !this.removed;}
 GetParent(){return this.parent;}
 BAscendantHasClass(name){for(let p=this;p;p=p.parent)if(p.classes&&p.classes.has(name))return true;return false;}
 FindChildTraverse(id){if(this.id===id&&!this.removed)return this;for(const c of this.children){if(c.removed)continue;const found=c.FindChildTraverse(id);if(found)return found;}return null;}
}
function fixture(){
 const block=new Panel('center_block'),group=new Panel('PortraitGroup',block),container=new Panel('PortraitContainer',group),native=new Panel('portraitHUD',container);
 for(const id of ['portraitHUDOverlay','RightSideHeroBlur','SilenceIcon','MutedIcon','DeathGradient'])new Panel(id,container);
 for(const id of ['PortraitStreakParticle','PortraitStreakParticleBorder'])new Panel(id,group);
 for(const id of ['HUDSkinPortrait','HUDSkinXPBackground','xp','unitbadge'])new Panel(id,block);
 for(const id of ['LowerOverlay','InspectButton','ReportUserButton','HeroViewButton'])new Panel(id,native);
 const custom=new Panel('SurvivalTowerPortraitOverlay',container),scene=new Panel('SurvivalTowerPortraitScene',custom);
 const frame=new Panel('HandoffPortraitFrame',block),level=new Panel('HandoffLevelPlate',block),multi=new Panel('multiunit',block);
 return {block,group,container,native,custom,scene,frame,level,multi};
}
for(const nativeOpacity of ['0','1']){
 const f=fixture();f.native.style.opacity=nativeOpacity;
 cfg.SurvivalPortraitPresentation.Refresh(f.group);
 for(const id of ['RightSideHeroBlur','portraitHUDOverlay','SilenceIcon','MutedIcon','DeathGradient','HUDSkinPortrait','HUDSkinXPBackground','InspectButton','PortraitStreakParticleBorder','xp','unitbadge']){
  const p=f.block.FindChildTraverse(id);assert.equal(p.style.visibility,'collapse',id);assert.equal(p.style.opacity,'0');assert.equal(p.hittest,false);
 }
 assert.equal(f.native.style.opacity,nativeOpacity,'must preserve native/custom portrait ownership');
 for(const p of [f.container,f.native,f.custom,f.scene,f.frame,f.level,f.multi])assert.notEqual(p.style.visibility,'collapse','must retain '+p.id);
 assert(f.container.style.backgroundColor.includes('#29424b'));
 assert.equal(f.container.style.backgroundImage,'none');
 assert.equal(f.container.style.backgroundImage,f.custom.style.backgroundImage);
 assert.equal(f.native.style.blur,'gaussian(0)');
 // Engine state updates may reveal the old layer again between HUD ticks.
 const blur=f.group.FindChildTraverse('RightSideHeroBlur');blur.style.visibility='visible';blur.style.opacity='1';
 cfg.SurvivalPortraitPresentation.Refresh(f.group);assert.equal(blur.style.visibility,'collapse');
 // Recreated native children must be reacquired, not left in a stale cache.
 const old=f.group.FindChildTraverse('SilenceIcon');old.removed=true;const fresh=new Panel('SilenceIcon',f.container);
 cfg.SurvivalPortraitPresentation.Refresh(f.group);assert.equal(fresh.style.visibility,'collapse');
}
assert.doesNotThrow(()=>cfg.SurvivalPortraitPresentation.Refresh(null));
const layout=fs.readFileSync('panorama/src/layout/custom_game/survival_hud.xml','utf8');
assert(layout.indexOf('portrait_presentation.js')<layout.indexOf('topnav_remaining_5d5c1152eb.js'));
for(const file of ['topnav_remaining_5d5c1152eb.js','handoff_hud.js']){
 const src=fs.readFileSync('panorama/src/scripts/custom_game/'+file,'utf8');
 assert(src.slice(src.indexOf('function refreshNow()')).includes('SurvivalPortraitPresentation.Refresh'));
}
console.log('PORTRAIT_PRESENTATION_PASS: old-size blur and native XP/badges removed; native/custom 3D, gold frame, level and multiselect preserved; state rewrites and HUD rebuild covered');

const f=fixture();selected=88;f.group.classes=new Set(['UnitSilenced','UnitMuted']);
now=10000;cfg.SurvivalPortraitPresentation.Refresh(f.group);
const silence=f.group.FindChildTraverse('SilenceIcon'),muted=f.group.FindChildTraverse('MutedIcon');
assert.equal(silence.style.opacity,'1');assert.equal(silence.style.visibility,'visible');
assert.equal(muted.style.visibility,'collapse','overlapping native faces must not double-draw');
now=12999;cfg.SurvivalPortraitPresentation.Refresh(f.group);assert.equal(silence.style.opacity,'1');
now=13000;cfg.SurvivalPortraitPresentation.Refresh(f.group);assert.equal(silence.style.opacity,'0');assert.equal(silence.style.transitionDuration,'0.25s');
now=13250;cfg.SurvivalPortraitPresentation.Refresh(f.group);assert.equal(silence.style.visibility,'collapse');
now=20000;cfg.SurvivalPortraitPresentation.Refresh(f.group);assert.equal(silence.style.visibility,'collapse','continuous status cannot restart');
selected=89;cfg.SurvivalPortraitPresentation.Refresh(f.group);assert.equal(silence.style.opacity,'1','new selected entity gets its own three seconds');
selected=88;cfg.SurvivalPortraitPresentation.Refresh(f.group);assert.equal(silence.style.visibility,'collapse','reselecting the same ongoing status must not replay');
const rebuilt=fixture();rebuilt.group.classes=new Set(['UnitSilenced']);cfg.SurvivalPortraitPresentation.Refresh(rebuilt.group);
assert.equal(rebuilt.group.FindChildTraverse('SilenceIcon').style.visibility,'collapse','HUD rebuilding must not replay an ongoing status');
f.group.classes.clear();cfg.SurvivalPortraitPresentation.Refresh(f.group);
f.group.classes.add('UnitSilenced');now=21000;cfg.SurvivalPortraitPresentation.Refresh(f.group);assert.equal(silence.style.opacity,'1','new status episode restarts the three second window');
console.log('PORTRAIT_STATUS_TIMER_PASS: 3s display + 250ms fade; no repeated continuous status, independent units, reselection/HUD rebuild, status reapplication');

selected=-1;cfg.SurvivalPortraitPresentation.Refresh(f.group);assert.equal(silence.style.visibility,"collapse","clearing selection removes any pending face");

// Native heroes and cosmetic model overrides share the actual visible fill.
selected=777;
const colors=fixture();
for(const [hero,color] of [['ember_spirit','#b57924'],['rubick','#285b27'],['doom_bringer','#943d20'],['drow_ranger','#355979']]){
 unitName='npc_dota_hero_'+hero;
 cfg.SurvivalPortraitPresentation.Refresh(colors.group);
 assert.equal(cfg.SurvivalPortraitPresentation.InspectBackdrop().color,color);
 assert(colors.container.style.backgroundColor.includes(color));
 assert.equal(colors.container.style.backgroundColor,colors.custom.style.backgroundColor);
}
unitName='some_challenge_monster';
cfg.SurvivalPortraitPresentation.SetSnapshot({entindex:777,portrait_unit_name:'npc_dota_hero_ember_spirit'});
cfg.SurvivalPortraitPresentation.Refresh(colors.group);
assert.equal(cfg.SurvivalPortraitPresentation.InspectBackdrop().color,'#b57924');
selected=778;unitName='npc_dota_hero_rubick';
cfg.SurvivalPortraitPresentation.Refresh(colors.group);
assert.equal(cfg.SurvivalPortraitPresentation.InspectBackdrop().color,'#285b27','old entity snapshot must never tint a newly selected unit');
unitName='some_tower';cfg.SurvivalPortraitPresentation.SetSnapshot({entindex:778,model_asset_id:'hero_permanent_hero_doom'});
assert.equal(cfg.SurvivalPortraitPresentation.InspectBackdrop().color,'#943d20');
cfg.SurvivalPortraitPresentation.SetSnapshot({entindex:778,model_asset_id:'',portrait_unit_name:''});
assert.equal(cfg.SurvivalPortraitPresentation.InspectBackdrop().color,'#29424b','explicit clear returns to fallback');
console.log('PORTRAIT_HERO_PALETTE_PASS: hero colors, cosmetic identity, stale selection rejection, native/custom fills match');

// Use the production scene controller with separate state so the native HUD
// assertions above remain independent of the corner shortcut's live identity.
const shortcutState={player:0,hero:101,selected:901,alive:true,canSelect:true,
 identity:{hero_ready:1,hero_id:'hero_monkey_king',unit_entindex:101}};
const shortcutNames={101:'npc_dota_hero_monkey_king',102:'npc_dota_hero_juggernaut',
 103:'npc_dota_hero_drow_ranger',901:'npc_survival_builder_proxy',902:'npc_dota_hero_axe'};
const shortcutOwners={101:0,102:0,103:0,901:0,902:1};
const shortcutClicks=[],shortcutConfig={SurvivalHeroSelection:{
 CanSelect:()=>shortcutState.canSelect,Select:source=>shortcutClicks.push(source)}};
vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/portrait_presentation.js','utf8'),{
 GameUI:{CustomUIConfig:()=>shortcutConfig},
 Game:{GetLocalPlayerID:()=>shortcutState.player,IsInToolsMode:()=>false},
 CustomNetTables:{GetTableValue:(table,key)=>table==='survival_hero_skills'&&key==='player_0'?shortcutState.identity:null},
 Players:{GetPlayerHeroEntityIndex:()=>shortcutState.hero,GetLocalPlayerPortraitUnit:()=>shortcutState.selected},
 Entities:{GetUnitName:entity=>shortcutNames[entity]||'',GetPlayerOwnerID:entity=>shortcutOwners[entity],
  IsValidEntity:entity=>Object.prototype.hasOwnProperty.call(shortcutNames,entity),IsAlive:()=>shortcutState.alive},
 Date:{now:()=>now},$:{Msg(){},Warning(){}}
});
const shortcutPresentation=shortcutConfig.SurvivalPortraitPresentation;
assert.equal(typeof shortcutPresentation.BindShortcutScene,'function','3D shortcuts share one cached scene binding helper');

function sceneFixture(id){
 const calls={local:[],unit:[],clear:0};
 const scene=new Panel(id);
 scene.paneltype='DOTAScenePanel';
 scene.SetUnit=(...args)=>{calls.unit.push(args);return undefined;};
 scene.ClearScene=()=>{calls.clear++;};
 scene.SetScenePanelToLocalHero=(...args)=>{
  calls.local.push(args);
  throw new Error('post-game loadout API must not bind a live custom-game shortcut');
 };
 return {scene,calls};
}
const directHeroScene=sceneFixture('DirectHeroShortcut');
for(let tick=0;tick<300;tick++)shortcutPresentation.BindShortcutScene(directHeroScene.scene,'hero:101:npc_dota_hero_monkey_king','npc_dota_hero_monkey_king',true);
assert.equal(directHeroScene.calls.local.length,0,'live custom-game shortcut never uses the account-loadout/post-game hero API');
assert.deepEqual(directHeroScene.calls.unit,[['npc_dota_hero_monkey_king','default',false]],'stable actual hero type binds one verified native scene');
const builderScene=sceneFixture('BuilderShortcut');
for(let tick=0;tick<300;tick++)shortcutPresentation.BindShortcutScene(builderScene.scene,'builder:901:npc_dota_hero_wisp','npc_dota_hero_wisp',false);
assert.equal(builderScene.calls.local.length,0,'builder must not borrow the local summoned combat hero');
assert.deepEqual(builderScene.calls.unit,[['npc_dota_hero_wisp','default',false]],'stable builder scene loads native Io once');
// A hot update can retain the old identity cache while changing the native
// portrait camera. Migrate that existing scene once, then retain steady caching.
const cameraMigration=sceneFixture('CameraMigrationShortcut');
cameraMigration.scene.__survivalSceneKey='hero:101:npc_dota_hero_monkey_king';
cameraMigration.scene.__survivalSceneCamera='shortcut_soft';
for(let tick=0;tick<300;tick++)shortcutPresentation.BindShortcutScene(cameraMigration.scene,'hero:101:npc_dota_hero_monkey_king','npc_dota_hero_monkey_king',true);
assert.deepEqual(cameraMigration.calls.unit,[['npc_dota_hero_monkey_king','default',false]],'same identity with retired camera reloads exactly once into the native default camera');
assert.equal(cameraMigration.scene.__survivalSceneCamera,'default','successful migration updates the camera cache');
assert.equal(cameraMigration.calls.local.length,0,'camera migration retains the native SetUnit path');
const rebuiltBuilderScene=sceneFixture('BuilderShortcut');
shortcutPresentation.BindShortcutScene(rebuiltBuilderScene.scene,'builder:901:npc_dota_hero_wisp','npc_dota_hero_wisp',false);
assert.equal(rebuiltBuilderScene.calls.unit.length,1,'new scene node with same identity needs its own load');
const failedScene=sceneFixture('FailedShortcut');
failedScene.scene.SetUnit=(...args)=>{failedScene.calls.unit.push(args);throw new Error('simulated missing model');};
const beforeFailedProbe=now;now=30000;
for(let tick=0;tick<300;tick++){
 now=30000+tick*10;
 assert.equal(shortcutPresentation.BindShortcutScene(failedScene.scene,'hero:101:npc_dota_hero_monkey_king','npc_dota_hero_monkey_king',true),false);
}
assert.equal(failedScene.calls.local.length,0,'failed native scene never tries an unrelated account-loadout scene');
assert.equal(failedScene.calls.unit.length,1,'failure cannot repeatedly load missing assets at HUD frequency');
now=35000;
assert.equal(shortcutPresentation.BindShortcutScene(failedScene.scene,'hero:101:npc_dota_hero_monkey_king','npc_dota_hero_monkey_king',true),false);
assert.equal(failedScene.calls.local.length,0);
assert.equal(failedScene.calls.unit.length,2,'failed identity permits one retry after the existing cooldown');
now=beforeFailedProbe;
console.log('SHORTCUT_SCENE_BINDING_PASS: stable 300-tick native SetUnit cache, one-time retired-camera migration, no post-game/account-loadout calls, failure cooldown, independent Io and rebuilt scenes');

const cornerRoot=new Panel('ShortcutHud'),cornerButton=new Panel('SurvivalLocalHeroPortrait',cornerRoot);
cornerButton.events={};cornerButton.SetPanelEvent=(event,fn)=>{cornerButton.events[event]=fn;};
const corner=sceneFixture('SurvivalLocalHeroPortraitImage');
corner.scene.parent=cornerButton;cornerButton.children.push(corner.scene);
for(let tick=0;tick<300;tick++)shortcutPresentation.RefreshLocalHeroPortrait(cornerRoot);
assert.equal(corner.calls.unit.length,1,'live corner 300 stable refreshes load the actual hero only once');
assert.deepEqual(corner.calls.unit[0],['npc_dota_hero_monkey_king','default',false]);
assert.equal(corner.calls.local.length,0,'live corner does not borrow the Steam account loadout API');
assert.equal(cornerButton.visible,true);assert.equal(cornerButton.enabled,true);assert.equal(cornerButton.hittest,true);
cornerButton.events.onactivate();assert.deepEqual(shortcutClicks,['top_left_portrait'],'original hero selection entry point is preserved');
assert.equal(shortcutState.selected,901,'model binding never changes the selected builder');

shortcutState.selected=902;shortcutState.alive=false;
for(let tick=0;tick<40;tick++)shortcutPresentation.RefreshLocalHeroPortrait(cornerRoot);
assert.equal(corner.calls.unit.length,1,'selection/death changes do not rebuild the summoned hero model');
assert.equal(cornerButton.visible,true,'dead summoned hero stays available for inspection');
assert.equal(cornerButton.enabled,true,'original selection controller still owns dead-hero availability');
shortcutState.canSelect=false;shortcutPresentation.RefreshLocalHeroPortrait(cornerRoot);
assert.equal(cornerButton.enabled,false,'modal/input guard can disable the button without destroying its scene');
assert.equal(corner.calls.unit.length,1);
shortcutState.canSelect=true;

shortcutState.hero=102;shortcutState.identity={hero_ready:1,hero_id:'hero_blademaster',unit_entindex:102};
for(let tick=0;tick<40;tick++)shortcutPresentation.RefreshLocalHeroPortrait(cornerRoot);
assert.equal(corner.calls.unit.length,2,'replacement hero entity binds exactly once');
assert.deepEqual(corner.calls.unit[1],['npc_dota_hero_juggernaut','default',false],'replacement uses the new hero type rather than selected builder');
assert.equal(cornerButton.visible,true);

shortcutState.identity={hero_ready:0,hero_id:'',unit_entindex:102};
for(let tick=0;tick<40;tick++)shortcutPresentation.RefreshLocalHeroPortrait(cornerRoot);
assert.equal(cornerButton.visible,false);assert.equal(cornerButton.hittest,false);assert.equal(cornerButton.enabled,false);
assert.equal(corner.calls.clear,0,'unready state hides its cached scene without repeated native teardown');
assert.equal(corner.calls.unit.length,2);

shortcutState.identity={hero_ready:1,hero_id:'hero_blademaster',unit_entindex:102};
shortcutPresentation.RefreshLocalHeroPortrait(cornerRoot);
assert.equal(corner.calls.unit.length,2,'same authoritative hero after temporary loading reuses the hidden cached scene');
assert.equal(cornerButton.visible,true);
corner.scene.removed=true;
const replacementCorner=sceneFixture('SurvivalLocalHeroPortraitImage');
replacementCorner.scene.parent=cornerButton;cornerButton.children.push(replacementCorner.scene);
for(let tick=0;tick<40;tick++)shortcutPresentation.RefreshLocalHeroPortrait(cornerRoot);
assert.equal(replacementCorner.calls.unit.length,1,'HUD node recreation reloads once even with the same hero entity');
assert.equal(replacementCorner.calls.local.length,0);
assert.equal(corner.calls.unit.length,2,'removed scene is not reused');
cornerButton.events.onactivate();assert.deepEqual(shortcutClicks,['top_left_portrait','top_left_portrait']);

// Authoritative identity must win over selected units and foreign/stale heroes.
for(const identity of [
 {hero_ready:1,hero_id:'hero_axe',unit_entindex:902},
 {hero_ready:1,hero_id:'hero_blademaster',unit_entindex:null},
 {hero_ready:1,hero_id:'hero_blademaster'},
 {hero_ready:1,hero_id:'hero_blademaster',unit_entindex:103}
]){
 shortcutState.identity=identity;shortcutPresentation.RefreshLocalHeroPortrait(cornerRoot);
 assert.equal(cornerButton.visible,false,'invalid/foreign/mismatched identity cannot populate the corner');
}
assert.equal(replacementCorner.calls.unit.length,1,'rejected identities never bind a model');
assert.equal(shortcutState.selected,902,'all scene lifecycle work stays independent of current selection');
assert(/<DOTAScenePanel\b[^>]*id="SurvivalLocalHeroPortraitImage"/.test(layout),'formal hero shortcut is an actual native 3D panel');
console.log('HERO_CORNER_SCENE_LIFECYCLE_PASS: actual hero identity, replacement/death, guards, loading hide/reuse, node recreation, click preservation and selection isolation');
