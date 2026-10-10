'use strict';
// Read-only local browser validation of production archive components.
const fs=require('fs'),path=require('path'),assert=require('assert'),crypto=require('crypto');
const {browser}=require('../shop_ui_12h/cdp.cjs');
const args=process.argv.slice(2),arg=(key,fallback)=>{const i=args.indexOf(key);return i<0?fallback:args[i+1];};
const input=arg('--input','design_refs/void_shadow_v1/work/preview/index.html');
const out=arg('--out','design_refs/void_shadow_v1/work/browser_v1');
const sizes=arg('--sizes','1672x941,1600x900,1280x720').split(',').map(x=>x.split('x').map(Number));
const layout=JSON.parse(fs.readFileSync('design_refs/void_shadow_v1/package/layout.json','utf8'));
const assembly=JSON.parse(fs.readFileSync(path.join(path.dirname(input),'assembly.json'),'utf8'));
const digest=crypto.createHash('sha256').update(JSON.stringify(assembly.sourceGraph)).digest('hex');
const forbidden=calls=>calls.filter(x=>/purchase|checkout|draw|claim|promote|upgrade|save/.test(x.name||x.method||''));
const inside=(r,outer,t=1)=>r.x>=outer.x-t&&r.y>=outer.y-t&&r.right<=outer.right+t&&r.bottom<=outer.bottom+t;
function inspect(){
 const shown=e=>!!(e&&!e.hidden&&e.getBoundingClientRect().width&&e.getBoundingClientRect().height&&getComputedStyle(e).display!=='none'&&getComputedStyle(e).visibility!=='hidden');
 const describe=e=>{if(!e)return null;const s=getComputedStyle(e);return {id:e.id,classes:e.className,text:e.textContent,src:e.src||null,visible:shown(e),bounds:e.getBoundingClientRect().toJSON(),font:s.fontFamily,fontSize:s.fontSize,fontWeight:s.fontWeight,overflow:s.overflow,objectFit:s.objectFit,display:s.display,opacity:s.opacity,transform:s.transform,inline:e.style.cssText,decoded:e.tagName==='IMG'?e.complete&&e.naturalWidth>0:null};};
 const grid=nodes.VoidShadowGrid||nodes.ArchiveGrid;
 const cards=grid.Children().filter(card=>(card.BHasClass('VoidShadowItem')||card.BHasClass('ArchiveCard'))&&shown(card.el)).map(card=>{
  const descendants=[...card.el.querySelectorAll('*')].filter(shown),icon=descendants.find(e=>e.tagName==='IMG'&&/virtual_\d+/.test(e.src||'')),plate=descendants.find(e=>e.tagName==='IMG'&&/quantity_plate/.test(e.src||''));
  const labels=descendants.filter(e=>e.classList.contains('label')).map(describe);
  return {...describe(card.el),unlocked:card.__archiveUnlocked,itemId:(card.__voidItem&&card.__voidItem.id)||(card.__archiveItem&&card.__archiveItem.id)||card.id.replace(/^VoidShadowItem_/,''),icon:describe(icon),plate:describe(plate),labels,allVisibleImages:descendants.filter(e=>e.tagName==='IMG').map(describe)};
 });
 return {state:previewState,errors:previewErrors,scripts:previewScriptResults,calls:previewCalls,window:describe((nodes.ArchiveVoidCanvas||nodes.ArchiveWindow).el),grid:describe(grid.el),cards,title:describe((nodes.VoidShadowTitle||nodes.ArchivePageTitle).el),wallet:['gold_text','purple_gem_text','ticket_text'].map(id=>describe(nodes['VoidShadow_'+id]&&nodes['VoidShadow_'+id].el)),filters:['all','unlocked','locked'].map(x=>describe((nodes['VoidShadowFilter_'+x]||nodes['ArchiveFilter_'+x]).el)),tooltip:describe(nodes.ArchiveTooltip.el),tooltipName:describe(nodes.ArchiveTooltipName.el),tooltipEffect:describe(nodes.ArchiveTooltipEffect.el),models:window.previewGeometryModels};
}
function expectedCount(row){const value=row.count,known=row.count_known!==0&&value!==null&&value!==undefined&&value!==''&&value!=='—'&&Number.isFinite(Number(value));const cap=Number(row.max_owned===undefined?row.target:row.max_owned);return (known?String(value):'—')+(Number.isFinite(cap)&&cap>0?'/'+cap:'');}
async function evaluate(b){await b.run('syncLayout();true');return b.run('('+inspect.toString()+')()');}
async function frame(b,prefix,width,height){const info=await evaluate(b);await b.shot(prefix+'.png',{x:0,y:0,width,height});fs.writeFileSync(prefix+'.json',JSON.stringify(info,null,2));return info;}
function checkNormal(info,width,height){
 assert.equal(info.errors.length,0,'Production script/adapter errors');assert.equal(forbidden(info.calls).length,0,'Preview sent a transaction');
 assert.equal(info.cards.length,23,'The first edition must display 23 configured items');
 assert(info.cards.every(c=>c.icon&&c.plate&&c.icon.decoded&&c.plate.decoded),'Package icon/quantity plate must decode for every visible cell');
 assert(info.cards.every(c=>c.labels.length===2),'Each cell has exactly independent quantity/name labels');
 assert.deepEqual(info.wallet.map(x=>x.text),['20','320','2881'],'Resource text must read the original wallet interface after its actual catalog event');
 const rowYs=[...new Set(info.cards.map(c=>Math.round(c.icon.bounds.y)))];assert.deepEqual(rowYs.map(y=>info.cards.filter(c=>Math.round(c.icon.bounds.y)===y).length),[8,8,7],'Expected 8+8+7');
 const scale=Math.min(width/1672,height/941),ox=(width-1672*scale)/2,oy=(height-941*scale)/2;
 for(let i=0;i<23;i++){
  const card=info.cards[i],slot=layout.items[i],asset=layout.assets[slot.icon_asset],r=card.icon.bounds;
  assert(Math.abs(r.x-(ox+slot.icon_bbox[0]*scale))<1.6&&Math.abs(r.y-(oy+slot.icon_bbox[1]*scale))<1.6,'Icon position must follow uniformly scaled source canvas at item '+i);
  assert(Math.abs(r.width/r.height-asset.size[0]/asset.size[1])<.025,'Icon original aspect ratio lost');
  const hole=asset.occluded_local_bbox,occlusion={x:r.x+hole[0]*scale,y:r.y+hole[1]*scale,right:r.x+hole[2]*scale,bottom:r.y+hole[3]*scale};
  assert(inside(occlusion,card.plate.bounds,.6),'Quantity plate exposes original missing pixels at item '+i);
  assert(Math.abs(card.plate.bounds.right-(ox+slot.quantity_bbox[2]*scale))<1.6,'Quantity right anchor drifted at item '+i);
  assert(inside(card.plate.bounds,{x:0,y:0,right:width,bottom:height}),'Quantity board exceeds viewport');
 }
}
function checkFilteredIcons(info){
 for(const card of info.cards){
  const number=Number(card.itemId.replace(/^shadow_/,'')),slot=layout.items[number-1];if(!slot)continue;
  assert(card.icon&&card.icon.src.includes('/'+slot.icon_asset+'.png'),'Filtering changed the icon identity of '+card.itemId);
  const asset=layout.assets[slot.icon_asset],r=card.icon.bounds,hole=asset.occluded_local_bbox,sx=r.width/asset.size[0],sy=r.height/asset.size[1],occlusion={x:r.x+hole[0]*sx,y:r.y+hole[1]*sy,right:r.x+hole[2]*sx,bottom:r.y+hole[3]*sy};
  assert(card.plate&&inside(occlusion,card.plate.bounds,.7),'Filtering exposed missing source pixels on '+card.itemId);
 }
}
let reportWritten=false;
process.on('beforeExit',()=>{if(!reportWritten){console.error('VOID_SHADOW_CAPTURE_INCOMPLETE: no new report');process.exitCode=1;}});
(async()=>{
 fs.mkdirSync(out,{recursive:true});const b=await browser(),cases=[];
 try{
  for(const [width,height]of sizes){
   await b.call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});await b.go(input,'?state=normal');assert.equal(await b.run('previewReady'),true);
   const prefix=out+'/'+width+'x'+height,normal=await frame(b,prefix+'_shadow_normal',width,height);checkNormal(normal,width,height);
   const rows=await b.run('previewFixtureRows');for(let i=0;i<rows.length;i++)assert(normal.cards[i].labels.some(l=>l.text===expectedCount(rows[i])),'Quantity text must retain configured cap and explicit unknown at '+i);
   const source=normal.cards[0].icon.bounds;await b.call('Input.dispatchMouseEvent',{type:'mouseMoved',x:source.x+source.width/2,y:source.y+source.height/2});await b.run('new Promise(r=>setTimeout(r,120)).then(()=>true)');
   const hover=await frame(b,prefix+'_shadow_tooltip',width,height);assert(hover.tooltip.visible&&hover.tooltipName.text===rows[0].name,'Original tooltip must receive real row name');assert(hover.tooltipEffect.text.includes(rows[0].description),'Original tooltip must receive configured effect');assert.equal(forbidden(hover.calls).length,0);
   cases.push({width,height,normal,hover});console.log('VOID_SHADOW_CAPTURE '+width+'x'+height);
  }
  await b.call('Emulation.setDeviceMetricsOverride',{width:1672,height:941,deviceScaleFactor:1,mobile:false});await b.go(input,'?state=edges');assert.equal(await b.run('previewReady'),true);
  const edges=await frame(b,out+'/1672x941_shadow_edges',1672,941),rows=await b.run('previewFixtureRows');checkNormal(edges,1672,941);
  for(let i=0;i<rows.length;i++)assert(edges.cards[i].labels.some(l=>l.text===expectedCount(rows[i])),'Edge count differs at '+i);
  assert(edges.cards.every(c=>c.labels.find(l=>l.classes.includes('VoidShadowName')).overflow==='hidden'),'Name clipping must be production-owned');
  const shrinkWidths=await b.run(`(()=>{const measure=document.createElement('canvas').getContext('2d');return [...document.querySelectorAll('.VoidShadowCount')].map(e=>{const s=getComputedStyle(e);measure.font=s.fontStyle+' '+s.fontWeight+' '+s.fontSize+' '+s.fontFamily;return {text:e.textContent,textWidth:measure.measureText(e.textContent).width,available:e.clientWidth,fontSize:s.fontSize};});})()`);assert(shrinkWidths.every(x=>x.textWidth<=x.available+1),'Native shrink preview model still lets quantity text overflow its board');
  const longSource=edges.cards[6].icon.bounds;await b.call('Input.dispatchMouseEvent',{type:'mouseMoved',x:longSource.x+longSource.width/2,y:longSource.y+longSource.height/2});await b.run('new Promise(r=>setTimeout(r,90)).then(()=>true)');const longTooltip=await frame(b,out+'/1672x941_shadow_long_tooltip',1672,941);assert.equal(longTooltip.tooltipName.text,rows[6].name,'Tooltip must retain full configured/stress name after grid ellipsis');
  const expectedOwned=rows.filter(r=>r.count_known!==0&&r.count!==null&&r.count!==undefined&&r.count!==''&&Number.isFinite(Number(r.count))&&Number(r.count)>0).length,expectedZero=rows.filter(r=>r.count_known!==0&&r.count!==null&&r.count!==undefined&&r.count!==''&&Number.isFinite(Number(r.count))&&Number(r.count)===0).length;
  const point=async(mode)=>{const f=edges.filters.find(f=>f.id.endsWith('_'+mode)),r=f.bounds;await b.call('Input.dispatchMouseEvent',{type:'mousePressed',button:'left',clickCount:1,x:r.x+r.width/2,y:r.y+r.height/2});await b.call('Input.dispatchMouseEvent',{type:'mouseReleased',button:'left',clickCount:1,x:r.x+r.width/2,y:r.y+r.height/2});await b.run('new Promise(r=>setTimeout(r,70)).then(()=>true)');return evaluate(b);};
  const owned=await point('unlocked');assert.equal(owned.cards.length,expectedOwned,'Owned filter must use known positive count even when unlocked flag disagrees');checkFilteredIcons(owned);await b.shot(out+'/1672x941_shadow_owned.png',{x:0,y:0,width:1672,height:941});
  const locked=await point('locked');assert.equal(locked.cards.length,expectedZero,'Unowned filter must include only known zero, exclude null/dash/missing');checkFilteredIcons(locked);await b.shot(out+'/1672x941_shadow_zero.png',{x:0,y:0,width:1672,height:941});
  const all=await point('all');assert.equal(all.cards.length,23,'All filter must retain unknown rows');
  await b.go(input,'?state=extra');assert.equal(await b.run('previewReady'),true);const extra=await evaluate(b);assert.equal(extra.cards.length,24,'23 must not become category capacity');
  const profiles=[];
  for(const state of ['loading','sparse','empty']){
   await b.go(input,'?state='+state);assert.equal(await b.run('previewReady'),true);
   const info=await frame(b,out+'/1672x941_shadow_'+state,1672,941),actual=await b.run('cfg.SurvivalArchiveVoidV1.Rows().map(r=>({id:r.id,count:r.count===undefined?null:r.count,countKnown:r.count_known,quantity:cfg.SurvivalArchiveVoidV1.Quantity(r)}))');
   assert.equal(info.cards.length,23,'Local '+state+' must preserve configured23 slots');assert.equal(info.errors.length,0);assert.equal(forbidden(info.calls).length,0);
   if(state==='loading')assert(actual.every(r=>r.countKnown===0&&r.quantity.startsWith('—')),'Unsynchronized archive cannot imply zero ownership');
   if(state==='sparse'){assert(actual[0].count>0);assert(actual.slice(1).every(r=>r.countKnown===1&&r.count===0),'Missing items in a successful complete snapshot are known zero');}
   if(state==='empty')assert(actual.every(r=>r.countKnown===1&&r.count===0),'Successful empty inventory is23 known zeros, not unknown');
   profiles.push({state,actual,info});
  }
  await b.go(input,'?state=normal');assert.equal(await b.run('previewReady'),true);
  await b.run(`cfg.SurvivalCommerceWallet.GetCatalog().balances.u_coin=99;emit('survival_commerce_result',{ok:true,action:'purchase',currency:'u_coin',balance:99,request_id:'LOCAL_BROWSER_EVENT_ONLY'});true`);
  await b.run('new Promise(r=>setTimeout(r,120)).then(()=>true)');const walletUpdate=await evaluate(b);assert.equal(walletUpdate.wallet[0].text,'99','Actual wallet result event must update resource text without another archive snapshot');assert.equal(forbidden(walletUpdate.calls).length,0,'Local result fixture must not issue a real purchase request');
  await b.go(input,'?state=chunked');assert.equal(await b.run('previewReady'),true);
  const chunkBefore=await b.run('cfg.SurvivalArchiveVoidV1.Rows().map(r=>r.count_known)');assert(chunkBefore.every(x=>x===0));
  await b.run(`emit('survival_archive_snapshot',{ok:1,sequence:200,chunk:1,chunks:2,category_id:'shadow',categories:PREVIEW_FIXTURE.archiveCats,rows:previewFixtureRows.slice(0,12),pending:0});syncLayout();true`);
  const chunkPartial=await b.run('cfg.SurvivalArchiveVoidV1.Rows().map(r=>r.count_known)');assert(chunkPartial.every(x=>x===0),'First partial packet must not generate false zeros before assembly completes');
  await b.run(`emit('survival_archive_snapshot',{ok:1,sequence:200,chunk:2,chunks:2,category_id:'shadow',categories:PREVIEW_FIXTURE.archiveCats,rows:previewFixtureRows.slice(12),pending:0});syncLayout();true`);
  const chunkDone=await b.run('cfg.SurvivalArchiveVoidV1.Rows().map(r=>({id:r.id,count:r.count===undefined?null:r.count,countKnown:r.count_known}))');assert.equal(chunkDone.length,23);assert(chunkDone[0].count>0);assert.equal(chunkDone[8].countKnown,0);
  const restored=await b.run(`(async()=>{cfg.SurvivalArchive.SelectCategory('clear');syncLayout();await new Promise(r=>setTimeout(r,300));syncLayout();const e=nodes.ArchiveWindow.el,s=getComputedStyle(e);return {className:e.className,width:s.width,height:s.height,canvasVisible:!nodes.ArchiveVoidCanvas.el.hidden,archiveOpen:cfg.SurvivalArchive.IsOpen()};})()`);
  assert(!restored.className.includes('ArchiveVoidPage')&&!restored.canvasVisible&&restored.archiveOpen,'Switching away must restore the original open archive');assert.equal(restored.width,'1280px');assert.equal(restored.height,'800px');
  const result={at:new Date().toISOString(),status:'PASS_BROWSER_VOID_SHADOW_V1',kind:'production_component_browser_preview',sourceDigest:digest,assembly,cases,edges,shrinkWidths,longTooltip,filters:{expectedOwned,expectedZero,owned,locked,all},capacity:{visible24:extra.cards.length},profiles,walletUpdate,chunks:{before:chunkBefore,partial:chunkPartial,complete:chunkDone},restored,limitations:['Chrome DOM is a Panorama API/layout approximation; native rendering requires separate game acceptance.','Quantity shrink is a scoped canvas text measurement emulation of production text-overflow:shrink, not a native font-pixel claim.','Names, limits and effects come from real CSV; quantities are explicit local fixtures, never written to a real archive.','Browser background is decorative local display; game uses live scene.','No server, purchase, draw, save, account or payment endpoint is called.']};
  fs.writeFileSync(out+'/report.json',JSON.stringify(result,null,2));reportWritten=true;console.log('VOID_SHADOW_BROWSER_PASS '+out+'/report.json');
 }finally{b.close();}
})().catch(error=>{console.error(error.stack||error);process.exitCode=1;});
