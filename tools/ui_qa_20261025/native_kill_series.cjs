'use strict';
// Four fresh offline native modes, each with a continuous first-open archive.
const fs=require('node:fs'),path=require('node:path'),cp=require('node:child_process');
const {connect}=require('../map_c6/console-session.cjs');
const i=process.argv.indexOf('--tag'),tag=i<0?'':process.argv[i+1];
const fromIndex=process.argv.indexOf('--from'),from=fromIndex<0?2:Number(process.argv[fromIndex+1]);
if(!/^[a-z0-9_]{1,20}$/.test(tag))throw Error('explicit_new_safe_tag_required');
if(!Number.isInteger(from)||from<2||from>5)throw Error('safe_from_round_required');
const out=path.resolve('output/ui_qa_20261025/native_review'),file=path.join(out,'kill_series_'+tag+'.json');
if(fs.existsSync(file))throw Error('series_report_exists');
const report={tag,started:new Date().toISOString(),scope:'four_offline_accelerated_native_Kill_settlements_not_full_wave_clears',rounds:[],ok:false};
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
function save(){fs.writeFileSync(file,JSON.stringify(report,null,2));}
function execute(exe,args,timeout=30000){const r=cp.spawnSync(exe,args,{encoding:'utf8',windowsHide:true,timeout,maxBuffer:2*1024*1024});if(r.status!==0)throw Error('native_series_command_failed:'+String(r.error?.message||r.stderr||r.stdout).slice(-700));return r.stdout;}
function stopCheck(){if(fs.existsSync(path.join(out,'STOP_SERIES')))throw Error('series_explicitly_stopped');}
async function quitOwned(pid){
 stopCheck();execute('powershell.exe',['-NoProfile','-NonInteractive','-Command',`$p=Get-CimInstance Win32_Process -Filter "name='dota2.exe'";if(@($p).Count -ne 1 -or $p.ProcessId -ne ${pid} -or $p.CommandLine -notmatch '\\s-tools\\s' -or $p.CommandLine -notmatch 'survival_offline_logic_test 1'){throw 'owned_offline_process_changed'}`],15000);
 const s=await connect({port:29006,timeoutMs:5000,retainOutput:false});try{await s.send([{name:'console_send',arguments:{commands:'quit'}}],'',100);}catch(e){if(!String(e.message).includes('disconnected'))throw e;}finally{await s.close();}await sleep(3000);
}
async function main(){
 try{
  for(const [round,mode]of [[2,'pure'],[3,'rich'],[4,'cold'],[5,'standard']].filter(([round])=>round>=from)){
   stopCheck();const record={round,mode,started:new Date().toISOString()};report.rounds.push(record);save();
   record.key_chain_stdout=execute(process.execPath,['tools/ui_qa_20261025/native_round.cjs','--round',String(round),'--mode',mode,'--tag',tag,'--archive-timeline'],240000);
   const base=JSON.parse(fs.readFileSync(path.join(out,'round_'+round+'_'+tag+'.json'),'utf8'));if(!base.procedural_ok)throw Error('key_chain_not_complete');record.pid=base.pid;save();
   record.settlement_stdout=execute(process.execPath,['tools/ui_qa_20261025/native_settlement.cjs','--tag',tag+'_r'+round,'--mode',mode],60000);
   const settled=JSON.parse(fs.readFileSync(path.join(out,'final_wave_'+tag+'_r'+round+'.json'),'utf8'));if(!settled.ok)throw Error('native_settlement_not_complete');record.settlement_ok=true;save();
   record.final_capture=JSON.parse(execute('powershell.exe',['-NoProfile','-NonInteractive','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-File','tools/ui_qa_20261025/native_capture.ps1','-GameProcessId',String(base.pid),'-Round',String(round),'-Name',tag+'_settled','-PointerX','1510','-PointerY','520','-Delay','1000'],15000));save();
   await quitOwned(base.pid);record.normal_quit=true;record.finished=new Date().toISOString();save();
  }
  report.ok=true;
 }catch(e){report.error=String(e.message);}finally{report.finished=new Date().toISOString();save();console.log(JSON.stringify({ok:report.ok,error:report.error,rounds:report.rounds.map(r=>({round:r.round,mode:r.mode,pid:r.pid,settled:r.settlement_ok,normal_quit:r.normal_quit})),file}));if(!report.ok)process.exitCode=1;}
}
main();
