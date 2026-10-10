'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const net = require('node:net');
const path = require('node:path');
const {test} = require('node:test');
const {packet, luaScript} = require('./console.cjs');
const {ConsoleSession} = require('./console-session.cjs');

const wait = ms => new Promise(resolve => setTimeout(resolve, ms));
const request = commands => [{name:'console_send', arguments:{commands}}];
const print = text => packet('PRNT', Buffer.concat([Buffer.alloc(28), Buffer.from(text+'\0')]));

test('resident prefix response ignores history, handles fragments and caps all retained data', async t => {
  const fake = await mockConsole(t, {
    session:{retainOutput:false,maxPendingOutputChars:2048},
    history(socket) {
      socket.write(print('VConsole Buffered Messages\nSTATE:{"secret":"history"}\n'));
      socket.write(print('End VConsole Buffered Messages\n'));
    },
    onCommand(socket) {
      socket.write(print('live unrelated secret '.repeat(2000)+'\nSTA'));
      socket.write(print('TE:{"status":"fresh"}'));
      setTimeout(()=>socket.write(print('\n')),10);
    },
  });
  await fake.session.connect();
  const result = await fake.session.send(request('inspect'),'',0,{responsePrefix:'STATE:'});
  assert.equal(result.matched_line,'STATE:{"status":"fresh"}');
  assert.equal(result.expected_output_received,true);
  assert.equal(result.output_truncated,true);
  assert.ok(result.output.length<=2048);
  assert.equal(fake.session.rawOutput,'');
  assert.equal(fake.session.historyOutput,'');
  assert.equal(fake.session.outputChunks.length,0);
  assert.equal(fake.session.historyChunks.length,0);
  await fake.session.close();
  assert.equal(fake.state.fin,1);
});

test('large client probe JSON lines retain their prefix across fragmented PRNT frames', async t => {
  const payload='[CLIENT_CALLBACK_PROBE] '+JSON.stringify({commandId:'2_4_123',rows:[{source:'x'.repeat(50000)}]});
  const fake=await mockConsole(t,{onCommand(socket){
    socket.write(print(payload.slice(0,12000)));
    socket.write(print(payload.slice(12000,34000)));
    socket.write(print(payload.slice(34000)+'\n'));
  }});
  await fake.session.connect();
  const response=await fake.session.send(request('probe_report'),'',0,{responsePrefix:'[CLIENT_CALLBACK_PROBE] {'});
  assert.equal(response.matched_line,payload);
  assert.equal(response.expected_output_received,true);
  assert.equal(response.output_truncated,false);
});

async function mockConsole(t, options = {}) {
  const peers = [], commands = [], barriers = [], handshakes = [], state = {fin:0, historyEndAt:0};
  const server = net.createServer({allowHalfOpen:true}, socket => {
    peers.push(socket);
    socket.on('error', () => {});
    socket.on('end', () => {
      state.fin++;
      if (options.onEnd) options.onEnd(socket); else socket.end();
    });
    let input = Buffer.alloc(0);
    socket.on('data', bytes => {
      input = Buffer.concat([input,bytes]);
      while (input.length >= 12) {
        const size = input.readUInt32BE(6);
        if (input.length < size) break;
        const frame = input.subarray(0,size);
        input = input.subarray(size);
        const kind = frame.toString('ascii',0,4);
        if (kind === 'VFCS') {
          handshakes.push(frame.subarray(12));
          if (options.history) options.history(socket,state);
          else {
            socket.write(Buffer.concat([
              print('VConsole Buffered Messages\n'),
              packet('CVRB',Buffer.alloc(50000)),
              print('history-only\nMISSING\nROUND_ONE\n'),
              print('End VConsole Buffered Messages\n'),
            ]));
            state.historyEndAt = Date.now();
          }
        } else if (kind === 'CMND') {
          const text = frame.subarray(12,-1).toString('utf8');
          if (/^echo SURVIVAL_CONSOLE_SESSION_READY_[0-9a-f]{32}$/.test(text)) {
            const nonce=text.slice(5);
            barriers.push({nonce,at:Date.now()});
            if (options.onBarrier) options.onBarrier(socket,nonce,state);
            else socket.write(print(nonce+'\n'));
            continue;
          }
          commands.push({text,at:Date.now()});
          if (options.onCommand) options.onCommand(socket,text,state);
        }
      }
    });
  });
  await new Promise(resolve => server.listen(0,'127.0.0.1',resolve));
  const session = new ConsoleSession({port:server.address().port, timeoutMs:200,
    commandDelayMs:0, ...(options.session || {})});
  t.after(async () => {
    await session.close();
    peers.forEach(socket => socket.destroy());
    await new Promise(resolve => server.close(resolve));
  });
  return {session,peers,commands,barriers,handshakes,state};
}

test('persistent rounds exclude history, wait post-history warmup and keep idle output', async t => {
  const fake = await mockConsole(t, {history(socket,state) {
    socket.write(print('VConsole Buffered Messages\n'));
    setTimeout(() => {
      socket.write(print('history-only\nROUND_ONE\n'));
      socket.write(print('End VConsole Buffered Messages\n'));
      state.historyEndAt = Date.now();
    },45);
  }, onCommand(socket,text) {
    if (text==='echo ROUND_ONE') socket.write(print('ROUND_ONE\n'));
    if (text==='echo ROUND_TWO') socket.write(print('ROUND_TWO\n'));
  }});
  assert.equal(await fake.session.connect(),fake.session);
  const a = await fake.session.send(request('echo ROUND_ONE'),'ROUND_ONE',5);
  fake.peers[0].write(print('live while no command pending\n'));
  await wait(20);
  const b = await fake.session.send(request('echo ROUND_TWO'),'ROUND_TWO',5);
  assert.equal(a.output,'ROUND_ONE\n');
  assert.equal(b.output,'ROUND_TWO\n');
  assert.match(fake.session.historyOutput,/history-only/);
  assert.doesNotMatch(fake.session.rawOutput,/history-only/);
  assert.match(fake.session.rawOutput,/live while no command pending/);
  assert.ok(fake.commands[0].at-fake.state.historyEndAt>=330,
    'first command is sent only after history end plus 350 ms warmup');
  assert.equal(fake.peers.length,1);
  assert.deepEqual(fake.handshakes,[Buffer.from([0])]);
  const first = fake.session.close(), second = fake.session.close();
  assert.equal(first,second,'close is idempotent even while waiting for FIN drain');
  await first;
  assert.equal(fake.state.fin,1);
});

test('marker split across TCP frames and PRNT records matches only a complete exact line', async t => {
  let released = false;
  const fake = await mockConsole(t,{onCommand(socket) {
    socket.write(print('echo SPLIT_MARKER\nSPLIT_MARKER_EXTRA\n'));
    const prefix=print('SPLIT_');
    socket.write(prefix.subarray(0,7));
    setTimeout(() => socket.write(prefix.subarray(7)),10);
    setTimeout(() => {
      released=true;
      const suffix=print('MARKER\n');
      socket.write(suffix.subarray(0,18));
      setTimeout(() => socket.write(suffix.subarray(18)),10);
    },35);
  }});
  await fake.session.connect();
  const result = await fake.session.send(request('echo SPLIT_MARKER'),'SPLIT_MARKER',5);
  assert.equal(released,true);
  assert.equal(result.expected_output_received,true);
  assert.match(result.output,/SPLIT_MARKER\n$/);
});

test('missing marker times out, excludes old history and permits cleanup on same connection', async t => {
  const fake = await mockConsole(t,{onCommand(socket,text) {
    if (text==='echo CLEAN') socket.write(print('CLEAN\n'));
  }});
  await fake.session.connect();
  await assert.rejects(fake.session.send(request('echo MISSING'),'MISSING',0), error => {
    assert.match(error.message,/Expected game response/);
    assert.equal(error.output,'');
    return true;
  });
  assert.equal(fake.session.state,'ready');
  assert.equal(fake.state.fin,0,'a phase timeout does not reconnect the engine');
  await fake.session.send(request('echo CLEAN'),'CLEAN',0);
  await fake.session.close();
  assert.equal(fake.peers.length,1);
  assert.equal(fake.state.fin,1);
});

test('unexpected peer FIN rejects the pending request and sends one return FIN', async t => {
  const fake = await mockConsole(t,{onCommand(socket) {
    socket.write(print('partial reply\n'));
    socket.end();
  }});
  await fake.session.connect();
  await assert.rejects(fake.session.send(request('echo NOT_DONE'),'NOT_DONE'), error => {
    assert.match(error.message,/disconnected/);
    assert.match(error.output,/partial reply/);
    return true;
  });
  await fake.session.close();
  // The local close event can precede delivery of its FIN to the mock peer.
  await wait(10);
  assert.equal(fake.state.fin,1);
});

test('malformed native frame rejects pending work and closes with FIN', async t => {
  const fake = await mockConsole(t,{onCommand(socket) {
    const invalid=Buffer.alloc(12);invalid.write('PRNT');invalid.writeUInt32BE(1,6);
    socket.write(invalid);
  }});
  await fake.session.connect();
  await assert.rejects(fake.session.send(request('echo NO'),'NO'),/Invalid console frame length/);
  await fake.session.close();
  assert.equal(fake.state.fin,1);
});

test('unfinished buffered history fails without transmitting any gameplay command', async t => {
  const fake = await mockConsole(t,{session:{historyTimeoutMs:550},history(socket) {
    socket.write(print('VConsole Buffered Messages\nnever finished\n'));
  }});
  await assert.rejects(fake.session.connect(),/history replay did not complete/);
  await fake.session.close();
  assert.equal(fake.commands.length,0);
  assert.equal(fake.state.fin,1);
});

test('close cancels pending work, drains late output once and bounds unresponsive peers', async t => {
  const fake = await mockConsole(t,{onEnd(socket) {
    socket.write(print('late-after-FIN\n'));
    // Deliberately leave the peer writable to exercise the bounded drain.
  }});
  await fake.session.connect();
  const pending = fake.session.send(request('echo PENDING'),'PENDING');
  const rejection = assert.rejects(pending,/closed with a request pending/);
  await wait(10);
  const start=Date.now();
  await Promise.all([fake.session.close(),fake.session.close(),rejection]);
  assert.ok(Date.now()-start>=200 && Date.now()-start<1500);
  assert.equal(fake.state.fin,1);
  assert.doesNotMatch(fake.session.rawOutput,/late-after-FIN/);
});

test('request validation keeps fixed Tools Lua files and rejects arbitrary hosts/overlap/long lines', async t => {
  assert.throws(() => new ConsoleSession({host:'example.com'}),/127.0.0.1/);
  assert.throws(() => new ConsoleSession({port:70000}),/Invalid port/);
  const fake = await mockConsole(t,{onCommand(socket,text) {
    setTimeout(() => socket.write(print(text.startsWith('script_reload_code')?'LUA_DONE\n':'DONE\n')),25);
  }});
  await fake.session.connect();
  await assert.rejects(fake.session.send(request('x'.repeat(391))),/390 bytes/);
  await assert.rejects(fake.session.send(request('bad\0value')),/NUL/);
  await assert.rejects(fake.session.send([{name:'load_any_path',arguments:{path:'elsewhere'}}]),/Unsupported/);
  assert.equal(fake.commands.length,0);
  const code="print('LUA_DONE')";
  const script=luaScript(code);
  const lua = fake.session.send([{name:'dota_run_lua',arguments:{code,path:'../../maintained.lua'}}],'LUA_DONE',5);
  await assert.rejects(fake.session.send(request('echo OTHER'),'OTHER'),/already pending/);
  await lua;
  assert.equal(fake.commands[0].text,script.command);
  assert.match(script.relative,/^tests\/c6_console_generated\/request_[0-9a-f]{24}\.lua$/);
  const written=fs.readFileSync(path.resolve(__dirname,'../../scripts/vscripts',script.relative),'utf8');
  assert.equal(written,script.source);
  assert.match(written,/if not IsInToolsMode or not IsInToolsMode\(\) then return end/);
  const result=await fake.session.send(request('one\ntwo'),'DONE',5);
  assert.equal(result.sent,2);
  assert.equal(fake.peers.length,1);
});

test('requests without marker collect a bounded phase and do not disconnect', async t => {
  const fake = await mockConsole(t,{onCommand(socket) {socket.write(print('unstructured report\n'));}});
  await fake.session.connect();
  const result=await fake.session.send(request('vprof_generate_report'),'',30);
  assert.equal(result.expected_output_received,null);
  assert.match(result.output,/unstructured report/);
  assert.equal(fake.session.state,'ready');
  assert.equal(fake.state.fin,0);
});

test('refused connection rejects and close remains safe before or after connect', async () => {
  const unopened=new ConsoleSession();
  await unopened.close();
  await assert.rejects(unopened.connect(),/closed/);
  const server=net.createServer();
  await new Promise(resolve => server.listen(0,'127.0.0.1',resolve));
  const port=server.address().port;
  await new Promise(resolve => server.close(resolve));
  const refused=new ConsoleSession({port,timeoutMs:200});
  await assert.rejects(refused.connect(),error => error.code==='ECONNREFUSED');
  await refused.close();
  assert.equal(refused.state,'closed');
});

test('one second of CVRB before forty thousand historical lines cannot make the session ready', async t => {
  const fake=await mockConsole(t,{session:{historyTimeoutMs:5000},history(socket,state) {
    // Match the real failure: the first 350 ms contains no PRNT at all.
    let sent=0;
    const schema=setInterval(() => {
      socket.write(packet('CVRB',Buffer.alloc(50000)));
      if (++sent<10) return;
      clearInterval(schema);
      socket.write(print('VConsole Buffered Messages\n'));
      const rows=[print('EXTREME_CAPTURE_VALID\nEXTREME_CAPTURE_BEGIN\nEXTREME_CAPTURE_END\n')];
      for(let i=0;i<40000;i++)rows.push(print('old-history-'+i+'\n'));
      // Even this session's FIRST nonce inside history is not a live proof.
      rows.push(print(state.firstNonce+'\n'));
      rows.push(print('[CLIENT_CALLBACK_PROBE] {"old":true,"ms":39472}\n'));
      rows.push(print('End VConsole Buffered Messages\n'));
      socket.write(Buffer.concat(rows));
      state.historyEndAt=Date.now();state.historyFinished=true;
    },100);
  },onBarrier(socket,nonce,state) {
    state.firstNonce=state.firstNonce||nonce;
    if(state.historyFinished)socket.write(print(nonce+'\n'));
  },onCommand(socket) {socket.write(print('ACTUAL_NEW_PHASE\n'));}});
  let ready=false;
  const connected=fake.session.connect().then(() => {ready=true;});
  await wait(500);
  assert.equal(ready,false,'no first PRNT/nonce reply means no ready, even after 350 ms');
  assert.equal(fake.commands.length,0);
  await connected;
  assert.ok(fake.session.initialPrintFrames>=40005);
  assert.equal(fake.session.rawOutput,'');
  assert.match(fake.session.historyOutput,/old-history-39999/);
  assert.ok(fake.barriers.length>=2,'history END requires a fresh nonce');
  assert.notEqual(fake.barriers[0].nonce,fake.barriers[1].nonce);
  assert.notEqual(fake.session.readyProof.nonce,fake.state.firstNonce);
  const result=await fake.session.send(request('echo ACTUAL_NEW_PHASE'),'ACTUAL_NEW_PHASE',0);
  assert.equal(result.output,'ACTUAL_NEW_PHASE\n');
  assert.doesNotMatch(fake.session.rawOutput,/EXTREME_CAPTURE|old-history|CLIENT_CALLBACK_PROBE/);
  assert.ok(fake.commands[0].at-fake.state.historyEndAt>=330);
});

test('late history during a request is quarantined and pauses unsent commands without replay', async t => {
  const fake=await mockConsole(t,{session:{commandDelayMs:80},onCommand(socket,text,state) {
    if(text==='first') {
      socket.write(print('VConsole Buffered Messages\n'));
      socket.write(print('LATE_DONE\n[CLIENT_CALLBACK_PROBE] {"old":true}\n'));
      setTimeout(() => {
        socket.write(print('End VConsole Buffered Messages\n'));
        state.lateEndAt=Date.now();
      },70);
    } else socket.write(print('LATE_DONE\n'));
  }});
  await fake.session.connect();
  const result=await fake.session.send(request('first\nsecond'),'LATE_DONE',0);
  assert.equal(result.output,'LATE_DONE\n');
  assert.deepEqual(fake.commands.map(x=>x.text),['first','second']);
  assert.ok(fake.commands[1].at-fake.state.lateEndAt>=330);
  assert.equal(fake.session.lateHistoryReplays,1);
  assert.doesNotMatch(fake.session.rawOutput,/"old"/);
  assert.match(fake.session.historyOutput,/"old"/);
});
