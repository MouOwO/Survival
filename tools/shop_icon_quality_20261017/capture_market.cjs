'use strict';
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),assert=require('node:assert/strict'),{spawn}=require('node:child_process'),{pathToFileURL}=require('node:url');
const repo=path.resolve(__dirname,'../..');process.chdir(repo);
const out='output/shop_icon_clarity_20261017',entry=out+'/preview/index.html',assembly=JSON.parse(fs.readFileSync(out+'/preview/clarity_assembly.json','utf8'));
const hash=file=>crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const sleep=ms=>new Promise(resolve=>setTimeout(resolve,ms));
function frozen(){for(const row of [...assembly.sources,...assembly.resources])assert.equal(hash(row.path),row.sha256,'Reviewed source/asset changed '+row.path);}
async function browser(){
 const profile=path.resolve(out,'browser','profile_'+Date.now()+'_'+process.pid);fs.mkdirSync(profile,{recursive:true});
 const processHandle=spawn('C:/Program Files/Google/Chrome/Application/chrome.exe',['--headless','--disable-gpu','--no-first-run','--no-default-browser-check','--remote-debugging-port=0','--user-data-dir='+profile,'about:blank'],{windowsHide:true,stdio:'ignore'});let ws;
 try{
  for(let i=0;i<100&&!fs.existsSync(path.join(profile,'DevToolsActivePort'));i++)await sleep(100);
  const port=fs.readFileSync(path.join(profile,'DevToolsActivePort'),'utf8').split('\n')[0];let pages;
  for(let i=0;i<50&&!pages;i++){try{pages=await(await fetch('http://127.0.0.1:'+port+'/json/list')).json();}catch{await sleep(100);}}
  ws=new WebSocket(pages.find(page=>page.type==='page').webSocketDebuggerUrl);await new Promise((resolve,reject)=>{ws.onopen=resolve;ws.onerror=reject;});
  let serial=0;const pending=new Map();ws.onmessage=event=>{const msg=JSON.parse(event.data),request=pending.get(msg.id);if(request){pending.delete(msg.id);msg.error?request.reject(msg.error):request.resolve(msg.result);}};
  const call=(method,params={})=>new Promise((resolve,reject)=>{const id=++serial;pending.set(id,{resolve,reject});ws.send(JSON.stringify({id,method,params}));});
  const run=async expression=>{const result=await call('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true});if(result.exceptionDetails)throw Error(JSON.stringify(result.exceptionDetails));return result.result.value;};
  await call('Page.enable');await call('Network.enable');await call('Network.setBlockedURLs',{urls:['http://*','https://*']});
  return {call,run,async go(query,width,height){await call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});await call('Page.navigate',{url:pathToFileURL(path.resolve(entry)).href+query});for(let i=0;i<150;i++){await sleep(50);if(await run('document.readyState==="complete"&&typeof iconClarityReady!=="undefined"'))break;}assert.equal(await run('iconClarityReady'),true);await run('document.fonts.ready.then(()=>true)');await sleep(120);},async shot(filename,width,height){const result=await call('Page.captureScreenshot',{format:'png',captureBeyondViewport:false,clip:{x:0,y:0,width,height,scale:1}});fs.mkdirSync(path.dirname(filename),{recursive:true});fs.writeFileSync(filename,Buffer.from(result.data,'base64'));},close(){if(ws)ws.close();processHandle.kill();}};
 }catch(error){if(ws)ws.close();processHandle.kill();throw error;}
}
const imageInfo=`function images(panel){return [...(panel.el.matches('img')?[panel.el]:panel.el.querySelectorAll('img'))].filter(image=>image.getBoundingClientRect().width>0).map(image=>({source:image.src,decoded:image.complete&&image.naturalWidth>0,natural:[image.naturalWidth,image.naturalHeight],fit:getComputedStyle(image).objectFit,bounds:image.getBoundingClientRect().toJSON()}));}`;
async function main(){frozen();const b=await browser(),report={kind:'actual_production_market_components',notGameCapture:true,noAccountSaveOrOrderWrites:true,blockedNetwork:['http://*','https://*'],screens:[],contacts:[],markets:[],assemblyHash:hash(out+'/preview/clarity_assembly.json'),limitations:['Local Panorama browser adapter approximates native layout and font rendering. These images are component previews, not live game captures.','64px artwork is the authored list size; adjacent128px artwork is an enlarged inspection aid. Native original source sizes are reported separately.']};
 try{
  async function shot(name,width,height){if(assembly.masterHash)assert.equal(await b.run('cfg.SurvivalItemResources.sourceHash'),assembly.masterHash,'Browser executes the frozen generated resource registry');const file=out+'/screens/'+name+'.png';await b.shot(file,width,height);report.screens.push({path:file,width,height,sha256:hash(file)});}
  for(const[width,height]of [[1920,1080],[1280,720]])for(const category of ['home','bundles','vip','all']){
   await b.go('?page=commerce&category='+category,width,height);
   const scene=await b.run(`(()=>{${imageInfo}const view=cfg.SurvivalCommerceView.Inspect(),rows=cfg.SurvivalBlackLionMarket.GetWindow().content.FindChildrenWithClassTraverse('BLMarketRow');return{viewport:[innerWidth,innerHeight],category,view,errors:previewErrors,rows:rows.map((row,index)=>({sku:view.visibleSkus[view.page*40+index],images:images(row.__menuCell.iconPanel),bounds:row.el.getBoundingClientRect().toJSON(),artBounds:row.__menuCell.iconPanel.el.getBoundingClientRect().toJSON(),nameBounds:row.__menuCell.namePanel.el.getBoundingClientRect().toJSON()}))};})()`);
   assert(scene.rows.length,category+' has formal listed products');
   for(const row of scene.rows){assert(row.images.length&&row.images.every(image=>image.decoded),row.sku+' images decode');assert(row.images.every(image=>Math.min(...image.natural)>=128),row.sku+' has128px minimum source pixels for64px list and120px tooltip');assert(row.artBounds.right<row.nameBounds.left,row.sku+' leaves a name gap');}
   assert.deepEqual(scene.errors,[],'Actual-source component assembly errors');report.markets.push(scene);await shot('market_'+category+'_'+width+'x'+height,width,height);
  }
  await b.go('?page=commerce&category=all&contact=1&sheet=0',1920,1080);
  const count=await b.run('clarityProducts.length'),sheets=Math.ceil(count/24);
  for(let sheet=0;sheet<sheets;sheet++){
   if(sheet)await b.go('?page=commerce&category=all&contact=1&sheet='+sheet,1920,1080);
   const rows=await b.run(`(()=>{${imageInfo}return clarityContactRows.map(row=>({sku:row.sku,title:row.title,resourceId:row.resourceId,small:images(row.small),large:images(row.large)}));})()`);
   assert(rows.length,'Contact sheet contains real products');for(const row of rows){assert(row.small.length&&row.large.length,row.sku+' has both images');for(const image of [...row.small,...row.large]){assert(image.decoded,row.sku+' contact art decodes');assert(Math.min(...image.natural)>=128,row.sku+' contact artwork never upscales its source at128px');}}
   report.contacts.push({sheet:sheet+1,rows});await shot('contact_'+String(sheet+1).padStart(2,'0')+'_64_and_128',1920,1080);
  }
  assert.equal(report.contacts.reduce((sum,sheet)=>sum+sheet.rows.length,0),count,'Every unique formal listed SKU appears once');
  report.transactionCalls=await b.run('previewCalls.filter(row=>row.method==="wallet"||row.method==="paid"||row.name==="survival_commerce_request"&&row.payload.action==="purchase"||row.name==="survival_payment_request"&&row.payload.action==="create")');assert.deepEqual(report.transactionCalls,[]);
  report.counts={uniqueListedSkus:count,contactSheets:sheets,marketScreens:report.markets.length};frozen();report.status='PASS';
 }catch(error){report.status='FAIL';report.failure=error.stack;try{report.previewErrors=await b.run('previewErrors');await b.shot(out+'/screens/failure.png',1920,1080);}catch{}throw error;}finally{fs.writeFileSync(out+'/visual_report.json',JSON.stringify(report,null,2)+'\n');b.close();}
 console.log('MARKET_ICON_VISUAL_PASS '+JSON.stringify(report.counts));
}
main().catch(error=>{console.error(error);process.exitCode=1;});
