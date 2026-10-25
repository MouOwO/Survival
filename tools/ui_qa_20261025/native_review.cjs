'use strict';
// Explicit offline Tools control. No cloud API, save file or payment fixture.
const fs=require('node:fs'),path=require('node:path');
const {connect}=require('../map_c6/console-session.cjs');
const arg=(n,d)=>{const i=process.argv.indexOf(n);return i<0?d:process.argv[i+1];};
const action=arg('--action','status'),round=Number(arg('--round','1'));
if(!['status','hold','resources','unlock','command'].includes(action)||!Number.isInteger(round)||round<1||round>5)throw Error('invalid_native_review_action');
const out=path.resolve('output/ui_qa_20261025/native_review');fs.mkdirSync(out,{recursive:true});
const prefix='[UI_QA_REVIEW_'+round+'_'+Date.now()+'] ';
let session;
async function main(){
 session=await connect({port:29006,timeoutMs:8000,retainOutput:false});
 try{
  if(action==='command'){const command=arg('--command','');if(!command||/[\r\n\0]/.test(command))throw Error('invalid_console_command');const r=await session.send([{name:'console_send',arguments:{commands:command}}],'',500);fs.writeFileSync(path.join(out,'r'+round+'_command_'+Date.now()+'.txt'),r.output);console.log(r.output.slice(-20000));return;}
  const code=`local d={rules=GameRules~=nil,server=IsServer(),tools=IsInToolsMode()}
if GameRules and IsServer() then
d.state=GameRules:State_Get()
local m=package.loaded['systems/match_setup_service'];d.core_initialized=type(m)=='table' and type(m.get_session_id)=='function' and m.get_session_id()~=''
if d.core_initialized then
local s=require('systems/startup_loading_service')
d.offline=require('debug/offline_logic_test').is_enabled();d.allowed=require('core/release_policy').development_allowed()
d.native=s.is_native_team_setup();d.admission=s.is_ready();d.gameplay=s.is_gameplay_ready();d.difficulty_ready=s.is_difficulty_selection_ready(0);d.mode=m.get_mode();d.state=GameRules:State_Get();d.session=m.get_session_id();d.post_game=DOTA_GAMERULES_STATE_POST_GAME
local p=require('systems/player_profile_service').get_profile(0);d.loaded=p~=nil;if p then local count=0;for _,v in pairs(p.save and p.save.content_inventory or {}) do if tonumber(v) and tonumber(v)>0 then count=count+1 end end;d.profile={revision=p.revision,mode=p.mode,game_mode=p.game_mode,nonzero_inventory_entries=count} end
d.real_money_allowed=require('core/commerce_release_policy').real_money_allowed()
local w=require('systems/wave_system');d.wave_hold=w.is_dev_mode()
d.defeated=require('systems/multiplayer_player_service').is_defeated(0);d.phase_frozen=require('systems/gameplay_phase_guard').post_clear_frozen()
if d.offline and d.allowed then
if '${action}'=='hold' then d.hold_result=w.set_dev_mode(true);d.wave_hold=w.is_dev_mode();d.wall_deadline_cancelled=require('core/scheduler').cancel('player_unbuilt_wall_defeat');d.wall_deadline_test_scope='offline_tools_menu_review_only' end
if '${action}'=='unlock' then d.unlock_result=require('debug/mode_unlock_test').enable(0) end
local b=require('core/event_bus');local e=require('core/events');d.resources=b.request(e.RESOURCE_GET_REQUEST,{player_id=0})
if '${action}'=='resources' and d.loaded and d.gameplay and d.state~=DOTA_GAMERULES_STATE_POST_GAME then
d.before=d.resources;if not GameRules.__ui_qa_review_added then d.add=b.request(e.RESOURCE_ADD_REQUEST,{player_id=0,wood=12345,gold=678,max_population=50,reason='offline_ui_qa_review_only'});if d.add and d.add.ok then GameRules.__ui_qa_review_added=true end end
d.after=b.request(e.RESOURCE_GET_REQUEST,{player_id=0});d.resource_added=GameRules.__ui_qa_review_added==true
end
end
end
end
print('${prefix}'..require('core/json_encoder').encode(d))`;
  const r=await session.send([{name:'dota_run_lua',arguments:{code}}],'',150,{responsePrefix:prefix});
  const observed=JSON.parse(r.matched_line.slice(prefix.length)),record={round,action,at:new Date().toISOString(),scope:'native_offline_Tools_actual_state_not_full_wave_clear',observed};
  const file=path.join(out,'r'+round+'_'+action+'_'+Date.now()+'.json');fs.writeFileSync(file,JSON.stringify(record,null,2));console.log(JSON.stringify(record));
 }finally{await session.close();}
}
main().catch(e=>{console.error(JSON.stringify({ok:false,error:String(e.message)}));process.exitCode=1;});
