const assert=require('node:assert/strict');
const {createHarness}=require('./fixtures/menus_v10_harness.cjs');
const h=createHarness(),{cfg,nodes}=h;
cfg.ArchiveHandoff={Icon(parent,item,category){if(category!=='wife')throw new Error('Formal social portraits must resolve through the CSV icon catalog');
 // Synthetic ownership rows reuse our portrait when testing without a rebuilt wife catalogue.
 const portrait=new h.root.constructor('Image',parent);portrait.SetImage('s2r://panorama/images/custom_game/archive_gpu_regular/head_v5_ex_01.vtex');
},Init(){},Observe(){},CardProgress:item=>String(item.count)+'/'+String(item.target)};
h.load('ui_snapshot_cache.js');h.load('icons_remaining_5d5c1152eb.js');h.load('archive_parchment_data.js');h.load('archive_v10_semantics.js');h.load('common/archive_tooltip.js');h.load('collection_gw2_data.js');h.load('collection_gw2.js');
const rows=Array.from({length:40},(_,i)=>({id:'ex_'+String(i+1).padStart(2,'0'),name:i?'正式收藏'+i:'胡桃',count:i===0?2:0,target:60,description:'真实奖励效果'+i}));
const friendRows=rows.map((r,i)=>({...r,id:'friend_'+String(i+1).padStart(2,'0'),name:i?'正式好友'+i:'哆啦A梦'}));
const wifeRows=rows.map((r,i)=>({...r,id:'wife_'+String(i+1).padStart(2,'0'),name:'老婆收藏样例'+(i+1)}));
function packet(category,sequence,items,extra={}){return {ok:1,category_id:category,sequence,chunk:1,chunks:1,rows:items,social:{tickets:3,currency_name:category==='ex'?'邀请函':category==='wife'?'姻缘签':'义帖',draw_cost:1,remaining:999,total:2},pending:0,...extra};}
function emit(data){h.emit('survival_archive_snapshot',data);}
function snapshot(category,sequence,items,extra){emit(packet(category,sequence,items,extra));}
function ack(pending,extra){h.emit('survival_archive_social_result',{pool_id:pending.pool_id,request_id:pending.request_id,ok:false,terminal:true,pending:false,...extra});}
function draws(){return h.sent.filter(r=>r.name==='survival_archive_social_draw');}
function images(node){return (node.paneltype==='Image'?[node]:[]).concat(node.Children().flatMap(images));}
let api=cfg.SurvivalCollection;
assert.equal(nodes.CollectionScrim.style.backgroundColor,'#00000022','The flat inventory overrides the generic modal dark scrim after adoption');
assert.equal(nodes.CollectionGW2Background.style.opacity,'1','The collection texture is not faded');assert.equal(nodes.CollectionGW2Background.style.backgroundColor,'#111413','Opaque black and gold backing covers the source texture alpha');assert.equal(nodes.CollectionWindow.style.backgroundColor,'#111413');
assert.equal(nodes.CollectionGW2CloseIcon.paneltype,'Image');assert(!nodes.CollectionGW2Close.Children().some(child=>child.paneltype==='Label'),'Close uses the fixed image instead of a font glyph');
assert.equal(nodes.CollectionGW2Sidebar.style.backgroundColor,nodes.CollectionGW2Header.style.backgroundColor,'Header and sidebar share one flat tint');
function bounds(node){const [x,y]=node.style.position.split(' ').map(parseFloat);return {x,y,right:x+parseFloat(node.style.width),bottom:y+parseFloat(node.style.height)};}
assert.deepEqual(Array.from(api.Inspect().canvas),[960,548],'One-page canvas matches the refined black and gold presentation');
assert.equal(parseFloat(nodes.CollectionGW2Header.style.height),52,'The title band gives the fixed corner artwork enough clearance');
assert.equal(parseFloat(nodes.CollectionGW2Title.style.fontSize),22,'The title keeps its refined readable size');
assert(bounds(nodes.CollectionGW2Title).bottom<=bounds(nodes.CollectionGW2Header).bottom,'The smaller title is contained in its band');
assert.equal(bounds(nodes.CollectionGW2Header).bottom,bounds(nodes.CollectionGW2Sidebar).y,'The left rail joins the header without a gap');
assert.equal(bounds(nodes.CollectionGW2Sidebar).bottom,bounds(nodes.CollectionGW2Footer).y,'The left rail joins the full-width footer');
function descendants(node){return node.Children().flatMap(child=>[child,...descendants(child)]);}
function assertNine(node,key,edge,fill){
 assert(node&&node.__collectionNine,'A native border is assembled from real cropped panels');
 const nine=node.__collectionNine,pieces=nine.pieces;
 assert.equal(nine.key,key);assert.equal(pieces.length,9,'Nine cropped regions retain independent geometry');
 assert(pieces.every(piece=>piece.paneltype==='Panel'&&!piece.hittest&&!piece.hittestchildren),'Border pieces never steal card or button input');
 const [left,top,right,bottom]=edge;
 assert.equal(parseFloat(pieces[0].style.width),left);assert.equal(parseFloat(pieces[0].style.height),top);
 assert.equal(parseFloat(pieces[2].style.width),right);assert.equal(parseFloat(pieces[2].style.height),top);
 assert.equal(parseFloat(pieces[6].style.width),left);assert.equal(parseFloat(pieces[6].style.height),bottom);
 assert.equal(parseFloat(pieces[8].style.width),right);assert.equal(parseFloat(pieces[8].style.height),bottom);
 if(fill)assert.notEqual(pieces[4].style.backgroundImage,'none','The primary button retains its native gold center');
 else assert.equal(pieces[4].style.backgroundImage,'none','Open border centers do not obscure portraits or the collection backdrop');
 assert.equal(pieces[4].style.backgroundColor,'transparent');
}
assertNine(descendants(nodes.CollectionGW2Canvas).find(node=>node.BHasClass('CollectionGoldWindowFrame')),'frame',[10,10,10,10],false);
assert.equal(parseFloat(nodes.CollectionGW2Draw.style.width),176);assert.equal(parseFloat(nodes.CollectionGW2Draw.style.height),40);
assertNine(descendants(nodes.CollectionGW2Draw).find(node=>node.BHasClass('CollectionGoldPrimary')),'button',[8,6,8,6],true);
function assertOnePage(category){
 const cards=nodes.CollectionGW2GridBody.Children(),grid=nodes.CollectionGW2Grid,body=nodes.CollectionGW2GridBody;
 assert.equal(cards.length,40,category+' renders all forty actual entries');
 assert.equal(api.Inspect().columns,10);assert.equal(api.Inspect().portraitSize,76);
 assert.equal(new Set(cards.map(card=>bounds(card).x)).size,10,'All ten columns are populated');
 assert.equal(new Set(cards.map(card=>bounds(card).y)).size,4,'The forty entries occupy exactly four rows');
 assert.equal(parseFloat(grid.style.width),834,'Forty items do not reserve a needless scrollbar gutter');
 assert.equal(parseFloat(grid.style.height),330);assert.equal(parseFloat(body.style.width),834);
 assert(parseFloat(body.style.height)<=parseFloat(grid.style.height),'The full catalogue fits without vertical scrolling');
 assert(bounds(grid).bottom<=bounds(nodes.CollectionGW2Footer).y,'The fourth row ends before the action footer');
 cards.forEach((card,index)=>{
  const b=bounds(card);assert(card.__collectionItem.id.startsWith(category+'_'),'Only the selected formal pool is shown');
  assert.equal(parseFloat(card.style.width),78);assert.equal(parseFloat(card.style.height),78);
  assert(b.x>=0&&b.y>=0&&b.right<=parseFloat(grid.style.width)&&b.bottom<=parseFloat(grid.style.height),'Card '+index+' is entirely inside the visible grid');
  const portraits=images(card);assert.equal(portraits.length,1,'One formal portrait per real item');
  assert.equal(parseFloat(portraits[0].style.width),76);assert.equal(parseFloat(portraits[0].style.height),76);
  assertNine(descendants(card).find(node=>node.BHasClass('CollectionGW2SlotFrame')),'slot',[2,2,2,2],false);
  const quantity=descendants(card).find(node=>node.BHasClass('CollectionGW2CardLabel'));
  assert.equal(quantity.visible,Number(card.__collectionItem.count)>0,'Zero ownership labels stay hidden while positive counts remain readable');
  if(Number(card.__collectionItem.count)>0)assert.equal(quantity.text,String(card.__collectionItem.count));
 });
}
['ex','friend','wife'].forEach((id,i)=>{
 const tab=nodes['CollectionGW2Tab_'+id],children=descendants(tab),frame=children.find(n=>n.BHasClass('CollectionGW2TabSelected')),icon=children.find(n=>n.paneltype==='Image');
 assert.equal(parseFloat(tab.style.width),44);assert.equal(parseFloat(tab.style.height),44);
 assert.equal(parseFloat(icon.style.width),28);assert.equal(parseFloat(icon.style.height),28);
 assert(!children.some(n=>n.paneltype==='Label'),'Category rail is icons only');
 assertNine(frame,'frame',[10,10,10,10],false);assert.equal(frame.style.borderLeft,undefined,'No protruding left selection edge');
 assert(bounds(tab).x>=bounds(nodes.CollectionGW2Sidebar).x&&bounds(tab).right<=bounds(nodes.CollectionGW2Sidebar).right,'Icon buttons stay inside the rail');
 assert(bounds(frame).x>=0&&bounds(frame).y>=0&&bounds(frame).right<=parseFloat(tab.style.width)&&bounds(frame).bottom<=parseFloat(tab.style.height),'The selected border stays within the icon button');
 assert.equal(typeof tab.events.onmouseover,'function');assert.equal(typeof tab.events.onmouseout,'function');
});
nodes.CollectionGW2Result.text='服务端返回的完整长错误说明'.repeat(50);assert(bounds(nodes.CollectionGW2Result).right<=bounds(nodes.CollectionGW2Draw).x,'Even a long response is contained before the draw button');assert.equal(nodes.CollectionGW2Result.style.textOverflow,'ellipsis');
api.Open('wife');assert.equal(h.sent.at(-1).payload.category_id,'wife','Wife requests the authoritative configured pool');assert.equal(h.sent.at(-1).payload.prefetch,1);assert.equal(api.Inspect().slots,0);assert(!nodes.CollectionGW2Draw.enabled);assert.equal(nodes.CollectionGW2Empty.text,'正在读取收藏…');
assert.equal(nodes.CollectionGW2GridBody.Children().length,0,'Wife never invents ownership while the server response is incomplete');
h.click(nodes.CollectionGW2Draw);assert.equal(draws().length,0);
emit({...packet('wife',10,wifeRows.slice(20)),chunk:2,chunks:2});assert.equal(api.Inspect().slots,0,'An out-of-order wife fragment cannot display a partial collection');
emit({...packet('wife',10,wifeRows.slice(0,20)),chunk:1,chunks:2});assertOnePage('wife');assert(nodes.CollectionGW2Draw.enabled);assert.equal(nodes.CollectionGW2Category.text,'我的老婆');assert(nodes.CollectionGW2Tickets.text.includes('姻缘签'));
nodes.CollectionGW2Item_wife_01.events.onmouseover();assert.equal(nodes.CollectionGW2TooltipQuantity.text,'2/60');assert(nodes.CollectionGW2TooltipEffect.text.includes('真实奖励效果0'));
snapshot('wife',11,wifeRows.map((row,i)=>i===39?{...row,draw_enabled:0,availability_note:'待适配，暂不参与抽取，不消耗玫瑰',description:'原文特殊效果'}:row));
assert.equal(api.Inspect().slots,40,'A pending adaptation remains visible beside the live draw pool');assert(nodes.CollectionGW2Item_wife_40.BHasClass('CollectionGW2Unavailable'));assert.equal(nodes.CollectionGW2Unavailable_wife_40,undefined,'Unavailable cards do not create an adaptation label');assert.equal(nodes.CollectionGW2Item_wife_40.__collectionItem.draw_enabled,0,'Removing the label preserves draw availability');
nodes.CollectionGW2Item_wife_40.events.onmouseover();assert(nodes.CollectionGW2TooltipState.text.includes('未解锁'));assert(!nodes.CollectionGW2TooltipState.text.includes('待适配'));assert.equal(nodes.CollectionGW2TooltipEffect.text,'原文特殊效果');assert(nodes.CollectionGW2TooltipCondition.text.includes('不消耗玫瑰'));assert(nodes.CollectionGW2TooltipCondition.visible);assert(nodes.CollectionGW2Draw.enabled,'Pending adaptation rows do not disable the remaining configured pool');
snapshot('wife',12,wifeRows);
snapshot('unconfigured_pool',900,wifeRows);assert.equal(api.Inspect().rows[0].id,'wife_01','Unknown categories cannot replace the current authoritative pool');
api.Select('ex');assert.equal(h.sent.at(-1).payload.category_id,'ex');assert.equal(h.sent.at(-1).payload.prefetch,1);assert.equal(api.Inspect().slots,api.Inspect().rows.length);
const pieces=[rows.slice(0,12),rows.slice(12,24),rows.slice(24,36),rows.slice(36)];
for(const index of [2,0,3])emit({...packet('ex',10,pieces[index]),chunk:index+1,chunks:4});
assert.equal(api.Inspect().rows.length,0,'Partial server pages cannot show incomplete ownership');
emit({...packet('ex',10,pieces[1]),chunk:2,chunks:4});
assert.equal(api.Inspect().rows.length,40);assert.equal(api.Inspect().slots,api.Inspect().rows.length);assert(nodes.CollectionGW2Draw.enabled);
assertOnePage('ex');
assert.equal(images(nodes.CollectionGW2Item_ex_01)[0].image,'s2r://panorama/images/custom_game/collection_portraits_compact_v1/ex_01.vtex','The collection uses its dedicated 128px portrait resource');
assert.equal(nodes.CollectionGW2GridBody.Children().length,rows.length);assert(nodes.CollectionGW2GridBody.Children().every(card=>card.__collectionItem),'No empty placeholder cells are created');
const cells=nodes.CollectionGW2GridBody.Children().slice(),created=h.counts.created;
for(let i=11;i<41;i++)snapshot('ex',i,rows);
assert.equal(h.counts.created,created,'Equal snapshots do not rebuild the actual item cards');assert.deepEqual(nodes.CollectionGW2GridBody.Children(),cells);
h.click(nodes.CollectionGW2Item_ex_01);assert.equal(h.counts.created,created,'Selecting an item changes only its outline and tooltip');assert.equal(draws().length,0,'Viewing an item never draws a reward');
nodes.CollectionGW2Item_ex_01.events.onmouseover();h.flushFinite();assert(api.Inspect().tooltipVisible);assert(nodes.CollectionGW2TooltipEffect.text.includes('真实奖励效果0'));assert.equal(nodes.CollectionGW2TooltipQuantity.text,'2/60');
assert(!nodes.CollectionGW2Search&&!nodes.CollectionGW2SearchBacking&&!nodes.CollectionGW2SearchHint,'The search box, hint and background are removed');
assert.equal(nodes.CollectionGW2Title.style.textShadow,'none','Collection labels have no blurred shadow');
assert.equal(api.Inspect().rows.length,40,'All collection entries remain visible without search');
snapshot('friend',42,friendRows);api.Select('friend');assert.equal(api.Inspect().rows.length,40);assert.equal(nodes.CollectionGW2Category.text,'我的前男友');assert.equal(images(nodes.CollectionGW2Item_friend_01)[0].image,'s2r://panorama/images/custom_game/collection_portraits_compact_v1/friend_01.vtex');
assertOnePage('friend');
api.Select('ex');h.click(nodes.CollectionGW2Draw);const first=api.Inspect().pending;assert(first&&first.pool_id==='ex');assert.equal(draws().length,1);nodes.CollectionGW2Draw.events.onactivate();assert.equal(draws().length,1,'Double clicks share one draw intent');
api.Select('friend');assert(!nodes.CollectionGW2Draw.enabled,'The pending intent also guards the other pool');api.Close();api.Open('friend');assert(!nodes.CollectionGW2Draw.enabled,'Reopening cannot spend again while a draw is unresolved');
const old=api,oldDraw=nodes.CollectionGW2Draw.events.onactivate;
h.load('collection_gw2.js');api=cfg.SurvivalCollection;api.Open('ex');assert.equal(api.Inspect().pending.request_id,first.request_id,'Pending state survives hot reload');oldDraw();old.Open();assert.equal(draws().length,1);
ack(first,{request_id:'unrelated'});assert(api.Inspect().pending,'An unrelated ACK cannot release the draw');ack(first,{terminal:false,pending:true,error:'网络超时'});assert(api.Inspect().pending,'Nonterminal server retries retain the intent');h.flushFinite();assert.equal(draws().length,2,'The reopened instance makes one recovery request');assert.equal(draws().at(-1).payload.request_id,first.request_id,'Recovery preserves the original transaction nonce');h.flushFinite();assert.equal(draws().length,2,'Timers cannot continuously replay a pending draw');
ack(first,{ok:true,terminal:true});assert(api.Inspect().pending,'Successful ACK waits for authoritative inventory');
emit(packet('ex',50,[{path:['rows',1,'count'],value:3},{path:['social','tickets'],value:2},{path:['last_draw'],value:{id:'match:social_draw:'+first.request_id,pool_id:'ex',name:'胡桃'}}],{delta:1,base_sequence:40}));
assert.equal(api.Inspect().pending,null);assert.equal(api.Inspect().rows[0].count,3);assert(nodes.CollectionGW2Draw.enabled);assert.equal(nodes.CollectionGW2Result.text,'','Committed collection draws use their item highlight rather than a success announcement');assert(nodes.CollectionGW2Item_ex_01.BHasClass('CollectionGW2RewardHighlight'));
snapshot('ex',49,rows);assert.equal(api.Inspect().rows[0].count,3,'Stale versions cannot undo acquired ownership');
h.click(nodes.CollectionGW2Draw);const rejected=api.Inspect().pending;ack(rejected,{error:'邀请函不足'});assert.equal(api.Inspect().pending,null);assert.equal(nodes.CollectionGW2Result.text,'邀请函不足','A terminal rejection releases the local gate and displays the real error');
h.click(nodes.CollectionGW2Draw);const concurrent=api.Inspect().pending;ack(concurrent,{ok:true,revision:80});assert(api.Inspect().pending,'A success cannot unlock before its authoritative profile revision');
const acquired=rows.map((r,i)=>({...r,count:i?0:3}));snapshot('ex',55,acquired,{revision:79,last_draw:{id:'match:social_draw:'+concurrent.request_id,pool_id:'ex',name:'胡桃'}});assert(api.Inspect().pending,'A matching draw name cannot bypass the newer acknowledged profile version');
snapshot('ex',56,acquired,{revision:80,last_draw:{id:'later-beast-draw',pool_id:'beast',name:'散魂钟'}});assert.equal(api.Inspect().pending,null,'A later blessing draw may replace last_draw without trapping the completed collection intent');
snapshot('ex',57,[{...acquired[0],count_known:0},...acquired.slice(1)]);assert(nodes.CollectionGW2Item_ex_01.BHasClass('CollectionGW2Unknown'));nodes.CollectionGW2Item_ex_01.events.onmouseover();assert.equal(nodes.CollectionGW2TooltipQuantity.text,'—/60');assert(nodes.CollectionGW2TooltipState.text.includes('状态待同步'));assert(nodes.CollectionGW2Summary.text.includes('已收藏 0 / 40'),'Unknown ownership is not counted as owned');snapshot('ex',58,acquired);
const requestsBeforeGap=h.sent.length;emit(packet('ex',60,[{path:['rows',1,'count'],value:99}],{delta:1,base_sequence:999}));assert.equal(api.Inspect().rows[0].count,3);h.flushFinite();assert(h.sent.length>requestsBeforeGap);assert.equal(h.sent.at(-1).payload.prefetch,1,'Missing delta baselines request a full authoritative page');
const many=Array.from({length:113},(_,i)=>({...rows[i%40],id:rows[i%40].id}));snapshot('ex',61,many);assert.equal(api.Inspect().slots,many.length);assert(parseFloat(nodes.CollectionGW2GridBody.style.height)>parseFloat(nodes.CollectionGW2Grid.style.height),'Additional real entries extend the scrolling inventory');
assert.equal(parseFloat(nodes.CollectionGW2Grid.style.width),842,'Future overflow adds an eight-pixel scrollbar gutter');assert.equal(parseFloat(nodes.CollectionGW2GridBody.style.width),834,'Overflow preserves the ten-column body width');
api.Close();const beforeClosed=h.counts.created;snapshot('ex',62,rows);assert.equal(h.counts.created,beforeClosed,'Hidden updates cache ownership without rebuilding UI');
api.Open('wife');assertOnePage('wife');const wifeRequests=h.sent.length,wifeRefreshDraws=draws().length;h.flushFinite();assert.equal(h.sent.length,wifeRequests);assert(nodes.CollectionGW2Draw.enabled);
for(let i=0;i<12;i++){api.Close();api.Open('wife');}assert.equal(h.sent.length,wifeRequests+12,'Repeated wife opens refresh authority without inventing a draw');assert.equal(draws().length,wifeRefreshDraws);
h.click(nodes.CollectionGW2Close);assert(!api.IsOpen());api.Open('ex');
assertOnePage('ex');
h.click(nodes.CollectionGW2Draw);const lostAck=api.Inspect().pending,lostAckDraws=draws().length;
h.load('collection_gw2.js');api=cfg.SurvivalCollection;api.Open('ex');
snapshot('ex',70,acquired,{pending:1,last_draw:{id:'match:social_draw:'+lostAck.request_id,pool_id:'ex',name:'胡桃'}});assert(api.Inspect().pending,'A pending page is not a committed draw proof');
snapshot('ex',71,acquired,{pending:0,last_draw:{id:'match:social_draw:'+lostAck.request_id,pool_id:'ex',name:'胡桃'}});assert.equal(api.Inspect().pending,null,'A fully assembled committed transaction repairs an ACK lost during reload');h.flushFinite();assert.equal(draws().length,lostAckDraws,'An authoritative proof cancels the need to replay');
h.click(nodes.CollectionGW2Draw);const overwritten=api.Inspect().pending,overwrittenDraws=draws().length;
snapshot('ex',72,acquired,{revision:89,last_draw:{id:'later-beast-draw',pool_id:'beast',name:'散魂钟'}});assert(api.Inspect().pending);
api.Close();api.Open('ex');api.Open('ex');const recoveryJobs=h.scheduled.filter(job=>job.delay===.55);assert(recoveryJobs.length>0&&recoveryJobs.every(job=>job.delay>=.5),'Recovery stays outside the server 0.3-second throttle');h.flushFinite();
assert.equal(draws().length,overwrittenDraws+1,'One reopen schedules exactly one recovery even when Open is called again');assert.deepEqual(JSON.parse(JSON.stringify(draws().at(-1).payload)),{pool_id:'ex',request_id:overwritten.request_id});assert.equal(api.Inspect().pending.request_id,overwritten.request_id);
h.flushFinite();assert.equal(draws().length,overwrittenDraws+1,'No polling cycle invents another draw or nonce');
ack(overwritten,{ok:true,revision:90,duplicate:true});snapshot('ex',73,acquired,{revision:90,last_draw:{id:'later-beast-draw',pool_id:'beast',name:'散魂钟'}});assert.equal(api.Inspect().pending,null,'Idempotent duplicate ACK and current revision recover an overwritten last_draw');
h.click(nodes.CollectionGW2Draw);const cancelled=api.Inspect().pending,beforeCancelled=draws().length;api.Close();api.Open('ex');api.Close();h.flushFinite();assert.equal(draws().length,beforeCancelled,'Closing cancels the lifecycle recovery timer');api.Open('wife');h.flushFinite();assert.equal(draws().length,beforeCancelled+1,'The configured wife page can recover an unresolved cross-pool intent');assert.equal(draws().at(-1).payload.request_id,cancelled.request_id);ack(cancelled,{error:'测试取消'});
const wifeStart=draws().length;h.click(nodes.CollectionGW2Draw);const wifeIntent=api.Inspect().pending;assert.equal(wifeIntent.pool_id,'wife');nodes.CollectionGW2Draw.events.onactivate();assert.equal(draws().length,wifeStart+1,'Wife double clicks share one transaction nonce');
api.Select('friend');assert(!nodes.CollectionGW2Draw.enabled,'Wife pending ownership guards every collection tab');api.Close();h.load('collection_gw2.js');api=cfg.SurvivalCollection;api.Open('wife');assert.equal(api.Inspect().pending.request_id,wifeIntent.request_id);h.flushFinite();assert.equal(draws().length,wifeStart+2);assert.equal(draws().at(-1).payload.request_id,wifeIntent.request_id,'Wife hot reload only retries the original nonce');
api.Select('friend');ack(wifeIntent,{ok:true,revision:120});assert(api.Inspect().pending,'Wife ACK waits for its authoritative revision');assert.equal(h.sent.at(-1).payload.category_id,'wife','A wife ACK refreshes its own inventory even after a tab switch');
api.Close();h.load('collection_gw2.js');api=cfg.SurvivalCollection;api.Open('friend');assert.equal(h.sent.at(-1).payload.category_id,'wife','Reloading on another tab refreshes the acknowledged pending pool');api.Select('wife');
const wifeAcquired=wifeRows.map((row,i)=>({...row,count:i?0:3}));
emit({...packet('wife',13,wifeAcquired.slice(20),{revision:120,last_draw:{id:'game:social_draw:'+wifeIntent.request_id,pool_id:'wife',name:wifeRows[0].name}}),chunk:2,chunks:2});assert(api.Inspect().pending,'Incomplete wife draw snapshots cannot release the transaction gate');
emit({...packet('wife',13,wifeAcquired.slice(0,20),{revision:120,last_draw:{id:'game:social_draw:'+wifeIntent.request_id,pool_id:'wife',name:wifeRows[0].name}}),chunk:1,chunks:2});assert.equal(api.Inspect().pending,null);assert.equal(api.Inspect().rows[0].count,3);assert(nodes.CollectionGW2Item_wife_01.BHasClass('CollectionGW2RewardHighlight'));ack(wifeIntent,{ok:true,revision:120,duplicate:true});h.flushFinite();assert.equal(draws().length,wifeStart+2,'Duplicate wife ACK and snapshot do not create another draw');
emit(packet('wife',14,[{path:['rows',1,'count'],value:4}],{delta:1,base_sequence:13}));assert.equal(api.Inspect().rows[0].count,4,'Wife uses the shared authoritative delta cache');snapshot('wife',10,wifeRows);assert.equal(api.Inspect().rows[0].count,4,'Old wife snapshots cannot rewind ownership');
const wifeGapRequests=h.sent.length;emit(packet('wife',15,[{path:['rows',1,'count'],value:99}],{delta:1,base_sequence:777}));h.flushFinite();assert.equal(api.Inspect().rows[0].count,4);assert(h.sent.length>wifeGapRequests);assert.equal(h.sent.at(-1).payload.category_id,'wife');assert.equal(h.sent.at(-1).payload.prefetch,1,'A wife delta gap requests its full authoritative collection');
h.assertCleanDispose(api);
const formal=require('../collection_gw2/fixture.cjs').fixture(),formalWife=formal.pages.wife;
assert.equal(formalWife.length,40,'The formal wife fixture retains every video entry');assert.deepEqual(formalWife.map(row=>row.id),Array.from({length:40},(_,i)=>'wife_'+String(i+1).padStart(2,'0')),'Wife cards follow the video positions even when CSV additions are appended');
assert.deepEqual(formalWife.filter(row=>row.draw_enabled===0).map(row=>row.id),['wife_31','wife_39']);assert.equal(formalWife.filter(row=>row.draw_enabled!==0).length,38);
assert.equal(formal.social.wife.remaining,formalWife.filter(row=>row.draw_enabled!==0).reduce((sum,row)=>sum+row.target-row.count,0),'Preview draw weight excludes pending adaptation capacities');assert(formalWife.filter(row=>row.draw_enabled===0).every(row=>row.count===0&&!row.description.includes(row.availability_note)&&row.availability_note.includes('不消耗玫瑰')),'Pending entries preserve their separate notice and original description without synthetic ownership');
console.log('COLLECTION_GW2_PASS: native black and gold nine-piece borders, hidden zero counts, independent inventory, real compact portrait cards, configured wife pool, wife chunk/delta/stale recovery, cross-tab pending and retry-safe hot reload, request/ACK authority and closure');
