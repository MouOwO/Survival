// Local, dependency-free browser checks. Does not connect to the game server.
const fs = require('fs'), path = require('path'), os = require('os'), assert = require('assert');
const { spawn } = require('child_process');
const { pathToFileURL } = require('url');
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
(async () => {
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'lottery-compact-review-'));
  const chrome = spawn('C:/Program Files/Google/Chrome/Application/chrome.exe', ['--headless', '--disable-gpu', '--no-first-run', '--no-default-browser-check', '--remote-debugging-port=0', '--user-data-dir=' + profile, pathToFileURL(path.join(__dirname, 'index.html')).href], { windowsHide: true, stdio: 'ignore' });
  let ws;
  try {
    const portFile = path.join(profile, 'DevToolsActivePort');
    for (let i = 0; i < 100 && !fs.existsSync(portFile); i++) await sleep(100);
    const port = fs.readFileSync(portFile, 'utf8').split('\n')[0];
    const targets = await (await fetch('http://127.0.0.1:' + port + '/json/list')).json();
    const target = targets.find(x => x.type === 'page');
    ws = new WebSocket(target.webSocketDebuggerUrl);
    await new Promise((resolve, reject) => { ws.onopen = resolve; ws.onerror = reject; });
    let serial = 0; const pending = new Map();
    ws.onmessage = event => { const m = JSON.parse(event.data); const p = pending.get(m.id); if (p) { pending.delete(m.id); m.error ? p.reject(new Error(JSON.stringify(m.error))) : p.resolve(m.result); } };
    const call = (method, params = {}) => new Promise((resolve, reject) => { const id = ++serial; pending.set(id, { resolve, reject }); ws.send(JSON.stringify({ id, method, params })); });
    const run = async expression => { const result = await call('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true }); if (result.exceptionDetails) throw new Error(JSON.stringify(result.exceptionDetails)); return result.result.value; };
    await call('Page.enable'); await call('DOM.enable'); await call('CSS.enable');
    await call('Emulation.setDeviceMetricsOverride', { width: 1600, height: 1080, deviceScaleFactor: 1, mobile: false });
    await run('document.fonts.ready');



    const report=await run('(()=>({count:document.images.length,broken:[...document.images].filter(i=>!i.complete||!i.naturalWidth).length}))()');assert.equal(report.broken,0);const screenshot=await call('Page.captureScreenshot',{format:'png',captureBeyondViewport:true,clip:{x:0,y:0,width:1600,height:2300,scale:1}});fs.writeFileSync(path.join(__dirname,'states.png'),Buffer.from(screenshot.data,'base64'));console.log(JSON.stringify(report));
  }finally{if(ws)ws.close();chrome.kill()}
})().catch(e=>{console.error(e);process.exitCode=1});
