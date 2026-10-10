const fs=require('fs'),vm=require('vm'),assert=require('assert/strict');
const boot=fs.readFileSync('panorama/src/scripts/custom_game/ui_bootstrap.js','utf8');
const guard=boot.slice(boot.indexOf('// BEGIN hero summon initial availability'),boot.indexOf('// END hero summon initial availability'));
for(const [file,start,end,fn] of [
 ['hud_takeover.js','    function runtimeFor(','    function unitAbilityCount(', 'runtimeFor'],
 ['combat_stats.js','    function abilityRuntime(','    function applyAbilityRuntime(', 'abilityRuntime'],
 ['ability_tooltip.js','    function readTooltipTable(','    function cancelChecks(', 'readTooltipTable']]){
 let name='ability_summon_monkey_king',row;
 const cfg={},env={config:cfg,GameUI:{CustomUIConfig:()=>cfg},Game:{GetLocalPlayerID:()=>0},Abilities:{GetAbilityName:()=>name},CustomNetTables:{GetTableValue:()=>row},bindingSnapshot:null,selectedUnit:()=>10};
 vm.createContext(env);vm.runInContext(guard,env);
 const source=fs.readFileSync('panorama/src/scripts/custom_game/'+file,'utf8');
 vm.runInContext(source.slice(source.indexOf(start),source.indexOf(end,source.indexOf(start))),env);
 const get=()=>fn==='readTooltipTable'?env[fn]('survival_ability_runtime','7'):env[fn](7);
 for(name of ['ability_summon_monkey_king','ability_summon_blademaster']){
  row=undefined;assert.equal(get().available,0,'first frame locked');
  row={available:1};assert.equal(get().available,0,'legacy generic allowed row is not permission');assert.equal(row.available,1,'no mutation of network cache');
  row={hero_summon:1,summon_player_id:1,available:1};assert.equal(get().available,0,'another player grant cannot unlock');
  row={hero_summon:1,summon_player_id:0,available:1};assert.equal(get().available,1,'confirmed own grant enables');
  row={hero_summon:1,summon_player_id:0,available:0,status_text:'需购买激活'};assert.equal(get().available,0,'denial/revocation remains locked');assert.equal(get().status_text,'需购买激活');
 }
 name='ability_summon_doom';row={available:1};assert.equal(get().available,1,'free hero unaffected');
 console.log('HERO_INITIAL_AVAILABILITY_PASS '+file);
}
