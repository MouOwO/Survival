'use strict';
// Private JSON-lines child of hammer_backend_bridge.py. This is not a network
// service. Console history stays inside the protocol parser and is discarded.
const crypto = require('node:crypto');
const {ConsoleSession} = require('./console-session.cjs');
const PREFIX = 'GOUFAYU_HAMMER_STATE:';
const INSPECT_COMMAND = 'survival_tools_hammer_bridge_inspect';
const INSTALL_ACK = 'SURVIVAL_TOOLS_HAMMER_BRIDGE_INSTALLED_V1';
// Fixed source produces at most two generated files, including command-loss repair.
const bootstrap = force => "local b=require('tests/manual_hammer_bridge_inspect');assert(b.prepare("+
  (force?'true':'false')+"));print('"+INSTALL_ACK+"')";

function stateFromLine(line) {
  if (typeof line !== 'string' || !line.startsWith(PREFIX)) return null;
  let value;
  try { value = JSON.parse(line.slice(PREFIX.length)); } catch { return null; }
  if (!value || typeof value !== 'object') return null;
  if (value.status === 'waiting_for_map') return {status:'waiting_for_map'};
  if (!['configured','authentication_required','waiting_for_party'].includes(value.status)
    || typeof value.session !== 'string' || value.session.length < 8 || value.session.length > 512) return null;
  const state = {status:value.status,
    session:crypto.createHash('sha256').update(value.session,'utf8').digest('hex')};
  for (const key of ['players','authenticated','loaded']) {
    const number = value[key] === undefined ? 0 : value[key];
    if (!Number.isInteger(number) || number < 0 || number > 64) return null;
    state[key] = number;
  }
  return state;
}

class Inspector {
  constructor({sessionFactory, now} = {}) {
    this.sessionFactory = sessionFactory || (() => new ConsoleSession({
      timeoutMs:2500, historyTimeoutMs:10000, retainOutput:false, maxPendingOutputChars:32768,
    }));
    this.now = now || Date.now;
    this.session = null;
    this.connections = 0;
    this.lastConnectAt = 0;
    this.failures = 0;
    this.retryAt = 0;
    this.closed = false;
    this.commandInstalled = false;
  }
  stats() {
    return {console_transport:'persistent_v1', console_connections_total:this.connections,
      console_connected:!!this.session && this.session.state === 'ready',
      console_last_connect_at:this.lastConnectAt};
  }
  async disconnect() {
    const session = this.session;
    this.session = null;
    this.commandInstalled = false;
    if (session) await session.close();
  }
  async close() { this.closed = true; await this.disconnect(); }
  async inspect(code) {
    if (this.closed) throw Error('worker_closed');
    if (typeof code !== 'string' || !code.trim() || Buffer.byteLength(code) > 60000 || code.includes('\0')) {
      throw Error('invalid_inspection');
    }
    if (this.now() < this.retryAt) return {status:'waiting_for_workshop'};
    try {
      if (!this.session || this.session.state !== 'ready') {
        await this.disconnect();
        this.session = this.sessionFactory();
        this.connections++;
        this.lastConnectAt = this.now() / 1000;
        await this.session.connect();
      }
      if (!this.commandInstalled) await this.install(false);
      let state, rebuild=false, force=false;
      try {
        state=await this.readState();
        rebuild=state?.status==='inspection_not_installed';
      } catch {
        // Only this read-only request may be retried. A closed socket still
        // follows the original disconnect/backoff path; gameplay/auth never replay.
        if (this.session.state!=='ready') throw Error('inspection_connection_closed');
        rebuild=true;force=true;
      }
      if (rebuild) {await this.install(force);state=await this.readState();}
      if (!state || state.status==='inspection_not_installed') throw Error('invalid_state');
      this.failures = 0;
      this.retryAt = 0;
      return state;
    } catch {
      // Never relay the exception or output: engine history may contain secrets.
      await this.disconnect();
      this.failures = Math.min(5, this.failures + 1);
      this.retryAt = this.now() + Math.min(30000, 1000 * 2 ** (this.failures - 1));
      return {status:'waiting_for_workshop'};
    }
  }
  async install(force) {
    this.commandInstalled=false;
    const result=await this.session.send([{name:'dota_run_lua',arguments:{code:bootstrap(force)}}],INSTALL_ACK,0);
    if (result.expected_output_received!==true) throw Error('inspection_install_failed');
    this.commandInstalled=true;
  }
  async readState() {
    const nonce=crypto.randomBytes(12).toString('hex'),prefix=PREFIX+nonce+':';
    const response=await this.session.send([{name:'console_send',arguments:{commands:INSPECT_COMMAND+' '+nonce}}],
      '',0,{responsePrefix:prefix});
    if (typeof response.matched_line!=='string'||!response.matched_line.startsWith(prefix)) throw Error('invalid_inspection_nonce');
    const line=PREFIX+response.matched_line.slice(prefix.length);
    if (line===PREFIX+'{"status":"inspection_not_installed"}') return {status:'inspection_not_installed'};
    const state=stateFromLine(line);
    if (!state) throw Error('invalid_state');
    return state;
  }
  async request(value) {
    const id = value && value.id;
    if (!Number.isSafeInteger(id) || id < 1 || !['inspect','disconnect','shutdown'].includes(value.op)) {
      return {id:Number.isSafeInteger(id) ? id : 0, ok:false, error:'invalid_request'};
    }
    try {
      let state;
      if (value.op === 'inspect') state = await this.inspect(value.code);
      else if (value.op === 'disconnect') await this.disconnect();
      else await this.close();
      return {id, ok:true, ...(state ? {state} : {}), stats:this.stats()};
    } catch { return {id, ok:false, error:'inspection_operation_failed', stats:this.stats()}; }
  }
}

function serve(input = process.stdin, output = process.stdout, inspector = new Inspector()) {
  let pending = '', queued = 0, chain = Promise.resolve(), stopping = false;
  const finish = () => {
    if (stopping) return;
    stopping = true;
    input.pause();
    input.destroy();
    chain = chain.finally(() => inspector.close());
  };
  const reply = value => new Promise(resolve => output.write(JSON.stringify(value)+'\n', resolve));
  input.setEncoding('utf8');
  input.on('data', chunk => {
    if (stopping) return;
    pending += chunk;
    if (Buffer.byteLength(pending) > 65536) { finish(); return; }
    let end;
    while ((end = pending.indexOf('\n')) !== -1) {
      const line = pending.slice(0,end); pending = pending.slice(end+1);
      if (++queued > 4) { finish(); return; }
      chain = chain.then(async () => {
        let value;
        try { value = JSON.parse(line); } catch { value = null; }
        const result = await inspector.request(value);
        await reply(result);
        queued--;
        if (value && value.op === 'shutdown') { stopping = true; input.destroy(); }
      }).catch(async () => { stopping = true; input.destroy(); await inspector.close(); });
    }
  });
  input.on('end', finish);
  input.on('error', finish);
  output.on('error', finish);
  return {close:async () => { finish(); await chain; }};
}

if (require.main === module) serve();
module.exports = {Inspector, stateFromLine, serve, PREFIX, INSPECT_COMMAND, INSTALL_ACK};
