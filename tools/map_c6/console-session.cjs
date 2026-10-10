'use strict';
// Explicit local Tools capture transport. One connection spans the whole sample,
// so reconnecting and replaying VConsole history cannot become a measured hitch.
const fs = require('node:fs');
const net = require('node:net');
const path = require('node:path');
const crypto = require('node:crypto');
const {packet, printText, requestCommands} = require('./console.cjs');

function integer(value, fallback, minimum, maximum, name) {
  value = value === undefined ? fallback : value;
  if (!Number.isInteger(value) || value < minimum || value > maximum) {
    throw new Error(`Invalid ${name}: expected ${minimum}..${maximum}`);
  }
  return value;
}

function writeLuaFiles(files) {
  const scripts = path.resolve(__dirname, '../../scripts/vscripts');
  for (const script of files) {
    // requestCommands/luaScript supplies the Tools guard and content-derived hash.
    // A request never selects a filename and cannot overwrite maintained Lua.
    if (!/^tests\/c6_console_generated\/request_[0-9a-f]{24}\.lua$/.test(script.relative)) {
      throw new Error('Invalid generated Lua path');
    }
    const destination = path.join(scripts, script.relative);
    fs.mkdirSync(path.dirname(destination), {recursive: true});
    if (fs.existsSync(destination)) {
      if (fs.readFileSync(destination, 'utf8') !== script.source) {
        throw new Error('Generated Lua file changed unexpectedly');
      }
    } else fs.writeFileSync(destination, script.source, {encoding: 'utf8', flag: 'wx'});
  }
}

class ConsoleSession {
  constructor(options = {}) {
    if (options.host !== undefined && options.host !== '127.0.0.1') {
      throw new Error('Console sessions only connect to 127.0.0.1');
    }
    this.port = integer(options.port, 29000, 1, 65535, 'port');
    this.timeoutMs = integer(options.timeoutMs, 5000, 100, 60000, 'timeoutMs');
    this.historyTimeoutMs = integer(options.historyTimeoutMs, 10000, 500, 60000, 'historyTimeoutMs');
    this.commandDelayMs = integer(options.commandDelayMs, 25, 0, 1000, 'commandDelayMs');
    this.closeDrainMs = integer(options.closeDrainMs, 250, 50, 2000, 'closeDrainMs');
    this.retainOutput = options.retainOutput !== false;
    this.maxPendingOutputChars = integer(options.maxPendingOutputChars, 8 * 1024 * 1024,
      1024, 16 * 1024 * 1024, 'maxPendingOutputChars');
    this.state = 'new';
    this.input = Buffer.alloc(0);
    this.historyChunks = [];
    this.outputChunks = [];
    this.initialPrintFrames = 0;
    this.lateHistoryReplays = 0;
    this.pending = null;
    this.finSent = false;
  }

  get rawOutput() { return this.outputChunks.join(''); }
  get historyOutput() { return this.historyChunks.join(''); }

  connect() {
    if (this.connectPromise) return this.connectPromise;
    if (this.state !== 'new') return Promise.reject(new Error('Console session is closed'));
    this.state = 'connecting';
    this.connectPromise = new Promise((resolve, reject) => {
      this.connectResolve = resolve;
      this.connectReject = reject;
    });
    this.connectTimer = setTimeout(() => this.fail(new Error('Console connection timed out')), this.timeoutMs);
    const socket = this.socket = net.createConnection({
      host: '127.0.0.1', port: this.port, allowHalfOpen: true,
    });
    socket.setNoDelay(true);
    socket.on('connect', () => {
      if (this.state !== 'connecting') return;
      clearTimeout(this.connectTimer);
      this.state = 'history';
      this.historyTimer = setTimeout(() => this.fail(new Error('Console history replay did not complete')), this.historyTimeoutMs);
      socket.write(packet('VFCS', Buffer.from([0])), error => { if (error) this.fail(error); });
      // Silence is not readiness: CVRB/schema replay can take over a second
      // before the first PRNT/history marker. Require an actual fresh reply.
      this.requestBarrier();
    });
    socket.on('data', bytes => this.read(bytes));
    socket.on('error', error => this.fail(error));
    socket.on('end', () => {
      if (this.state !== 'closing' && this.state !== 'closed') {
        this.fail(new Error('Console disconnected during persistent session'));
      }
    });
    socket.on('close', () => {
      if (this.state !== 'closing' && this.state !== 'closed') {
        this.fail(new Error('Console disconnected during persistent session'));
      }
      this.state = 'closed';
      clearTimeout(this.closeTimer);
      if (this.closeResolve) this.closeResolve();
    });
    return this.connectPromise;
  }

  scheduleWarmup() {
    clearTimeout(this.warmupTimer);
    this.warmupTimer = setTimeout(() => {
      if (this.state !== 'history' || this.bufferedHistory || !this.barrierMatched) return;
      clearTimeout(this.historyTimer);
      this.state = 'ready';
      this.readyProof = {nonce:this.barrierNonce, receivedAt:this.barrierReceivedAt, readyAt:Date.now()};
      const resolve = this.connectResolve;
      this.connectResolve = this.connectReject = null;
      if (resolve) resolve(this);
      const pending = this.pending;
      if (pending) {
        if (pending.sent < pending.commands.length) pending.transmit();
        else { this.armResponseTimeout(pending); this.maybeDrain(pending); }
      }
    }, 350);
  }

  requestBarrier() {
    if (this.state !== 'history' || this.bufferedHistory) return;
    clearTimeout(this.warmupTimer);
    this.barrierNonce = 'SURVIVAL_CONSOLE_SESSION_READY_' + crypto.randomBytes(16).toString('hex');
    this.barrierTail = '';
    this.barrierMatched = false;
    this.socket.write(packet('CMND', Buffer.from('echo ' + this.barrierNonce + '\0')),
      error => { if (error) this.fail(error); });
  }

  suspendForHistory() {
    // Handle late history regardless of the current phase. Already sent game
    // commands are never replayed; later commands pause until a fresh barrier.
    if (this.state === 'ready') {
      this.lateHistoryReplays++;
      this.state = 'history';
      this.historyTimer = setTimeout(() => this.fail(new Error('Late console history replay did not complete')), this.historyTimeoutMs);
    }
    clearTimeout(this.warmupTimer);
    this.barrierNonce = null;
    this.barrierTail = '';
    this.barrierMatched = false;
    const pending = this.pending;
    if (pending) {
      clearTimeout(pending.sendTimer);
      clearTimeout(pending.timeout);
      clearTimeout(pending.drainTimer);
      pending.draining = false;
      pending.tail = '';
    }
  }

  consumeBarrier(value) {
    if (this.bufferedHistory || !this.barrierNonce || this.barrierMatched) return;
    this.barrierTail = (this.barrierTail + value).slice(-16384);
    if (this.barrierTail.split(/\r?\n/).slice(0,-1).some(line => line.trim() === this.barrierNonce)) {
      this.barrierMatched = true;
      this.barrierReceivedAt = Date.now();
      this.scheduleWarmup();
    }
  }

  read(bytes) {
    if (this.state === 'closed') return;
    // Late bytes after FIN are drained without allocating retained log data.
    if (this.state === 'closing') return;
    this.input = this.input.length ? Buffer.concat([this.input, bytes]) : bytes;
    while (this.input.length >= 12) {
      const size = this.input.readUInt32BE(6);
      if (size < 12 || size > 8 * 1024 * 1024) {
        this.fail(new Error('Invalid console frame length'));
        return;
      }
      if (this.input.length < size) break;
      const frame = this.input.subarray(0, size);
      this.input = this.input.subarray(size);
      if (frame.toString('ascii', 0, 4) !== 'PRNT') continue;
      let value;
      try { value = printText(frame); } catch (error) { this.fail(error); return; }
      const historyEnd = value.includes('End VConsole Buffered Messages');
      const historyStart = !historyEnd && value.includes('VConsole Buffered Messages');
      if (historyStart || historyEnd) {
        this.suspendForHistory();
        this.initialPrintFrames++;
        if (this.retainOutput) this.historyChunks.push(value);
        this.bufferedHistory = !historyEnd;
        // The first barrier may itself have appeared inside buffered history.
        // Send a new unpredictable one after END, never accept that old reply.
        if (historyEnd) this.requestBarrier();
        continue;
      }
      if (this.state === 'history') {
        this.initialPrintFrames++;
        if (this.retainOutput) this.historyChunks.push(value);
        this.consumeBarrier(value);
        continue;
      }
      if (this.retainOutput) this.outputChunks.push(value);
      const pending = this.pending;
      if (!pending) continue;
      pending.chunks.push(value);
      pending.outputChars += value.length;
      if (pending.outputChars > this.maxPendingOutputChars) {
        pending.chunks = [pending.chunks.join('').slice(-this.maxPendingOutputChars)];
        pending.outputChars = pending.chunks[0].length;
        pending.outputTruncated = true;
      }
      // JSON probe reports can exceed 16KB. Prefix requests have a bounded
      // larger line window; exact nonce requests keep the small marker tail.
      pending.tail = (pending.tail + value).slice(-(pending.responsePrefix
        ? Math.min(this.maxPendingOutputChars,262144) : 16384));
      // Only complete output lines match: command echoes and token prefixes
      // cannot complete a request, even when TCP/PRNT split the real marker.
      if (pending.expect && pending.tail.split(/\r?\n/).slice(0, -1)
        .some(line => line.trim() === pending.expect)) pending.matched = true;
      if (pending.responsePrefix && !pending.matched) {
        const line = pending.tail.split(/\r?\n/).slice(0, -1)
          .find(line => line.startsWith(pending.responsePrefix));
        if (line) { pending.matched = true; pending.matchedLine = line; }
      }
      this.maybeDrain(pending);
    }
  }

  prepare(requests) {
    const files = [];
    const commands = requestCommands(requests, files);
    writeLuaFiles(files);
    return commands;
  }

  async send(requests, expect = '', drainMs = 250, options = {}) {
    if (this.state !== 'ready') throw new Error('Console session is not connected');
    if (this.pending) throw new Error('A console request is already pending');
    if (typeof expect !== 'string' || /[\r\n\0]/.test(expect)) {
      throw new Error('Expected marker must be a single output line');
    }
    const responsePrefix = options.responsePrefix || '';
    if (typeof responsePrefix !== 'string' || /[\r\n\0]/.test(responsePrefix)
      || responsePrefix.length > 256 || (responsePrefix && expect)) {
      throw new Error('Response prefix must be a single output prefix without an expected marker');
    }
    drainMs = integer(drainMs, 250, 0, 10000, 'drainMs');
    // The shared parser enforces nonempty requests, no NUL and 390-byte lines.
    const commands = this.prepare(requests);
    return new Promise((resolve, reject) => {
      const pending = this.pending = {commands, expect, responsePrefix, drainMs, sent: 0,
        matched: false, matchedLine: null, tail: '', chunks: [], outputChars: 0,
        outputTruncated: false, resolve, reject};
      const transmit = pending.transmit = () => {
        if (this.pending !== pending || this.state !== 'ready' || pending.writeInFlight) return;
        pending.writeInFlight = true;
        this.socket.write(packet('CMND', Buffer.from(commands[pending.sent] + '\0')), error => {
          pending.writeInFlight = false;
          if (this.pending !== pending) return;
          if (error) { this.fail(error); return; }
          pending.sent++;
          if (pending.sent < commands.length) {
            pending.sendTimer = setTimeout(transmit, this.commandDelayMs);
          } else {
            this.armResponseTimeout(pending);
            this.maybeDrain(pending);
          }
        });
      };
      transmit();
    });
  }

  armResponseTimeout(pending) {
    clearTimeout(pending.timeout);
    if (this.state !== 'ready' || this.pending !== pending) return;
    pending.timeout = setTimeout(() => this.finishPending(pending,
      new Error('Expected game response was not received: ' + pending.expect)), this.timeoutMs);
  }

  maybeDrain(pending) {
    if (this.state !== 'ready' || this.pending !== pending || pending.draining || pending.sent !== pending.commands.length
      || ((pending.expect || pending.responsePrefix) && !pending.matched)) return;
    pending.draining = true;
    clearTimeout(pending.timeout);
    pending.drainTimer = setTimeout(() => this.finishPending(pending), pending.drainMs);
  }

  finishPending(pending, error) {
    if (this.pending !== pending) return;
    this.pending = null;
    clearTimeout(pending.sendTimer);
    clearTimeout(pending.timeout);
    clearTimeout(pending.drainTimer);
    const output = pending.chunks.join('');
    if (error) {
      error.output = output;
      error.sent = pending.sent;
      pending.reject(error);
    } else pending.resolve({output, sent: pending.sent,
      expected_output_received: pending.expect || pending.responsePrefix ? pending.matched : null,
      matched_line: pending.matchedLine, output_truncated: pending.outputTruncated});
  }

  fail(error) {
    if (this.state === 'closed' || this.state === 'closing') return;
    if (this.connectReject) {
      this.connectReject(error);
      this.connectResolve = this.connectReject = null;
    }
    if (this.pending) this.finishPending(this.pending, error);
    void this.close();
  }

  close() {
    if (this.closePromise) return this.closePromise;
    this.closePromise = new Promise(resolve => { this.closeResolve = resolve; });
    clearTimeout(this.connectTimer);
    clearTimeout(this.historyTimer);
    clearTimeout(this.warmupTimer);
    if (this.connectReject) {
      this.connectReject(new Error('Console session closed before ready'));
      this.connectResolve = this.connectReject = null;
    }
    if (this.pending) this.finishPending(this.pending, new Error('Console session closed with a request pending'));
    const socket = this.socket;
    this.input = Buffer.alloc(0);
    if (!socket || socket.destroyed) {
      this.state = 'closed';
      this.closeResolve();
      return this.closePromise;
    }
    this.state = 'closing';
    if (socket.connecting || !socket.writable) {
      socket.destroy();
    } else {
      // FIN exactly once, even if a timeout, caller cleanup and peer close race.
      if (!this.finSent) { this.finSent = true; socket.end(); }
      this.closeTimer = setTimeout(() => socket.destroy(), this.closeDrainMs);
    }
    return this.closePromise;
  }
}

async function connect(options) {
  const session = new ConsoleSession(options);
  return session.connect();
}

module.exports = {ConsoleSession, connect};
