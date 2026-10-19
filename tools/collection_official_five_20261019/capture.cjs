'use strict';
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {browser,sleep}=require('../market_filter_20261017/browser.cjs');
const repo=path.resolve(__dirname,'../..'),delivery=path.join(repo,'design_refs/collection_official_five_20261019'),qa=path.join(repo,'output/collection_official_five_20261019');
const themes=['classic','armory','crownfall','paper','gold'];
async function main(){
 fs.mkdirSync(qa,{recursive:true});const temporary=path.join(qa,'chrome_temp');fs.mkdirSync(temporary,{recursive:true});process.env.TEMP=temporary;process.env.TMP=temporary;const b=await browser(),report={kind:'browser_composed_design_candidates',notGameCapture:true,themes:[],viewports:[]};
 try{
  await b.call('Page.addScriptToEvaluateOnNewDocument',{source:'window.__previewErrors=[];window.addEventListener("error",e=>window.__previewErrors.push(e.message));'});
  await b.call('Emulation.setDeviceMetricsOverride',{width:1600,height:1000,deviceScaleFactor:1,mobile:false});
  for(const [index,theme]of themes.entries()){
   await b.go(path.join(delivery,'index.html'),'?theme='+theme+'#'+theme);
   const state=await b.run(`(()=>{const r=document.getElementById('collection').getBoundingClientRect(),tiles=[...document.querySelectorAll('.tile')],g=document.getElementById('grid').getBoundingClientRect(),f=document.querySelector('.window-footer').getBoundingClientRect();return{...CollectionPreview.Inspect(),bounds:{x:r.x,y:r.y,width:r.width,height:r.height,bottom:r.bottom},gridBottom:g.bottom,footerTop:f.top,images:[...document.images].filter(i=>!i.complete||i.naturalWidth===0).map(i=>i.src),columns:getComputedStyle(document.getElementById('grid')).gridTemplateColumns.split(' ').length,errors:window.__previewErrors};})()`);
   assert.equal(state.theme,theme);assert.equal(state.category,'ex');assert.equal(state.items,40);assert.equal(state.columns,10);assert.equal(state.selectedItems,0);assert(state.gridBottom<state.footerTop-4,'Grid clears the footer: '+theme);assert(state.bounds.bottom<=960,'Window is visible: '+theme);assert.deepEqual(state.images,[]);assert.deepEqual(state.errors,[]);
   const file=`${String(index+1).padStart(2,'0')}_${theme}.png`;await b.shot(path.join(delivery,file),1600,1000);report.themes.push({...state,file});
   const tip=await b.run(`(()=>{const card=document.querySelector('.tile'),r=card.getBoundingClientRect();card.dispatchEvent(new MouseEvent('mouseenter',{clientX:r.right,clientY:r.top}));const t=document.getElementById('tooltip').getBoundingClientRect();card.dispatchEvent(new MouseEvent('mouseleave'));return{x:t.x,y:t.y,right:t.right,bottom:t.bottom,width:t.width};})()`);assert(tip.width>200&&tip.x>=0&&tip.right<=1600&&tip.bottom<=1000,'Hover detail stays visible');
   await b.run(`document.querySelector('.tile').click();true`);assert.equal((await b.run('CollectionPreview.Inspect()')).selectedItems,0);
   await b.run(`document.querySelector('[data-category="wife"]').click();true`);assert.equal((await b.run('CollectionPreview.Inspect()')).items,40);
   await b.run(`document.getElementById('ownershipFilter').click();true`);assert((await b.run('CollectionPreview.Inspect()')).items<40);
   await b.run(`document.getElementById('ownershipFilter').click();true`);assert.equal((await b.run('CollectionPreview.Inspect()')).selectedItems,0);
   await b.run(`document.getElementById('ownershipFilter').click();document.getElementById('draw').click();true`);const drawn=await b.run('CollectionPreview.Inspect()');assert.equal(drawn.tickets,9);assert.equal(drawn.selectedItems,0);
   await b.run(`document.getElementById('close').click();true`);assert(await b.run('document.getElementById("collection").hidden'));await b.run(`document.getElementById('reopen').click();true`);assert(!(await b.run('document.getElementById("collection").hidden')));
  }
  for(const [width,height]of [[1920,1080],[1280,720],[960,720]]){
   await b.call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});
   await b.go(path.join(delivery,'index.html'),'?viewport='+width+'#paper');
   const rect=await b.run(`(()=>{const r=document.getElementById('collection').getBoundingClientRect();return{x:r.x,y:r.y,right:r.right,bottom:r.bottom,bodyWidth:document.body.scrollWidth};})()`);
   assert(rect.x>=10&&rect.right<=width-10,'Window fits width '+width);assert(rect.bottom<=height-25,'Window fits height '+height);assert(rect.bodyWidth<=width,'No horizontal page overflow');report.viewports.push({width,height,...rect});
  }
  report.result='PASS';
 }catch(error){report.result='FAIL';report.error=error.stack;try{await b.shot(path.join(qa,'failure.png'),1600,1000);}catch{}throw error;}
 finally{fs.writeFileSync(path.join(qa,'browser_report.json'),JSON.stringify(report,null,2));b.close();}
 console.log('COLLECTION_OFFICIAL_FIVE_CAPTURE_PASS: five full-size designs, 40 portraits each, categories, filters, no selection, local draw/reopen and three desktop sizes');
}
main().catch(error=>{console.error(error.stack);process.exitCode=1;});
