'use strict';
// Native combat death path. The failed first helper remains in ignored output.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const {connect}=require('../map_c6/console-session.cjs');
const arg=(name,fallback)=>{const i=process.argv.indexOf(name);return i<0?fallback:process.argv[i+1];};
const tag=arg('--tag',''),mode=arg('--mode','standard');
if(!/^[a-z0-9_-]{1,40}$/.test(tag)||!['standard','pure','rich','cold'].includes(mode))throw Error('explicit_safe_tag_and_mode_required');
const file=path.resolve('output/ui_qa_20261025/native_review/final_wave_'+tag+'.json');
if(fs.existsSync(file))throw Error('settlement_report_exists');
const report={tag,mode,started:new Date().toISOString(),helper_sha256:crypto.createHash('sha256').update(fs.readFileSync(__filename)).digest('hex'),scope:'offline_tools_early_final_plus_Kill_nil_valid_allied_attacker_not_full_defense',font_status:'not_asserted_by_settlement_helper_see_archive_timeline',samples:[],ok:false};
const helperSnapshot=path.join(path.dirname(file),'native_settlement_source_'+tag+'.cjs');
if(fs.existsSync(helperSnapshot))throw Error('settlement_source_snapshot_exists');
fs.copyFileSync(__filename,helperSnapshot);report.helper_source_snapshot=path.basename(helperSnapshot);
let session;const sleep=ms=>new Promise(r=>setTimeout(r,ms));
const guard="assert(GameRules and IsServer() and IsInToolsMode(),'offline_tools_required');assert(require('debug/offline_logic_test').is_enabled() and require('core/release_policy').development_allowed(),'offline_development_required');assert(require('systems/startup_loading_service').is_gameplay_ready(),'gameplay_required');assert(require('systems/match_setup_service').get_mode()=='"+mode+"','expected_mode_required');";
const snapshot="local s=b.request(e.WAVE_STATE_GET_REQUEST,{player_id=0});d.wave={current_wave=s.current_wave,total_waves=s.total_waves,status=s.status,alive=s.alive,victory_settled=s.victory_settled,defeat_settled=s.defeat_settled,player_defeated=s.player_defeated,early_final_remaining=s.early_final_remaining,early_final_used=s.early_final_used,post_clear_frozen=s.post_clear_frozen};d.resources=b.request(e.RESOURCE_GET_REQUEST,{player_id=0});local p=require('systems/player_profile_service').get_profile(0);d.profile_revision=p and p.revision;d.clear_counts=p and p.save and p.save.archive and p.save.archive.clear_counts;d.real_money_allowed=require('core/commerce_release_policy').real_money_allowed();d.engine_state=GameRules:State_Get();local q=GameRules.__ui_qa_final_kill_stats or {};d.kills=q.kills or 0;d.kill_errors=q.errors or 0";
async function run(body){const prefix='[UI_QA_FINAL_KILL_'+Date.now()+'] ';const code=guard+`local b=require('core/event_bus');local e=require('core/events');local d={};${body};print('${prefix}'..require('core/json_encoder').encode(d))`;const r=await session.send([{name:'dota_run_lua',arguments:{code}}],'',150,{responsePrefix:prefix});return JSON.parse(r.matched_line.slice(prefix.length));}
async function main(){
 try{
  session=await connect({port:29006,timeoutMs:8000,retainOutput:false});
  report.before=await run(snapshot+";local a=PlayerResource:GetSelectedHeroEntity(0);assert(a and not a:IsNull() and a:IsAlive() and a:GetTeamNumber()==DOTA_TEAM_GOODGUYS and a:GetPlayerOwnerID()==0,'valid_allied_attacker_required');d.attacker={unit_name=a:GetUnitName(),team=a:GetTeamNumber(),player_id=a:GetPlayerOwnerID(),alive=a:IsAlive()}");
  if(report.before.wave.victory_settled||report.before.wave.player_defeated)throw Error('not_ready_for_existing_early_final_request');
  if(report.before.wave.early_final_remaining>0){
   // Advance the actual engine clock; never backdate or alter the business timer.
   report.accelerated_cooldown_samples=[];
   await session.send([{name:'console_send',arguments:{commands:'host_timescale 10'}}],'',100);
   const until=Date.now()+12000;let waiting=report.before;
   while(waiting.wave.early_final_remaining>0&&Date.now()<until){await sleep(500);waiting=await run(snapshot);report.accelerated_cooldown_samples.push(waiting);}
   if(waiting.wave.early_final_remaining>0)throw Error('existing_early_final_cooldown_not_elapsed');
  }
  report.request=await run("local attacker=PlayerResource:GetSelectedHeroEntity(0);assert(attacker and not attacker:IsNull() and attacker:IsAlive() and attacker:GetTeamNumber()==DOTA_TEAM_GOODGUYS and attacker:GetPlayerOwnerID()==0,'valid_allied_attacker_required');require('systems/wave_system').set_dev_mode(false);d.result=b.request(e.WAVE_EARLY_FINAL_REQUEST,{player_id=0});if d.result and d.result.ok then local ticks=0;local q={kills=0,errors=0};GameRules.__ui_qa_final_kill_stats=q;require('core/scheduler').every(0.2,function() ticks=ticks+1;if not IsInToolsMode() or not require('debug/offline_logic_test').is_enabled() or not require('core/release_policy').development_allowed() then return false end;if not attacker or attacker:IsNull() or not attacker:IsAlive() or attacker:GetTeamNumber()~=DOTA_TEAM_GOODGUYS or attacker:GetPlayerOwnerID()~=0 then q.errors=q.errors+1;return false end;local s=b.request(e.WAVE_STATE_GET_REQUEST,{player_id=0});if s.victory_settled or s.defeat_settled or ticks>1200 then return false end;local units=FindUnitsInRadius(DOTA_TEAM_GOODGUYS,Vector(0,0,0),nil,FIND_UNITS_EVERYWHERE,DOTA_UNIT_TARGET_TEAM_ENEMY,DOTA_UNIT_TARGET_ALL,DOTA_UNIT_TARGET_FLAG_INVULNERABLE,FIND_ANY_ORDER,false);for _,u in ipairs(units)do if u and not u:IsNull() and u:IsAlive() and u.survival_is_wave_monster==true and u.survival_player_id==0 then local ok=pcall(u.Kill,u,nil,attacker);if not ok then q.errors=q.errors+1;return false end;if not u:IsAlive()then q.kills=q.kills+1 end end end;return true end,'ui_qa_offline_final_kill')end");
  if(!report.request.result?.ok)throw Error('early_final_request_rejected');
  await session.send([{name:'console_send',arguments:{commands:'host_timescale 10'}}],'',100);
  const end=Date.now()+35000;
  while(Date.now()<end){await sleep(750);const s=await run(snapshot);report.samples.push(s);if(s.kill_errors)throw Error('native_kill_failed');if(s.wave.victory_settled){report.ok=true;break;}if(s.wave.defeat_settled||s.wave.player_defeated)throw Error('accelerated_wave_defeated');}
  if(!report.ok)throw Error('accelerated_final_timeout');
 }catch(e){report.error=String(e.message);}finally{if(session){try{await session.send([{name:'console_send',arguments:{commands:'host_timescale 1'}}],'',100);report.timescale_restore_command_sent=true;}catch{report.timescale_restore_command_sent=false;}try{await run("d.cancelled=require('core/scheduler').cancel('ui_qa_offline_final_kill')");report.timer_cancel_attempted=true;}catch{report.timer_cancel_attempted=false;}await session.close();}report.finished=new Date().toISOString();fs.writeFileSync(file,JSON.stringify(report,null,2));console.log(JSON.stringify({ok:report.ok,error:report.error,report:file,final:report.samples.at(-1)}));if(!report.ok)process.exitCode=1;}
}
main();
