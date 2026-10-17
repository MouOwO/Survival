'use strict';
// Pure parsing/ownership regression; no game, Windows APIs or child processes.
const assert=require('node:assert/strict'),fs=require('node:fs'),os=require('node:os'),path=require('node:path');
const {analyzeV2Csv,finiteCell,nativeSnapshot,parseSnapshot,restoreEdge}=require('./run_native_cpu_gpu_diagnostic.cjs');
const {cleanupSampler,reserveEvidenceDirectory}=require('./run_four_player_live_perf.cjs');
let checks=0;
function check(value){checks++;assert(value);}
const headers=['Application','ProcessID','SwapChainAddress','CPUStartTime','FrameTime','CPUBusy','CPUWait','GPUTime','GPUBusy','GPUWait','GPULatency','PresentMode','SyncInterval'];
function row(index,pid=42,chain='0xAB',override={}){
  const values=['dota2.exe',String(pid),chain,String(8000+index*50),'50','40','10','30','25','5','12','Composed: Copy with GPU GDI','1'];
  for(const [name,value] of Object.entries(override))values[headers.indexOf(name)]=String(value);
  return values;
}
function csv(rows,head=headers){return [head.join(','),...rows.map(values=>values.join(','))].join('\r\n');}
const normal=Array.from({length:601},(_,index)=>row(index));
let result=analyzeV2Csv(csv(normal),42);
check(result.valid);check(result.groups.length===1);check(result.groups[0].accepted_frame_rows===600);
check(result.groups[0].mean_fps===20);check(result.groups[0].metrics.CPUBusy.mean_ms===40);
check(result.groups[0].metrics.GPUBusy.p99_ms===25);check(result.groups[0].discarded_first_row===1);
check(result.groups[0].timestamp_span_seconds===29.95);check(result.column_mapping.FrameTime==='FrameTime');
const prefixed=headers.map(value=>['CPUBusy','CPUWait','GPUTime','GPUBusy','GPUWait','GPULatency'].includes(value)?'Ms'+value:value);
result=analyzeV2Csv(csv(normal,prefixed),42);check(result.valid);check(result.column_mapping.GPUBusy==='MsGPUBusy');
let mixed=normal.concat(Array.from({length:601},(_,index)=>row(index,43,'0xCD')));
result=analyzeV2Csv(csv(mixed),42);check(result.valid);check(result.groups.length===2);check(result.primary_chain.process_id===42);
mixed=normal.concat(Array.from({length:601},(_,index)=>row(index,42,'0xCD')));
result=analyzeV2Csv(csv(mixed),42);check(!result.valid);check(result.invalid_reasons.includes('multiple_swapchains_require_explicit_selection'));
result=analyzeV2Csv(csv(mixed),42,'0xCD');check(result.valid);check(result.primary_chain.swapchain_address==='0xCD');
check(result.groups.every(group=>group.mean_fps===20));
result=analyzeV2Csv(csv(normal.slice(0,201)),42);check(!result.valid);check(result.invalid_reasons.includes('less_than_30s_interval_coverage'));
for(const [name,value,expected] of [['FrameTime',0,'invalid_native_frame_rows'],['FrameTime',-1,'invalid_native_frame_rows'],
    ['CPUBusy','NA','invalid_native_metric_rows'],['GPUBusy',-1,'invalid_native_metric_rows']]){
  const invalid=normal.map(values=>[...values]);invalid[100][headers.indexOf(name)]=String(value);
  result=analyzeV2Csv(csv(invalid),42);check(!result.valid);check(result.invalid_reasons.includes(expected));
}
const zero=normal.map(values=>[...values]);zero[100][headers.indexOf('GPUBusy')]='0';
check(analyzeV2Csv(csv(zero),42).valid); // GPU idle is a valid zero, not missing telemetry.
const stale=normal.map(values=>[...values]);stale[100][3]=stale[99][3];
result=analyzeV2Csv(csv(stale),42);check(!result.valid);check(result.groups[0].nonmonotonic_timestamp_rows===1);
const drift=normal.map(values=>[...values]);for(const values of drift)values[3]=String(Number(values[3])*2);
result=analyzeV2Csv(csv(drift),42);check(!result.valid);check(result.invalid_reasons.includes('frame_sum_timestamp_span_mismatch'));
result=analyzeV2Csv(csv(normal,headers.map(name=>name==='GPUWait'?'unsupported':name)),42);
check(!result.valid);check(result.invalid_reasons.includes('missing_GPUWait'));
const invalidUngrouped=normal.concat([['wrong']]);check(!analyzeV2Csv(csv(invalidUngrouped),42).valid);
for(const value of ['',' ','NA','NaN','Infinity','0x11'])check(finiteCell(value)===null);
check(finiteCell('-0')===0);check(finiteCell('1e2')===100);check(finiteCell('.5')===.5);
check(analyzeV2Csv('"unterminated',42).invalid_reasons.includes('csv_parse_error'));
const nonce='a'.repeat(16),snapshot=nativeSnapshot(nonce,'BEFORE');
check(snapshot.request.arguments.code.includes('DOTA_GAMERULES_STATE_GAME_IN_PROGRESS'));
check(!/\.start\(|spawn_wave|vprof_on|sethook\(/.test(snapshot.request.arguments.code));
check(parseSnapshot('[CPU_GPU_SNAPSHOT] '+JSON.stringify({nonce,phase:'BEFORE',owners:[]}),nonce,'BEFORE').owners.length===0);
check(parseSnapshot('[CPU_GPU_SNAPSHOT] '+JSON.stringify({nonce:'wrong',phase:'BEFORE'}),nonce,'BEFORE')===null);
assert.throws(()=>nativeSnapshot('unsafe','BEFORE'));checks++;
async function main(){
  const directory=fs.mkdtempSync(path.join(os.tmpdir(),'cpu_gpu_test_'));
  try{
    const state={nonce,stage:directory,edgeChanged:true,originalEdge:'true'};let sent='';
    await restoreEdge(state,{send:async requests=>{sent=requests[0].arguments.commands;return {output:'dota_camera_edgemove = true\n'};}});
    check(state.edgeRestored===true);check(sent.startsWith('dota_camera_edgemove true\n'));
    await assert.rejects(()=>restoreEdge({...state,originalEdge:'1;unsafe'},{}));checks++;
    await assert.rejects(()=>restoreEdge({...state,edgeRestored:false},{send:async()=>({output:'dota_camera_edgemove = false\n'})}));checks++;
    let killed=0,terminated=[];
    const record={child:{pid:111,kill(){killed++;record.closed=true;record.code=1;return true;}},closed:false,code:1,closeDone:Promise.resolve()};
    const cleanup={nonce,meta:{session_name:'SurvivalLive_'+nonce},presentmonPath:'own-signed.exe',presentmon:record};
    await cleanupSampler(cleanup,{}, {terminateSession:async(executable,args)=>{terminated.push({executable,args});record.closed=true;}});
    check(terminated.length===1);check(terminated[0].args[0]==='--session_name');
    check(terminated[0].args[1]==='SurvivalLive_'+nonce);check(terminated[0].args[2]==='--terminate_existing_session');check(killed===0);
    await cleanupSampler(cleanup,{}, {terminateSession:async()=>{throw Error('idempotence violated');}});check(terminated.length===1);
    const stopped={nonce,meta:{session_name:'SurvivalLive_'+nonce},presentmonPath:'own.exe',presentmon:{child:{pid:112},closed:true,code:0}};
    await cleanupSampler(stopped,{}, {terminateSession:async()=>{throw Error('must not touch normal or foreign sessions');}});
    check(stopped.etwTerminationStatus==='not_needed_normal_exit');check(stopped.cleanupErrors.length===0);
    reserveEvidenceDirectory(directory,'unique');assert.throws(()=>reserveEvidenceDirectory(directory,'unique'));checks++;
    assert.throws(()=>reserveEvidenceDirectory(directory,'../outside'));checks++;
  }finally{
    assert(path.resolve(directory).startsWith(path.resolve(os.tmpdir())+path.sep)&&path.basename(directory).startsWith('cpu_gpu_test_'));
    fs.rmSync(directory,{recursive:true,force:true});
  }
  console.log('native_cpu_gpu_diagnostic PASS checks='+checks+' no_game_or_process_operations');
}
main().catch(error=>{console.error(error);process.exitCode=1;});
