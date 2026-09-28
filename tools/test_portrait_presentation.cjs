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
