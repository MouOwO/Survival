'use strict';
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),cp=require('node:child_process');
const {ConsoleSession}=require('../map_c6/console-session.cjs');
const root=path.resolve(__dirname,'../..'),folder=path.join(root,'output/shop_recovery_20261031');
const owned=JSON.parse(fs.readFileSync(path.join(folder,'native_process.json'),'utf8'));
if(!Number.isSafeInteger(owned.pid)||owned.pid<1||owned.addon!=='svt_s3102'||owned.port!==29006)throw Error('owned_native_scope_invalid');
const script='$ErrorActionPreference="Stop";$p=Get-CimInstance Win32_Process -Filter "ProcessId='+owned.pid+'";if($null -eq $p -or $p.Name -ne "dota2.exe" -or $p.CommandLine -notmatch "-addon svt_s3102(?: |$)" -or $p.CommandLine -notmatch "(?:^| )-tools(?: |$)" -or $p.CommandLine -notmatch "\\+sv_cheats 0(?: |$)" -or $p.CommandLine -match "survival_offline_logic_test"){throw "native_process_changed"};$tcp=@(Get-NetTCPConnection -State Listen -LocalPort 29006 -ErrorAction Stop);if($tcp.Count -lt 1 -or @($tcp|Where-Object{$_.OwningProcess -ne '+owned.pid+'}).Count -gt 0){throw "native_listener_changed"};[ordered]@{pid=$p.ProcessId;created=$p.CreationDate.ToUniversalTime().ToString("o")}|ConvertTo-Json -Compress';
const live=JSON.parse(cp.execFileSync('powershell.exe',['-NoProfile','-NonInteractive','-Command',script],{encoding:'utf8',windowsHide:true}));
if(live.pid!==owned.pid||Math.abs(Date.parse(live.created)-Date.parse(owned.started_utc))>1000)throw Error('native_process_changed');
const output=path.join(folder,'native_cvar_query.json');if(fs.existsSync(output))throw Error('new_query_receipt_required');
const marker='SHOP_NATIVE_READONLY_'+crypto.randomBytes(10).toString('hex');
(async()=>{
 const session=new ConsoleSession({port:owned.port,timeoutMs:10000,historyTimeoutMs:30000,retainOutput:false});
 try{
  await session.connect();
  const result=await session.send([{name:'console_send',arguments:{commands:'sv_cheats\nsurvival_archive_http_enabled\necho '+marker}}],marker,300);
  const value={pid:owned.pid,addon:owned.addon,marker_received:result.expected_output_received,script_injection:false,
   commands:['sv_cheats','survival_archive_http_enabled'],raw_output:result.output,
   raw_output_sha256:crypto.createHash('sha256').update(result.output).digest('hex')};
  fs.writeFileSync(output,JSON.stringify(value,null,2)+'\n',{flag:'wx'});
  console.log(JSON.stringify({pid:owned.pid,marker_received:value.marker_received,script_injection:false,query_count:2}));
 }finally{await session.close();}
})().catch(error=>{console.error(error.message);process.exitCode=1;});
