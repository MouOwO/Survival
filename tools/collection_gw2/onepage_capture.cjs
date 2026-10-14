'use strict';
// Targeted proof for the 900x478 ten-column layout. Earlier compact assertions
// remain historical; no production source, save, or live game is changed here.
const fs=require('fs'),path=require('path'),crypto=require('crypto'),assert=require('node:assert/strict');
const {browser,sleep}=require('../shop_ui_12h/cdp.cjs');
const {inspect,validateNavigation,auditSources}=require('./entry_capture.cjs');
const {validateOnePage,shot}=require('./acceptance.cjs');
const {probeOpaque,decodePng}=require('./opaque_probe.cjs');
const {fixture}=require('./fixture.cjs');
const base='design_refs/collection_gw2_v2/work',preview=base+'/entry_preview',out=base+'/onepage_final',sizes=[[1920,1080],[815,528]],formal=fixture();
const hash=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
async function extra(state){
 const describe=id=>({id,bounds:nodes[id].el.getBoundingClientRect().toJSON()});
 const assets=await Promise.all(Object.entries(cfg.CollectionGW2Data.assets).map(async([key,value])=>{const image=new Image();image.src=cssValue(value.file);try{await image.decode();return {key,src:image.src,decoded:!!image.naturalWidth};}catch{return {key,src:image.src,decoded:false};}}));
 const tabs=['ex','friend','wife'].map(key=>{const tab=nodes['CollectionGW2Tab_'+key],descendants=[...tab.el.querySelectorAll('*')];return {...describe(tab.id),labels:descendants.filter(element=>element.classList.contains('label')).length,icons:descendants.filter(element=>getComputedStyle(element).backgroundImage.includes('/tab_'+key+'.png')).map(element=>element.getBoundingClientRect().toJSON())};});
 const grid=nodes.CollectionGW2Grid.el,portraitParents=nodes.CollectionGW2GridBody.Children().map(card=>{const image=card.el.querySelector('img');return {direct:!!image?.parentElement.classList.contains('CollectionGW2Portrait'),legacyWrapper:!!image?.closest('.ArchiveArt'),className:image?.className};});
 state.onePage={sidebar:describe('CollectionGW2Sidebar'),footer:describe('CollectionGW2Footer'),result:describe('CollectionGW2Result'),draw:describe('CollectionGW2Draw'),tabs,assets,portraitParents,scrollWidth:grid.scrollWidth,clientWidth:grid.clientWidth,category:nodes.CollectionGW2Category.text};
 return state;
}
async function read(b){return b.run('('+extra.toString()+')(('+inspect.toString()+')())');}
async function settle(b){await b.run('syncLayout();document.fonts.ready.then(()=>Promise.all([...document.images].map(image=>image.decode().catch(()=>false)))).then(()=>true)');await sleep(100);}
async function nativeInputHits(b){
 // Panorama hittest=false does not disable children when hittestchildren=true.
 // CSS pointer-events is inherited; the generic harness only repairs buttons.
 // Mirror the two ordinary input targets locally without changing geometry.
 const targets=await b.run('(()=>{return ["CollectionGW2Search","CollectionGW2Grid"].map(id=>{const panel=nodes[id],parents=[];for(let p=panel.GetParent();p;p=p.GetParent())parents.push({id:p.id,children:p.hittestchildren});const before=getComputedStyle(panel.el).pointerEvents;if(!panel.hittest||parents.some(p=>!p.children))throw Error("Native input is actually blocked: "+id);panel.el.style.pointerEvents="auto";return {id,hittest:panel.hittest,before,after:getComputedStyle(panel.el).pointerEvents,parents};});})()');
 return {targets,scope:'Browser input inheritance only; production hittest and all parent hittestchildren are checked before mirroring.'};
}
async function move(b,x,y){await b.call('Input.dispatchMouseEvent',{type:'mouseMoved',x,y});await sleep(100);}
async function click(b,id){
 const point=await b.run('(()=>{const e=nodes['+JSON.stringify(id)+'].el,r=e.getBoundingClientRect(),x=r.x+r.width/2,y=r.y+r.height/2,p=document.elementFromPoint(x,y);return {x,y,hit:!!p&&(p===e||e.contains(p))};})()');
 assert(point.hit,'Actual pointer hits '+id);await move(b,point.x,point.y);
 for(const type of ['mousePressed','mouseReleased'])await b.call('Input.dispatchMouseEvent',{type,x:point.x,y:point.y,button:'left',clickCount:1});await settle(b);return point;
}
function validateArt(state,category){
 assert.deepEqual(state.cards.map(card=>card.item),formal.pages[category].map(item=>item.id),'Formal CSV item order is retained');
 for(let index=0;index<state.cards.length;index++)assert(decodeURI(state.cards[index].image.src).endsWith(formal.pages[category][index].icon.replace('file://{images}/','')),'Original configured portrait URI is retained for '+state.cards[index].item);
 assert.deepEqual(state.collection.rows.map(item=>item.name),formal.pages[category].map(item=>item.name),'All formal character names remain unchanged');
}
async function cropPortrait(b,state,index,name){
 const image=state.cards[index].image,r=image.bounds,clip={x:Math.floor(r.x),y:Math.floor(r.y),width:Math.ceil(r.right)-Math.floor(r.x),height:Math.ceil(r.bottom)-Math.floor(r.y)},file=out+'/'+name;
 await shot(b,file,clip);const decoded=decodePng(fs.readFileSync(file));assert.equal(decoded.width,clip.width);assert.equal(decoded.height,clip.height);
 return {file,item:state.cards[index].item,source:image.src,clip,pixelSize:[decoded.width,decoded.height],method:'CDP screenshot clip at scale 1; no image recreation, resize, sharpening, or pixel editing'};
}
async function hoverCard(b,index,width,height){
 await move(b,2,2);let state=await read(b);const card=state.cards[index],r=card.bounds,x=r.x+r.width/2,y=r.y+r.height/2;
 const hit=await b.run('document.elementFromPoint('+x+','+y+')?.closest(".CollectionGW2Slot")?.id');assert.equal(hit,card.id,'Actual mouse reaches card '+(index+1));
 await move(b,x,y);state=await read(b);assert(state.collection.tooltipVisible,'Card '+(index+1)+' opens its tooltip');assert.equal(state.tooltip.title,state.collection.rows[index].name);
 const c=state.canvas.bounds,t=state.tooltip.bounds,scale=c.width/900;
 assert(t.x>=c.x-.5&&t.y>=c.y-.5&&t.right<=c.x+c.width+.5&&t.bottom<=c.y+c.height+.5,'Tooltip is inside the collection canvas');assert(t.height/scale<=406.5,'Tooltip respects the shorter window cap');
 const surface=await b.run('nodes.CollectionGW2TooltipSurface.el.getBoundingClientRect().toJSON()');
 await move(b,surface.right-2,surface.bottom-2);assert.equal((await read(b)).collection.tooltipVisible,false,'Moving inside the tooltip immediately hides it');
 await sleep(100);assert.equal((await read(b)).collection.tooltipVisible,false,'Tooltip does not immediately reappear over another portrait');await move(b,2,2);
 return {width,height,index:index+1,item:card.item,realPointerHit:true,title:state.tooltip.title,tooltipBounds:t,selfEntryDismissed:true};
}
async function search(b,text){
 await move(b,2,2);await click(b,'CollectionGW2Search');
 await b.call('Input.dispatchKeyEvent',{type:'keyDown',key:'a',code:'KeyA',windowsVirtualKeyCode:65,modifiers:2});await b.call('Input.dispatchKeyEvent',{type:'keyUp',key:'a',code:'KeyA',windowsVirtualKeyCode:65,modifiers:2});
 await b.call('Input.dispatchKeyEvent',{type:'keyDown',key:'Backspace',code:'Backspace',windowsVirtualKeyCode:8});await b.call('Input.dispatchKeyEvent',{type:'keyUp',key:'Backspace',code:'Backspace',windowsVirtualKeyCode:8});
 if(text)await b.call('Input.insertText',{text});await settle(b);return read(b);
}
async function mirrorNativeScrollbar(b){
 const css=fs.readFileSync('panorama/src/styles/custom_game/collection_gw2.css','utf8'),width=Number(css.match(/#CollectionWindow VerticalScrollBar\s*\{\s*width:\s*(\d+)px/)[1]);assert.equal(width,8);
 await b.run('(()=>{const style=document.createElement("style");style.id="OnePageNativeScrollbarMirror";style.textContent="#CollectionGW2Grid::-webkit-scrollbar{width:'+width+'px;height:'+width+'px}#CollectionGW2Grid::-webkit-scrollbar-track{background:#12191d55}#CollectionGW2Grid::-webkit-scrollbar-thumb{background:#718b9660;border-radius:0}";document.head.appendChild(style);return true;})()');
 return {nativeWidth:width,scope:'#CollectionGW2Grid only',reason:'Chrome scrollbar mirrors the explicit production Panorama VerticalScrollBar width; actual layout measurements and cursor geometry are unchanged.'};
}
async function main(){
 fs.mkdirSync(out,{recursive:true});const report={at:new Date().toISOString(),kind:'collection_onepage_40_portraits',notGameCapture:true,outboundStubs:true,assembly:JSON.parse(fs.readFileSync(preview+'/assembly.json','utf8')),screens:[],portraits:[],pointerChecks:[],checks:[],limitations:['Headless browser assembly of frozen production sources with native HUD stand-ins; no claim of a live game screenshot.','Ownership, currencies and responses are isolated fixture values; card IDs, names and portrait image paths are read from the actual CSV.']};
 const b=await browser();try{
  for(const [width,height]of sizes){
   await b.call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});await b.go(preview+'/index.html');assert(await b.run('previewReady'));await settle(b);
   let state=await read(b);validateNavigation(state,width,height);await click(b,'HandoffNav_collection');report.checks.push({width,height,entryActualPointer:true,inputHitCompatibility:await nativeInputHits(b)});
   for(const category of ['ex','friend']){
    await move(b,2,2);await click(b,'CollectionGW2Tab_'+category);await b.run('entrySend('+JSON.stringify(category)+');true');await settle(b);state=await read(b);
    const geometry=validateOnePage(state,width,height);validateArt(state,category);assert.equal(state.collection.category,category);assert.equal(state.layer,'collection');
    await move(b,2,2);const file=out+'/'+category+'_'+width+'x'+height+'.png';await shot(b,file,{x:0,y:0,width,height});report.screens.push({file,category,...geometry,all40Decoded:true,originalUris:true,opaque:true,categoryHeading:state.onePage.category});
    report.portraits.push(await cropPortrait(b,state,0,category+'_portrait_1_'+width+'x'+height+'.png'));report.portraits.push(await cropPortrait(b,state,39,category+'_portrait_40_'+width+'x'+height+'.png'));
    if(width===1920&&category==='ex')report.opacityProof=await probeOpaque(b,out+'/opaque_1920x1080',width,height);
    for(const index of [0,9,30,39])report.pointerChecks.push(await hoverCard(b,index,width,height));
   }
   if(width===1920){
    let filtered=await search(b,formal.pages.friend[0].name);assert.equal(filtered.cards.length,1);assert.equal(filtered.cards[0].item,formal.pages.friend[0].id);assert.equal(filtered.emptySlots,0);
    filtered=await search(b,'本地不存在的收藏检索词');assert.equal(filtered.cards.length,0);assert(filtered.empty.visible);assert.equal(filtered.emptySlots,0);
    filtered=await search(b,'');validateOnePage(filtered,width,height);report.checks.push({width,height,search:'Real pointer focus and CDP keyboard input match one item, empty result, and restore forty',noFillerSlots:true});
   }
   const before=await b.run('previewCalls.length');await click(b,'CollectionGW2Tab_wife');state=await read(b);assert.equal(state.collection.category,'wife');assert.equal(state.cards.length,0);assert.equal(state.collection.slots,0);assert.equal(state.emptySlots,0);assert.equal(state.collection.drawEnabled,false);assert.equal(state.calls.slice(before).filter(call=>call.name==='survival_archive_request').length,0);
   await shot(b,out+'/wife_'+width+'x'+height+'.png',{x:0,y:0,width,height});report.checks.push({width,height,wifeEmpty:true,drawDisabled:true,wifeRequests:0});
   if(width===1920){
    await click(b,'CollectionGW2Tab_ex');report.scrollbarMirror=await mirrorNativeScrollbar(b);
    await b.run('(()=>{const snapshot=entrySnapshot("ex"),original=snapshot.rows;snapshot.rows=Array.from({length:113},(_,index)=>({...original[index%original.length],id:"onepage_overflow_"+index,name:"本地扩容样例 "+(index+1),icon_type:"image"}));emit("survival_archive_snapshot",snapshot);syncLayout();return true;})()');await settle(b);state=await read(b);validateOnePage(state,width,height,113);
    const grid=state.grid.bounds,scale=state.canvas.bounds.width/900;await move(b,grid.x+80*scale,grid.y+20*scale);await b.call('Input.dispatchMouseEvent',{type:'mouseWheel',x:grid.x+80*scale,y:grid.y+20*scale,deltaX:0,deltaY:12000});await sleep(180);state=await read(b);const last=state.cards[112].bounds;
    assert(state.scroll.top>0);assert(last.y>=grid.y-1&&last.bottom<=grid.y+grid.height+1,'The 113th fixture item remains reachable after a real wheel scroll');report.pointerChecks.push(await hoverCard(b,112,width,height));
    await shot(b,out+'/overflow_113_'+width+'x'+height+'.png',{x:0,y:0,width,height});report.checks.push({width,height,overflowFixtureItems:113,lastItemReachable:true,scroll:state.scroll,fixtureNote:'Synthetic unique IDs reuse the forty configured portrait URIs only to exercise overflow; these are not new game rewards.'});
   }
   state=await read(b);assert(!state.calls.some(call=>/draw|claim|purchase|checkout/.test(call.name)),'No transaction is sent, even to the in-memory stub');await click(b,'CollectionGW2Close');state=await read(b);assert(!state.collection.open);assert.equal(state.layer,null);report.checks.push({width,height,imageCloseActualPointer:true});
  }
  auditSources(report);assert.deepEqual(report.sourceChanged,[],'All assembled working sources remain frozen');assert.equal(hash(fs.readFileSync(report.assembly.readOnlyUserSource.path)),report.assembly.readOnlyUserSource.sha256);
  report.assetChanged=report.assembly.assets.filter(row=>hash(fs.readFileSync(row.path))!==row.sha256).map(row=>row.path);assert.deepEqual(report.assetChanged,[]);report.harnessSha256=hash(fs.readFileSync(__filename));report.status='PASS_COLLECTION_ONEPAGE_40';
 }catch(error){report.status='FAIL_COLLECTION_ONEPAGE_40';report.failure=error.stack||String(error);try{report.failureSnapshot=await read(b);await b.shot(out+'/failure.png');}catch{}throw error;}
 finally{fs.writeFileSync(out+'/report.json',JSON.stringify(report,null,2));b.close();}
 console.log('COLLECTION_ONEPAGE_CAPTURE_PASS '+out+'/report.json');
}
if(require.main===module)main().catch(error=>{console.error(error.stack||error);process.exitCode=1;});
module.exports={extra,validateArt};
