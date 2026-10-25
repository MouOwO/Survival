'use strict';
// A read-only convar query and harmless logger reload attempt. The latter must
// be rejected by the engine; it never grants resources or modifies a profile.
const fs=require('node:fs'),path=require('node:path'),cp=require('node:child_process');
const {connect}=require('../map_c6/console-session.cjs');
const root=path.resolve(__dirname,'../..');
async function main(){
 const label=process.argv[2]||'engine_cheats';
 if(!/^[a-z0-9_]{1,64}$/.test(label))throw Error('fixed_output_label_required');
 const receipt=JSON.parse(fs.readFileSync(path.join(root,'output/test_entry_runtime/online_latest.json'),'utf8'));
 if(receipt.mode!=='online'||receipt.addon!=='svt_w24'||!Number.isSafeInteger(receipt.pid)||receipt.pid<=0||receipt.started_utc<'2026-10-24T16:06:39')throw Error('current_online_entry_required');
 const script=`$ErrorActionPreference='Stop';$p=Get-CimInstance Win32_Process -Filter 'ProcessId=${receipt.pid}';if($p.Name -ne 'dota2.exe' -or $p.CommandLine -notmatch '(?:^|\\s)-addon\\s+svt_w24(?:\\s|$)' -or $p.CommandLine -notmatch '(?:^|\\s)-vconport\\s+29005(?:\\s|$)'){throw 'fixed_online_process_required'};'verified'`;
 const verified=cp.spawnSync('powershell.exe',['-NoProfile','-NonInteractive','-Command',script],{encoding:'utf8',windowsHide:true,timeout:15000});
 if(verified.status!==0||verified.stdout.trim()!=='verified')throw Error('fixed_online_process_required');
 const session=await connect({port:29005,timeoutMs:6000,retainOutput:false});
 try{
  const reply=await session.send([{name:'console_send',arguments:{commands:'sv_cheats\nscript_reload_code core/logger'}}],'',500);
  const lines=reply.output.split(/\r?\n/).filter(x=>/sv_cheats|script_reload_code/.test(x)&&!/[0-9]{15,}|https?:|Bearer/i.test(x)).map(x=>x.slice(0,512));
  const report={at_utc:new Date().toISOString(),pid:receipt.pid,port:29005,scope:'native_engine_no_resource_mutation',lines,
   convar_disabled:lines.some(x=>/sv_cheats["'\s=:]*(?:false|0)\b/i.test(x)),
   reload_rejected:lines.some(x=>/script_reload_code/.test(x)&&/cheat|sv_cheats/i.test(x)),
   cloud_database_access:false,resource_commands_sent:false};
  report.passed=report.convar_disabled&&report.reload_rejected;
  const target=path.join(root,'output/ui_qa_20261025/online/'+label+'.json');
  fs.writeFileSync(target,JSON.stringify(report,null,2),{flag:'wx'});console.log(JSON.stringify(report));
  if(!report.passed)process.exitCode=1;
 }finally{await session.close();}
}
main().catch(()=>{console.error(JSON.stringify({ok:false,error:'online_cheat_gate_check_failed'}));process.exitCode=1;});
