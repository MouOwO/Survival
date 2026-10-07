'use strict';
const fs=require('fs'),path=require('path'),{spawn}=require('child_process'),{pathToFileURL}=require('url');
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
async function browser(){
 const profile=path.resolve('output/commerce_ui_12h/chrome_'+Date.now());fs.mkdirSync(profile,{recursive:true});
 const process=spawn('C:/Program Files/Google/Chrome/Application/chrome.exe',['--headless','--disable-gpu','--no-first-run','--no-default-browser-check','--remote-debugging-port=0','--user-data-dir='+profile,'about:blank'],{windowsHide:true,stdio:'ignore'});
 let ws;try{
  for(let i=0;i<100&&!fs.existsSync(path.join(profile,'DevToolsActivePort'));i++)await sleep(100);
  const port=fs.readFileSync(path.join(profile,'DevToolsActivePort'),'utf8').split('\n')[0];let list;
  for(let i=0;i<60&&!list;i++){try{list=await(await fetch('http://127.0.0.1:'+port+'/json/list')).json();}catch(e){await sleep(100);}}
  if(!list)throw new Error('Chrome DevTools endpoint unavailable');
  ws=new WebSocket(list.find(x=>x.type==='page').webSocketDebuggerUrl);await new Promise((r,j)=>{ws.onopen=r;ws.onerror=j});
  let serial=0;const pending=new Map();ws.onmessage=e=>{const m=JSON.parse(e.data),p=pending.get(m.id);if(p){pending.delete(m.id);m.error?p.reject(m.error):p.resolve(m.result)}};
  const call=(method,params={})=>new Promise((resolve,reject)=>{const id=++serial;pending.set(id,{resolve,reject});ws.send(JSON.stringify({id,method,params}))});
  const run=async expression=>{const r=await call('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true});if(r.exceptionDetails)throw new Error(JSON.stringify(r.exceptionDetails));return r.result.value};
  await call('Page.enable');await call('Emulation.setDeviceMetricsOverride',{width:1920,height:1080,deviceScaleFactor:1,mobile:false});
  const go=async(file,query='')=>{await call('Page.navigate',{url:pathToFileURL(path.resolve(file)).href+query});for(let i=0;i<100;i++){await sleep(60);if(await run('document.readyState==="complete"'))break;}await run('document.fonts.ready.then(()=>true)');await run('Promise.all([...document.images].map(i=>{i.loading="eager";return i.decode().catch(()=>false);})).then(()=>true)');await sleep(230);};
  const shot=async(file,clip)=>{fs.mkdirSync(path.dirname(file),{recursive:true});const r=await call('Page.captureScreenshot',{format:'png',captureBeyondViewport:true,...(clip?{clip:{...clip,scale:1}}:{})});fs.writeFileSync(file,Buffer.from(r.data,'base64'));};
  return {call,run,go,shot,close:()=>{ws.close();process.kill();}};
 }catch(e){if(ws)ws.close();process.kill();throw e;}
}
module.exports={browser,sleep};
if(require.main===module)(async()=>{const b=await browser();try{await b.go(process.argv[2],process.argv[4]||'');await b.shot(process.argv[3]);console.log('SCREENSHOT_SAVED '+process.argv[3]);}finally{b.close();}})().catch(e=>{console.error(e);process.exitCode=1});
