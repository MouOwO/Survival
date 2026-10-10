const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
// Completing the middle technology must not hide a later unfinished action.
for(const name of ['topnav_remaining_5d5c1152eb.js','handoff_hud.js']) {
 const source=fs.readFileSync('panorama/src/scripts/custom_game/'+name,'utf8');
 const start=source.indexOf('    function fitNativeSkills('),end=source.indexOf('    function canvas(',start);
 const all=[{ability:100,name:'research_a'},{ability:101,name:'research_b'},{ability:102,name:'research_c'}];
 const native=all.map((_,i)=>({id:'Ability'+i,style:{},visible:true,FindChildTraverse(){return null;}}));
 const list={GetChildCount:()=>native.length,GetChild:i=>native[i]};
 let completed=101;
 const cfg={HandoffCombat:{NativeEntries:()=>all,IsCompleted:index=>index===completed,
  ApplyRuntime:(panel,index)=>{panel.style.opacity=index===completed?'0':'1';panel.hittest=index!==completed;panel.hittestchildren=index!==completed;}}};
 const context={cfg,selectedUnit:()=>10,currentEntries:[all[0],all[2]],geometry:{scale:1},ctx:{actualuiscale_x:1,actualuiscale_y:1},
  native:()=>list,valid:node=>!!node,style:(node,properties)=>Object.assign(node.style,properties),square:panel=>{panel.style.width='116px';},skillPanels:[]};
 vm.runInNewContext(source.slice(start,end),context);
 context.fitNativeSkills({scale:1});
 assert.deepEqual(Array.from(context.skillPanels,p=>p.id),['Ability0','Ability2'],name+': completed middle row must not remove the later unfinished native action');
 assert.equal(native[1].style.width,'0px');assert.equal(native[1].style.opacity,'0');assert.equal(native[1].hittestchildren,false);
 assert.notEqual(native[1].style.visibility,'collapse','native identities stay available to tooltip/hotkey binding');
 assert.notEqual(native[2].style.visibility,'collapse');
 completed=-1;context.currentEntries=all;context.fitNativeSkills({scale:1});
 assert.deepEqual(Array.from(context.skillPanels,p=>p.id),['Ability0','Ability1','Ability2']);
 assert.equal(native[1].style.width,'116px');assert.equal(native[1].style.opacity,'1');assert.equal(native[1].hittestchildren,true);
}
// Native children may report zero geometry after their parent loses its width.
// Both the hotkey and tooltip collectors must pair only the surviving actions,
// so no transparent completed proxy can intercept the next button.
const combat=fs.readFileSync('panorama/src/scripts/custom_game/combat_stats.js','utf8');
const tooltip=fs.readFileSync('panorama/src/scripts/custom_game/ability_tooltip.js','utf8');
const entries=[100,101,102].map((ability,i)=>({ability,abilityIndex:ability,name:'ability_research_'+i,abilityName:'ability_research_'+i,slot:i,engineSlot:i}));
let completed=101;
const runtime=ability=>({completed:ability===completed?1:0});
const native=entries.map((entry,i)=>{
 const anchor={style:{},actuallayoutwidth:116,actuallayoutheight:116,GetPositionWithinWindow:()=>({x:i===0?0:116,y:0})};
 return {id:'Ability'+i,style:{},visible:true,FindChildTraverse:()=>anchor,anchor};
});
const list={FindChildTraverse:id=>native.find(p=>p.id===id)};
const cc={Entities:{GetUnitName:()=> 'building_advanced_research_lab',GetAbility:(unit,slot)=>entries[slot].ability},
 Abilities:{GetAbilityName:ability=>entries.find(e=>e.ability===ability).name,IsHidden:()=>false},
 abilityIndexForSlot:(unit,slot)=>entries[slot].ability,unitAbilityCount:()=>entries.length,
 orderVisibleAbilities:values=>values,abilityRuntime:runtime,maxAbilityEngineSlots:32,
 belongsToLegacyHud:()=>false,abilityPanelStyleValue:(panel,key)=>panel.style[key]||'',
 windowPosition:anchor=>anchor.GetPositionWithinWindow(),officialPanel:()=>list};
let start=combat.indexOf('    function nativeAbilityEntries('),end=combat.indexOf('    function refreshInventory()',start);
vm.runInNewContext(combat.slice(start,end),cc);
start=combat.indexOf('    function officialAbilityButtonAnchor(');end=combat.indexOf('    function officialAbilityMappingSignature(',start);
vm.runInNewContext(combat.slice(start,end),cc);
const tc={bindingSnapshot:null,selectedUnit:()=>10,enumerateAbilitySlots:()=>entries,
 externalAbilityRuntime:runtime,bindingPerformance:{panelScans:0},maxAbilityEngineSlots:32,
 officialAbilityAnchor:panel=>panel.anchor,panelStyle:(panel,key)=>panel.style[key]||'',
 visualWindowSize:(anchor,axis)=>axis==='width'?anchor.actuallayoutwidth:anchor.actuallayoutheight};
start=tooltip.indexOf('    function visibleAbilityEntries()');end=tooltip.indexOf('    function unitOwnsAbility(',start);
vm.runInNewContext(tooltip.slice(start,end),tc);
start=tooltip.indexOf('    function collectOfficialAbilityPanels(');end=tooltip.indexOf('    function extendResearchAbilityPanels(',start);
vm.runInNewContext(tooltip.slice(start,end),tc);
for(const hidden of [101,-1,100,102]) {
 completed=hidden;
 native.forEach((panel,i)=>{panel.__survivalCompleted=entries[i].ability===hidden;panel.anchor.actuallayoutwidth=panel.__survivalCompleted?0:116;});
 const expected=entries.filter(e=>e.ability!==hidden);
 assert.deepEqual(Array.from(cc.nativeAbilityEntries(10),e=>e.ability),[100,101,102],'native identities remain complete');
 const visible=cc.visibleAbilityEntries(10),mappings=cc.resolveOfficialAbilityMappings(visible);
 assert(mappings,'zero-sized completed native children must not invalidate surviving hotkeys');
 assert.deepEqual(Array.from(mappings,m=>[m.entry.ability,m.panel.id]),expected.map(e=>[e.ability,'Ability'+e.slot]));
 assert.deepEqual(Array.from(tc.visibleAbilityEntries(),e=>e.abilityIndex),expected.map(e=>e.ability),'completed action owns no external tooltip binding');
 assert.deepEqual(Array.from(tc.collectOfficialAbilityPanels(list),e=>e.panel.id),expected.map(e=>'Ability'+e.slot));
}
console.log('PASS research HUD completion: later actions, zero-sized native children, hotkeys and no completed tooltip hit area');
