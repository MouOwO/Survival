'use strict';
// Private Tools fixture: no research upgrades, account writes or resource changes.
const fs=require('node:fs'),path=require('node:path'),cp=require('node:child_process');
const root=path.resolve(__dirname,'..'),out=path.join(root,'output/late_combat_20261008/research_ui');
fs.mkdirSync(out,{recursive:true});
const action=process.argv[2]||'advanced';
if(!['advanced','basic','stop'].includes(action))throw Error('Use advanced, basic or stop');
const cleanup=`local previous=SURVIVAL_RESEARCH_UI_FIXTURE;if previous then for _,unit in ipairs(previous) do if unit and not unit:IsNull() then unit:ForceKill(false);UTIL_Remove(unit) end end;SURVIVAL_RESEARCH_UI_FIXTURE=nil end;PlayerResource:SetCameraTarget(0,nil);`;
const code=`assert(IsServer() and IsInToolsMode() and GetMapName()=='template_map');${cleanup}
${action==='stop'?'':`
assert(GameRules:State_Get()==DOTA_GAMERULES_STATE_GAME_IN_PROGRESS);
local bus,events=require('core/event_bus'),require('core/events');
local id='${action==='advanced'?'building_advanced_research_lab':'building_research_lab'}';
local definition=require('config/buildings_config')[id];
local unit=CreateUnitByName(definition.unit_name,GetGroundPosition(Vector(-2500,2700,0),nil),false,nil,nil,DOTA_TEAM_GOODGUYS);
SURVIVAL_RESEARCH_UI_FIXTURE={unit};unit.survival_is_building=true;unit.survival_player_id=0;unit.survival_level=1;unit.survival_population_occupied=0;
unit:SetControllableByPlayer(0,true);unit:SetMaxHealth(2500);unit:SetHealth(2500);
local state=assert(bus.request(events.BUILDING_QUERY_REQUEST,{entindex=unit:entindex()}));
bus.emit(events.BUILDING_CREATED,state);
PlayerResource:SetCameraTarget(0,unit);
CustomGameEventManager:Send_ServerToPlayer(PlayerResource:GetPlayer(0),'survival_select_unit',{entindex=unit:entindex(),reason='tools_research_ui_validation'});
local runtimes=CustomNetTables:GetTableValue('survival_ability_runtime',tostring(unit:entindex())) or {};
print('[RESEARCH_UI_FIXTURE] building='..id..' entindex='..unit:entindex()..' abilities='..unit:GetAbilityCount());
for slot=0,unit:GetAbilityCount()-1 do local a=unit:GetAbilityByIndex(slot);if a then print('[RESEARCH_UI_NATIVE] name='..a:GetAbilityName()..' activated='..tostring(a:IsActivated())) end end;
`}
print('RESEARCH_UI_FIXTURE_READY');`;
const file=path.join(out,action+'.json');fs.writeFileSync(file,JSON.stringify([{name:'dota_run_lua',arguments:{code}}]));
const r=cp.spawnSync(process.execPath,[path.join(__dirname,'map_c6/console.cjs'),'--file',file,'--timeout-ms','5000','--expect','RESEARCH_UI_FIXTURE_READY'],{cwd:root,encoding:'utf8',windowsHide:true,maxBuffer:2e6});
fs.writeFileSync(path.join(out,action+'.txt'),r.stdout||'');
console.log((r.stdout||'').split(/\r?\n/).filter(x=>/RESEARCH_UI_/.test(x)).join('\n'));
if(r.status!==0)throw Error('Private research fixture failed: '+r.stderr);
