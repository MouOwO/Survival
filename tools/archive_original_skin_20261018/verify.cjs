'use strict';
// Real GW2 dat texture / production archive preview, isolated from accounts and game inputs.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),assert=require('node:assert/strict'),zlib=require('node:zlib');
const {browser,sleep}=require('../market_filter_20261017/browser.cjs');
const out='output/archive_original_skin_20261018',preview=out+'/preview',captures=out+'/browser';
const assetNames=['window_background','header_strip','sidebar_background','content_background'];
const sha=file=>crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const sourceHash=file=>crypto.createHash('sha256').update(fs.readFileSync(file,'utf8').replace(/^\uFEFF/,'')).digest('hex');
async function inspect(){
 const rect=el=>el.getBoundingClientRect().toJSON(),style=el=>{const s=getComputedStyle(el);return {overflow:s.overflow,overflowX:s.overflowX,overflowY:s.overflowY,display:s.display};};
 const grid=nodes.ArchiveGrid,host=nodes.ArchiveV10GridHost,outer=rect(host.el),canvas=nodes.ArchiveV10Canvas;
 const cards=grid.Children().filter(card=>card.visible&&card.BHasClass('ArchiveCard')).map(card=>{
  const ring=card.el.querySelector('.ArchiveParchmentIconRing'),r=ring&&rect(ring),name=card.__v10?.name;
  return {id:card.__archiveItem.id,name:card.__archiveItem.name,renderedName:name?.text,position:rect(card.el),style:style(card.el),visual:style(card.__v10.host.el),ring:r?{position:r,style:style(ring),fullyOutside:r.bottom<=outer.y||r.y>=outer.bottom,fullyInside:r.y>=outer.y&&r.bottom<=outer.bottom,rims:[...ring.querySelectorAll('.ArchiveParchmentIconRim,.ArchiveParchmentIconEdge')].map(style)}:null};
 });
 const tip=nodes.ArchiveV10Tooltip;
 const texts=[nodes.ArchiveV10WindowTitle,nodes.ArchiveV10OverviewTitle,nodes.ArchiveV10_page_title,nodes.ArchiveV10SectionTitle,...grid.Children().filter(card=>card.visible&&card.__v10).flatMap(card=>[card.__v10.name,card.__v10.count])].filter(panel=>{if(!panel?.el||!panel.text)return false;const r=rect(panel.el);return r.width>0&&r.height>0&&r.y>=outer.y&&r.bottom<=outer.bottom||['ArchiveV10WindowTitle','ArchiveV10OverviewTitle','ArchiveV10_page_title','ArchiveV10SectionTitle'].includes(panel.id);}).map(panel=>{const css=getComputedStyle(panel.el);return {id:panel.id,text:panel.text,position:rect(panel.el),color:css.color,fontFamily:css.fontFamily,fontSize:css.fontSize,opacity:css.opacity};});
 const imageSources=new Map([...canvas.el.querySelectorAll('img')].filter(el=>/archive_parchment_v1/.test(el.src)).map(el=>[el.src,el.id]));
 for(const el of canvas.el.querySelectorAll('*')){const match=getComputedStyle(el).backgroundImage.match(/url\(["']?([^"')]+)["']?\)/);if(match&&/archive_parchment_v1/.test(match[1]))imageSources.set(match[1],el.id);}
 const images=await Promise.all([...imageSources].map(async([src,id])=>{const image=new Image();image.src=src;try{await image.decode();return {id,src,decoded:image.naturalWidth>0,width:image.naturalWidth,height:image.naturalHeight};}catch{return {id,src,decoded:false};}}));
 return {errors:previewErrors,api:cfg.SurvivalArchiveV10.Inspect(),caption:document.getElementById('PreviewCaption').textContent,canvas:{position:rect(canvas.el)},host:{position:outer,style:style(host.el)},grid:{position:rect(grid.el),style:style(grid.el),scrollTop:grid.el.scrollTop,scrollHeight:grid.el.scrollHeight,clientHeight:grid.el.clientHeight},cards,images,texts,tooltip:tip?{visible:tip.visible,position:rect(tip.el),text:tip.el.textContent}:null,subscriptions:subscribers.size,calls:previewCalls};
}
function check(state,width,height){
 assert.deepEqual(state.errors,[],'Production UI executes without errors');
 assert.match(state.caption,/真实 GW2 原始纹理.*离线.*未连接/,'Caption distinguishes asset provenance and isolated preview');
 for(const [label,r] of [['canvas',state.canvas.position],['list host',state.host.position]])assert(r.x>=-1&&r.y>=-1&&r.right<=width+1&&r.bottom<=height+1,label+' fits viewport');
 assert.equal(state.host.style.overflowX,'hidden','Outer host guards horizontal clipping');
 assert.equal(state.host.style.overflowY,'hidden','Outer host guards vertical clipping');
 assert.equal(state.grid.style.overflowY,'auto','Inner native list remains scrollable');
 assert.equal(state.cards.length,state.api.rows.length,'All configured rows remain retained');
 assert(state.images.length>=4&&state.images.every(row=>row.decoded),'All archive component textures decode');
 for(const card of state.cards){
  const expectedName=state.api.category==='commerce_goods'?String(card.name||'').replace(/\s*[（(]功能版[）)]\s*$/,'').replace(/[·・]\s*永久\s*$/,''):card.name;
  assert.equal(expectedName,card.renderedName,'Existing row name treatment stays unchanged');
  assert.equal(card.style.overflowY,'hidden','Each card clips border descendants');
  assert.equal(card.visual.overflowY,'hidden','Visual host stays clipped');
  if(card.ring){assert.equal(card.ring.style.overflowY,'hidden');assert(card.ring.rims.every(row=>row.overflowY==='hidden'),'Native rim/edge retain the previous clipping fix');}
 }
 assert(!state.calls.some(row=>/claim|draw|purchase|checkout/.test(row.name||row.event||'')),'Preview never submits a transaction');
}
// Chrome screenshots are RGB/RGBA PNGs; decode with built-in zlib, without new packages.
function png(file){
 const bytes=fs.readFileSync(file);let cursor=8,width,height,channels,idat=[];
 while(cursor<bytes.length){const count=bytes.readUInt32BE(cursor),kind=bytes.toString('ascii',cursor+4,cursor+8),body=bytes.subarray(cursor+8,cursor+8+count);if(kind==='IHDR'){width=body.readUInt32BE(0);height=body.readUInt32BE(4);assert.equal(body[8],8);channels=body[9]===6?4:body[9]===2?3:0;assert(channels,'Only RGB/RGBA screenshots are supported');assert.equal(body[12],0);}if(kind==='IDAT')idat.push(body);cursor+=count+12;}
 const raw=zlib.inflateSync(Buffer.concat(idat)),stride=width*channels,data=Buffer.alloc(stride*height);let p=0;
 const paeth=(a,b,c)=>{const p=a+b-c,pa=Math.abs(p-a),pb=Math.abs(p-b),pc=Math.abs(p-c);return pa<=pb&&pa<=pc?a:pb<=pc?b:c;};
 for(let y=0;y<height;y++){const filter=raw[p++];for(let x=0;x<stride;x++){const i=y*stride+x,left=x>=channels?data[i-channels]:0,up=y?data[i-stride]:0,ul=y&&x>=channels?data[i-stride-channels]:0,v=raw[p++];data[i]=(v+(filter===0?0:filter===1?left:filter===2?up:filter===3?Math.floor((left+up)/2):paeth(left,up,ul)))&255;}}
 return {width,height,channels,data};
}
function contrast(screenshot,texts){
 const p=png(screenshot),linear=v=>{v/=255;return v<=.04045?v/12.92:Math.pow((v+.055)/1.055,2.4);},lum=c=>.2126*linear(c[0])+.7152*linear(c[1])+.0722*linear(c[2]);
 return texts.map(text=>{const box=text.position,foreground=(text.color.match(/[\d.]+/g)||[]).slice(0,3).map(Number),samples=[];for(let y=Math.max(0,Math.ceil(box.y+box.height*.3));y<Math.min(p.height,box.bottom-box.height*.2);y+=3)for(let x=Math.max(0,Math.ceil(box.x+2));x<Math.min(p.width,box.x+Math.min(box.width-2,180));x+=3){const i=(y*p.width+x)*p.channels;const bg=[p.data[i],p.data[i+1],p.data[i+2]],a=lum(foreground),b=lum(bg);samples.push((Math.max(a,b)+.05)/(Math.min(a,b)+.05));}samples.sort((a,b)=>a-b);return {...text,contrastMedian:samples[Math.floor(samples.length*.5)],contrastP10:samples[Math.floor(samples.length*.1)],samples:samples.length};});
}
function verifyFiles(plan){
 const baseline=JSON.parse(fs.readFileSync(out+'/layout_baseline.json','utf8'));for(const row of baseline.files)assert.equal(sha(row.path),row.sha256,'Layout/code unchanged: '+row.path);
 for(const row of plan.assets)for(const file of row.mirrors)assert.equal(sha(file),row.sha256,'Reviewed texture mirror: '+file);
 return baseline;
}
async function main(){
 fs.mkdirSync(captures,{recursive:true});
 const assembly=JSON.parse(fs.readFileSync(preview+'/assembly.json','utf8')),plan=JSON.parse(fs.readFileSync(out+'/asset_freeze.json','utf8'));
 const baseline=verifyFiles(plan),report={at:new Date().toISOString(),kind:'real_original_gw2_archive_skin_browser_preview',notGameCapture:true,assembly:preview+'/assembly.json',sourceProvenance:out+'/source_audit/source_report.json',assets:plan.assets,layoutBaseline:baseline,screens:[],textContrast:[],limitations:['Actual production XML/JS/CSS executes with isolated fixture progress, offline and without account/game inputs.','Native clipping and font rasterization remain separate engine behavior.','Contrast samples use rendered backgrounds with text temporarily transparent in this preview only.','Dota was present without a visible main window; no game input or real reward transaction was sent.']};
 const b=await browser();
 try{
  for(const [width,height] of [[1920,1080],[1280,720]]){
   await b.call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});
   await b.go(preview+'/index.html','?category=shadow');assert.equal(await b.run('previewReady'),true);
   const expected=await b.run('previewFixturePages.shadow.map(row=>row.id)');
   for(const [part,fraction] of [['top',0],['middle',.5],['bottom',1]]){
    await b.run(`(()=>{nodes.ArchiveGrid.el.scrollTop=(nodes.ArchiveGrid.el.scrollHeight-nodes.ArchiveGrid.el.clientHeight)*${fraction};syncLayout();return true;})()`);await sleep(120);
    const state=await b.run('('+inspect.toString()+')()');check(state,width,height);
    assert.deepEqual(state.cards.map(row=>row.id),expected,'Scroll never removes/reorders rows');
    if(part==='top')assert(state.cards.slice(7).some(row=>row.ring?.fullyOutside),'Later icons remain clipped outside initial viewport');
    if(part==='bottom'){assert(state.cards.at(-1).ring?.fullyInside,'Last icon becomes fully visible at list bottom');assert(state.grid.scrollTop>0);}
    const file=captures+'/'+width+'x'+height+'_'+part;await b.shot(file+'.png',width,height);fs.writeFileSync(file+'.json',JSON.stringify(state,null,2));
    report.screens.push({width,height,part,scrollTop:state.grid.scrollTop,rows:state.cards.length,visibleRings:state.cards.filter(row=>row.ring?.fullyInside).map(row=>row.id)});
    if(part==='top'){
     await b.run(`(()=>{const style=document.createElement('style');style.id='OriginalSkinContrastSample';style.textContent='.label{color:transparent!important;text-shadow:none!important}';document.head.append(style);return true;})()`);
     const clean=file+'_background_only.png';await b.shot(clean,width,height);await b.run('document.getElementById("OriginalSkinContrastSample").remove();true');
     const rows=contrast(clean,state.texts);assert(rows.length>=8,'Heading and row texts sampled');assert(rows.every(row=>row.samples>0&&row.contrastMedian>=4.5),'Existing text retains readable median contrast');report.textContrast.push({width,height,rows});
    }
   }
   await b.run(`(()=>{const viewport=nodes.ArchiveV10GridHost.el.getBoundingClientRect(),card=nodes.ArchiveGrid.Children().find(row=>row.visible&&row.BHasClass('ArchiveCard')&&row.el.getBoundingClientRect().y>=viewport.y&&row.el.getBoundingClientRect().bottom<=viewport.bottom);if(!card)throw Error('No fully visible row');card.events.onmouseover();syncLayout();return true;})()`);await sleep(250);
   const hover=await b.run('('+inspect.toString()+')()');check(hover,width,height);assert(hover.tooltip?.visible,'Bottom retained row opens its tooltip');
   assert(hover.tooltip.position.x>=0&&hover.tooltip.position.y>=0&&hover.tooltip.position.right<=width+1&&hover.tooltip.position.bottom<=height+1,'Tooltip fits viewport');
   await b.shot(captures+'/'+width+'x'+height+'_bottom_tooltip.png',width,height);
   await b.run(`(()=>{previewFixturePages.commerce_goods=PREVIEW_FIXTURE.commerce.paid.products.slice(0,14).map((row,i)=>({id:row.sku,resource_id:row.sku,name:row.title,description:row.description,icon:row.icon,icon_type:'image',count:i%2,count_known:1,target:1,owned:i%2,unlocked:i%2}));return true;})()`);
   await b.run('previewSelect("commerce_goods")');const goods=await b.run('('+inspect.toString()+')()');check(goods,width,height);assert(goods.cards.length>0);
   await b.shot(captures+'/'+width+'x'+height+'_commerce_goods.png',width,height);report.screens.push({width,height,category:'commerce_goods',rows:goods.cards.length,clipping:true});
  }
  report.changedSinceSnapshot=assembly.sourceGraph.filter(item=>/^(scripts\/custom_game\/archive_(v10|parchment_data)\.js|styles\/custom_game\/archive_v10\.css|layout\/custom_game\/archive\.xml)$/.test(item.path)).filter(item=>sourceHash('panorama/src/'+item.path)!==item.sha256).map(item=>item.path);
  assert.deepEqual(report.changedSinceSnapshot,[],'Production layout sources stay frozen');verifyFiles(plan);report.status='PASS';
 }catch(error){report.status='FAIL';report.failure=error.stack||String(error);try{report.failureSnapshot=await b.run('('+inspect.toString()+')()');await b.shot(captures+'/failure.png',1920,1080);}catch{}throw error;}
 finally{fs.writeFileSync(out+'/preview_report.json',JSON.stringify(report,null,2));b.close();}
 console.log('ARCHIVE_ORIGINAL_GW2_SKIN_PREVIEW_PASS '+out+'/preview_report.json');
}
let settled=false;process.on('beforeExit',()=>{if(!settled){console.error('ARCHIVE_ORIGINAL_GW2_SKIN_PREVIEW_INCOMPLETE');process.exitCode=1;}});
main().then(()=>{settled=true;},error=>{settled=true;console.error(error.stack||error);process.exitCode=1;});
