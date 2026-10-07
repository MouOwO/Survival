const fs=require('fs'),vm=require('vm'),assert=require('assert');
const source=fs.readFileSync('panorama/src/scripts/custom_game/combat_stats.js','utf8');
const start=source.indexOf('    function toggleTowerAutoUpgrade(');
const end=source.indexOf('    GameUI.CustomUIConfig().SurvivalAbilityInput =',start);
let selected=10,name='ability_upgrade_tower_lv01',runtime={auto_upgrade_visible:1,auto_upgrade_available:1},sent=[];
const env={abilityRuntime:()=>runtime,Abilities:{GetAbilityName:()=>name},casterForAbility:()=>10,
 selectedUnit:()=>selected,GameEvents:{SendCustomGameEventToServer:(event,payload)=>sent.push({event,payload})}};
vm.createContext(env);vm.runInContext(source.slice(start,end),env);
assert(env.toggleTowerAutoUpgrade(100));
assert.equal(sent[0].event,'ui_tower_auto_upgrade_toggle_request');
assert.equal(sent[0].payload.entindex,10);
runtime={auto_upgrade_visible:1,available:0,upgrade_in_progress:1,auto_upgrade_enabled:1};
assert(env.toggleTowerAutoUpgrade(100),'cancel remains possible during an upgrade');
name='ability_upgrade_tower_max';assert(!env.toggleTowerAutoUpgrade(100));
name='ability_upgrade_tower_lv01';selected=11;assert(!env.toggleTowerAutoUpgrade(100));
selected=10;runtime={removed:1};assert(!env.toggleTowerAutoUpgrade(100));
for(const file of ['ability_tooltip.js','hud_takeover.js']) {
 const src=fs.readFileSync('panorama/src/scripts/custom_game/'+file,'utf8');
 const begin=src.indexOf('SetPanelEvent("oncontextmenu", function () {');
 const body=src.slice(begin+'SetPanelEvent("oncontextmenu", function () {'.length,src.indexOf('        });',begin));
 let count=0;
 const cfg={SurvivalAbilityInput:{ToggleTowerAutoUpgrade:a=>{assert.equal(a,100);count++;return true;}}};
 const proxy={__survivalAbilityIndex:100,__survivalAbilityName:'ability_upgrade_tower_lv01'};
 const scope={proxy,slot:{entry:{ability:100,name:'ability_upgrade_tower_lv01'}},config:cfg,GameUI:{CustomUIConfig:()=>cfg}};
 assert(!vm.runInNewContext('(function(){'+body+'})()',scope));
 assert.equal(count,0,file+' right-click never toggles tower automation');
}
runtime={auto_upgrade_visible:0,auto_upgrade_available:0};assert(!env.toggleTowerAutoUpgrade(100));
console.log('TOWER_AUTO_INPUT_PASS: right-click removed; explicit toggle, cancel while busy; base/stale/removed rejected');
