'use strict';
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {browser,sleep}=require('../shop_ui_12h/cdp.cjs');
process.chdir(path.resolve(__dirname,'../..'));
const base='design_refs/button_toggle_catalog_20261019',html=base+'/按钮与切换栏图册.html';
const keepAlive=setInterval(()=>{},1000),deadline=setTimeout(()=>{console.error('CATALOG_CAPTURE_TIMEOUT');process.exit(1);},110000);
const report={status:'STARTING',at:new Date().toISOString(),screenshots:[],remoteRequests:false};
fs.writeFileSync(base+'/verification.json',JSON.stringify(report,null,2));
async function main(){
 const b=await browser();
 try{
  await b.call('Network.enable');await b.call('Network.setBlockedURLs',{urls:['http://*','https://*','ws://*','wss://*']});
  await b.call('Emulation.setDeviceMetricsOverride',{width:1600,height:1100,deviceScaleFactor:1,mobile:false});
  await b.go(html);
  assert.equal(await b.run('window.catalogReady'),true);
  const images=await b.run('({count:document.querySelectorAll("article").length,broken:[...document.querySelectorAll("article img")].filter(i=>!i.complete||!i.naturalWidth).map(i=>i.alt),summary:window.catalogSummary})');
  assert.equal(images.count,images.summary.uniqueImages);assert.deepEqual(images.broken,[]);
  report.images=images;
  const interactions=await b.run(`(()=>{document.getElementById('search').value='N12';document.getElementById('search').dispatchEvent(new Event('input'));const visible=[...document.querySelectorAll('article')].filter(a=>!a.hidden);if(visible.length!==1||visible[0].dataset.id!=='N12')throw Error('ID search failed');visible[0].querySelector('input').click();const selected=document.getElementById('chosen').textContent;visible[0].querySelector('.zoom').click();const zoom=document.querySelector('dialog').open;document.getElementById('viewerClose').click();document.getElementById('search').value='';document.getElementById('kind').value='切换栏';document.getElementById('kind').dispatchEvent(new Event('change'));const toggles=[...document.querySelectorAll('article')].filter(a=>!a.hidden).length;document.getElementById('reset').click();return {selected,zoom,toggles,selectionCleared:document.getElementById('chosen').textContent};})()`);
  assert(interactions.selected.includes('N12'));assert(interactions.zoom);assert.equal(interactions.toggles,images.summary.toggles);assert.equal(interactions.selectionCleared,'尚未选择');report.interactions=interactions;
  const ids=['N12','N11','N13','N09','B353','B248','B329','B333','B038','B319','B178','B182','B183','B184','B220','B224','B158','B130','B148','B194','B196','B261','B361','B123'];
  const sheets=[{name:'常用按钮与切换栏总览',query:'?sheet=精选&ids='+ids.join(',')+'&title=按钮与切换栏：常用样式，按编号挑选'},
   {name:'全部按钮底图_第1页',query:'?sheet=按钮底图&page=1&title=按钮底图：第1页，完整图库含全部状态'},
   {name:'全部切换栏_第1页',query:'?sheet=切换栏&page=1&title=切换栏：第1页，完整图库含全部状态'}];
  for(const sheet of sheets){await b.go(html,sheet.query);await sleep(100);const state=await b.run('({ready:catalogReady,count:sheetCount,width:document.documentElement.clientWidth,height:Math.max(document.body.scrollHeight,document.documentElement.scrollHeight),broken:[...document.querySelectorAll("article img")].filter(i=>!i.complete||!i.naturalWidth).length})');assert(state.ready&&state.count>0);assert.equal(state.broken,0);assert(state.height<6000);const file=base+'/'+sheet.name+'.png';await b.shot(file,{x:0,y:0,width:1600,height:state.height});report.screenshots.push({path:file,...state});console.log('CATALOG_SHEET_PASS '+sheet.name+' '+state.count);}
  report.status='PASS';
 }catch(error){report.status='FAIL';report.error=error.stack;throw error;}
 finally{b.close();fs.writeFileSync(base+'/verification.json',JSON.stringify(report,null,2)+'\n');}
 console.log(JSON.stringify({status:report.status,images:report.images.count,broken:0,screenshots:report.screenshots.length}));
}
main().catch(e=>{console.error(e.stack||e);process.exitCode=1;}).finally(()=>{clearInterval(keepAlive);clearTimeout(deadline);});
