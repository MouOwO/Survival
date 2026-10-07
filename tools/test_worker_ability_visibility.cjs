const fs=require('fs'),vm=require('vm'),assert=require('assert');
const source=fs.readFileSync('panorama/src/scripts/custom_game/combat_stats.js','utf8');
const start=source.indexOf('    function visibleAbilityEntries(unit) {');
const code=source.slice(start,source.indexOf('    function refreshInventory()',start));
let name='',abilities=[];
const env={Entities:{GetUnitName:()=>name},Abilities:{GetAbilityName:i=>abilities[i].name,IsHidden:i=>!!abilities[i].hidden},
 unitAbilityCount:()=>abilities.length,abilityIndexForSlot:(u,i)=>i,orderVisibleAbilities:entries=>entries};
vm.createContext(env);vm.runInContext(code,env);
function visible(unit,list){name=unit;abilities=list.map(name=>({name}));return Array.from(env.visibleAbilityEntries(1),e=>e.name);}
assert.deepEqual(visible('npc_survival_repairer',['passive_repair','ability_repairer_suicide']),['ability_repairer_suicide']);
assert.deepEqual(visible('npc_survival_lumberjack',['ability_fuse_lumberjack_04','lumberjack_personality_leader']),['ability_fuse_lumberjack_04']);
assert.deepEqual(visible('npc_survival_super_lumberjack_04',['lumberjack_personality_leader']),[]);
assert.deepEqual(visible('npc_survival_lumberjack',['lumberjack_personality_leader']),[],'fused workers can retain ordinary entity names');
assert.deepEqual(visible('npc_dota_hero_doom_bringer',['doom_bringer_devour','doom_bringer_doom']),['doom_bringer_devour','doom_bringer_doom']);
assert.deepEqual(visible('building_main_city',['ability_train_repairer','ability_train_advanced_repairer']),['ability_train_repairer','ability_train_advanced_repairer']);
console.log('PASS worker skill visibility: self-destruct, fusion, super passives hidden, hero and building restoration');
