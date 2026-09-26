// Optional adapter for the already running dota2-mcp relay. Never starts it,
// changes GUI settings, or includes either relay/backend credentials in output.
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const net = require('node:net');
const crypto = require('node:crypto');

function relayEndpoint() {
  const port = Number(process.env.DOTA2_VCON_CTRL_PORT || 29002);
  if (!Number.isInteger(port) || port < 1 || port > 65535) return null;
  for (const directory of [path.join(os.tmpdir(), 'dota2-mcp'), path.join(os.homedir(), '.dota2-mcp')]) {
    try {
      const tokenPath = path.join(directory, 'relay.token');
      const pidPath = path.join(directory, 'relay.pid');
      for (const file of [tokenPath, pidPath]) {
        const stat = fs.lstatSync(file);
        if (!stat.isFile() || stat.isSymbolicLink() || stat.size > 128) throw new Error('Invalid relay state');
      }
      const token = fs.readFileSync(tokenPath, 'utf8').trim();
      const pidText = fs.readFileSync(pidPath, 'utf8').trim();
      if (!/^[a-f0-9]{48}$/.test(token) || !/^[1-9][0-9]{0,9}$/.test(pidText)) continue;
      process.kill(Number(pidText), 0); // Liveness check only; never stops a process.
      return {port, token};
    } catch { /* No live local relay: retain the direct console transport. */ }
  }
  return null;
}

function sendRelay(options, endpoint) {
  return new Promise((resolve, reject) => {
    const socket = net.createConnection({host: '127.0.0.1', port: endpoint.port});
    const fence = 'SURVIVAL_CONSOLE_BEGIN_' + crypto.randomBytes(16).toString('hex');
    let buffer = '', outputTail = '', fenceTail = '', sent = 0, suppressed = 0;
    let hello = false, started = false, matched = false, attempted = false, done = false;
    let timer, sendTimer;
    function finish(message) {
      if (done) return;
      done = true;
      clearTimeout(timer); clearTimeout(sendTimer);
      socket.destroy();
      if (message) {
        const error = new Error(message);
        error.safeToFallback = !attempted;
        reject(error);
      } else resolve({sent, expected_output_received: options.expect ? matched : null,
        initial_print_frames_suppressed: suppressed, transport: 'relay'});
    }
    function timeout(ms, message) {
      clearTimeout(timer);
      timer = setTimeout(() => finish(message), ms);
    }
    function transmit() {
      if (done) return;
      // Once any real command was handed to the socket, an error must not
      // replay it on the direct connection: it may already have taken effect.
      attempted = true;
      socket.write('CMD:' + options.commands[sent] + '\n', error => {
        if (done) return;
        if (error) { finish('Console relay send failed'); return; }
        sent++;
        if (sent < options.commands.length) sendTimer = setTimeout(transmit, options.delay);
        else if (options.expect && matched) finish();
        else timeout(options.timeout, options.expect ? 'Expected game response was not received' : undefined);
      });
    }
    timeout(Math.min(options.timeout, 750), 'Console relay handshake timed out');
    socket.on('connect', () => socket.write('HELLO ' + endpoint.token + '\n'));
    socket.on('error', () => finish('Console relay connection unavailable'));
    socket.on('close', () => { if (!done) finish('Console relay disconnected'); });
    socket.on('data', bytes => {
      if (done) return;
      buffer += bytes.toString('utf8');
      if (buffer.length > 8 * 1024 * 1024) { finish('Invalid console relay frame'); return; }
      let index;
      while (!done && (index = buffer.indexOf('\n')) >= 0) {
        const line = buffer.slice(0, index); buffer = buffer.slice(index + 1);
        if (line === 'OK' || !line.trim()) continue;
        let value;
        try { value = JSON.parse(line); } catch { finish('Invalid console relay response'); return; }
        if (!value || typeof value !== 'object') { finish('Invalid console relay response'); return; }
        if (!hello) {
          if (value.type !== 'hello-ok' || value.version !== 1 || value.dota !== true) {
            finish('Console relay is not ready'); return;
          }
          hello = true;
          timeout(options.timeout, 'Console relay game response timed out');
          socket.write('STREAM\nCMD:echo ' + fence + '\n');
        } else if (value.type === 'status' && value.dota === false) {
          finish('Console relay game disconnected'); return;
        } else if (value.type === 'prnt' && typeof value.text === 'string') {
          // Relay v1 trims each engine PRNT message, including its newline.
          // Restore that boundary so nonce lines do not merge with commands.
          const text = value.text.endsWith('\n') ? value.text : value.text + '\n';
          if (!started) {
            suppressed++;
            fenceTail = (fenceTail + text).slice(-16384);
            if (fenceTail.split(/\r?\n/).some(text => text.trim() === fence)) {
              started = true;
              clearTimeout(timer);
              transmit();
            }
            continue;
          }
          process.stdout.write(text);
          outputTail = (outputTail + text).slice(-16384);
          if (options.expect && outputTail.split(/\r?\n/).some(text => text.trim() === options.expect)) matched = true;
          if (matched && sent === options.commands.length) finish();
        }
      }
    });
  });
}

async function sendWithTransport(options, direct, endpoint = relayEndpoint()) {
  // An explicit nonstandard port is caller-owned and must never be redirected.
  if (options.port === 29000 && endpoint) {
    try { return await sendRelay(options, endpoint); }
    catch (error) { if (!error.safeToFallback) throw error; }
  }
  return direct(options);
}

module.exports = {relayEndpoint, sendRelay, sendWithTransport};
