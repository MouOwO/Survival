'use strict';
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {browser}=require('./browser.cjs'),repo=path.resolve(__dirname,'../..'),delivery=path.join(repo,'design_refs/collection_gold_refine_20261019'),qa=path.join(repo,'output/collection_gold_refine_20261019/qa_preview');
async function main(){
 fs.mkdirSync(qa,{recursive:true});const b=await browser(),report={kind:'browser_composed_collection_gold_refinements',notGameCapture:true,rounds:[],categories:[],viewports:[]};
 try{
  await b.call('Page.addScriptToEvaluateOnNewDocument',{source:'window.__previewErrors=[];window.addEventListener("error",e=>window.__previewErrors.push(e.message));'});
  await b.call('Emulation.setDeviceMetricsOverride',{width:1600,height:1000,deviceScaleFactor:1,mobile:false});
  for(let round=1;round<=5;round++){
   await b.go(path.join(delivery,'index.html'),'#round'+round);
   const state=await b.run(`(()=>{const r=document.getElementById('collection').getBoundingClientRect(),g=document.getElementById('grid').getBoundingClientRect(),f=document.querySelector('.window-footer').getBoundingClientRect(),s=[...document.querySelectorAll('.nine')];return{...CollectionPreview.Inspect(),bounds:{x:r.x,y:r.y,width:r.width,height:r.height,bottom:r.bottom},gridBottom:g.bottom,footerTop:f.top,images:[...document.images].filter(i=>!i.complete||!i.naturalWidth).map(i=>i.src),columns:getComputedStyle(document.getElementById('grid')).gridTemplateColumns.split(' ').length,sliceSets:s.length,badSliceSets:s.filter(n=>n.children.length!==9).length,searchFields:document.querySelectorAll('input[type="search"]').length,animations:[...document.querySelectorAll('*')].filter(n=>getComputedStyle(n).animationName!=='none').length,errors:window.__previewErrors};})()`);
   assert.equal(state.round,round);assert.equal(state.items,40);assert.equal(state.columns,10);assert.equal(state.selectedItems,0);assert.equal(state.badSliceSets,0);assert.equal(state.searchFields,0);assert.equal(state.animations,0);assert(state.gridBottom<state.footerTop-3,'Grid clears footer at R'+round);assert.deepEqual(state.images,[]);assert.deepEqual(state.errors,[]);
   state.file='round_'+round+'.png';await b.shot(path.join(delivery,state.file),1600,1000);report.rounds.push(state);
  }
  for(const category of ['ex','friend','wife','beast']){
   await b.run(`CollectionPreview.Select(${JSON.stringify(category)});true`);
   await b.run('Promise.all([...document.images].map(i=>i.decode().catch(()=>false))).then(()=>true)');
   const state=await b.run('CollectionPreview.Inspect()');assert.equal(state.items,40);assert.equal(state.category,category);assert.equal(state.selectedItems,0);report.categories.push(state);
   const hovered=await b.run(`(()=>{const c=document.querySelector('.tile'),r=c.getBoundingClientRect();c.dispatchEvent(new MouseEvent('mouseenter',{clientX:r.right,clientY:r.top}));const t=document.getElementById('tooltip').getBoundingClientRect();return{x:t.x,y:t.y,right:t.right,bottom:t.bottom,width:t.width,nine:document.getElementById('tooltip').querySelectorAll('.nine>img').length};})()`);assert(hovered.x>=0&&hovered.right<=1600&&hovered.bottom<=1000);assert.equal(hovered.nine,9);
   if(category==='beast')await b.shot(path.join(qa,'final_tooltip_beast.png'),1600,1000);
   await b.run(`document.querySelector('.tile').dispatchEvent(new MouseEvent('mouseleave'));document.querySelector('.tile').click();true`);assert.equal((await b.run('CollectionPreview.Inspect()')).selectedItems,0);
   await b.run(`document.getElementById('ownershipFilter').click();true`);const own=await b.run('CollectionPreview.Inspect()');assert(own.items<40);await b.run(`document.getElementById('ownershipFilter').click();true`);assert.equal((await b.run('CollectionPreview.Inspect()')).items,40-own.items);await b.run(`document.getElementById('ownershipFilter').click();true`);
  }
  await b.run(`document.getElementById('draw').click();true`);const draw=await b.run('CollectionPreview.Inspect()');assert.equal(draw.tickets,9);assert.equal(draw.selectedItems,0);assert(await b.run('document.getElementById("drawResult").textContent.startsWith("获得 ")'));
  await b.run(`document.getElementById('close').click();true`);assert(await b.run('document.getElementById("collection").hidden'));await b.run(`document.getElementById('reopen').click();true`);assert(!(await b.run('document.getElementById("collection").hidden')));
  for(const [width,height]of [[1920,1080],[1280,720],[960,720]]){
   await b.call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});await b.go(path.join(delivery,'index.html'),'#round5');
   const rect=await b.run(`(()=>{const r=document.getElementById('collection').getBoundingClientRect(),c=document.querySelector('.outer-frame .slice-00').getBoundingClientRect();return{x:r.x,y:r.y,right:r.right,bottom:r.bottom,bodyWidth:document.body.scrollWidth,cornerSize:[c.width,c.height],localCornerSize:[getComputedStyle(document.querySelector('.outer-frame .slice-00')).width,getComputedStyle(document.querySelector('.outer-frame .slice-00')).height]};})()`);
   assert(rect.x>=10&&rect.right<=width-10,'Fits viewport '+width);assert(rect.bottom<=height-20,'Fits height '+height);assert(rect.bodyWidth<=width);assert.deepEqual(rect.localCornerSize,['10px','10px']);report.viewports.push({width,height,...rect});await b.shot(path.join(qa,'final_'+width+'.png'),width,height);
  }
  report.result='PASS';
 }catch(error){report.result='FAIL';report.error=error.stack;try{await b.shot(path.join(qa,'failure.png'),1600,1000);}catch{}throw error;}
 finally{fs.writeFileSync(path.join(qa,'browser_report.json'),JSON.stringify(report,null,2));b.close();}
 console.log('COLLECTION_GOLD_REFINE_CAPTURE_PASS: 5 cumulative rounds; 4×40 entries; true nine-part controls; filter, tooltip, draw, reopen; three desktop sizes');
}
main().catch(error=>{console.error(error.stack);process.exitCode=1;});
