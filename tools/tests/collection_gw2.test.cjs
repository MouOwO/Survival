const assert=require('node:assert/strict');
const {createHarness}=require('./fixtures/menus_v10_harness.cjs');
const h=createHarness(),{cfg,nodes}=h;
cfg.ArchiveHandoff={Icon(){throw new Error('Formal social portraits must resolve through the CSV icon catalog');},Init(){},Observe(){},CardProgress:item=>String(item.count)+'/'+String(item.target)};
h.load('ui_snapshot_cache.js');h.load('icons_remaining_5d5c1152eb.js');h.load('archive_parchment_data.js');h.load('archive_v10_semantics.js');h.load('common/archive_tooltip.js');h.load('collection_gw2_data.js');h.load('collection_gw2.js');
const rows=Array.from({length:40},(_,i)=>({id:'ex_'+String(i+1).padStart(2,'0'),name:i?'正式收藏'+i:'胡桃',count:i===0?2:0,target:60,description:'真实奖励效果'+i}));
const friendRows=rows.map((r,i)=>({...r,id:'friend_'+String(i+1).padStart(2,'0'),name:i?'正式好友'+i:'哆啦A梦'}));
function packet(category,sequence,items,extra={}){return {ok:1,category_id:category,sequence,chunk:1,chunks:1,rows:items,social:{tickets:3,currency_name:category==='ex'?'邀请函':'义帖',draw_cost:1,remaining:999,total:2},pending:0,...extra};}
function emit(data){h.emit('survival_archive_snapshot',data);}
function snapshot(category,sequence,items,extra){emit(packet(category,sequence,items,extra));}
function ack(pending,extra){h.emit('survival_archive_social_result',{pool_id:pending.pool_id,request_id:pending.request_id,ok:false,terminal:true,pending:false,...extra});}
function draws(){return h.sent.filter(r=>r.name==='survival_archive_social_draw');}
function images(node){return (node.paneltype==='Image'?[node]:[]).concat(node.Children().flatMap(images));}
let api=cfg.SurvivalCollection;
assert.equal(nodes.CollectionScrim.style.backgroundColor,'#00000022','The flat inventory overrides the generic modal dark scrim after adoption');
assert.equal(nodes.CollectionGW2Background.style.opacity,'1','The collection texture is not faded');assert.equal(nodes.CollectionGW2Background.style.backgroundColor,'#171e24','Opaque backing covers the source texture alpha');assert.equal(nodes.CollectionWindow.style.backgroundColor,'#171e24');
assert.equal(nodes.CollectionGW2CloseIcon.paneltype,'Image');assert(!nodes.CollectionGW2Close.Children().some(child=>child.paneltype==='Label'),'Close uses the fixed image instead of a font glyph');
assert.equal(nodes.CollectionGW2Sidebar.style.backgroundColor,nodes.CollectionGW2Header.style.backgroundColor,'Header and sidebar share one flat tint');
function bounds(node){const [x,y]=node.style.position.split(' ').map(parseFloat);return {x,y,right:x+parseFloat(node.style.width),bottom:y+parseFloat(node.style.height)};}
assert.deepEqual(Array.from(api.Inspect().canvas),[900,478],'One-page canvas matches the approved presentation metadata');
assert.equal(parseFloat(nodes.CollectionGW2Header.style.height),34,'The title band stays thin');
assert.equal(parseFloat(nodes.CollectionGW2Title.style.fontSize),18,'The title uses the smaller approved size');
assert(bounds(nodes.CollectionGW2Title).bottom<=bounds(nodes.CollectionGW2Header).bottom,'The smaller title is contained in its band');
assert.equal(bounds(nodes.CollectionGW2Header).bottom,bounds(nodes.CollectionGW2Sidebar).y,'The left rail joins the header without a gap');
assert.equal(bounds(nodes.CollectionGW2Sidebar).bottom,bounds(nodes.CollectionGW2Footer).y,'The left rail joins the full-width footer');
function descendants(node){return node.Children().flatMap(child=>[child,...descendants(child)]);}
function assertOnePage(category){
 const cards=nodes.CollectionGW2GridBody.Children(),grid=nodes.CollectionGW2Grid,body=nodes.CollectionGW2GridBody;
 assert.equal(cards.length,40,category+' renders all forty actual entries');
 assert.equal(api.Inspect().columns,10);assert.equal(api.Inspect().portraitSize,74);
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
  assert.equal(parseFloat(portraits[0].style.width),74);assert.equal(parseFloat(portraits[0].style.height),74);
 });
}
['ex','friend','wife'].forEach((id,i)=>{
 const tab=nodes['CollectionGW2Tab_'+id],children=descendants(tab),frame=children.find(n=>n.BHasClass('CollectionGW2TabSelected')),icon=children.find(n=>n.BHasClass('CollectionGW2Art'));
 assert.equal(parseFloat(tab.style.width),34);assert.equal(parseFloat(tab.style.height),34);
 assert.equal(parseFloat(icon.style.width),27);assert.equal(parseFloat(icon.style.height),27);
 assert(!children.some(n=>n.paneltype==='Label'),'Category rail is icons only');
 assert.equal(frame.style.backgroundColor,'transparent');assert.equal(frame.style.border,'1px solid #afc4c54a');assert.equal(frame.style.borderLeft,undefined,'No protruding left selection edge');
 assert(bounds(tab).x>=bounds(nodes.CollectionGW2Sidebar).x&&bounds(tab).right<=bounds(nodes.CollectionGW2Sidebar).right,'Icon buttons stay inside the rail');
 assert(bounds(frame).x>0&&bounds(frame).y>0&&bounds(frame).right<parseFloat(tab.style.width)&&bounds(frame).bottom<parseFloat(tab.style.height),'The selection outline stays inset');
 assert.equal(typeof tab.events.onmouseover,'function');assert.equal(typeof tab.events.onmouseout,'function');
});
nodes.CollectionGW2Result.text='服务端返回的完整长错误说明'.repeat(50);assert(bounds(nodes.CollectionGW2Result).right<=bounds(nodes.CollectionGW2Draw).x,'Even a long response is contained before the draw button');assert.equal(nodes.CollectionGW2Result.style.textOverflow,'ellipsis');
api.Open('wife');assert.equal(h.sent.length,0,'An unconfigured wife page never requests an invalid pool');assert.equal(api.Inspect().slots,api.Inspect().rows.length);assert(!nodes.CollectionGW2Draw.enabled);assert.equal(nodes.CollectionGW2Empty.text,'暂无收藏配置');
assert.equal(nodes.CollectionGW2GridBody.Children().length,0,'The unconfigured wife page has no fabricated placeholder cells');
h.click(nodes.CollectionGW2Draw);assert.equal(draws().length,0);
api.Select('ex');assert.equal(h.sent.at(-1).payload.category_id,'ex');assert.equal(h.sent.at(-1).payload.prefetch,1);assert.equal(api.Inspect().slots,api.Inspect().rows.length);
const pieces=[rows.slice(0,12),rows.slice(12,24),rows.slice(24,36),rows.slice(36)];
for(const index of [2,0,3])emit({...packet('ex',10,pieces[index]),chunk:index+1,chunks:4});
assert.equal(api.Inspect().rows.length,0,'Partial server pages cannot show incomplete ownership');
emit({...packet('ex',10,pieces[1]),chunk:2,chunks:4});
assert.equal(api.Inspect().rows.length,40);assert.equal(api.Inspect().slots,api.Inspect().rows.length);assert(nodes.CollectionGW2Draw.enabled);
assertOnePage('ex');
assert.equal(images(nodes.CollectionGW2Item_ex_01)[0].image,'s2r://panorama/images/custom_game/archive_gpu_regular/head_v3_ex_01.vtex','The current formal portrait replaces the old heads catalog');
assert.equal(nodes.CollectionGW2GridBody.Children().length,rows.length);assert(nodes.CollectionGW2GridBody.Children().every(card=>card.__collectionItem),'No empty placeholder cells are created');
const cells=nodes.CollectionGW2GridBody.Children().slice(),created=h.counts.created;
for(let i=11;i<41;i++)snapshot('ex',i,rows);
assert.equal(h.counts.created,created,'Equal snapshots do not rebuild the actual item cards');assert.deepEqual(nodes.CollectionGW2GridBody.Children(),cells);
h.click(nodes.CollectionGW2Item_ex_01);assert.equal(h.counts.created,created,'Selecting an item changes only its outline and tooltip');assert.equal(draws().length,0,'Viewing an item never draws a reward');
nodes.CollectionGW2Item_ex_01.events.onmouseover();h.flushFinite();assert(api.Inspect().tooltipVisible);assert(nodes.CollectionGW2TooltipEffect.text.includes('真实奖励效果0'));assert.equal(nodes.CollectionGW2TooltipQuantity.text,'2/60');
nodes.CollectionGW2Search.text='胡桃';nodes.CollectionGW2Search.events.ontextentrychange();assert.equal(api.Inspect().rows.length,1);assert.equal(api.Inspect().slots,api.Inspect().rows.length);assert(!api.Inspect().tooltipVisible);
nodes.CollectionGW2Search.text='不存在';nodes.CollectionGW2Search.events.ontextentrychange();assert.equal(api.Inspect().rows.length,0);assert.equal(api.Inspect().slots,0);assert.equal(nodes.CollectionGW2Empty.text,'没有找到匹配的收藏');
nodes.CollectionGW2Search.text='';nodes.CollectionGW2Search.events.ontextentrychange();
snapshot('friend',42,friendRows);api.Select('friend');assert.equal(api.Inspect().rows.length,40);assert.equal(nodes.CollectionGW2Category.text,'我的前男友');assert(images(nodes.CollectionGW2Item_friend_01)[0].image.includes('head_v3_friend_01'));
assertOnePage('friend');
api.Select('ex');h.click(nodes.CollectionGW2Draw);const first=api.Inspect().pending;assert(first&&first.pool_id==='ex');assert.equal(draws().length,1);nodes.CollectionGW2Draw.events.onactivate();assert.equal(draws().length,1,'Double clicks share one draw intent');
api.Select('friend');assert(!nodes.CollectionGW2Draw.enabled,'The pending intent also guards the other pool');api.Close();api.Open('friend');assert(!nodes.CollectionGW2Draw.enabled,'Reopening cannot spend again while a draw is unresolved');
const old=api,oldDraw=nodes.CollectionGW2Draw.events.onactivate;
h.load('collection_gw2.js');api=cfg.SurvivalCollection;api.Open('ex');assert.equal(api.Inspect().pending.request_id,first.request_id,'Pending state survives hot reload');oldDraw();old.Open();assert.equal(draws().length,1);
ack(first,{request_id:'unrelated'});assert(api.Inspect().pending,'An unrelated ACK cannot release the draw');ack(first,{terminal:false,pending:true,error:'网络超时'});assert(api.Inspect().pending,'Nonterminal server retries retain the intent');h.flushFinite();assert.equal(draws().length,2,'The reopened instance makes one recovery request');assert.equal(draws().at(-1).payload.request_id,first.request_id,'Recovery preserves the original transaction nonce');h.flushFinite();assert.equal(draws().length,2,'Timers cannot continuously replay a pending draw');
ack(first,{ok:true,terminal:true});assert(api.Inspect().pending,'Successful ACK waits for authoritative inventory');
emit(packet('ex',50,[{path:['rows',1,'count'],value:3},{path:['social','tickets'],value:2},{path:['last_draw'],value:{id:'match:social_draw:'+first.request_id,pool_id:'ex',name:'胡桃'}}],{delta:1,base_sequence:40}));
assert.equal(api.Inspect().pending,null);assert.equal(api.Inspect().rows[0].count,3);assert(nodes.CollectionGW2Draw.enabled);assert.equal(nodes.CollectionGW2Result.text,'获得：胡桃');
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
api.Open('wife');const wifeRequests=h.sent.length;h.flushFinite();assert.equal(h.sent.length,wifeRequests);assert.equal(api.Inspect().rows.length,0);assert.equal(api.Inspect().slots,api.Inspect().rows.length);assert(!nodes.CollectionGW2Draw.enabled);
for(let i=0;i<12;i++){api.Close();api.Open('wife');}assert.equal(h.sent.length,wifeRequests,'Repeated wife opens do not invent a backend category');
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
h.click(nodes.CollectionGW2Draw);const beforeCancelled=draws().length;api.Close();api.Open('ex');api.Close();h.flushFinite();assert.equal(draws().length,beforeCancelled,'Closing cancels the lifecycle recovery timer');api.Open('wife');h.flushFinite();assert.equal(draws().length,beforeCancelled,'The unconfigured wife page never replays another pool');
h.assertCleanDispose(api);
console.log('COLLECTION_GW2_PASS: independent inventory, real item cards only, formal v3 portraits, search, wife empty, chunk/delta/stale recovery, no hidden rebuild, request/ACK authority, retry-safe hot reload and closure');
