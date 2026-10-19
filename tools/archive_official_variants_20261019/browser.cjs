'use strict';

// Local-only Chrome helper. It creates its own isolated profile beneath output
// and never uses an existing interactive browser session.
const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');
const { pathToFileURL } = require('url');

const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

async function browser(options = {}) {
  const output = path.resolve(options.output || 'output/archive_official_variants_20261019');
  fs.mkdirSync(output, { recursive: true });
  const profile = path.join(output, 'browser_profile_' + Date.now() + '_' + process.pid + '_' + Math.random().toString(36).slice(2, 10));
  fs.mkdirSync(profile, { recursive: true });
  const executable = options.executable || 'C:/Program Files/Google/Chrome/Application/chrome.exe';
  const processHandle = spawn(executable, [
    '--headless', '--disable-background-networking', '--disable-component-update',
    '--disable-sync', '--disable-extensions', '--disable-domain-reliability',
    '--no-proxy-server', '--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE localhost, EXCLUDE 127.0.0.1',
    '--disable-gpu', '--no-first-run', '--no-default-browser-check',
    '--remote-debugging-port=0', '--user-data-dir=' + profile, 'about:blank'
  ], { windowsHide: true, stdio: 'ignore' });
  let socket;
  const events = [];
  let closed = false;
  const close = async () => {
    if (closed) return;
    closed = true;
    if (socket) socket.close();
    processHandle.kill();
    // Only this exact task-owned temporary profile is eligible for cleanup.
    const resolved = path.resolve(profile);
    if (path.dirname(resolved) === output && path.basename(resolved).startsWith('browser_profile_')) {
      for (let attempt = 0; attempt < 10; attempt++) {
        try { fs.rmSync(resolved, { recursive: true, force: true }); break; }
        catch (_) { await sleep(100); }
      }
    }
  };
  try {
    const portFile = path.join(profile, 'DevToolsActivePort');
    for (let attempt = 0; attempt < 150 && !fs.existsSync(portFile); attempt++) {
      if (processHandle.exitCode !== null) throw new Error('Isolated Chrome exited before DevTools was ready');
      await sleep(100);
    }
    if (!fs.existsSync(portFile)) throw new Error('Isolated Chrome did not expose a DevTools port');
    const port = fs.readFileSync(portFile, 'utf8').split('\n')[0];
    let page;
    for (let attempt = 0; attempt < 100 && !page; attempt++) {
      try {
        const pages = await (await fetch('http://127.0.0.1:' + port + '/json/list')).json();
        page = pages.find(value => value.type === 'page');
      } catch (_) { /* Browser target can appear after the HTTP endpoint. */ }
      if (!page) await sleep(100);
    }
    if (!page) throw new Error('Isolated Chrome page target was unavailable');
    socket = new WebSocket(page.webSocketDebuggerUrl);
    await new Promise((resolve, reject) => { socket.onopen = resolve; socket.onerror = reject; });
    let serial = 0;
    const pending = new Map();
    socket.onmessage = event => {
      const message = JSON.parse(event.data);
      const request = pending.get(message.id);
      if (request) {
        pending.delete(message.id);
        message.error ? request.reject(new Error(JSON.stringify(message.error))) : request.resolve(message.result);
      } else if (message.method) events.push(message);
    };
    const call = (method, params = {}) => new Promise((resolve, reject) => {
      const id = ++serial;
      pending.set(id, { resolve, reject });
      socket.send(JSON.stringify({ id, method, params }));
    });
    const run = async expression => {
      const result = await call('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true });
      if (result.exceptionDetails) throw new Error(JSON.stringify(result.exceptionDetails));
      return result.result.value;
    };
    const viewport = async (width, height) => call('Emulation.setDeviceMetricsOverride', { width, height, deviceScaleFactor: 1, mobile: false });
    await call('Page.enable');
    await call('Runtime.enable');
    await viewport(options.width || 1600, options.height || 900);
    const go = async (file, query = '') => {
      await call('Page.navigate', { url: pathToFileURL(path.resolve(file)).href + query });
      let complete = false;
      for (let attempt = 0; attempt < 150; attempt++) {
        await sleep(60);
        if (await run('document.readyState === "complete"')) { complete = true; break; }
      }
      if (!complete) throw new Error('Timed out loading local preview: ' + file);
      await run('document.fonts.ready.then(() => true)');
      await run('Promise.all([...document.images].map(image => { image.loading = "eager"; return image.decode().catch(() => false); })).then(() => true)');
      await sleep(200);
    };
    const shot = async (file, clip) => {
      fs.mkdirSync(path.dirname(file), { recursive: true });
      const result = await call('Page.captureScreenshot', {
        format: 'png', captureBeyondViewport: true,
        ...(clip ? { clip: { ...clip, scale: 1 } } : {})
      });
      fs.writeFileSync(file, Buffer.from(result.data, 'base64'));
    };
    const move = async (x, y) => { await call('Input.dispatchMouseEvent', { type: 'mouseMoved', x, y }); await sleep(120); };
    const click = async (x, y) => {
      await move(x, y);
      await call('Input.dispatchMouseEvent', { type: 'mousePressed', x, y, button: 'left', clickCount: 1 });
      await call('Input.dispatchMouseEvent', { type: 'mouseReleased', x, y, button: 'left', clickCount: 1 });
      await sleep(100);
    };
    return { call, run, viewport, go, shot, move, click, close, events };
  } catch (error) {
    await close();
    throw error;
  }
}

module.exports = { browser, sleep };

if (require.main === module) {
  (async () => {
    const active = await browser();
    try { await active.go(process.argv[2], process.argv[4] || ''); await active.shot(process.argv[3]); }
    finally { await active.close(); }
  })().catch(error => { console.error(error); process.exitCode = 1; });
}
