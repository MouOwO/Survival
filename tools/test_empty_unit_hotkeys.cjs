// Real production hotkey writer; only native entities/Panorama are mocked.
const assert=require('node:assert/strict');
const {setup}=require('./test_combat_stats_callbacks.cjs');
const slots=new Map([[7,[100,101,102]],[8,[]]]),names=new Map([[100,'mock_q'],[101,'mock_w'],[102,'mock_e']]);
const mirrors=new Map();let clears=0;
const t=setup({portrait:true,entities:{GetAbility:(unit,slot)=>(slots.get(unit)||[])[slot]??-1},
 abilities:{GetAbilityName:id=>names.get(id)||'',IsHidden:()=>false,GetBehavior:()=>4,IsPassive:()=>false},
 config:{HandoffClearHotkey:panel=>{clears++;mirrors.delete(panel.id);},
         HandoffStyleHotkey:(label,panel,unit,ability)=>mirrors.set(panel.id,{text:label.text,unit,ability})}});
const root=new t.Panel('abilities',t.root),panels=[];
function mount(slot){
 const panel=new t.Panel('Ability'+slot,root),button=new t.Panel('AbilityButton',panel);
 button.point={x:slot*140,y:900};new t.Panel('AbilityImage',button);
 const key=new t.Panel('HotkeyContainer',panel);key.values.opacity='1';
 new t.Panel('HotkeyText',key).text=['Q','W','E'][slot]||'R';panels[slot]=panel;return panel;
}
for(let slot=0;slot<3;slot++)mount(slot);
const key=slot=>panels[slot].FindChildTraverse('HotkeyContainer');
const own=slot=>panels[slot].FindChildTraverse('SurvivalAbilityHotkey');
function noKeys(){
 for(const panel of panels){
  assert.equal(panel.FindChildTraverse('HotkeyContainer').style.opacity,'0','empty native slot stays suppressed');
  const label=panel.FindChildTraverse('SurvivalAbilityHotkey');
  assert(!label||!label.text||label.style.visibility==='collapse','no stale custom key');
  assert(!mirrors.has(panel.id),'no independent mirror binding for empty slot');
 }
}
t.api.refreshHotkeys(false);assert.deepEqual([0,1,2].map(i=>own(i).text),['Q','W','E']);
// The screenshot's ten-turn boss has no Ability1..N in the actual native KV.
// Keep the existing visible native panels, as Valve can do across selection.
t.select(8,'npc_survival_named_rebirth_boss_10');t.api.refreshHotkeys(false);noKeys();
const stable=clears;
for(let tick=0;tick<64;tick++)t.api.refreshHotkeys(false);
assert.equal(clears,stable,'steady empty selection does not repeatedly clear/rebind');
// Native UI rewrites and same-ID replacement are repaired by the existing
// recovery tick rather than needing another selection or an added timer.
key(0).values.opacity='1';t.api.refreshHotkeys(false);noKeys();
const old=panels[1];old.alive=false;old.children.forEach(p=>p.alive=false);
root.children=root.children.filter(p=>p!==old);mount(1);t.api.refreshHotkeys(false);noKeys();
// Becoming a one-skill unit must keep the trailing empty W/E slots keyless.
slots.set(8,[100]);panels[1].style.visibility='collapse';panels[2].style.visibility='collapse';
t.api.refreshHotkeys(false);assert.equal(own(0).text,'Q');
for(const slot of [1,2])assert.equal(key(slot).style.opacity,'0');
key(2).values.opacity='1';t.api.refreshHotkeys(false);assert.equal(key(2).style.opacity,'0');
// Genuine hero abilities and native input ownership recover on reuse.
t.select(7,'npc_dota_hero_test');panels[1].style.visibility='visible';panels[2].style.visibility='visible';
t.api.refreshHotkeys(false);assert.deepEqual([0,1,2].map(i=>own(i).text),['Q','W','E']);
assert.equal(mirrors.size,3);assert(t.api.officialAbilityHotkeysMatch([
 {entry:{ability:100,name:'mock_q',standardHotkeyIndex:0},panel:panels[0],anchor:panels[0].FindChildTraverse('AbilityButton')},
 {entry:{ability:101,name:'mock_w',standardHotkeyIndex:1},panel:panels[1],anchor:panels[1].FindChildTraverse('AbilityButton')},
 {entry:{ability:102,name:'mock_e',standardHotkeyIndex:2},panel:panels[2],anchor:panels[2].FindChildTraverse('AbilityButton')}]));
t.api.shutdown('done');for(const slot of [0,1,2])assert.equal(key(slot).style.opacity,'1','shutdown restores original native ownership');
console.log('EMPTY_UNIT_HOTKEYS_PASS: hero→ten-turn zero-skill unit, visible stale native slots, native rewrites/rebuild, trailing empty slots, stable cache, real hero reuse and shutdown');
