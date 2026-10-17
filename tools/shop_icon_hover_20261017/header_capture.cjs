'use strict';
// Reads a frozen production preview. No game commands, account requests or orders.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),assert=require('node:assert/strict'),{spawn}=require('node:child_process'),{pathToFileURL}=require('node:url');
const repo=path.resolve(__dirname,'../..');process.chdir(repo);
const arg=name=>{const i=process.argv.indexOf(name);return i<0?null:process.argv[i+1];};
const entry=arg('--entry');if(!entry)throw Error('Usage: node header_capture.cjs --entry <frozen production preview/index.html>');
const out=path.resolve('output/shop_icon_hover_20261017/header');fs.mkdirSync(out,{recursive:true});
const hash=file=>crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex'),sleep=ms=>new Promise(resolve=>setTimeout(resolve,ms));
const html=fs.readFileSync(entry,'utf8'),key='window.PREVIEW_SOURCES=',start=html.indexOf(key)+key.length,stop=html.indexOf(';window.PREVIEW_FIXTURE=',start);
assert(start>=key.length&&stop>start,'Frozen actual production sources are embedded');
const snapshot=JSON.parse(html.slice(start,stop)),sources=['scripts/custom_game/black_lion_market.js','styles/custom_game/black_lion_market.css'].map(relative=>({path:'panorama/src/'+relative,sha256:crypto.createHash('sha256').update(snapshot[relative]).digest('hex')}));
function frozen(){for(const row of sources)assert.equal(hash(row.path),row.sha256,'Production header changed from the frozen snapshot: '+row.path);}
async function browser(){
 const profile=path.join(out,'browser','profile_'+Date.now()+'_'+process.pid);fs.mkdirSync(profile,{recursive:true});
 const child=spawn('C:/Program Files/Google/Chrome/Application/chrome.exe',['--headless','--disable-gpu','--no-first-run','--no-default-browser-check','--remote-debugging-port=0','--user-data-dir='+profile,'about:blank'],{windowsHide:true,stdio:'ignore'});let ws;
 try{
  for(let i=0;i<100&&!fs.existsSync(path.join(profile,'DevToolsActivePort'));i++)await sleep(100);
  const port=fs.readFileSync(path.join(profile,'DevToolsActivePort'),'utf8').split('\n')[0];let pages;
  for(let i=0;i<50&&!pages;i++){try{pages=await(await fetch('http://127.0.0.1:'+port+'/json/list')).json();}catch{await sleep(100);}}
  ws=new WebSocket(pages.find(page=>page.type==='page').webSocketDebuggerUrl);await new Promise((resolve,reject)=>{ws.onopen=resolve;ws.onerror=reject;});
  let serial=0;const pending=new Map();ws.onmessage=event=>{const message=JSON.parse(event.data),request=pending.get(message.id);if(request){pending.delete(message.id);message.error?request.reject(message.error):request.resolve(message.result);}};
  const call=(method,params={})=>new Promise((resolve,reject)=>{const id=++serial;pending.set(id,{resolve,reject});ws.send(JSON.stringify({id,method,params}));});
  const run=async expression=>{const result=await call('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true});if(result.exceptionDetails)throw Error(JSON.stringify(result.exceptionDetails));return result.result.value;};
  await call('Page.enable');await call('Network.enable');await call('Network.setBlockedURLs',{urls:['http://*','https://*']});
  return {call,run,close(){if(ws)ws.close();child.kill();}};
 }catch(error){if(ws)ws.close();child.kill();throw error;}
}
async function main(){
 frozen();const b=await browser(),report={kind:'actual_production_header_browser_preview',notGameCapture:true,noAccountSaveOrOrderWrites:true,entry,entrySha256:hash(entry),sources,scenarios:[],limitations:['The browser adapter approximates native Panorama layout, fonts, alignment and shrink. Screenshots are component previews, not live game captures.']};
 try{
  for(const [width,height] of [[1920,1080],[1280,720]])for(const balances of [[0,0,0],[123456789,987654321,123456789]]){
   await b.call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});
   await b.call('Page.navigate',{url:pathToFileURL(path.resolve(entry)).href+'?page=commerce&category=bundles'});
   let ready=false;for(let i=0;i<180&&!ready;i++){await sleep(70);ready=await b.run('typeof previewReady!=="undefined"&&document.readyState==="complete"');}assert(ready,'Preview becomes ready');assert.equal(await b.run('previewReady'),true);
   if(await b.run('typeof hoverReady!=="undefined"'))assert.equal(await b.run('hoverReady'),true);
   if(await b.run('typeof iconClarityReady!=="undefined"'))assert.equal(await b.run('iconClarityReady'),true);
   await b.run('document.fonts.ready.then(()=>true)');
   await b.run(`(()=>{const values=${JSON.stringify(balances)};cfg.SurvivalBlackLionMarket.GetWindow().SetResources(['U币','积分','商城金币'].map((name,i)=>({name,value:values[i]})));syncLayout();})()`);await sleep(150);
   const scenario=await b.run(`(()=>{function rect(element){const r=element.getBoundingClientRect();return{x:r.x,y:r.y,width:r.width,height:r.height,right:r.right,bottom:r.bottom,cy:r.y+r.height/2};}const market=cfg.SurvivalBlackLionMarket.GetWindow(),balance=market.panel.FindChildrenWithClassTraverse('BLMarketBalance')[0];return{viewport:[innerWidth,innerHeight],balances:${JSON.stringify(balances)},errors:previewErrors,groups:balance.Children().map(group=>{const icon=group.FindChildrenWithClassTraverse('BLMarketCurrencyIcon')[0],text=group.FindChildrenWithClassTraverse('BLMarketBalanceText')[0],plus=group.FindChildTraverse('BlackLionMarketRecharge');return{group:rect(group.el),icon:{...rect(icon.el),decoded:icon.el.complete&&icon.el.naturalWidth>0,natural:[icon.el.naturalWidth,icon.el.naturalHeight]},text:{...rect(text.el),value:text.text,paddingTop:getComputedStyle(text.el).paddingTop,whiteSpace:getComputedStyle(text.el).whiteSpace},plus:plus?rect(plus.el):null};})};})()`);
   report.scenarios.push(scenario);assert.deepEqual(scenario.errors,[],'Production preview has no script errors');assert.equal(scenario.groups.length,3);
   const centers=scenario.groups.map(group=>group.group.cy),tolerance=1.1;
   assert(Math.max(...centers)-Math.min(...centers)<tolerance,'Currency group row centers align');
   for(const group of scenario.groups){assert(group.icon.decoded,'Header uses a decoded actual icon');assert(Math.abs(group.icon.cy-group.group.cy)<tolerance,'Currency icon centers on its row');assert(Math.abs(group.text.cy-group.group.cy)<tolerance,'Currency text centers on its row');assert.equal(group.text.paddingTop,'0px');assert(group.icon.right<=group.text.x+0.6,'Currency icon does not overlap its text');assert(group.text.right<=group.group.right+0.6,'Currency text stays inside its group');if(group.plus){assert(Math.abs(group.plus.cy-group.group.cy)<tolerance,'Recharge centers on the same row');assert(group.text.right<=group.plus.x+0.6,'Balance text does not overlap recharge');assert(group.plus.right<=group.group.right+0.6,'Recharge stays inside its group');}}
   for(let i=1;i<scenario.groups.length;i++)assert(scenario.groups[i-1].group.right<=scenario.groups[i].group.x+0.6,'Adjacent currency groups do not overlap');
   const file=path.join(out,'header_'+width+'x'+height+'_'+(balances[0]?'long':'zero')+'.png'),image=await b.call('Page.captureScreenshot',{format:'png',captureBeyondViewport:false});fs.writeFileSync(file,Buffer.from(image.data,'base64'));scenario.screenshot={path:path.relative(repo,file).replaceAll('\\','/'),sha256:hash(file)};
   const recharge=scenario.groups[0].plus;await b.call('Input.dispatchMouseEvent',{type:'mouseMoved',x:recharge.x+recharge.width/2,y:recharge.cy});await b.call('Input.dispatchMouseEvent',{type:'mousePressed',button:'left',clickCount:1,x:recharge.x+recharge.width/2,y:recharge.cy});await b.call('Input.dispatchMouseEvent',{type:'mouseReleased',button:'left',clickCount:1,x:recharge.x+recharge.width/2,y:recharge.cy});await sleep(90);
   scenario.recharge=await b.run(`({open:cfg.SurvivalCommerceView.IsOpen(),paid:previewCalls.filter(row=>row.method==='paid'),transactions:previewCalls.filter(row=>row.name==='survival_payment_request'&&row.payload&&row.payload.action==='create'||row.name==='survival_commerce_request'&&row.payload&&row.payload.action==='purchase')})`);
   assert.equal(scenario.recharge.open,false,'Actual recharge activation closes the storefront');assert(scenario.recharge.paid.some(row=>row.sku==='u_coin_recharge'),'Actual recharge callback retains the existing recharge SKU');assert.deepEqual(scenario.recharge.transactions,[],'No payment order or wallet purchase is submitted');
  }
  frozen();report.status='PASS';
 }catch(error){report.status='FAIL';report.failure=error.stack;throw error;}finally{fs.writeFileSync(path.join(out,'header_report.json'),JSON.stringify(report,null,2)+'\n');b.close();}
 console.log('PASS_HEADER_ALIGNMENT '+JSON.stringify({scenarios:report.scenarios.length,viewports:['1920x1080','1280x720'],balances:['0','9 digits'],recharge:'actual button click → existing local checkout fixture'}));
}
main().catch(error=>{console.error(error);process.exitCode=1;});
