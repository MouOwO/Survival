// Compatibility fixes for dota2-mcp 1.6.0 and this installed Source 2 client.
// Keep the GUI gate and VFCS handshake. Readiness must not connect/disconnect
// every second: the local 2026-10-02 dump ends in socket shutdown error 10038.
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const vm = require('node:vm');

function replaceOnce(source, from, to, name) {
  if (source.includes(to)) return source;
  if (!source.includes(from) || source.indexOf(from) !== source.lastIndexOf(from)) {
    throw new Error('Unsupported upstream code: ' + name);
  }
  return source.replace(from, to);
}

function patchBridge(source) {
  return replaceOnce(source.replace(/\r\n/g, '\n'), 'this.emit("connected");',
    'this.buffer = Buffer.alloc(0);\n                this.socket.write(Buffer.concat([buildHeader("VFCS", 1), Buffer.from([0])]));\n                this.emit("connected");',
    'VConsole handshake');
}

function patchRelay(source) {
  source = source.replace(/\r\n/g, '\n');
  source = replaceOnce(source, 'this.dotaClient.rawWrite(frame);',
    'if (frame.toString("ascii", 0, 4) !== "VFCS") this.dotaClient.rawWrite(frame);', 'GUI handshake');
  if (source.includes('// SURVIVAL_PASSIVE_VCON_READINESS_V1')) return source;
  const start = source.indexOf('    _probeTick() {');
  const end = source.indexOf('    _scanMaps() {', start);
  if (start < 0 || end < 0 || !source.slice(start, end).includes('probe.connect(DOTA_PORT, "127.0.0.1")')) {
    throw new Error('Unsupported upstream readiness probe');
  }
  source = source.slice(0, start) + `    // SURVIVAL_PASSIVE_VCON_READINESS_V1
    async _probeTick() {
        if (this._closed || this._guiConnected || this.dotaClient || this._readyProbePending)
            return;
        this._readyProbePending = true;
        try {
            const ready = await vconReadiness.isVconListening(DOTA_PORT);
            // A GUI connection or shutdown can overtake the OS query.
            if (!this._closed && !this._guiConnected && !this.dotaClient)
                this._setReady(ready);
        } catch {
            if (!this._closed && !this._guiConnected && !this.dotaClient)
                this._setReady(false);
        } finally {
            this._readyProbePending = false;
        }
    }
` + source.slice(end);
  source = replaceOnce(source, 'import * as net from "net";',
    'import * as net from "net";\nimport vconReadiness from "./survival-vcon-readiness.cjs";', 'readiness import');
  source = replaceOnce(source, 'readyProbeIntervalMs: 1_000,', 'readyProbeIntervalMs: 5_000,', 'readiness interval');
  source = replaceOnce(source, '    _probeSock = null;', '    _readyProbePending = false;', 'readiness state');
  const cleanup = '        if (this._probeSock) {\n            this._probeSock.destroy();\n            this._probeSock = null;\n        }\n';
  if (source.split(cleanup).length !== 3) throw new Error('Unsupported upstream probe cleanup');
  source = source.split(cleanup).join('');
  source = source.replace('TCP 连一下即断，不持有 29000', '只读取系统监听表，不连接 29000')
    .replace('    /** 无 GUI 时的就绪探测：TCP 连一下即断，不持有 29000（每次连接最多一个探针在飞） */',
      '    /** 无 GUI 时被动读取监听表，不向引擎创建或中断探测连接。 */')
    .replace('        // 严格门控：vconsole 接入才连 Dota。先掐死在飞的就绪探针——\n        // 它还占着引擎唯一客户端槽，会让首个真连接被拒（竞态，review 抓出）',
      '        // 严格门控：vconsole 接入才连 Dota；被动就绪检查不占用引擎连接。');
  return source;
}

function install(base = process.env.DOTA2_MCP_INSTALL || path.join(os.homedir(), '.codex/tools/dota2-mcp/node_modules')) {
  const dir = path.join(base, 'dota2-mcp/dist/tools');
  const helper = fs.readFileSync(path.join(__dirname, 'vcon-readiness.cjs'), 'utf8');
  new vm.Script(helper, {filename: 'vcon-readiness.cjs'});
  // Validate all source shapes before changing the installed package.
  const updates = [
    ['vcon-bridge.js', patchBridge(fs.readFileSync(path.join(dir, 'vcon-bridge.js'), 'utf8'))],
    ['vcon-relay.js', patchRelay(fs.readFileSync(path.join(dir, 'vcon-relay.js'), 'utf8'))],
  ];
  fs.writeFileSync(path.join(dir, 'survival-vcon-readiness.cjs'), helper);
  for (const [name, updated] of updates) {
    const target = path.join(dir, name);
    if (fs.readFileSync(target, 'utf8') === updated) {
      console.log(name + ': already patched');
      continue;
    }
    const backup = target + '.before-survival-socket-fix';
    if (!fs.existsSync(backup)) fs.copyFileSync(target, backup);
    fs.writeFileSync(target, updated);
    console.log(name + ': patched (original saved)');
  }
  console.log('Passive readiness installed. Restart any running dota2-mcp relay to load it.');
}

module.exports = {patchBridge, patchRelay, install};
if (require.main === module) install();
