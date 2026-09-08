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


    const sizes=[];
    for(const name of ['astrolabe','fan','potion']){
      const bytes=fs.readFileSync(path.join(__dirname,'sources',name+'.png')).toString('base64');
      const images=await run('('+ (async function(bytes){const image=new Image();image.src='data:image/png;base64,'+bytes;await image.decode();return [1,2].map(scale=>{const c=document.createElement('canvas');c.width=186*scale;c.height=142*scale;const ctx=c.getContext('2d');ctx.fillStyle='#e4edf2';ctx.fillRect(0,0,c.width,c.height);ctx.drawImage(image,22*scale,0,142*scale,142*scale);return c.toDataURL()})}).toString()+')('+JSON.stringify(bytes)+')');
      for(let i=0;i<2;i++){const file=name+'-'+(186*(i+1))+'x'+(142*(i+1))+'.png';fs.writeFileSync(path.join(__dirname,'../../panorama/src/images/custom_game/lottery_handoff/test_art',file),Buffer.from(images[i].split(',')[1],'base64'));sizes.push(file)}
    }
    const nine=await run('(()=>{const p=document.querySelector(".panel"),c=document.querySelector(".nine-slice").children;const before=[c[0].offsetWidth,c[0].offsetHeight];p.style.width="1200px";p.style.height="850px";const after=[c[0].offsetWidth,c[0].offsetHeight];p.style.width="1045px";p.style.height="760px";return {before,after,count:c.length}})()');assert.equal(nine.count,9);assert.deepEqual(nine.before,[32,32]);assert.deepEqual(nine.after,[32,32]);
    await run('render(false)');await sleep(300);await screenshot('test-grid.png');
    const check=await run('(()=>{const grid=document.querySelector(".grid"),r=grid.getBoundingClientRect();return {visible:[...grid.children].filter(c=>{const b=c.getBoundingClientRect();return b.top>=r.top-.1&&b.bottom<=r.bottom+.1}).length,broken:[...document.images].filter(i=>!i.naturalWidth).length,sizes:[...document.images].map(i=>[i.naturalWidth,i.naturalHeight])}})()');assert.equal(check.visible,8);assert.equal(check.broken,0);assert(check.sizes.every(s=>s[0]===372&&s[1]===284));
    await run('poolId="cultivation";render(false)');await sleep(100);await screenshot('selected-tab.png');
    await run('render(true)');await sleep(200);await screenshot('real-grid.png');
    fs.writeFileSync(path.join(__dirname,'verification.json'),JSON.stringify({sizes,check,native_game_capture:false},null,2));
    async function screenshot(name){const r=await call('Page.captureScreenshot',{format:'png'});fs.writeFileSync(path.join(__dirname,name),Buffer.from(r.data,'base64'))}
    console.log('COMPACT_PASS: 3 test illustrations, 6 normalized PNGs, 8 visible cards, no missing images');
  }finally{if(ws)ws.close();chrome.kill()}
})().catch(e=>{console.error(e);process.exitCode=1});
