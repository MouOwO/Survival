const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const {setup}=require('./test_combat_stats_callbacks.cjs');
let behavior=2,enginePassive=false;
const t=setup({portrait:true,abilities:{GetBehavior:id=>id===101?behavior:4,IsPassive:id=>id===101&&enginePassive,
 GetAbilityName:id=>id===103?'ability_building_blink':'mock_spell'},entities:{GetAbility:(_,slot)=>slot===0?103:-1}});
const abilities=new t.Panel('abilities',t.root),native=new t.Panel('Ability0',abilities);
const anchor=new t.Panel('AbilityButton',native),icon=new t.Panel('AbilityImage',anchor),hotkey=new t.Panel('HotkeyContainer',native);
icon.values.saturation='0.8';icon.values.brightness='0.7';hotkey.values.opacity='0.35';
const entries=[{ability:100,name:'mock_active',slot:0},{ability:101,name:'mock_passive',slot:1},{ability:102,name:'mock_active_two',slot:2}];
function ordered(){return t.api.orderVisibleAbilities(entries.map(e=>({...e})))}
let order=ordered();assert.equal(t.api.hotkeyForAbilityEntry(order[0],''),'Q');
assert.equal(t.api.hotkeyForAbilityEntry(order[1],''),'');assert.equal(t.api.hotkeyForAbilityEntry(order[2],''),'W');
let mirrors={};t.cfg.HandoffStyleHotkey=(label,slot)=>mirrors[slot.id]=label.text;
// Use the real loaded HUD's clearing hook, including its cache deletion.
for(const file of ['topnav_remaining_5d5c1152eb.js','handoff_hud.js']){
 const source=fs.readFileSync('panorama/src/scripts/custom_game/'+file,'utf8');
 const hook=source.match(/    cfg\.HandoffClearHotkey=function\(slot\)\{[^\n]+/)[0];
 vm.runInNewContext(hook,{cfg:t.cfg,keyBindings:mirrors});
 const active={...order[0]},passive={...order[1]};
 const mapping=entry=>[{entry,panel:native,anchor,nodeIndex:0}];
 assert(t.api.refreshOfficialUtilityHotkeys([active],mapping(active)));
 assert.equal(mirrors.Ability0,'Q');assert.equal(hotkey.values.opacity,'0');
 assert(t.api.refreshOfficialUtilityHotkeys([passive],mapping(passive)));
 assert.equal(native.FindChildTraverse('SurvivalAbilityHotkey').values.visibility,'collapse');
 assert.equal(hotkey.values.opacity,'0','native passive key must stay hidden');
 assert.equal(mirrors.Ability0,undefined,'floating key cache must not survive panel reuse');
 assert(t.api.officialAbilityHotkeysMatch(mapping(passive)),'passive suppression must be a stable cached state');
 // Engine behavior can temporarily be unavailable. Server metadata still wins.
 behavior=0;t.runtime['101']={passive:1};
 assert.equal(t.api.hotkeyForAbilityEntry(passive,''),'');
 assert(t.api.officialAbilityHotkeysMatch(mapping(passive)));
 delete t.runtime['101'];enginePassive=true;assert.equal(t.api.hotkeyForAbilityEntry(passive,''),'');
 enginePassive=false;assert.equal(t.api.officialAbilityHotkeysMatch(mapping(passive)),false);
 assert(t.api.refreshOfficialUtilityHotkeys([passive],mapping(passive)));
 assert.equal(hotkey.values.opacity,'0.35','active keyless reuse restores the original native style');
 behavior=2;
}
t.runtime['100']={available:0,status_text:'前置不足'};t.api.applyAbilityRuntime(native,100);
assert.equal(native.classes.DOTADisabled,true);assert.equal(icon.values.saturation,'0');assert.equal(icon.values.brightness,'0.45');
assert.equal(native.hittest,true,'disabled icons retain tooltip hit testing');
t.runtime['100']={available:1};t.api.applyAbilityRuntime(native,100);
assert.equal(native.classes.DOTADisabled,false);assert.equal(icon.values.saturation,'0.8');assert.equal(icon.values.brightness,'0.7');
t.runtime['100']={available:0};t.api.applyAbilityRuntime(native,100);t.api.restoreAbilityRuntime(native);
assert.equal(icon.values.saturation,'0.8','unmanaged/native slot reuse cannot retain a grey icon');
let calls=0;t.cfg.SurvivalArrowTowerTools={TriggerAbility:()=>{calls++;return true}};
t.runtime['103']={available:0,ability_name:'ability_building_blink',owner_entindex:7};
assert.equal(t.api.executeAbility(103),false);assert.equal(calls,0,'special dispatch cannot bypass availability');
t.runtime['103'].available=1;t.runtime['103'].passive=1;
assert.equal(t.api.executeAbility(103),false);assert.equal(calls,0,'server passive metadata must block dispatch');
t.runtime['103'].passive=0;assert.equal(t.api.executeAbility(103),true);assert.equal(calls,1);
console.log('ABILITY_BUTTON_STATES_PASS: native/custom/mirrored passive keys, active slot numbering, slot reuse, grey restoration, tooltip access and special dispatch gates');
