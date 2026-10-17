const assert=require('node:assert/strict');
const {csv}=require('../shop_ui_12h/catalog.cjs');
const {createHarness}=require('./fixtures/menus_v10_harness.cjs');
const h=createHarness(),{cfg,nodes}=h;
cfg.ArchiveHandoff={Icon(){throw Error('Use the formal reward art catalog');},Init(){},Observe(){},CardProgress:item=>item.count+'/'+item.target};
for(const script of ['ui_snapshot_cache.js','icons_remaining_5d5c1152eb.js','archive_parchment_data.js','archive_v10_semantics.js','common/archive_tooltip.js','collection_gw2_data.js','collection_gw2.js'])h.load(script);
let api=cfg.SurvivalCollection;
const definitions=csv('data/csv/存档系统/archive_social_items.csv').filter(r=>r.enabled==='1'&&r.pool_id==='beast');
const rule=csv('data/csv/存档系统/archive_social_rules.csv').find(r=>r.pool_id==='beast');
const rows=definitions.map((r,i)=>({id:r.item_id,name:r.display_name,description:r.description,quality:r.quality,count:i===0?2:0,count_known:1,target:+r.max_owned,max_owned:+r.max_owned,icon_style:'seal'}));
function packet(sequence,items=rows,extra={}){
 return {ok:1,category_id:'beast',sequence,chunk:1,chunks:1,rows:items,pending:0,social:{tickets:2,currency_name:rule.currency_name,draw_cost:+rule.draw_cost,total:items.reduce((n,r)=>n+r.count,0),remaining:items.reduce((n,r)=>n+Math.max(0,r.target-r.count),0)},...extra};
}
function emit(data){h.emit('survival_archive_snapshot',data);}
function ack(intent,extra){h.emit('survival_archive_social_result',{pool_id:'beast',request_id:intent.request_id,terminal:true,...extra});}
function draws(){return h.sent.filter(r=>r.name==='survival_archive_social_draw');}
function images(n){return (n.paneltype==='Image'?[n]:[]).concat(n.Children().flatMap(images));}
assert.equal(rows.length,40,'Use all forty existing formal rewards');
assert.equal(rule.currency_name,'福签');
assert.equal(nodes.CollectionGW2Tab_beast.Children().filter(n=>n.BHasClass('CollectionGW2Art')).length,1);
api.Open('beast');
assert.equal(h.sent.at(-1).payload.category_id,'beast');
assert.equal(api.Inspect().slots,0,'No placeholder rewards before authority arrives');
emit({...packet(10,rows.slice(20)),chunk:2,chunks:2});
assert.equal(api.Inspect().slots,0,'Incomplete inventory never replaces the page');
emit({...packet(10,rows.slice(0,20)),chunk:1,chunks:2});
assert.equal(api.Inspect().category,'beast');assert.equal(nodes.CollectionGW2Category.text,'瑞兽赐福');
assert.equal(api.Inspect().slots,40);assert.equal(nodes.CollectionGW2GridBody.GetChildCount(),40);
assert.equal(nodes.CollectionGW2GridBody.style.height,nodes.CollectionGW2Grid.style.height,'All forty fit on one page');
assert(nodes.CollectionGW2Tickets.text.includes('福签：2'));assert(nodes.CollectionGW2Draw.enabled);
for(const item of rows){
 const card=nodes['CollectionGW2Item_'+item.id],art=images(card);
 assert.equal(art.length,1);assert.equal(art[0].image,'s2r://panorama/images/custom_game/collection_portraits_compact_v1/'+item.id+'.vtex');
 assert.equal(card.__collectionItem.target,item.target,'Each original reward keeps its own cap');
}
nodes.CollectionGW2Item_beast_01.events.onmouseover();
assert.equal(nodes.CollectionGW2TooltipTitle.text,rows[0].name);
assert.equal(nodes.CollectionGW2TooltipQuantity.text,'2/'+rows[0].target);
assert(nodes.CollectionGW2TooltipEffect.text.includes(rows[0].description));
nodes.CollectionGW2Search.text=rows[0].name;nodes.CollectionGW2Search.events.ontextentrychange();
assert.equal(api.Inspect().slots,1);assert.equal(api.Inspect().rows[0].id,rows[0].id);
nodes.CollectionGW2Search.text='';nodes.CollectionGW2Search.events.ontextentrychange();
emit({ok:1,category_id:'ex',sequence:1,chunk:1,chunks:1,pending:0,rows:[{id:'ex_01',name:'胡桃',count:1,target:60}],social:{tickets:3,draw_cost:1,remaining:59,total:1}});
h.click(nodes.CollectionGW2Draw);const intent=api.Inspect().pending;
assert.equal(intent.pool_id,'beast');assert.equal(draws().length,1);
assert.deepEqual(JSON.parse(JSON.stringify(draws()[0].payload)),{pool_id:'beast',request_id:intent.request_id});
nodes.CollectionGW2Draw.events.onactivate();assert.equal(draws().length,1,'Double clicking never spends another ticket');
api.Select('ex');assert(!nodes.CollectionGW2Draw.enabled,'One pending reward guards all collection pools');
api.Close();h.load('collection_gw2.js');api=cfg.SurvivalCollection;api.Open('beast');
assert.equal(api.Inspect().pending.request_id,intent.request_id,'Reload preserves the transaction identity');
ack(intent,{ok:true,revision:21});assert(api.Inspect().pending,'ACK cannot unlock before authoritative inventory');
const acquired=rows.map((r,i)=>({...r,count:i===0?3:r.count}));
const last_draw={id:'proof:social_draw:'+intent.request_id,pool_id:'beast',name:rows[0].name};
emit(packet(11,acquired,{revision:20,last_draw}));assert(api.Inspect().pending,'Older inventory cannot satisfy the ACK revision');
const committed=packet(12,acquired,{revision:21,last_draw});committed.social.tickets=1;emit(committed);
assert.equal(api.Inspect().pending,null);assert.equal(api.Inspect().rows[0].count,3);
assert.equal(nodes.CollectionGW2Result.text,'','A committed blessing uses its item highlight rather than a success announcement');assert(nodes['CollectionGW2Item_'+rows[0].id].BHasClass('CollectionGW2RewardHighlight'));assert(nodes.CollectionGW2Tickets.text.includes('福签：1'));
api.Select('ex');assert.equal(api.Inspect().rows[0].count,1,'A blessing draw does not alter another pool');api.Select('beast');
emit(packet(11));assert.equal(api.Inspect().rows[0].count,3,'Stale packets cannot undo the acquired reward');
emit(packet(13,[{path:['rows',1,'count'],value:4},{path:['social','tickets'],value:0}],{delta:1,base_sequence:12}));
assert.equal(api.Inspect().rows[0].count,4);assert(!nodes.CollectionGW2Draw.enabled,'No tickets disables drawing');
const before=draws().length;nodes.CollectionGW2Draw.events.onactivate();assert.equal(draws().length,before);
const full=rows.map(r=>({...r,count:r.target}));emit(packet(14,full));
assert(!nodes.CollectionGW2Draw.enabled);assert.equal(nodes.CollectionGW2DrawText.text,'已全部集满');
api.Open('wife');assert.equal(h.sent.at(-1).payload.category_id,'wife');assert.equal(api.Inspect().slots,0);assert(!nodes.CollectionGW2Draw.enabled,'Wife awaits its authoritative snapshot');
h.assertCleanDispose(api);
console.log('COLLECTION_BEAST_PASS: forty formal rewards, original caps/art/currency, one-page grid, search/tooltip, chunk/delta/stale authority, shared pending gate, reload and committed draw');
