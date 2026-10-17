'use strict';
// Independent 30-second ETW diagnostic of an ALREADY running Tools battle.
// No waves, activity, profiler, debug hooks, accounts or payment requests.
const fs=require('node:fs'),path=require('node:path'),os=require('node:os');
const cp=require('node:child_process'),crypto=require('node:crypto');
const {ConsoleSession}=require('./map_c6/console-session.cjs');
const shared=require('./run_four_player_live_perf.cjs');
const root=path.resolve(__dirname,'..'),SECONDS=30,DELAY=8;
const python='C:/Users/Administrator/AppData/Local/Programs/Python/Python314/python.exe';
const pwsh='D:/7/pwsh.exe';
const metricAliases={
  FrameTime:['FrameTime','MsBetweenPresents'],
  CPUBusy:['CPUBusy','MsCPUBusy'],CPUWait:['CPUWait','MsCPUWait'],
  GPUTime:['GPUTime','MsGPUTime'],GPUBusy:['GPUBusy','MsGPUBusy'],
  GPUWait:['GPUWait','MsGPUWait'],GPULatency:['GPULatency','MsGPULatency'],
};
const artifacts=['cpu_gpu.csv','settings.log','settings_after.log','before.log','start.log','after.log',
  'camera.log','focus.json','focus_restore.log','focus_observer.log','presentmon.log','signature.json','analysis.json'];
function finiteCell(value){
  if(typeof value!=='string'||!value.trim()||!/^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$/.test(value.trim()))return null;
  const number=Number(value);return Number.isFinite(number)?number:null;
}
function quantile(values,p){
  const sorted=[...values].sort((a,b)=>a-b),position=(sorted.length-1)*p,index=Math.floor(position);
  return sorted[index]+(sorted[Math.min(index+1,sorted.length-1)]-sorted[index])*(position-index);
}
function distribution(values){
  if(!values.length)return {count:0,mean_ms:null,p50_ms:null,p95_ms:null,p99_ms:null,max_ms:null};
  return {count:values.length,mean_ms:values.reduce((a,b)=>a+b,0)/values.length,
    p50_ms:quantile(values,.5),p95_ms:quantile(values,.95),p99_ms:quantile(values,.99),max_ms:Math.max(...values)};
}
function analyzeV2Csv(text,pid,requestedChain=null){
  const result={schema:'native_cpu_gpu_v2_analysis_v1',groups:[],column_mapping:{},invalid_reasons:[],valid:false,
    primary_chain:null,selection_strategy:null,discarded_ungrouped_rows:0,
    note:'CPU/GPU timings are ETW frame durations, not OS utilization. Causal CPU/GPU bottleneck classification requires matched workload and native profiling.'};
  let rows;try{rows=shared.csvRows(String(text).replace(/^\uFEFF/,''));}catch(error){result.invalid_reasons.push('csv_parse_error');return result;}
  const header=rows.shift()||[];
  for(const name of ['ProcessID','SwapChainAddress'])if(!header.includes(name))result.invalid_reasons.push('missing_'+name);
  for(const [metric,aliases] of Object.entries(metricAliases)){
    const matches=aliases.filter(name=>header.includes(name));
    if(matches.length===1)result.column_mapping[metric]=matches[0];
    else result.invalid_reasons.push(matches.length?'ambiguous_'+metric:'missing_'+metric);
  }
  const timestampName=header.includes('CPUStartTime')?'CPUStartTime':null;
  result.timestamp_column=timestampName;result.timestamp_unit='milliseconds';
  if(!timestampName)result.invalid_reasons.push('missing_CPUStartTime');
  if(result.invalid_reasons.length)return result;
  const index=Object.fromEntries(header.map((name,i)=>[name,i])),groups=new Map();
  for(const cells of rows){
    const process=finiteCell(cells[index.ProcessID]),chain=cells[index.SwapChainAddress];
    if(cells.length!==header.length||!Number.isInteger(process)||process<=0||!/^0x[0-9a-f]+$/i.test(chain||'')){
      result.discarded_ungrouped_rows++;continue;
    }
    const key=process+'|'+chain;
    if(!groups.has(key))groups.set(key,{process_id:process,swapchain:chain,raw:[]});
    groups.get(key).raw.push(cells);
  }
  for(const group of groups.values()){
    const report={process_id:group.process_id,swapchain_address:group.swapchain,raw_rows:group.raw.length,
      discarded_first_row:group.raw.length?1:0,invalid_frame_rows:0,nonmonotonic_timestamp_rows:0,
      metrics:{},present_modes:{},sync_intervals:{},first_timestamp_ms:null,last_timestamp_ms:null};
    const values=Object.fromEntries(Object.keys(metricAliases).map(name=>[name,[]]));
    const invalidMetric=Object.fromEntries(Object.keys(metricAliases).map(name=>[name,0]));let previous=null;
    for(const cells of group.raw.slice(1)){
      const frame=finiteCell(cells[index[result.column_mapping.FrameTime]]),time=finiteCell(cells[index[timestampName]]);
      if(frame===null||frame<=0||time===null||time<0){report.invalid_frame_rows++;continue;}
      if(previous!==null&&time<=previous){report.nonmonotonic_timestamp_rows++;continue;}previous=time;
      if(report.first_timestamp_ms===null)report.first_timestamp_ms=time;report.last_timestamp_ms=time;
      for(const metric of Object.keys(metricAliases)){
        const value=finiteCell(cells[index[result.column_mapping[metric]]]);
        if(value===null||value<0)invalidMetric[metric]++;else values[metric].push(value);
      }
      for(const [field,target] of [['PresentMode',report.present_modes],['SyncInterval',report.sync_intervals]]){
        if(index[field]!==undefined){const value=cells[index[field]];target[value]=(target[value]||0)+1;}
      }
    }
    for(const metric of Object.keys(metricAliases))report.metrics[metric]={...distribution(values[metric]),invalid_rows:invalidMetric[metric]};
    report.accepted_frame_rows=values.FrameTime.length;
    report.frame_time_sum_seconds=values.FrameTime.reduce((a,b)=>a+b,0)/1000;
    report.mean_fps=report.frame_time_sum_seconds?report.accepted_frame_rows/report.frame_time_sum_seconds:null;
    report.timestamp_span_seconds=report.first_timestamp_ms===null?0:(report.last_timestamp_ms-report.first_timestamp_ms)/1000;
    result.groups.push(report);
  }
  const candidates=result.groups.filter(group=>group.process_id===pid&&group.accepted_frame_rows>0);
  let primary;
  if(requestedChain){primary=candidates.find(group=>group.swapchain_address===requestedChain);result.selection_strategy='explicit_swapchain';}
  else if(candidates.length===1){primary=candidates[0];result.selection_strategy='only_usable_swapchain_for_requested_pid';}
  else if(candidates.length>1)result.invalid_reasons.push('multiple_swapchains_require_explicit_selection');
  if(!primary)result.invalid_reasons.push('no_selected_usable_swapchain');
  if(primary){
    result.primary_chain={process_id:primary.process_id,swapchain_address:primary.swapchain_address};
    if(primary.frame_time_sum_seconds<28.75||primary.timestamp_span_seconds<28.75)result.invalid_reasons.push('less_than_30s_interval_coverage');
    if(primary.frame_time_sum_seconds>31.25||primary.timestamp_span_seconds>31.25)result.invalid_reasons.push('unexpected_long_capture');
    if(Math.abs(primary.frame_time_sum_seconds-primary.timestamp_span_seconds)>.5)result.invalid_reasons.push('frame_sum_timestamp_span_mismatch');
    if(primary.invalid_frame_rows||primary.nonmonotonic_timestamp_rows)result.invalid_reasons.push('invalid_native_frame_rows');
    if(Object.values(primary.metrics).some(metric=>metric.invalid_rows))result.invalid_reasons.push('invalid_native_metric_rows');
  }
  if(result.discarded_ungrouped_rows)result.invalid_reasons.push('ungrouped_csv_rows');
  result.valid=result.invalid_reasons.length===0;return result;
}
function nativeSnapshot(nonce,phase){
  if(!/^[0-9a-f]{16}$/.test(nonce)||!['BEFORE','START','AFTER'].includes(phase))throw Error('Invalid snapshot identity');
  const marker='CPU_GPU_'+phase+'_'+nonce;
  const body=shared.gameStateGuard(nonce,phase,phase!=='AFTER')+
    "assert(IsInToolsMode() and IsServer(),'Tools server required');local r={nonce='"+nonce+"',phase='"+phase+"',owners={},creature_count=0};"+
    "if GameRules then r.paused=GameRules:IsGamePaused();r.game_time=GameRules:GetGameTime() end;"+
    "local bus=package.loaded['core/event_bus'];local events=package.loaded['core/events'];"+
    "if bus and events then for id=0,3 do if PlayerResource:IsValidPlayerID(id) then local counts={};"+
    "for _,b in ipairs((bus.request(events.BUILDING_LIST_REQUEST,{player_id=id,handles_only=true}) or {}).buildings or {}) do counts[b.building_id]=(counts[b.building_id] or 0)+1 end;"+
    "local resources=bus.request(events.RESOURCE_GET_REQUEST,{player_id=id}) or {};r.owners[#r.owners+1]={id=id,fake=PlayerResource:IsFakeClient(id),buildings=counts,population=resources.population,max_population=resources.max_population} end end;"+
    "local w=bus.request(events.WAVE_STATE_GET_REQUEST,{}) or {};r.wave_alive=w.alive;r.wave_index=w.current_wave or w.wave_index end;"+
    "for _,u in ipairs(Entities:FindAllByClassname('npc_dota_creature') or {}) do r.creature_count=r.creature_count+1 end;"+
    "r.debug_hook_present=debug and debug.gethook and debug.gethook()~=nil or false;"+
    "r.known_lua_profiler_active=_G.SURVIVAL_EXTREME_PERFORMANCE_CAPTURE~=nil or _G.SURVIVAL_COMBAT_PERFORMANCE_CAPTURE~=nil or _G.SURVIVAL_NATIVE_DAMAGE_FILTER_PROFILE~=nil or _G.SURVIVAL_BOSS_PERFORMANCE_CAPTURE~=nil;"+
    "print('[CPU_GPU_SNAPSHOT] '..require('core/json_encoder').encode(r));print('"+marker+"')";
  return {request:{name:'dota_run_lua',arguments:{code:body}},marker};
}
function parseSnapshot(text,nonce,phase){
  for(const line of String(text).split(/\r?\n/))if(line.startsWith('[CPU_GPU_SNAPSHOT] ')){
    try{const value=JSON.parse(line.slice('[CPU_GPU_SNAPSHOT] '.length));if(value.nonce===nonce&&value.phase===phase)return value;}catch{}
  }return null;
}
function command(text){return {name:'console_send',arguments:{commands:text}};}
function execFile(executable,args,timeout=15000){return new Promise((resolve,reject)=>cp.execFile(executable,args,{windowsHide:true,encoding:'utf8',timeout},(error,stdout,stderr)=>error?reject(error):resolve({stdout,stderr})));}
function readJsonLine(text){const line=String(text).trim().split(/\r?\n/).filter(value=>value.startsWith('{')).pop();return line?JSON.parse(line):null;}
async function restoreEdge(state,session){
  if(!state.edgeChanged)return;
  if(!/^(0|1|true|false)$/.test(state.originalEdge))throw Error('Original edge-move unconfirmed');
  const marker='CPU_GPU_RESTORE_'+state.nonce;
  const response=await session.send([command('dota_camera_edgemove '+state.originalEdge+'\ndota_camera_edgemove\necho '+marker)],marker,100);
  fs.appendFileSync(path.join(state.stage,'settings_after.log'),response.output+'\n');
  const actual=shared.parseEdgeMove(response.output),expected=['1','true'].includes(state.originalEdge)?1:0;
  if(!actual||actual.value!==expected)throw Error('Edge-move restore readback mismatch');state.edgeRestored=true;
}
async function main(args=process.argv.slice(2)){
  const [label,pidText,chain]=args,pid=Number(pidText);
  if(!/^[a-z0-9_]+$/.test(label||'')||!Number.isInteger(pid)||pid<=0||args.length>3||chain&&!/^0x[0-9a-f]+$/i.test(chain))throw Error('Usage: node tools/run_native_cpu_gpu_diagnostic.cjs <unique_label> <pid> [swapchain]');
  const target=shared.reserveEvidenceDirectory(path.join(root,'output/native_cpu_gpu_20261012'),label);
  const nonce=crypto.randomBytes(8).toString('hex'),stage=fs.mkdtempSync(path.join(os.tmpdir(),'survival_cpu_gpu_'));
  const pm=path.join(root,'output/four_client_perf_20261012/bin/PresentMon-2.6.0-x64.exe');
  const meta={schema:'native_cpu_gpu_diagnostic_v1',scope:'one_rendered_client_with_actual_engine_owners_in_snapshots',
    network_clients_claimed:false,acceptance_sample:false,diagnostic_only:true,seconds:SECONDS,delay_seconds:DELAY,
    pid,nonce,session_name:'SurvivalLive_'+nonce,profilers_started:false,activity_started:false,production_source_files_changed:false,
    diagnostic_lua_request_files_prepared_before_capture:true,
    invalid_reasons:[],started_at:new Date().toISOString(),stage,
    measurement_limitations:['One rendered client, engine fake players are not network clients.',
      'One-Hz exact-window observations cannot prove uninterrupted subsecond focus.',
      'CPUStartTime reference is retained raw; focus and ETW start with the same delay but absolute cross-clock alignment is not certified.',
      'No native profiler is started; preexisting native VProf state is not queried or altered.']};
  const state={nonce,stage,target,meta,presentmonPath:pm};let session,failure=null;
  try{
    const signature=await execFile(pwsh,['-NoProfile','-Command',"$s=Get-AuthenticodeSignature -LiteralPath '"+pm.replace(/'/g,"''")+"';@{status=$s.Status.ToString();signer=$s.SignerCertificate.Subject}|ConvertTo-Json -Compress"]);
    const signed=readJsonLine(signature.stdout);fs.writeFileSync(path.join(stage,'signature.json'),JSON.stringify(signed,null,2));
    if(signed?.status!=='Valid'||!signed.signer?.includes('O=Intel Corporation'))throw Error('Signed Intel PresentMon required');
    session=new ConsoleSession({timeoutMs:15000,historyTimeoutMs:60000});await session.connect();
    const phases=Object.fromEntries(['BEFORE','START','AFTER'].map(phase=>[phase,nativeSnapshot(nonce,phase)]));
    session.prepare(Object.values(phases).map(value=>value.request));
    const settingsAck='CPU_GPU_SETTINGS_'+nonce;
    const settings=await session.send([command('fps_max\nfps_max_ui\nengine_no_focus_sleep\nhost_timescale\nsv_stressbots\ndota_camera_edgemove\necho '+settingsAck)],settingsAck,100);
    fs.writeFileSync(path.join(stage,'settings.log'),settings.output);
    const edge=shared.parseEdgeMove(settings.output);if(!edge)throw Error('Original edge-move unavailable');
    state.originalEdge=edge.command_text;meta.original_edge_move=edge;
    const scale=/^\s*host_timescale\s*=\s*"?(\d+(?:\.\d+)?)"?\s*$/mi.exec(settings.output);
    if(!scale||Number(scale[1])!==1)throw Error('Diagnostic requires existing host_timescale=1; no speed changes are made');
    const before=await session.send([phases.BEFORE.request],phases.BEFORE.marker,100);
    fs.writeFileSync(path.join(stage,'before.log'),before.output);meta.before=parseSnapshot(before.output,nonce,'BEFORE');
    if(!meta.before||meta.before.paused||meta.before.known_lua_profiler_active||meta.before.debug_hook_present)throw Error('Unpaused match without preexisting Lua instrumentation required');
    state.edgeChanged=true;
    const edgeAck='CPU_GPU_EDGE_'+nonce;await session.send([command('dota_camera_edgemove 0\necho '+edgeAck)],edgeAck,100);
    meta.camera_before=await shared.readCamera(session,nonce,'BEFORE',stage);
    const start=await session.send([phases.START.request],phases.START.marker,100);
    fs.writeFileSync(path.join(stage,'start.log'),start.output);meta.start=parseSnapshot(start.output,nonce,'START');
    if(!meta.start||meta.start.paused||meta.start.known_lua_profiler_active||meta.start.debug_hook_present)throw Error('Start snapshot invalid');
    state.focus=shared.watchChild(cp.spawn(python,['-B',path.join(root,'tools/observe_live_perf_focus.py'),String(pid),String(SECONDS),String(DELAY)],{windowsHide:true,stdio:['ignore','pipe','pipe']}));
    meta.presentmon_spawn_unix_seconds=Date.now()/1000;
    state.presentmon=shared.watchChild(cp.spawn(pm,['--process_id',String(pid),'--session_name',meta.session_name,'--output_file',path.join(stage,'cpu_gpu.csv'),'--v2_metrics','--delay',String(DELAY),'--timed',String(SECONDS),'--terminate_after_timed','--no_console_stats'],{windowsHide:true,stdio:['ignore','pipe','pipe']}));
    const restored=await execFile(pwsh,['-NoProfile','-File',path.join(root,'tools/focus_live_perf_window.ps1'),'-GameProcessId',String(pid)],7000);
    fs.writeFileSync(path.join(stage,'focus_restore.log'),restored.stdout+restored.stderr);
    meta.focus_restore_window=readJsonLine(restored.stdout);
    if(!shared.restoreWindowValid(meta.focus_restore_window,pid))throw Error('Exact Dota HWND/focus/cursor center not confirmed');
    console.log('CPU_GPU_DIAGNOSTIC_STARTED',label,'30s','pid='+pid,'no_activity_or_profilers');
    const check=record=>record.done.then(value=>{if(value.fatalError)throw value.fatalError;if(value.code!==0)throw Error('Owned child exit '+value.code);return value;});
    await shared.boundedWait(Promise.all([check(state.presentmon),check(state.focus)]),55000,'Owned diagnostic children timed out');
    meta.camera_after=await shared.readCamera(session,nonce,'AFTER',stage);
    const after=await session.send([phases.AFTER.request],phases.AFTER.marker,100);
    fs.writeFileSync(path.join(stage,'after.log'),after.output);meta.after=parseSnapshot(after.output,nonce,'AFTER');
    const afterSettingsAck='CPU_GPU_SETTINGS_AFTER_'+nonce;
    const afterSettings=await session.send([command('fps_max\nfps_max_ui\nengine_no_focus_sleep\nhost_timescale\nsv_stressbots\ndota_camera_edgemove\necho '+afterSettingsAck)],afterSettingsAck,100);
    fs.writeFileSync(path.join(stage,'settings_after.log'),afterSettings.output);
  }catch(error){failure=error;meta.failure=shared.redactConsoleOutput(error.message);}
  finally{
    await shared.cleanupSampler(state,session||{send:()=>Promise.reject(Error('No owned console session'))});
    if(session&&state.edgeChanged)try{await restoreEdge(state,session);}catch(error){state.cleanupErrors.push({step:'edge_move_restore',error:error.message});}
    if(session)try{await session.close();}catch(error){state.cleanupErrors.push({step:'console_close',error:error.message});}
    meta.cleanup_errors=state.cleanupErrors;meta.edge_move_restored=state.edgeRestored===true;meta.owned_etw_session_cleanup=state.etwTerminationStatus;
    meta.presentmon_exit=state.presentmon?.code??null;meta.focus_observer_exit=state.focus?.code??null;
    if(state.presentmon)fs.writeFileSync(path.join(stage,'presentmon.log'),state.presentmon.stdout+state.presentmon.stderr);
    if(state.focus){fs.writeFileSync(path.join(stage,'focus_observer.log'),state.focus.stdout+state.focus.stderr);try{meta.focus=JSON.parse(state.focus.stdout);fs.writeFileSync(path.join(stage,'focus.json'),JSON.stringify(meta.focus,null,2));}catch{meta.invalid_reasons.push('focus_json_unavailable');}}
    if(fs.existsSync(path.join(stage,'focus.json')))try{
      const validated=await execFile(python,['-B',path.join(root,'tools/observe_live_perf_focus.py'),'--validate-json',path.join(stage,'focus.json'),String(pid),String(SECONDS),String(meta.focus_restore_window?.target_hwnd||0)]);
      meta.focus_validation=JSON.parse(validated.stdout);if(!meta.focus_validation.valid)meta.invalid_reasons.push(...meta.focus_validation.invalid_reasons);
    }catch{meta.invalid_reasons.push('exact_hwnd_focus_validation_unavailable');}
    if(fs.existsSync(path.join(stage,'cpu_gpu.csv'))){
      meta.analysis=analyzeV2Csv(fs.readFileSync(path.join(stage,'cpu_gpu.csv'),'utf8'),pid,chain);
      fs.writeFileSync(path.join(stage,'analysis.json'),JSON.stringify(meta.analysis,null,2));if(!meta.analysis.valid)meta.invalid_reasons.push(...meta.analysis.invalid_reasons);
    }else meta.invalid_reasons.push('v2_csv_unavailable');
    const nativeLogs=['before.log','start.log','after.log'].filter(file=>fs.existsSync(path.join(stage,file))).map(file=>fs.readFileSync(path.join(stage,file),'utf8')).join('\n');
    meta.game_state_validation=shared.gameStateEvidence(nativeLogs,nonce);
    if(!meta.game_state_validation.valid)meta.invalid_reasons.push('game_state_invalid');
    if(!meta.after||meta.after.paused||meta.after.known_lua_profiler_active||meta.after.debug_hook_present)meta.invalid_reasons.push('after_context_unconfirmed_or_instrumented');
    if(meta.presentmon_exit!==0||meta.focus_observer_exit!==0)meta.invalid_reasons.push('owned_child_not_successful');
    if(!meta.focus_validation?.valid)meta.invalid_reasons.push('focus_unconfirmed');
    if(!meta.camera_before||!meta.camera_after)meta.invalid_reasons.push('camera_readbacks_incomplete');
    else meta.camera_delta=Object.fromEntries(['x','y','z'].map(axis=>[axis,meta.camera_after.position[axis]-meta.camera_before.position[axis]]));
    if(failure)meta.invalid_reasons.push('diagnostic_failed');if(meta.cleanup_errors.length)meta.invalid_reasons.push('cleanup_incomplete');
    meta.invalid_reasons=[...new Set(meta.invalid_reasons)];meta.capture_valid=meta.invalid_reasons.length===0;
    meta.evidence_publish_errors=[];
    for(const name of artifacts)if(fs.existsSync(path.join(stage,name)))try{fs.copyFileSync(path.join(stage,name),path.join(target,name),fs.constants.COPYFILE_EXCL);}catch(error){meta.evidence_publish_errors.push({file:name,error:error.message});}
    if(meta.evidence_publish_errors.length){meta.capture_valid=false;meta.invalid_reasons.push('evidence_publish_incomplete');}
    fs.writeFileSync(path.join(target,'capture.json'),JSON.stringify(meta,null,2),{flag:'wx'});
    console.log('CPU_GPU_DIAGNOSTIC_DONE',target,'capture_valid='+meta.capture_valid,'acceptance_sample=false');
  }
  if(failure)throw failure;
  if(!meta.capture_valid)throw Error('Diagnostic invalid: '+meta.invalid_reasons.join(','));
}
if(require.main===module)main().catch(error=>{console.error(shared.redactConsoleOutput(error.message));process.exitCode=1;});
module.exports={analyzeV2Csv,finiteCell,distribution,nativeSnapshot,parseSnapshot,restoreEdge,main};
