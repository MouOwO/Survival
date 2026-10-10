'use strict';
// Run the capture controller entirely in memory: no Dota, GUI, files or TCP.
const assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const {test}=require('node:test');
const toolsFixtureDir=path.join(process.cwd(),'tools');
const source=fs.readFileSync(process.argv[2]||path.join(toolsFixtureDir,'capture_extreme_scene.cjs'),'utf8');

async function capture({seconds=60,mode='spawn',lateHistory=false,external=false,legacyBridge=false,
  probeFailure='',invalidCommand=false,panCamera=false,clientProbe=true,instrument='off',profileSeconds=25,
  phaseFailure='',cleanupOffFailure=false,oversizedArtifact=false,modalFrames=0,worldBarsAbsent=false,chunked=false,chunkFault='',
  persistentBridge=false,allowPersistentBridge,bridgeStates,cameraAnchorFailure='',cameraAckFailureAt=0,cameraLatencyMs=0}={}) {
  const files=new Map(),calls=[],logs=[],errors=[],waits=[],writes=[],copies=[],directories=[];
  let current,shows=0,closes=0,connections=0,monotonic=0,pans=0,bridgeReads=0; const cameraTimes=[];
  const epoch=Date.now();
  class CaptureDate extends Date {static now(){return epoch+monotonic;}}
  const id='2_4_1791477695511',oldId='1_2_1791475693582';
  const commands={start:'survival_client_callback_probe_v2_'+id,report:'survival_client_callback_report_v2_'+id,stop:'survival_client_callback_stop_v2_'+id};
  const advertisement='10/09 00:41:35 [PanoramaScript] [TOOLS_PROBE_COMMANDS] '+JSON.stringify({api:'SurvivalClientCallbackProbe',commandId:id,
    commands:{...commands,start:invalidCommand?'quit; dangerous':commands.start}})+'\n';
  const old='[CLIENT_CALLBACK_PROBE] {"ms":39472,"old":true,"rows":18}\n';
  const freshReport={commandId:probeFailure==='wrong_report_id'?oldId:id,captureSerial:1,elapsedMs:seconds*1000,
    diagnostics:worldBarsAbsent?{}:{worldBars:{observed:true,frames:3600,modalBlockedFrames:modalFrames}},
    contextActive:true,rows:probeFailure==='no_rows'?[]:[{name:'topnav.refreshNow',count:120,ms:123}],schedule:{rows:[{name:'schedule.fixture',count:29}]}};
  const fresh='[CLIENT_CALLBACK_PROBE] '+JSON.stringify(freshReport)+'\n';
  class Session {
    constructor() {
      current=this;this.state='new';this.historyOutput=old;this.rawOutput=old;
      this.initialPrintFrames=40005;this.lateHistoryReplays=0;
      this.readyProof={nonce:'unique_ready_proof',receivedAt:1000,readyAt:1350};
      this.prepared=new Set();this.vprofActive=false;
    }
    prepare(requests) {
      assert.equal(this.vprofActive,false,'prepare resources before profiling');
      requests.filter(x=>x.name==='dota_run_lua').forEach(x=>this.prepared.add(x.arguments.code));
    }
    async connect() {connections++;this.state='ready';return this;}
    async send(requests,expect,drainMs,options) {
      assert.equal(this.state,'ready');
      const camera=/^EXTREME_CAMERA_[0-9a-f]{24}_\d+$/.test(expect);
      const native=camera||expect.startsWith('VProf ')||expect==='******** END VPROF REPORT ********'||!!options?.responsePrefix;
      if(!native)assert.match(expect,/^EXTREME_CAPTURE_[A-Z_]+_[0-9a-f]{24}$/);
      const code=requests.filter(x=>x.name==='dota_run_lua').map(x=>x.arguments.code).join('\n');
      if(this.vprofActive)assert.equal(requests.filter(x=>x.name==='dota_run_lua').length,0,
        'preparing a file does not remove script_reload_code cost; no Lua load requests while VProf is active');
      const phaseMatch=/^EXTREME_CAPTURE_([A-Z_]+)_([0-9a-f]{24})$/.exec(expect);
      for(const request of requests.filter(x=>x.name==='console_send')) {
        if(request.arguments.commands==='vprof_on')this.vprofActive=true;
        if(request.arguments.commands==='vprof_off')this.vprofActive=false;
      }
      if(!native){
        assert.ok(phaseMatch);
        if(phaseMatch[1]==='VALID'){
          assert.equal(this.vprofActive,false,'the one preprime executes before profiling');
          assert.match(code,/driver\.prepare\(/);
          assert.ok(code.includes("driver.dispatch('"+phaseMatch[2]+"','VALID')"),'preprime uses the expected nonce');
        }else{
          assert.equal(code,'','every later Lua phase is a native ConCommand');
          assert.ok(requests.some(x=>x.name==='console_send'&&x.arguments.commands===
            'survival_extreme_capture_phase '+phaseMatch[2]+' '+phaseMatch[1]),'native phase uses exactly the expected nonce/phase');
        }
      }
      calls.push({requests,expect,code,options});
      if(cleanupOffFailure&&expect==='VProf off.'&&calls.some(call=>call.expect.startsWith('EXTREME_CAPTURE_BEGIN_')))
        throw Object.assign(Error('Native VProf off acknowledgement missing'),{output:''});
      if(phaseMatch&&phaseMatch[1]===phaseFailure)throw Object.assign(Error('Expected game response was not received'),{output:'[EXTREME_CAPTURE_DRIVER] phase_error\n'});
      let output=expect+'\n';
      if(phaseMatch?.[1]==='VALID')output='[EXTREME_CAMERA_ANCHOR] {"x":800,"y":5200,"owner":0}\n'+output;
      if(phaseMatch?.[1]==='VALID'&&cameraAnchorFailure){
        const validAnchor='[EXTREME_CAMERA_ANCHOR] {"x":800,"y":5200,"owner":0}\n';
        if(cameraAnchorFailure==='missing')output=expect+'\n';
        if(cameraAnchorFailure==='duplicate')output=validAnchor+validAnchor+expect+'\n';
        if(cameraAnchorFailure==='invalid_json')output='[EXTREME_CAMERA_ANCHOR] {broken\n'+expect+'\n';
        if(cameraAnchorFailure==='null')output='[EXTREME_CAMERA_ANCHOR] null\n'+expect+'\n';
        if(cameraAnchorFailure==='string_x')output='[EXTREME_CAMERA_ANCHOR] {"x":"800","y":5200}\n'+expect+'\n';
        if(cameraAnchorFailure==='out_of_bounds')output='[EXTREME_CAMERA_ANCHOR] {"x":40000,"y":5200}\n'+expect+'\n';
      }
      if(camera){
        pans++;
        cameraTimes.push({at:monotonic,active:this.vprofActive,index:pans});
        monotonic+=cameraLatencyMs;
        if(pans===cameraAckFailureAt)throw Object.assign(Error('Camera ACK timed out'),{output:'command echo without exact acknowledgement\n'});
        assert.equal(requests.length,1);
        assert.equal(requests[0].name,'console_send');
        assert.equal(drainMs,0);
        const match=/^dota_camera_set_lookatpos (-?[\d.]+) (-?[\d.]+)\necho (\w+)$/.exec(requests[0].arguments.commands);
        assert.ok(match);
        assert.equal(match[3],expect);
        assert.ok(Math.abs(Number(match[1])-800)<=180&&Math.abs(Number(match[2])-5200)<=120);
      }
      if(requests.some(x=>x.name==='console_send'&&x.arguments.commands.includes('cl_printfps'))) {
        output='1000 frames: average 60 fps total frames: 3600\n'+output;
        if(lateHistory)this.lateHistoryReplays++;
      }
      if(requests.some(x=>x.name==='console_send'&&x.arguments.commands==='vprof_generate_report'))output='******** BEGIN VPROF REPORT ********\n2000 frames sampled\n'+output;
      if(requests.some(x=>x.name==='console_send'&&x.arguments.commands===commands.start)){
        if(probeFailure==='old_context')throw Object.assign(Error('Expected game response was not received'),{output:''});
        output='[CLIENT_CALLBACK_PROBE] started '+JSON.stringify({commandId:probeFailure==='wrong_start_id'?oldId:id,generation:2,scheduleHooked:true,captureSerial:chunkFault==='start_serial'?2:1})+'\n';
      }
      if(requests.some(x=>x.name==='console_send'&&x.arguments.commands.startsWith(commands.report+' '))){
        if(probeFailure==='missing_report')throw Object.assign(Error('Expected game response was not received'),{output:''});
        const command=requests.find(x=>x.name==='console_send'&&x.arguments.commands.startsWith(commands.report+' ')).arguments.commands;
        const nonce=command.slice(commands.report.length+1);assert.match(nonce,/^[0-9a-f]{24}$/,'report uses capture nonce, never arbitrary console text');
        output=fresh;
        if(chunked){
          const data={...freshReport,longSource:'汉字😀\\"'.repeat(4000)};
          const core=fs.readFileSync(process.argv[3]||path.join(toolsFixtureDir,'../panorama/src/scripts/custom_game/combat_stats.js'),'utf8');
          const first=core.indexOf('    function toolsProbeChecksum('),last=core.indexOf('    function registerToolsProbeCommands(',first),lines=[];
          assert(first>=0&&last>first);const emitEnv={customConfig:{},Date:{now:()=>12345},$: {Msg:(...parts)=>lines.push(parts.join(''))}};
          vm.createContext(emitEnv);vm.runInContext(core.slice(first,last),emitEnv);emitEnv.emitToolsProbeReport('CLIENT_CALLBACK_PROBE',data,nonce);
          if(chunkFault==='missing')lines.splice(0,1);
          if(chunkFault==='duplicate')lines.splice(0,0,lines[0]);
          if(chunkFault==='truncated')lines[0]=lines[0].slice(0,-4);
          if(['nonce','commandId','captureSerial'].includes(chunkFault)){
            const prefix='[CLIENT_CALLBACK_PROBE_CHUNK] ',chunk=JSON.parse(lines[0].slice(prefix.length));
            chunk[chunkFault]=chunkFault==='nonce'?'f'.repeat(24):chunkFault==='commandId'?oldId:99;lines[0]=prefix+JSON.stringify(chunk);
          }
          output=lines.join('\n')+'\n';
        }
      }
      if(expect.startsWith('EXTREME_CAPTURE_END_'))output='[EXTREME_CLOCK] wall=60.000 wall_source=GetSystemTimeMS simulation=30.000 game=30.000 ratio=0.5000 paused=false\n'+output;
      this.rawOutput+=output;
      return {output,sent:requests.length,expected_output_received:true};
    }
    async close() {closes++;this.state='closed';}
  }
  const fakeFs={mkdirSync(file){directories.push(String(file));},statSync(file){
      if(oversizedArtifact&&path.basename(file)==='vprof_report.txt')return {size:65*1024*1024};
      return {size:Buffer.byteLength(files.get(path.basename(file))||'')};
    },
    readFileSync(file,encoding){
      if(path.basename(file)==='bridge_status.json'){
        let value=persistentBridge?{status:'connected',ok:true,version:1,pid:7001,
          console_transport:'persistent_v1',console_connected:true,console_connections_total:1,
          console_worker_generation:1,console_last_connect_at:epoch/1000-10,updated_at:CaptureDate.now()/1000}
          :legacyBridge?{status:'connected',updated_at:CaptureDate.now()/1000}:{status:'stopped',stop_confirmed:true};
        const spec=bridgeStates?.[Math.min(bridgeReads,bridgeStates.length-1)];bridgeReads++;
        if(spec===null)throw Error('bridge status missing');
        if(spec==='invalid_json')return '{truncated';
        if(typeof spec==='function')value=spec(value);
        return JSON.stringify(value);
      }
      const value=advertisement+'SERVER: dota_base_game_mode thinking for 11.50 ms!\n'
        +(external?'[VConComm] Connection in progress...\nVConsole client connection from 127.0.0.1\n':'');
      return encoding?value:Buffer.from(value);
    },
    writeFileSync(file,text){writes.push(String(file));files.set(path.basename(file),String(text));},
    appendFileSync(file,text){writes.push(String(file));const key=path.basename(file);files.set(key,(files.get(key)||'')+text);},
    copyFileSync(from,to){
      assert.equal(current.state,'closed','publishing cannot overlap a console connection');
      assert.equal(current.vprofActive,false,'publishing follows native VProf off');
      copies.push({from:String(from),to:String(to)});
    }};
  const fakeProcess={argv:['node','capture_extreme_scene.cjs','mock_capture',mode,instrument],
    env:{EXTREME_SECONDS:String(seconds),EXTREME_PROFILE_SECONDS:String(profileSeconds),EXTREME_CLIENT_PROBE:clientProbe?'1':'0',EXTREME_PAN_CAMERA:panCamera?'1':'0',EXTREME_ALLOW_PERSISTENT_BRIDGE:allowPersistentBridge},execPath:process.execPath};
  await vm.runInNewContext(source,{
    __dirname:toolsFixtureDir,__filename:path.join(toolsFixtureDir,'capture_extreme_scene.cjs'),Buffer,Date:CaptureDate,
    process:fakeProcess,console:{log(...args){logs.push(args);},error(error){errors.push(String(error));}},
    setTimeout(callback,ms){waits.push(ms);queueMicrotask(()=>{monotonic+=ms;callback();});return 1;},
    require(name){
      if(name==='node:fs')return fakeFs;
      if(name==='node:perf_hooks')return {performance:{now(){return monotonic;}}};
      if(name==='node:child_process')return {spawnSync(){
        shows++;assert.ok(!current||current.state==='closed','window helper never overlaps the persistent console');
        return {status:0,stdout:'mock window\n'};
      },spawn(command,args){
        pans++;assert.ok(args.some(x=>String(x).endsWith('pan-camera.ps1')));
        const {EventEmitter}=require('node:events');const child=new EventEmitter();
        child.stdout=new EventEmitter();child.stderr=new EventEmitter();
        queueMicrotask(()=>{child.stdout.emit('data','completed=1\n');child.emit('close',0);});return child;
      }};
      if(name==='./map_c6/console-session.cjs')return {ConsoleSession:Session};
      return require(name);
    },
  });
  return {files,calls,logs,errors,waits,shows,closes,connections,pans,writes,copies,directories,bridgeReads,cameraTimes,finalState:current?.state,vprofActive:current?.vprofActive,process:fakeProcess};
}

test('capture uses fresh phase nonce and only current report JSON across one persistent connection',async()=>{
  const a=await capture();
  assert.equal(a.process.exitCode,undefined);
  assert.equal(a.connections,1);assert.equal(a.closes,1);assert.equal(a.shows,2);
  assert.deepEqual(a.waits,[2000,10000,10000,10000,10000,10000,10000]);
  assert.equal(a.calls.length,14,'separate unique probe acknowledgements and nonce phases still share one session');
  const markers=JSON.parse(a.files.get('phase_markers.json'));
  for(const call of a.calls.filter(call=>call.expect.startsWith('EXTREME_CAPTURE_')))assert.ok(call.expect.endsWith(markers.capture_nonce));
  const nativeCommands=a.calls.flatMap(call=>call.requests.filter(request=>request.name==='console_send'&&request.arguments.commands.startsWith('vprof_')).map(request=>request.arguments.commands));
  assert.deepEqual(nativeCommands,['vprof_off','vprof_reset','vprof_on','vprof_generate_report','vprof_off'],
    'settings and report are separate acknowledged phases; final off follows the completed report');
  const summary=JSON.parse(a.files.get('summary.json'));
  assert.equal(summary.capture_nonce,markers.capture_nonce);
  assert.equal(summary.capture_seconds,60);
  assert.equal(summary.console_reconnects_during_capture,0);
  assert.equal(summary.client_probe_report_present,true);
  assert.equal(summary.client_probe_valid,true);
  assert.equal(summary.client_probe_command_id,'2_4_1791477695511');
  assert.equal(summary.node_measurement_elapsed_seconds,60);
  assert.equal(summary.node_server_clock_envelope_seconds,60);
  assert.match(summary.node_clock,/monotonic/);
  assert.equal(summary.capture_valid,true);
  assert.equal(summary.vprof_samples_present,true);
  assert.equal(summary.resource_scripts_prepared_before_capture,true);
  assert.equal(summary.resource_settle_ms,2000);
  assert.equal(summary.lua_phase_transport,'static_tools_convar');
  assert.equal(summary.lua_script_reload_requests_during_capture,0);
  assert.equal(summary.output_staging,'outside_game_os_tmpdir');
  assert.equal(summary.world_render_unobstructed,true);
  assert.equal(summary.world_render_blocked_fraction,0);
  assert.equal(summary.world_render_warning,null);
  assert.equal(a.copies.length,new Set(a.writes.map(file=>path.basename(file))).size,'all own artifacts are published once');
  for(const file of a.writes)assert.equal(path.dirname(file),summary.output_staging_directory,'all writes, including camera output and cleanup, remain outside Game');
  assert.equal(a.directories.at(-1),path.join(toolsFixtureDir,'../output/extreme_perf_20261008/mock_capture'));
  assert.ok(a.copies.every(copy=>path.dirname(copy.from)===summary.output_staging_directory));
  assert.ok(!summary.output_staging_directory.startsWith(path.resolve(toolsFixtureDir,'../..')));
  assert.equal(a.calls.flatMap(call=>call.requests).filter(request=>request.name==='dota_run_lua').length,1,
    'only preprime may load a Lua resource, including cleanup');
  const orderedPhases=a.calls.filter(call=>call.expect.startsWith('EXTREME_CAPTURE_'))
    .map(call=>/^EXTREME_CAPTURE_([A-Z_]+)_/.exec(call.expect)[1]);
  assert.deepEqual(orderedPhases,['VALID','VPROF_READY','BEGIN','FPS','VPROF_REPORT','END','CLEAN']);
  assert.doesNotMatch(a.files.get('client_callbacks.txt'),/39472|"old"/);
  assert.match(a.files.get('client_callbacks.txt'),/"ms":123.*"count":29/);
  const probeCalls=a.calls.flatMap(call=>call.requests.filter(x=>x.name==='console_send').map(x=>x.arguments.commands));
  assert.ok(probeCalls.some(x=>x==='survival_client_callback_probe_v2_2_4_1791477695511'));
  assert.ok(probeCalls.some(x=>x==='survival_client_callback_report_v2_2_4_1791477695511 '+markers.capture_nonce));
  assert.ok(probeCalls.some(x=>x.includes('survival_client_callback_stop_v2_2_4_1791477695511')));
  const b=await capture({seconds:90,mode:'selection'});
  const other=JSON.parse(b.files.get('phase_markers.json'));
  assert.notEqual(other.capture_nonce,markers.capture_nonce,'every capture gets independent tokens');
  assert.equal(b.waits.length,10);
  const preprime=b.calls.find(call=>call.expect.startsWith('EXTREME_CAPTURE_VALID_'));
  assert.match(preprime.code,/limit=120/);assert.match(preprime.code,/GetGameTime\(\)\+24/);
  assert.match(preprime.code,/SURVIVAL_EXTREME_SELECTION=nil/);
  assert.match(preprime.code,/driver\.is_current\(capture\)/);
  assert.match(preprime.code,/GetSystemTimeMS/);assert.match(preprime.code,/simulation=Time\(\)/);
  assert.doesNotMatch(preprime.code,/wall=Time\(\)/);
  assert.match(preprime.code,/unavailable_use_node_monotonic/);
  assert.match(preprime.code,/idle_initialized==true/,'tower AI readiness remains a strict fixture prerequisite');
});

test('old client contexts, wrong IDs and missing rows/reports never produce a valid capture',async()=>{
  for(const probeFailure of ['old_context','wrong_start_id','missing_report','wrong_report_id','no_rows']){
    const result=await capture({probeFailure});
    const summary=JSON.parse(result.files.get('summary.json'));
    assert.equal(summary.capture_valid,false,probeFailure);
    assert.equal(summary.client_probe_valid,false,probeFailure);
    assert.equal(result.process.exitCode,1,probeFailure);
    assert.equal(result.connections,1);assert.equal(result.closes,1);
    assert.equal(result.shows,1);
    assert.ok(result.calls.at(-1).expect.startsWith('EXTREME_CAPTURE_CLEAN_'));
    assert.ok(result.calls.at(-1).requests[0].arguments.commands.includes('survival_client_callback_stop_v2_2_4_1791477695511'));
  }
});

test('advertised commands are strictly validated before execution, without using old static aliases',async()=>{
  const result=await capture({invalidCommand:true});
  const summary=JSON.parse(result.files.get('summary.json'));
  assert.equal(summary.capture_valid,false);assert.equal(summary.client_probe_valid,false);
  assert.match(summary.failure,/Invalid current client probe command/);
  assert.ok(!result.calls.some(call=>JSON.stringify(call).includes('dangerous')));
  assert.ok(!result.calls.some(call=>JSON.stringify(call).includes('survival_client_callback_probe_v2')));
});

test('camera pan helper and release mode survive probe changes, and probe-off needs no advertisement',async()=>{
  const result=await capture({mode:'release',panCamera:true,clientProbe:false,invalidCommand:true});
  const summary=JSON.parse(result.files.get('summary.json'));
  assert.equal(summary.capture_valid,true);assert.equal(summary.client_probe_valid,null);
  assert.equal(summary.native_camera_pan.ok,true);assert.equal(result.pans,242);
  assert.equal(summary.native_camera_pan.physical_mouse_drag,false);
  assert.equal(summary.native_camera_pan.method,'bounded_native_camera_commands');
  const preprime=result.calls.find(call=>call.expect.startsWith('EXTREME_CAPTURE_VALID_'));
  assert.match(preprime.code,/hold_tower_attacks\(false\)/);
  assert.ok(!result.calls.some(call=>call.options?.responsePrefix));
});

test('90 second instrumentation is preloaded and every missing phase ack fails without retrying gameplay',async()=>{
  const good=await capture({seconds:90,instrument:'on',profileSeconds:90,clientProbe:false});
  assert.equal(good.process.exitCode,undefined);
  const preprime=good.calls.find(call=>call.expect.startsWith('EXTREME_CAPTURE_VALID_'));
  assert.match(preprime.code,/local profiler=require\('tests\/manual_extreme_profile'\)/);
  assert.match(preprime.code,/profiler\.run\(90\);scheduler_profiler\.start\(90\)/);
  assert.equal(JSON.parse(good.files.get('summary.json')).profile_seconds,90);
  for(const phaseFailure of ['VALID','VPROF_READY','BEGIN','FPS','VPROF_REPORT','END','CLEAN']){
    const result=await capture({phaseFailure,clientProbe:false});
    assert.equal(result.process.exitCode,1,phaseFailure);
    assert.equal(JSON.parse(result.files.get('summary.json')).capture_valid,false,phaseFailure);
    assert.equal(result.calls.filter(call=>call.expect.startsWith('EXTREME_CAPTURE_BEGIN_')).length,
      ['VALID','VPROF_READY'].includes(phaseFailure)?0:1,'BEGIN is never retried');
    assert.equal(result.connections,1);assert.equal(result.closes,1);
    assert.ok(result.calls.at(-1).expect.startsWith('EXTREME_CAPTURE_CLEAN_'),'partial preprime/begin uses only native cleanup');
    assert.equal(result.calls.flatMap(call=>call.requests).filter(request=>request.name==='dota_run_lua').length,1);
  }
});

test('late history makes capture invalid while cleanup still uses the same connection',async()=>{
  const result=await capture({lateHistory:true});
  const summary=JSON.parse(result.files.get('summary.json'));
  assert.equal(summary.late_history_replays_during_capture,1);
  assert.equal(summary.capture_valid,false);
  assert.equal(result.process.exitCode,1);
  assert.match(result.errors.join('\n'),/Late console history replay/);
  assert.equal(result.connections,1);assert.equal(result.closes,1);
  assert.ok(result.calls.at(-1).expect.startsWith('EXTREME_CAPTURE_CLEAN_'));
  assert.equal(result.shows,1,'invalid capture stops before the post-capture window helper');
});

test('external reconnects and legacy resident status invalidate capture without touching bridge',async()=>{
  for(const options of [{external:true},{legacyBridge:true}]){
    const result=await capture(options);
    const summary=JSON.parse(result.files.get('summary.json'));
    assert.equal(summary.capture_valid,false);
    assert.equal(summary.external_connection_contamination,true);
    assert.equal(summary.own_console_reconnects_during_capture,0);
    assert.equal(summary.console_reconnects_during_capture,options.external?1:null);
    assert.equal(result.process.exitCode,1);
    assert.equal(result.connections,1);
    assert.equal(result.closes,1);
  }
});

test('TEMP camera/results staging publishes only after off/close and retains failed or oversized captures',async()=>{
  const a=await capture({panCamera:true});
  assert.equal(a.process.exitCode,undefined);
  assert.ok(a.writes.some(file=>path.basename(file)==='camera_pan.txt'));
  assert.ok(a.copies.some(copy=>path.basename(copy.to)==='camera_pan.txt'));
  const b=await capture();
  assert.notEqual(JSON.parse(a.files.get('summary.json')).output_staging_directory,
    JSON.parse(b.files.get('summary.json')).output_staging_directory,'independent nonce owns an independent TEMP directory');
  const failedOff=await capture({cleanupOffFailure:true});
  assert.equal(failedOff.process.exitCode,1);
  assert.equal(failedOff.copies.length,0,'missing off ack forbids publishing to watched Game even after closing');
  assert.match(failedOff.errors.join('\n'),/EXTREME_OUTPUT_STAGE_RETAINED/);
  assert.equal(JSON.parse(failedOff.files.get('summary.json')).capture_valid,false);
  const oversized=await capture({oversizedArtifact:true});
  assert.equal(oversized.process.exitCode,1);
  assert.equal(oversized.copies.length,0,'validate all publish bounds before the first Game copy');
  assert.match(oversized.errors.join('\n'),/publish bound/);
});

test('modal coverage is reported separately from valid server capture without changing choice behavior',async()=>{
  const blocked=await capture({modalFrames:2700});
  const summary=JSON.parse(blocked.files.get('summary.json'));
  assert.equal(summary.capture_valid,true,'a modal does not invalidate observed server combat');
  assert.equal(summary.world_render_unobstructed,false);
  assert.equal(summary.world_render_blocked_fraction,0.75);
  assert.match(summary.world_render_warning,/2700\/3600/);
  assert.ok(!blocked.calls.some(call=>/choose|reroll|reward\.select/.test(JSON.stringify(call.requests))),
    'runner never resolves or rerolls production offers');
  for(const options of [{worldBarsAbsent:true},{clientProbe:false}]){
    const unknown=JSON.parse((await capture(options)).files.get('summary.json'));
    assert.equal(unknown.world_render_unobstructed,null,'unobserved coverage is not falsely reported clear');
    assert.equal(unknown.world_render_blocked_fraction,null);
  }
});

test('chunked report is fully reassembled under one completion ack and missing/mixed identities fail strictly',async()=>{
  const result=await capture({chunked:true});const summary=JSON.parse(result.files.get('summary.json'));
  assert.equal(summary.capture_valid,true);assert.equal(summary.client_probe_valid,true);assert.equal(result.connections,1);assert.equal(result.closes,1);
  const report=JSON.parse(result.files.get('client_callbacks.json'));assert.equal(report.commandId,summary.client_probe_command_id);assert.equal(report.captureSerial,1);assert(report.longSource.includes('汉字😀'));
  assert.match(result.files.get('client_callbacks.txt'),/CLIENT_CALLBACK_PROBE_CHUNK/);
  const reportCall=result.calls.find(call=>call.requests.some(x=>x.name==='console_send'&&x.arguments.commands.startsWith('survival_client_callback_report_v2_')));
  assert.equal(reportCall.options.responsePrefix,'[CLIENT_CALLBACK_PROBE] {','completion footer shares the existing ack; fragments use distinct prefix');
  for(const chunkFault of ['missing','duplicate','truncated','nonce','commandId','captureSerial','start_serial']){
    const failed=await capture({chunked:true,chunkFault}),bad=JSON.parse(failed.files.get('summary.json'));
    assert.equal(bad.capture_valid,false,chunkFault);assert.equal(bad.client_probe_valid,false,chunkFault);assert.equal(failed.process.exitCode,1,chunkFault);
    assert.equal(failed.connections,1);assert.equal(failed.closes,1);assert.ok(failed.calls.at(-1).expect.startsWith('EXTREME_CAPTURE_CLEAN_'));
    assert.equal(failed.files.has('client_callbacks.json'),false,'invalid/truncated assembly never produces a parsed JSON artifact');
  }
});

test('bridge-off is the default and does not accept even a healthy resident bridge',async()=>{
  for(const allowPersistentBridge of [undefined,'0']){
    const stopped=await capture({allowPersistentBridge});
    const off=JSON.parse(stopped.files.get('summary.json'));
    assert.equal(off.capture_valid,true);assert.equal(off.bridge_mode,'bridge_off');
    assert.equal(off.intentional_bridge_on,false);assert.equal(off.bridge_heartbeat_observed,null);
    const on=await capture({persistentBridge:true,allowPersistentBridge});
    const rejected=JSON.parse(on.files.get('summary.json'));
    assert.equal(rejected.capture_valid,false);assert.equal(rejected.bridge_before.readiness,'ready');
    assert.equal(rejected.bridge_before.verified,false,'an opt-in is required even with valid status proof');
    assert.equal(rejected.external_connection_contamination,true);assert.equal(on.process.exitCode,1);
  }
  const unconfirmed=await capture({bridgeStates:[()=>({status:'stopped'})]});
  assert.equal(JSON.parse(unconfirmed.files.get('summary.json')).capture_valid,false);
});

test('explicit bridge-on accepts only stable ready persistent identity and records the intentional comparison',async()=>{
  for(const seconds of [30,120]){
    const result=await capture({seconds,profileSeconds:25,persistentBridge:true,allowPersistentBridge:'1'});
    const summary=JSON.parse(result.files.get('summary.json'));
    assert.equal(summary.capture_valid,true);assert.equal(result.process.exitCode,undefined);
    assert.equal(summary.bridge_mode,'intentional_bridge_on');assert.equal(summary.intentional_bridge_on,true);
    assert.equal(summary.bridge_before.status,'connected','preserve the actual bridge status spelling');
    assert.equal(summary.bridge_before.readiness,'ready');assert.equal(summary.bridge_after.readiness,'ready');
    assert.equal(summary.bridge_before.transport,'persistent_v1');assert.equal(summary.bridge_identity_unchanged,true);
    assert.equal(summary.bridge_heartbeat_observed,true);assert(summary.bridge_after.updated_at>summary.bridge_before.updated_at);
    assert.equal(summary.external_connection_contamination,false);assert.equal(summary.console_reconnects_during_capture,0);
    assert.equal(result.bridgeReads,2);assert.equal(result.connections,1);assert.equal(result.closes,1);
    assert.ok(!result.calls.some(call=>/hammer_backend_bridge|bridge[.]stop|auth[.]inject|tunnel[.]connect/.test(JSON.stringify(call.requests))),
      'the runner only reads proof; it never starts/stops/authenticates the resident bridge');
  }
  const stopped=await capture({allowPersistentBridge:'1'});
  assert.equal(JSON.parse(stopped.files.get('summary.json')).capture_valid,false,'an off bridge cannot masquerade as the requested on comparison');
  for(const allowPersistentBridge of ['true','yes','2','01']){
    await assert.rejects(capture({allowPersistentBridge}),/EXTREME_ALLOW_PERSISTENT_BRIDGE must be 0 or 1/);
  }
});

test('bridge-on rejects missing status, legacy schema and incomplete proof on either boundary',async()=>{
  const fields=['status','ok','version','pid','console_transport','console_connected','console_connections_total',
    'console_worker_generation','console_last_connect_at','updated_at'];
  for(const field of fields){
    for(const boundary of [0,1]){
      const bridgeStates=[value=>value,value=>value];
      bridgeStates[boundary]=value=>{const copy={...value};delete copy[field];return copy;};
      const result=await capture({persistentBridge:true,allowPersistentBridge:'1',bridgeStates});
      const summary=JSON.parse(result.files.get('summary.json'));
      assert.equal(summary.capture_valid,false,field+' boundary '+boundary);
      assert.equal(boundary===0?summary.bridge_before.verified:summary.bridge_after.verified,false);
      assert.equal(summary.external_connection_contamination,true);assert.equal(result.process.exitCode,1);
    }
  }
  for(const spec of [null,'invalid_json',()=>null]){
    for(const boundary of [0,1]){
      const bridgeStates=[value=>value,value=>value];bridgeStates[boundary]=spec;
      const result=await capture({persistentBridge:true,allowPersistentBridge:'1',bridgeStates});
      assert.equal(JSON.parse(result.files.get('summary.json')).capture_valid,false);
    }
  }
  const legacy=await capture({legacyBridge:true,allowPersistentBridge:'1'});
  assert.equal(JSON.parse(legacy.files.get('summary.json')).capture_valid,false);
});

test('bridge-on rejects reconnects, worker/process restart and unready or invalid native status fields',async()=>{
  const changes=[{console_connections_total:2},{console_worker_generation:2},{pid:7002},
    {console_last_connect_at:1},{version:2},{console_transport:'legacy_v0'},{console_connected:false},
    {status:'ready'},{status:'retrying'},{status:'authentication_applied'},{ok:false},
    {console_connections_total:0},{console_connections_total:1.5},{console_connections_total:'1'},
    {console_worker_generation:0},{pid:0}];
  for(const change of changes){
    const result=await capture({persistentBridge:true,allowPersistentBridge:'1',
      bridgeStates:[value=>value,value=>({...value,...change})]});
    const summary=JSON.parse(result.files.get('summary.json'));
    assert.equal(summary.capture_valid,false,JSON.stringify(change));assert.equal(result.process.exitCode,1);
    assert.equal(summary.external_connection_contamination,true);
    assert.equal(result.connections,1);assert.equal(result.closes,1);
  }
  for(const options of [{external:true},{lateHistory:true}]){
    const result=await capture({...options,persistentBridge:true,allowPersistentBridge:'1'});
    const summary=JSON.parse(result.files.get('summary.json'));
    assert.equal(summary.capture_valid,false,'explicit on never permits external connections or history replay');
    assert.equal(result.process.exitCode,1);assert.equal(result.connections,1);assert.equal(result.closes,1);
    if(options.external)assert.equal(summary.external_console_connections_observed,1);
    else assert.equal(summary.late_history_replays_during_capture,1);
  }
});

test('bridge-on requires fresh nonfuture status and an advancing heartbeat, not a frozen ready file',async()=>{
  let stamp;
  const frozen=await capture({persistentBridge:true,allowPersistentBridge:'1',seconds:30,
    bridgeStates:[value=>{stamp=value.updated_at;return value;},value=>({...value,updated_at:stamp})]});
  const summary=JSON.parse(frozen.files.get('summary.json'));
  assert.equal(summary.bridge_before.verified,true);assert.equal(summary.bridge_after.verified,true,
    'both frozen endpoints remain within the 90s age bound, so freshness alone is insufficient');
  assert.equal(summary.bridge_heartbeat_observed,false);assert.equal(summary.capture_valid,false);
  const badTime=[
    value=>({...value,updated_at:value.updated_at-91}),
    value=>({...value,updated_at:value.updated_at+1}),
    value=>({...value,console_last_connect_at:value.updated_at+1}),
    value=>({...value,console_last_connect_at:0})
  ];
  for(const change of badTime){
    for(const boundary of [0,1]){
      const bridgeStates=[value=>value,value=>value];bridgeStates[boundary]=change;
      const result=await capture({persistentBridge:true,allowPersistentBridge:'1',bridgeStates});
      assert.equal(JSON.parse(result.files.get('summary.json')).capture_valid,false,'invalid timestamp at either boundary');
    }
  }
  const early=await capture({persistentBridge:true,allowPersistentBridge:'1',phaseFailure:'VALID'});
  assert.equal(JSON.parse(early.files.get('summary.json')).bridge_mode,'intentional_bridge_on',
    'even failures before boundary reads cannot be confused with a default-off sample');
});


test('camera anchor absence/ambiguity/invalid native coordinates fail before BEGIN and clean once',async()=>{
  for(const cameraAnchorFailure of ['missing','duplicate','invalid_json','null','string_x','out_of_bounds']){
    const result=await capture({seconds:30,panCamera:true,clientProbe:false,cameraAnchorFailure});
    const summary=JSON.parse(result.files.get('summary.json'));
    assert.equal(result.process.exitCode,1,cameraAnchorFailure);assert.equal(summary.capture_valid,false);
    assert.equal(result.calls.filter(x=>x.expect.startsWith('EXTREME_CAPTURE_BEGIN_')).length,0);
    assert.equal(result.pans,0);assert.equal(result.connections,1);assert.equal(result.closes,1);
    assert.equal(result.finalState,'closed');assert.equal(result.vprofActive,false);
    assert.ok(result.calls.at(-1).expect.startsWith('EXTREME_CAPTURE_CLEAN_'));
    assert.equal(result.calls.flatMap(x=>x.requests).filter(x=>x.name==='dota_run_lua').length,1);
    assert.ok(result.copies.length>0,'Failed capture may publish TEMP evidence only after off/close');
  }
});

test('camera ACK failure at anchoring, timed movement, or final recenter never replays and always retires',async()=>{
  for(const cameraAckFailureAt of [1,2,122]){
    const result=await capture({seconds:30,panCamera:true,clientProbe:false,cameraAckFailureAt});
    const summary=JSON.parse(result.files.get('summary.json'));
    assert.equal(result.process.exitCode,1);assert.equal(summary.capture_valid,false);
    assert.match(summary.failure,/Camera ACK timed out/);
    assert.equal(result.pans,cameraAckFailureAt,'No retry or camera request after first missing ACK');
    assert.equal(result.calls.filter(x=>x.expect.startsWith('EXTREME_CAPTURE_BEGIN_')).length,cameraAckFailureAt===1?0:1);
    assert.equal(result.calls.filter(x=>x.expect.startsWith('EXTREME_CAPTURE_CLEAN_')).length,1);
    assert.equal(result.calls.filter(x=>x.expect.startsWith('EXTREME_CAPTURE_FPS_')).length,0);
    assert.equal(result.connections,1);assert.equal(result.closes,1);
    assert.equal(result.finalState,'closed');assert.equal(result.vprofActive,false);
    assert.equal(result.files.has('camera_pan.txt'),false,'No success proof after failed camera ACK');
    assert.equal(result.calls.flatMap(x=>x.requests).filter(x=>x.name==='dota_run_lua').length,1);
  }
});

test('camera ACK latency reduces cadence without overlapping or catch-up; actual duration records overhead',async()=>{
  const result=await capture({seconds:30,panCamera:true,clientProbe:false,cameraLatencyMs:120});
  const summary=JSON.parse(result.files.get('summary.json'));
  assert.equal(summary.capture_valid,true);assert.equal(result.connections,1);assert.equal(result.closes,1);
  assert.ok(result.pans<122,'Do not claim exact 4Hz with 120ms ACK cost');
  const active=result.cameraTimes.filter(x=>x.active);
  assert.ok(active.length>2);
  assert.equal(active[1].at-active[0].at,370,'Current contract is ACK + 250ms, not a fixed 250ms schedule');
  assert.ok(summary.node_measurement_elapsed_seconds>=30&&summary.node_measurement_elapsed_seconds<30.5);
  assert.equal(summary.native_camera_pan.commands,result.pans);
  assert.equal(summary.native_camera_pan.includes_command_overhead,true);
  assert.equal(result.vprofActive,false);assert.equal(result.finalState,'closed');
});
