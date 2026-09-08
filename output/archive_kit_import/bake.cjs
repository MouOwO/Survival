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



    const src=fs.readFileSync(path.join(__dirname,'../../panorama/src/images/custom_game/archive_kit/reusable/card_normal.png')).toString('base64');
    const slices=await run('('+(async function(src){const im=new Image();im.src='data:image/png;base64,'+src;await im.decode();const out=[];const xx=[0,12,im.width-12],yy=[0,12,im.height-12],ww=[12,im.width-24,12],hh=[12,im.height-24,12];for(let y=0;y<3;y++)for(let x=0;x<3;x++){const c=document.createElement('canvas');c.width=ww[x];c.height=hh[y];c.getContext('2d').drawImage(im,xx[x],yy[y],ww[x],hh[y],0,0,c.width,c.height);out.push({name:'card_'+y+x+'.png',png:c.toDataURL()});}return out;}).toString()+')('+JSON.stringify(src)+')');
    const dir=path.join(__dirname,'../../panorama/src/images/custom_game/archive_kit/clean_slices');fs.mkdirSync(dir,{recursive:true});slices.forEach(s=>fs.writeFileSync(path.join(dir,s.name),Buffer.from(s.png.split(',')[1],'base64')));console.log('ARCHIVE_CLEAN_SLICES_PASS');
  }finally{if(ws)ws.close();chrome.kill()}
})().catch(e=>{console.error(e);process.exitCode=1});
