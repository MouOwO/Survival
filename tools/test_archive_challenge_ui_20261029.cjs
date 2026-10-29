'use strict';
// Executes the production classification, slot painting and native layout paths.
// Compact rows must preserve actual button identity, hover and cooldown overlays.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const source=fs.readFileSync('panorama/src/scripts/custom_game/topnav_remaining_5d5c1152eb.js','utf8');
function between(first,last){const a=source.indexOf(first),b=source.indexOf(last,a+first.length);assert(a>=0&&b>a,first);return source.slice(a,b);}
class Panel{
 constructor(id,parent){this.id=id;this.parent=parent||null;this.children=[];this.style={};this.visible=true;this.hittest=true;this.hittestchildren=true;if(parent)parent.children.push(this);}
 IsValid(){return true;}GetParent(){return this.parent;}GetChildCount(){return this.children.length;}GetChild(i){return this.children[i];}
 FindChildTraverse(id){return this.children.find(p=>p.id===id)||this.children.map(p=>p.FindChildTraverse(id)).find(Boolean)||null;}
 BHasClass(){return false;}SetParent(parent){if(this.parent)this.parent.children=this.parent.children.filter(p=>p!==this);this.parent=parent;parent.children.push(this);}
}
const nodes={},root=new Panel('root'),ctx=new Panel('ctx',root),runtime={};
function native(id,parent=root){return nodes[id]=new Panel(id,parent);}
const lower=native('lower_hud'),outer=native('center_with_stats',lower),block=native('center_block',outer);
const portrait=native('PortraitGroup',block);native('PortraitContainer',portrait);native('portraitHUD',portrait);
const branch=native('AbilitiesAndStatBranch',block),list=native('abilities',branch),inventory=native('inventory',block);
for(const id of ['minimap','inventory_composition_layer_container','buffs','debuffs'])native(id);
const buttons=Array.from({length:12},(_,i)=>{const p=new Panel('Ability'+i,list);new Panel('AbilityButton',p);new Panel('ButtonWell',p);new Panel('CooldownOverlay',p).style.clip='engine_live';return p;});
let name='npc_archive_challenge_4',selected=7;
const env={root,ctx,cfg:{},nodes:{},natives:nodes,geometry:null,currentEntries:[],skillPanels:[],layoutNativeWrappers:[],
 selectedUnit:()=>selected,valid:p=>!!p,style:(p,props)=>{if(p)Object.assign(p.style,props);},
 findCached:(p,id)=>p&&p.FindChildTraverse(id),
 place:(p,x,y,w,h,overrides)=>{if(p)Object.assign(p.style,{position:`${x}px ${y}px 0px`,width:`${w}px`,height:`${h}px`},overrides||{});},
 square:p=>{p.style.width='116px';p.style.height='116px';},native:id=>nodes[id]||null,background:new Panel('background',ctx),
 layoutMinimap(){},layoutPanels:[],missing:[],ctx,cssNumber:String,
 canvas(p,g){env.place(p,g.x,g.y,g.width,g.height);},child(p,id,props){env.style(p&&p.FindChildTraverse(id),props);},
 Entities:{GetUnitName:()=>name,IsBuilding:()=>false,IsHero:()=>false,GetTeamNumber:()=>2},
 CustomNetTables:{GetTableValue:(_,key)=>runtime[key]||{}},$: {GetContextPanel:()=>ctx}};
ctx.actualuiscale_x=ctx.actualuiscale_y=1;
env.cfg.HandoffCombat={NativeEntries:()=>env.currentEntries,ApplyRuntime:(panel)=>{panel.hittest=true;panel.hittestchildren=true;},IsCompleted:()=>false};
vm.createContext(env);
vm.runInContext(between('    function actionOffset(','    function canvas(')
 +between('    function nativeAbilityWrappers(','    function findCached(')
 +between('    function nativeLayout(','    // Resolve navigation')
 +between('    function statVisibility(','    function buildingPresentation('),env);
for(let i=1;i<=4;i++){name='npc_archive_challenge_'+i;const p=env.statVisibility(selected);assert(p.building);assert(p.archive_challenge);assert(!p.combat&&!p.attributes);}
for(const other of ['npc_archive_challenge_5','npc_archive_challenge_14','npc_survival_named_rebirth_boss_01']){name=other;assert(!env.statVisibility(selected).archive_challenge);}
const bootstrap=fs.readFileSync('panorama/src/scripts/custom_game/ui_bootstrap.js','utf8');
const filter={valid:()=>true,Entities:{GetUnitName:()=>name,IsBuilding:()=>false}};
vm.runInNewContext(bootstrap.slice(bootstrap.indexOf('    function fixedTarget('),bootstrap.indexOf('    function cancel(){')),filter);
for(let i=1;i<=4;i++){name='npc_archive_challenge_'+i;assert(filter.fixedTarget(selected),'fourth hub also stays out of army box selection');}
name='npc_archive_challenge_5';assert(!filter.fixedTarget(selected));
let g;
for(const [building,count] of [[1,11],[2,10],[3,9],[4,9]]){
 name='npc_archive_challenge_'+building;
 env.currentEntries=Array.from({length:count},(_,i)=>{const entry={ability:100+i,name:'ability_archive_test_'+i,slot:i};runtime[entry.ability]={ability_entindex:entry.ability,owner_entindex:selected,slot_order:i+1};return entry;});
 // A hot-reloaded old grid must be cleared before the first compact paint.
 for(let i=0;i<count;i++){buttons[i].__handoffArchiveSlot=i;buttons[i].style.position='120px 240px 0px';}
 g={width:count*120+20,height:205,x:300,y:600,scale:.5,portraitSize:264,heroWidth:0,centerWidth:count*120+20,inventoryX:count*120+20,minimapSize:220,actionOffset:10,archiveChallenge:true};
 assert(env.nativeLayout(g));
 assert.equal(list.style.flowChildren,'right');assert.equal(list.style.height,'116px');assert.equal(branch.style.height,'116px');
 for(let i=0;i<count;i++){
  const p=buttons[i];assert.equal(p.__handoffArchiveSlot,undefined);assert.equal(p.style.position,'0px 0px 0px');assert.equal(p.style.marginRight,'4px');
  assert(p.hittest&&p.hittestchildren,'locked/used buttons retain native hover');
  assert.equal(p.FindChildTraverse('CooldownOverlay').style.clip,'engine_live');
  assert.equal(p.__survivalWindowWidth,58);assert.equal(p.GetParent(),list);assert.notEqual(p.style.visibility,'collapse');
 }
 for(let i=count;i<buttons.length;i++)assert.equal(buttons[i].style.visibility,'collapse','unused native placeholders cannot occupy space');
 assert(env.repairNativeLayout(g));assert.equal(list.style.flowChildren,'right');assert.equal(list.style.height,'116px');
 // Runtime updates cannot turn compact engine identity back into grid coordinates.
 runtime[100]={ability_entindex:100,owner_entindex:88,slot_order:12};env.fitNativeSkills(g);assert.equal(buttons[0].style.position,'0px 0px 0px');
}
// Returning to any normal building restores its original one-row native layout.
assert(env.nativeLayout({...g,archiveChallenge:false,height:205,centerWidth:1218}));
assert.equal(list.style.flowChildren,'right');assert.equal(list.style.height,'116px');
for(const p of buttons.slice(0,9)){assert.equal(p.__handoffArchiveSlot,undefined);assert.equal(p.style.position,'0px 0px 0px');assert.equal(p.style.marginRight,'4px');}

// Execute the real compact geometry branch at common widths/UI scales.
const geometry=require('../panorama/src/scripts/custom_game/geometry_remaining_5d5c1152eb.js');
const start=source.indexOf('        var count=presentation.tree?0:abilityCount(readContext),g=cfg.HandoffGeometry(');
const end=source.indexOf('        var signature=',start);assert(start>=0&&end>start);
for(const count of [11,10,9,9])for(const [w,h] of [[800,600],[1280,720],[1920,1080],[2560,1440],[3440,1440]]){
 const grid={w,h,presentation:{building:true,archive_challenge:true},abilityCount:()=>count,readContext:null,cfg:{HandoffGeometry:geometry}};
 vm.runInNewContext(source.slice(start,end)+';this.result=g;',grid);const actual=grid.result;
 assert.equal(actual.centerWidth,count*120+20);assert.equal(actual.height,205);assert.equal(actual.count,count);
 assert(actual.scale>0&&Number.isFinite(actual.scale));assert(actual.x>=0&&actual.y>=0);assert(actual.x+actual.width*actual.scale<=w);assert(actual.y+actual.height*actual.scale<=h);
}
assert(!source.includes('Subscribe("survival_archive_return"'),'retired archive return event has no UI listener');
console.log('ARCHIVE_CHALLENGE_UI_PASS: four compact rows 11/10/9/9, no holes/returns, hover/cooldown identity, repair, normal-layout recovery and five viewports');
