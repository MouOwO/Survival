const fs=require('fs'),vm=require('vm'),assert=require('assert');
let selected=7,clock=1000,multi=false,assigned=30,names={7:'unknown',30:'npc_dota_hero_doom_bringer',40:'npc_dota_hero_rubick'},states={};
const cfg={SurvivalMultiSelectionPortraits:{IsActive:()=>multi}};
class Panel {
 constructor(id,parent,type='Panel'){this.id=id;this.parent=parent;this.paneltype=type;this.children=[];this.style={};this.hittest=true;this.hittestchildren=true;if(parent)parent.children.push(this);}
 IsValid(){return !this.removed;}
 GetParent(){return this.parent;}
 AddClass(name){(this.classes||(this.classes=new Set())).add(name);}
 Children(){return this.children.filter(x=>!x.removed);}
 FindChildTraverse(id){if(this.id===id&&this.IsValid())return this;for(const c of this.Children()){const p=c.FindChildTraverse(id);if(p)return p;}return null;}
 MoveChildBefore(child,before){assert.equal(child.parent,this);assert.equal(before.parent,this);this.children.splice(this.children.indexOf(child),1);this.children.splice(this.children.indexOf(before),0,child);}
 SetPanelEvent(name,fn){(this.events||(this.events={}))[name]=fn;}
 SetImage(path){this.image=path;}
 SetUnit(name,camera){this.unit=name;this.camera=camera;this.loads=(this.loads||0)+1;return true;}
 DeleteAsync(){this.removed=true;}
}
const root=new Panel('root'),block=new Panel('center',root),group=new Panel('PortraitGroup',block),container=new Panel('PortraitContainer',group),native=new Panel('portraitHUD',container),custom=new Panel('SurvivalTowerPortraitOverlay',container),scene=new Panel('SurvivalTowerPortraitScene',custom);
custom.style.visibility='collapse';
const context={GameUI:{CustomUIConfig:()=>cfg},Players:{GetLocalPlayerPortraitUnit:()=>selected,GetPlayerHeroEntityIndex:()=>assigned},Entities:{GetUnitName:e=>names[e]||'',GetPlayerOwnerID:()=>0},CustomNetTables:{GetTableValue:(table,key)=>states[key]},Date:{now:()=>clock},$:{CreatePanel:(type,parent,id,attrs)=>{const p=new Panel(id,parent,type);p.attributes=attrs||{};return p;},Warning(){}}};
for(const file of ['portrait_palette','portrait_presentation'])vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/'+file+'.js','utf8'),context);
const api=cfg.SurvivalPortraitPresentation;
api.SetSnapshot({entindex:7,portrait_model_name:'models/heroes/ember_spirit/ember_spirit.vmdl'});
assert.equal(api.InspectBackdrop().color,'#b57924');
api.Refresh(group);
const layer=container.FindChildTraverse('SurvivalPortraitMotes');assert.equal(layer.GetParent(),container);assert.equal(layer.Children().length,4);assert.equal(layer.hittest,false);assert.equal(layer.hittestchildren,false);assert.equal(layer.style.zIndex,'-1');
for(let i=0;i<200;i++){clock+=100;api.Refresh(group);}
assert.equal(layer.Children().length,4,'effects must reuse panels');
assert(layer.Children().every(p=>p.hittest===false && p.hittestchildren===false));
custom.style.visibility='visible';api.Refresh(group);
const customLayer=custom.FindChildTraverse('SurvivalPortraitMotes');assert(customLayer);assert.equal(customLayer.GetParent(),custom);assert.notEqual(layer,customLayer);assert.equal(layer.style.visibility,'collapse');assert.equal(customLayer.style.visibility,'visible');
multi=true;api.Refresh(group);assert.equal(customLayer.style.visibility,'collapse');multi=false;
customLayer.Children()[0].removed=true;api.Refresh(group);api.Refresh(group);assert.notEqual(customLayer,custom.FindChildTraverse('SurvivalPortraitMotes'),'stale engine panels are rebuilt');
layer.removed=true;custom.style.visibility='collapse';api.Refresh(group);assert.equal(container.FindChildTraverse('SurvivalPortraitMotes').GetParent(),container,'nested effect must never stand in for native layer');
selected=-1;api.Refresh(group);assert.equal(container.FindChildTraverse('SurvivalPortraitMotes').style.visibility,'collapse');
selected=8;names[8]='npc_dota_hero_rubick';assert.equal(api.InspectBackdrop().color,'#285b27','stale model metadata must not recolor new selection');
const own=new Panel('SurvivalLocalHeroPortrait',root,'Button');
const ownImage=new Panel('SurvivalLocalHeroPortraitImage',own,'DOTAScenePanel');
let followClicks=0;cfg.SurvivalHeroSelection={CanSelect:()=>true,Select:source=>{assert.equal(source,'top_left_portrait');followClicks++;}};
context.Game={GetLocalPlayerID:()=>0};
states={player_0:{hero_ready:1,hero_id:'configured_hero',unit_entindex:30},player_3:{hero_ready:1,hero_id:'configured_hero',unit_entindex:40}};
api.RefreshLocalHeroPortrait(root);assert.equal(own.__survivalActiveHeroScene.attributes.map,'portraits/doom_soft_a');assert.equal(own.style.visibility,'visible');
selected=40;api.RefreshLocalHeroPortrait(root);assert.equal(own.__survivalActiveHeroScene.__survivalSceneKey,'hero:30:npc_dota_hero_doom_bringer','selecting another unit must not change local hero');
states.player_0.hero_ready=0;api.RefreshLocalHeroPortrait(root);assert.equal(own.style.visibility,'collapse','no hero means no placeholder at the corner');
states.player_0={hero_ready:1,hero_id:'configured_hero',unit_entindex:999};api.RefreshLocalHeroPortrait(root);assert.equal(own.style.visibility,'collapse','invalid entity cannot leave a stale visible portrait');
names[40]='npc_dota_hero_axe';assigned=40;states.player_0={hero_ready:1,hero_id:'configured_hero',unit_entindex:40};api.RefreshLocalHeroPortrait(root);assert.equal(ownImage.unit,'npc_dota_hero_axe');assert.equal(ownImage.camera,'default');assert.equal(own.style.visibility,'visible','summon/replacement refreshes portrait');
const layout=fs.readFileSync('panorama/src/layout/custom_game/survival_hud.xml','utf8');
assert(!layout.includes('SurvivalReturnCastleAsset'),'unused castle dependency must not leak at the origin');
assert(layout.includes('id="SurvivalLocalHeroPortrait"'));
console.log('PORTRAIT_ALL_UNITS_PASS: runtime model colors, particle reuse/ownership/recovery, corner hero summon/remove/replace and selection isolation');

// The shortcut follows the real local entity and keeps native face cameras.
assigned=30;
for(const [hero,summon] of [['axe','axe'],['doom_bringer','doom'],['nevermore','shadow_fiend'],['drow_ranger','drow_ranger'],['monkey_king','monkey_king'],['juggernaut','blademaster']]) {
 names[30]='npc_dota_hero_'+hero;states.player_0={hero_ready:1,hero_id:'configured_hero',unit_entindex:30};api.RefreshLocalHeroPortrait(root);
 const active=own.__survivalActiveHeroScene;assert.equal(active.__survivalHeroIcon,hero);
 if(hero==='doom_bringer'){assert.equal(active.__survivalSceneMap,'portraits/doom_soft_a');assert.equal(active.__survivalSceneCamera,'shortcut_camera');}
 else{assert.equal(active,ownImage);assert.equal(active.unit,'npc_dota_hero_'+hero);assert.equal(active.camera,'default');}
 assert.equal(own.enabled,true);own.events.onactivate();
}
assert.equal(followClicks,6);
cfg.SurvivalHeroSelection.CanSelect=()=>false;api.RefreshLocalHeroPortrait(root);assert.equal(own.enabled,false);
assert(layout.includes('<Button id="SurvivalLocalHeroPortrait" visible="false" hittest="false"'));
console.log('HERO_CORNER_BUTTON_PASS: six native hero scenes with isolated Doom camera, clickable selection/single-jump route, unavailable state and live hero replacement');
