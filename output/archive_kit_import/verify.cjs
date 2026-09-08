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



    await call('Emulation.setDeviceMetricsOverride',{width:1672,height:941,deviceScaleFactor:1,mobile:false});await run('document.fonts.ready');const result=await run('(()=>{const grid=document.querySelector(".grid"),r=grid.getBoundingClientRect();return {visible:[...grid.children].filter(c=>{const b=c.getBoundingClientRect();return b.top>=r.top-.1&&b.bottom<=r.bottom+.1}).length,broken:[...document.images].filter(i=>!i.complete||!i.naturalWidth).length}})()');assert.equal(result.visible,12);assert.equal(result.broken,0);const snap=await call('Page.captureScreenshot',{format:'png'});fs.writeFileSync(path.join(__dirname,'preview.png'),Buffer.from(snap.data,'base64'));fs.writeFileSync(path.join(__dirname,'verification.json'),JSON.stringify({...result,native_game_capture:false}));const reference=fs.readFileSync(path.join(__dirname,'archive_ui_kit_v1/reference/progress_mockup.png')).toString('base64');const comparison=await run('('+(async function(reference,actual){const images=await Promise.all([reference,actual].map(async data=>{const image=new Image();image.src='data:image/png;base64,'+data;await image.decode();return image;}));const c=document.createElement('canvas');c.width=3344;c.height=981;const ctx=c.getContext('2d');ctx.fillStyle='#17343e';ctx.fillRect(0,0,c.width,c.height);ctx.fillStyle='#efe8d0';ctx.font='24px sans-serif';ctx.fillText('包内参考',20,30);ctx.fillText('浏览器预览（零进度测试数据，非游戏截图）',1692,30);ctx.drawImage(images[0],0,40,1672,941);ctx.drawImage(images[1],1672,40,1672,941);const side=c.toDataURL();c.width=1672;c.height=941;ctx.drawImage(images[0],0,0,1672,941);ctx.globalAlpha=.5;ctx.drawImage(images[1],0,0,1672,941);return {side,overlay:c.toDataURL()};}).toString()+')('+JSON.stringify(reference)+','+JSON.stringify(snap.data)+')');for(const key of ['side','overlay'])fs.writeFileSync(path.join(__dirname,key+'.png'),Buffer.from(comparison[key].split(',')[1],'base64'));console.log('ARCHIVE_PREVIEW_PASS: four columns, three complete rows, no missing images');
  }finally{if(ws)ws.close();chrome.kill()}
})().catch(e=>{console.error(e);process.exitCode=1});
