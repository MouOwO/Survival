const assert = require('node:assert/strict');
const {test} = require('node:test');
const net = require('node:net');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const {pathToFileURL} = require('node:url');
const {hasLoopbackListener, isVconListening} = require('./vcon-readiness.cjs');
const {patchRelay} = require('./patch-mcp.cjs');

test('readiness accepts only local IPv4 listeners on the exact port', () => {
  for (const address of ['0.0.0.0', '127.0.0.1']) {
    assert.equal(hasLoopbackListener(`  TCP  ${address}:29000  0.0.0.0:0  LISTENING  123\r\n`, 29000), true);
  }
  for (const row of [
    'TCP  127.0.0.1:29000  127.0.0.1:42000  ESTABLISHED  123',
    'TCP  127.0.0.1:42000  127.0.0.1:29000  ESTABLISHED  123',
    'TCP  127.0.0.1:290001  0.0.0.0:0  LISTENING  123',
    'TCP  192.168.1.2:29000  0.0.0.0:0  LISTENING  123',
    'TCP  [::1]:29000  [::]:0  LISTENING  123',
    'UDP  127.0.0.1:29000  *:*  123',
    '',
  ]) assert.equal(hasLoopbackListener(row, 29000), false, row);
  assert.equal(hasLoopbackListener('TCP  0.0.0.0:0  0.0.0.0:0  LISTENING  1', 0), false);
});

test('OS inspection detects opening/closing a listener without ever connecting', {
  skip: process.platform !== 'win32',
}, async t => {
  let accepted = 0;
  const server = net.createServer(socket => { accepted++; socket.destroy(); });
  t.after(() => { if (server.listening) server.close(); });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const port = server.address().port;
  assert.equal(await isVconListening(port), true);
  assert.equal(await isVconListening(port), true);
  await new Promise(resolve => server.close(resolve));
  assert.equal(await isVconListening(port), false);
  assert.equal(accepted, 0);
});

const installed = path.join(process.env.DOTA2_MCP_INSTALL ||
  path.join(os.homedir(), '.codex/tools/dota2-mcp/node_modules'), 'dota2-mcp/dist/tools/vcon-relay.js');

test('patched relay coalesces polls and ignores results after GUI attach or shutdown', {
  skip: !fs.existsSync(installed),
}, async () => {
  const backup = installed + '.before-survival-socket-fix';
  const original = fs.readFileSync(fs.existsSync(backup) ? backup : installed, 'utf8');
  const source = patchRelay(original);
  if (fs.existsSync(backup)) assert.equal(source, fs.readFileSync(installed, 'utf8'),
    'reapplying to the saved upstream file must reproduce the installed repair');
  assert.equal(patchRelay(source), source, 'patch must be idempotent');
  assert.ok(!source.includes('_probeSock'), 'raw probe lifecycle must be fully removed');
  const start = source.indexOf('    async _probeTick() {');
  const method = source.slice(start, source.indexOf('    _scanMaps() {', start));
  let calls = 0, complete;
  const poll = new Function('vconReadiness', 'DOTA_PORT', `return ({${method}})._probeTick;`)({
    isVconListening: () => { calls++; return new Promise(resolve => { complete = resolve; }); },
  }, 29000);
  const changed = [];
  const relay = {_setReady: value => changed.push(value)};
  const first = poll.call(relay);
  await Promise.all(Array.from({length: 100}, () => poll.call(relay)));
  assert.equal(calls, 1, 'only one OS query may be in flight');
  complete(true);
  await first;
  assert.deepEqual(changed, [true]);

  for (const state of ['_guiConnected', '_closed', 'dotaClient']) {
    changed.length = 0;
    const pending = poll.call(relay);
    relay[state] = true;
    complete(false);
    await pending;
    assert.deepEqual(changed, [], 'late query must not overwrite active state: ' + state);
    const before = calls;
    await poll.call(relay);
    assert.equal(calls, before);
    relay[state] = false;
  }

  const fail = new Function('vconReadiness', 'DOTA_PORT', `return ({${method}})._probeTick;`)({
    isVconListening: async () => { throw new Error('OS inspection failed'); },
  }, 29000);
  await fail.call(relay);
  assert.deepEqual(changed, [false]);
  assert.equal(relay._readyProbePending, false);
});

test('installed relay identifies readiness through repeated ticks with zero engine connections', {
  skip: process.platform !== 'win32' || !fs.existsSync(installed),
}, async t => {
  assert.match(fs.readFileSync(installed, 'utf8'), /SURVIVAL_PASSIVE_VCON_READINESS_V1/,
    'Run node tools/map_c6/patch-mcp.cjs before installed integration verification');
  let accepted = 0;
  const server = net.createServer(socket => { accepted++; socket.destroy(); });
  t.after(() => { if (server.listening) server.close(); });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  process.env.DOTA2_VCON_DOTA_PORT = String(server.address().port);
  const {VConRelay} = await import(pathToFileURL(installed).href);
  const relay = new VConRelay({}, {enabled: false});
  t.after(() => relay.close());
  for (let i = 0; i < 6; i++) {
    await Promise.all(Array.from({length: 20}, () => relay._probeTick()));
    assert.equal(relay.dotaReady, true);
  }
  await new Promise(resolve => server.close(resolve));
  await relay._probeTick();
  assert.equal(relay.dotaReady, false);
  assert.equal(accepted, 0, '120 readiness ticks must open no game sockets');
});
