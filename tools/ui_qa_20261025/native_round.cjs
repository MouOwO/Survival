'use strict';
// Cold-launch accelerated OFFLINE key-chain. Screens remain pending visual review.
const fs=require('node:fs'),path=require('node:path'),cp=require('node:child_process');
const arg=(n,d)=>{const i=process.argv.indexOf(n);return i<0?d:process.argv[i+1];},round=Number(arg('--round','1')),mode=arg('--mode','standard'),tag=arg('--tag','cold');
const archiveTimeline=process.argv.includes('--archive-timeline');
if(!Number.isInteger(round)||round<1||round>5||!['standard','pure','rich','cold'].includes(mode)||!/^[a-z0-9_]{1,20}$/.test(tag))throw Error('invalid_round_options');
const out=path.resolve('output/ui_qa_20261025/native_review'),report={round,mode,tag,started:new Date().toISOString(),scope:'native_offline_key_chain_not_full_wave_clear',states:[],captures:[],visual_review:'pending',procedural_ok:false};fs.mkdirSync(out,{recursive:true});
const target=path.join(out,'round_'+round+'_'+tag+'.json');if(fs.existsSync(target))throw Error('round_report_exists');
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
function save(){fs.writeFileSync(target,JSON.stringify(report,null,2));}
function command(exe,args,timeout=30000){const r=cp.spawnSync(exe,args,{cwd:path.resolve(__dirname,'../..'),encoding:'utf8',windowsHide:true,timeout,maxBuffer:1024*1024});if(r.status!==0)throw Error('native_command_failed:'+String(r.error?.message||r.stderr||r.stdout).slice(-700));return r.stdout;}
function probe(action){const r=JSON.parse(command(process.execPath,['tools/ui_qa_20261025/native_review.cjs','--round',String(round),'--action',action],20000));report.states.push(r);save();return r.observed;}
function capture(name,options={}){const args=['-NoProfile','-NonInteractive','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-File','tools/ui_qa_20261025/native_capture.ps1','-GameProcessId',String(report.pid),'-Round',String(round),'-Name',tag+'_'+name];for(const [k,v]of Object.entries(options))if(v===true)args.push('-'+k);else args.push('-'+k,String(v));const r=JSON.parse(command('powershell.exe',args,15000));report.captures.push(r);save();return r;}
function need(x,message){if(!x)throw Error(message);}
async function until(predicate,label){const start=Date.now();while(Date.now()-start<100000){try{const s=probe('status');if(s.rules&&s.offline&&s.allowed&&predicate(s))return s;}catch(e){report.last_wait_error=String(e.message);save();}await sleep(1000);}throw Error('actual_gate_timeout:'+label);}
async function main(){
 try{
  report.launch=JSON.parse(command(path.resolve('output/ecs_backend_work/.venv/Scripts/python.exe'),['tools/workshop_test/test_entry.py','offline'],20000));need(report.launch.ok,'offline_launch_failed');report.pid=report.launch.pid;save();
  await until(s=>s.native&&s.state===2,'native_team_setup');capture('native_ready');probe('hold');capture('start',{ClickX:1418,ClickY:862});
  await until(s=>s.admission&&!s.native&&!s.mode,'admitted_mode_selection');capture('mode_ready');
  capture('mode_'+mode,{ClickX:800,ClickY:{standard:405,rich:449,cold:495,pure:539}[mode]});
  const loaded=await until(s=>s.mode===mode&&s.loaded&&s.difficulty_ready,'loaded_mode_profile');report.initialProfile=loaded.profile;report.initialResources=loaded.resources;
  need(loaded.resources.wood===10&&loaded.resources.gold===0,'fresh_offline_resources_not_reset');need(loaded.profile.revision===1,'fresh_offline_revision_not_reset');
  probe('hold');capture('difficulty_n1',{ClickX:800,ClickY:309});probe('hold');
  const added=probe('resources');need(added.add?.ok&&added.before.wood===10&&added.before.gold===0&&added.after.wood===12355&&added.after.gold===678&&added.after.max_population===50,'resource_delta_failed');capture('resources');
  await sleep(1500);
  for(const [name,x]of [['archive',156],['treasure',100],['lottery',211],['daily',268],['commerce',323],['collection',377]]){
   if(name==='archive'&&archiveTimeline){
    report.archive_timeline=JSON.parse(command('powershell.exe',['-NoProfile','-NonInteractive','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-File','tools/ui_qa_20261025/native_archive_timeline.ps1','-GameProcessId',String(report.pid),'-Round',String(round),'-Tag',tag+'_r'+round],20000));
    save();capture('archive_observed_10s');
   }else capture(name,{ClickX:x,ClickY:44,Delay:1200});
   capture(name+'_escape',{Escape:true});
  }
  capture('archive_reopen',{ClickX:156,ClickY:44});capture('archive_reopen_escape',{Escape:true});capture('vip_passive',{ClickX:528,ClickY:44});
  report.final=probe('status');need(report.final.rules&&report.final.offline&&report.final.allowed&&report.final.wave_hold&&report.final.loaded&&report.final.mode===mode&&!report.final.defeated&&!report.final.phase_frozen,'final_offline_gate_failed');
  report.procedural_ok=true;
 }catch(e){report.error=String(e.message);}finally{report.finished=new Date().toISOString();save();console.log(JSON.stringify({round,mode,pid:report.pid,procedural_ok:report.procedural_ok,visual_review:report.visual_review,error:report.error||null,captures:report.captures.length,report:target}));if(!report.procedural_ok)process.exitCode=1;}
}
main();
