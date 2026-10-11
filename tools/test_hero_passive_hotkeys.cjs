'use strict';
// Exercise the real HUD against Monkey King's four configured skills, including
// stale engine behavior during selection and reuse of an old active Q slot.
const fs=require('node:fs');
const assert=require('node:assert/strict');
const {csv}=require('./shop_ui_12h/catalog.cjs');
const {setup}=require('./test_combat_stats_callbacks.cjs');
const skills=csv('data/csv/英雄系统/hero_skill_definitions.csv')
    .filter(row=>row.exclusive_hero_id==='hero_monkey_king'&&row.enabled==='1');
assert.equal(skills.length,4);
assert(skills.every(row=>row.skill_type==='passive'));
const fourth=skills.find(row=>row.skill_id==='skill_monkey_king_agility');
assert(fourth);
const ids=skills.map((_,i)=>100+i),names=new Map(skills.map((row,i)=>[ids[i],row.ability_name]));
let nativePassive=false;
const requests=[],mirrors=new Map();
const t=setup({portrait:true,
    config:{HandoffClearHotkey:slot=>mirrors.delete(slot.id),
        HandoffStyleHotkey:(label,slot)=>mirrors.set(slot.id,label.text)},
    entities:{GetAbility:(unit,slot)=>unit===7?(ids[slot]??-1):-1},
    abilities:{GetAbilityName:id=>names.get(id)||'',IsHidden:()=>false,GetLevel:()=>1,
        GetBehavior:()=>nativePassive?2:4,IsPassive:()=>nativePassive},
    events:{SendCustomGameEventToServer:(name,payload)=>requests.push({name,payload})}});
t.select(7,'npc_dota_hero_monkey_king');
t.runtime['unit:7']={owner_entindex:7,ability_count:4};
const abilities=new t.Panel('abilities',t.root);
const panels=ids.map((id,i)=>{
    const panel=new t.Panel('Ability'+i,abilities);
    const button=new t.Panel('AbilityButton',panel);
    button.point={x:100+i*140,y:900};
    new t.Panel('AbilityImage',button);
    new t.Panel('HotkeyContainer',panel).values.opacity='1';
    return panel;
});

// Seed Q as if the fourth native slot was previously displaying an active.
const priorQ=new t.Panel('SurvivalAbilityHotkey',panels[3].FindChildTraverse('AbilityButton'));
priorQ.text='Q';priorQ.style.visibility='visible';mirrors.set(panels[3].id,'Q');
for(const id of ids)t.runtime[id]={ability_entindex:id,owner_entindex:7,passive:1,available:1};

function noKeys(){
    for(const panel of panels){
        const label=panel.FindChildTraverse('SurvivalAbilityHotkey');
        assert(!label||label.text===''||label.style.visibility==='collapse');
        assert.equal(panel.FindChildTraverse('HotkeyContainer').style.opacity,'0');
        assert(!mirrors.has(panel.id),'independent HUD key mirror must not revive a passive key');
    }
}
t.api.refreshHotkeys(false);noKeys();
for(const id of ids)assert.equal(t.api.executeAbility(id),false,'server passive signal rejects manual casts');
assert.equal(requests.length,0,'passive actions cannot reach the server');

// Once the KV behavior arrives, all four stay keyless even without metadata.
nativePassive=true;
for(const id of ids)delete t.runtime[id];
t.api.refreshAbilities();noKeys();
for(const id of ids)assert.equal(t.api.executeAbility(id),false,'native passive signal rejects manual casts');
assert.equal(requests.length,0);

// A genuinely active ability reusing the same native panel keeps its shortcut.
nativePassive=false;
names.set(ids[0],'mock_active');
t.runtime[ids[0]]={ability_entindex:ids[0],owner_entindex:7,passive:0};
for(const id of ids.slice(1))t.runtime[id]={ability_entindex:id,owner_entindex:7,passive:1};
t.api.refreshHotkeys(false);
assert.equal(panels[0].FindChildTraverse('SurvivalAbilityHotkey').text,'Q');
assert.equal(mirrors.get(panels[0].id),'Q');
assert(!mirrors.has(panels[3].id));
console.log('HERO_PASSIVE_HOTKEYS_PASS: all four Monkey King skills, stale native Q, runtime/native passive signals, mirrors, input rejection and active slot reuse');
