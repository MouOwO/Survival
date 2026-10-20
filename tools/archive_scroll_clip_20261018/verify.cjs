'use strict';
// Isolated production UI preview. No game, account, draw or reward operations.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const {browser,sleep}=require('../market_filter_20261017/browser.cjs');
const out='output/archive_scroll_clip_20261018',preview=out+'/preview',captures=out+'/browser';
const hash=file=>crypto.createHash('sha256').update(fs.readFileSync(file,'utf8').replace(/^\uFEFF/,'')).digest('hex');
function inspect(){
 const rect=el=>el.getBoundingClientRect().toJSON(),style=el=>{const s=getComputedStyle(el);return {overflow:s.overflow,overflowX:s.overflowX,overflowY:s.overflowY,display:s.display};};
 const grid=nodes.ArchiveGrid,host=nodes.ArchiveV10GridHost,outer=rect(host.el);
 const cards=grid.Children().filter(card=>card.visible&&card.BHasClass('ArchiveCard')).map(card=>{
  const ring=card.el.querySelector('.ArchiveParchmentIconRing'),r=ring&&rect(ring),name=card.__v10?.name;
  return {id:card.__archiveItem.id,name:card.__archiveItem.name,renderedName:name?.text,position:rect(card.el),style:style(card.el),visual:style(card.__v10.host.el),ring:r?{position:r,style:style(ring),fullyOutside:r.bottom<=outer.y||r.y>=outer.bottom,fullyInside:r.y>=outer.y&&r.bottom<=outer.bottom,rims:[...ring.querySelectorAll('.ArchiveParchmentIconRim,.ArchiveParchmentIconEdge')].map(style)}:null};
 });
 const tip=nodes.ArchiveV10Tooltip;
 return {errors:previewErrors,api:cfg.SurvivalArchiveV10.Inspect(),host:{position:outer,style:style(host.el)},grid:{position:rect(grid.el),style:style(grid.el),scrollTop:grid.el.scrollTop,scrollHeight:grid.el.scrollHeight,clientHeight:grid.el.clientHeight},cards,tooltip:tip?{visible:tip.visible,position:rect(tip.el),text:tip.el.textContent}:null,subscriptions:subscribers.size,calls:previewCalls};
}
function check(state){
 assert.deepEqual(state.errors,[],'Production UI executes without errors');
 assert.equal(state.host.style.overflowX,'hidden','Outer host guards horizontal clipping');
 assert.equal(state.host.style.overflowY,'hidden','Outer host guards vertical clipping');
 assert.equal(state.grid.style.overflowY,'auto','Native scrolling remains the inner list responsibility');
 assert.equal(state.cards.length,state.api.rows.length,'All configured rows remain retained');
 for(const card of state.cards){
  const expectedName=state.api.category==='commerce_goods'?String(card.name||'').replace(/\s*[（(]功能版[）)]\s*$/,'').replace(/[·・]\s*永久\s*$/,''):card.name;
  assert.equal(expectedName,card.renderedName,'Existing authored row name treatment remains unchanged');
  assert.equal(card.style.overflowY,'hidden','Each card clips its native border descendants');
  assert.equal(card.visual.overflowY,'hidden','Visual host remains clipped');
  if(card.ring){assert.equal(card.ring.style.overflowY,'hidden','Ring is clipped');assert(card.ring.rims.every(row=>row.overflowY==='hidden'),'Rim and edge are clipped');}
 }
 assert(!state.calls.some(row=>/claim|draw|purchase|checkout/.test(row.name||row.event||'')),'Preview never submits a transaction');
}
async function main(){
 fs.mkdirSync(captures,{recursive:true});
 const assembly=JSON.parse(fs.readFileSync(preview+'/assembly.json','utf8'));
 const report={at:new Date().toISOString(),kind:'production_archive_scroll_clipping_preview',notGameCapture:true,assembly:preview+'/assembly.json',screens:[],limitations:['Chrome executes the actual production XML/JS/CSS with isolated fixture progress.','Native rounded-border clipping is a separate engine behavior and cannot be proved by this browser preview.','Dota process was present without a visible main window; no game input was sent.']};
 const b=await browser();
 try{
  for(const [width,height] of [[1920,1080],[1280,720]]){
   await b.call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});
   await b.go(preview+'/index.html','?category=shadow');assert.equal(await b.run('previewReady'),true);
   const expected=await b.run('previewFixturePages.shadow.map(row=>row.id)');
   for(const [part,fraction] of [['top',0],['middle',.5],['bottom',1]]){
    await b.run(`(()=>{nodes.ArchiveGrid.el.scrollTop=(nodes.ArchiveGrid.el.scrollHeight-nodes.ArchiveGrid.el.clientHeight)*${fraction};syncLayout();return true;})()`);await sleep(100);
    const state=await b.run('('+inspect.toString()+')()');check(state);
    assert.deepEqual(state.cards.map(row=>row.id),expected,'Scroll never removes or reorders rows');
    if(part==='top'){assert(state.cards.slice(7).some(row=>row.ring?.fullyOutside),'Later icons remain outside the initial viewport');}
    if(part==='bottom'){assert(state.cards.at(-1).ring?.fullyInside,'The last icon is fully visible after scrolling down');assert(state.grid.scrollTop>0,'List reaches its bottom');}
    const file=captures+'/'+width+'x'+height+'_'+part;
    await b.shot(file+'.png',width,height);fs.writeFileSync(file+'.json',JSON.stringify(state,null,2));
    report.screens.push({width,height,part,scrollTop:state.grid.scrollTop,rows:state.cards.length,visibleRings:state.cards.filter(row=>row.ring?.fullyInside).map(row=>row.id)});
   }
   await b.run(`(()=>{const grid=nodes.ArchiveGrid,viewport=nodes.ArchiveV10GridHost.el.getBoundingClientRect();const card=grid.Children().find(row=>row.visible&&row.BHasClass('ArchiveCard')&&row.el.getBoundingClientRect().y>=viewport.y&&row.el.getBoundingClientRect().bottom<=viewport.bottom);if(!card)throw Error('No fully visible row');card.events.onmouseover();syncLayout();return true;})()`);await sleep(250);
   const hover=await b.run('('+inspect.toString()+')()');check(hover);assert(hover.tooltip?.visible,'Actual retained card opens the tooltip at the list bottom');
   assert(hover.tooltip.position.x>=0&&hover.tooltip.position.y>=0&&hover.tooltip.position.right<=width+1&&hover.tooltip.position.bottom<=height+1,'Tooltip fits the viewport');
   await b.shot(captures+'/'+width+'x'+height+'_bottom_tooltip.png',width,height);
   await b.run(`(()=>{previewFixturePages.commerce_goods=PREVIEW_FIXTURE.commerce.paid.products.slice(0,14).map((row,i)=>({id:row.sku,resource_id:row.sku,name:row.title,description:row.description,icon:row.icon,icon_type:'image',count:i%2,count_known:1,target:1,owned:i%2,unlocked:i%2}));return true;})()`);
   await b.run('previewSelect("commerce_goods")');const goods=await b.run('('+inspect.toString()+')()');check(goods);assert(goods.cards.length>0,'Commerce clipping is exercised with real configured product fixture rows');
   await b.shot(captures+'/'+width+'x'+height+'_commerce_goods.png',width,height);
   report.screens.push({width,height,category:'commerce_goods',rows:goods.cards.length,clipping:true});
  }
  report.changedSinceSnapshot=assembly.sourceGraph.filter(item=>/^(scripts\/custom_game\/archive_v10\.js|styles\/custom_game\/archive_v10\.css)$/.test(item.path)).filter(item=>hash('panorama/src/'+item.path)!==item.sha256).map(item=>item.path);
  assert.deepEqual(report.changedSinceSnapshot,[],'Production files stay frozen throughout the preview');
  report.status='PASS';
 }catch(error){report.status='FAIL';report.failure=error.stack||String(error);try{report.failureSnapshot=await b.run('('+inspect.toString()+')()');await b.shot(captures+'/failure.png',1920,1080);}catch{}throw error;}
 finally{fs.writeFileSync(out+'/preview_report.json',JSON.stringify(report,null,2));b.close();}
 console.log('ARCHIVE_SCROLL_CLIP_PREVIEW_PASS '+out+'/preview_report.json');
}
let finished=false;process.on('beforeExit',()=>{if(!finished){console.error('ARCHIVE_SCROLL_CLIP_PREVIEW_INCOMPLETE');process.exitCode=1;}});
main().then(()=>{finished=true;},error=>{finished=true;console.error(error.stack||error);process.exitCode=1;});
