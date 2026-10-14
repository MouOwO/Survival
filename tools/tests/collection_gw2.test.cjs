const assert=require('node:assert/strict');
const {createHarness}=require('./fixtures/menus_v10_harness.cjs');
const h=createHarness(),{cfg,nodes}=h;
cfg.ArchiveHandoff={Icon(){throw new Error('Formal social portraits must resolve through the CSV icon catalog');},Init(){},Observe(){},CardProgress:item=>String(item.count)+'/'+String(item.target)};
h.load('ui_snapshot_cache.js');h.load('icons_remaining_5d5c1152eb.js');h.load('collection_gw2.js');
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
assert.equal(nodes.CollectionGW2Canvas.style.width,'1200px');assert.equal(nodes.CollectionGW2Canvas.style.height,'778px');
assert.equal(nodes.CollectionGW2Background.style.position,'0px 0px 0px');assert.equal(nodes.CollectionGW2Background.style.width,'1200px');
assert.equal(nodes.CollectionGW2Background.style.opacity,'0.84','Only the background wash is translucent');assert.notEqual(nodes.CollectionGW2Canvas.style.opacity,'0.84');
assert.equal(nodes.CollectionGW2Header.style.position,'0px 0px 0px');assert.equal(nodes.CollectionGW2Header.style.width,'1200px');assert.equal(nodes.CollectionGW2Header.style.height,'60px');
assert.equal(nodes.CollectionGW2Sidebar.style.position,'0px 60px 0px');assert.equal(nodes.CollectionGW2Sidebar.style.width,'70px');assert.equal(nodes.CollectionGW2Sidebar.style.height,'658px');assert.equal(nodes.CollectionGW2Sidebar.style.backgroundImage,'none');
assert.equal(nodes.CollectionGW2Sidebar.style.backgroundColor,nodes.CollectionGW2Header.style.backgroundColor,'Header and sidebar share one flat tint');
assert.equal(nodes.CollectionGW2Footer.style.position,'0px 718px 0px');assert.equal(nodes.CollectionGW2Footer.style.width,'1200px');assert.equal(nodes.CollectionGW2Footer.style.height,'60px');
assert.equal(nodes.CollectionGW2SearchBacking.style.position,'82px 109px 0px');assert.equal(nodes.CollectionGW2SearchBacking.style.width,'1090px');
assert.equal(nodes.CollectionGW2Grid.style.position,'82px 156px 0px');assert.equal(nodes.CollectionGW2Grid.style.width,'1110px');assert.equal(nodes.CollectionGW2Grid.style.height,'560px');
assert.equal(nodes.CollectionGW2Summary.style.position,'385px 73px 0px');
assert.equal(nodes.CollectionGW2Draw.style.position,'1010px 730px 0px');assert.equal(nodes.CollectionGW2Draw.style.width,'162px');assert.equal(nodes.CollectionGW2Draw.style.height,'30px');
assert.equal(nodes.CollectionGW2Draw.style.border,'1px solid #a7a99970');assert.equal(nodes.CollectionGW2Tooltip.style.boxShadow,'none');
assert.equal(nodes.CollectionGW2Result.style.position,'82px 753px 0px');assert.equal(nodes.CollectionGW2Result.style.height,'18px');assert.equal(nodes.CollectionGW2Result.style.width,'900px');
function bounds(node){const [x,y]=node.style.position.split(' ').map(parseFloat);return {x,y,right:x+parseFloat(node.style.width),bottom:y+parseFloat(node.style.height)};}
assert.equal(bounds(nodes.CollectionGW2Header).bottom,bounds(nodes.CollectionGW2Sidebar).y,'The left rail joins the header without a gap');
assert.equal(bounds(nodes.CollectionGW2Sidebar).bottom,bounds(nodes.CollectionGW2Footer).y,'The left rail joins the full-width footer');
function descendants(node){return node.Children().flatMap(child=>[child,...descendants(child)]);}
['ex','friend','wife'].forEach((id,i)=>{
 const tab=nodes['CollectionGW2Tab_'+id],children=descendants(tab),frame=children.find(n=>n.BHasClass('CollectionGW2TabSelected')),icon=children.find(n=>n.BHasClass('CollectionGW2Art'));
 assert.equal(tab.style.position,'4px '+(84+i*74)+'px 0px');assert.equal(tab.style.width,'62px');assert.equal(tab.style.height,'62px');
 assert(!children.some(n=>n.paneltype==='Label'),'Category rail is icons only');
 assert.equal(icon.style.position,'11px 11px 0px');assert.equal(icon.style.width,'40px');assert.equal(icon.style.height,'40px');
 assert.equal(frame.style.position,'2px 2px 0px');assert.equal(frame.style.width,'58px');assert.equal(frame.style.height,'58px');
 assert.equal(frame.style.backgroundColor,'transparent');assert.equal(frame.style.border,'1px solid #afc4c54a');assert.equal(frame.style.borderLeft,undefined,'No protruding left selection edge');
 assert(bounds(tab).x>=bounds(nodes.CollectionGW2Sidebar).x&&bounds(tab).right<=bounds(nodes.CollectionGW2Sidebar).right,'Icon buttons stay inside the rail');
 assert(bounds(frame).x>0&&bounds(frame).y>0&&bounds(frame).right<62&&bounds(frame).bottom<62,'The selection outline stays inset');
 assert.equal(typeof tab.events.onmouseover,'function');assert.equal(typeof tab.events.onmouseout,'function');
});
nodes.CollectionGW2Result.text='服务端返回的完整长错误说明'.repeat(50);assert(bounds(nodes.CollectionGW2Result).right+28<=bounds(nodes.CollectionGW2Draw).x,'Even a long response is contained before the draw button');assert.equal(nodes.CollectionGW2Result.style.textOverflow,'ellipsis');
api.Open('wife');assert.equal(h.sent.length,0,'An unconfigured wife page never requests an invalid pool');assert.equal(api.Inspect().slots,98);assert(!nodes.CollectionGW2Draw.enabled);assert.equal(nodes.CollectionGW2Empty.text,'暂无收藏配置');
h.click(nodes.CollectionGW2Draw);assert.equal(draws().length,0);
api.Select('ex');assert.equal(h.sent.at(-1).payload.category_id,'ex');assert.equal(h.sent.at(-1).payload.prefetch,1);assert.equal(api.Inspect().slots,98);
const pieces=[rows.slice(0,12),rows.slice(12,24),rows.slice(24,36),rows.slice(36)];
for(const index of [2,0,3])emit({...packet('ex',10,pieces[index]),chunk:index+1,chunks:4});
assert.equal(api.Inspect().rows.length,0,'Partial server pages cannot show incomplete ownership');
emit({...packet('ex',10,pieces[1]),chunk:2,chunks:4});
assert.equal(api.Inspect().rows.length,40);assert.equal(api.Inspect().slots,98);assert(nodes.CollectionGW2Draw.enabled);
assert.equal(images(nodes.CollectionGW2Item_ex_01)[0].image,'s2r://panorama/images/custom_game/archive_gpu_regular/head_v3_ex_01.vtex','The current formal portrait replaces the old heads catalog');
assert.equal(nodes.CollectionGW2Item_ex_01.style.width,'74px');assert.equal(images(nodes.CollectionGW2Item_ex_01)[0].style.width,'70px');
assert.equal(nodes.CollectionGW2Item_ex_14.style.position,'1014px 0px 0px');assert.equal(nodes.CollectionGW2Item_ex_15.style.position,'0px 80px 0px');assert.equal(nodes.CollectionGW2EmptySlot_97.style.position,'1014px 480px 0px');
const cells=nodes.CollectionGW2GridBody.Children().slice(),created=h.counts.created;
for(let i=11;i<41;i++)snapshot('ex',i,rows);
assert.equal(h.counts.created,created,'Equal snapshots do not rebuild the 98 inventory slots');assert.deepEqual(nodes.CollectionGW2GridBody.Children(),cells);
h.click(nodes.CollectionGW2Item_ex_01);assert.equal(h.counts.created,created,'Selecting an item changes only its outline and tooltip');assert.equal(draws().length,0,'Viewing an item never draws a reward');
nodes.CollectionGW2Item_ex_01.events.onmouseover();h.flushFinite();assert(api.Inspect().tooltipVisible);assert(nodes.CollectionGW2TooltipBody.text.includes('真实奖励效果0'));assert(nodes.CollectionGW2TooltipBody.text.includes('持有数量：2 / 60'));
nodes.CollectionGW2Search.text='胡桃';nodes.CollectionGW2Search.events.ontextentrychange();assert.equal(api.Inspect().rows.length,1);assert.equal(api.Inspect().slots,98);assert(!api.Inspect().tooltipVisible);
nodes.CollectionGW2Search.text='不存在';nodes.CollectionGW2Search.events.ontextentrychange();assert.equal(api.Inspect().rows.length,0);assert.equal(nodes.CollectionGW2Empty.text,'没有找到匹配的收藏');
nodes.CollectionGW2Search.text='';nodes.CollectionGW2Search.events.ontextentrychange();
snapshot('friend',42,friendRows);api.Select('friend');assert.equal(api.Inspect().rows.length,40);assert.equal(nodes.CollectionGW2Category.text,'我的前男友');assert(images(nodes.CollectionGW2Item_friend_01)[0].image.includes('head_v3_friend_01'));
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
snapshot('ex',57,[{...acquired[0],count_known:0},...acquired.slice(1)]);assert(nodes.CollectionGW2Item_ex_01.BHasClass('CollectionGW2Unknown'));nodes.CollectionGW2Item_ex_01.events.onmouseover();assert(nodes.CollectionGW2TooltipBody.text.includes('持有数量：—'));assert(nodes.CollectionGW2Summary.text.includes('已收藏 0 / 40'),'Unknown ownership is not counted as owned');snapshot('ex',58,acquired);
const requestsBeforeGap=h.sent.length;emit(packet('ex',60,[{path:['rows',1,'count'],value:99}],{delta:1,base_sequence:999}));assert.equal(api.Inspect().rows[0].count,3);h.flushFinite();assert(h.sent.length>requestsBeforeGap);assert.equal(h.sent.at(-1).payload.prefetch,1,'Missing delta baselines request a full authoritative page');
const many=Array.from({length:113},(_,i)=>({...rows[i%40],id:rows[i%40].id}));snapshot('ex',61,many);assert.equal(api.Inspect().slots,126);assert.equal(nodes.CollectionGW2GridBody.style.height,'720px','Additional real entries extend the scrolling inventory');
api.Close();const beforeClosed=h.counts.created;snapshot('ex',62,rows);assert.equal(h.counts.created,beforeClosed,'Hidden updates cache ownership without rebuilding UI');
api.Open('wife');const wifeRequests=h.sent.length;h.flushFinite();assert.equal(h.sent.length,wifeRequests);assert.equal(api.Inspect().rows.length,0);assert.equal(api.Inspect().slots,98);assert(!nodes.CollectionGW2Draw.enabled);
for(let i=0;i<12;i++){api.Close();api.Open('wife');}assert.equal(h.sent.length,wifeRequests,'Repeated wife opens do not invent a backend category');
h.click(nodes.CollectionGW2Close);assert(!api.IsOpen());api.Open('ex');
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
console.log('COLLECTION_GW2_PASS: independent inventory, 98 slots, formal v3 portraits, search, wife empty, chunk/delta/stale recovery, no hidden rebuild, request/ACK authority, retry-safe hot reload and closure');
