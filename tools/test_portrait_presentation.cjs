const fs=require('fs'),vm=require('vm'),assert=require('assert');
let now=0,selected=7,unitName="unknown_unit";
const cfg={};
vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/portrait_palette.js','utf8'),{GameUI:{CustomUIConfig:()=>cfg}});
vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/portrait_presentation.js','utf8'),{GameUI:{CustomUIConfig:()=>cfg},Players:{GetLocalPlayerPortraitUnit:()=>selected},Entities:{GetUnitName:()=>unitName},Date:{now:()=>now},$:{CreatePanel:(type,parent,id)=>{
 assert.notEqual(type,'DOTAScenePanel','background/status presentation must not create another 3D portrait');
 return new Panel(id,parent,type);
}}});
class Panel {
 constructor(id,parent,type='Panel'){this.id=id;this.paneltype=type;this.parent=parent;this.children=[];this.style={};this.hittest=true;this.hittestchildren=true;this.imageCalls=[];if(parent)parent.children.push(this);}
 IsValid(){return !this.removed;}
 GetParent(){return this.parent;}
 AddClass(name){if(!this.classes)this.classes=new Set();this.classes.add(name);}
 SetImage(uri){this.image=uri;this.imageCalls.push(uri);}
 MoveChildBefore(child,anchor){this.children=this.children.filter(value=>value!==child);this.children.splice(this.children.indexOf(anchor),0,child);}
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

// Isolation flags on a presentation body must not cover its face. The same
// unit name/asset on a formal monster retains genuine status feedback.
const displayStatus=fixture();selected=8800;unitName='npc_survival_named_rebirth_boss_10';
displayStatus.group.classes=new Set(['UnitSilenced','UnitMuted']);
cfg.SurvivalPortraitPresentation.SetSnapshot({entindex:selected,portrait_display_only:1});
for(const stamp of [0,100,2999,3000,3250,10000]){
 now=40000+stamp;
 for(const id of ['SilenceIcon','MutedIcon']){
  const icon=displayStatus.group.FindChildTraverse(id);icon.style.visibility='visible';icon.style.opacity='1';
 }
 cfg.SurvivalPortraitPresentation.Refresh(displayStatus.group);
 for(const id of ['SilenceIcon','MutedIcon']){
  const icon=displayStatus.group.FindChildTraverse(id);
  assert.equal(icon.style.visibility,'collapse','display-only isolation never paints '+id);
  assert.equal(icon.style.opacity,'0');
 }
}
cfg.SurvivalPortraitPresentation.SetSnapshot({entindex:selected,portrait_display_only:0});now=51000;
cfg.SurvivalPortraitPresentation.Refresh(displayStatus.group);
assert.equal(displayStatus.group.FindChildTraverse('SilenceIcon').style.visibility,'visible','explicit role clear restores real silence feedback');
assert.equal(displayStatus.group.FindChildTraverse('SilenceIcon').style.opacity,'1');
selected=8801;now=52000;
cfg.SurvivalPortraitPresentation.SetSnapshot({entindex:8800,portrait_display_only:1});
cfg.SurvivalPortraitPresentation.Refresh(displayStatus.group);
assert.equal(displayStatus.group.FindChildTraverse('SilenceIcon').style.visibility,'visible','late snapshot for another entity cannot hide formal same-name monster state');
assert.equal(displayStatus.group.FindChildTraverse('SilenceIcon').style.opacity,'1');
cfg.SurvivalPortraitPresentation.SetSnapshot({entindex:selected,portrait_display_only:0});
displayStatus.group.classes=new Set(['UnitMuted']);now=52100;
cfg.SurvivalPortraitPresentation.Refresh(displayStatus.group);
assert.equal(displayStatus.group.FindChildTraverse('SilenceIcon').style.visibility,'collapse');
assert.equal(displayStatus.group.FindChildTraverse('MutedIcon').style.visibility,'visible','formal same-name monster keeps a genuine mute episode');
cfg.SurvivalPortraitPresentation.SetSnapshot(null);unitName='unknown_unit';
console.log('PORTRAIT_DISPLAY_ROLE_PASS: matching authoritative preview stays unobscured, explicit zero/formal same-name monsters retain real status and late entity snapshots cannot cross selection');

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

// The builder's map owns Io and its particles, while both possible HUD hosts
// supply the original coolinterior image underneath. Ordinary Io heroes must
// retain their existing palette, and stale builder snapshots must not leak.
selected=779;unitName='npc_survival_builder_proxy';
const builderBackdrop=fixture();
cfg.SurvivalPortraitPresentation.SetSnapshot({entindex:779,
 model_asset_id:'builder_io_benevolent_companion',portrait_unit_name:'npc_dota_hero_wisp'});
const builderImage='url("file://{images}/custom_game/portrait_builder_io/coolinterior.png")';
for(let tick=0;tick<64;tick++)cfg.SurvivalPortraitPresentation.Refresh(builderBackdrop.group);
for(const parent of [builderBackdrop.container,builderBackdrop.custom]){
 assert.equal(parent.style.backgroundImage,builderImage);
 assert.equal(parent.style.backgroundColor,'#071321');
 assert.equal(parent.style.backgroundSize,'100% 100%');
 assert.equal(parent.style.backgroundPosition,'50% 50%');
 assert.equal(parent.style.backgroundRepeat,'no-repeat');
 assert.equal(parent.style.brightness,undefined,'background cannot tint the model subtree');
 assert.equal(parent.style.washColor,undefined,'background cannot tint Io or its particles');
}
assert.equal(builderBackdrop.scene.style.backgroundImage,undefined,'image remains behind the 3D scene');
assert.equal(builderBackdrop.scene.style.brightness,undefined);
selected=780;unitName='npc_dota_hero_wisp';
cfg.SurvivalPortraitPresentation.Refresh(builderBackdrop.group);
for(const parent of [builderBackdrop.container,builderBackdrop.custom]){
 assert.equal(parent.style.backgroundImage,'none','new selection clears a stale builder image');
 assert(parent.style.backgroundColor.includes('#477e9a'),'ordinary Io retains its existing palette');
}
cfg.SurvivalPortraitPresentation.SetSnapshot({entindex:780,
 model_asset_id:'builder_io_benevolent_companion',portrait_unit_name:'npc_dota_hero_wisp'});
cfg.SurvivalPortraitPresentation.Refresh(builderBackdrop.group);
cfg.SurvivalPortraitPresentation.SetSnapshot({entindex:780,
 model_asset_id:'tower_lightning_razor',portrait_unit_name:'npc_dota_hero_razor'});
cfg.SurvivalPortraitPresentation.Refresh(builderBackdrop.group);
for(const parent of [builderBackdrop.container,builderBackdrop.custom]){
 assert.equal(parent.style.backgroundImage,'none','changing same-entity identity restores a tower gradient');
 assert(parent.style.backgroundColor.includes('#364199'));
}
cfg.SurvivalPortraitPresentation.SetSnapshot(null);
selected=-1;unitName='';cfg.SurvivalPortraitPresentation.Refresh(builderBackdrop.group);
assert.equal(builderBackdrop.container.style.backgroundImage,'none','cleared selection removes the builder image');
const ioBackgroundPng=fs.readFileSync('panorama/src/images/custom_game/portrait_builder_io/coolinterior.png');
assert.equal(ioBackgroundPng.subarray(1,4).toString(),'PNG');
assert.equal(ioBackgroundPng.readUInt32BE(16),128);assert.equal(ioBackgroundPng.readUInt32BE(20),128);
console.log('BUILDER_PORTRAIT_BACKDROP_PASS: native coolinterior image only for the selected builder, both hosts covered, palette restoration on selection/identity/clear, no model brightness or tint');

// Returning from a custom portrait must remove both the builder's image and
// generated color/motes, including before the boss snapshot arrives.
selected=790;unitName='npc_survival_builder_proxy';
const nativeRebirth=fixture();
cfg.SurvivalPortraitPresentation.SetSnapshot({entindex:selected,model_asset_id:'builder_io_benevolent_companion'});
cfg.SurvivalPortraitPresentation.Refresh(nativeRebirth.group);
// The visible native host already has motes from the builder refresh above.
new Panel('SurvivalPortraitMotes',nativeRebirth.custom);
const expectedNativeTextures=['graveyard_psd_cadcdea4','desert_psd_a61ef989','gradient_btm_psd_dfa949cf',
 'darkclouds_psd_c19b9d70','motion_swoops_color_psd_60163809','darkclouds_psd_c19b9d70',
 'graveyard_psd_cadcdea4','bluebloom_psd_e431a05c','gradient_btm_psd_dfa949cf','gradient_btm_psd_dfa949cf'];
const rebirthAssets=['phalanx','bloodforge','silverwurm','stormwrought','lucid_torment','obsidian_atrocity',
 'fairy_godmummer','reaper_elegy','phantom_advent','darkness_foretold'];
for(let rank=1;rank<=10;rank++){
 selected=790+rank;unitName='npc_survival_named_rebirth_boss_'+String(rank).padStart(2,'0');
 cfg.SurvivalPortraitPresentation.Refresh(nativeRebirth.group);
 assert.equal(cfg.SurvivalPortraitPresentation.InspectBackdrop().nativeRebirth,true);
 assert.equal(nativeRebirth.custom.style.backgroundColor,'transparent','native outfit scene keeps its own authored backdrop');
 assert.equal(nativeRebirth.custom.style.backgroundImage,'none');
 for(const key of ['backgroundColor','backgroundImage','backgroundSize','backgroundPosition','backgroundRepeat'])
  assert.equal(nativeRebirth.container.style[key],'','native rebirth clears custom '+key);
 for(const parent of [nativeRebirth.container,nativeRebirth.custom])
  assert.equal(parent.FindChildTraverse('SurvivalPortraitMotes').style.visibility,'collapse');
 const image=nativeRebirth.container.FindChildTraverse('SurvivalOfficialPortraitBackground');
 const expected='s2r://materials/vgui/hud/heroportraits/portraitbackground_'+expectedNativeTextures[rank-1]+'.vtex';
 assert(image&&image.paneltype==='Image','official background is a two-dimensional image');
 assert.equal(image.image,expected,'pending snapshot uses the actual named unit native texture');
 assert.equal(image.style.washColor,'#ffffff','official original texture must never receive an extra uniform tint');
 assert.equal(image.style.visibility,'visible');assert.equal(image.hittest,false);assert.equal(image.hittestchildren,false);
 assert(nativeRebirth.container.children.indexOf(image)<nativeRebirth.container.children.indexOf(nativeRebirth.native),'background paints behind existing native portrait');
 const before=image.imageCalls.length;
 cfg.SurvivalPortraitPresentation.SetSnapshot({entindex:selected,
  model_asset_id:'monster_boss_rebirth_'+String(rank).padStart(2,'0')+'_'+rebirthAssets[rank-1]});
 for(let tick=0;tick<64;tick++)cfg.SurvivalPortraitPresentation.Refresh(nativeRebirth.group);
 assert.equal(image.image,expected);assert.equal(image.imageCalls.length,before,'stable identity does not repeatedly load its native texture');
}
selected=8100;unitName='npc_survival_named_rebirth_boss_10';
cfg.SurvivalPortraitPresentation.SetSnapshot({entindex:8099,model_asset_id:'monster_boss_rebirth_01_phalanx',portrait_display_only:1});
cfg.SurvivalPortraitPresentation.Refresh(nativeRebirth.group);
assert.equal(nativeRebirth.container.FindChildTraverse('SurvivalOfficialPortraitBackground').image,
 's2r://materials/vgui/hud/heroportraits/portraitbackground_gradient_btm_psd_dfa949cf.vtex',
 'late other-entity metadata cannot replace the selected Doom background');
selected=809;unitName='npc_survival_builder_proxy';
cfg.SurvivalPortraitPresentation.SetSnapshot({entindex:selected,model_asset_id:'builder_io_benevolent_companion'});
cfg.SurvivalPortraitPresentation.Refresh(nativeRebirth.group);
assert.equal(nativeRebirth.container.FindChildTraverse('SurvivalOfficialPortraitBackground').style.visibility,'collapse','returning to builder hides the rebirth background');
assert.equal(nativeRebirth.container.style.backgroundImage,builderImage);
selected=810;unitName='npc_dota_hero_juggernaut';
cfg.SurvivalPortraitPresentation.Refresh(nativeRebirth.group);
assert.equal(cfg.SurvivalPortraitPresentation.InspectBackdrop().nativeRebirth,false);
assert(nativeRebirth.container.style.backgroundColor.includes('gradient('),'other heroes retain their background');
console.log('NATIVE_REBIRTH_BACKDROP_PASS: ten exact untinted Valve texture URIs, stable Image reuse behind existing native portrait, no new 3D scene, builder/hero restoration and stale Io/motes cleared');

// The real inspected-unit portrait lives under QueryVertical/MidSection and
// has no SilenceIcon. Its duplicate PortraitContainer ID must not accidentally
// make a global lookup reuse the main portrait's background Image.
function queryFixture(root){
 const vertical=new Panel('QueryVertical',root),middle=new Panel('MidSection',vertical);
 const container=new Panel('PortraitContainer',middle);
 const portrait=new Panel('QueryUnitHeroPortrait',container,'DOTAPortrait');
 portrait.style.position='native-query-position';portrait.style.transform='native-query-transform';
 portrait.SetUnit=()=>assert.fail('query background must keep the existing native portrait model');
 portrait.SetScenePanelToLocalHero=()=>assert.fail('query background must never create an Econ portrait');
 return {vertical,middle,container,portrait};
}
const dual=fixture(),dualRoot=new Panel('Hud');dual.block.parent=dualRoot;dualRoot.children.push(dual.block);
const query=queryFixture(dualRoot),officialDoom='s2r://materials/vgui/hud/heroportraits/portraitbackground_gradient_btm_psd_dfa949cf.vtex';
selected=8910;unitName='npc_survival_named_rebirth_boss_10';dual.group.classes=new Set(['UnitSilenced','UnitMuted']);
cfg.SurvivalPortraitPresentation.SetSnapshot({entindex:selected,portrait_display_only:1});
for(let tick=0;tick<64;tick++)cfg.SurvivalPortraitPresentation.Refresh(dual.group);
const mainImage=dual.container.FindChildTraverse('SurvivalOfficialPortraitBackground');
const queryImage=query.container.FindChildTraverse('SurvivalOfficialPortraitBackground');
assert(mainImage&&queryImage&&mainImage!==queryImage,'main and query trees own separate named background Images');
for(const [container,portrait,image] of [[dual.container,dual.native,mainImage],[query.container,query.portrait,queryImage]]){
 assert.equal(image.parent,container);assert.equal(image.paneltype,'Image');assert.equal(image.image,officialDoom);
 assert.equal(image.imageCalls.length,1,'each real portrait tree independently caches its native texture');
 assert.equal(image.style.washColor,'#ffffff');assert.equal(image.style.visibility,'visible');
 assert(container.children.indexOf(image)<container.children.indexOf(portrait),'each background belongs behind its own native portrait');
}
assert.equal(query.portrait.style.blur,'gaussian(0)');
assert.equal(query.portrait.style.position,'native-query-position');
assert.equal(query.portrait.style.transform,'native-query-transform');
assert.equal(query.vertical.FindChildTraverse('SilenceIcon'),null,'query fixture and correction must not invent a silence icon');
assert.equal(query.vertical.FindChildTraverse('MutedIcon'),null);
assert.equal(dual.group.FindChildTraverse('SilenceIcon').style.visibility,'collapse','main group alone owns preview state-face suppression');
selected=8920;unitName='npc_survival_builder_proxy';
cfg.SurvivalPortraitPresentation.SetSnapshot({entindex:selected,model_asset_id:'builder_io_benevolent_companion',portrait_display_only:0});
cfg.SurvivalPortraitPresentation.Refresh(dual.group);
assert.equal(mainImage.style.visibility,'collapse');assert.equal(queryImage.style.visibility,'collapse','returning to builder also hides the independent query background');
assert.equal(dual.container.style.backgroundImage,builderImage);

// Handoff can call the corner/query refresh directly while no PortraitGroup
// or local-hero corner exists. The query correction must precede those exits.
const queryOnlyRoot=new Panel('HudWithoutMainPortrait'),queryOnly=queryFixture(queryOnlyRoot);
assert.equal(queryOnlyRoot.FindChildTraverse('PortraitGroup'),null);
assert.equal(queryOnlyRoot.FindChildTraverse('SurvivalLocalHeroPortrait'),null);
selected=8930;unitName='npc_survival_named_rebirth_boss_10';
cfg.SurvivalPortraitPresentation.SetSnapshot({entindex:selected,portrait_display_only:1});
cfg.SurvivalPortraitPresentation.RefreshLocalHeroPortrait(queryOnlyRoot);
const onlyImage=queryOnly.container.FindChildTraverse('SurvivalOfficialPortraitBackground');
assert(onlyImage&&onlyImage.image===officialDoom&&onlyImage.style.visibility==='visible','query-only refresh works before a missing hero corner early return');
assert.equal(onlyImage.style.washColor,'#ffffff');
assert.equal(queryOnly.portrait.style.blur,'gaussian(0)');
selected=8931;
cfg.SurvivalPortraitPresentation.SetSnapshot({entindex:8930,model_asset_id:'monster_boss_rebirth_01_phalanx',portrait_display_only:1});
cfg.SurvivalPortraitPresentation.RefreshLocalHeroPortrait(queryOnlyRoot);
assert.equal(onlyImage.image,officialDoom,'late different-entity snapshot cannot change the query-only background');
unitName='npc_survival_builder_proxy';
cfg.SurvivalPortraitPresentation.SetSnapshot({entindex:selected,model_asset_id:'builder_io_benevolent_companion'});
cfg.SurvivalPortraitPresentation.RefreshLocalHeroPortrait(queryOnlyRoot);
assert.equal(onlyImage.style.visibility,'collapse');
assert.equal(queryOnly.vertical.FindChildTraverse('SilenceIcon'),null);assert.equal(queryOnly.vertical.FindChildTraverse('MutedIcon'),null);
console.log('NATIVE_QUERY_BACKGROUND_PASS: actual independent query tree, separate untinted Images, cached native URI behind each own portrait, no invented query state faces, query-only early-return coverage and builder restoration');

// Use the production scene controller with separate state so the native HUD
// assertions above remain independent of the corner shortcut's live identity.
const shortcutState={player:0,hero:101,selected:901,alive:true,canSelect:true,
 identity:{hero_ready:1,hero_id:'hero_monkey_king',unit_entindex:101}};
const shortcutNames={101:'npc_dota_hero_monkey_king',102:'npc_dota_hero_juggernaut',
 103:'npc_dota_hero_drow_ranger',104:'npc_dota_hero_doom_bringer',901:'npc_survival_builder_proxy',902:'npc_dota_hero_axe'};
const shortcutOwners={101:0,102:0,103:0,104:0,901:0,902:1};
const shortcutClicks=[],shortcutConfig={SurvivalHeroSelection:{
 CanSelect:()=>shortcutState.canSelect,Select:source=>shortcutClicks.push(source)}};
const shortcutSceneCreations=[];
vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/portrait_presentation.js','utf8'),{
 GameUI:{CustomUIConfig:()=>shortcutConfig},
 Game:{GetLocalPlayerID:()=>shortcutState.player,IsInToolsMode:()=>false},
 CustomNetTables:{GetTableValue:(table,key)=>table==='survival_hero_skills'&&key==='player_0'?shortcutState.identity:null},
 Players:{GetPlayerHeroEntityIndex:()=>shortcutState.hero,GetLocalPlayerPortraitUnit:()=>shortcutState.selected},
 Entities:{GetUnitName:entity=>shortcutNames[entity]||'',GetPlayerOwnerID:entity=>shortcutOwners[entity],
  IsValidEntity:entity=>Object.prototype.hasOwnProperty.call(shortcutNames,entity),IsAlive:()=>shortcutState.alive},
 Date:{now:()=>now},$:{Msg(){},Warning(){},CreatePanel(type,parent,id,attrs){
  const created=sceneFixture(id);
  created.scene.paneltype=type;
  created.scene.parent=parent;parent.children.push(created.scene);
  shortcutSceneCreations.push({...created,parent,attrs:Object.assign({},attrs)});
  return created.scene;
 }}
});
const shortcutPresentation=shortcutConfig.SurvivalPortraitPresentation;
assert.equal(typeof shortcutPresentation.BindShortcutScene,'function','3D shortcuts share one cached scene binding helper');
assert.equal(typeof shortcutPresentation.BindLocalHeroScene,'function','hero shortcuts expose their cached native/isolated scene selection');

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

// Exercise the isolated Doom camera through the same authoritative identity
// refresh used by the actual corner button, including native hero round trips.
const doomRoot=new Panel('DoomShortcutHud'),doomButton=new Panel('SurvivalLocalHeroPortrait',doomRoot);
doomButton.hittestchildren=false;
doomButton.events={};doomButton.SetPanelEvent=(event,fn)=>{doomButton.events[event]=fn;};
const doomNative=sceneFixture('SurvivalLocalHeroPortraitImage');
doomNative.scene.parent=doomButton;doomButton.children.push(doomNative.scene);
doomNative.scene.hittest=false;doomNative.scene.hittestchildren=false;
shortcutState.hero=104;shortcutState.identity={hero_ready:1,hero_id:'hero_doom_bringer',unit_entindex:104};
shortcutState.canSelect=true;shortcutState.alive=true;
const selectionBeforeDoom=shortcutState.selected;
for(let tick=0;tick<300;tick++)shortcutPresentation.RefreshLocalHeroPortrait(doomRoot);
assert.equal(shortcutSceneCreations.length,1,'300 Doom ticks create exactly one isolated portrait map');
const isolatedDoom=shortcutSceneCreations[0];
assert.equal(isolatedDoom.parent,doomButton);
assert.equal(doomButton.FindChildTraverse('SurvivalLocalHeroPortraitDoomScene'),isolatedDoom.scene,'created scene belongs to the actual button subtree');
assert.equal(isolatedDoom.scene.paneltype,'DOTAScenePanel');
assert.deepEqual(isolatedDoom.attrs,{map:'portraits/doom_soft_a',camera:'shortcut_camera',particleonly:'false'});
assert(isolatedDoom.scene.classes.has('ShortcutHeroPortraitScene'));
assert.equal(isolatedDoom.scene.hittest,false);assert.equal(isolatedDoom.scene.hittestchildren,false);
assert.equal(isolatedDoom.scene.visible,true);assert.equal(isolatedDoom.scene.style.visibility,'visible');
assert.equal(doomNative.scene.visible,false);assert.equal(doomNative.scene.style.visibility,'collapse');
assert.equal(doomNative.calls.unit.length,0,'Doom never loads the clipped native portrait through SetUnit');
assert.equal(isolatedDoom.calls.unit.length,0,'isolated map is loaded through creation attributes, never SetUnit');
assert.equal(isolatedDoom.scene.__survivalSceneLoads,1);
assert.equal(doomButton.__survivalActiveHeroScene,isolatedDoom.scene);
assert.equal(doomButton.hittest,true);assert.equal(doomButton.hittestchildren,false,'original parent button exclusively handles clicks');
const clicksBeforeDoom=shortcutClicks.length;
doomButton.events.onactivate();assert.equal(shortcutClicks.length,clicksBeforeDoom+1);
assert.equal(shortcutClicks[shortcutClicks.length-1],'top_left_portrait','isolated camera retains the existing click entry point');

shortcutState.hero=101;shortcutState.identity={hero_ready:1,hero_id:'hero_monkey_king',unit_entindex:101};
for(let tick=0;tick<300;tick++)shortcutPresentation.RefreshLocalHeroPortrait(doomRoot);
assert.equal(shortcutSceneCreations.length,1,'switching to Monkey King retains the hidden Doom map');
assert.deepEqual(doomNative.calls.unit,[['npc_dota_hero_monkey_king','default',false]],'native hero still uses one cached SetUnit binding');
assert.equal(doomNative.scene.visible,true);assert.equal(doomNative.scene.style.visibility,'visible');
assert.equal(isolatedDoom.scene.visible,false);assert.equal(isolatedDoom.scene.style.visibility,'collapse');
assert.equal(doomButton.__survivalActiveHeroScene,doomNative.scene);
assert.equal(doomNative.scene.hittest,false);assert.equal(doomNative.scene.hittestchildren,false);

shortcutState.hero=104;shortcutState.identity={hero_ready:1,hero_id:'hero_doom_bringer',unit_entindex:104};
for(let tick=0;tick<300;tick++)shortcutPresentation.RefreshLocalHeroPortrait(doomRoot);
assert.equal(shortcutSceneCreations.length,1,'returning to Doom reuses the original map across 300 further ticks');
assert.equal(doomButton.__survivalActiveHeroScene,isolatedDoom.scene);
assert.equal(isolatedDoom.scene.visible,true);assert.equal(isolatedDoom.scene.style.visibility,'visible');
assert.equal(doomNative.scene.visible,false);assert.equal(doomNative.scene.style.visibility,'collapse');
assert.equal(doomNative.calls.unit.length,1);assert.equal(isolatedDoom.calls.unit.length,0);
assert.equal(isolatedDoom.calls.clear,0);assert.equal(isolatedDoom.scene.__survivalSceneLoads,1);
assert.equal(isolatedDoom.scene.hittest,false);assert.equal(isolatedDoom.scene.hittestchildren,false);
assert.equal(shortcutState.selected,selectionBeforeDoom,'scene switching never changes the current game selection');
console.log('DOOM_CORNER_ISOLATED_SCENE_PASS: one lazy map across 300-tick Doom/Monkey/Doom round trip, no Doom SetUnit, native cache, visibility switching and noninteractive scenes');
