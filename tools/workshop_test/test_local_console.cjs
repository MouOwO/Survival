'use strict';
// Isolated worker regression checks: no real console, game or network is used.
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');
const crypto=require('node:crypto');

const workerSource=fs.readFileSync(path.join(__dirname,'local_console.cjs'),'utf8');
const listenCommand='map template_map gamemode=15 customgamemode=survival_ws4_local loopback=false nomapvalidation=1';

function harness({connectFailures=0, mapErrorSent=null}={}){
  const calls=[];
  const instances=[];
  let failedMap=false;
  class FakeConsoleSession{
    constructor(options){this.options=options;this.closed=false;instances.push(this);}
    async connect(){
      if(connectFailures>0){connectFailures--;throw new Error('fixture_connect_not_ready');}
      return this;
    }
    async close(){this.closed=true;}
    async send(requests,marker){
      assert.equal(requests.length,1);
      assert.equal(requests[0].name,'console_send');
      const commands=requests[0].arguments.commands;
      assert.match(marker,/^WS4_LOCAL_CMD_[a-f0-9]{24}$/);
      calls.push(commands);
      if(commands.startsWith(listenCommand+'\n')){
        assert.equal(commands,listenCommand+'\necho '+marker);
        if(mapErrorSent!==null&&!failedMap){
          failedMap=true;
          const error=new Error('fixture_echo_timed_out');
          error.sent=mapErrorSent;
          error.output='FIXTURE_PRIVATE_RAW_OUTPUT_MUST_NOT_ESCAPE';
          throw error;
        }
        return {sent:2,expected_output_received:true,output:marker+'\n'};
      }
      assert.match(commands,/^script_reload_code ws4_local_launcher\/(?:apply|probe)\.lua\necho WS4_LOCAL_CMD_[a-f0-9]{24}$/);
      const state={status:'waiting_for_players',phase:'team_setup',players:1,
        authenticated:0,profiles:0,credential_applied:false,
        private_token:'FIXTURE_PRIVATE_STATE_MUST_NOT_ESCAPE',profile:{secret:'fixture'}};
      return {sent:2,expected_output_received:true,
        output:'WS4_LOCAL_STATUS:'+JSON.stringify(state)+'\n'+marker+'\n'};
    }
  }
  // Keep the worker's actual stdin loop idle. The exported hook invokes the
  // same request function; the fake iterator never owns timers or OS handles.
  const input={ [Symbol.asyncIterator](){return {next(){return new Promise(()=>{});}};} };
  const context={
    require(name){
      if(name==='node:readline')return {createInterface(){return input;}};
      if(name==='node:crypto')return crypto;
      if(name==='../map_c6/console-session.cjs')return {ConsoleSession:FakeConsoleSession};
      throw new Error('Unexpected worker dependency: '+name);
    },
    process:{stdin:{},stdout:{write(){throw new Error('Unexpected worker stdout');}},exitCode:0},
  };
  vm.runInNewContext(workerSource+'\nglobalThis.testRequest=request;\n',context,
    {filename:'local_console.cjs'});
  return {request:context.testRequest,calls,instances,
    mapAttempts(){return calls.filter(value=>value.startsWith(listenCommand+'\n')).length;}};
}

async function connectionFailureCanRetryBeforeMapDispatch(){
  const fixture=harness({connectFailures:1});
  const first=await fixture.request({id:1,op:'listen'});
  assert.equal(first.ok,false);
  assert.equal(first.error,'console_unavailable');
  assert.equal(fixture.mapAttempts(),0);
  assert.equal(fixture.instances[0].closed,true);
  const second=await fixture.request({id:2,op:'listen'});
  assert.equal(second.ok,true);
  assert.equal(second.state.status,'listen_map_requested');
  assert.equal(fixture.mapAttempts(),1);
}

async function dispatchedMapIsNotReplayedAfterEchoTimeout(sent){
  const fixture=harness({mapErrorSent:sent});
  const first=await fixture.request({id:1,op:'listen'});
  assert.equal(fixture.mapAttempts(),1);
  assert.equal(JSON.stringify(first).includes('FIXTURE_PRIVATE_RAW_OUTPUT'),false);
  const retry=await fixture.request({id:2,op:'listen'});
  assert.equal(retry.ok,true);
  assert.equal(retry.state.status,'listen_map_requested');
  assert.equal(fixture.mapAttempts(),1,'a dispatched map must not be restarted after a missing echo');
  const probe=await fixture.request({id:3,op:'probe'});
  assert.equal(probe.ok,true);
  assert.equal(probe.state.status,'waiting_for_players');
  assert.equal(probe.state.players,1);
  assert.equal(JSON.stringify(probe).includes('FIXTURE_PRIVATE_STATE'),false);
  assert.equal(fixture.mapAttempts(),1);
}

async function zeroSentFailureCanRetry(){
  const fixture=harness({mapErrorSent:0});
  const first=await fixture.request({id:1,op:'listen'});
  assert.equal(first.ok,false);
  const retry=await fixture.request({id:2,op:'listen'});
  assert.equal(retry.ok,true);
  assert.equal(retry.state.status,'listen_map_requested');
  assert.equal(fixture.mapAttempts(),2,'a known zero-sent failure may retry the first map dispatch');
}

async function onlyFixedWorkerOperationsCanReachConsole(){
  const fixture=harness();
  const injected='quit\nmap other_map\nscript print("INJECTED_CONSOLE_COMMAND")';
  for(const value of [{id:1,op:'console_send',commands:injected},
    {id:2,op:'listen\nquit',commands:injected},{id:'3',op:'probe',commands:injected}]){
    const result=await fixture.request(value);
    assert.equal(result.ok,false);
    assert.equal(result.error,'invalid_operation');
  }
  assert.equal(fixture.calls.length,0);
  // Extra caller fields never select a command or a script filename.
  await fixture.request({id:4,op:'probe',commands:injected,file:'other.lua'});
  await fixture.request({id:5,op:'apply',commands:injected,file:'other.lua'});
  assert.equal(fixture.mapAttempts(),0,'single-player apply/probe must not launch a listen map');
  await fixture.request({id:6,op:'listen',commands:injected,file:'other.lua'});
  assert.equal(fixture.mapAttempts(),1);
  assert.equal(fixture.calls.some(value=>value.includes('INJECTED_CONSOLE_COMMAND')),false);
  assert.equal(fixture.calls.some(value=>value.includes('other.lua')),false);
}

(async()=>{
  await connectionFailureCanRetryBeforeMapDispatch();
  await dispatchedMapIsNotReplayedAfterEchoTimeout(1);
  await dispatchedMapIsNotReplayedAfterEchoTimeout(2);
  await zeroSentFailureCanRetry();
  await onlyFixedWorkerOperationsCanReachConsole();
  console.log('WS4_LOCAL_CONSOLE_CHECKS_PASSED 5');
})().catch(error=>{console.error(error.stack||error);process.exitCode=1;});
