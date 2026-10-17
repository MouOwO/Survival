'use strict';
// Pure fixtures/mock children only: no game console, windows, or ETW processes.
const assert=require('node:assert/strict'),fs=require('node:fs'),os=require('node:os'),path=require('node:path');
const {EventEmitter}=require('node:events');
const audit=require(process.env.LIVE_PERF_TEST_MODULE||'./run_four_player_live_perf.cjs');
const header='Application,ProcessID,SwapChainAddress,TimeInSeconds,msBetweenPresents';
function chainRows(pid=42,chain='0xaa',seconds=30,step=.2){
  const count=Math.round(seconds/step);
  return Array.from({length:count+1},(_,i)=>['"dota, test.exe"',pid,chain,(8+i*step).toFixed(6),i?step*1000:999]);
}
const csv=rows=>header+'\r\n'+rows.map(row=>row.join(',')).join('\r\n')+'\r\n';
function validMeta(){return {diagnostic_instrumentation:false,client_callback_probe:false,presentmon_exit:0,focus_observer_exit:0,focus_restore_exit:0,
  csv_validation:{valid:true},focus_validation:{valid:true},focus_csv_overlap:{valid:true},snapshots_valid:true,game_state_valid:true,exact_window_match:true,
  camera_readbacks:{before:{acknowledged:true,valid:true},after:{acknowledged:true,valid:true}},cleanup_errors:[],failure:null};}
function fakeChild(pid){
  const child=new EventEmitter();child.pid=pid;child.stdout=new EventEmitter();child.stderr=new EventEmitter();child.killCount=0;
  child.kill=()=>{child.killCount++;setImmediate(()=>child.emit('close',null,'SIGTERM'));return true;};return child;
}
async function main(){
  let checks=0;
  const expect=(condition,message)=>{assert.ok(condition,message);checks++;};
  const slow=audit.validatePresentCsv(csv(chainRows()),42,30);
  expect(slow.valid,'native 5 FPS cadence is a valid measurement, not a performance pass');
  assert.equal(slow.primary.accepted_interval_count,150);assert.ok(Math.abs(slow.primary.mean_present_fps-5)<1e-9);checks+=2;
  const fast=audit.validatePresentCsv(csv(chainRows(42,'0xaa',120,1/60)),42,120);
  expect(fast.valid,'native 60 FPS full-length cadence passes evidence validation');
  assert.equal(fast.primary.accepted_interval_count,7200);checks++;
  expect(audit.validatePresentCsv(csv(chainRows()).replace('msBetweenPresents','MsBetweenPresents'),42,30).valid,'older native column spelling');
  expect(!audit.validatePresentCsv('',42,30).valid,'empty CSV is not evidence');
  expect(!audit.validatePresentCsv(csv(chainRows(43)),42,30).valid,'another PID cannot stand in for the requested renderer');
  expect(!audit.validatePresentCsv(csv(chainRows(42,'0xaa',20)),42,30).valid,'short capture rejected');
  expect(!audit.validatePresentCsv(csv(chainRows(42,'0xaa',40)),42,30).valid,'overlong capture rejected');
  const corrupt=chainRows();corrupt[20][4]='NaN';
  expect(!audit.validatePresentCsv(csv(corrupt),42,30).valid,'invalid native interval cannot disappear from acceptance');
  const duplicate=chainRows();duplicate[20][3]=duplicate[19][3];
  expect(!audit.validatePresentCsv(csv(duplicate),42,30).valid,'nonincreasing native timestamps rejected');
  const ambiguous=csv([...chainRows(42,'0xaa'),...chainRows(42,'0xbb')]);
  expect(!audit.validatePresentCsv(ambiguous,42,30).valid,'multiple swapchains require an explicit selection');
  const explicit=audit.validatePresentCsv(ambiguous,42,30,'0xbb');
  expect(explicit.valid,'explicit main-chain selection accepted');assert.equal(explicit.primary.accepted_interval_count,150);checks++;
  expect(!audit.validatePresentCsv(csv(chainRows())+'broken,last,row\n',42,30).valid,'truncated CSV row rejected');
  expect(audit.assessAcceptance(validMeta()).valid,'complete uninstrumented measurement accepted');
  const stateNonce='0123456789abcdef';
  const nativeStates=(progress=10)=>['BEFORE','START','AFTER'].map(phase=>({nonce:stateNonce,phase,rules_available:true,actual_state:progress,expected_state:progress,post_game_state:progress+1,in_progress:true}));
  const stateOutput=entries=>entries.map(entry=>'[LIVE_GAME_STATE] '+JSON.stringify(entry)).join('\n');
  expect(audit.gameStateEvidence(stateOutput(nativeStates(10)),stateNonce).valid,'runtime progress=10 is accepted without assuming historical state7');
  expect(audit.gameStateEvidence(stateOutput(nativeStates(12)),stateNonce).valid,'runtime enum may change and is still compared by its actual constant');
  const ended=nativeStates();ended[2].actual_state=11;ended[2].in_progress=false;
  expect(!audit.gameStateEvidence(stateOutput(ended),stateNonce).valid,'post-game after capture invalidates normal-game acceptance');
  const unknown=nativeStates();unknown[2].rules_available=false;delete unknown[2].actual_state;
  expect(!audit.gameStateEvidence(stateOutput(unknown),stateNonce).valid,'destroyed GameRules scope is not positive state evidence');
  expect(!audit.gameStateEvidence(stateOutput(nativeStates().slice(0,2)),stateNonce).valid,'missing AFTER state guard rejected');
  expect(!audit.gameStateEvidence(stateOutput(nativeStates()),'ffffffffffffffff').valid,'old capture state evidence is ignored');
  const drift=nativeStates();drift[2].expected_state=12;drift[2].actual_state=12;
  expect(!audit.gameStateEvidence(stateOutput(drift),stateNonce).valid,'runtime enum identity mismatch within one capture rejected');
  expect(audit.gameStateGuard(stateNonce,'START').includes("assert(game_in_progress,'game_state_invalid")&&audit.gameStateGuard(stateNonce,'START').includes('DOTA_GAMERULES_STATE_GAME_IN_PROGRESS'),'start guard checks the runtime native constant before actions');
  const endedMeta={...validMeta(),game_state_valid:false};
  expect(audit.assessAcceptance(endedMeta).invalid_reasons.includes('game_state_invalid'),'post-game metric cannot be a gameplay acceptance');
  expect(audit.assessAcceptance({...endedMeta,game_state_valid:true,snapshots_valid:true}).valid,'independent presentation evidence may remain complete despite invalid gameplay scope');
  for(const [key,value] of [['presentmon_exit',1],['focus_observer_exit',1],['focus_restore_exit',1],['snapshots_valid',false],['exact_window_match',false],['failure','report decode failed'],['cleanup_errors',[{error:'cleanup failed'}]],['diagnostic_instrumentation',true],['client_callback_probe',true]]){
    expect(!audit.assessAcceptance({...validMeta(),[key]:value}).valid,key+' cannot yield acceptance_sample=true');
  }
  for(const key of ['csv_validation','focus_validation','focus_csv_overlap'])expect(!audit.assessAcceptance({...validMeta(),[key]:{valid:false,invalid_reasons:['bad']}}).valid,key+' failure rejected');
  expect(!audit.assessAcceptance({...validMeta(),camera_readbacks:{before:{acknowledged:true,valid:true}}}).valid,'missing after camera readback rejected');
  expect(!audit.assessAcceptance({...validMeta(),camera_readbacks:{before:{acknowledged:true,valid:true},after:{acknowledged:true,valid:false}}}).valid,'fresh echo alone is not camera position evidence');
  const focus={observation_start_unix_seconds:1008,observation_end_unix_seconds:1038};
  const realWindow={pid:42,foreground:true,selection_unique:true,title:'Dota 2',visible:true,iconic:false,client_rect_valid:true,cursor_centered:true,target_hwnd:3675722,client_width:1600,client_height:900};
  expect(audit.restoreWindowValid(realWindow,42),'exact real window accepted');
  for(const [key,value] of [['title',''],['client_width',0],['client_height',0],['target_hwnd',null],['visible',null],['iconic',true],['selection_unique',false],['cursor_centered',false]])expect(!audit.restoreWindowValid({...realWindow,[key]:value},42),'invalid restored window '+key+' rejected');
  for(const [raw,value] of [['0',0],['1',1],['false',0],['true',1]]){
    assert.deepEqual(audit.parseEdgeMove('dota_camera_edgemove = '+raw+'\n'),{value,command_text:raw});checks++;
  }
  for(const raw of ['2','-1','NaN','unknown','1 extra_command'])expect(audit.parseEdgeMove('dota_camera_edgemove = '+raw+'\n')===null,'unsafe old edge-move value rejected '+raw);
  assert.deepEqual(audit.parseNativeCamera('Camera look-at position: 1280.000000 -15584.000977 3.764706\n'),{x:1280,y:-15584.000977,z:3.764706});checks++;
  assert.deepEqual(audit.parseNativeCamera('Camera look-at position: 1280.000000 4992.000000 260.678711\r\n'),{x:1280,y:4992,z:260.678711});checks++;
  for(const raw of ['Unknown command: dota_camera_get_lookatpos','Camera look-at position: 1280 NaN 256','Camera look-at position: 1280 4992 Infinity','Camera look-at position: 1 2 3 trailing'])expect(audit.parseNativeCamera(raw)===null,'unconfirmed camera position rejected');
  const secrets='server_key = abc123\ntv_secret_code "private-code"\n{"auth_token":"secret with spaces","access_token":"access-secret","player_id":3,"count":28}\n';
  const redacted=audit.redactConsoleOutput(secrets);
  for(const value of ['abc123','private-code','secret with spaces','access-secret'])expect(!redacted.includes(value),'credential value removed');
  expect(redacted.includes('"player_id":3')&&redacted.includes('"count":28'),'business counters and IDs preserved');
  const jsonLine=redacted.split('\n').find(line=>line.startsWith('{'));
  assert.deepEqual(JSON.parse(jsonLine),{auth_token:'[REDACTED]',access_token:'[REDACTED]',player_id:3,count:28});checks++;
  expect(audit.focusCsvOverlap(focus,slow,1000).valid,'focus clock window overlaps native present cadence');
  expect(!audit.focusCsvOverlap({...focus,observation_start_unix_seconds:1012},slow,1000).valid,'late focus observation cannot cover the capture');
  const spawnFailed=fakeChild(undefined),watched=audit.watchChild(spawnFailed);
  spawnFailed.emit('error',Error('missing exe'));
  const failed=await watched.done;expect(failed.fatalError.message==='missing exe','spawn failure is handled immediately without unhandled rejection');
  spawnFailed.emit('close',-2,null);
  const child=fakeChild(123),record=audit.watchChild(child),foreign=fakeChild(777),sends=[];
  const state={nonce:'aabb',presentmon:record,activityStarted:true,luaProfileStarted:true,vprofStarted:true,settingsChanged:true,oldFps:2,oldTimescale:8,oldEdgeMoveText:'1'};
  const session={send:async requests=>{sends.push(requests);if(sends.length===1)throw Error('Lua cleanup send failed');return {output:''};}};
  const errors=await audit.cleanupSampler(state,session);
  expect(errors.some(error=>error.step==='owned_lua_operations_stop'),'failed Lua cleanup recorded');
  expect(sends.some(requests=>requests[0].arguments.commands==='vprof_off'),'Lua cleanup failure does not skip native profiler cleanup');
  expect(sends.some(requests=>requests[0].arguments.commands==='cl_showfps 2\nhost_timescale 8\ndota_camera_edgemove 1'),'original settings restored despite earlier cleanup error');
  assert.equal(child.killCount,1);assert.equal(foreign.killCount,0);checks+=2;
  const sendsBefore=sends.length;await audit.cleanupSampler(state,session);
  assert.equal(sends.length,sendsBefore);assert.equal(child.killCount,1);checks+=2;
  const ownedChild=fakeChild(321),ownedRecord=audit.watchChild(ownedChild),stops=[];
  const ownedState={nonce:'0123456789abcdef',presentmon:ownedRecord,presentmonPath:'fake-presentmon.exe',meta:{session_name:'SurvivalLive_0123456789abcdef'}};
  await audit.cleanupSampler(ownedState,{send:async()=>{}},{terminateSession:async(executable,args)=>{
    stops.push({executable,args});ownedChild.emit('close',0,null);
  }});
  assert.deepEqual(stops,[{executable:'fake-presentmon.exe',args:['--session_name','SurvivalLive_0123456789abcdef','--terminate_existing_session']}]);checks++;
  assert.equal(ownedState.etwTerminationStatus,'terminated');assert.equal(ownedChild.killCount,0);checks+=2;
  const normalChild=fakeChild(322),normalRecord=audit.watchChild(normalChild);normalChild.emit('close',0,null);
  await audit.cleanupSampler({...ownedState,cleanupDone:false,presentmon:normalRecord},{send:async()=>{}},{terminateSession:async()=>{throw Error('Normal capture must not stop any ETW session');}});
  assert.equal(stops.length,1);checks++;
  const badChild=fakeChild(323),badRecord=audit.watchChild(badChild),badState={nonce:'0123456789abcdef',presentmon:badRecord,presentmonPath:'fake-presentmon.exe',meta:{session_name:'FrameViewService'}};
  await audit.cleanupSampler(badState,{send:async()=>{}},{terminateSession:async()=>{throw Error('Foreign session must never be terminated');}});
  expect(badState.cleanupErrors.some(x=>x.step==='owned_etw_session_stop'),'mismatched session is rejected before termination');
  assert.equal(badChild.killCount,1);checks++;
  const unownedSends=[],unowned={nonce:'cc',clientProbeStarted:true,probeSerial:7,probeBinding:{commandId:'1_2_3',commands:{report:'safe_report',stop:'safe_stop'}},readClientProbe:()=>({commandId:'9_8_7'})};
  await audit.cleanupSampler(unowned,{send:async requests=>{unownedSends.push(requests);return {output:''};}});
  assert.equal(unownedSends.length,0);expect(unowned.cleanupErrors.length===1,'context replacement does not stop another client probe');checks++;
  await assert.rejects(audit.boundedWait(new Promise(()=>{}),5,'bounded timeout'),/bounded timeout/);checks++;
  const temp=fs.mkdtempSync(path.join(os.tmpdir(),'sampler_pure_test_'));
  try{
    const target=audit.reserveEvidenceDirectory(temp,'sample'),stage=path.join(temp,'stage');fs.mkdirSync(stage);
    const marker=path.join(target,'existing.txt');fs.writeFileSync(marker,'keep');
    assert.throws(()=>audit.reserveEvidenceDirectory(temp,'sample'),/EEXIST/);assert.equal(fs.readFileSync(marker,'utf8'),'keep');checks+=2;
    assert.throws(()=>audit.reserveEvidenceDirectory(temp,'../escape'),/Invalid evidence/);checks++;
    fs.writeFileSync(path.join(stage,'presents.csv'),'new');fs.writeFileSync(path.join(target,'presents.csv'),'old');
    const meta={acceptance_sample:true,invalid_reasons:[]};const publish=audit.publishEvidence({stage,target},meta);
    expect(publish.length===1&&!meta.acceptance_sample,'evidence conflict invalidates acceptance');
    assert.equal(fs.readFileSync(path.join(target,'presents.csv'),'utf8'),'old');checks++;
    assert.throws(()=>audit.publishEvidence({stage,target},meta),/EEXIST/);checks++;
    const cameraCommands=[];
    const cameraSession={send:async(requests,marker)=>{cameraCommands.push({requests,marker});return {output:'dota_camera_edgemove = false\nCamera look-at position: 1280.000000 4992.000000 260.678711\n'+marker};}};
    const before=await audit.readCamera(cameraSession,'0123456789abcdef','BEFORE',stage),after=await audit.readCamera(cameraSession,'0123456789abcdef','AFTER',stage);
    expect(before.acknowledged&&after.acknowledged&&before.marker!==after.marker,'camera readbacks use fresh, distinct acknowledgements');
    expect(cameraCommands.every(call=>call.requests[0].arguments.commands==='dota_camera_edgemove\ndota_camera_get_lookatpos\necho '+call.marker),'camera probe executes only getters and its own ack');
    expect(fs.readFileSync(path.join(stage,'camera.log'),'utf8').includes('[CAMERA_AFTER]'),'both camera readbacks preserved');
    await assert.rejects(audit.readCamera({send:async()=>({output:'dota_camera_edgemove = 0\nUnknown command\n'})},'0123456789abcdef','AFTER',stage),/not confirmed/);checks++;
  }finally{
    const absolute=path.resolve(temp),allowed=path.resolve(os.tmpdir())+path.sep;
    assert.ok(absolute.startsWith(allowed)&&path.basename(absolute).startsWith('sampler_pure_test_'));
    fs.rmSync(absolute,{recursive:true,force:true}); // Solely the verified, freshly created temp fixture.
  }
  console.log('live perf sampler pure checks PASS '+checks);
}
main().catch(error=>{console.error(error);process.exitCode=1;});
