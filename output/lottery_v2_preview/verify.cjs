// Local, dependency-free browser checks. Does not connect to the game server.
const fs = require('fs'), path = require('path'), os = require('os'), assert = require('assert');
const { spawn } = require('child_process');
const { pathToFileURL } = require('url');
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
(async () => {
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'lottery-v2-review-'));
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

    const report={pools:[],icons:[],runtime:'Chrome component preview, not Dota'};
    for(const id of ['map','cultivation','dragon_knight','summer']){
      await run('showPool('+JSON.stringify(id)+')');await sleep(200);
      const result=await run('({pool:selectedPool,count:rewards.length,scrolling:document.querySelector(".grid").scrollHeight>document.querySelector(".grid").clientHeight,broken:[...document.images].filter(i=>!i.complete||!i.naturalWidth).length,selected:document.querySelector("#selection h2").textContent})');
      const bounds=await run('(()=>{const r=document.querySelector(".dialog").getBoundingClientRect();return {top:r.top,bottom:r.bottom,height:innerHeight}})()');assert(bounds.top>=42&&bounds.bottom<=bounds.height);assert.equal(result.pool,id);assert.equal(result.broken,0);assert(result.scrolling);report.pools.push(result);
      await screenshot('pool-'+id+'.png');
      await run('select(1)');assert.equal(await run('document.querySelectorAll(".reward.selected").length'),1);
      await run('document.querySelector(".grid").scrollTop=10000');
    }
    await run('showIcons()');await screenshot('icon-states.png');
    for(const n of await run('names')){
      const svg=fs.readFileSync(path.join(__dirname,'../../panorama/src/images/custom_game/lottery_handoff/icons',n+'.svg'),'utf8');
      const checks=await run('('+ (async function(svg){const image=new Image();image.src='data:image/svg+xml;base64,'+btoa(svg);await image.decode();return [16,24,32].map(size=>{const canvas=document.createElement('canvas');canvas.width=canvas.height=size;const c=canvas.getContext('2d');c.drawImage(image,0,0,size,size);const bytes=c.getImageData(0,0,size,size).data;let painted=0,black=0;for(let i=0;i<bytes.length;i+=4){if(bytes[i+3]){painted++;if(bytes[i+3]>16&&bytes[i]<20&&bytes[i+1]<20&&bytes[i+2]<20)black++}}return {size,cornerAlpha:bytes[3],painted,black}})}).toString()+')('+JSON.stringify(svg)+')');
      assert(checks.every(x=>x.cornerAlpha===0&&x.painted>0&&x.black===0),n+JSON.stringify(checks));report.icons.push({name:n,checks});
    }
    fs.writeFileSync(path.join(__dirname,'verification.json'),JSON.stringify(report,null,2));
    async function screenshot(name){const r=await call('Page.captureScreenshot',{format:'png'});fs.writeFileSync(path.join(__dirname,name),Buffer.from(r.data,'base64'))}
    console.log('V2_PREVIEW_PASS: four pool views, real item images, selection, scroll and 14 SVG edge checks');
  }finally{if(ws)ws.close();chrome.kill()}
})().catch(e=>{console.error(e);process.exitCode=1});
