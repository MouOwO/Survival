const assert = require('node:assert/strict');
const net = require('node:net');
const {execFile} = require('node:child_process');
const {test} = require('node:test');
const {packet} = require('./console.cjs');

function print(value) {
  return packet('PRNT', Buffer.concat([Buffer.alloc(28), Buffer.from(value + '\0')]));
}

async function mockConsole(t, onCommand, onEnd = socket => socket.end()) {
  const connections = [], commands = [], handshakes = [];
  const server = net.createServer({allowHalfOpen: true}, socket => {
    connections.push(socket);
    socket.on('error', () => {});
    socket.on('end', () => onEnd(socket));
    let input = Buffer.alloc(0);
    socket.on('data', bytes => {
      input = Buffer.concat([input, bytes]);
      while (input.length >= 12) {
        const size = input.readUInt32BE(6);
        if (input.length < size) return;
        const frame = input.subarray(0, size);
        input = input.subarray(size);
        const kind = frame.toString('ascii', 0, 4);
        if (kind === 'VFCS') {
          handshakes.push(frame.subarray(12));
          socket.write(Buffer.concat([
            print('VConsole Buffered Messages\n'),
            print('history-secret\nTEST_DONE\n'),
            print('End VConsole Buffered Messages\n'),
          ]));
        } else if (kind === 'CMND') {
          commands.push(frame.subarray(12, -1).toString('utf8'));
          onCommand(socket);
        }
      }
    });
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(async () => {
    for (const socket of connections) socket.destroy();
    await new Promise(resolve => server.close(resolve));
  });
  return {connections, commands, handshakes, options: {
    port: server.address().port, commands: ['echo TEST_DONE'],
    expect: 'TEST_DONE', timeout: 200, delay: 0,
  }};
}

function runClient(options) {
  // Capture a separate client's stdout so node:test's own report stream is
  // never intercepted. The child only talks to this test's ephemeral port.
  const source = `require('./console.cjs').send(JSON.parse(process.argv[1]))
    .then(result => process.stdout.write('\\nTEST_RESULT:' + JSON.stringify(result)),
      error => { process.stderr.write(JSON.stringify({message: error.message, code: error.code}));
        process.exitCode = 1; });`;
  return new Promise((resolve, reject) => {
    execFile(process.execPath, ['-e', source, JSON.stringify(options)],
      {cwd: __dirname, timeout: 4000}, (error, stdout, stderr) => {
        if (error) {
          try { Object.assign(error, JSON.parse(stderr)); } catch {}
          error.output = stdout;
          reject(error);
          return;
        }
        const marker = stdout.lastIndexOf('\nTEST_RESULT:');
        try { resolve({result: JSON.parse(stdout.slice(marker + 13)), output: stdout.slice(0, marker)}); }
        catch (parseError) { reject(parseError); }
      });
  });
}

test('successful VConsole session sends FIN and drains late data without logging it', async t => {
  let clientEnded = false, peerEnded = false;
  const fake = await mockConsole(t, socket => socket.write(print('TEST_DONE\n')), socket => {
    clientEnded = true;
    setTimeout(() => {
      socket.write(print('late-secret\n'));
      peerEnded = true;
      socket.end();
    }, 35);
  });
  const {result, output: printed} = await runClient(fake.options);
  assert.equal(result.expected_output_received, true);
  assert.equal(result.sent, 1);
  assert.equal(clientEnded, true);
  assert.equal(peerEnded, true, 'success waits for peer close while draining');
  assert.equal(fake.connections.length, 1);
  assert.deepEqual(fake.handshakes, [Buffer.from([0])]);
  assert.deepEqual(fake.commands, ['echo TEST_DONE']);
  assert.match(printed, /TEST_DONE/);
  assert.doesNotMatch(printed, /history-secret|late-secret/);
});

test('successful session has bounded drain when the peer never closes', async t => {
  let finAt = 0;
  const fake = await mockConsole(t, socket => socket.write(print('TEST_DONE\n')), () => {
    finAt = Date.now();
  });
  const {result} = await runClient(fake.options);
  assert.equal(result.expected_output_received, true);
  assert.ok(finAt > 0, 'client sends FIN before forced cleanup');
  const drain = Date.now() - finAt;
  assert.ok(drain >= 150 && drain < 1500, `bounded drain took ${drain} ms`);
});

test('missing expected response still times out and buffered history cannot satisfy it', async t => {
  const fake = await mockConsole(t, () => {});
  const started = Date.now();
  await assert.rejects(runClient(fake.options), error => {
    assert.match(error.message, /Expected game response was not received/);
    assert.doesNotMatch(error.output, /history-secret|TEST_DONE/);
    return true;
  });
  assert.ok(Date.now() - started < 2000);
});

test('collection without an expected marker also closes gracefully', async t => {
  let clientEnded = false;
  const fake = await mockConsole(t, () => {}, socket => {
    clientEnded = true;
    socket.end();
  });
  const {result} = await runClient({...fake.options, expect: ''});
  assert.equal(result.expected_output_received, null);
  assert.equal(result.sent, 1);
  assert.equal(clientEnded, true);
});

test('refused connection rejects without hanging', async () => {
  const server = net.createServer();
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const port = server.address().port;
  await new Promise(resolve => server.close(resolve));
  await assert.rejects(runClient({port, commands: ['echo TEST_DONE'], expect: '', timeout: 200,
    delay: 0}), error => error.code === 'ECONNREFUSED');
});
