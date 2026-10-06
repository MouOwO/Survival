// Observe the Windows listener table without creating a VConsole session.
// Source 2 can fatally fail during shutdown of repeated incomplete sessions.
const {execFile} = require('node:child_process');
const path = require('node:path');

function hasLoopbackListener(output, port) {
  if (!Number.isInteger(port) || port < 1 || port > 65535) return false;
  return String(output).split(/\r?\n/).some(line => {
    const fields = line.trim().split(/\s+/);
    // -p TCP reports IPv4. Only wildcard/loopback listeners can serve the
    // relay's 127.0.0.1 connection. Never match remote ports or established peers.
    return fields[0] === 'TCP' && fields[3] === 'LISTENING' &&
      (fields[1] === `127.0.0.1:${port}` || fields[1] === `0.0.0.0:${port}`);
  });
}

function isVconListening(port) {
  // This compatibility patch targets Windows Workshop Tools. On unsupported
  // systems or inspection failure, fail closed; never fall back to TCP probes.
  if (process.platform !== 'win32' || !Number.isInteger(port) || port < 1 || port > 65535) {
    return Promise.resolve(false);
  }
  const executable = path.join(process.env.SystemRoot || 'C:\\Windows', 'System32', 'netstat.exe');
  return new Promise(resolve => {
    execFile(executable, ['-ano', '-p', 'TCP'], {
      encoding: 'utf8', windowsHide: true, timeout: 3000, maxBuffer: 4 * 1024 * 1024,
    }, (error, stdout) => resolve(!error && hasLoopbackListener(stdout, port)));
  });
}

module.exports = {hasLoopbackListener, isVconListening};
