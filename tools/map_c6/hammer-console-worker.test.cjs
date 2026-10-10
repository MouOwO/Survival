'use strict';
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const net = require('node:net');
const {PassThrough} = require('node:stream');
const {test} = require('node:test');
const {packet} = require('./console.cjs');
const {ConsoleSession} = require('./console-session.cjs');
const {Inspector,stateFromLine,serve,PREFIX,INSPECT_COMMAND,INSTALL_ACK} = require('./hammer-console-worker.cjs');
const print = text => packet('PRNT',Buffer.concat([Buffer.alloc(28),Buffer.from(text+'\0')]));
const wait = ms => new Promise(resolve=>setTimeout(resolve,ms));

test('whitelist hashes the session and never forwards arbitrary data',()=>{
  const line=PREFIX+JSON.stringify({status:'configured',session:'session-original',players:4,
    authenticated:3,loaded:2,token:'unrelated-secret'});
  const result=stateFromLine(line);
  assert.deepEqual(result,{status:'configured',players:4,authenticated:3,loaded:2,
    session:crypto.createHash('sha256').update('session-original').digest('hex')});
  assert.doesNotMatch(JSON.stringify(result),/original|secret|token/);
  for(const invalid of ['echo '+line,PREFIX+'null',PREFIX+'[]',PREFIX+'{',
    PREFIX+JSON.stringify({status:'configured',session:'short'}),
    PREFIX+JSON.stringify({status:'configured',session:'valid-session',players:true}),
    PREFIX+JSON.stringify({status:'configured',session:'valid-session',players:65})])assert.equal(stateFromLine(invalid),null);
});

test('thousands of resident polls use one TCP connection and discard history and live chatter',async t=>{
  let peers=[],connections=0,fin=0,polls=0,reloads=0,sessionName='map-session-first';
  let drop=false,clock=1000;
  const sessions=[];
  const server=net.createServer({allowHalfOpen:true},socket=>{
    connections++;peers.push(socket);socket.on('error',()=>{});
    socket.on('end',()=>{fin++;socket.end();});
    let input=Buffer.alloc(0);
    socket.on('data',bytes=>{
      input=Buffer.concat([input,bytes]);
      while(input.length>=12){
        const size=input.readUInt32BE(6);if(input.length<size)break;
        const frame=input.subarray(0,size);input=input.subarray(size);
        if(frame.toString('ascii',0,4)==='VFCS')socket.write(Buffer.concat([
          print('VConsole Buffered Messages\n'),print((PREFIX+'{"status":"configured","session":"old-secret-session"}\n').repeat(2000)),
          print('End VConsole Buffered Messages\n')]));
        else if(frame.toString('ascii',0,4)==='CMND'){
          const text=frame.subarray(12,-1).toString();
          if(text.startsWith('echo SURVIVAL_CONSOLE_SESSION_READY_'))socket.write(print(text.slice(5)+'\n'));
          else if(text.startsWith('script_reload_code ')){
            reloads++;socket.write(print(INSTALL_ACK+'\n'));
          }else{
            const nonce=text.slice(INSPECT_COMMAND.length+1);assert.match(nonce,/^[0-9a-f]{24}$/);
            assert.equal(text,INSPECT_COMMAND+' '+nonce);
            polls++;
            if(drop){drop=false;socket.end();continue;}
            socket.write(print('unrelated live secret '.repeat(2000)+'\n'));
            const response=PREFIX+nonce+':'+JSON.stringify({status:'configured',session:sessionName,players:4,authenticated:4,loaded:4});
            socket.write(print(response.slice(0,12)));socket.write(print(response.slice(12)+'\n'));
          }
        }
      }
    });
  });
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  const inspector=new Inspector({now:()=>clock,sessionFactory:()=>{
    const session=new ConsoleSession({port:server.address().port,retainOutput:false,maxPendingOutputChars:32768,timeoutMs:300});
    sessions.push(session);return session;
  }});
  t.after(async()=>{await inspector.close();peers.forEach(peer=>peer.destroy());await new Promise(resolve=>server.close(resolve));});
  let first;
  for(let i=0;i<1000;i++){
    const result=await inspector.request({id:i+1,op:'inspect',code:"print('fixture')"});
    assert.equal(result.state.status,'configured');
    assert.equal(result.stats.console_connections_total,1);
    if(!first)first=result.state.session;
    assert.doesNotMatch(JSON.stringify(result),/secret|map-session/);
  }
  assert.equal(connections,1);assert.equal(polls,1000);assert.equal(reloads,1,'1000 healthy polls load Lua only once');
  assert.equal(sessions[0].historyChunks.length,0);assert.equal(sessions[0].outputChunks.length,0);
  assert.equal(sessions[0].pending,null);assert.ok(sessions[0].input.length<8192);
  drop=true;
  assert.equal((await inspector.inspect("print('fixture')")).status,'waiting_for_workshop');
  const attempts=inspector.connections;
  assert.equal((await inspector.inspect("print('fixture')")).status,'waiting_for_workshop');
  assert.equal(inspector.connections,attempts,'failed connections back off rather than reconnecting immediately');
  clock+=2000;sessionName='map-session-second';
  const second=await inspector.inspect("print('fixture')");
  assert.equal(second.status,'configured');assert.notEqual(second.session,first);
  assert.equal(connections,2);
  await inspector.request({id:1002,op:'disconnect'});
  assert.equal(inspector.stats().console_connected,false);
  assert.equal(fin,2,'auth handoff closes the existing socket');
  await inspector.inspect("print('fixture')");assert.equal(connections,3);
  await inspector.close();await inspector.close();
  assert.equal(fin,3,'shutdown sends FIN only once per connection');
});

test('JSON-lines worker serializes requests, shuts down, and hides exception details',async()=>{
  const input=new PassThrough(),output=new PassThrough();let log='';
  output.on('data',bytes=>log+=bytes.toString());
  let disconnects=0;
  const session={state:'ready',async connect(){},async send(){throw Error('SECRET HISTORY');},async close(){disconnects++;}};
  const inspector=new Inspector({sessionFactory:()=>session});
  const server=serve(input,output,inspector);
  input.write(JSON.stringify({id:1,op:'inspect',code:'print(1)'})+'\n');
  input.write(JSON.stringify({id:2,op:'shutdown'})+'\n');
  await wait(30);await server.close();
  const rows=log.trim().split('\n').map(JSON.parse);
  assert.equal(rows.length,2);assert.equal(rows[0].state.status,'waiting_for_workshop');
  assert.equal(rows[1].id,2);assert.equal(rows[1].ok,true);
  assert.equal(disconnects,1);assert.equal(inspector.closed,true);
  assert.doesNotMatch(log,/SECRET|HISTORY/);
  assert.equal((await inspector.request({id:3,op:'inspect',code:'print(1)'})).error,'inspection_operation_failed');
  assert.equal((await inspector.request({id:4,op:'console_send',commands:'anything'})).error,'invalid_request');
});

test('oversized or flooded input closes the private worker with bounded buffering',async()=>{
  const input=new PassThrough(),output=new PassThrough();output.resume();
  const inspector=new Inspector();
  const server=serve(input,output,inspector);
  input.write('x'.repeat(70000));
  await server.close();
  assert.equal(inspector.closed,true);assert.equal(inspector.connections,0);
});


function fakeInspector({fault=''}={}){
  const calls=[],nonces=[],closures=[],bootstraps=[];let reads=0,installed=false;
  const session={state:'new',async connect(){this.state='ready';},async close(){this.state='closed';closures.push(true);},
    async send(requests,expect,drain,options){
      calls.push(requests);
      if(requests[0].name==='dota_run_lua'){
        const code=requests[0].arguments.code;bootstraps.push(code);
        assert.match(code,/require\('tests\/manual_hammer_bridge_inspect'\)/);
        assert.equal(expect,INSTALL_ACK);installed=true;
        if(fault==='install')throw Error('secret install failure');
        return {expected_output_received:true};
      }
      const command=requests[0].arguments.commands,nonce=command.slice(INSPECT_COMMAND.length+1);
      assert.equal(command,INSPECT_COMMAND+' '+nonce);assert.match(nonce,/^[0-9a-f]{24}$/);
      assert.equal(options.responsePrefix,PREFIX+nonce+':');assert(installed);
      nonces.push(nonce);reads++;
      if(fault==='missing'&&reads===2)throw Error('Unknown command');
      if(fault==='closed'&&reads===2){this.state='closed';throw Error('socket closed');}
      if(fault==='always_missing')throw Error('Unknown command');
      const stale=fault==='stale_mode'&&reads===2;
      const prefix=fault==='wrong_nonce'&&reads===2?PREFIX+'f'.repeat(24)+':':options.responsePrefix;
      return {matched_line:prefix+JSON.stringify(stale?{status:'inspection_not_installed'}:
        {status:'configured',session:'normal-map-session',players:1,authenticated:1,loaded:1})};
    }};
  return {inspector:new Inspector({sessionFactory:()=>session,now:()=>1000}),calls,nonces,closures,bootstraps};
}

test('native inspection uses fresh nonce, fixed bootstrap files and repairs map/command loss on the same socket',async()=>{
  for(const fault of ['', 'stale_mode','missing','wrong_nonce']){
    const fake=fakeInspector({fault}),inspector=fake.inspector;
    assert.equal((await inspector.inspect('trusted legacy inspection source')).status,'configured');
    for(let i=0;i<3;i++)assert.equal((await inspector.inspect('trusted legacy inspection source')).status,'configured');
    assert.equal(inspector.connections,1);assert.equal(fake.closures.length,0);
    assert.equal(fake.bootstraps.length,fault?2:1);assert.equal(new Set(fake.nonces).size,fake.nonces.length);
    for(const code of fake.bootstraps)assert.doesNotMatch(code,/trusted legacy|SURVIVAL_CONSOLE_SESSION|[0-9a-f]{24}/,
      'no request/source nonce or supplied source creates generated-file churn');
    if(fault==='stale_mode')assert.match(fake.bootstraps[1],/prepare\(false\)/);
    if(['missing','wrong_nonce'].includes(fault))assert.match(fake.bootstraps[1],/prepare\(true\)/);
    await inspector.close();await inspector.close();assert.equal(fake.closures.length,1);
  }
});

test('failed install/read repair is bounded, errors stay private and closed sockets follow backoff',async()=>{
  for(const fault of ['install','always_missing','closed']){
    const fake=fakeInspector({fault}),inspector=fake.inspector;
    if(fault==='closed')assert.equal((await inspector.inspect('read only')).status,'configured');
    const result=await inspector.request({id:1,op:'inspect',code:'read only'});
    assert.equal(result.state.status,'waiting_for_workshop');assert.doesNotMatch(JSON.stringify(result),/secret|Unknown|socket/);
    assert.equal(fake.closures.length,1);assert(fake.bootstraps.length<=2);
    if(fault==='closed')assert.equal(fake.bootstraps.length,1,'a dead socket cannot receive bootstrap retries');
    const count=fake.calls.length;await inspector.inspect('read only');assert.equal(fake.calls.length,count,'backoff does not busy-poll/reconnect');
  }
});
