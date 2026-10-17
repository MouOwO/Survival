'use strict';
// Opt-in local Workshop measurement. Bots never count as network clients.
const fs=require('node:fs'),path=require('node:path'),os=require('node:os');
const cp=require('node:child_process'),crypto=require('node:crypto');
const {performance}=require('node:perf_hooks');
const {ConsoleSession}=require('./map_c6/console-session.cjs');
const {currentClientProbe,probeJson}=require('./client_callback_report.cjs');
const root=path.resolve(__dirname,'..');
const [action,label='probe',durationText='60',mode='steady']=process.argv.slice(2);
const out=path.join(root,'output/four_client_perf_20261012');
const lua=code=>({name:'dota_run_lua',arguments:{code}});
const cmd=commands=>({name:'console_send',arguments:{commands}});
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
const python='C:/Users/Administrator/AppData/Local/Programs/Python/Python314/python.exe';
const artifactNames=['presents.csv','settings.log','camera.log','before.log','begin.log','native_fps.log','after.log','presentmon.log','focus.json','focus_observer.log','focus_restore.log','vprof.log','session_diagnostic.log','activity.json','ranged.json','acquisition.json','tree_observer.json','client_callbacks.log','client_callbacks.json'];
function parseEdgeMove(output){
  const raw=/^[ \t]*dota_camera_edgemove[ \t]*=[ \t]*"?(0|1|true|false)"?[ \t]*$/mi.exec(String(output))?.[1]?.toLowerCase();
  return raw===undefined?null:{value:raw==='1'||raw==='true'?1:0,command_text:raw};
}
function gameStateGuard(nonce,phase,hard=true){
  if(!/^[0-9a-f]{16}$/.test(nonce)||!['BEFORE','START','AFTER'].includes(phase))throw Error('Invalid native game-state identity');
  return "local rules_available=GameRules~=nil and GameRules.State_Get~=nil;local actual_state=rules_available and GameRules:State_Get() or nil;local expected_state=DOTA_GAMERULES_STATE_GAME_IN_PROGRESS;local game_in_progress=rules_available and type(expected_state)=='number' and actual_state==expected_state;print('[LIVE_GAME_STATE] '..require('core/json_encoder').encode({nonce='"+nonce+"',phase='"+phase+"',rules_available=rules_available,actual_state=actual_state,expected_state=expected_state,post_game_state=DOTA_GAMERULES_STATE_POST_GAME,in_progress=game_in_progress}));"+(hard?"assert(game_in_progress,'game_state_invalid: running native match required');":"");
}
function gameStateEvidence(output,nonce){
  const phases={};
  for(const line of String(output).split(/\r?\n/))if(line.startsWith('[LIVE_GAME_STATE] ')){
    try{const entry=JSON.parse(line.slice('[LIVE_GAME_STATE] '.length));if(entry.nonce===nonce&&['BEFORE','START','AFTER'].includes(entry.phase))phases[entry.phase]=entry;}catch{/* Unknown evidence is never positive evidence. */}
  }
  const validEntry=entry=>entry?.rules_available===true&&entry.in_progress===true&&Number.isInteger(entry.actual_state)&&entry.actual_state>=0&&Number.isInteger(entry.expected_state)&&entry.expected_state>=0&&entry.actual_state===entry.expected_state;
  const entries=['BEFORE','START','AFTER'].map(phase=>phases[phase]);
  return {valid:entries.every(validEntry)&&new Set(entries.map(entry=>entry?.expected_state)).size===1,phases,
    source:'Runtime DOTA_GAMERULES_STATE_GAME_IN_PROGRESS constant; numeric historical values are never assumed'};
}
function parseNativeCamera(output){
  const number='([-+]?(?:\\d+(?:\\.\\d*)?|\\.\\d+)(?:[eE][+-]?\\d+)?)';
  const expression=new RegExp('^Camera look-at position:[ \\t]+'+number+'[ \\t]+'+number+'[ \\t]+'+number+'[ \\t]*$','gm');
  const matches=[...String(output).replace(/\r/g,'').matchAll(expression)];
  if(!matches.length)return null;
  const values=matches[matches.length-1].slice(1).map(Number);
  return values.every(Number.isFinite)?{x:values[0],y:values[1],z:values[2]}:null;
}
async function readCamera(session,nonce,phase,stage){
  if(!/^[0-9a-f]{16}$/.test(nonce)||!['BEFORE','AFTER'].includes(phase))throw Error('Invalid camera readback identity');
  const marker='LIVE_CAMERA_'+phase+'_'+nonce+'_'+crypto.randomBytes(4).toString('hex');
  const response=await session.send([cmd('dota_camera_edgemove\ndota_camera_get_lookatpos\necho '+marker)],marker,100);
  fs.appendFileSync(path.join(stage,'camera.log'),'[CAMERA_'+phase+'] expected_ack='+marker+'\n'+response.output+'\n');
  const position=parseNativeCamera(response.output),edgeMove=parseEdgeMove(response.output);
  if(!position||!edgeMove||edgeMove.value!==0)throw Error('Native camera readback/disabled edge-move not confirmed; see camera.log');
  return {acknowledged:true,valid:true,marker,phase,position,edge_move:edgeMove.value,scope:'actual native camera getter; no setter is executed by this readback'};
}
function redactConsoleOutput(value){
  const redact=(_match,prefix)=>prefix+'"[REDACTED]"';
  return String(value)
    .replace(/(\b(?:server_key|tv_secret_code|auth_token|access_token)\b["']?[ \t]*(?:=|:|changed[ \t]+to|is|value[ \t]+is)[ \t]*)("(?:\\.|[^"\\\r\n])*"|'(?:\\.|[^'\\\r\n])*'|[^ \t\r\n,}]+)/gi,redact)
    .replace(/(\b(?:server_key|tv_secret_code|auth_token|access_token)\b["']?[ \t]+)(?![=:]|changed\b|is\b|value\b)("(?:\\.|[^"\\\r\n])*"|'(?:\\.|[^'\\\r\n])*'|[^ \t\r\n,}]+)/gi,redact);
}
function restoreWindowValid(value,pid){
  return value?.pid===pid&&value.foreground===true&&value.selection_unique===true&&value.title==='Dota 2'
    &&value.visible===true&&value.iconic===false&&value.client_rect_valid===true&&value.cursor_centered===true
    &&Number.isSafeInteger(value.target_hwnd)&&value.target_hwnd>0
    &&Number.isInteger(value.client_width)&&value.client_width>=640&&Number.isInteger(value.client_height)&&value.client_height>=360;
}
function csvRows(text){
  const rows=[];let row=[],field='',quoted=false,afterQuote=false;
  for(let i=0;i<text.length;i++){
    const c=text[i];
    if(quoted){if(c==='"'){if(text[i+1]==='"'){field+='"';i++;}else{quoted=false;afterQuote=true;}}else field+=c;continue;}
    if(c==='"'){if(field.length||afterQuote)throw Error('CSV quote outside field');quoted=true;continue;}
    if(c===','||c==='\n'||c==='\r'){
      row.push(field);field='';afterQuote=false;
      if(c!==','){if(c==='\r'&&text[i+1]==='\n')i++;if(row.some(x=>x.length))rows.push(row);row=[];}
    }else{if(afterQuote)throw Error('CSV trailing text after quote');field+=c;}
  }
  if(quoted)throw Error('CSV unterminated quote');
  if(field.length||row.length){row.push(field);if(row.some(x=>x.length))rows.push(row);}
  return rows;
}
function validatePresentCsv(text,pid,seconds,requestedSwapchain=null){
  const reasons=[],groups=new Map();let rows;
  const minimumSpan=seconds-Math.max(1.25,seconds*.02);
  const result={valid:false,invalid_reasons:reasons,requested_process_id:pid,
    requested_swapchain_address:requestedSwapchain,minimum_accepted_span_seconds:minimumSpan,
    selected_swapchain_address:null,selection_strategy:null,primary:null,groups:[],discarded_ungrouped_rows:0,
    maximum_accepted_span_seconds:seconds+Math.max(1.25,seconds*.02)};
  try{rows=csvRows(String(text).replace(/^\uFEFF/,''));}catch(e){reasons.push('csv_parse_error: '+e.message);return result;}
  if(!rows.length){reasons.push('csv_empty');return result;}
  const header=rows.shift().map(x=>x.trim()),native=header.filter(x=>x==='MsBetweenPresents'||x==='msBetweenPresents');
  const required=['ProcessID','SwapChainAddress','TimeInSeconds'];
  if(new Set(header).size!==header.length||native.length!==1||required.some(x=>!header.includes(x))){reasons.push('csv_native_header_invalid');return result;}
  result.canonical_to_native_columns={MsBetweenPresents:native[0]};
  const indexes=Object.fromEntries([...required,native[0]].map(x=>[x,header.indexOf(x)]));
  for(const row of rows){
    if(row.length!==header.length){result.discarded_ungrouped_rows++;continue;}
    const identity=row[indexes.ProcessID].trim(),chain=row[indexes.SwapChainAddress].trim().toLowerCase();
    if(!/^[0-9]+$/.test(identity)||Number(identity)<=0||!chain){result.discarded_ungrouped_rows++;continue;}
    if(Number(identity)!==pid)continue;
    let group=groups.get(chain);
    if(!group){group={process_id:pid,swapchain_address:chain,observed_present_rows:0,accepted_interval_count:0,
      discarded_invalid_rows:0,accepted_interval_sum_seconds:0,first_timestamp_seconds:null,last_timestamp_seconds:null};groups.set(chain,group);}
    group.observed_present_rows++;
    const rawTime=row[indexes.TimeInSeconds].trim(),timestamp=rawTime?Number(rawTime):NaN;
    if(!Number.isFinite(timestamp)||timestamp<0||(group.last_timestamp_seconds!==null&&timestamp<=group.last_timestamp_seconds)){group.discarded_invalid_rows++;continue;}
    if(group.observed_present_rows===1)group.first_timestamp_seconds=timestamp;
    group.last_timestamp_seconds=timestamp;
    if(group.observed_present_rows===1)continue; // Interval before the first captured present is never counted.
    const rawInterval=row[indexes[native[0]]].trim(),interval=rawInterval?Number(rawInterval):NaN;
    if(!Number.isFinite(interval)||interval<=0){group.discarded_invalid_rows++;continue;}
    group.accepted_interval_count++;group.accepted_interval_sum_seconds+=interval/1000;
  }
  result.groups=[...groups.values()].map(g=>({...g,timestamp_span_seconds:g.first_timestamp_seconds===null?null:g.last_timestamp_seconds-g.first_timestamp_seconds,
    mean_present_fps:g.accepted_interval_sum_seconds?g.accepted_interval_count/g.accepted_interval_sum_seconds:null}));
  const usable=result.groups.filter(g=>g.accepted_interval_count>0);
  let primary;
  if(requestedSwapchain){primary=usable.find(g=>g.swapchain_address===requestedSwapchain.toLowerCase());result.selection_strategy='explicit_swapchain';}
  else{primary=usable.sort((a,b)=>b.accepted_interval_count-a.accepted_interval_count||b.accepted_interval_sum_seconds-a.accepted_interval_sum_seconds||a.swapchain_address.localeCompare(b.swapchain_address))[0];result.selection_strategy='most_intervals_recorded_heuristic';if(usable.length>1)reasons.push('multiple_usable_swapchains_require_explicit_selection');}
  result.primary=primary||null;result.selected_swapchain_address=primary?.swapchain_address||null;
  if(result.discarded_ungrouped_rows)reasons.push('csv_malformed_or_unidentifiable_rows');
  if(!primary){reasons.push('csv_no_requested_usable_swapchain');return result;}
  if(primary.discarded_invalid_rows)reasons.push('csv_selected_swapchain_invalid_rows');
  if(primary.timestamp_span_seconds===null||primary.timestamp_span_seconds<minimumSpan)reasons.push('csv_capture_span_too_short');
  if(primary.timestamp_span_seconds>result.maximum_accepted_span_seconds)reasons.push('csv_capture_span_too_long');
  if(primary.accepted_interval_sum_seconds<minimumSpan)reasons.push('csv_positive_interval_sum_too_short');
  if(primary.timestamp_span_seconds!==null&&Math.abs(primary.accepted_interval_sum_seconds-primary.timestamp_span_seconds)>Math.max(.001,primary.timestamp_span_seconds*.001))reasons.push('csv_interval_sum_timestamp_span_mismatch');
  result.valid=reasons.length===0;
  return result;
}
function watchChild(child){
  const record={child,closed:false,fatalError:null,code:null,signal:null,stdout:'',stderr:''};
  child.stdout?.on('data',b=>record.stdout+=b);child.stderr?.on('data',b=>record.stderr+=b);
  record.done=new Promise(resolve=>{
    child.once('error',error=>{record.fatalError=error;resolve(record);}); // Never create a delayed unhandled rejection.
    child.once('close',(code,signal)=>{record.closed=true;record.code=code;record.signal=signal;resolve(record);});
  });
  record.closeDone=new Promise(resolve=>child.once('close',()=>resolve(record)));
  return record;
}
async function boundedWait(promise,milliseconds,message){
  let timer;try{return await Promise.race([promise,new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error(message)),milliseconds);})]);}finally{clearTimeout(timer);}
}
function assessAcceptance(meta){
  const reasons=[];
  if(meta.diagnostic_instrumentation||meta.client_callback_probe)reasons.push('diagnostic_instrumentation_enabled');
  if(meta.presentmon_exit!==0)reasons.push('presentmon_not_successful');
  if(meta.focus_observer_exit!==0)reasons.push('focus_observer_not_successful');
  if(meta.focus_restore_exit!==0)reasons.push('foreground_restore_not_successful');
  if(!meta.csv_validation?.valid)reasons.push(...(meta.csv_validation?.invalid_reasons||['csv_evidence_unavailable']));
  if(!meta.focus_validation?.valid)reasons.push(...(meta.focus_validation?.invalid_reasons||['focus_evidence_unavailable']));
  if(!meta.focus_csv_overlap?.valid)reasons.push(...(meta.focus_csv_overlap?.invalid_reasons||['focus_csv_timeline_unavailable']));
  if(!meta.snapshots_valid)reasons.push('before_after_snapshot_not_validated');
  if(!meta.game_state_valid)reasons.push('game_state_invalid');
  if(!meta.exact_window_match)reasons.push('real_game_window_identity_not_confirmed');
  if(!meta.camera_readbacks?.before?.acknowledged||!meta.camera_readbacks?.after?.acknowledged||!meta.camera_readbacks.before.valid||!meta.camera_readbacks.after.valid)reasons.push('native_camera_readback_not_acknowledged');
  if(meta.failure)reasons.push('sampler_failed');
  if(meta.cleanup_errors?.length)reasons.push('sampler_cleanup_incomplete');
  return {valid:reasons.length===0,invalid_reasons:[...new Set(reasons)]};
}
function focusCsvOverlap(focus,csv,spawnUnix){
  const p=csv?.primary,tolerance=1.25,result={valid:false,invalid_reasons:[],alignment_tolerance_seconds:tolerance,
    note:'CSV TimeInSeconds is aligned to PresentMon process start approximately; process startup uncertainty and one-Hz observations remain.'};
  if(!p||!Number.isFinite(p.first_timestamp_seconds)||!Number.isFinite(p.last_timestamp_seconds)||!Number.isFinite(spawnUnix)||!Number.isFinite(focus?.observation_start_unix_seconds)||!Number.isFinite(focus?.observation_end_unix_seconds)){result.invalid_reasons.push('focus_csv_timeline_unavailable');return result;}
  result.approximate_first_present_unix_seconds=spawnUnix+p.first_timestamp_seconds;
  result.approximate_last_present_unix_seconds=spawnUnix+p.last_timestamp_seconds;
  result.observation_start_unix_seconds=focus.observation_start_unix_seconds;result.observation_end_unix_seconds=focus.observation_end_unix_seconds;
  if(result.observation_start_unix_seconds>result.approximate_first_present_unix_seconds+tolerance||result.observation_end_unix_seconds<result.approximate_last_present_unix_seconds-tolerance)result.invalid_reasons.push('focus_observer_did_not_cover_csv_window');
  result.valid=result.invalid_reasons.length===0;return result;
}
function terminateOwnedSession(executable,args){
  return new Promise((resolve,reject)=>cp.execFile(executable,args,{windowsHide:true,timeout:5000},(error,stdout,stderr)=>{
    if(error){error.message+=' '+String(stderr||stdout).trim();reject(error);}else resolve({stdout,stderr});
  }));
}
async function cleanupSampler(state,session,dependencies={}){
  if(state.cleanupDone)return state.cleanupErrors;
  state.cleanupDone=true;state.cleanupErrors=[];
  const attempt=async(name,fn)=>{try{await fn();}catch(error){state.cleanupErrors.push({step:name,error:error.message});}};
  const pm=state.presentmon,interrupted=pm&&pm.child.pid&&(!pm.closed||pm.code!==0);
  state.etwTerminationStatus=pm?.child.pid?'not_needed_normal_exit':'not_started';
  if(interrupted&&state.presentmonPath){
    await attempt('owned_etw_session_stop',async()=>{
      state.etwTerminationStatus='failed';
      if(!/^[0-9a-f]{16}$/.test(state.nonce)||state.meta?.session_name!=='SurvivalLive_'+state.nonce)throw Error('Independent session identity invalid; termination skipped');
      const terminate=dependencies.terminateSession||terminateOwnedSession;
      await terminate(state.presentmonPath,['--session_name',state.meta.session_name,'--terminate_existing_session']);
      state.etwTerminationStatus='terminated';
      // Give the consumer a short chance to flush its CSV after its own ETW session ends.
      if(!pm.closed)try{await boundedWait(pm.closeDone,1500,'Own PresentMon consumer flush timed out');}catch{/* The owned child is killed below. */}
    });
  }
  // Stop our own children before any console/file work, even on partial startup.
  for(const [name,record] of [['presentmon',state.presentmon],['focus_observer',state.focus]])if(record&&!record.closed&&record.child.pid){
    await attempt(name+'_child_stop',async()=>{record.child.kill();await boundedWait(record.closeDone,5000,name+' child did not exit');});
  }
  if(state.activityStarted||state.luaProfileStarted){
    const parts=[];
    if(state.activityStarted)parts.push("local a=package.loaded['tests/manual_four_player_activity'];if a then a.stop('capture_cleanup') end");
    if(state.luaProfileStarted)parts.push("local a=package.loaded['tests/manual_extreme_profile'];if a then a.stop('capture_cleanup') end;local b=package.loaded['core/scheduler_profile'];if b then b.stop('capture_cleanup') end");
    const body="local g=_G.SURVIVAL_LIVE_SAMPLER_OWNERSHIP;if g and g.nonce=='"+state.nonce+"' then if GameRules and GameRules.GetGameModeEntity and g.mode==GameRules:GetGameModeEntity() then "+parts.join(';')+" end;_G.SURVIVAL_LIVE_SAMPLER_OWNERSHIP=nil end;print('LIVE_OWNED_CLEAN_"+state.nonce+"')";
    await attempt('owned_lua_operations_stop',()=>session.send([lua(body)],'LIVE_OWNED_CLEAN_'+state.nonce,100));
  }
  if(state.vprofStarted)await attempt('owned_vprof_stop',()=>session.send([cmd('vprof_off')],'',100));
  if(state.clientProbeStarted)await attempt('owned_client_probe_stop',async()=>{
    if(state.probeSerial===null||state.readClientProbe().commandId!==state.probeBinding.commandId)throw Error('Probe capture ownership unavailable/context changed; stop skipped');
    const nonce=crypto.randomBytes(12).toString('hex');
    const response=await session.send([cmd(state.probeBinding.commands.report+' '+nonce)],'',100,{responsePrefix:'[CLIENT_CALLBACK_PROBE] {'});
    if(!probeJson(response.output,'report',{nonce,commandId:state.probeBinding.commandId,captureSerial:state.probeSerial}))throw Error('Probe serial changed/unconfirmed; stop skipped');
    await session.send([cmd(state.probeBinding.commands.stop)],'',100);
  });
  if(state.settingsChanged)await attempt('owned_settings_restore',()=>{
    if(!/^(?:0|1|true|false)$/.test(state.oldEdgeMoveText))throw Error('Original edge-move value unconfirmed; unsafe restore skipped');
    return session.send([cmd('cl_showfps '+state.oldFps+'\nhost_timescale '+state.oldTimescale+'\ndota_camera_edgemove '+state.oldEdgeMoveText)],'',100);
  });
  return state.cleanupErrors;
}
function publishEvidence(state,meta){
  const errors=[];
  for(const name of artifactNames)if(fs.existsSync(path.join(state.stage,name)))try{fs.copyFileSync(path.join(state.stage,name),path.join(state.target,name),fs.constants.COPYFILE_EXCL);}catch(error){errors.push({file:name,error:error.message});}
  meta.evidence_publish_errors=errors;
  if(errors.length){meta.capture_valid=false;meta.acceptance_sample=false;meta.invalid_reasons=[...new Set([...(meta.invalid_reasons||[]),'evidence_publish_incomplete'])];}
  fs.writeFileSync(path.join(state.target,'capture.json'),JSON.stringify(meta,null,2),{flag:'wx'});
  return errors;
}
function reserveEvidenceDirectory(base,label){
  if(!/^[a-z0-9_]+$/.test(label))throw Error('Invalid evidence label');
  fs.mkdirSync(base,{recursive:true});const target=path.join(base,label);fs.mkdirSync(target);return target;
}
function chunkReport(expression,marker){
  return lua("local function safe(v) if type(v)~='table' then return v end;local n,max,array=0,0,true;for k in pairs(v) do n=n+1;if type(k)~='number' or k<1 or k~=math.floor(k) then array=false else max=math.max(max,k) end end;array=array and max==n;local r={};for k,x in pairs(v) do r[array and k or tostring(k)]=safe(x) end;return r end;local encoded=require('core/json_encoder').encode(safe("+expression+"));local first,index=1,0;while first<=#encoded do local last=math.min(#encoded,first+1199);while last<#encoded and encoded:byte(last+1)>=128 and encoded:byte(last+1)<=191 do last=last-1 end;index=index+1;print('[LIVE_REPORT_CHUNK] '..require('core/json_encoder').encode({index=index,data=encoded:sub(first,last)}));first=last+1 end;print('\\n"+marker+"')");
}
function decodeReport(output){
  const chunks=output.split(/\r?\n/).filter(line=>line.startsWith('[LIVE_REPORT_CHUNK] ')).map(line=>JSON.parse(line.slice('[LIVE_REPORT_CHUNK] '.length)));
  if(!chunks.length||chunks.some((c,i)=>c.index!==i+1))throw Error('Report chunks incomplete');
  return JSON.parse(chunks.map(c=>c.data).join(''));
}
async function main(){
  const session=new ConsoleSession({timeoutMs:15000,historyTimeoutMs:60000});
  const state={};let failure=null;
  try{
    await session.connect();
    if(action!=='sample'){
      if(['reload','stresssettings','normalspeed'].includes(action)){
        const commands={reload:'dota_launch_custom_game survival template_map',stresssettings:'dota_bot_disable 1\ndota_bot_force_pick npc_dota_hero_undying\ndota_bot_populate\nsv_stressbots 1\nhost_timescale 8\nengine_no_focus_sleep 0\ndota_video_config.setting.fullscreen_min_on_focus_loss 0\nr_always_render_all_windows 1',normalspeed:'host_timescale 1\ndota_camera_distance 1600\ndota_camera_set_lookatpos 1280 4992'}[action];
        const setupAck='LIVE_SETUP_'+action.toUpperCase()+'_'+crypto.randomBytes(8).toString('hex');
        const verify=action==='normalspeed'?'\nhost_timescale\ndota_camera_get_lookatpos':'';
        const response=await session.send([cmd(commands+verify+'\necho '+setupAck)],setupAck,250);
        fs.mkdirSync(out,{recursive:true});fs.writeFileSync(path.join(out,action+'_'+label+'.log'),response.output);
        if(action==='normalspeed'&&(!/^host_timescale\s*=\s*1\s*$/m.test(response.output.replace(/\r/g,''))||!parseNativeCamera(response.output)))throw Error('Normal-speed setup readback not confirmed');
        process.stdout.write(redactConsoleOutput(response.output));return;
      }
      const body={
        probe:"local t={map=GetMapName(),state=GameRules:State_Get(),paused=GameRules:IsGamePaused(),mode=require('systems/match_setup_service').get_mode(),gameplay_ready=require('systems/startup_loading_service').is_gameplay_ready(),players={}};for id=0,3 do t.players[#t.players+1]={id=id,valid=PlayerResource:IsValidPlayerID(id),player=PlayerResource:GetPlayer(id)~=nil,hero=PlayerResource:GetSelectedHeroEntity(id)~=nil,fake=PlayerResource:IsFakeClient(id)} end;print('[LIVE_ENV] '..require('core/json_encoder').encode(t))",
        heroes:"for id=0,3 do local p=PlayerResource:GetPlayer(id);print('[LIVE_PLAYER] id='..id..' team='..PlayerResource:GetTeam(id)..' defeated='..tostring(require('systems/multiplayer_player_service').is_defeated(id))..' selected='..tostring(PlayerResource:GetSelectedHeroEntity(id))..' assigned='..tostring(p and p:GetAssignedHero())) end;for _,h in ipairs(HeroList:GetAllHeroes()) do print('[LIVE_HERO] name='..h:GetUnitName()..' index='..h:entindex()..' owner='..h:GetPlayerOwnerID()..' alive='..tostring(h:IsAlive())) end",
        bindprobe:"local p=assert(PlayerResource:GetPlayer(1));for _,name in ipairs({'SetAssignedHeroEntity','SetAssignedHero','SetSelectedHeroEntity','SetSelectedHero'}) do print('[LIVE_BIND_API] '..name..' player='..type(p[name])..' resource='..type(PlayerResource[name])) end",
        recover:"package.loaded['tests/manual_four_player_live_perf']=nil;require('tests/manual_four_player_live_perf').recover_ready()",
        camera:"local s=assert(_G.SURVIVAL_REAL_GAME_STRESS);local w=assert(s.players[1].units.wall);local p=w:GetAbsOrigin();print('[LIVE_CAMERA] '..p.x..' '..p.y)",
        ownership:"local b=require('core/event_bus');local e=require('core/events');local c=require('systems/player_context_service');for id=0,3 do for _,r in ipairs((b.request(e.BUILDING_LIST_REQUEST,{player_id=id}) or {}).buildings or {}) do local u=r.unit;local q=b.request(e.BUILDING_QUERY_REQUEST,{entindex=u:entindex(),read_only=true});print('[LIVE_OWNERSHIP] listed='..id..' kind='..tostring(r.building_id)..' row='..tostring(r.player_id)..' query='..tostring(q and q.player_id)..' native='..tostring(u:GetPlayerOwnerID())..' context='..tostring(c.is_owned_by(id,u))) end end",
        foreground:"print('[LIVE_ENGINE_FOREGROUND] active='..tostring(IsClient and IsClient()))",
        repairlinks:"for _,n in ipairs({'modifier_tower_projectile_speed','modifier_tower_fixed_facing'}) do require('modifiers/'..n);LinkLuaModifier(n,'modifiers/'..n,LUA_MODIFIER_MOTION_NONE) end;local b=require('core/event_bus');local e=require('core/events');for _,r in ipairs((b.request(e.BUILDING_LIST_REQUEST,{building_id='arrow_tower',handles_only=true}) or {}).buildings or {}) do local u=r.unit;local target=require('systems/tower_projectile_speed').apply(u,u.survival_base_projectile_speed,u.survival_tower_class);require('systems/tower_fixed_facing').apply(u,u.survival_tower_class);assert(u:HasModifier('modifier_tower_projectile_speed'));assert(math.abs(u:GetProjectileSpeed()-target)<0.01,'Native projectile speed mismatch');print('[LIVE_PROJECTILE_VERIFIED] id='..r.player_id..' unit='..u:entindex()..' speed='..u:GetProjectileSpeed()) end",
        census:"local o=require('systems/enemy_attack_observer');local r={units=0,modifiers={},enemy_ai={shared_attack=0,legacy_attack=0,shared_death=0,legacy_death=0,ranged=0,melee=0,states={}},attack_observer_ready=o.is_ready(),death_observer_ready=o.can_route_death()};for _,u in ipairs(Entities:FindAllByClassname('npc_dota_creature') or {}) do r.units=r.units+1;for _,m in ipairs(u:FindAllModifiers() or {}) do local n=m:GetName();r.modifiers[n]=(r.modifiers[n] or 0)+1;if n=='modifier_enemy_wall_ai' then local a=r.enemy_ai;a[m.shared_attack_observer and 'shared_attack' or 'legacy_attack']=a[m.shared_attack_observer and 'shared_attack' or 'legacy_attack']+1;a[m.shared_death_observer and 'shared_death' or 'legacy_death']=a[m.shared_death_observer and 'shared_death' or 'legacy_death']+1;a[u:GetAttackCapability()==DOTA_UNIT_CAP_RANGED_ATTACK and 'ranged' or 'melee']=a[u:GetAttackCapability()==DOTA_UNIT_CAP_RANGED_ATTACK and 'ranged' or 'melee']+1;local s=tostring(m.ai_state);a.states[s]=(a.states[s] or 0)+1 end end end;print('[LIVE_CENSUS] '..require('core/json_encoder').encode(r))",
        isolate:"require('tests/manual_real_game_stress').isolate_writes();require('core/scheduler').cancel('player_unbuilt_wall_defeat')",
        difficultyN2:"assert(IsInToolsMode() and GetMapName()=='template_map');assert(require('systems/wave_system').set_difficulty('N2'));print('[LIVE_SETUP] difficulty=N2 public_wave_setter=1 tools_fixture_setup=1')",
        bots:"assert(IsInToolsMode());for id=1,3 do assert(PlayerResource:IsFakeClient(id));local p=assert(PlayerResource:GetPlayer(id));local h=PlayerResource:GetSelectedHeroEntity(id);if not h then for _,u in ipairs(HeroList:GetAllHeroes()) do if u:GetPlayerOwnerID()==id and u:GetUnitName()=='npc_dota_hero_undying' and u:IsAlive() then h=u;break end end;h=h or CreateHeroForPlayer('npc_dota_hero_undying',p);p:SetAssignedHeroEntity(h) end;assert(h and h:GetPlayerOwnerID()==id and PlayerResource:GetSelectedHeroEntity(id)==h,'Native bot binding unavailable '..id);print('[LIVE_BOT_HERO] id='..id..' entindex='..h:entindex()) end",
        prepare:"require('tests/manual_four_player_live_perf').prepare('"+label+"',{research_levels=1,sr_stage_level=1,benchmark_keep_towers_alive=true})",
        prepareactive:"require('tests/manual_four_player_live_perf').prepare_activity_fixture('"+label+"',{research_levels=1,sr_stage_level=1,benchmark_keep_towers_alive=true})",
        activityprepare:"require('tests/manual_four_player_activity').prepare({seed=731,duration_seconds=150,trace_limit=512,observe_hero_completion="+(process.env.LIVE_HERO_OBSERVE==='1'?'true':'false')+"});print('[LIVE_ACTIVITY] prepared seed=731 normal_resource_debits=1 duration=150')",
        activitystop:"require('tests/manual_four_player_activity').stop('manual')",
        activitydrain:"local r=require('tests/manual_four_player_activity').drain_offers();print('[LIVE_ACTIVITY_DRAIN] '..require('core/json_encoder').encode(r))",
        rangedon:"local p=require('systems/enemy_ranged_stationary');assert(p.set_probe_enabled(true));p.reset_counters();print('[LIVE_RANGED] candidate=on current_tools_world_only=1')",
        rangedoff:"assert(require('systems/enemy_ranged_stationary').set_probe_enabled(false));print('[LIVE_RANGED] candidate=off releases_on_normal_think=1')",
        acquireon:"local r=require('tests/manual_wave_acquisition_probe').enable({zero_acquisition=false});print('[LIVE_ACQUIRE] idle_acquire_false=1 zero_acquisition=0')",
        acquirezero:"local r=require('tests/manual_wave_acquisition_probe').enable({zero_acquisition=true});print('[LIVE_ACQUIRE] idle_acquire_false=1 zero_acquisition=1')",
        acquireoff:"require('tests/manual_wave_acquisition_probe').stop('manual');print('[LIVE_ACQUIRE] hook_stopped=1 reload_map_to_restore_units=1')",
        treeon:"local r=require('systems/tree_attack_observer').enable_probe();assert(r.ok and r.carrier_ready);print('[LIVE_TREE] enabled_before_new_tree_modifiers=1')",
        treeoff:"require('systems/tree_attack_observer').disable_probe();print('[LIVE_TREE] future_registration_off=1 existing_routes_retained=1 reload_to_restore=1')",
        treecensus:"local r={};for _,u in ipairs(Entities:FindAllByClassname('npc_dota_creature')) do local m=u:FindModifierByName('modifier_tree_progression');if m then r[#r+1]={unit=u:entindex(),owner=u.survival_tree_owner_id,callback=type(u.survival_tree_depleted_callback),shared=m.shared_tree_observer,reason=m.survival_tree_event_decl_reason,declaration_calls=m.survival_tree_declaration_calls,before_created=m.survival_tree_declaration_calls_before_created,after_created=m.survival_tree_declaration_calls_after_created} end end;print('[LIVE_TREE_CENSUS] '..require('core/json_encoder').encode(r))",
        roguedeclon:"assert(IsInToolsMode());local g=assert(_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION);assert(g.mode==GameRules:GetGameModeEntity());_G.SURVIVAL_ROGUE_COMBAT_DAMAGE_DECL_PROBE={enabled=true,mode=g.mode,guard=g};print('[LIVE_ROGUE_DECL] new_instances_only=1 default_off=1')",
        declareon:"assert(require('tests/manual_modifier_declaration_probe').start(20));print('[LIVE_DECLARATION] real_lifecycle_probe_started=1 bounded_seconds=20')",
        declareoff:"require('tests/manual_modifier_declaration_probe').stop('manual')",
        stageoog:"assert(IsInToolsMode());local g=assert(_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION);assert(g.mode==GameRules:GetGameModeEntity());_G.SURVIVAL_CHALLENGE_STAGING_PROBE={mode=g.mode,guard=g,out_of_game=true,pause_health_bar=false};print('[LIVE_STAGE] out_of_game=1 pause_health_bar=0 new_formal_staging_only=1')",
        stagehealth:"assert(IsInToolsMode());local g=assert(_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION);assert(g.mode==GameRules:GetGameModeEntity());_G.SURVIVAL_CHALLENGE_STAGING_PROBE={mode=g.mode,guard=g,out_of_game=false,pause_health_bar=true};print('[LIVE_STAGE] out_of_game=0 pause_health_bar=1 new_formal_staging_only=1')",
        status:"require('tests/manual_four_player_live_perf').status()",
        wave:"require('tests/manual_four_player_live_perf').spawn_wave(15)",
        hold:"require('tests/manual_four_player_live_perf').hold_tower_attacks(true)",
        release:"require('tests/manual_four_player_live_perf').hold_tower_attacks(false)",
        stop:"local a=package.loaded['tests/manual_four_player_activity'];if a then a.stop('fixture_stop') end;require('tests/manual_four_player_live_perf').stop()",
      }[action];
      const ack='LIVE_ACTION_'+crypto.randomBytes(8).toString('hex');
      if(['activityreport','rangedreport','acquirereport','rangedcoverage','treereport','declarereport'].includes(action)){
        const expression=action==='activityreport'?"require('tests/manual_four_player_activity').report({include_trace=true,include_plan=true})":action==='acquirereport'?"require('tests/manual_wave_acquisition_probe').snapshot()":action==='rangedcoverage'?"(function() package.loaded['tests/manual_ranged_coverage']=nil;return require('tests/manual_ranged_coverage').snapshot() end)()":action==='treereport'?"require('systems/tree_attack_observer').snapshot()":action==='declarereport'?"require('tests/manual_modifier_declaration_probe').snapshot()":"require('systems/enemy_ranged_stationary').snapshot()";
        const response=await session.send([chunkReport(expression,ack)],ack,100);
        fs.mkdirSync(out,{recursive:true});const report=decodeReport(response.output);fs.writeFileSync(path.join(out,action.replace('report','')+'_'+label+'.json'),JSON.stringify(report,null,2));
        if(['acquirereport','rangedcoverage','treereport'].includes(action)){console.log(redactConsoleOutput(JSON.stringify(report)));return;}
        if(action==='declarereport'){console.log(redactConsoleOutput(JSON.stringify({active:report.active,classes:report.classes?.map(x=>({name:x.name,declarations:x.declarations,callbacks:x.callbacks}))})));return;}
        console.log(redactConsoleOutput(JSON.stringify(action==='rangedreport'?{enabled:report.enabled,entered:report.entered,active:report.active_holds,start_held:report.attack_start_held,landed_held:report.attack_landed_held,reasons:report.reasons}:{status:report.status,seed:report.seed,owners:report.owners?.map(x=>({id:x.player_id,steps:x.steps,planned:x.planned_steps,unexecuted:x.unexecuted_steps,counts:x.counts}))})));return;
      }
      if(!body||['prepare','prepareactive'].includes(action)&&!['A','B'].includes(label))throw Error('Invalid action');
      const response=await session.send([lua(body+";print('\\n"+ack+"')")],ack,100);
      fs.mkdirSync(out,{recursive:true});
      fs.writeFileSync(path.join(out,action+'_'+label+'.log'),response.output);
      process.stdout.write(redactConsoleOutput(response.output));
      return;
    }
    const seconds=Number(durationText),pid=Number(process.env.LIVE_PERF_PID);
    if(!/^[a-z0-9_]+$/.test(label)||!Number.isInteger(seconds)||seconds<30||seconds>120||!Number.isInteger(pid)||pid<=0||!['steady','wave','release'].includes(mode))throw Error('sample requires label, 30..120 seconds, steady|wave|release and LIVE_PERF_PID');
    const nonce=crypto.randomBytes(8).toString('hex');
    // Exclusive reservation: a repeated label must never destroy earlier evidence.
    const target=reserveEvidenceDirectory(out,label);
    Object.assign(state,{isSample:true,nonce,target,stage:fs.mkdtempSync(path.join(os.tmpdir(),'survival_live_perf_')),pid,seconds});
    const stage=state.stage,pmCsv=path.join(stage,'presents.csv'),pm=path.join(out,'bin/PresentMon-2.6.0-x64.exe');
    state.presentmonPath=pm;
    const diagnostic=process.env.LIVE_PROFILE==='1',activeOperations=process.env.LIVE_ACTIVITY==='1';
    const rangedCandidate=process.env.LIVE_RANGED==='1',acquisitionCandidate=process.env.LIVE_ACQUIRE==='1';
    const treeCandidate=process.env.LIVE_TREE==='1',clientProbe=process.env.LIVE_CLIENT_PROBE==='1';
    const probeNonce=crypto.randomBytes(12).toString('hex');
    state.probeSerial=null;
    state.readClientProbe=()=>currentClientProbe(fs.readFileSync(path.resolve(root,'../../dota/console.log'),'utf8'));
    state.meta={label,mode,active_operations:activeOperations,activity_seed:activeOperations?731:null,
      ranged_candidate:rangedCandidate,acquisition_candidate:acquisitionCandidate,tree_candidate:treeCandidate,
      client_callback_probe:clientProbe,diagnostic_instrumentation:diagnostic,acceptance_sample:false,
      requested_seconds:seconds,presentmon_delay_seconds:8,pid,scope:'one_rendered_client_four_engine_owners',
      network_clients_claimed:false,stage,session_name:'SurvivalLive_'+nonce,existing_frameview_session_preserved:true,
      externally_enabled_candidates_cleanup:'ranged/acquisition/tree candidates are not sampler-owned; fresh map restores existing units',
      native_fps_note:'cl_printfps includes the 8-second ETW delay and console tail; use native CSV intervals for formal FPS',
      focus_note:'Once-per-second foreground checks do not prove continuous focus between observations'};
    if(!fs.existsSync(pm))throw Error('PresentMon unavailable');
    if(diagnostic)await session.send([lua("require('tests/manual_extreme_profile');require('core/scheduler_profile');print('LIVE_PROFILE_READY_"+nonce+"')")],'LIVE_PROFILE_READY_'+nonce,100);
    const snapshot=phase=>lua("assert(IsInToolsMode() and GetMapName()=='template_map');"+gameStateGuard(nonce,phase,phase==='BEFORE')+"local s={phase='"+phase+"',state=actual_state,expected_game_state=expected_state,in_progress=game_in_progress,game_rules_available=rules_available,owners={}};if game_in_progress then assert(not GameRules:IsGamePaused());s.game_time=GameRules:GetGameTime();s.engine_time=Time();s.paused=GameRules:IsGamePaused();local b=require('core/event_bus');local e=require('core/events');local f=_G.SURVIVAL_FOUR_PLAYER_LIVE_PERF;if f then s.fixture_status=f.status;s.scenario=f.scenario;for id=0,3 do local p=require('systems/player_profile_service').get_profile(id);local counts={};for _,r in ipairs((b.request(e.BUILDING_LIST_REQUEST,{player_id=id,handles_only=true}) or {}).buildings or {}) do counts[r.building_id]=(counts[r.building_id] or 0)+1 end;s.owners[#s.owners+1]={id=id,fake=PlayerResource:IsFakeClient(id),map_level=p and p.save and p.save.gameplay_stats.map_level,counts=counts,research=(b.request(e.RESEARCH_STATE_GET_REQUEST,{player_id=id}) or {}).levels} end end;s.wave=b.request(e.WAVE_STATE_GET_REQUEST,{}) or {} end;print('[LIVE_SNAPSHOT] '..require('core/json_encoder').encode(s));print('\\nLIVE_"+phase+'_'+nonce+"')");
    const before=snapshot('BEFORE'),after=snapshot('AFTER');
    let startBody=gameStateGuard(nonce,'START')+"assert(not GameRules:IsGamePaused());";
    if(activeOperations||diagnostic)startBody+="_G.SURVIVAL_LIVE_SAMPLER_OWNERSHIP={nonce='"+nonce+"',mode=GameRules:GetGameModeEntity()};";
    if(mode==='wave')startBody+="require('tests/manual_four_player_live_perf').spawn_wave(15);";
    if(mode==='release')startBody+="require('tests/manual_four_player_live_perf').hold_tower_attacks(false);";
    if(activeOperations)startBody+="assert(require('tests/manual_four_player_activity').start().ok);";
    if(rangedCandidate)startBody+="local r=require('systems/enemy_ranged_stationary');assert(r.enabled(),'Enable ranged candidate before spawning');r.reset_counters();";
    if(acquisitionCandidate)startBody+="assert(require('tests/manual_wave_acquisition_probe').snapshot().enabled,'Enable acquisition candidate before spawning');";
    if(treeCandidate)startBody+="assert(require('systems/tree_attack_observer').snapshot().registered_trees==4,'Shared tree candidate did not cover all four trees');";
    if(diagnostic)startBody+="assert(require('tests/manual_extreme_profile').run(20,{native_sample_every=32,native_api=false,damage_details=false,top=48}));assert(require('core/scheduler_profile').start(20));";
    const begin=lua(startBody+"print('LIVE_BEGIN_"+nonce+"')");
    session.prepare([before,after,begin]);
    const settings=await session.send([cmd('fps_max\nfps_max_ui\nengine_no_focus_sleep\nhost_timescale\ncl_showfps\ndota_camera_edgemove\nsv_stressbots\nstatus')],'',200);
    fs.writeFileSync(path.join(stage,'settings.log'),settings.output);
    const cvar=name=>{const value=new RegExp('^\\s*'+name+'\\s*=\\s*"?(-?(?:\\d+(?:\\.\\d*)?|\\.\\d+)(?:e[+-]?\\d+)?)"?\\s*$','mi').exec(settings.output)?.[1];return value===undefined?null:Number(value);};
    state.oldFps=cvar('cl_showfps');state.oldTimescale=cvar('host_timescale');
    const oldEdgeMove=parseEdgeMove(settings.output);state.oldEdgeMoveText=oldEdgeMove?.command_text;
    if(!Number.isFinite(state.oldFps)||!Number.isInteger(state.oldFps)||state.oldFps<0||!Number.isFinite(state.oldTimescale)||state.oldTimescale<=0||!oldEdgeMove)throw Error('Original cl_showfps/host_timescale/edge-move unavailable; settings not changed');
    state.meta.original_settings={cl_showfps:state.oldFps,host_timescale:state.oldTimescale,dota_camera_edgemove:oldEdgeMove.value,dota_camera_edgemove_native_text:oldEdgeMove.command_text};
    state.meta.measurement_settings={dota_camera_edgemove:0,cursor_centering_requested:true};state.meta.camera_readbacks={};
    state.settingsChanged=true;
    await session.send([cmd('host_timescale 1\ncl_showfps 1\ndota_camera_edgemove 0\ncl_resetfps')],'',100);
    const prior=await session.send([before],'LIVE_BEFORE_'+nonce,100);
    fs.writeFileSync(path.join(stage,'before.log'),prior.output);
    console.log('LIVE_WARMUP',label,'12s');await sleep(12000);
    if(clientProbe){
      state.probeBinding=state.readClientProbe();state.clientProbeStarted=true;
      const started=await session.send([cmd(state.probeBinding.commands.start)],'',100,{responsePrefix:'[CLIENT_CALLBACK_PROBE] started '});
      const result=probeJson(started.output,'start');
      if(!result||result.commandId!==state.probeBinding.commandId||!Number.isSafeInteger(result.captureSerial)||result.captureSerial<0)throw Error('Current client probe start was not acknowledged');
      state.probeSerial=result.captureSerial;
    }
    if(diagnostic){await session.send([cmd('vprof_off')],'',100);await session.send([cmd('vprof_reset')],'',100);state.vprofStarted=true;await session.send([cmd('vprof_on')],'',100);}
    state.activityStarted=activeOperations;state.luaProfileStarted=diagnostic;
    const begun=await session.send([begin],'LIVE_BEGIN_'+nonce,0);
    fs.writeFileSync(path.join(stage,'begin.log'),begun.output);
    await session.send([cmd('cl_resetfps')],'',50);
    state.meta.camera_readbacks.before=await readCamera(session,nonce,'BEFORE',stage);
    state.startMonotonic=performance.now();state.meta.started_at=new Date().toISOString();
    state.focus=watchChild(cp.spawn(python,['-B',path.join(root,'tools/observe_live_perf_focus.py'),String(pid),String(seconds),'8'],{windowsHide:true,stdio:['ignore','pipe','pipe']}));
    state.meta.presentmon_spawn_unix_seconds=Date.now()/1000;
    state.presentmon=watchChild(cp.spawn(pm,['--process_id',String(pid),'--session_name','SurvivalLive_'+nonce,'--output_file',pmCsv,'--delay','8','--timed',String(seconds),'--terminate_after_timed','--no_console_stats','--v1_metrics'],{windowsHide:true,stdio:['ignore','pipe','pipe']}));
    const focusRestore=cp.spawnSync('D:/7/pwsh.exe',['-NoProfile','-File',path.join(root,'tools/focus_live_perf_window.ps1'),'-GameProcessId',String(pid)],{windowsHide:true,encoding:'utf8',timeout:7000});
    state.meta.focus_restore_exit=focusRestore.status;
    fs.writeFileSync(path.join(stage,'focus_restore.log'),(focusRestore.stdout||'')+(focusRestore.stderr||'')+(focusRestore.error?'\n'+focusRestore.error.message:''));
    try{const line=(focusRestore.stdout||'').trim().split(/\r?\n/).filter(line=>line.startsWith('{')).pop();state.meta.focus_restore_window=JSON.parse(line);}catch{state.meta.focus_restore_window=null;}
    if(focusRestore.status!==0||focusRestore.error||!restoreWindowValid(state.meta.focus_restore_window,pid))throw Error('Exact real game window restore failed before timed capture');
    console.log('LIVE_CAPTURE_STARTED',label,mode,seconds+'s','pid='+pid);
    const progress=setInterval(()=>console.log('LIVE_CAPTURE_PROGRESS',label,((performance.now()-state.startMonotonic)/1000).toFixed(1)+'s'),10000);
    try{
      const checked=record=>record.done.then(r=>{if(r.fatalError)throw r.fatalError;if(r.code!==0)throw Error('Own capture child exited '+r.code);return r;});
      await boundedWait(Promise.all([checked(state.presentmon),checked(state.focus)]),(seconds+20)*1000,'Own capture children timed out');
    }finally{clearInterval(progress);state.meta.measurement_finished_at=new Date().toISOString();state.meta.wall_seconds=(performance.now()-state.startMonotonic)/1000;}
    state.meta.camera_readbacks.after=await readCamera(session,nonce,'AFTER',stage);
    const fps=await session.send([cmd('cl_printfps')],'',300);
    fs.writeFileSync(path.join(stage,'native_fps.log'),fps.output);
    const next=await session.send([after],'LIVE_AFTER_'+nonce,100);
    fs.writeFileSync(path.join(stage,'after.log'),next.output);
    if(diagnostic){
      const vprof=(await session.send([cmd('vprof_generate_report')],'******** END VPROF REPORT ********',1000)).output;
      fs.writeFileSync(path.join(stage,'vprof.log'),vprof);
    }
    if(activeOperations){
      const report=await session.send([chunkReport("require('tests/manual_four_player_activity').report({include_trace=true,include_plan=true})",'LIVE_ACTIVITY_REPORT_'+nonce)],'LIVE_ACTIVITY_REPORT_'+nonce,100);
      fs.writeFileSync(path.join(stage,'activity.json'),JSON.stringify(decodeReport(report.output),null,2));
    }
    for(const [enabled,expression,filename,stem] of [
      [rangedCandidate,"require('systems/enemy_ranged_stationary').snapshot()",'ranged.json','RANGED'],
      [acquisitionCandidate,"require('tests/manual_wave_acquisition_probe').snapshot()",'acquisition.json','ACQUIRE'],
      [treeCandidate,"require('systems/tree_attack_observer').snapshot()",'tree_observer.json','TREE']])if(enabled){
      const marker='LIVE_'+stem+'_REPORT_'+nonce,response=await session.send([chunkReport(expression,marker)],marker,100);
      fs.writeFileSync(path.join(stage,filename),JSON.stringify(decodeReport(response.output),null,2));
    }
    if(clientProbe){
      const response=await session.send([cmd(state.probeBinding.commands.report+' '+probeNonce)],'',100,{responsePrefix:'[CLIENT_CALLBACK_PROBE] {'});
      fs.writeFileSync(path.join(stage,'client_callbacks.log'),response.output);
      const report=probeJson(response.output,'report',{nonce:probeNonce,commandId:state.probeBinding.commandId,captureSerial:state.probeSerial});
      if(!report||report.contextActive!==true||state.readClientProbe().commandId!==state.probeBinding.commandId)throw Error('Current client callback report unavailable/context changed');
      fs.writeFileSync(path.join(stage,'client_callbacks.json'),JSON.stringify(report,null,2));
    }
  }catch(error){failure=error;throw error;
  }finally{
    if(state.isSample)await cleanupSampler(state,session);
    try{await session.close();}catch(error){if(state.isSample)state.cleanupErrors.push({step:'console_close',error:error.message});else if(!failure)throw error;}
    if(state.isSample){
      try{
        const meta=state.meta||{label,mode,pid:state.pid,requested_seconds:state.seconds,acceptance_sample:false};
        meta.finished_at=new Date().toISOString();meta.failure=failure?.message||null;meta.cleanup_errors=state.cleanupErrors;
        meta.owned_etw_session_cleanup=state.etwTerminationStatus;
        meta.presentmon_exit=state.presentmon?.code??null;meta.focus_observer_exit=state.focus?.code??null;
        meta.owned_children=Object.fromEntries(['presentmon','focus'].map(name=>[name,state[name]?{pid:state[name].child.pid||null,closed:state[name].closed,exit:state[name].code,signal:state[name].signal,error:state[name].fatalError?.message||null}:null]));
        if(state.presentmon)fs.writeFileSync(path.join(state.stage,'presentmon.log'),state.presentmon.stdout+state.presentmon.stderr+(state.presentmon.fatalError?'\n'+state.presentmon.fatalError.message:''));
        if(state.focus){fs.writeFileSync(path.join(state.stage,'focus.json'),state.focus.stdout);fs.writeFileSync(path.join(state.stage,'focus_observer.log'),state.focus.stderr+(state.focus.fatalError?'\n'+state.focus.fatalError.message:''));}
        if(meta.diagnostic_instrumentation||failure)fs.writeFileSync(path.join(state.stage,'session_diagnostic.log'),session.rawOutput||'');
        const pmCsv=path.join(state.stage,'presents.csv');
        meta.csv_validation=fs.existsSync(pmCsv)?validatePresentCsv(fs.readFileSync(pmCsv,'utf8'),state.pid,state.seconds,process.env.LIVE_PERF_SWAPCHAIN||null):{valid:false,invalid_reasons:['csv_evidence_unavailable']};
        let focusReport;
        try{
          focusReport=JSON.parse(state.focus?.stdout||'');
          meta.focus_validation=JSON.parse(cp.execFileSync(python,['-B',path.join(root,'tools/observe_live_perf_focus.py'),'--validate-json',path.join(state.stage,'focus.json'),String(state.pid),String(state.seconds),String(meta.focus_restore_window.target_hwnd)],{windowsHide:true,encoding:'utf8',timeout:5000}));
        }catch(error){meta.focus_validation={valid:false,invalid_reasons:['focus_evidence_unavailable: '+error.message]};}
        meta.exact_window_match=restoreWindowValid(meta.focus_restore_window,state.pid)&&focusReport?.target_hwnd===meta.focus_restore_window.target_hwnd;
        const cameraBefore=meta.camera_readbacks?.before?.position,cameraAfter=meta.camera_readbacks?.after?.position;
        meta.camera_delta=cameraBefore&&cameraAfter?Object.fromEntries(['x','y','z'].map(key=>[key,cameraAfter[key]-cameraBefore[key]])):null;
        meta.camera_visibility_note='Before/after native readbacks and delta do not prove an unobstructed battlefield throughout the sample; actual screenshots remain required.';
        meta.focus_csv_overlap=focusCsvOverlap(focusReport,meta.csv_validation,meta.presentmon_spawn_unix_seconds);
        const readSnapshot=name=>{
          const file=path.join(state.stage,name+'.log');if(!fs.existsSync(file))return null;
          const line=fs.readFileSync(file,'utf8').split(/\r?\n/).filter(x=>x.startsWith('[LIVE_SNAPSHOT] ')).pop();return line?JSON.parse(line.slice('[LIVE_SNAPSHOT] '.length)):null;
        };
        try{
          const before=readSnapshot('before'),after=readSnapshot('after'),valid=(s,phase)=>s?.phase===phase&&s.paused===false&&Number.isFinite(s.game_time)&&Array.isArray(s.owners)&&s.owners.length===4&&new Set(s.owners.map(p=>p.id)).size===4&&s.owners.every(p=>Number.isInteger(p.id)&&p.id>=0&&p.id<4);
          meta.snapshots_valid=valid(before,'BEFORE')&&valid(after,'AFTER')&&after.game_time>=before.game_time;meta.snapshots={before,after};
        }catch{meta.snapshots_valid=false;}
        meta.game_state_validation=gameStateEvidence(session.rawOutput,state.nonce);meta.game_state_valid=meta.game_state_validation.valid;
        meta.capture_valid_scope='Presentation/focus/camera measurement completeness; normal native game state and four-owner snapshots are additional acceptance requirements.';
        const measurement=assessAcceptance({...meta,diagnostic_instrumentation:false,client_callback_probe:false,game_state_valid:true,snapshots_valid:true});
        const acceptance=assessAcceptance(meta);meta.capture_valid=measurement.valid;meta.acceptance_sample=acceptance.valid;meta.invalid_reasons=acceptance.invalid_reasons;
        const publishErrors=publishEvidence(state,meta);
        console.log('LIVE_CAPTURE_DONE',state.target,'presentmon_exit='+meta.presentmon_exit,'capture_valid='+meta.capture_valid,'acceptance_sample='+meta.acceptance_sample);
        if(!failure&&!meta.game_state_valid)throw Error('game_state_invalid: native running-match guards failed; presentation evidence retained');
        if(!failure&&(!measurement.valid||publishErrors.length))throw Error('Capture evidence failed validation; '+meta.invalid_reasons.join(', '));
      }catch(error){if(failure)console.error('LIVE_EVIDENCE_FINALIZE_ERROR',redactConsoleOutput(error.message));else throw error;}
    }
  }

}
if(require.main===module)main().catch(e=>{console.error(redactConsoleOutput(e.message));process.exitCode=1;});
module.exports={csvRows,validatePresentCsv,watchChild,boundedWait,assessAcceptance,focusCsvOverlap,cleanupSampler,publishEvidence,reserveEvidenceDirectory,redactConsoleOutput,restoreWindowValid,parseEdgeMove,readCamera,parseNativeCamera,gameStateGuard,gameStateEvidence};
