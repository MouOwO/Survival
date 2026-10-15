'use strict';
// Real production controllers with explicit isolated snapshots; all outbound events are stubs.
const fs=require('fs'),path=require('path'),assert=require('node:assert/strict');
const {browser}=require('../shop_ui_12h/cdp.cjs');
const repo=path.resolve(__dirname,'../..'),base='design_refs/archive_parchment_v1/work';
process.chdir(repo);
const input=base+'/preview/index.html',out=base+'/browser';
const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));
function inspect(){
 const shown=el=>{if(!el)return false;const s=getComputedStyle(el),r=el.getBoundingClientRect();return !el.hidden&&s.display!=='none'&&s.visibility!=='hidden'&&r.width>0&&r.height>0;};
 const describe=panel=>panel?{id:panel.id,visible:shown(panel.el),bounds:panel.el.getBoundingClientRect().toJSON(),text:panel.text}:null;
 const cards=nodes.ArchiveGrid.Children().filter(card=>card.visible&&card.BHasClass('ArchiveCard')).map(card=>({id:card.__archiveItem?.id,name:card.__archiveItem?.name,bounds:card.el.getBoundingClientRect().toJSON(),images:[...card.el.querySelectorAll('img')].filter(shown).map(el=>({src:el.src,decoded:el.complete&&el.naturalWidth>0}))}));
 const canvas=nodes.ArchiveV10Canvas,grid=nodes.ArchiveGrid,tip=nodes.ArchiveV10Tooltip;
 const assets=canvas?[...canvas.el.querySelectorAll('img')].filter(el=>/archive_parchment_v1/.test(el.src)&&shown(el)).map(el=>({id:el.id,src:el.src,decoded:el.complete&&el.naturalWidth>0,bounds:el.getBoundingClientRect().toJSON()})):[];
 const categoryButtons=Object.values(nodes).filter(panel=>panel.id.startsWith('ArchiveV10Category_')&&panel.visible).map(panel=>({id:panel.id.slice('ArchiveV10Category_'.length),label:panel.el.textContent}));
 return {errors:previewErrors,api:cfg.SurvivalArchiveV10?.Inspect(),canvas:describe(canvas),grid:{...describe(grid),scrollTop:grid.el.scrollTop,scrollHeight:grid.el.scrollHeight,clientHeight:grid.el.clientHeight,scrollbarThumbImage:getComputedStyle(grid.el,'::-webkit-scrollbar-thumb').backgroundImage},cards,assets,categoryButtons,searchEmpty:describe(nodes.ArchiveV10SearchEmpty),footer:describe(nodes.ArchiveFooter),status:describe(nodes.ArchiveStatus),tooltip:describe(tip),tooltipViewport:nodes.ArchiveV10TooltipViewport?{...describe(nodes.ArchiveV10TooltipViewport),scrollHeight:nodes.ArchiveV10TooltipViewport.el.scrollHeight,clientHeight:nodes.ArchiveV10TooltipViewport.el.clientHeight,scrollTop:nodes.ArchiveV10TooltipViewport.el.scrollTop}:null,subscriptions:subscribers.size,calls:previewCalls};
}
function inViewport(rect,width,height,label){assert(rect&&rect.width>0&&rect.height>0,label+' has visible geometry');assert(rect.x>=-1&&rect.y>=-1&&rect.right<=width+1&&rect.bottom<=height+1,label+' fits '+width+'x'+height);}
async function info(b){await b.run('syncLayout();true');return b.run('('+inspect.toString()+')()');}
async function frame(b,name,width,height){const state=await info(b);await b.shot(out+'/'+name+'.png',{x:0,y:0,width,height});fs.writeFileSync(out+'/'+name+'.json',JSON.stringify(state,null,2));return state;}
async function ready(b,query='?category=shadow'){await b.go(input,query);assert.equal(await b.run('previewReady'),true,'Production archive preview initializes');await b.run('document.fonts.ready.then(()=>true)');await b.run('Promise.all([...document.images].map(el=>el.decode().catch(()=>false))).then(()=>true)');}
function validate(state,width,height){assert.deepEqual(state.errors,[],'No production or adapter errors');assert(state.api?.active,'Archive presentation is active');assert.equal(state.api.layout,'parchment_rows','New parchment controller is loaded');assert(state.canvas?.visible,'Archive canvas is visible');inViewport(state.canvas.bounds,width,height,'Archive canvas');assert(state.assets.length>=4,'Parchment component assets are mounted');assert(state.assets.every(asset=>asset.decoded),'Visible parchment assets decode');assert(state.grid.scrollbarThumbImage.includes('archive_parchment_v1/scroll_thumb.png'),'Browser scrollbar adapter loads the actual parchment thumb texture');}
async function main(){
 fs.mkdirSync(out,{recursive:true});
 const report={at:new Date().toISOString(),kind:'archive_parchment_production_component_browser_preview',notGameCapture:true,assembly:JSON.parse(fs.readFileSync(base+'/preview/assembly.json','utf8')),sizes:[],categories:[],interactions:[],limitations:['Real project XML/JS/CSS executed in the existing Panorama browser adapter.','Names, effects, item IDs and categories come from current CSV; progress and balances are explicitly isolated fixture data.','Outbound game events are recorded by stubs, with no network, account, payment, reward or save operation.','Browser layout and native widgets approximate Panorama; native gameplay screenshots and resource compilation are separate checks.']};
 const b=await browser();
 try{
  for(const [width,height] of [[1280,720],[1920,1080],[2560,1440],[2560,1080],[960,720]]){
   await b.call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});await ready(b);
   const state=await frame(b,'shadow_'+width+'x'+height,width,height);validate(state,width,height);
   const expected=await b.run('previewFixturePages.shadow.length');assert.equal(state.cards.length,expected,'Every configured shadow row remains reachable');
   assert(state.cards.every(card=>card.images.length&&card.images.every(image=>image.decoded)),'Every shadow row icon and component image decodes');
   report.sizes.push({width,height,narrowStress:width===960,canvas:state.canvas.bounds,rows:state.cards.length,decodedAssets:state.assets.length});
  }
  await b.call('Emulation.setDeviceMetricsOverride',{width:1920,height:1080,deviceScaleFactor:1,mobile:false});await ready(b);
  await b.run('window.parchmentOriginalCanvas=nodes.ArchiveV10Canvas;window.parchmentOriginalSubscriptions=subscribers.size;true');
  const serverCategories=await b.run('PREVIEW_FIXTURE.v10.categories.map(category=>category.id)');
  assert.equal(serverCategories.length,18,'The server fixture retains all 18 categories, including the three collection pools');
  const categories=await b.run('cfg.SurvivalArchiveV10.Inspect().categories');
  assert.equal(categories.length,15,'The independent archive exposes 15 categories');
  assert.deepEqual([...categories].sort(),serverCategories.filter(id=>id!=='ex'&&id!=='friend'&&id!=='beast').sort(),'The social and blessing pools use the independent collection window');
  for(const category of categories){
   await b.run(`(async()=>{const id=${JSON.stringify(category)},button=nodes['ArchiveV10Category_'+id];if(!button?.events.onactivate)throw Error('Missing actual category button '+id);button.events.onactivate();emit('survival_archive_snapshot',previewSnapshot(id));await new Promise(resolve=>setTimeout(resolve,180));syncLayout();return true;})()`);
   const state=await frame(b,'category_'+category,1920,1080);validate(state,1920,1080);assert.equal(state.api.category,category);assert.equal(await b.run('nodes.ArchiveV10Canvas===parchmentOriginalCanvas'),true,'Category switches reuse canvas');assert(!state.tooltip?.visible,'Category switch clears former tooltip');
   const expected=await b.run('previewFixturePages['+JSON.stringify(category)+'].length');assert.equal(state.cards.length,expected,'Category '+category+' preserves every fixture row');
   report.categories.push({id:category,rows:state.cards.length,source:await b.run('PREVIEW_FIXTURE.v10.sources['+JSON.stringify(category)+']')});
  }
  await b.run('previewSelect("shadow")');const baseline=await info(b);
  for(const mode of ['unlocked','locked','all']){
   await b.run(`(()=>{const toggle=nodes.ArchiveV10FilterToggle;if(toggle?.events.onactivate)toggle.events.onactivate();const button=nodes['ArchiveV10Filter_'+${JSON.stringify(mode)}];if(!button?.events.onactivate)throw Error('Missing production filter');button.events.onactivate();syncLayout();return true;})()`);await delay(120);
   const state=await info(b),expected=mode==='all'?baseline.api.rows.length:baseline.api.rows.filter(row=>row.unlocked===(mode==='unlocked')).length;
   assert.equal(state.cards.length,expected,'Filter '+mode+' follows production ownership semantics');assert.deepEqual(state.errors,[]);report.interactions.push({kind:'filter',mode,rows:state.cards.length});
  }
  // The existing search filters sidebar categories, not current page items.
  const searchId=await b.run(`(()=>{const candidates=['ArchiveParchmentSearch','ArchiveV10Search','ArchiveSearch'];const exact=candidates.map(id=>nodes[id]).find(panel=>panel?.type==='TextEntry');const fallback=Object.values(nodes).find(panel=>panel.type==='TextEntry'&&panel.el.closest('#ArchiveV10Canvas'));return (exact||fallback)?.id||null;})()`);
  assert(searchId,'Search TextEntry exists in the actual archive');
  const name=baseline.categoryButtons.find(category=>category.id==='shadow').label;assert(name,'Search sample uses an actual category label');
  async function search(query){await b.run(`(()=>{const panel=nodes[${JSON.stringify(searchId)}];panel.text=${JSON.stringify(query)};panel.el.dispatchEvent(new Event('input',{bubbles:true}));syncLayout();return true;})()`);await delay(250);return info(b);}
  const matching=await search(name);assert(matching.categoryButtons.length>0&&matching.categoryButtons.every(category=>category.label.includes(name)),'Search narrows sidebar to the requested category');assert.deepEqual(matching.cards.map(card=>card.id),baseline.cards.map(card=>card.id),'Category search preserves current page contents');
  const missing=await search('__ARCHIVE_LOCAL_NO_MATCH_20261013__');assert.equal(missing.categoryButtons.length,0,'No-match search hides unrelated category buttons');assert(missing.searchEmpty?.visible,'No-match category hint is visible');assert.equal(missing.api.category,baseline.api.category);assert.deepEqual(missing.cards.map(card=>card.id),baseline.cards.map(card=>card.id));
  const restored=await search('');assert.equal(restored.categoryButtons.length,categories.length,'Clearing search restores all 15 active archive categories');assert(!restored.searchEmpty?.visible,'Search empty hint hides after clearing');report.interactions.push({kind:'categorySearch',query:name,matching:matching.categoryButtons.length,noMatch:0,restored:restored.categoryButtons.length,currentRowsUnchanged:true});
  await b.run(`(()=>{const card=nodes.ArchiveGrid.Children().find(panel=>panel.visible&&panel.BHasClass('ArchiveCard'));if(!card?.events.onmouseover)throw Error('Missing production hover handler');card.events.onmouseover();syncLayout();return true;})()`);await delay(300);
  const tooltip=await frame(b,'shadow_tooltip',1920,1080);assert(tooltip.tooltip?.visible,'Actual hover opens tooltip');inViewport(tooltip.tooltip.bounds,1920,1080,'Tooltip');report.interactions.push({kind:'tooltip',bounds:tooltip.tooltip.bounds});
  const scrollCategory=await b.run(`cfg.SurvivalArchiveV10.Inspect().categories.slice().sort((a,b)=>previewFixturePages[b].length-previewFixturePages[a].length)[0]`);
  await b.run('previewSelect('+JSON.stringify(scrollCategory)+')');let scroll=await info(b);assert(scroll.grid.scrollHeight>scroll.grid.clientHeight,'Configured long category has a scrollable list');
  const point={x:scroll.grid.bounds.x+scroll.grid.bounds.width*.65,y:scroll.grid.bounds.y+scroll.grid.bounds.height*.5};
  await b.call('Input.dispatchMouseEvent',{type:'mouseMoved',...point});await b.call('Input.dispatchMouseEvent',{type:'mouseWheel',...point,deltaX:0,deltaY:800});await delay(250);
  scroll=await frame(b,'category_'+scrollCategory+'_scrolled',1920,1080);assert(scroll.grid.scrollTop>0,'Actual browser wheel scrolls the list');report.interactions.push({kind:'scroll',category:scrollCategory,scrollTop:scroll.grid.scrollTop,rows:scroll.cards.length});
  const lifecycle=await b.run(`(()=>{const before=subscribers.size,close=nodes.ArchiveV10Close;if(!close?.events.onactivate)throw Error('Missing production close button');for(let i=0;i<12;i++){close.events.onactivate();if(cfg.SurvivalArchive.IsOpen())throw Error('Archive remained open');cfg.SurvivalArchive.Toggle();if(!cfg.SurvivalArchive.IsOpen())throw Error('Archive did not reopen');}syncLayout();return {before,after:subscribers.size,sameCanvas:nodes.ArchiveV10Canvas===parchmentOriginalCanvas};})()`);
  assert.equal(lifecycle.before,lifecycle.after,'Open/close does not add listeners');assert(lifecycle.sameCanvas,'Open/close reuses canvas');report.interactions.push({kind:'lifecycle',cycles:12,...lifecycle});
  await ready(b,'?category=shadow&state=edges');const edges=await info(b);assert.deepEqual(edges.errors,[]);assert.equal(edges.api.rows[0].unlocked,false,'Zero count remains unowned');assert.equal(edges.api.rows[1].unlocked,null,'Unknown count is not fabricated as zero');
  await b.run(`(()=>{const card=nodes.ArchiveGrid.Children().find(panel=>panel.__archiveItem?.id===previewFixturePages.shadow[6].id);card.events.onmouseover();syncLayout();return true;})()`);await delay(500);
  const long=await frame(b,'long_tooltip',1920,1080);assert(long.tooltip?.visible);inViewport(long.tooltip.bounds,1920,1080,'Long tooltip');assert(long.tooltipViewport&&long.tooltipViewport.scrollHeight>long.tooltipViewport.clientHeight,'Long text preserves an independently scrollable tooltip body');
  report.interactions.push({kind:'unknownAndLongTooltip',quantity:edges.api.rows[1].quantity,tooltip:long.tooltip.bounds,scrollHeight:long.tooltipViewport.scrollHeight});
  await ready(b,'?category=shadow&state=extra');const extra=await info(b);assert.equal(extra.cards.length,73,'Category capacity is not capped at the 23 initial shadow entries');
  await ready(b,'?category=shop&state=empty');const empty=await frame(b,'empty_category',1920,1080);assert.equal(empty.cards.length,0);assert.deepEqual(empty.errors,[]);report.interactions.push({kind:'capacityAndEmpty',capacityRows:extra.cards.length,emptyRows:0});
  report.status='PASS_BROWSER_ARCHIVE_PARCHMENT';
 }catch(error){report.status='FAIL_BROWSER_ARCHIVE_PARCHMENT';report.failure=error.stack||String(error);try{report.failureSnapshot=await info(b);await b.shot(out+'/failure.png');}catch(captureError){report.captureFailure=String(captureError);}throw error;}
 finally{fs.writeFileSync(out+'/report.json',JSON.stringify(report,null,2));b.close();}
 console.log('ARCHIVE_PARCHMENT_BROWSER_PASS '+out+'/report.json');
}
module.exports={inspect,validate,inViewport};
if(require.main===module){
 let verificationSettled=false;
 process.on('beforeExit',()=>{if(!verificationSettled){console.error('ARCHIVE_PARCHMENT_BROWSER_INCOMPLETE: Chrome/CDP closed before verification finished; no PASS result.');process.exitCode=1;}});
 main().then(()=>{verificationSettled=true;},error=>{verificationSettled=true;console.error(error.stack||error);process.exitCode=1;});
}
