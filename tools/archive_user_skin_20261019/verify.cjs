'use strict';
// Focused production component regression. Accounts, native input and transactions are unavailable.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),assert=require('node:assert/strict'),{fileURLToPath}=require('node:url');
const {browser,sleep}=require('../market_filter_20261017/browser.cjs');
const out='output/archive_user_skin_20261019',input=out+'/preview/index.html',captures=out+'/browser';
const sha=file=>crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const textSha=file=>crypto.createHash('sha256').update(fs.readFileSync(file,'utf8').replace(/^\uFEFF/,'')).digest('hex');
const inside=(r,p,epsilon=1)=>r.x>=p.x-epsilon&&r.y>=p.y-epsilon&&r.right<=p.right+epsilon&&r.bottom<=p.bottom+epsilon;
async function inspect(){
 const rect=el=>el.getBoundingClientRect().toJSON(),shown=el=>{if(!el)return false;for(let p=el;p;p=p.parentElement){const s=getComputedStyle(p);if(p.hidden||s.display==='none'||s.visibility==='hidden')return false;}const r=rect(el);return r.width>0&&r.height>0;};
 const describe=el=>{if(!el)return null;const css=getComputedStyle(el);return {id:el.id,tag:el.tagName,bounds:rect(el),visible:shown(el),src:el.currentSrc||el.src||null,decoded:el.tagName==='IMG'?el.complete&&el.naturalWidth>0:null,naturalWidth:el.naturalWidth,naturalHeight:el.naturalHeight,background:css.backgroundImage,backgroundSource:nodes[el.id]?._style.backgroundImage,backgroundColor:css.backgroundColor,mask:css.maskImage,maskSource:nodes[el.id]?._style.opacityMask,maskSize:css.maskSize,overflowX:css.overflowX,overflowY:css.overflowY,borders:[css.borderTopWidth,css.borderRightWidth,css.borderBottomWidth,css.borderLeftWidth],childCount:el.children.length};};
 const pair=(name,glyph,ring)=>({name,glyph:describe(glyph),ring:describe(ring),delta:glyph&&ring?{x:(rect(glyph).x+rect(glyph).width/2)-(rect(ring).x+rect(ring).width/2),y:(rect(glyph).y+rect(glyph).height/2)-(rect(ring).y+rect(ring).height/2)}:null});
 const ownRing=el=>[...el.children].find(child=>getComputedStyle(child).backgroundImage.includes('/icon_ring.png'))||[...el.children].find(child=>child.classList.contains('ArchiveParchmentCategoryBadge'))?.querySelector('.ArchiveParchmentIconRing')||[...el.children].find(child=>child.classList.contains('ArchiveParchmentIconRing'));
 const canvas=nodes.ArchiveV10Canvas,grid=nodes.ArchiveGrid,host=nodes.ArchiveV10GridHost,nav=Object.values(nodes).filter(row=>/^ArchiveV10Category_/.test(row.id));
 const headerRing=ownRing(nodes.ArchiveV10CategoryIcon.el.parentElement);
 const pairs=nav.map(row=>pair('nav:'+row.id,row.el.querySelector('.ArchiveV10Icon:not(.ArchiveParchmentIconRing)'),ownRing(row.el)));
 pairs.push(pair('header',nodes.ArchiveV10CategoryIcon?.el,headerRing));
 const cards=grid.Children().filter(row=>row.visible&&row.__v10).map(row=>{const r=row.el.querySelector('.ArchiveParchmentIconRing'),stage=row.el.querySelector('.ArchiveParchmentIconStage');if(r&&stage)pairs.push(pair('row:'+row.__archiveItem.id,stage,r));return {id:row.__archiveItem.id,name:row.__archiveItem.name,bounds:rect(row.el),overflow:describe(row.el),ring:describe(r),images:[...row.el.querySelectorAll('img')].filter(shown).map(describe)};});
 const visibleImages=[...canvas.el.querySelectorAll('img')].filter(shown);await Promise.all(visibleImages.map(el=>el.decode().catch(()=>false)));
 const backgroundURIs=[...new Set([...canvas.el.querySelectorAll('*'),canvas.el].filter(shown).flatMap(el=>[...getComputedStyle(el).backgroundImage.matchAll(/url\(["']?([^"')]+)["']?\)/g)].map(match=>match[1])))];
 const backgrounds=await Promise.all(backgroundURIs.map(async src=>{const image=new Image();image.src=src;try{await image.decode();return {src,decoded:image.naturalWidth>0,width:image.naturalWidth,height:image.naturalHeight};}catch{return {src,decoded:false};}}));
 return {errors:previewErrors,api:cfg.SurvivalArchiveV10.Inspect(),caption:document.getElementById('PreviewCaption').textContent,canvas:describe(canvas.el),background:describe(nodes.ArchiveV10Shell_Background.el),sidebarBacking:describe(nodes.ArchiveV10Shell_Sidebar.el),contentBacking:describe(nodes.ArchiveV10Shell_Content.el),header:describe(nodes.ArchiveV10Shell_Header.el),title:describe(nodes.ArchiveV10WindowTitle.el),headerGlyph:describe(nodes.ArchiveV10CategoryIcon.el),grid:{...describe(grid.el),scrollTop:grid.el.scrollTop,scrollHeight:grid.el.scrollHeight,clientHeight:grid.el.clientHeight},host:describe(host.el),cards,pairs,rings:pairs.map(row=>row.ring).filter(Boolean),obsoleteRims:canvas.el.querySelectorAll('.ArchiveParchmentIconRim,.ArchiveParchmentIconEdge').length,images:visibleImages.map(describe),backgrounds,tooltip:describe(nodes.ArchiveV10Tooltip?.el),leaderboard:cfg.SurvivalEndlessLeaderboard?.Inspect(),calls:previewCalls};
}
function check(state,width,height,category){
 assert.deepEqual(state.errors,[]);assert.equal(state.api.category,category);assert(state.api.active);
 assert(inside(state.canvas.bounds,{x:0,y:0,right:width,bottom:height}),'Archive canvas fits viewport');
 assert(inside(state.title.bounds,state.header.bounds),'Full title rectangle is covered by header');
 assert(Math.abs(state.header.bounds.y-state.background.bounds.y)<=.5,'Header starts at window background top');
 const scale=state.title.bounds.height/44;
 assert(state.header.bounds.height>=71.5*scale,'Header grows from 56 to at least 72 design pixels');
 assert(state.header.bounds.bottom-state.title.bounds.bottom>=12*scale,'Title has sufficient dark backing below it');
 assert(state.title.bounds.y-state.header.bounds.y>=12*scale,'Title has sufficient dark backing above it');
 assert.equal(state.header.background,'none','Header is its own clean dark Panel');
 assert.equal(state.header.backgroundColor,'rgba(9, 12, 15, 0.96)');
 assert.match(state.header.maskSource,/archive_user_skin_v1\/right_fade\.svg/,'Header fades softly along the right edge');
 assert.match(state.header.mask,/^url\("data:image\/svg\+xml;base64,/,'Header browser mask uses exact SVG bytes without file-origin CORS');
 assert.match(state.background.background,/archive_user_skin_v1\/background\.png/,'Uses the supplied original background image');
 assert.match(state.background.maskSource,/archive_user_skin_v1\/background_fade\.svg/,'Whole background fades at right and bottom edges');
 assert.match(state.background.mask,/^url\("data:image\/svg\+xml;base64,/,'Background browser mask uses exact SVG bytes without file-origin CORS');
 assert.match(state.background.backgroundSource,/s2r:\/\/panorama\/images\/custom_game\/archive_user_skin_v1\/background\.vtex/);
 for(const panel of [state.sidebarBacking,state.contentBacking]){assert.equal(panel.background,'none','Old local panel art does not cover the supplied full background');assert.equal(panel.backgroundColor,'rgba(0, 0, 0, 0)');}
 assert.equal(state.obsoleteRims,0,'No old rim/edge child panels remain');
 assert(state.rings.length>=16,'Navigation/header rings are present');
 for(const ring of state.rings){assert.equal(ring.childCount,0);assert(ring.src||ring.background!=='none','Each unchanged ring has an image source');assert(ring.borders.every(v=>parseFloat(v)===0),'Ring has no duplicate native border');}
 for(const pair of state.pairs){assert(pair.glyph&&pair.ring,'Icon and ring exist: '+pair.name);assert(Math.abs(pair.delta.x)<=1.1&&Math.abs(pair.delta.y)<=1.1,'Icon and ring share a center: '+pair.name+' '+JSON.stringify(pair.delta));}
 assert(state.images.length&&state.images.every(row=>row.decoded),'Every active image decodes, including offscreen current rows');
 assert(state.backgrounds.every(row=>row.decoded),'Every active CSS background decodes');
 for(const row of [...state.images,...state.backgrounds])if(row.src.startsWith('file:'))assert(fs.existsSync(fileURLToPath(row.src)),'Decoded asset exists locally');
 assert.deepEqual(state.api.missingIcons,[],'No question-mark fallback icons');
 assert.equal(state.grid.overflowX,'hidden');assert.equal(state.grid.overflowY,'auto','Retain the existing scroll viewport behavior');
 assert(!state.calls.some(row=>/claim|draw|purchase|checkout|activate|promote|equip/.test(row.name||row.event||'')),'No business mutation events are submitted');
}
function freeze(snapshot){const changed=[];for(const row of snapshot.sources)if(textSha('panorama/src/'+row.path)!==row.sha256)changed.push(row.path);for(const row of snapshot.assets)if(sha(row.path)!==row.sha256)changed.push(row.path);assert.deepEqual(changed,[],'Final source and assets remain frozen');return changed;}
async function main(){
 fs.mkdirSync(captures,{recursive:true});const snapshot=JSON.parse(fs.readFileSync(out+'/snapshot.json','utf8'));freeze(snapshot);
 const original='C:/Users/Administrator/Desktop/背景图4.png',canonical='art/ui/sources/custom_game/archive_user_skin_v1/background.png',mirror='panorama/src/images/custom_game/archive_user_skin_v1/background.png';
 assert.equal(sha(canonical),sha(original),'Canonical background is the exact supplied PNG');assert.equal(sha(mirror),sha(original),'Panorama source mirror preserves supplied PNG bytes');
 const png=fs.readFileSync(canonical);assert.equal(png.subarray(1,4).toString(),'PNG');const sourceImage={sha256:sha(original),width:png.readUInt32BE(16),height:png.readUInt32BE(20),bytes:png.length};
 const report={at:new Date().toISOString(),kind:'archive_user_skin_production_component_offline_preview',notGameCapture:true,networkBlocked:true,snapshot:out+'/snapshot.json',sourceImage,cases:[],limitations:['Chrome renders actual production XML/JS/CSS with explicit local fixture progress.','HTTP/HTTPS and page WebSocket requests are blocked; no account, native game inputs, purchases, rewards or save writes.','Panorama opacity-mask is mirrored to browser mask-image with the same SVG and production values. Native engine mask sampling, fonts, widgets and rasterization remain separate.']};
 const b=await browser();let lastWidth=1920,lastHeight=1080;
 try{
  await b.call('Network.setBlockedURLs',{urls:['http://*','https://*','ws://*','wss://*']});
  for(const [width,height]of [[1920,1080],[1280,720]]){
   lastWidth=width;lastHeight=height;await b.call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});await b.go(input,'?category=shadow');assert.equal(await b.run('previewReady'),true);
   await b.run(`(()=>{const products=[...PREVIEW_FIXTURE.commerce.paid.products,...PREVIEW_FIXTURE.commerce.wallet.products],seen=new Set();previewFixturePages.commerce_goods=products.filter(row=>{if(seen.has(row.sku))return false;seen.add(row.sku);return true;}).map((row,i)=>({id:row.sku,resource_id:row.sku,name:row.title,description:row.description,icon:row.icon,icon_type:'image',count:i%2,count_known:1,target:1,owned:i%2,unlocked:i%2}));return true;})()`);
   const categories=await b.run('cfg.SurvivalArchiveV10.Inspect().categories');assert(categories.length>=15);
   const selected=['clear','shadow','gift','commerce_goods'].filter(id=>categories.includes(id));assert.equal(selected.length,4);
   for(const category of selected){
    await b.run('previewSelect('+JSON.stringify(category)+')');await sleep(200);await b.run('syncLayout();true');
    const state=await b.run('('+inspect.toString()+')()'),name=width+'x'+height+'_'+category;check(state,width,height,category);fs.writeFileSync(captures+'/'+name+'.json',JSON.stringify(state,null,2));await b.shot(captures+'/'+name+'.png',width,height);
    report.cases.push({width,height,category,rows:state.cards.length,images:state.images.length,backgrounds:state.backgrounds.length,alignedPairs:state.pairs.length,header:state.header.bounds,title:state.title.bounds,screenshot:captures+'/'+name+'.png'});
    console.log('ARCHIVE_USER_SKIN_CATEGORY_PASS '+name+' rows='+state.cards.length+' images='+state.images.length);
   }
   await b.run('previewSelect("shadow")');await b.run('nodes.ArchiveGrid.ScrollToBottom();syncLayout();true');await sleep(150);
   const bottom=await b.run('('+inspect.toString()+')()');check(bottom,width,height,'shadow');assert(bottom.grid.scrollTop>0);assert(inside(bottom.cards.at(-1).ring.bounds,bottom.host.bounds),'Last ring is fully inside bottom viewport');
   const base=width+'x'+height+'_shadow_bottom';fs.writeFileSync(captures+'/'+base+'.json',JSON.stringify(bottom,null,2));await b.shot(captures+'/'+base+'.png',width,height);
   await b.run(`(()=>{const r=nodes.ArchiveV10GridHost.el.getBoundingClientRect(),card=nodes.ArchiveGrid.Children().find(row=>row.visible&&row.__v10&&row.el.getBoundingClientRect().y>=r.y&&row.el.getBoundingClientRect().bottom<=r.bottom);if(!card)throw Error('No visible bottom row');card.events.onmouseover();syncLayout();return true;})()`);await sleep(250);
   const tip=await b.run('('+inspect.toString()+')()');check(tip,width,height,'shadow');assert(tip.tooltip.visible);assert(inside(tip.tooltip.bounds,{x:0,y:0,right:width,bottom:height}),'Tooltip fits viewport');await b.shot(captures+'/'+base+'_tooltip.png',width,height);
   report.cases.push({width,height,category:'shadow',part:'bottom',scrollTop:bottom.grid.scrollTop,tooltip:tip.tooltip.bounds,screenshot:captures+'/'+base+'.png',tooltipScreenshot:captures+'/'+base+'_tooltip.png'});
  }
  report.maskSamples={};
  for(const name of ['background_fade','right_fade']){
   const svg=fs.readFileSync('art/ui/sources/custom_game/archive_user_skin_v1/'+name+'.svg','utf8');
   const result=await b.run(`(async()=>{const image=new Image();image.src='data:image/svg+xml;charset=utf-8,'+encodeURIComponent(${JSON.stringify(svg)});await image.decode();const canvas=document.createElement('canvas');canvas.width=256;canvas.height=256;const ctx=canvas.getContext('2d');ctx.drawImage(image,0,0,256,256);const alpha=(x,y)=>ctx.getImageData(x,y,1,1).data[3];return {width:image.naturalWidth,height:image.naturalHeight,center:alpha(128,128),left:alpha(0,128),top:alpha(128,0),right:alpha(255,128),bottom:alpha(128,255),rightRamp:[232,240,244,248,252,255].map(x=>alpha(x,128)),bottomRamp:[232,240,244,248,252,255].map(y=>alpha(128,y)),corner:alpha(255,255)};})()`);
   assert(result.center>=254&&result.left>=254&&result.top>=254,name+' keeps the middle, top and left fully solid');
   assert(result.right<24,name+' softens the right edge');
   assert(result.rightRamp[0]>result.rightRamp.at(-1)+200,name+' right transition is a real gradual alpha fade');
   if(name==='background_fade'){assert(result.bottom<24);assert(result.corner<24);assert(result.bottomRamp[0]>result.bottomRamp.at(-1)+200);}
   else assert(result.bottom>=254,'Title backing retains its full lower edge');
   report.maskSamples[name]=result;
  }
  report.changedSinceSnapshot=freeze(snapshot);report.status='PASS';
 }catch(error){report.status='FAIL';report.failure=error.stack||String(error);try{report.failureState=await b.run('('+inspect.toString()+')()');await b.shot(captures+'/failure.png',lastWidth,lastHeight);}catch{}throw error;}
 finally{fs.writeFileSync(out+'/report.json',JSON.stringify(report,null,2));b.close();}
 console.log('ARCHIVE_USER_SKIN_PREVIEW_PASS '+out+'/report.json');
}
let settled=false;process.on('beforeExit',()=>{if(!settled){console.error('ARCHIVE_USER_SKIN_PREVIEW_INCOMPLETE');process.exitCode=1;}});main().then(()=>{settled=true;},error=>{settled=true;console.error(error.stack||error);process.exitCode=1;});
