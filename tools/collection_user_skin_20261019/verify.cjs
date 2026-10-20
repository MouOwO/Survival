'use strict';
// No native game, account, save or draw endpoint is contacted.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const {browser,sleep}=require('../market_filter_20261017/browser.cjs');
const repo=path.resolve(__dirname,'../..'),out='output/collection_user_skin_20261019',input=out+'/preview/index.html',captures=out+'/browser';process.chdir(repo);
const sha=file=>crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const textSha=file=>crypto.createHash('sha256').update(fs.readFileSync(file,'utf8').replace(/^\uFEFF/,'')).digest('hex');
const inside=(r,p)=>r.x>=p.x-1&&r.y>=p.y-1&&r.right<=p.right+1&&r.bottom<=p.bottom+1;
async function inspect(){
 const rect=p=>p.el.getBoundingClientRect().toJSON(),css=p=>getComputedStyle(p.el),win=nodes.CollectionWindow;
 const decode=async src=>{const image=new Image();image.src=src;try{await image.decode();return {src,decoded:image.naturalWidth>0,width:image.naturalWidth,height:image.naturalHeight};}catch{return {src,decoded:false};}};
 await Promise.all([...win.el.querySelectorAll('img')].map(image=>image.decode().catch(()=>false)));
 const url=background=>(background.match(/url\(["']?(.*?)["']?\)/)||[])[1];
 const background=nodes.CollectionGW2Background,backgroundUri=url(css(background).backgroundImage);
 const icons=await Promise.all(['ex','friend','wife','beast'].map(async id=>{const tab=nodes['CollectionGW2Tab_'+id],icon=tab.FindChildrenWithClassTraverse('CollectionGW2Art')[0];return {id,type:icon.paneltype,...await decode(url(css(icon).backgroundImage)),position:icon.style.position,selected:tab.BHasClass('CollectionGW2Selected')};}));
 const cards=win.FindChildrenWithClassTraverse('CollectionGW2Slot').map(p=>({id:p.__collectionItem.id,bounds:rect(p),images:[...p.el.querySelectorAll('img')].map(el=>({src:el.currentSrc||el.src,decoded:el.complete&&el.naturalWidth>0,width:el.naturalWidth,height:el.naturalHeight,bounds:el.getBoundingClientRect().toJSON()}))}));
 return {api:cfg.SurvivalCollection.Inspect(),errors:previewErrors,canvas:rect(nodes.CollectionGW2Canvas),window:rect(win),grid:rect(nodes.CollectionGW2Grid),gridPosition:nodes.CollectionGW2Grid.style.position,background:{...await decode(backgroundUri),source:background.style.backgroundImage,bounds:rect(background),opacity:css(background).opacity},icons,cards,searchNodes:Object.keys(nodes).filter(id=>/CollectionGW2Search|CollectionSearch/.test(id)),textEntries:win.el.querySelectorAll('input,[data-type="TextEntry"]').length,searchText:[...win.el.querySelectorAll('label')].filter(el=>/搜索收藏/.test(el.textContent)).map(el=>el.textContent),texts:win.FindChildrenWithClassTraverse('CollectionGW2Text').map(p=>({id:p.id,text:p.text,font:css(p).fontFamily,shadow:css(p).textShadow})),heading:nodes.CollectionGW2Category.text,tooltipVisible:cfg.SurvivalCollection.Inspect().tooltipVisible,calls:previewCalls};
}
function freeze(snapshot){const changed=[];for(const row of snapshot.sources)if(textSha('panorama/src/'+row.path)!==row.sha256)changed.push(row.path);for(const row of snapshot.assets)if(sha(row.path)!==row.sha256)changed.push(row.path);assert.deepEqual(changed,[],'Production sources and assets stay frozen during verification');return changed;}
function check(state,width,height,category){
 assert.deepEqual(state.errors,[]);assert.equal(state.api.category,category);assert(state.api.open);assert.equal(state.api.rows.length,40);assert.equal(state.api.slots,40);assert.equal(state.cards.length,40);
 assert(inside(state.window,{x:0,y:0,right:width,bottom:height}),'Window fits viewport');assert.equal(state.gridPosition,'54px 98px 0px','Existing card layout stays unchanged');
 assert.deepEqual(state.searchNodes,[],'No old search nodes survive');assert.equal(state.textEntries,0,'No editable search control');assert.deepEqual(state.searchText,[],'No search placeholder or label');
 assert.match(state.background.source,/collection_user_skin_v1\/background\.vtex/,'Uses new native background');assert.match(state.background.src,/collection_user_skin_v1\/background\.png/,'Browser sees exact new original PNG');assert(state.background.decoded);assert.equal(state.background.width,1586);assert.equal(state.background.height,992);assert.equal(state.background.opacity,'1');
 for(const icon of state.icons){assert(icon.decoded,'Category icon decodes '+icon.id);assert.equal(icon.position,'3.5px 3.5px 0px');assert.equal(icon.selected,icon.id===category);}
 for(const card of state.cards){assert(inside(card.bounds,state.window));assert.equal(card.images.length,1,'One portrait per card');assert(card.images[0].decoded,'Portrait decodes '+card.id);assert(inside(card.images[0].bounds,card.bounds));}
 assert(!state.calls.some(row=>/claim|social_draw|purchase|checkout|activate|promote|equip/.test(row.name||row.event||'')),'No business mutation event');
}
async function main(){
 fs.mkdirSync(captures,{recursive:true});const snapshot=JSON.parse(fs.readFileSync(out+'/snapshot.json','utf8'));freeze(snapshot);
 const original='C:/Users/Administrator/Desktop/背景图1.png',canonical='art/ui/sources/custom_game/collection_user_skin_v1/background.png',mirror='panorama/src/images/custom_game/collection_user_skin_v1/background.png';
 assert.equal(sha(canonical),sha(original),'Canonical PNG preserves exact user bytes');assert.equal(sha(mirror),sha(original),'Runtime-source PNG preserves exact user bytes');
 const report={at:new Date().toISOString(),kind:'collection_user_skin_production_component_offline_preview',notGameCapture:true,networkBlocked:true,sourceBackground:{path:original,sha256:sha(original),bytes:fs.statSync(original).size},cases:[],interactions:[],limitations:['Actual production XML/JS/CSS with formal repository catalog and synthetic local progress.','Browser rendering only; not a native game capture.','HTTP/HTTPS and page WebSocket requests blocked; all game events stay in fixture memory.','Production s2r texture backgrounds use the exact original PNG alias in the browser; native texture sampling remains separate.']};
 const b=await browser();let width=1920,height=1080;
 try{
  await b.call('Network.setBlockedURLs',{urls:['http://*','https://*','ws://*','wss://*']});
  for(const size of [[1920,1080],[1280,720]]){
   [width,height]=size;await b.call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});await b.go(input,'?state=normal&category=ex');assert(await b.run('previewReady'));
   for(const category of ['ex','friend','wife','beast']){
    await b.run('collectionPreviewSelect('+JSON.stringify(category)+')');await sleep(100);await b.run('syncLayout();true');
    const state=await b.run('('+inspect.toString()+')()');check(state,width,height,category);
    const name=width+'x'+height+'_'+category;fs.writeFileSync(captures+'/'+name+'.json',JSON.stringify(state,null,2));await b.shot(captures+'/'+name+'.png',width,height);
    const hover=await b.run(`(()=>{const tab=nodes['CollectionGW2Tab_${category}'];tab.events.onmouseover();const tabCaption=previewNativeTooltip;tab.events.onmouseout();const first=nodes.CollectionWindow.FindChildrenWithClassTraverse('CollectionGW2Slot')[0];first.events.onmouseover();syncLayout();return{tabCaption,heading:nodes.CollectionGW2Category.text,tooltipVisible:cfg.SurvivalCollection.Inspect().tooltipVisible};})()`);assert.equal(hover.tabCaption,state.heading);assert(hover.tooltipVisible,'Card tooltip remains functional');
    await sleep(220);if(category==='ex')await b.shot(captures+'/'+name+'_tooltip.png',width,height);
    await b.run(`(()=>{const first=nodes.CollectionWindow.FindChildrenWithClassTraverse('CollectionGW2Slot')[0];first.events.onmouseout();return true;})()`);
    report.cases.push({width,height,category,cards:state.cards.length,portraits:state.cards.flatMap(row=>row.images).length,searchNodes:0,textEntries:0,background:state.background,hover,screenshot:captures+'/'+name+'.png'});
    console.log('COLLECTION_USER_SKIN_CATEGORY_PASS '+name);
   }
   const restored=await b.run(`(()=>{const before=cfg.SurvivalCollection.Inspect().category;nodes.CollectionGW2Close.events.onactivate();syncLayout();const closed=!cfg.SurvivalCollection.IsOpen();cfg.SurvivalCollection.Open();syncLayout();return{before,closed,after:cfg.SurvivalCollection.Inspect().category,open:cfg.SurvivalCollection.IsOpen()};})()`);assert(restored.closed&&restored.open);assert.equal(restored.after,restored.before);report.interactions.push({width,height,...restored});
   const final=await b.run('('+inspect.toString()+')()');check(final,width,height,'beast');
  }
  report.changedSinceSnapshot=freeze(snapshot);report.status='PASS';
 }catch(error){report.status='FAIL';report.failure=error.stack||String(error);try{report.failureState=await b.run('('+inspect.toString()+')()');await b.shot(captures+'/failure.png',width,height);}catch{}throw error;}
 finally{fs.writeFileSync(out+'/report.json',JSON.stringify(report,null,2));b.close();}
 console.log('COLLECTION_USER_SKIN_PREVIEW_PASS '+out+'/report.json');
}
let settled=false;process.on('beforeExit',()=>{if(!settled){console.error('COLLECTION_USER_SKIN_PREVIEW_INCOMPLETE');process.exitCode=1;}});main().then(()=>{settled=true;},error=>{settled=true;console.error(error.stack||error);process.exitCode=1;});
