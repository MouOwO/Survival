"use strict";
// Fixed commands for the separately owned base-map serializer probe only.
const fs=require('node:fs'),cp=require('node:child_process'),path=require('node:path');
const {ConsoleSession}=require('./map_c6/console-session.cjs');
const run=process.argv[3]||'run01';if(!['run01','run02','run03','run04'].includes(run))throw Error('explicit_probe_run_required');
const folder='D:/Survival_本地排演/network50_probe_20261103/'+run;
const wanted=JSON.parse(fs.readFileSync(path.join(folder,'process.json'),'utf8'));
const mode=process.argv[2]||'query';
if(!['query','run','read','c2s','close'].includes(mode))throw Error('fixed_probe_operation_required');
if(['c2s','close'].includes(mode)&&run!=='run04')throw Error('c2s_or_close_requires_run04');
if(!Number.isSafeInteger(wanted.pid)||wanted.pid<1)throw Error('pinned_native_pid_required');
const inspect=String.raw`$ErrorActionPreference='Stop';$p=Get-CimInstance Win32_Process -Filter 'ProcessId=${wanted.pid}';$l=@(Get-NetTCPConnection -State Listen -LocalPort 29068 -ErrorAction Stop);[ordered]@{pid=[int]$p.ProcessId;created=$p.CreationDate.ToUniversalTime().ToString('o');portOwners=@($l|ForEach-Object{[int]$_.OwningProcess})}|ConvertTo-Json -Compress`;
function guard(){const p=cp.spawnSync('powershell.exe',['-NoProfile','-NonInteractive','-Command',inspect],{windowsHide:true,encoding:'utf8',timeout:20000,maxBuffer:65536});if(p.status!==0)throw Error('owned_probe_identity_query_failed');const s=JSON.parse(p.stdout.replace(/^\uFEFF/,''));if(s.pid!==wanted.pid||s.created!==wanted.created||!s.portOwners.length||s.portOwners.some(x=>x!==wanted.pid))throw Error('owned_probe_identity_or_port_changed');}
(async()=>{
 guard();const client=new ConsoleSession({port:29068,timeoutMs:5000,historyTimeoutMs:10000,retainOutput:false,maxPendingOutputChars:262144});
 try{await client.connect();guard();
  const commands=mode==='c2s'?'net_restrict_showmsg_socket server\nnet_showmsg 1\nscript if IsInToolsMode() and GetMapName()=="template_map" then local p=PlayerResource:GetPlayer(0) if p then if not p:GetAssignedHero() then CreateHeroForPlayer("npc_dota_hero_axe",p) end GameRules:ForceGameStart() CustomGameEventManager:Send_ServerToPlayer(p,"cw",{d=""}) end end':mode==='close'?'quit':mode==='query'?'net_showmsg CUserMsg_CustomGameEvent\nnet_restrict_showmsg_socket client\nnet_messageinfo 148\nscript print("[N50_STATE] map="..tostring(GetMapName()).." server="..tostring(IsServer()))':mode==='run'?'exec net50_probe_20261103':'echo N50_READ';
  const result=await client.send([{name:'console_send',arguments:{commands:commands+'\necho N50_DONE'}}],'N50_DONE',200);
  const safe=String(result.output||'').split(/\r?\n/).filter(x=>/N50_|CUserMsg_CustomGameEvent|net50_probe_20261103|CustomGameEventManager/.test(x));
  fs.writeFileSync(path.join(folder,'console_'+mode+'_'+Date.now()+'.json'),JSON.stringify({mode,output_truncated:result.output_truncated,lines:safe},null,2));
  console.log(JSON.stringify({status:'OWNED_NATIVE_PROBE_CONSOLE',mode,output_truncated:result.output_truncated,lines:safe}));
 }finally{await client.close();}
})().catch(e=>{console.error(JSON.stringify({status:'NATIVE_PROBE_CONSOLE_REFUSED',error:String(e.message).slice(0,180)}));process.exitCode=2;});
