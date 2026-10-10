const fs=require('fs'),vm=require('vm'),assert=require('assert');
const source=fs.readFileSync('panorama/src/scripts/custom_game/combat_stats.js','utf8');
const start=source.indexOf('    function nativeAbilityEntries(unit) {');
const code=source.slice(start,source.indexOf('    function refreshInventory()',start));
let name='',abilities=[];
const env={Entities:{GetUnitName:()=>name,GetAbility:(unit,slot)=>slot},Abilities:{GetAbilityName:i=>abilities[i].name,IsHidden:i=>!!abilities[i].hidden},
 unitAbilityCount:()=>abilities.length,orderVisibleAbilities:entries=>entries,abilityRuntime:()=>({})};
vm.createContext(env);vm.runInContext(code,env);
function visible(unit,list){name=unit;abilities=list.map(value=>typeof value==='string'?{name:value}:value);return Array.from(env.visibleAbilityEntries(1),e=>e.name);}
assert.deepEqual(visible('npc_survival_repairer',['passive_repair','ability_repairer_suicide']),['ability_repairer_suicide']);
const personalities=fs.readFileSync('data/csv/建筑与工人系统/lumberjack_personality_definitions.csv','utf8')
 .split(/\r?\n/).filter(line=>line.startsWith('lumberjack_personality_')).map(line=>line.split(',')[1]);
assert.equal(personalities.length,11,'exercise the configured personality pool');
assert.deepEqual(visible('npc_survival_lumberjack',['ability_fuse_lumberjack_04','internal_worker_ai']),['ability_fuse_lumberjack_04']);
for(let level=1;level<=7;level++)for(const passive of personalities){
 assert.deepEqual(visible('npc_survival_super_lumberjack_'+String(level).padStart(2,'0'),[passive]),[passive]);
 assert.deepEqual(visible('npc_survival_lumberjack',[passive]),[passive],'in-place fusion retains the ordinary entity name');
}
assert.deepEqual(visible('npc_survival_super_lumberjack_08',[]),[],'LV8 has no configured personality');
assert.deepEqual(visible('npc_survival_lumberjack',[
 {name:'ability_fuse_lumberjack_01',hidden:true},
 {name:personalities[0],hidden:true},
 {name:personalities[1]},
 {name:'special_bonus_attack_speed_20'},
 {name:'internal_worker_ai'}]),[personalities[1]],'hidden, talent and internal abilities remain excluded');
assert.deepEqual(visible('npc_survival_lumberjack',['ability_fuse_lumberjack_04',personalities[0]]),['ability_fuse_lumberjack_04',personalities[0]],'native slot order remains intact');
assert.deepEqual(visible('npc_dota_hero_doom_bringer',['doom_bringer_devour','doom_bringer_doom']),['doom_bringer_devour','doom_bringer_doom']);
assert.deepEqual(visible('building_main_city',['ability_train_repairer','ability_train_advanced_repairer']),['ability_train_repairer','ability_train_advanced_repairer']);
console.log('PASS worker skill visibility: 11 configured passives across 7 fused tiers, in-place names, hidden/internal filtering, slot order, repairer, hero and building compatibility');
