'use strict';
// Focused production component regression. Accounts, native input and transactions are unavailable.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),assert=require('node:assert/strict'),{fileURLToPath}=require('node:url');
const {browser,sleep}=require('../market_filter_20261017/browser.cjs');
const out='output/archive_visual_alignment_20261018',input=out+'/preview/index.html',captures=out+'/browser';
const sha=file=>crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const textSha=file=>crypto.createHash('sha256').update(fs.readFileSync(file,'utf8').replace(/^\uFEFF/,'')).digest('hex');
const inside=(r,p,epsilon=1)=>r.x>=p.x-epsilon&&r.y>=p.y-epsilon&&r.right<=p.right+epsilon&&r.bottom<=p.bottom+epsilon;
async function inspect(){
 const rect=el=>el.getBoundingClientRect().toJSON(),shown=el=>{if(!el)return false;for(let p=el;p;p=p.parentElement){const s=getComputedStyle(p);if(p.hidden||s.display==='none'||s.visibility==='hidden')return false;}const r=rect(el);return r.width>0&&r.height>0;};
 const describe=el=>{if(!el)return null;const css=getComputedStyle(el);return {id:el.id,tag:el.tagName,bounds:rect(el),visible:shown(el),src:el.currentSrc||el.src||null,decoded:el.tagName==='IMG'?el.complete&&el.naturalWidth>0:null,naturalWidth:el.naturalWidth,naturalHeight:el.naturalHeight,background:css.backgroundImage,overflowX:css.overflowX,overflowY:css.overflowY,borders:[css.borderTopWidth,css.borderRightWidth,css.borderBottomWidth,css.borderLeftWidth],childCount:el.children.length};};
 const pair=(name,glyph,ring)=>({name,glyph:describe(glyph),ring:describe(ring),delta:glyph&&ring?{x:(rect(glyph).x+rect(glyph).width/2)-(rect(ring).x+rect(ring).width/2),y:(rect(glyph).y+rect(glyph).height/2)-(rect(ring).y+rect(ring).height/2)}:null});
 const canvas=nodes.ArchiveV10Canvas,grid=nodes.ArchiveGrid,host=nodes.ArchiveV10GridHost,nav=Object.values(nodes).filter(row=>/^ArchiveV10Category_/.test(row.id));
 const headerRing=nodes.ArchiveV10CategoryIcon?.el.parentElement.querySelector('.ArchiveParchmentIconRing');
 const pairs=nav.map(row=>pair('nav:'+row.id,row.el.querySelector('.ArchiveV10Icon:not(.ArchiveParchmentIconRing)'),row.el.querySelector('.ArchiveParchmentIconRing')));
 pairs.push(pair('header',nodes.ArchiveV10CategoryIcon?.el,headerRing));
 const cards=grid.Children().filter(row=>row.visible&&row.__v10).map(row=>{const r=row.el.querySelector('.ArchiveParchmentIconRing'),stage=row.el.querySelector('.ArchiveParchmentIconStage');if(r&&stage)pairs.push(pair('row:'+row.__archiveItem.id,stage,r));return {id:row.__archiveItem.id,name:row.__archiveItem.name,bounds:rect(row.el),overflow:describe(row.el),ring:describe(r),images:[...row.el.querySelectorAll('img')].filter(shown).map(describe)};});
 const visibleImages=[...canvas.el.querySelectorAll('img')].filter(shown);await Promise.all(visibleImages.map(el=>el.decode().catch(()=>false)));
 const backgroundURIs=[...new Set([...canvas.el.querySelectorAll('*'),canvas.el].filter(shown).flatMap(el=>[...getComputedStyle(el).backgroundImage.matchAll(/url\(["']?([^"')]+)["']?\)/g)].map(match=>match[1])))];
 const backgrounds=await Promise.all(backgroundURIs.map(async src=>{const image=new Image();image.src=src;try{await image.decode();return {src,decoded:image.naturalWidth>0,width:image.naturalWidth,height:image.naturalHeight};}catch{return {src,decoded:false};}}));
 return {errors:previewErrors,api:cfg.SurvivalArchiveV10.Inspect(),caption:document.getElementById('PreviewCaption').textContent,canvas:describe(canvas.el),background:describe(nodes.ArchiveV10Shell_Background.el),header:describe(nodes.ArchiveV10Shell_Header.el),title:describe(nodes.ArchiveV10WindowTitle.el),headerGlyph:describe(nodes.ArchiveV10CategoryIcon.el),grid:{...describe(grid.el),scrollTop:grid.el.scrollTop,scrollHeight:grid.el.scrollHeight,clientHeight:grid.el.clientHeight},host:describe(host.el),cards,pairs,rings:[...canvas.el.querySelectorAll('.ArchiveParchmentIconRing')].filter(shown).map(describe),obsoleteRims:canvas.el.querySelectorAll('.ArchiveParchmentIconRim,.ArchiveParchmentIconEdge').length,images:visibleImages.map(describe),backgrounds,tooltip:describe(nodes.ArchiveV10Tooltip?.el),leaderboard:cfg.SurvivalEndlessLeaderboard?.Inspect(),calls:previewCalls};
}
function check(state,width,height,category){
 assert.deepEqual(state.errors,[]);assert.equal(state.api.category,category);assert(state.api.active);
 assert(inside(state.canvas.bounds,{x:0,y:0,right:width,bottom:height}),'Archive canvas fits viewport');
 assert(inside(state.title.bounds,state.header.bounds),'Full title rectangle is covered by header');
 assert(Math.abs(state.header.bounds.y-state.background.bounds.y)<=.5,'Header starts at window background top');
 assert.equal(state.obsoleteRims,0,'No old rim/edge child panels remain');
 assert(state.rings.length>=16,'Navigation/header rings are present');
 for(const ring of state.rings){assert.equal(ring.tag,'IMG','Each outer ring is one Image');assert.equal(ring.childCount,0);assert(ring.decoded);assert.match(ring.src,/archive_polish_v2\/icon_ring\.svg/);assert(ring.borders.every(v=>parseFloat(v)===0),'Ring has no duplicate native border');}
 for(const pair of state.pairs){assert(pair.glyph&&pair.ring,'Icon and ring exist: '+pair.name);assert(Math.abs(pair.delta.x)<=1.1&&Math.abs(pair.delta.y)<=1.1,'Icon and ring share a center: '+pair.name+' '+JSON.stringify(pair.delta));if(pair.name==='header'||pair.name.startsWith('nav:'))assert.match(pair.glyph.src,/archive_polish_v2\/nav\/.+\.svg/,'Category artwork uses the final clear SVG');}
 assert(state.images.length&&state.images.every(row=>row.decoded),'Every active image decodes, including offscreen current rows');
 assert(state.backgrounds.every(row=>row.decoded),'Every active CSS background decodes');
 for(const row of [...state.images,...state.backgrounds])if(row.src.startsWith('file:'))assert(fs.existsSync(fileURLToPath(row.src)),'Decoded asset exists locally');
 assert.deepEqual(state.api.missingIcons,[],'No question-mark fallback icons');
 assert.equal(state.host.overflowX,'hidden');assert.equal(state.host.overflowY,'hidden');
 for(const card of state.cards){assert.equal(card.overflow.overflowY,'hidden');if(card.ring)assert.equal(card.ring.overflowY,'hidden');}
 assert(!state.calls.some(row=>/claim|draw|purchase|checkout|activate|promote|equip/.test(row.name||row.event||'')),'No business mutation events are submitted');
}
function freeze(snapshot){const changed=[];for(const row of snapshot.sources)if(textSha('panorama/src/'+row.path)!==row.sha256)changed.push(row.path);for(const row of snapshot.assets)if(sha(row.path)!==row.sha256)changed.push(row.path);assert.deepEqual(changed,[],'Final source and assets remain frozen');return changed;}
async function main(){
 fs.mkdirSync(captures,{recursive:true});const snapshot=JSON.parse(fs.readFileSync(out+'/snapshot.json','utf8'));freeze(snapshot);
 const report={at:new Date().toISOString(),kind:'archive_visual_alignment_production_component_offline_preview',notGameCapture:true,networkBlocked:true,snapshot:out+'/snapshot.json',cases:[],limitations:['Chrome renders actual production XML/JS/CSS with explicit local fixture progress.','HTTP/HTTPS and page WebSocket requests are blocked; no account, native game inputs, purchases, rewards or save writes.','Images, fonts and native widgets are browser approximations; actual engine rasterization remains separate.']};
 const b=await browser();let lastWidth=1920,lastHeight=1080;
 try{
  await b.call('Network.setBlockedURLs',{urls:['http://*','https://*','ws://*','wss://*']});
  for(const [width,height]of [[1920,1080],[1280,720]]){
   lastWidth=width;lastHeight=height;await b.call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});await b.go(input,'?category=shadow');assert.equal(await b.run('previewReady'),true);
   await b.run(`(()=>{const products=[...PREVIEW_FIXTURE.commerce.paid.products,...PREVIEW_FIXTURE.commerce.wallet.products],seen=new Set();previewFixturePages.commerce_goods=products.filter(row=>{if(seen.has(row.sku))return false;seen.add(row.sku);return true;}).map((row,i)=>({id:row.sku,resource_id:row.sku,name:row.title,description:row.description,icon:row.icon,icon_type:'image',count:i%2,count_known:1,target:1,owned:i%2,unlocked:i%2}));return true;})()`);
   const categories=await b.run('cfg.SurvivalArchiveV10.Inspect().categories');assert(categories.length>=15);
   const selected=width===1920?categories:['shadow','clear','fishing','points','commerce_goods','shop','titles'].filter(id=>categories.includes(id));
   for(const category of selected){
    await b.run('previewSelect('+JSON.stringify(category)+')');await sleep(200);await b.run('syncLayout();true');
    const state=await b.run('('+inspect.toString()+')()'),name=width+'x'+height+'_'+category;check(state,width,height,category);fs.writeFileSync(captures+'/'+name+'.json',JSON.stringify(state,null,2));await b.shot(captures+'/'+name+'.png',width,height);
    report.cases.push({width,height,category,rows:state.cards.length,images:state.images.length,backgrounds:state.backgrounds.length,alignedPairs:state.pairs.length,header:state.header.bounds,title:state.title.bounds,screenshot:captures+'/'+name+'.png'});
    console.log('ARCHIVE_VISUAL_CATEGORY_PASS '+name+' rows='+state.cards.length+' images='+state.images.length);
   }
   await b.run('previewSelect("shadow")');await b.run('nodes.ArchiveGrid.ScrollToBottom();syncLayout();true');await sleep(150);
   const bottom=await b.run('('+inspect.toString()+')()');check(bottom,width,height,'shadow');assert(bottom.grid.scrollTop>0);assert(inside(bottom.cards.at(-1).ring.bounds,bottom.host.bounds),'Last ring is fully inside bottom viewport');
   const base=width+'x'+height+'_shadow_bottom';fs.writeFileSync(captures+'/'+base+'.json',JSON.stringify(bottom,null,2));await b.shot(captures+'/'+base+'.png',width,height);
   await b.run(`(()=>{const r=nodes.ArchiveV10GridHost.el.getBoundingClientRect(),card=nodes.ArchiveGrid.Children().find(row=>row.visible&&row.__v10&&row.el.getBoundingClientRect().y>=r.y&&row.el.getBoundingClientRect().bottom<=r.bottom);if(!card)throw Error('No visible bottom row');card.events.onmouseover();syncLayout();return true;})()`);await sleep(250);
   const tip=await b.run('('+inspect.toString()+')()');check(tip,width,height,'shadow');assert(tip.tooltip.visible);assert(inside(tip.tooltip.bounds,{x:0,y:0,right:width,bottom:height}),'Tooltip fits viewport');await b.shot(captures+'/'+base+'_tooltip.png',width,height);
   report.cases.push({width,height,category:'shadow',part:'bottom',scrollTop:bottom.grid.scrollTop,tooltip:tip.tooltip.bounds,screenshot:captures+'/'+base+'.png',tooltipScreenshot:captures+'/'+base+'_tooltip.png'});
  }
  report.changedSinceSnapshot=freeze(snapshot);report.status='PASS';
 }catch(error){report.status='FAIL';report.failure=error.stack||String(error);try{report.failureState=await b.run('('+inspect.toString()+')()');await b.shot(captures+'/failure.png',lastWidth,lastHeight);}catch{}throw error;}
 finally{fs.writeFileSync(out+'/report.json',JSON.stringify(report,null,2));b.close();}
 console.log('ARCHIVE_VISUAL_ALIGNMENT_PREVIEW_PASS '+out+'/report.json');
}
let settled=false;process.on('beforeExit',()=>{if(!settled){console.error('ARCHIVE_VISUAL_ALIGNMENT_PREVIEW_INCOMPLETE');process.exitCode=1;}});main().then(()=>{settled=true;},error=>{settled=true;console.error(error.stack||error);process.exitCode=1;});
