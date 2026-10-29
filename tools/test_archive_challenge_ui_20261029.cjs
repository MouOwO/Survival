'use strict';
// Executes the production classification, slot painting and native layout paths.
// Sparse rows must preserve actual button identity, hover and cooldown overlays.
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
name='npc_archive_challenge_4';
// Runtime slots deliberately differ from compact native enumeration indices.
const slots=[1,2,3,5,6,7,8,9,10,12];
env.currentEntries=slots.map((slot,i)=>{const entry={ability:100+i,name:'ability_archive_test_'+i,slot:i};runtime[entry.ability]={ability_entindex:entry.ability,owner_entindex:selected,slot_order:slot};return entry;});
const g={width:500,height:438,x:300,y:600,scale:.5,portraitSize:264,heroWidth:0,centerWidth:500,inventoryX:500,minimapSize:220,actionOffset:10,archiveChallenge:true};
assert(env.nativeLayout(g));
assert.equal(list.style.flowChildren,'none');assert.equal(list.style.height,'356px');assert.equal(branch.style.height,'356px');
slots.forEach((slot,i)=>{
 const p=buttons[i];assert.equal(p.__handoffArchiveSlot,slot-1);
 assert.equal(p.style.position,`${((slot-1)%4)*120}px ${Math.floor((slot-1)/4)*120}px 0px`);
 assert(p.hittest&&p.hittestchildren,'locked/used buttons retain native hover');
 assert.equal(p.FindChildTraverse('CooldownOverlay').style.clip,'engine_live');
 assert.equal(p.__survivalWindowWidth,58);assert.equal(p.GetParent(),list);
});
assert.equal(buttons[10].style.visibility,'collapse');assert.equal(buttons[11].style.visibility,'collapse');
assert(env.repairNativeLayout(g));assert.equal(list.style.flowChildren,'none');assert.equal(list.style.height,'356px');
// A stale entity snapshot cannot reposition a current ability.
runtime[100].owner_entindex=88;env.fitNativeSkills(g);assert.equal(buttons[0].__handoffArchiveSlot,0);
runtime[100]={ability_entindex:100,owner_entindex:selected,slot_order:12};env.fitNativeSkills(g);assert.equal(buttons[0].__handoffArchiveSlot,11);
// Returning to any normal building restores its original one-row native layout.
assert(env.nativeLayout({...g,archiveChallenge:false,height:205,centerWidth:1218}));
assert.equal(list.style.flowChildren,'right');assert.equal(list.style.height,'116px');
for(const p of buttons.slice(0,slots.length)){assert.equal(p.__handoffArchiveSlot,undefined);assert.equal(p.style.position,'0px 0px 0px');assert.equal(p.style.marginRight,'4px');}

// Execute the real grid geometry branch at common widths/UI scales.
const geometry=require('../panorama/src/scripts/custom_game/geometry_remaining_5d5c1152eb.js');
const start=source.indexOf('        var count=presentation.tree?0:abilityCount(readContext),g=cfg.HandoffGeometry(');
const end=source.indexOf('        var signature=',start);assert(start>=0&&end>start);
for(const [w,h] of [[800,600],[1280,720],[1920,1080],[2560,1440],[3440,1440]]){
 const grid={w,h,presentation:{building:true,archive_challenge:true},abilityCount:()=>10,readContext:null,cfg:{HandoffGeometry:geometry}};
 vm.runInNewContext(source.slice(start,end)+';this.result=g;',grid);const actual=grid.result;
 assert.equal(actual.centerWidth,500);assert.equal(actual.height,438);assert.equal(actual.count,12);
 assert(actual.scale>0&&Number.isFinite(actual.scale));assert(actual.x>=0&&actual.y>=0);assert(actual.x+actual.width*actual.scale<=w);assert(actual.y+actual.height*actual.scale<=h);
}
console.log('ARCHIVE_CHALLENGE_UI_PASS: four hubs, sparse 4x3 native slots, hover/cooldown identity, runtime ownership, repair, normal-layout recovery and five viewports');
