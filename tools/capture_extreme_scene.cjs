'use strict';
// Explicit capture of an already prepared Tools match; no account or launcher calls.
const fs=require('node:fs'),path=require('node:path'),cp=require('node:child_process'),os=require('node:os');
const crypto=require('node:crypto');
const {performance}=require('node:perf_hooks');
const {ConsoleSession}=require('./map_c6/console-session.cjs');
const root=path.resolve(__dirname,'..');
const [label,mode='combat',instrument='off']=process.argv.slice(2);
if(!/^[a-z0-9_]+$/.test(label||'')||!['combat','spawn','idle','selection','release'].includes(mode)||!['off','on'].includes(instrument))throw Error('Usage: capture_extreme_scene label [combat|spawn|idle|selection|release] [off|on]');
const captureSeconds=Number(process.env.EXTREME_SECONDS||30);
if(!Number.isInteger(captureSeconds)||captureSeconds<30||captureSeconds>120)throw Error('EXTREME_SECONDS must be an integer from 30 to 120');
const profileSeconds=Number(process.env.EXTREME_PROFILE_SECONDS||25);
if(!Number.isInteger(profileSeconds)||profileSeconds<1||profileSeconds>captureSeconds)throw Error('EXTREME_PROFILE_SECONDS must be an integer from 1 to the capture duration');
const clientProbe=process.env.EXTREME_CLIENT_PROBE==='1';
if(process.env.EXTREME_CLIENT_PROBE&&!['0','1'].includes(process.env.EXTREME_CLIENT_PROBE))throw Error('EXTREME_CLIENT_PROBE must be 0 or 1');
const panCamera=process.env.EXTREME_PAN_CAMERA==='1';
if(process.env.EXTREME_PAN_CAMERA&&!['0','1'].includes(process.env.EXTREME_PAN_CAMERA))throw Error('EXTREME_PAN_CAMERA must be 0 or 1');
// Bridge-on comparisons are deliberate and must never be inferred from status.
const allowPersistentBridge=process.env.EXTREME_ALLOW_PERSISTENT_BRIDGE==='1';
if(process.env.EXTREME_ALLOW_PERSISTENT_BRIDGE&&!['0','1'].includes(process.env.EXTREME_ALLOW_PERSISTENT_BRIDGE))throw Error('EXTREME_ALLOW_PERSISTENT_BRIDGE must be 0 or 1');
const bridgeMode=allowPersistentBridge?'intentional_bridge_on':'bridge_off';
const captureNonce=crypto.randomBytes(12).toString('hex');
const finalOut=path.join(root,'output/extreme_perf_20261008',label);
const out=path.join(os.tmpdir(),'survival_extreme_capture_'+captureNonce);
const relativeToGame=path.relative(path.resolve(root,'../..'),out);
if(relativeToGame===''||(!relativeToGame.startsWith('..'+path.sep)&&!path.isAbsolute(relativeToGame))) {
  throw Error('TEMP capture staging must be outside the Dota game directory');
}
fs.mkdirSync(out,{recursive:false});
const artifactNames=new Set(),maxArtifactFiles=64,maxArtifactBytes=128*1024*1024,maxSingleArtifactBytes=64*1024*1024;
function artifactPath(name){
  if(!/^[a-z0-9_]+\.(json|txt|log)$/.test(name))throw Error('Invalid capture artifact name');
  artifactNames.add(name);return path.join(out,name);
}
const writeArtifact=(name,data)=>fs.writeFileSync(artifactPath(name),data);
const appendArtifact=(name,data)=>fs.appendFileSync(artifactPath(name),data);
let nativeVprofStopped=false,consoleClosed=false;
function publishArtifacts(){
  if(!nativeVprofStopped||!consoleClosed){
    console.error('EXTREME_OUTPUT_STAGE_RETAINED',out,'native_off='+nativeVprofStopped,'console_closed='+consoleClosed);
    return;
  }
  // Only our fixed artifact names are copied. Never traverse the TEMP folder,
  // and validate the complete bound before any writes into the watched game.
  if(artifactNames.size>maxArtifactFiles)throw Error('Capture artifact count exceeds publish bound; retained in '+out);
  let bytes=0;
  for(const name of artifactNames){
    const size=fs.statSync(path.join(out,name)).size;
    if(size>maxSingleArtifactBytes)throw Error('Capture artifact exceeds publish bound; retained in '+out);
    bytes+=size;
  }
  if(bytes>maxArtifactBytes)throw Error('Capture artifacts exceed total publish bound; retained in '+out);
  fs.mkdirSync(finalOut,{recursive:true});
  for(const name of artifactNames)fs.copyFileSync(path.join(out,name),path.join(finalOut,name));
}
const marker=phase=>'EXTREME_CAPTURE_'+phase+'_'+captureNonce;
const phaseCommand='survival_extreme_capture_phase';
writeArtifact('phase_markers.json',JSON.stringify({capture_nonce:captureNonce,
  markers:Object.fromEntries(['VALID','CLIENT_PROBE_ARMED','VPROF_READY','FPS','VPROF_REPORT','BEGIN','END','CLEAN'].map(phase=>[phase,marker(phase)]))},null,2));
const logfile=path.resolve(root,'../../dota/console.log');
function currentClientProbe(){
  const lines=fs.readFileSync(logfile,'utf8').split(/\r?\n/);
  for(let index=lines.length-1;index>=0;index--){
    const at=lines[index].indexOf('[TOOLS_PROBE_COMMANDS] ');
    if(at<0)continue;
    let value;try{value=JSON.parse(lines[index].slice(at+23));}catch{continue;}
    if(!value||value.api!=='SurvivalClientCallbackProbe')continue;
    // Never fall back to an older advertisement or execute arbitrary commands
    // from a console line. Only this known API's exact safe command family.
    if(typeof value.commandId!=='string'||!/^\d+_\d+_\d+$/.test(value.commandId)
      ||value.commandId.length>96||!value.commands)throw Error('Invalid current client probe advertisement');
    for(const [action,stem] of [['start','probe'],['report','report'],['stop','stop']]){
      const command=value.commands[action];
      if(typeof command!=='string'||!/^\w+$/.test(command)
        ||command!=='survival_client_callback_'+stem+'_v2_'+value.commandId){
        throw Error('Invalid current client probe command');
      }
    }
    return {api:value.api,commandId:value.commandId,commands:{...value.commands}};
  }
  throw Error('Current client probe commands were not advertised');
}
function probeChecksum(text){
  let hash=2166136261;
  for(let i=0;i<text.length;i++)hash=((hash^text.charCodeAt(i))*16777619)>>>0;
  return ('00000000'+hash.toString(16)).slice(-8);
}
function probeJson(output,kind,expected={}){
  const prefix=kind==='start'?'[CLIENT_CALLBACK_PROBE] started ':'[CLIENT_CALLBACK_PROBE] ';
  const chunkPrefix='[CLIENT_CALLBACK_PROBE_CHUNK] ',normal=[],chunks=[];
  try{
    for(const line of output.split(/\r?\n/)){
      const isChunk=kind==='report'&&line.startsWith(chunkPrefix);
      if(!isChunk&&!line.startsWith(prefix))continue;
      const text=line.slice(isChunk?chunkPrefix.length:prefix.length);
      if(!text.startsWith('{'))continue;
      if(isChunk&&(normal.length||Buffer.byteLength(line,'utf8')>8192))return null;
      const value=JSON.parse(text);
      (isChunk?chunks:normal).push(value);
    }
    if(kind==='start')return normal.length===1?normal[0]:null;
    if(normal.length!==1)return null;
    const footer=normal[0];
    if(!chunks.length&&footer.chunked!==true){
      if((expected.commandId&&footer.commandId!==expected.commandId)
        ||(expected.captureSerial!==undefined&&expected.captureSerial!==null&&footer.captureSerial!==expected.captureSerial))return null;
      return footer; // Existing short report.
    }
    if(footer.chunked!==true||footer.protocol!=='survival_probe_chunks_v1'
      ||typeof footer.nonce!=='string'||!/^(?:[0-9a-f]{24}|manual_\d+_\d+)$/.test(footer.nonce)
      ||typeof footer.commandId!=='string'||!/^\d+_\d+_\d+$/.test(footer.commandId)||footer.commandId.length>96
      ||!Number.isSafeInteger(footer.captureSerial)||footer.captureSerial<0
      ||!Number.isSafeInteger(footer.count)||footer.count<1||footer.count>175
      ||!Number.isSafeInteger(footer.chars)||footer.chars<1||footer.chars>524288
      ||footer.count!==Math.ceil(footer.chars/3000)||!/^[0-9a-f]{8}$/.test(footer.checksum)
      ||(expected.nonce&&footer.nonce!==expected.nonce)
      ||(expected.commandId&&footer.commandId!==expected.commandId)
      ||(expected.captureSerial!==undefined&&expected.captureSerial!==null&&footer.captureSerial!==expected.captureSerial)
      ||chunks.length!==footer.count)return null;
    const ordered=new Array(footer.count);
    for(const chunk of chunks){
      if(chunk.protocol!==footer.protocol||chunk.nonce!==footer.nonce||chunk.commandId!==footer.commandId
        ||chunk.captureSerial!==footer.captureSerial||chunk.count!==footer.count||chunk.chars!==footer.chars||chunk.checksum!==footer.checksum
        ||!Number.isSafeInteger(chunk.index)||chunk.index<0||chunk.index>=footer.count||ordered[chunk.index]!==undefined
        ||typeof chunk.data!=='string'||chunk.data.length<1||chunk.data.length>3000||/[^\x20-\x7e]/.test(chunk.data)
        ||chunk.data.length!==(chunk.index===footer.count-1?footer.chars-3000*chunk.index:3000))return null;
      ordered[chunk.index]=chunk.data;
    }
    const text=ordered.join('');
    if(text.length!==footer.chars||probeChecksum(text)!==footer.checksum)return null;
    const value=JSON.parse(text);
    if(value.commandId!==footer.commandId||value.captureSerial!==footer.captureSerial)return null;
    return value;
  }catch{return null;}
}
function bridgeState(){
  try{
    const value=JSON.parse(fs.readFileSync(path.join(root,'output/hammer_backend/bridge_status.json'),'utf8'));
    const stopped=value.status==='stopped'&&value.stop_confirmed===true;
    const now=Date.now()/1000;
    // The bridge publishes 'connected' after normal auth/loading inspection.
    // Merely advertising persistent_v1 does not prove a live, ready connection.
    const persistent=value.status==='connected'&&value.ok===true&&value.version===1
      &&value.console_transport==='persistent_v1'&&value.console_connected===true
      &&Number.isSafeInteger(value.pid)&&value.pid>0
      &&Number.isSafeInteger(value.console_worker_generation)&&value.console_worker_generation>0
      &&Number.isSafeInteger(value.console_connections_total)&&value.console_connections_total>0
      &&Number.isFinite(value.updated_at)&&now-value.updated_at>=0&&now-value.updated_at<90
      &&Number.isFinite(value.console_last_connect_at)&&value.console_last_connect_at>0
      &&value.console_last_connect_at<=value.updated_at;
    return {status:typeof value.status==='string'?value.status.slice(0,64):'unknown',
      verified:allowPersistentBridge?persistent:stopped,readiness:stopped?'stopped':persistent?'ready':'unverified',
      transport:stopped?'stopped':value.console_transport==='persistent_v1'?'persistent_v1':'unverified',
      connected:value.console_connected===true,
      connections:Number.isSafeInteger(value.console_connections_total)?value.console_connections_total:null,
      generation:Number.isSafeInteger(value.console_worker_generation)?value.console_worker_generation:null,
      pid:Number.isSafeInteger(value.pid)?value.pid:null,version:Number.isSafeInteger(value.version)?value.version:null,
      last_connect_at:Number.isFinite(value.console_last_connect_at)?value.console_last_connect_at:null,
      updated_at:Number.isFinite(value.updated_at)?value.updated_at:null};
  }catch{return {status:'unavailable',verified:false,readiness:'unverified',transport:'unverified',
    connected:false,connections:null,generation:null,pid:null,version:null,last_connect_at:null,updated_at:null};}
}
const sleep=ms=>new Promise(resolve=>setTimeout(resolve,ms));
let session,cameraAnchor,cameraSequence=0;
async function positionCamera(x,y){
  if(!Number.isFinite(x)||!Number.isFinite(y)||Math.abs(x)>32768||Math.abs(y)>32768)throw Error('Invalid scene camera coordinates');
  const ack='EXTREME_CAMERA_'+captureNonce+'_'+cameraSequence++;
  await session.send([command('dota_camera_set_lookatpos '+x.toFixed(2)+' '+y.toFixed(2)+'\necho '+ack)],ack,0);
}
async function send(name,requests,expect='',drainMs=350,options){
  writeArtifact(name+'.json',JSON.stringify(requests));
  try{
    const result=await session.send(requests,expect,drainMs,options);
    writeArtifact(name+'.txt',result.output);
    return result.output;
  }catch(error){
    writeArtifact(name+'.txt',(error.output||'')+'\n'+error.message+'\n');
    throw error;
  }
}
const lua=code=>({name:'dota_run_lua',arguments:{code}}),command=commands=>({name:'console_send',arguments:{commands}});
const phaseRequest=phase=>command(phaseCommand+' '+captureNonce+' '+phase);
function show(screenshot){
  const args=['-NoProfile','-ExecutionPolicy','Bypass','-File',path.join(__dirname,'map_c6/window.ps1'),'-Show','-CenterPointer'];
  if(screenshot)args.push('-Screenshot',screenshot);
  const result=cp.spawnSync('powershell.exe',args,{cwd:root,windowsHide:true,encoding:'utf8',timeout:20000});
  appendArtifact('window.txt',result.stdout||'');
  if(result.status!==0)throw Error('Tools window unavailable: '+result.stderr);
}
const snapshot=tag=>`local scene=assert(SURVIVAL_REAL_GAME_STRESS,'Prepare real scene first');assert(scene.status=='ready' or '${mode}'=='selection','Scene must finish normal preparation');assert(GameRules:State_Get()==DOTA_GAMERULES_STATE_GAME_IN_PROGRESS);assert(not GameRules:IsGamePaused(),'Paused capture rejected');local b=require('core/event_bus');local e=require('core/events'); for _,s in ipairs(scene.players) do local workers=b.request(e.WORKER_LIST_REQUEST,{player_id=s.id}) or {};local wave=b.request(e.WAVE_STATE_GET_REQUEST,{player_id=s.id}) or {};local readyTowers,attackingTowers=0,0;for _,tower in ipairs(s.towers) do if tower and not tower:IsNull() and tower:IsAlive() then local auto=tower:FindModifierByName('modifier_tower_auto_attack');if auto and auto.idle_initialized==true and not auto.destroyed then readyTowers=readyTowers+1 end;if tower:GetAttackTarget() then attackingTowers=attackingTowers+1 end end end;assert(readyTowers==#s.towers,'Tower AI initialization incomplete; reject noncombat fixture');local counts={};local chopping=0;for _,w in ipairs(workers) do local u=w.unit;if u and not u:IsNull() then local l=tostring(u.survival_lumberjack_level or '?');counts[l]=(counts[l] or 0)+1;if u.GetAttackTarget and u:GetAttackTarget() then chopping=chopping+1 end end end;local parts={};for l,n in pairs(counts) do parts[#parts+1]=l..':'..n end;table.sort(parts); print('[EXTREME_SCENE] tag=${tag} owner='..s.id..' towers='..#s.towers..' ready_towers='..readyTowers..' attacking_towers='..attackingTowers..' workers='..#workers..' tiers='..table.concat(parts,',')..' attacking_workers='..chopping..' alive='..tostring(wave.alive)..' wall_armor='..tostring(s.units.wall.survival_effective_war3_armor));end`;
const nativeWallLua="local wall=nil;if type(GetSystemTimeMS)=='function' then local ok,ms=pcall(GetSystemTimeMS);if ok and type(ms)=='number' and ms==ms and ms~=math.huge and ms~=-math.huge then wall=ms/1000 end end;";
const clockBeginLua=nativeWallLua+"capture.clock={wall=wall,wall_source=wall and 'GetSystemTimeMS' or 'unavailable_use_node_monotonic',simulation=Time(),game=GameRules:GetGameTime()};SURVIVAL_EXTREME_CAPTURE_CLOCK=capture.clock;";
const clockReportLua=nativeWallLua+"local c=assert(capture.clock,'Capture clock missing');local elapsed=wall and c.wall and wall-c.wall;local game=GameRules:GetGameTime()-c.game;local simulation=Time()-c.simulation;print('[EXTREME_CLOCK] wall='..(elapsed and string.format('%.3f',elapsed) or 'unavailable')..' wall_source='..c.wall_source..' simulation='..string.format('%.3f',simulation)..' game='..string.format('%.3f',game)..' ratio='..(elapsed and elapsed>0 and string.format('%.4f',game/elapsed) or 'unavailable')..' paused='..tostring(GameRules:IsGamePaused()));";
const selection=mode==='selection'?`
  local s=SURVIVAL_REAL_GAME_STRESS.players[1]
  assert(s.builder and not s.builder:IsNull() and s.units.main_city and not s.units.main_city:IsNull(),'Selection fixture requires builder and main city')
  local state={count=0,limit=120,deadline=GameRules:GetGameTime()+24}
  capture.selection=state;SURVIVAL_EXTREME_SELECTION=state
  scheduler.every(0.15,function()
    if not driver.is_current(capture) then return false end
    if state.count>=state.limit or GameRules:GetGameTime()>=state.deadline then
      print('[EXTREME_SELECTION] stopped count='..state.count);return false
    end
    local unit=state.count%2==0 and s.builder or s.units.main_city
    if not unit or unit:IsNull() then print('[EXTREME_SELECTION] invalid_unit');return false end
    state.count=state.count+1
    CustomGameEventManager:Send_ServerToPlayer(PlayerResource:GetPlayer(s.id),'survival_select_unit',{entindex=unit:entindex(),reason='tools_selection_stress'})
    if state.count>=state.limit then print('[EXTREME_SELECTION] completed count='..state.count);return false end
    return true
  end,'manual_extreme_selection')
`:'';
// Only this request may load Lua code. All closures and first-use Tools modules
// exist before the settle period and VProf start; timed phases carry no source.
const preprimeRequests=[lua(`
  local driver=require('tests/manual_extreme_capture_driver')
  assert(driver.command=='${phaseCommand}','Unexpected capture dispatcher')
  local scheduler=require('core/scheduler')
  -- A cancelled/manual capture must not leave instrumentation in an "off"
  -- comparison. Restore it before the settle period, never in a timed phase.
  local previous_profiler=package.loaded['tests/manual_extreme_profile']
  if previous_profiler then previous_profiler.stop('pre_capture_cleanup') end
  local previous_scheduler_profiler=package.loaded['core/scheduler_profile']
  if previous_scheduler_profiler then previous_scheduler_profiler.stop('pre_capture_cleanup') end
  assert(rawget(_G,'SURVIVAL_EXTREME_PERFORMANCE_CAPTURE')==nil,'Previous Lua profiler still active')
  ${instrument==='on'?"local profiler=require('tests/manual_extreme_profile');local scheduler_profiler=require('core/scheduler_profile')":''}
  ${mode==='spawn'||mode==='release'?"local stress=require('tests/manual_real_game_stress')":''}
  assert(driver.prepare('${captureNonce}',{
    VALID=function(capture)
      ${snapshot('before')}
      local p=assert(SURVIVAL_REAL_GAME_STRESS.players[1]);local wall=assert(p.units.wall):GetAbsOrigin();local point=(wall+p.base)*0.5;
      print('[EXTREME_CAMERA_ANCHOR] '..require('core/json_encoder').encode({x=point.x,y=point.y,owner=p.id}));
    end,
    VPROF_READY=function(capture) end,
    BEGIN=function(capture)
      ${clockBeginLua}SURVIVAL_EXTREME_SELECTION=nil;
      ${instrument==='on'?`profiler.run(${profileSeconds});scheduler_profiler.start(${profileSeconds});`:''}
      ${selection}
      ${mode==='spawn'?"stress.spawn_wave(15);":mode==='release'?"stress.hold_tower_attacks(false);":''}
    end,
    FPS=function(capture) end,
    VPROF_REPORT=function(capture) end,
    END=function(capture)
      ${snapshot('after')};${clockReportLua}
      local sel=capture.selection;if sel then print('[EXTREME_SELECTION] report count='..sel.count..' limit='..sel.limit) end;
    end,
    CLEAN=function(capture)
      scheduler.cancel('manual_extreme_selection');
      local p=package.loaded['tests/manual_extreme_profile'];if p then p.stop('capture_cleanup') end;
      local s=package.loaded['core/scheduler_profile'];if s then s.stop('capture_cleanup') end;
    end
  }))
  assert(driver.dispatch('${captureNonce}','VALID'))
`)];
const beginRequests=[command('host_timescale 1\ncl_showfps 1\ncl_resetfps'),phaseRequest('BEGIN')];
const afterRequests=[phaseRequest('END')];
(async()=>{
  let started=false,driverPrepared=false,failure,summary,probeBinding,probeStarted=false,probeStartedSerial=null,probeReport=null;
  let nodeBeginAt=null,nodeMeasurementSeconds=null,nodeClockEnvelopeSeconds=null;
  try{
    // window.ps1 can open a proof connection. Keep it outside the persistent
    // session and the measured interval; reconnect history can stall CInputService.
    show();
    session=new ConsoleSession({timeoutMs:5000});
    await session.connect();
    writeArtifact('connect_history.txt',session.historyOutput);
    session.prepare(preprimeRequests);
    driverPrepared=true; // Partial preparation still needs nonce-scoped cleanup.
    const validation=await send('validate',preprimeRequests,marker('VALID'));
    if(panCamera){
      const lines=validation.split(/\r?\n/).filter(line=>line.startsWith('[EXTREME_CAMERA_ANCHOR] '));
      if(lines.length!==1)throw Error('Scene camera anchor missing or ambiguous');
      cameraAnchor=JSON.parse(lines[0].slice('[EXTREME_CAMERA_ANCHOR] '.length));
      await positionCamera(cameraAnchor.x,cameraAnchor.y);
    }
    await sleep(2000);
    if(clientProbe){
      probeBinding=currentClientProbe();
      writeArtifact('client_probe_commands.json',JSON.stringify(probeBinding,null,2));
      const output=await send('client_probe_start',[command(probeBinding.commands.start)],'',50,
        {responsePrefix:'[CLIENT_CALLBACK_PROBE] started '});
      const value=probeJson(output,'start');
      if(!value||value.commandId!==probeBinding.commandId)throw Error('Client probe start did not acknowledge the current commandId');
      probeStarted=true;probeStartedSerial=Number.isSafeInteger(value.captureSerial)?value.captureSerial:null;
    }
    started=true;
    // Client and server console queues do not share execution order. Do not
    // batch off/on/reset: wait for each native acknowledgement before the next.
    await send('vprof_off',[command('vprof_off')],'VProf off.',400);
    nativeVprofStopped=true;
    await send('vprof_reset',[command('vprof_reset')],'VProf reset.',400);
    nativeVprofStopped=false; // A partially failed on request must still be stopped.
    const vprofOn=await send('vprof_on',[command('vprof_on')],'VProf on.',400);
    const vprofStates=[...vprofOn.matchAll(/VProf (on|off)\./g)].map(match=>match[1]);
    if(vprofStates.at(-1)!=='on')throw Error('VProf did not remain on after its acknowledged start');
    await send('vprof_ready',[phaseRequest('VPROF_READY')],marker('VPROF_READY'));
    const startOffset=fs.statSync(logfile).size;
    const bridgeBefore=bridgeState();
    const lateHistoryAtStart=session.lateHistoryReplays;
    // Both sides use ordinary live gameplay. Do not force attack rates or change health.
    // Mark started before transmission: even a partial/failed begin gets cleanup
    // on this same connection, without replaying any gameplay command.
    started=true;
    nodeBeginAt=performance.now();
    await send('begin',beginRequests,marker('BEGIN'));
    console.log('EXTREME_CAPTURE_MEASURING',label,mode,instrument);
    const measurementOutputStart=session.rawOutput.length;
    const nodeMeasurementAt=performance.now();
    for(let elapsed=0,progress=0;elapsed<captureSeconds;){
      if(panCamera){
        const phase=elapsed*Math.PI/3;
        await positionCamera(cameraAnchor.x+180*Math.sin(phase),cameraAnchor.y+120*Math.sin(phase*2));
      }
      const next=Math.min(panCamera?0.25:10,captureSeconds-elapsed);
      await sleep(next*1000);
      elapsed=(performance.now()-nodeMeasurementAt)/1000;
      if(Math.floor(elapsed/10)>progress){progress=Math.floor(elapsed/10);console.log('EXTREME_CAPTURE_PROGRESS',label,Math.min(captureSeconds,progress*10)+'s');}
    }
    if(panCamera)await positionCamera(cameraAnchor.x,cameraAnchor.y);
    nodeMeasurementSeconds=(performance.now()-nodeMeasurementAt)/1000;
    writeArtifact('measurement.txt',session.rawOutput.slice(measurementOutputStart));
    const cameraPanResult=panCamera?{ok:true,method:'bounded_native_camera_commands',anchor:cameraAnchor,
      max_offset_x:180,max_offset_y:120,commands:cameraSequence,includes_command_overhead:true,physical_mouse_drag:false}:null;
    if(cameraPanResult)writeArtifact('camera_pan.txt',JSON.stringify(cameraPanResult));
    // Freeze the FPS sample before generating the potentially lengthy report.
    const fpsReport=await send('fps',[command('cl_printfps'),phaseRequest('FPS')],marker('FPS'),500);
    const vprofReport=await send('vprof_report',[command('vprof_generate_report')],'******** END VPROF REPORT ********',500);
    const vprofFence=await send('vprof_report_fence',[phaseRequest('VPROF_REPORT')],marker('VPROF_REPORT'));
    let clientReportOutput='';
    if(clientProbe){
      clientReportOutput=await send('client_probe_report',[command(probeBinding.commands.report+' '+captureNonce)],'',50,
        {responsePrefix:'[CLIENT_CALLBACK_PROBE] {'});
      writeArtifact('client_callbacks.txt',clientReportOutput);
      const value=probeJson(clientReportOutput,'report',{nonce:captureNonce,commandId:probeBinding.commandId,captureSerial:probeStartedSerial});
      if(!value||value.commandId!==probeBinding.commandId||!Array.isArray(value.rows)||value.rows.length===0
        ||value.contextActive!==true||!Number.isFinite(value.elapsedMs)||value.elapsedMs<=0
        ||currentClientProbe().commandId!==probeBinding.commandId){
        throw Error('Client probe report is missing current commandId/rows or its context changed');
      }
      probeReport=value;writeArtifact('client_callbacks.json',JSON.stringify(value,null,2));
    }
    const afterReport=await send('after',afterRequests,marker('END'),500);
    nodeClockEnvelopeSeconds=(performance.now()-nodeBeginAt)/1000;
    const report=[fpsReport,vprofReport,vprofFence,clientReportOutput,afterReport].join('\n');
    writeArtifact('report.txt',report);
    // Only the response to THIS unique report request is admissible. Session
    // history can contain reports from dead Panorama command contexts.
    const clientReportLines=clientReportOutput.split(/\r?\n/).filter(line=>line.startsWith('[CLIENT_CALLBACK_PROBE] ')||line.startsWith('[CLIENT_CALLBACK_PROBE_CHUNK] '));
    if(clientProbe)writeArtifact('client_callbacks.txt',clientReportLines.join('\n')+'\n');
    const all=fs.readFileSync(logfile);const excerpt=all.subarray(startOffset<=all.length?startOffset:0).toString('utf8');
    writeArtifact('live.log',excerpt);
    const bridgeAfter=bridgeState();
    // Our socket was established before startOffset. New connection messages
    // therefore belong to another client, including an old resident bridge.
    // Read only: the runner never starts/stops/authenticates another process.
    const externalStarts=(excerpt.match(/\[VConComm\] Connection in progress/g)||[]).length;
    const externalConnections=externalStarts||(excerpt.match(/VConsole client connection from 127\.0\.0\.1/g)||[]).length;
    const bridgeChanged=bridgeBefore.status!==bridgeAfter.status||bridgeBefore.transport!==bridgeAfter.transport
      ||bridgeBefore.generation!==bridgeAfter.generation||bridgeBefore.connections!==bridgeAfter.connections
      ||bridgeBefore.pid!==bridgeAfter.pid||bridgeBefore.version!==bridgeAfter.version
      ||bridgeBefore.last_connect_at!==bridgeAfter.last_connect_at;
    // A frozen status file cannot certify a live bridge throughout a >=30s capture.
    const bridgeHeartbeatObserved=allowPersistentBridge?bridgeAfter.updated_at>bridgeBefore.updated_at:null;
    const externalContamination=externalConnections>0||!bridgeBefore.verified||!bridgeAfter.verified
      ||bridgeChanged||(allowPersistentBridge&&!bridgeHeartbeatObserved);
    const warnings=[...excerpt.matchAll(/SERVER: ([^\r\n]+?) thinking for ([\d.]+) ms!/g)].map(x=>({thinker:x[1],ms:Number(x[2])}));
    const fps=report.split(/\r?\n/).filter(x=>/frames:|Average .*fps|Peak .*frame|EXTREME_CLOCK|EXTREME_SCENE|EXTREME_SELECTION/.test(x));
    summary={label,mode,instrument,capture_nonce:captureNonce,capture_seconds:captureSeconds,client_probe:clientProbe,client_probe_report_present:clientProbe?!!probeReport:null,client_probe_valid:clientProbe?probeStarted&&!!probeReport:null,client_probe_command_id:probeBinding?probeBinding.commandId:null,transport:'persistent_direct',single_capture_connection:true,console_reconnects_during_capture:0,history_print_frames_excluded:session.initialPrintFrames,late_history_replays_during_capture:session.lateHistoryReplays-lateHistoryAtStart,ready_proof:session.readyProof,native_think_warnings:warnings,fps_and_scene:fps,rendered_samples_present:/1000 frames:.*total frames:\s*[1-9]/.test(report),live_log_bytes:Buffer.byteLength(excerpt),node_clock:'performance.now monotonic milliseconds',node_measurement_elapsed_seconds:nodeMeasurementSeconds,node_server_clock_envelope_seconds:nodeClockEnvelopeSeconds};
    summary.resource_scripts_prepared_before_capture=true;
    summary.lua_profilers_stopped_before_capture=true;
    summary.resource_settle_ms=2000;
    summary.lua_phase_transport='static_tools_convar';
    summary.lua_script_reload_requests_during_capture=0;
    summary.output_staging='outside_game_os_tmpdir';
    summary.output_staging_directory=out;
    const worldBars=probeReport&&probeReport.diagnostics&&probeReport.diagnostics.worldBars;
    const renderObserved=!!(worldBars&&worldBars.observed===true&&Number.isFinite(worldBars.frames)&&worldBars.frames>0
      &&Number.isFinite(worldBars.modalBlockedFrames)&&worldBars.modalBlockedFrames>=0&&worldBars.modalBlockedFrames<=worldBars.frames);
    const blockedFraction=renderObserved?worldBars.modalBlockedFrames/worldBars.frames:null;
    Object.assign(summary,{world_render_unobstructed:renderObserved?blockedFraction===0:null,
      world_render_blocked_fraction:blockedFraction,
      world_render_warning:renderObserved&&blockedFraction>0?'Custom modal blocked world bars during '+worldBars.modalBlockedFrames+'/'+worldBars.frames+' observed client frames; do not compare with an uncovered scene':null});
    summary.vprof_samples_present=/BEGIN VPROF REPORT/.test(vprofReport)&&!/No samples/i.test(vprofReport);
    Object.assign(summary,{profile_seconds:instrument==='on'?profileSeconds:0,own_console_reconnects_during_capture:0,
      native_camera_pan:cameraPanResult,
      console_reconnects_during_capture:externalContamination&&externalConnections===0?null:externalConnections,
      external_console_connections_observed:externalConnections,external_connection_contamination:externalContamination,
      bridge_mode:bridgeMode,intentional_bridge_on:allowPersistentBridge,
      bridge_identity_unchanged:!bridgeChanged,bridge_heartbeat_observed:bridgeHeartbeatObserved,
      bridge_before:bridgeBefore,bridge_after:bridgeAfter});
    summary.capture_valid=summary.rendered_samples_present&&summary.vprof_samples_present&&summary.late_history_replays_during_capture===0&&!externalContamination&&(!clientProbe||summary.client_probe_valid);
    writeArtifact('summary.json',JSON.stringify(summary,null,2));
    console.log(JSON.stringify(summary));
    if(!summary.rendered_samples_present)throw Error('No rendered FPS samples; exclude this capture');
    if(!summary.vprof_samples_present)throw Error('VProf returned no samples; exclude this profiler capture');
    if(summary.late_history_replays_during_capture!==0)throw Error('Late console history replay occurred during capture; exclude this capture');
    if(externalContamination)throw Error('External console connection or unverified bridge during capture; exclude this capture');
  }catch(error){
    failure=error;
    summary={...(summary||{label,mode,instrument,capture_nonce:captureNonce,capture_seconds:captureSeconds}),
      bridge_mode:bridgeMode,intentional_bridge_on:allowPersistentBridge,
      capture_valid:false,failure:error.message,profile_seconds:instrument==='on'?profileSeconds:0,client_probe:clientProbe,
      client_probe_started:probeStarted,client_probe_report_present:clientProbe?!!probeReport:null,
      client_probe_valid:clientProbe?probeStarted&&!!probeReport:null,
      client_probe_command_id:probeBinding?probeBinding.commandId:null,
      node_clock:'performance.now monotonic milliseconds',node_measurement_elapsed_seconds:nodeMeasurementSeconds,
      node_server_clock_envelope_seconds:nodeBeginAt===null?null:(performance.now()-nodeBeginAt)/1000};
    writeArtifact('summary.json',JSON.stringify(summary,null,2));
  }finally{
    try{
      if((started||driverPrepared||clientProbe)&&session&&session.state==='ready'){
        await send('vprof_cleanup',[command('vprof_off')],'VProf off.',400);
        nativeVprofStopped=true;
        await send('cleanup',[command('cl_showfps 0'+(probeBinding?'\n'+probeBinding.commands.stop:'')),phaseRequest('CLEAN')],marker('CLEAN'));
      }
    }catch(error){if(!failure)failure=error;}
    finally{
      if(session){
        await session.close();
        consoleClosed=session.state==='closed';
        writeArtifact('connect_history.txt',session.historyOutput);
        writeArtifact('session.txt',session.rawOutput);
      }
    }
  }
  if(failure){
    if(summary){summary.capture_valid=false;summary.failure=failure.message;
      writeArtifact('summary.json',JSON.stringify(summary,null,2));}
    throw failure;
  }
  show('extreme_'+label+'.png');
})().finally(publishArtifacts).catch(error=>{console.error(error.stack||error.message);process.exitCode=1;});
