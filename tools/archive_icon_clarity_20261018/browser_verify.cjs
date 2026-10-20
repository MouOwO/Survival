'use strict';
// Isolated production-component preview only: no native game, console or server.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const {fileURLToPath}=require('node:url');
const {browser,sleep}=require('../shop_ui_12h/cdp.cjs');
const root=path.resolve(__dirname,'../..'),base='design_refs/archive_icon_clarity_20261018',out=base+'/browser',input=base+'/preview/index.html';
process.chdir(root);fs.mkdirSync(out,{recursive:true});
function inspect(){
 const bounds=el=>el.getBoundingClientRect().toJSON();
 const shown=el=>{for(let n=el;n;n=n.parentElement){const s=getComputedStyle(n);if(n.hidden||s.display==='none'||s.visibility==='hidden')return false;}const r=el.getBoundingClientRect();return r.width>0&&r.height>0;};
 const image=el=>({src:el.currentSrc||el.src,decoded:el.complete&&el.naturalWidth>0,width:el.naturalWidth,height:el.naturalHeight,bounds:bounds(el),visible:shown(el)});
 const canvas=nodes.ArchiveV10Canvas,grid=nodes.ArchiveGrid;
 const images=[...canvas.el.querySelectorAll('img')].filter(shown).map(image);
 const cards=grid.Children().filter(card=>card.visible&&card.__v10).map(card=>({id:card.__archiveItem?.id,name:card.__archiveItem?.name,bounds:bounds(card.el),resource:cfg.SurvivalItemResources?.Lookup(card.__archiveItem)?.uri,images:[...card.el.querySelectorAll('img')].filter(shown).map(image)}));
 const backgrounds=[...new Set([...canvas.el.querySelectorAll('*'),canvas.el].filter(shown).flatMap(el=>[...getComputedStyle(el).backgroundImage.matchAll(/url\(["']?([^"')]+)["']?\)/g)].map(m=>m[1])))];
 return {ready:previewState.ready,errors:previewErrors,api:cfg.SurvivalArchiveV10.Inspect(),canvas:bounds(canvas.el),grid:{bounds:bounds(grid.el),scrollTop:grid.el.scrollTop,clientHeight:grid.el.clientHeight,scrollHeight:grid.el.scrollHeight},images,cards,backgrounds,calls:previewCalls};
}
function localMissing(uris){return [...new Set(uris)].filter(uri=>!uri.startsWith('data:')&&(!uri.startsWith('file:')||!fs.existsSync(fileURLToPath(uri))));}
function validate(info,width,height,category){
 assert(info.ready,'Production component initialized');assert.deepEqual(info.errors,[],'No UI script errors');
 assert.equal(info.api.category,category);assert(info.canvas.x>=-1&&info.canvas.y>=-1&&info.canvas.right<=width+1&&info.canvas.bottom<=height+1,'Archive fits viewport');
 assert(info.images.length>0&&info.images.every(img=>img.decoded),'Every visible image decodes');
 assert(info.cards.length>0&&info.cards.every(card=>card.images.length&&card.images.every(img=>img.decoded)),'All category row images decode, including offscreen rows');
 assert.deepEqual(info.api.missingIcons,[],'No fallback question-mark resources');
 const uris=info.images.map(img=>img.src).concat(info.backgrounds);assert.deepEqual(localMissing(uris),[],'All image and visible background resources exist locally');
 assert(info.calls.every(call=>['survival_archive_request','survival_vip_request','survival_daily_request'].includes(call.name)),'Only stubbed read-only UI queries are exercised');
 if(category==='shadow'){
  assert.equal(info.cards.length,23,'All 23 formal shadow rows remain accessible');
  assert.equal(info.cards[0].id,'shadow_01');assert.equal(info.cards.at(-1).id,'shadow_23');
  assert(info.cards.every(card=>card.images.some(img=>img.width===256&&img.height===256)),'All 23 original images decode at their real 256px resolution');
 }
}
async function main(){
 const report={at:new Date().toISOString(),kind:'isolated_archive_icon_clarity_production_component_browser',notGameCapture:true,networkBlocked:true,assembly:JSON.parse(fs.readFileSync(base+'/preview/assembly.json','utf8')),cases:[],limitations:['Chrome emulates Panorama APIs and layout; these are component previews, not native game screenshots.','All progress and counts are explicit browser samples; outbound game events are stubs.','HTTP, HTTPS and WebSocket page requests are blocked. No native game, console, login, payment, draw or reward calls.']};
 const b=await browser();
 try{
  await b.call('Network.enable');await b.call('Network.setBlockedURLs',{urls:['http://*','https://*','ws://*','wss://*']});
  for(const [width,height]of [[960,720],[1920,1080],[2560,1440]])for(const category of ['shadow','fishing']){
   const name=category+'_'+width+'x'+height;
   await b.call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});
   await b.go(input,'?category='+category);assert.equal(await b.run('previewReady'),true);
   await b.run('syncLayout();true');await sleep(100);
   const info=await b.run('('+inspect.toString()+')()');fs.writeFileSync(out+'/'+name+'.json',JSON.stringify(info,null,2));
   await b.shot(out+'/'+name+'.png',{x:0,y:0,width,height});validate(info,width,height,category);
   const entry={name,width,height,category,rows:info.cards.length,images:info.images.length,allImagesDecoded:true,canvas:info.canvas,screenshot:out+'/'+name+'.png',first:info.cards[0],last:info.cards.at(-1)};
   if(category==='shadow'){
    await b.run('nodes.ArchiveGrid.ScrollToBottom();syncLayout();true');await sleep(100);
    const bottom=await b.run('('+inspect.toString()+')()');validate(bottom,width,height,category);
    assert(bottom.grid.scrollTop>0,'The complete list scrolls');
    const last=bottom.cards.at(-1).bounds,viewport=bottom.grid.bounds;
    assert(last.bottom<=viewport.bottom+1&&last.bottom>viewport.top,'Last shadow item is reachable in the scroll viewport');
    fs.writeFileSync(out+'/'+name+'_bottom.json',JSON.stringify(bottom,null,2));await b.shot(out+'/'+name+'_bottom.png',{x:0,y:0,width,height});
    entry.bottomScreenshot=out+'/'+name+'_bottom.png';entry.scrollTop=bottom.grid.scrollTop;
   }
   report.cases.push(entry);console.log('ARCHIVE_ICON_BROWSER_PASS '+name+' rows='+info.cards.length);
  }
  const selected=/^(scripts\/custom_game\/(archive_v10|archive_v10_icons|reward_presentation|common\/item_resources)\.js|styles\/custom_game\/archive_v10\.css)$/;
  report.changedCriticalSources=report.assembly.sourceGraph.filter(item=>selected.test(item.path)).filter(item=>crypto.createHash('sha256').update(fs.readFileSync('panorama/src/'+item.path,'utf8').replace(/^\uFEFF/,'')).digest('hex')!==item.sha256).map(item=>item.path);
  assert.deepEqual(report.changedCriticalSources,[],'Critical code stayed frozen during preview capture');report.status='PASS';
 }catch(error){report.status='FAIL';report.failure=error.stack||String(error);try{report.failureState=await b.run('('+inspect.toString()+')()');await b.shot(out+'/failure.png');}catch{}throw error;}
 finally{fs.writeFileSync(out+'/report.json',JSON.stringify(report,null,2));b.close();}
 console.log('ARCHIVE_ICON_CLARITY_BROWSER_COMPLETE '+out+'/report.json');
}
main().catch(error=>{console.error(error.stack||error);process.exitCode=1;});
