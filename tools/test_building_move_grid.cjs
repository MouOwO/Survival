const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const keys = {}, mouse = {}, sent = [], calls = [];
let selected=10, moving=false, cancelled=0;
const shared = {
    SurvivalSelectionResolver:{Resolve:()=>selected},
    SurvivalInputDispatcher:{RegisterMouseHandler:(id,fn)=>mouse[id]=fn,
        RegisterKeyHandler:(id,fn)=>keys[id]=fn},
    SurvivalGridPlacement:{BeginRelocation(ability,unit) {
        calls.push({ability,unit});moving=true;return true;
    },CancelRelocation(){moving=false;cancelled++;},IsRelocating:()=>moving}
};
const scheduled=[];
const $=()=>null;
$.Schedule=(_,fn)=>scheduled.push(fn);$.Msg=()=>{};
vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/building_move.js','utf8'),{
    $,GameUI:{CustomUIConfig:()=>shared},
    Entities:{GetUnitName:()=> 'building_arrow_tower',GetAbility:(_,slot)=>slot<2 ? 20+slot : -1},
    Abilities:{GetAbilityName:id=>id===20 ? 'ability_building_blink' : 'ability_destroy_arrow_tower',
        IsHidden:()=>false},
    GameEvents:{Subscribe:()=>{},SendCustomGameEventToServer:(name,data)=>sent.push({name,data})}
});
assert(keys.building_move('D',true));
assert(keys.building_move('d',true));
assert.equal(calls.length,2,'each D delegates to fresh grid preview; never toggle off');
assert.equal(cancelled,0);
assert.equal(mouse.building_move('pressed',0),false,'grid controller owns placement click');
assert.equal(sent.length,0,'adapter never sends raw movement coordinates');
assert(shared.SurvivalArrowTowerTools.TriggerAbility('ability_building_blink',10));
assert.equal(calls.length,3,'ability button and D use same grid entry');
selected=11;scheduled[0]();
assert.equal(cancelled,1,'selection change retires the placement session');
console.log('BUILDING_MOVE_GRID_PASS D repeats, button parity, no raw coordinates, selection cancellation');
