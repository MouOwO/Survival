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




    const bytes=fs.readFileSync(path.join(__dirname,'../lottery_reference_review/reference-1045.png')).toString('base64');
    const images=await run('('+(async function(bytes){
      const im=new Image();im.src='data:image/png;base64,'+bytes;await im.decode();const out={};
      function canvas(w,h){const c=document.createElement('canvas');c.width=w;c.height=h;return c;}
      function patch(ctx,sx,sy,sw,sh,x,y,w,h){ctx.drawImage(im,sx,sy,sw,sh,x,y,w,h);}
      function nine(ctx,sx,sy,sw,sh,w,h,n){for(let row=0;row<3;row++)for(let col=0;col<3;col++){const xs=[0,n,sw-n],ys=[0,n,sh-n],ws=[n,sw-2*n,n],hs=[n,sh-2*n,n],dx=[0,n,w-n],dy=[0,n,h-n],dw=[n,w-2*n,n],dh=[n,h-2*n,n];if(row===1&&col===1)continue;patch(ctx,sx+xs[col],sy+ys[row],ws[col],hs[row],dx[col],dy[row],dw[col],dh[row]);}}
      const p=canvas(1045,760),c=p.getContext('2d');
      // Clean source areas only: no labels, sample rewards or baked interactions.
      for(let x=0;x<1045;x+=235){c.save();c.translate(x,0);if(Math.floor(x/235)%2){c.translate(235,0);c.scale(-1,1);}patch(c,40,8,235,65,0,0,235,106);c.restore();}
      patch(c,231,81,25,46,26,106,994,76);
      patch(c,30,485,640,23,20,182,1005,558);
      // Original perimeter cut into eight slices; corners retain source size.
      nine(c,0,0,1045,600,1045,760,24);
      // Header ornament crops retain original pixels, placed independently of title.
      // V3 title ornaments are independent controls, not baked into the slices.
      // Remove screenshot backdrop outside the panel's outer silhouette.
      c.globalCompositeOperation='destination-in'; c.beginPath(); [[0,26],[5,13],[14,5],[28,0],[1017,0],[1031,5],[1040,13],[1045,26],[1045,734],[1040,747],[1031,755],[1017,760],[28,760],[14,755],[5,747],[0,734]].forEach(function(q,i){if(i)c.lineTo(q[0],q[1]);else c.moveTo(q[0],q[1]);});c.closePath();c.fill();c.globalCompositeOperation='source-over';
      out['pool_reference_skin']=p.toDataURL();
      const names=['tl','t','tr','l','c','r','bl','b','br'];for(let y=0;y<3;y++)for(let x=0;x<3;x++){const xx=[0,32,1013],yy=[0,32,728],ww=[32,981,32],hh=[32,696,32];const slice=canvas(ww[x],hh[y]);slice.getContext('2d').drawImage(p,xx[x],yy[y],ww[x],hh[y],0,0,ww[x],hh[y]);out['slices/panel_'+names[y*3+x]]=slice.toDataURL();}
      const card=canvas(204,194),cc=card.getContext('2d');patch(cc,215,165,119,12,0,0,204,194);nine(cc,201,159,146,156,204,194,5);out['card_reference_skin']=card.toDataURL();
      const tab=canvas(248,76),tc=tab.getContext('2d');patch(tc,24,118,196,1,0,0,248,61);patch(tc,24,118,196,15,0,61,248,15);
      const glow=tc.getImageData(0,0,248,76);for(let y=0;y<76;y++)for(let x=0;x<248;x++){const i=(y*248+x)*4,r=glow.data[i],g=glow.data[i+1],b=glow.data[i+2];let alpha=Math.max(0,Math.min(1,(r-b)/45));if(y>63&&Math.min(r,g,b)>235)alpha=1;if(y<61)alpha*=Math.pow(y/61,3);glow.data[i+3]=Math.round(alpha*255);}tc.putImageData(glow,0,0);out['tab_reference_skin']=tab.toDataURL();
      const close=canvas(40,40),xc=close.getContext('2d');patch(xc,976,24,40,40,0,0,40,40);const pixels=xc.getImageData(0,0,40,40);for(let i=0;i<pixels.data.length;i+=4){const r=pixels.data[i],g=pixels.data[i+1],b=pixels.data[i+2];pixels.data[i+3]=Math.round(Math.max(0,Math.min(1,(Math.min(r,g)-b-5)/30))*Math.max(0,Math.min(1,(r-105)/95))*255);}xc.putImageData(pixels,0,0);out['close_reference_skin']=close.toDataURL();
      const button=canvas(425,57),bc=button.getContext('2d');patch(bc,835,532,135,6,0,0,425,57);nine(bc,798,521,211,53,425,57,10);out['button_reference_skin']=button.toDataURL();return out;
    }).toString()+')('+JSON.stringify(bytes)+')');
    fs.mkdirSync(path.join(__dirname,'../../panorama/src/images/custom_game/lottery_handoff/slices'),{recursive:true});
    for(const [name,data] of Object.entries(images))fs.writeFileSync(path.join(__dirname,'../../panorama/src/images/custom_game/lottery_handoff',name+'.png'),Buffer.from(data.split(',')[1],'base64'));
    console.log('REFERENCE_CROPS_PASS: source crops, fixed corner slices, no baked text');
  }finally{if(ws)ws.close();chrome.kill()}
})().catch(e=>{console.error(e);process.exitCode=1});
