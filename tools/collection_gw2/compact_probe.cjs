'use strict';
const assert=require('node:assert/strict'),{sleep}=require('../shop_ui_12h/cdp.cjs');
const baseline=require('./compact_baseline.json');
function compactGeometry(state,width,height){
 const old=baseline.viewports.find(row=>row.width===width&&row.height===height);assert(old,'Previous same-viewport screenshot measurement exists');
 const areaRatio=state.canvas.bounds.width*state.canvas.bounds.height/(old.canvas.width*old.canvas.height);assert(areaRatio>.32&&areaRatio<.35,'Window occupies about one third of the previous window area');
 assert.equal(state.collection.slots,state.collection.rows.length);assert.equal(state.emptySlots,0);assert.equal(state.cards.length,state.collection.rows.length);
 const first=state.cards[0];if(first){assert.equal(state.cards.filter(card=>Math.abs(card.bounds.y-first.bounds.y)<1).length,6,'Six larger portraits fit in each row');assert(state.scroll.height>state.scroll.clientHeight,'Forty actual cards have scrollable overflow');}
 let portraitComparison=null;if(width===1920&&height===1080&&first){const before=baseline.portrait1920.width,after=first.image.bounds.width;assert(after>before*1.35,'Portraits are larger on screen despite the smaller window');portraitComparison={baseline:'tools/collection_gw2/compact_baseline.json',before,after,ratio:after/before};}
 return {width,height,oldCanvas:old.canvas,newCanvas:state.canvas.bounds,areaRatio,portraitComparison,actualCards:state.cards.length,emptySlots:state.emptySlots};
}
async function wheel(b,x,y,deltaY){await b.call('Input.dispatchMouseEvent',{type:'mouseMoved',x,y});await b.call('Input.dispatchMouseEvent',{type:'mouseWheel',x,y,deltaX:0,deltaY});await sleep(180);await b.run('syncLayout();true');}
async function scrollAndInspect(b,read,screenshot){
 let state=await read(),grid=state.grid.bounds;const first=state.cards[0].bounds,x=first.x+first.width/2,y=first.y+first.height/2,ids=state.cards.map(card=>card.id),beforeCalls=state.calls.length;
 assert.equal(ids.length,40);const wanted=ids[39];
 for(let attempt=0;attempt<12;attempt++){await wheel(b,x,y,650);state=await read();if(state.scroll.top+state.scroll.clientHeight>=state.scroll.height-2)break;}
 assert(state.scroll.top>0,'Actual wheel changes scroll position');assert(state.scroll.top+state.scroll.clientHeight>=state.scroll.height-2,'Actual wheel reaches the final row');assert.deepEqual(state.cards.map(card=>card.id),ids,'Scrolling preserves formal order and all actual cards');
 const card=state.cards[39],bounds=card.bounds;assert(bounds.y>=grid.y-1&&bounds.y+bounds.height<=grid.y+grid.height+1,'The fortieth card is fully visible');assert(state.cards[0].bounds.y+state.cards[0].bounds.height<=grid.y,'First row has scrolled out of view');
 const cx=bounds.x+bounds.width/2,cy=bounds.y+bounds.height/2;await b.call('Input.dispatchMouseEvent',{type:'mouseMoved',x:state.canvas.bounds.x-12,y:state.canvas.bounds.y});await sleep(220);assert.equal(await b.run('(()=>{const p=document.elementFromPoint('+cx+','+cy+');return p&&p.closest(".CollectionGW2Slot")?.id;})()'),wanted,'Fortieth card receives pointer hits after leaving the previous card tooltip');
 await screenshot('scroll_last_1920x1080.png');await b.call('Input.dispatchMouseEvent',{type:'mouseMoved',x:cx,y:cy});await sleep(240);state=await read();assert(state.collection.tooltipVisible);assert.equal(state.tooltip.title,state.collection.rows[39].name);assert(state.tooltip.frontmost,'Tooltip paints over the scrolled inventory');const tip=state.tooltip.bounds,canvas=state.canvas.bounds;assert(tip.x>=canvas.x-.5&&tip.y>=canvas.y-.5&&tip.x+tip.width<=canvas.x+canvas.width+.5&&tip.y+tip.height<=canvas.y+canvas.height+.5,'Tooltip stays inside the smaller window');await screenshot('scroll_tooltip_1920x1080.png');
 const atBottom=state.scroll.top;await wheel(b,cx,cy,-20);state=await read();assert(state.scroll.top<atBottom,'The small wheel step actually moves the hovered card');assert(!state.collection.tooltipVisible,'Moving the same card under a stationary pointer hides its stale tooltip');assert(!state.calls.slice(beforeCalls).some(call=>/draw|claim|purchase/.test(call.name)));return {lastId:wanted,scrollTop:state.scroll.top,formalItems:ids.length,tooltipName:state.collection.rows[39].name,scrollHidesTooltip:true,actualMouseWheel:true};
}
async function searchAndEmpty(b,read){
 const before=await read(),name=before.collection.rows[0].name,calls=before.calls.length;
 async function search(value){await b.run('nodes.CollectionGW2Search.el.value='+JSON.stringify(value)+';nodes.CollectionGW2Search.el.dispatchEvent(new Event("input",{bubbles:true}));syncLayout();true');await sleep(100);return read();}
 const one=await search(name);assert.equal(one.collection.rows.length,1);assert.equal(one.collection.slots,1);assert.equal(one.emptySlots,0);assert.equal(one.scroll.top,0);
 const zero=await search('不存在的收藏本地边界');assert.equal(zero.collection.rows.length,0);assert.equal(zero.collection.slots,0);assert.equal(zero.cards.length,0);assert.equal(zero.emptySlots,0);assert(zero.empty.text.includes('没有找到'));
 const reset=await search('');assert.equal(reset.collection.rows.length,40);assert.equal(reset.collection.slots,40);assert(!reset.calls.slice(calls).some(call=>/archive_request|draw/.test(call.name)),'Local search sends no pool request or draw');return {one:one.collection.slots,none:zero.collection.slots,reset:reset.collection.slots,emptyPlaceholders:0};
}
module.exports={compactGeometry,scrollAndInspect,searchAndEmpty};
