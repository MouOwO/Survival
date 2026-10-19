'use strict';
const fs=require('node:fs'),path=require('node:path'),{spawn}=require('node:child_process'),{pathToFileURL}=require('node:url');
const sleep=ms=>new Promise(resolve=>setTimeout(resolve,ms));
async function browser(){
 const qa=path.resolve(__dirname,'../../output/collection_gold_refine_20261019/qa_preview'),temporary=path.join(qa,'chrome_temp');fs.mkdirSync(temporary,{recursive:true});process.env.TEMP=temporary;process.env.TMP=temporary;
 const profile=path.join(qa,'profile_'+Date.now()+'_'+process.pid);fs.mkdirSync(profile,{recursive:true});
 const handle=spawn('C:/Program Files/Google/Chrome/Application/chrome.exe',['--headless','--disable-gpu','--disable-background-networking','--disable-component-update','--disable-sync','--no-first-run','--no-default-browser-check','--remote-debugging-port=0','--user-data-dir='+profile,'about:blank'],{windowsHide:true,stdio:'ignore'});
 let ws;try{
  for(let i=0;i<100&&!fs.existsSync(path.join(profile,'DevToolsActivePort'));i++)await sleep(100);
  const port=fs.readFileSync(path.join(profile,'DevToolsActivePort'),'utf8').split('\n')[0];let list;
  for(let i=0;i<60&&!list;i++){try{list=await(await fetch('http://127.0.0.1:'+port+'/json/list')).json();}catch{await sleep(100);}}
  if(!list)throw Error('Chrome DevTools unavailable');ws=new WebSocket(list.find(x=>x.type==='page').webSocketDebuggerUrl);await new Promise((resolve,reject)=>{ws.onopen=resolve;ws.onerror=reject;});
  let serial=0;const pending=new Map();ws.onmessage=event=>{const m=JSON.parse(event.data),p=pending.get(m.id);if(p){pending.delete(m.id);m.error?p.reject(m.error):p.resolve(m.result);}};
  const call=(method,params={})=>new Promise((resolve,reject)=>{const id=++serial;pending.set(id,{resolve,reject});ws.send(JSON.stringify({id,method,params}));});
  const run=async expression=>{const r=await call('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true});if(r.exceptionDetails)throw Error(JSON.stringify(r.exceptionDetails));return r.result.value;};
  await call('Page.enable');await call('Network.enable');await call('Network.setBlockedURLs',{urls:['http://*','https://*']});
  const go=async(file,query='')=>{await call('Page.navigate',{url:pathToFileURL(path.resolve(file)).href+query});for(let i=0;i<100;i++){await sleep(60);if(await run('document.readyState==="complete"'))break;}await run('document.fonts.ready.then(()=>true)');await run('Promise.all([...document.images].map(i=>i.decode().catch(()=>false))).then(()=>true)');await sleep(180);};
  const shot=async(file,width,height)=>{fs.mkdirSync(path.dirname(file),{recursive:true});const r=await call('Page.captureScreenshot',{format:'png',captureBeyondViewport:true,clip:{x:0,y:0,width,height,scale:1}});fs.writeFileSync(file,Buffer.from(r.data,'base64'));};
  return{call,run,go,shot,close(){ws.close();handle.kill();}};
 }catch(error){if(ws)ws.close();handle.kill();throw error;}
}
module.exports={browser,sleep};
