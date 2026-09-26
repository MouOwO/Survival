// Local Source 2 console transport. Reuses an existing authenticated relay when
// available; otherwise connects directly. No MCP package or relay is required.
// Existing usage remains: node console.cjs "echo hello" 3500
// Request files use the console_send / dota_run_lua format of launch.json.
const fs = require('node:fs');
const net = require('node:net');
const crypto = require('node:crypto');
const path = require('node:path');
// The engine rejects long CMND lines; leave room below its observed limit.
const MAX_COMMAND_BYTES = 390;
const CLOSE_DRAIN_MS = 250;

function packet(type, body) {
  const buffer = Buffer.alloc(12 + body.length);
  buffer.write(type, 0, 4, 'ascii');
  buffer.writeUInt32BE(0x00d40000, 4);
  buffer.writeUInt32BE(buffer.length, 6);
  body.copy(buffer, 12);
  return buffer;
}

function printText(frame) {
  // Source 2 PRNT: 12-byte frame header, then 28 bytes of channel/severity/
  // color/time metadata. Text begins at byte 40 and ends with NUL. Metadata
  // contains arbitrary binary bytes and must never be UTF-8 decoded as text.
  if (frame.length < 40) throw new Error('Invalid PRNT metadata length');
  const end = frame.indexOf(0, 40);
  return frame.subarray(40, end < 0 ? frame.length : end).toString('utf8')
    .replace(/[\x00-\x08\x0e-\x1f]/g, '');
}

function luaScript(code) {
  if (typeof code !== 'string' || !code.trim() || code.includes('\0')) {
    throw new Error('dota_run_lua requires nonempty Lua code without NUL bytes');
  }
  // Dota's console has no `script` command. Keep source out of CMND entirely:
  // only an explicit script_reload_code loads this ignored tools-only file.
  // UTF-8, newlines and quoting are preserved without console escaping.
  const source = '-- Generated local console request; not loaded by gameplay.\n' +
    'if not IsInToolsMode or not IsInToolsMode() then return end\n' +
    'do\n' + code + '\nend\n';
  const id = crypto.createHash('sha256').update(source).digest('hex').slice(0, 24);
  const relative = `tests/c6_console_generated/request_${id}.lua`;
  return {relative, source, command: `script_reload_code ${relative}`};
}

function luaCommands(code) {
  return [luaScript(code).command];
}

function luaCommand(code) {
  const commands = luaCommands(code);
  if (commands.length !== 1) throw new Error('Lua requires multiple commands; use luaCommands');
  return commands[0];
}

function requestCommands(requests, luaFiles = []) {
  if (!Array.isArray(requests) || !requests.length) throw new Error('Expected a nonempty request array');
  const commands = [];
  for (const request of requests) {
    if (request?.name === 'dota_run_lua') {
      const script = luaScript(request.arguments?.code);
      luaFiles.push(script);
      commands.push(script.command);
    } else if (request?.name === 'console_send') {
      const value = request.arguments?.commands;
      if (typeof value !== 'string' || value.includes('\0')) throw new Error('console_send requires command text without NUL bytes');
      // Preserve semicolons inside quoted aliases. Split only physical lines.
      commands.push(...value.split(/\r?\n/).map(line => line.trim()).filter(Boolean));
    } else {
      throw new Error('Unsupported request type: ' + String(request?.name));
    }
  }
  if (!commands.length) throw new Error('No console commands to send');
  if (commands.some(command => Buffer.byteLength(command) > MAX_COMMAND_BYTES)) {
    throw new Error('Console command exceeds 390 bytes; split the source command before sending');
  }
  return commands;
}

function writeLuaFiles(luaFiles) {
  const scripts = path.resolve(__dirname, '../../scripts/vscripts');
  for (const script of luaFiles) {
    // Do not accept caller-selected filenames or overwrite maintained scripts.
    if (!/^tests\/c6_console_generated\/request_[0-9a-f]{24}\.lua$/.test(script.relative)) {
      throw new Error('Invalid generated Lua path');
    }
    const destination = path.join(scripts, script.relative);
    fs.mkdirSync(path.dirname(destination), {recursive: true});
    if (fs.existsSync(destination)) {
      if (fs.readFileSync(destination, 'utf8') !== script.source) throw new Error('Generated Lua file changed unexpectedly');
    } else fs.writeFileSync(destination, script.source, {encoding: 'utf8', flag: 'wx'});
  }
}

function parseArgs(argv) {
  const options = {port: 29000, timeout: 3500, delay: 25, expect: '', dryRun: false};
  const positional = [];
  for (let index = 0; index < argv.length; index++) {
    const arg = argv[index];
    if (arg === '--dry-run') { options.dryRun = true; continue; }
    if (['--file', '--expect', '--port', '--timeout-ms', '--delay-ms'].includes(arg)) {
      const value = argv[++index];
      if (value === undefined || value.startsWith('--')) throw new Error('Missing value for ' + arg);
      const key = {'--file': 'file', '--expect': 'expect', '--port': 'port', '--timeout-ms': 'timeout', '--delay-ms': 'delay'}[arg];
      options[key] = ['port', 'timeout', 'delay'].includes(key) ? Number(value) : value;
    } else if (arg.startsWith('--')) {
      throw new Error('Unknown option: ' + arg);
    } else positional.push(arg);
  }
  if (options.file && positional.length) throw new Error('--file cannot be combined with a command');
  if (positional.length > 2) throw new Error('Too many command arguments');
  if (positional[1] !== undefined) options.timeout = Number(positional[1]);
  if (!Number.isInteger(options.port) || options.port < 1 || options.port > 65535) throw new Error('Invalid port');
  if (!Number.isInteger(options.timeout) || options.timeout < 100 || options.timeout > 60000) throw new Error('Timeout must be 100..60000 ms');
  if (!Number.isInteger(options.delay) || options.delay < 0 || options.delay > 1000) throw new Error('Command delay must be 0..1000 ms');
  if (/[\r\n\0]/.test(options.expect)) throw new Error('--expect must be a single output line');
  options.luaFiles = [];
  options.commands = options.file
    ? requestCommands(JSON.parse(fs.readFileSync(options.file, 'utf8').replace(/^\uFEFF/, '')), options.luaFiles)
    : requestCommands([{name: 'console_send', arguments: {commands: positional[0] || 'echo C6_CONSOLE_CONNECTED'}}]);
  return options;
}

function send(options) {
  return new Promise((resolve, reject) => {
    const socket = net.createConnection({host: '127.0.0.1', port: options.port});
    let input = Buffer.alloc(0), outputTail = '', sent = 0, matched = false, done = false;
    let startedSending = false, initialPrintFrames = 0;
    let bufferedHistory = false, historyDeadline = 0;
    let sendTimer, responseTimer, closeTimer;
    const connectTimer = setTimeout(() => finish(new Error('Console connection timed out')), options.timeout);
    function finish(error) {
      if (done) return;
      done = true;
      clearTimeout(connectTimer); clearTimeout(sendTimer); clearTimeout(responseTimer);
      input = Buffer.alloc(0);
      function settle() {
        clearTimeout(closeTimer);
        if (error) reject(error);
        else resolve({sent, expected_output_received: options.expect ? matched : null,
          initial_print_frames_suppressed: initialPrintFrames});
      }
      if (error || socket.destroyed) {
        socket.destroy();
        settle();
        return;
      }
      // Finish successful sessions with FIN, then consume any remaining engine
      // output until it closes. Never leave a hung peer holding this tool open.
      socket.once('close', settle);
      closeTimer = setTimeout(() => { socket.destroy(); settle(); }, CLOSE_DRAIN_MS);
      socket.end();
    }
    function transmit() {
      if (done) return;
      if (bufferedHistory) {
        if (Date.now() >= historyDeadline) { finish(new Error('Console history replay did not complete')); return; }
        sendTimer = setTimeout(transmit, 25);
        return;
      }
      startedSending = true;
      socket.write(packet('CMND', Buffer.from(options.commands[sent] + '\0')), error => {
        if (done) return;
        if (error) { finish(error); return; }
        sent++;
        if (sent < options.commands.length) sendTimer = setTimeout(transmit, options.delay);
        else if (options.expect && matched) finish();
        else responseTimer = setTimeout(() => finish(options.expect && !matched
          ? new Error('Expected game response was not received: ' + options.expect) : undefined), options.timeout);
      });
    }
    socket.on('connect', () => {
      clearTimeout(connectTimer);
      historyDeadline = Date.now() + 10000;
      socket.write(packet('VFCS', Buffer.from([0])));
      sendTimer = setTimeout(transmit, 350);
    });
    socket.on('data', bytes => {
      if (done) return; // Drain late output without logging or retaining it.
      input = Buffer.concat([input, bytes]);
      while (!done && input.length >= 12) {
        const size = input.readUInt32BE(6);
        if (size < 12 || size > 8 * 1024 * 1024) { finish(new Error('Invalid console frame length')); return; }
        if (input.length < size) break;
        const frame = input.subarray(0, size);
        input = input.subarray(size);
        if (frame.toString('ascii', 0, 4) !== 'PRNT') continue;
        let value;
        try { value = printText(frame); } catch (error) { finish(error); return; }
        if (value.includes('End VConsole Buffered Messages')) {
          bufferedHistory = false; initialPrintFrames++; continue;
        }
        if (value.includes('VConsole Buffered Messages')) bufferedHistory = true;
        // Connecting flushes buffered engine history (plus large CVRB records).
        // Consume it for framing, but only report output after our first command.
        if (!startedSending || bufferedHistory) { initialPrintFrames++; continue; }
        process.stdout.write(value);
        // An echoed Lua command containing the token does not count as ready.
        outputTail = (outputTail + value).slice(-16384);
        if (options.expect && [value, outputTail].some(text => text.split(/\r?\n/).some(line => line.trim() === options.expect))) matched = true;
        if (matched && sent === options.commands.length) finish();
      }
    });
    socket.on('error', finish);
    socket.on('close', () => {
      if (!done) finish(sent !== options.commands.length ? new Error('Console disconnected before all commands were sent')
        : options.expect && !matched ? new Error('Console disconnected without the expected game response') : undefined);
    });
  });
}

async function main(argv) {
  const options = parseArgs(argv);
  if (options.dryRun) {
    console.log(JSON.stringify({dry_run: true, host: '127.0.0.1', port: options.port,
      expected_output: options.expect, commands: options.commands,
      generated_lua_files: options.luaFiles.map(file => file.relative)}));
    return;
  }
  writeLuaFiles(options.luaFiles);
  const result = await require('./console-relay.cjs').sendWithTransport(options, send);
  console.log('\n' + JSON.stringify(result));
}

module.exports = {packet, printText, luaScript, luaCommand, luaCommands, requestCommands, parseArgs, send, MAX_COMMAND_BYTES};
if (require.main === module) main(process.argv.slice(2)).catch(error => {
  console.error(error.message); process.exitCode = 1;
});
