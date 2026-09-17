const fs=require('fs'),path=require('path'),os=require('os'),assert=require('assert'),{spawn}=require('child_process'),{pathToFileURL}=require('url');
const sleep=ms=>new Promise(r=>setTimeout(r,ms)),dir=path.resolve('art/ui/development/font_import/preview');
(async()=>{const profile=fs.mkdtempSync(path.join(os.tmpdir(),'survival-font-review-')),chrome=spawn('C:/Program Files/Google/Chrome/Application/chrome.exe',['--headless','--disable-gpu','--no-first-run','--no-default-browser-check','--remote-debugging-port=0','--user-data-dir='+profile,pathToFileURL(path.join(dir,'index.html')).href],{windowsHide:true,stdio:'ignore'});let ws;
try{for(let i=0;i<100&&!fs.existsSync(path.join(profile,'DevToolsActivePort'));i++)await sleep(100);const port=fs.readFileSync(path.join(profile,'DevToolsActivePort'),'utf8').split('\n')[0],targets=await(await fetch('http://127.0.0.1:'+port+'/json/list')).json();ws=new WebSocket(targets.find(t=>t.type==='page').webSocketDebuggerUrl);await new Promise((r,j)=>{ws.onopen=r;ws.onerror=j});let serial=0;const pending=new Map();ws.onmessage=e=>{const m=JSON.parse(e.data),p=pending.get(m.id);if(p){pending.delete(m.id);m.error?p.reject(m.error):p.resolve(m.result)}};const call=(method,params={})=>new Promise((resolve,reject)=>{pending.set(++serial,{resolve,reject});ws.send(JSON.stringify({id:serial,method,params}))});const run=async expression=>{const r=await call('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true});if(r.exceptionDetails)throw Error(JSON.stringify(r.exceptionDetails));return r.result.value};
await call('Page.enable');await call('DOM.enable');await call('CSS.enable');await run('document.fonts.ready.then(()=>true)');
const report={kind:'browser_font_specimen_NOT_native_Dota',actual_rendered_fonts:[],screens:[]};
const doc=await call('DOM.getDocument');
for(const [id,ps]of[['title','SourceHanSerifSC-Bold'],['medium','SourceHanSansSC-Medium'],['body','SourceHanSansSC-Regular']]){
 const node=await call('DOM.querySelector',{nodeId:doc.root.nodeId,selector:'#'+id});const fonts=await call('CSS.getPlatformFontsForNode',{nodeId:node.nodeId});
 assert(fonts.fonts.length&&fonts.fonts.every(f=>f.isCustomFont&&f.postScriptName===ps),JSON.stringify(fonts));report.actual_rendered_fonts.push({id,...fonts});
}
for(const[width,height]of[[1280,720],[1920,1080],[2560,1440],[3440,1440]]){
 await call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});await sleep(200);
 const rect=await run('(()=>{const r=document.querySelector("main").getBoundingClientRect();return {x:r.x,y:r.y,width:r.width,height:r.height}})()');
 assert(rect.x>=0&&rect.y>=0&&rect.x+rect.width<=width+1&&rect.y+rect.height<=height+1);
 const clipped=await run('[...document.querySelectorAll("p,button,h1,footer")].filter(e=>e.scrollHeight>e.clientHeight+1||e.scrollWidth>e.clientWidth+1).map(e=>e.textContent)');assert.deepEqual(clipped,[]);
 const bottom=await run('document.querySelector("footer").getBoundingClientRect().bottom');assert(bottom<=rect.y+rect.height);
 const shot=await call('Page.captureScreenshot',{format:'png'});fs.writeFileSync(path.join(dir,'fonts-'+width+'x'+height+'.png'),Buffer.from(shot.data,'base64'));report.screens.push({width,height,rect,clipped});
}
fs.writeFileSync(path.join(dir,'verification.json'),JSON.stringify(report,null,2));console.log('FONT_BROWSER_PASS: 3 exact PostScript faces, bundled fonts; no clipped specimen text at 4 sizes; NOT a native game capture.');
}finally{if(ws)ws.close();chrome.kill()}})().catch(e=>{console.error(e);process.exitCode=1});
