// Local, dependency-free browser checks. Does not connect to the game server.
const fs = require('fs'), path = require('path'), os = require('os'), assert = require('assert');
const { spawn } = require('child_process');
const { pathToFileURL } = require('url');
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
(async () => {
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'lottery-handoff-review-'));
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


    const alpha=[];
    for(const name of ['button_ivory','button_gold']){
      const svg=fs.readFileSync(path.join(__dirname,'../../panorama/src/images/custom_game/lottery_handoff',name+'.svg'),'utf8');
      const result=await run('('+ (async function(svg){const img=new Image();img.src='data:image/svg+xml;base64,'+btoa(svg);await img.decode();return [1,.5,.25].map(scale=>{const c=document.createElement('canvas');c.width=360*scale;c.height=80*scale;const ctx=c.getContext('2d');ctx.drawImage(img,0,0,c.width,c.height);return {scale,cornerAlpha:ctx.getImageData(0,0,1,1).data[3],centerAlpha:ctx.getImageData(c.width/2,c.height/2,1,1).data[3]}})}).toString()+')('+JSON.stringify(svg)+')');
      assert(result.every(x=>x.cornerAlpha===0&&x.centerAlpha===255));alpha.push({name,result});
    }
    fs.writeFileSync(path.join(__dirname,'alpha-check.json'),JSON.stringify(alpha,null,2));
    await screenshot('components.png');
    await run('home()'); await screenshot('home.png');
    await run('pool()'); await screenshot('pool.png');
    await run('draw(10);skip()'); assert.equal(await run('document.querySelectorAll(".card").length'),10); await screenshot('ten.png');
    await run('draw(1);skip()'); await screenshot('single.png');
    const check=await run('({cards:document.querySelectorAll(".card").length,overflow:document.body.scrollWidth>innerWidth})');
    fs.writeFileSync(path.join(__dirname,'verification.json'),JSON.stringify(check,null,2));
    async function screenshot(name){await sleep(250);const r=await call('Page.captureScreenshot',{format:'png'});fs.writeFileSync(path.join(__dirname,name),Buffer.from(r.data,'base64'));}

    const fonts={};const doc=await call('DOM.getDocument');
    for(const selector of ['h2','.name']){const n=await call('DOM.querySelector',{nodeId:doc.root.nodeId,selector});fonts[selector]=(await call('CSS.getPlatformFontsForNode',{nodeId:n.nodeId})).fonts;}
    fs.writeFileSync(path.join(__dirname,'fonts.json'),JSON.stringify(fonts,null,2));
    for(const width of [1280,2560]){await call('Emulation.setDeviceMetricsOverride',{width,height:900,deviceScaleFactor:1,mobile:false});await run('home()');await screenshot('home-'+width+'.png');}
    await call('Emulation.setDeviceMetricsOverride',{width:1600,height:900,deviceScaleFactor:1,mobile:false});
    for(const count of [1,10]){
      await run('draw('+count+')');const frames=[];const start=Date.now();
      while(Date.now()-start<3400){const frame=await call('Page.captureScreenshot',{format:'jpeg',quality:70});frames.push({data:frame.data,ms:Date.now()-start});await sleep(65);}
      const encoded=await run('('+ (async function(frames){
        const canvas=document.createElement('canvas');canvas.width=1600;canvas.height=900;
        const ctx=canvas.getContext('2d');const stream=canvas.captureStream(20);const chunks=[];
        const recorder=new MediaRecorder(stream,{mimeType:'video/webm;codecs=vp8',videoBitsPerSecond:2500000});
        const done=new Promise(resolve=>{recorder.onstop=()=>{const reader=new FileReader();reader.onload=()=>resolve(reader.result.split(',')[1]);reader.readAsDataURL(new Blob(chunks,{type:'video/webm'}))}});
        recorder.ondataavailable=e=>chunks.push(e.data);recorder.start();let prev=0;
        for(const frame of frames){await new Promise(r=>setTimeout(r,Math.max(1,frame.ms-prev)));prev=frame.ms;const img=new Image();img.src='data:image/jpeg;base64,'+frame.data;await img.decode();ctx.drawImage(img,0,0);}
        await new Promise(r=>setTimeout(r,150));recorder.stop();const result=await done;stream.getTracks().forEach(t=>t.stop());return result;
      }).toString()+')('+JSON.stringify(frames)+')');
      fs.writeFileSync(path.join(__dirname,count===1?'single-preview.webm':'ten-preview.webm'),Buffer.from(encoded,'base64'));
    }
    console.log('PREVIEW_PASS: screenshots, fonts, responsive views and two browser recordings');
  } finally { if(ws)ws.close();chrome.kill(); }
})().catch(e=>{console.error(e);process.exitCode=1});
