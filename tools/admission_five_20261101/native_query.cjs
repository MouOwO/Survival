'use strict';
// One readonly fresh-nonce query, bound to our exact signed addon/PID/start time.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),cp=require('node:child_process');
const {ConsoleSession}=require('../map_c6/console-session.cjs');
const root=path.resolve(__dirname,'../..'),folder=path.join(root,'output/admission_five_20261101');
const owned=JSON.parse(fs.readFileSync(path.join(folder,'native_process.json'),'utf8'));
const target=path.join(folder,'native_cvar_query.json');
if(fs.existsSync(target)||owned.addon!=='svt_f1104'||!Number.isInteger(owned.pid)||owned.pid<1||owned.port!==29006)throw Error('Explicit new owned native query required');
const ps="$ErrorActionPreference='Stop';$p=Get-CimInstance Win32_Process -Filter 'ProcessId="+owned.pid+"';if($null -eq $p -or $p.Name -ne 'dota2.exe' -or $p.CommandLine -notmatch '-addon svt_f1104(?: |$)' -or $p.CommandLine -notmatch '(?:^| )-tools(?: |$)' -or $p.CommandLine -notmatch '-vconport 29006(?: |$)'){throw 'Owned process mismatch'};$l=@(Get-NetTCPConnection -State Listen -LocalPort 29006);if($l.Count -lt 1 -or @($l|Where-Object{$_.OwningProcess -ne "+owned.pid+"}).Count -gt 0){throw 'Console listener ownership mismatch'};[ordered]@{pid=$p.ProcessId;started=$p.CreationDate.ToUniversalTime().ToString('o')}|ConvertTo-Json -Compress";
const identity=JSON.parse(cp.execFileSync('powershell.exe',['-NoProfile','-Command',ps],{encoding:'utf8',windowsHide:true}));
if(identity.pid!==owned.pid||identity.started!==owned.process_started_os_utc)throw Error('Native process creation time changed');
(async()=>{
 const marker='ADMISSION_FIVE_QUERY_'+crypto.randomBytes(16).toString('hex');
 const session=new ConsoleSession({port:29006,timeoutMs:15000,historyTimeoutMs:30000,retainOutput:false});
 try{
  await session.connect();
  const commands=['sv_cheats','survival_archive_http_enabled'];
  const answer=await session.send([{name:'console_send',arguments:{commands:commands.join('\n')+'\necho '+marker}}],marker,500);
  if(!answer.expected_output_received)throw Error('Fresh native marker missing');
  const result={schema:1,pid:owned.pid,addon:owned.addon,process_started_os_utc:identity.started,commands,
   marker_received:true,script_injection:false,query_count:1,raw_output:answer.output,
   raw_output_sha256:crypto.createHash('sha256').update(answer.output,'utf8').digest('hex')};
  fs.writeFileSync(target,JSON.stringify(result,null,2)+'\n',{flag:'wx'});
  process.stdout.write(JSON.stringify({status:'READONLY_NATIVE_QUERY_CAPTURED',pid:owned.pid,script_injection:false})+'\n');
 }finally{await session.close();}
})().catch(error=>{process.stderr.write(error.message+'\n');process.exitCode=1;});
