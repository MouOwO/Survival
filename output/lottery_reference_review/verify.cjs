// Local, dependency-free browser checks. Does not connect to the game server.
const fs = require('fs'), path = require('path'), os = require('os'), assert = require('assert');
const { spawn } = require('child_process');
const { pathToFileURL } = require('url');
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
(async () => {
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'lottery-reference-review-'));
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


    await run('document.body.classList.add("baseline");showPool("map")');await sleep(150);
    const rect=await run('(()=>{const r=document.querySelector(".dialog").getBoundingClientRect();return {x:r.x,y:r.y,width:r.width,height:r.height}})()');
    assert.equal(rect.width,1045);assert.equal(rect.height,600);
    const screenshot=await call('Page.captureScreenshot',{format:'png',clip:{...rect,scale:1}});
    fs.writeFileSync(path.join(__dirname,'actual-1045.png'),Buffer.from(screenshot.data,'base64'));
    const ref=fs.readFileSync(path.join(__dirname,'../lottery_v2_preview/pool_details_reference.png')).toString('base64');
    const comparisons=await run('('+ (async function(reference,current){
      async function image(data){const i=new Image();i.src='data:image/png;base64,'+data;await i.decode();return i}
      const ref=await image(reference),actual=await image(current),canvas=document.createElement('canvas');canvas.width=1045;canvas.height=600;const c=canvas.getContext('2d');
      c.fillStyle='#234754';c.fillRect(0,0,1045,600);const scale=1045/1140,dy=(600-646*scale)/2;c.drawImage(ref,266,155,1140,646,0,dy,1045,646*scale);const normalized=canvas.toDataURL();
      c.globalAlpha=.5;c.drawImage(actual,0,0);c.globalAlpha=1;const overlay=canvas.toDataURL();
      const side=document.createElement('canvas');side.width=2090;side.height=638;const d=side.getContext('2d');d.fillStyle='#183441';d.fillRect(0,0,2090,638);d.fillStyle='#f3eee2';d.font='20px sans-serif';d.fillText('参考图：等比归一到 1045×600',20,26);d.fillText('当前组件预览：1045×600（非游戏实测截图）',1065,26);const norm=await image(normalized.split(',')[1]);d.drawImage(norm,0,38);d.drawImage(actual,1045,38);
      return {reference:normalized,overlay,side:side.toDataURL()};
    }).toString()+')('+JSON.stringify(ref)+','+JSON.stringify(screenshot.data)+')');
    for(const [key,name] of Object.entries({reference:'reference-1045.png',overlay:'overlay-50.png',side:'side-by-side.png'}))fs.writeFileSync(path.join(__dirname,name),Buffer.from(comparisons[key].split(',')[1],'base64'));
    const geometry=await run('(()=>{const p=document.querySelector(".dialog").getBoundingClientRect(),out={};for(const [name,sel] of Object.entries({header:".heading",tabs:"nav",grid:".grid",card:".reward",details:"aside",footer:"footer",confirm:".confirm"})){const r=document.querySelector(sel).getBoundingClientRect();out[name]={x:r.x-p.x,y:r.y-p.y,width:r.width,height:r.height}}return out})()');
    const design=JSON.parse(fs.readFileSync(path.join(__dirname,'design.json')));for(const key of ['grid','details','footer','confirm'])for(const prop of ['x','y','width','height'])assert(Math.abs(geometry[key][prop]-design[key][prop])<=2,key+' '+prop);
    const grid=await run('(()=>{const g=document.querySelector(".grid"),r=g.getBoundingClientRect();return {visible:[...g.children].filter(c=>{const b=c.getBoundingClientRect();return b.top>=r.top&&b.bottom<=r.bottom}).length,scroll:g.scrollHeight>g.clientHeight}})()');assert.equal(grid.visible,8);assert(grid.scroll);
    const fonts={};const doc=await call('DOM.getDocument');for(const sel of ['h1','.reward span']){const node=await call('DOM.querySelector',{nodeId:doc.root.nodeId,selector:sel});fonts[sel]=(await call('CSS.getPlatformFontsForNode',{nodeId:node.nodeId})).fonts;}
    const screens=[];await run('document.body.classList.remove("baseline")');
    for(const [width,height] of [[1280,720],[1920,1080],[2560,1080],[3840,2160]]){await call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});await run('fit()');const r=await run('(()=>{const r=document.querySelector(".dialog").getBoundingClientRect();return {width:r.width,height:r.height,left:r.left,top:r.top,right:r.right,bottom:r.bottom}})()');assert(Math.abs(r.width/r.height-1045/600)<.001);assert(r.left>=0&&r.top>=42&&r.right<=width&&r.bottom<=height);screens.push({width,height,rect:r})}
    fs.writeFileSync(path.join(__dirname,'verification.json'),JSON.stringify({geometry,grid,fonts,screens,native_game_capture:false},null,2));
    console.log('REFERENCE_PASS: fixed geometry, 8 visible cards, uniform screen scaling, comparison images and font report');
  }finally{if(ws)ws.close();chrome.kill()}
})().catch(e=>{console.error(e);process.exitCode=1});
