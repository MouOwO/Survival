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




    const src=fs.readFileSync(path.join(__dirname,'../lottery_reference_review/reference-1045.png')).toString('base64'),actual=fs.readFileSync(path.join(__dirname,'real-grid.png')).toString('base64');
    const data=await run('('+(async function(src,actual){const imgs=await Promise.all([src,actual].map(async b=>{const i=new Image();i.src='data:image/png;base64,'+b;await i.decode();return i;}));const c=document.createElement('canvas');c.width=2090;c.height=820;const x=c.getContext('2d');x.fillStyle='#172f3b';x.fillRect(0,0,2090,820);x.fillStyle='#efe9d9';x.font='24px sans-serif';x.fillText('原版参考（1045 × 600，保持原比例）',24,35);x.fillText('裁切组装版（浏览器预览，四列两排布局）',1069,35);x.drawImage(imgs[0],0,130,1045,600);x.drawImage(imgs[1],103,54,1395,1014,1045,60,1045,760);return c.toDataURL();}).toString()+')('+JSON.stringify(src)+','+JSON.stringify(actual)+')');fs.writeFileSync(path.join(__dirname,'reference-comparison.png'),Buffer.from(data.split(',')[1],'base64'));
  }finally{if(ws)ws.close();chrome.kill()}
})().catch(e=>{console.error(e);process.exitCode=1});
