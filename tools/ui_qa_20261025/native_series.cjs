'use strict';
// Continue rounds 3..5 only after the preceding owned offline key-chain exits.
const fs=require('node:fs'),path=require('node:path'),cp=require('node:child_process');
const {connect}=require('../map_c6/console-session.cjs');
const out=path.resolve('output/ui_qa_20261025/native_review'),sleep=ms=>new Promise(r=>setTimeout(r,ms));
const report={started:new Date().toISOString(),scope:'owned_offline_native_key_chains_not_full_wave_clear',rounds:[],ok:false};
function save(){fs.writeFileSync(path.join(out,'series_3_5.json'),JSON.stringify(report,null,2));}
function stopCheck(){if(fs.existsSync(path.join(out,'STOP_SERIES')))throw Error('series_explicitly_stopped');}
async function completed(file){const start=Date.now();while(Date.now()-start<600000){stopCheck();if(fs.existsSync(file)){const r=JSON.parse(fs.readFileSync(file,'utf8'));if(r.finished){if(!r.procedural_ok)throw Error('previous_round_failed:'+r.error);return r;}}await sleep(1500);}throw Error('previous_round_completion_timeout');}
async function quitOwned(pid){
 stopCheck();const ps=cp.spawnSync('powershell.exe',['-NoProfile','-NonInteractive','-Command',`$p=Get-CimInstance Win32_Process -Filter "name='dota2.exe'"; if(@($p).Count -ne 1 -or $p.ProcessId -ne ${pid} -or $p.CommandLine -notmatch '\\s-tools\\s' -or $p.CommandLine -notmatch 'survival_offline_logic_test 1'){throw 'owned_offline_process_changed'}; Write-Output 'OWNED_OFFLINE_CONFIRMED'`],{encoding:'utf8',windowsHide:true,timeout:15000});
 if(ps.status!==0||!ps.stdout.includes('OWNED_OFFLINE_CONFIRMED'))throw Error('owned_offline_process_changed');
 const s=await connect({port:29006,timeoutMs:5000,retainOutput:false});try{await s.send([{name:'console_send',arguments:{commands:'quit'}}],'',100);}catch(e){if(!String(e.message).includes('disconnected'))throw e;}finally{await s.close();}await sleep(3000);
}
async function main(){
 let previous=path.join(out,'round_2_cold.json');
 try{for(const [round,mode]of [[3,'rich'],[4,'cold'],[5,'standard']]){const prior=await completed(previous);await quitOwned(prior.pid);stopCheck();const args=['tools/ui_qa_20261025/native_round.cjs','--round',String(round),'--mode',mode,'--tag','cold'];const r=await new Promise((resolve,reject)=>{const child=cp.spawn(process.execPath,args,{encoding:'utf8',windowsHide:true,stdio:['ignore','pipe','pipe']});let stdout='',stderr='';child.stdout.on('data',b=>stdout+=b);child.stderr.on('data',b=>stderr+=b);child.on('error',reject);child.on('close',code=>resolve({code,stdout,stderr}));});report.rounds.push({round,mode,...r});save();if(r.code!==0)throw Error('native_round_failed:'+round);previous=path.join(out,'round_'+round+'_cold.json');}report.ok=true;}catch(e){report.error=String(e.message);}finally{report.finished=new Date().toISOString();save();console.log(JSON.stringify(report));if(!report.ok)process.exitCode=1;}
}
main();
