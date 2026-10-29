'use strict';
// Run the production native mapping, runtime paint and both keyboard handlers.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const {setup}=require('./test_combat_stats_callbacks.cjs');
const combat=fs.readFileSync('panorama/src/scripts/custom_game/combat_stats.js','utf8');
const bootstrap=fs.readFileSync('panorama/src/scripts/custom_game/ui_bootstrap.js','utf8');
function fixture(archive){
 const ids=[100,101,102,103],names=ids.map((_,i)=>'ability_archive_shadow_'+(i+1));
 const hud=setup({entities:{GetAbility:(_,slot)=>ids[slot]??-1},abilities:{
  GetAbilityName:id=>names[ids.indexOf(id)]||'',IsHidden:()=>false,IsPassive:()=>false,GetBehavior:()=>4,
 }});
 hud.select(7,archive?'npc_archive_challenge_1':'npc_dota_hero_test');
 hud.runtime['unit:7']={owner_entindex:7,ability_count:ids.length};
 const official=new hud.Panel('abilities',hud.root),buttons=[];let writes=0;
 ids.forEach((id,i)=>{
  const panel=new hud.Panel('Ability'+i,official),anchor=new hud.Panel('AbilityButton',panel),image=new hud.Panel('AbilityImage',anchor);
  // Engine can retain a previous grid for one frame while native layout settles.
  anchor.point={x:(i%2)*120,y:Math.floor(i/2)*120};
  const hotkey=new hud.Panel('HotkeyContainer',panel);hotkey.values.opacity='0.35';
  for(const target of [image,hotkey])target.style=new Proxy(target.style,{set:(o,k,v)=>{writes++;o[k]=v;return true;}});
  hud.runtime[id]={ability_entindex:id,ability_name:names[i],owner_entindex:7,
   available:i===1?0:1,prerequisite_met:i===1?0:1,can_afford:1,status_text:i===1?'本局已挑战':'可以挑战'};
  buttons.push({id,panel,anchor,image,hotkey});
 });
 const paint=()=>buttons.forEach(b=>hud.api.applyAbilityRuntime(b.panel,b.id));
 return {hud,buttons,paint,reset:()=>{writes=0;},writes:()=>writes};
}

// Reproduce the real x-then-y painter disagreement: engine slot 1 and 2 swap.
const legacy=fixture(false);legacy.paint();legacy.hud.api.refreshHotkeys(true);
assert.equal(Number(legacy.buttons[1].image.style.brightness),1,'screen sorting repaints the locked second slot with the third ability');
assert.equal(Number(legacy.buttons[2].image.style.brightness),.45,'screen sorting repaints the ready third slot with the second ability');

const live=fixture(true);live.paint();live.hud.api.refreshHotkeys(true);
live.reset();
for(let frame=0;frame<40;frame++){
 live.paint();live.hud.api.refreshHotkeys(false);
 live.buttons.forEach((b,i)=>{
  assert.equal(Number(b.image.style.brightness),i===1?.45:1,'each native slot keeps its own challenge state');
  assert.equal(Number(b.hotkey.style.opacity),0);assert.equal(b.panel.hittest,true,'used challenges still expose hover/tooltip');
  assert(!b.panel.FindChildTraverse('SurvivalAbilityHotkey'),'archive hubs do not create key labels');
 });
}
assert.equal(live.writes(),0,'stable bindings neither repaint colors nor restore/hide hotkeys');
// An incomplete native rebuild keeps the last stable paint until identity returns.
live.buttons[2].anchor.alive=false;live.reset();live.hud.api.refreshHotkeys(false);assert.equal(live.writes(),0);
live.buttons[2].anchor.alive=true;live.hud.api.refreshHotkeys(false);assert.equal(live.writes(),0);
// Reusing the same native buttons for a regular hero restores normal Q/W/E/R.
live.hud.select(7,'npc_dota_hero_test');
live.buttons.forEach((b,i)=>{b.anchor.point={x:i*120,y:0};});
live.hud.api.refreshHotkeys(false);
live.buttons.forEach((b,i)=>assert.equal(b.panel.FindChildTraverse('SurvivalAbilityHotkey').text,'QWER'[i]));

const first=bootstrap.indexOf('    // Consume skill keys before both our caster');
const last=bootstrap.indexOf('    // BEGIN shared box-selection filter',first);assert(first>=0&&last>first);
let name='npc_archive_challenge_4',blocked=false,handler,priority;
const input={keyHandlers:{},keyHandlerOrder:[],inputConfig:{SurvivalSelectionResolver:{ResolveDisplayUnit:()=>7}},
 shortcutsBlocked:()=>blocked,validUnit:id=>id===7,Entities:{GetUnitName:()=>name},
 registerHandler:(handlers,order,id,fn,p)=>{assert.equal(id,'archive_mouse_only');handler=fn;priority=p;}};
vm.runInNewContext(bootstrap.slice(first,last),input);assert(priority>130,'archive skill guard runs before commerce D');
for(const key of 'QWERTYUSDFGH')for(const down of [true,false])assert.equal(handler(key,down),true,key+' stays mouse only');
for(const key of ['SPACE','F1','F2','A','TAB','ESCAPE'])assert.equal(handler(key,true),false,key+' keeps its normal handler');
blocked=true;assert.equal(handler('Q',true),false,'chat/modal owns input before skill guard');blocked=false;
for(const normal of ['npc_dota_hero_test','building_main_city','npc_archive_challenge_5']){
 name=normal;for(const key of 'QWERTYUSDFGH')assert.equal(handler(key,true),false,'ordinary unit hotkeys remain available');
}

// Exercise the real lower-priority caster callback too, including fallback callers.
let abilityHandler,casts=0;name='npc_archive_challenge_1';
const caster={GameUI:{CustomUIConfig:()=>({SurvivalInputDispatcher:{RegisterKeyHandler:(id,fn)=>{assert.equal(id,'ability_input');abilityHandler=fn;}}})},
 $:{Msg(){},Warning(){}},selectedUnit:()=>7,Entities:{GetUnitName:()=>name},utilityAbilityForKey:{},
 isSelectedCombatHero:()=>false,researchDisplaySlotForKey:()=>-1,builderDisplaySlotForKey:()=>-1,
 castDisplaySlot:()=>{casts++;return true;}};
const a=combat.indexOf('    function bindHotkeys()'),b=combat.indexOf('    function bindHeroPortrait()',a);assert(a>=0&&b>a);
vm.runInNewContext(combat.slice(a,b)+';bindHotkeys();',caster);
for(const key of 'QWERTYUSDFGH')assert.equal(abilityHandler(key,true),true);
assert.equal(casts,0,'archive fallback keyboard path never submits a cast');
name='npc_dota_hero_test';assert.equal(abilityHandler('Q',true),true);assert.equal(casts,1,'hero Q still casts');
console.log('ARCHIVE_COMPACT_INPUT_PASS: screen-order conflict reproduced, native identity stable for 40 paints with zero writes, hover preserved, labels hidden, both keyboard guards and ordinary hero restoration');
