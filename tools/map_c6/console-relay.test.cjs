const assert = require('node:assert/strict');
const net = require('node:net');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {execFile} = require('node:child_process');
const {test} = require('node:test');
const {relayEndpoint} = require('./console-relay.cjs');

async function mockRelay(t, action = 'success') {
  const commands = [], sockets = [];
  const server = net.createServer(socket => {
    sockets.push(socket);
    socket.on('error', () => {});
    let buffer = '';
    const frame = value => socket.write(JSON.stringify(value) + '\n');
    const print = text => frame({type: 'prnt', text});
    socket.on('data', bytes => {
      buffer += bytes.toString('utf8');
      let index;
      while ((index = buffer.indexOf('\n')) >= 0) {
        const line = buffer.slice(0,index); buffer = buffer.slice(index+1);
        if (line.startsWith('HELLO ')) {
          assert.equal(line, 'HELLO ' + 'a'.repeat(48));
          if (action === 'deny') frame({type:'hello-err',reason:'secret-server-message'});
          else frame({type:'hello-ok',version:1,dota:action !== 'offline'});
        } else if (line === 'STREAM') {
          print('old-history-secret'); print('TEST_DONE');
        } else if (line.startsWith('CMD:echo SURVIVAL_CONSOLE_BEGIN_')) {
          print(line.slice(4)); // Echoed command must not open the output gate.
          print('old-before-fence-secret');
          print(line.slice('CMD:echo '.length));
        } else if (line.startsWith('CMD:')) {
          commands.push(line.slice(4));
          socket.write('OK\n');
          if (action === 'drop') { socket.destroy(); return; }
          if (action === 'timeout') continue;
          print('engine command echo');
          print('TEST_DONE'); // v1 trims trailing newlines, unlike direct PRNT.
        }
      }
    });
  });
  await new Promise(resolve => server.listen(0,'127.0.0.1',resolve));
  t.after(async () => {
    sockets.forEach(socket => socket.destroy());
    await new Promise(resolve => server.close(resolve));
  });
  return {commands, endpoint:{port:server.address().port,token:'a'.repeat(48)}};
}

function runClient(endpoint, extra = {}) {
  const options = {port:29000,commands:['echo TEST_DONE'],expect:'TEST_DONE',timeout:150,delay:0,...extra};
  const source = `const {sendWithTransport}=require('./console-relay.cjs');
    const [options,endpoint]=JSON.parse(process.argv[1]);
    sendWithTransport(options,async()=>({transport:'direct'}),endpoint)
      .then(value=>process.stdout.write('\\nRESULT:'+JSON.stringify(value)),
        error=>{process.stderr.write(error.message);process.exitCode=1;});`;
  return new Promise(resolve => execFile(process.execPath,['-e',source,JSON.stringify([options,endpoint])],
    {cwd:__dirname,timeout:3000}, (error,stdout,stderr) => resolve({error,stdout,stderr})));
}

test('shared relay uses fresh fence, preserves trimmed output boundaries and hides credentials/history', async t => {
  const relay = await mockRelay(t);
  const result = await runClient(relay.endpoint);
  assert.ifError(result.error);
  assert.match(result.stdout,/\nTEST_DONE\n/);
  assert.match(result.stdout,/"transport":"relay"/);
  assert.match(result.stdout,/"expected_output_received":true/);
  assert.doesNotMatch(result.stdout,/history-secret|before-fence-secret|SURVIVAL_CONSOLE_BEGIN_|a{48}/);
  assert.deepEqual(relay.commands,['echo TEST_DONE']);
  // A new short-lived connection also works after a game/assistant restart.
  assert.ifError((await runClient(relay.endpoint)).error);
  assert.equal(relay.commands.length,2);
});

for (const state of ['deny','offline']) {
  test(`relay ${state} falls back before dispatch without exposing its response`, async t => {
    const relay = await mockRelay(t,state);
    const result = await runClient(relay.endpoint);
    assert.ifError(result.error);
    assert.match(result.stdout,/"transport":"direct"/);
    assert.doesNotMatch(result.stdout+result.stderr,/secret-server-message|a{48}/);
    assert.equal(relay.commands.length,0);
  });
}

for (const state of ['drop','timeout']) {
  test(`relay ${state} after dispatch never replays a possibly completed command`, async t => {
    const relay = await mockRelay(t,state);
    const result = await runClient(relay.endpoint);
    assert(result.error);
    assert.doesNotMatch(result.stdout,/"transport":"direct"/);
    assert.equal(relay.commands.length,1);
    assert.doesNotMatch(result.stdout,/old-history-secret|old-before-fence-secret/);
  });
}

test('no relay and explicit alternate ports preserve direct operation', async t => {
  assert.match((await runClient(null)).stdout,/"transport":"direct"/);
  const relay = await mockRelay(t);
  assert.match((await runClient(relay.endpoint,{port:29009})).stdout,/"transport":"direct"/);
  assert.equal(relay.commands.length,0);
});

test('discovery requires private local state and a live PID without creating a daemon', t => {
  const root=fs.mkdtempSync(path.join(os.tmpdir(),'survival-relay-test-'));
  t.after(()=>fs.rmSync(root,{recursive:true,force:true}));
  t.mock.method(os,'tmpdir',()=>root);
  t.mock.method(os,'homedir',()=>root);
  assert.equal(relayEndpoint(),null);
  const directory=path.join(root,'dota2-mcp');fs.mkdirSync(directory);
  fs.writeFileSync(path.join(directory,'relay.pid'),String(process.pid));
  fs.writeFileSync(path.join(directory,'relay.token'),'a'.repeat(48));
  assert.equal(relayEndpoint().token,'a'.repeat(48));
  fs.writeFileSync(path.join(directory,'relay.pid'),'9999999999');
  assert.equal(relayEndpoint(),null);
  fs.writeFileSync(path.join(directory,'relay.pid'),String(process.pid));
  fs.writeFileSync(path.join(directory,'relay.token'),'invalid\ncontrol text');
  assert.equal(relayEndpoint(),null);
});
