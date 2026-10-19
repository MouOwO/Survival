'use strict';
const fs=require('fs'),path=require('path'),Module=require('module'),assert=require('node:assert/strict');
// Add a virtual clock only to an in-memory copy of the existing native-panel fixture.
// Production code and the shared fixture remain untouched.
const fixturePath=path.resolve('tools/tests/fixtures/menus_v10_harness.cjs');
let fixture=fs.readFileSync(fixturePath,'utf8');
for(const [before,after] of [
 ['let serial=0,steam=', 'let now=100000,serial=0,steam='],
 ['const item={id:++serial,delay,fn,guard,cancelled:false}', 'const item={id:++serial,at:now+delay*1000,delay,fn,guard,cancelled:false}'],
 ['const env={GameUI:', 'const env={Date:{now:()=>now},GameUI:'],
 ['return {cfg,nodes,root,sent,counts,scheduled,load,', `return {advance(ms){const until=now+ms;let count=0;while(true){scheduled.sort((a,b)=>a.at-b.at);if(!scheduled.length||scheduled[0].at>until)break;const job=scheduled.shift();now=job.at;if(!job.cancelled)job.fn();assert(++count<2000,'finite lifecycle scheduling only');}now=until;},cfg,nodes,root,sent,counts,scheduled,load,`]
]){assert(fixture.includes(before),'Timed fixture seam exists: '+before);fixture=fixture.replace(before,after);}
const loaded=new Module(fixturePath,module);loaded.filename=fixturePath;loaded.paths=Module._nodeModulePaths(path.dirname(fixturePath));loaded._compile(fixture,fixturePath);
const h=loaded.exports.createHarness(),{cfg,nodes}=h;let rewardFactories=0,rewardPlays=0;
cfg.ArchiveHandoff={Icon(){},Init(){},Observe(){}};
cfg.SurvivalUI.RewardFX={Create(){rewardFactories++;return {Play(){rewardPlays++},Clear(){},Dispose(){}}}};
['ui_snapshot_cache.js','archive_parchment_data.js','archive_v10_semantics.js','common/archive_tooltip.js','collection_gw2_data.js','collection_gw2.js'].forEach(h.load);
let api=cfg.SurvivalCollection,sequence=0;
const rows={ex:[{id:'ex_01',name:'胡桃',count:0,target:60,description:'效果'},{id:'ex_02',name:'甘雨',count:0,target:60,description:'效果'}],friend:[{id:'friend_01',name:'哆啦A梦',count:0,target:60,description:'效果'},{id:'friend_02',name:'路飞',count:0,target:60,description:'效果'}],wife:[{id:'wife_01',name:'老婆收藏样例1',count:0,target:60,description:'效果'},{id:'wife_02',name:'老婆收藏样例2',count:0,target:60,description:'效果'}],beast:[{id:'beast_01',name:'散魂钟',count:0,target:60,description:'效果'},{id:'beast_02',name:'瑞兽',count:0,target:60,description:'效果'}]};
const card=id=>nodes['CollectionGW2Item_'+id];
function highlighted(){return Object.values(nodes).filter(p=>p.IsValid()&&p.BHasClass('CollectionGW2RewardHighlight'));}
function plainSuccess(){assert(!/^(?:已)?获得[：:\s]/.test(nodes.CollectionGW2Result.text),'Successful draw never writes an acquired-item announcement');assert.equal(rewardFactories,0,'Collection never creates floating-text/particle feedback');assert.equal(rewardPlays,0);}
function send(pool,extra={}){h.emit('survival_archive_snapshot',{ok:1,category_id:pool,sequence:++sequence,chunk:1,chunks:1,rows:rows[pool].map(r=>({...r})),pending:0,social:{tickets:99,draw_cost:1,remaining:99,total:rows[pool].reduce((n,r)=>n+r.count,0)},...extra});}
function begin(pool){api.Open(pool);h.click(nodes.CollectionGW2Draw);return api.Inspect().pending;}
function ack(intent,extra={}){h.emit('survival_archive_social_result',{pool_id:intent.pool_id,request_id:intent.request_id,ok:true,terminal:true,...extra});}
function finish(intent,extra={}){rows[intent.pool_id][0].count++;send(intent.pool_id,{last_draw:{id:'game:social_draw:'+intent.request_id,pool_id:intent.pool_id,name:rows[intent.pool_id][0].name},...extra});if(api.IsOpen()&&api.Inspect().category===intent.pool_id&&!api.Inspect().pending)assert.equal(nodes.CollectionGW2Result.text,'','Success leaves no acquired-item announcement');}
function glow(p){return p.Children().find(c=>c.BHasClass('CollectionGW2RewardGlow'));}
function noHighlight(){assert.equal(highlighted().length,0);plainSuccess();}
Object.keys(rows).forEach(p=>send(p));api.Open('ex');noHighlight();
const first=begin('ex'),oldCard=card('ex_01');ack(first,{revision:10});assert(api.Inspect().pending);noHighlight();
finish(first,{revision:10});assert.equal(api.Inspect().pending,null);assert(!oldCard.IsValid());assert(card('ex_01').BHasClass('CollectionGW2RewardHighlight'));assert(!card('ex_02').BHasClass('CollectionGW2RewardHighlight'));assert.equal(api.Inspect().rows[0].count,1);plainSuccess();
const overlay=glow(card('ex_01'));assert(overlay,'The native card contains a non-text glass reflection');assert.equal(overlay.hittest,false);assert.equal(overlay.hittestchildren,false);assert.equal(overlay.paneltype,'Panel');assert(overlay.BHasClass('RewardGlassSurface'),'The winning card uses the shared clipped glass surface');
const sweep=overlay.Children().find(c=>c.BHasClass('RewardGlassSweep'));assert(sweep,'The native card contains the shared moving reflection band');assert.equal(sweep.paneltype,'Panel');assert.equal(sweep.hittest,false);assert.equal(sweep.hittestchildren,false);assert.equal(overlay.Children().length,1,'A single two-dimensional reflection band needs no particle scene or text');
ack(first,{revision:10,duplicate:true});send('ex',{revision:10,last_draw:{id:'game:social_draw:'+first.request_id,pool_id:'ex',name:'胡桃'}});h.advance(649);assert(card('ex_01').BHasClass('CollectionGW2RewardHighlight'),'The reflection retains its short native animation window');h.advance(2);noHighlight();
send('ex',{revision:10,last_draw:{id:'game:social_draw:'+first.request_id,pool_id:'ex',name:'胡桃'}});noHighlight();
for(const pool of ['friend','wife','beast']){const intent=begin(pool);finish(intent,{revision:11});assert.equal(api.Inspect().pending,null,'Committed snapshot can precede ACK');assert(card(rows[pool][0].id).BHasClass('CollectionGW2RewardHighlight'));ack(intent,{revision:11});plainSuccess();h.advance(700);noHighlight();}
const failure=begin('friend');ack(failure,{ok:false,terminal:false,pending:true,error:'暂时离线'});assert(api.Inspect().pending);noHighlight();ack(failure,{ok:false,terminal:true,error:'义帖不足'});assert.equal(api.Inspect().pending,null);assert.equal(nodes.CollectionGW2Result.text,'义帖不足');assert.equal(highlighted().length,0);
const closed=begin('ex');api.Close();finish(closed);assert.equal(api.Inspect().pending,null);assert.equal(highlighted().length,0);api.Open('ex');noHighlight();
const switched=begin('ex');api.Select('friend');finish(switched);assert.equal(api.Inspect().pending,null);noHighlight();assert(nodes.CollectionGW2Draw.enabled);api.Select('ex');noHighlight();
const reloaded=begin('friend'),oldCanvas=nodes.CollectionGW2Canvas;h.load('collection_gw2.js');api=cfg.SurvivalCollection;assert(!oldCanvas.IsValid());api.Open('friend');assert.equal(api.Inspect().pending.request_id,reloaded.request_id);ack(reloaded,{revision:20});finish(reloaded,{revision:20});assert(card('friend_01').BHasClass('CollectionGW2RewardHighlight'));plainSuccess();
h.load('collection_gw2.js');api=cfg.SurvivalCollection;api.Open('friend');ack(reloaded,{revision:20,duplicate:true});send('friend',{revision:20});h.advance(700);noHighlight();
const covered=begin('ex');ack(covered,{revision:30});finish(covered,{revision:30,last_draw:{id:'later-other-pool',pool_id:'beast',name:'其他奖励'}});assert.equal(api.Inspect().pending,null);noHighlight();assert(!nodes.CollectionGW2Result.text.includes('其他奖励'));
assert.equal(nodes.CollectionGW2Search,undefined,'The collection keeps the complete inventory visible without a search field');
const unfiltered=begin('ex');finish(unfiltered);assert.equal(api.Inspect().pending,null);assert.equal(api.Inspect().slots,rows.ex.length);assert(card('ex_01').BHasClass('CollectionGW2RewardHighlight'),'The committed reward remains visible for its glass sweep');plainSuccess();h.advance(700);noHighlight();
const filtered=begin('ex'),filteredDraws=h.sent.filter(event=>event.name==='survival_archive_social_draw').length;h.click(nodes.CollectionGW2OwnershipFilter);assert(api.Inspect().filterMenuOpen);assert.equal(api.Inspect().ownershipFilter,'all','Opening a dropdown never applies a different inventory filter');h.click(nodes.CollectionGW2FilterOption_unowned);assert.equal(api.Inspect().filterMenuOpen,false);
assert.equal(api.Inspect().ownershipFilter,'unowned');assert.equal(api.Inspect().pending.request_id,filtered.request_id,'Filtering during settlement preserves the original transaction nonce');assert.equal(filtered.counts.ex_01,rows.ex[0].count,'The pending intent captures the complete inventory before local filtering');assert.equal(api.Inspect().slots,1);assert.equal(api.Inspect().rows[0].id,'ex_02');
finish(filtered);assert.equal(api.Inspect().pending,null,'A filtered-out acquired card still settles from the complete authoritative snapshot');assert.equal(api.Inspect().slots,1);noHighlight();assert.equal(h.sent.filter(event=>event.name==='survival_archive_social_draw').length,filteredDraws,'Changing the filter never repeats the purchase');h.click(nodes.CollectionGW2OwnershipFilter);h.click(nodes.CollectionGW2FilterOption_all);assert.equal(api.Inspect().filterMenuOpen,false);assert.equal(api.Inspect().slots,rows.ex.length);noHighlight();
rows.ex[0].count_known=0;send('ex');const unknown=begin('ex');delete rows.ex[0].count_known;finish(unknown);assert.equal(api.Inspect().pending,null);noHighlight();
rows.ex[1].name='胡桃';send('ex');const ambiguous=begin('ex');rows.ex[1].count++;finish(ambiguous);assert.equal(api.Inspect().pending,null);noHighlight();rows.ex[1].name='甘雨';send('ex');
const rapid1=begin('ex');finish(rapid1);h.advance(200);const rapid2=begin('ex');finish(rapid2);assert(card('ex_01').BHasClass('CollectionGW2RewardHighlight'));h.advance(500);assert(card('ex_01').BHasClass('CollectionGW2RewardHighlight'),'An earlier draw cleanup cannot erase the next glass sweep');h.advance(200);noHighlight();
const rebuilt=begin('ex');finish(rebuilt);h.advance(300);const retired=card('ex_01');rows.ex[0].description='服务器补充效果';send('ex');assert(!retired.IsValid());assert(card('ex_01').BHasClass('CollectionGW2RewardHighlight'),'Inventory rebuild preserves a still-active glass sweep');h.advance(400);noHighlight();
const closePulse=begin('ex');finish(closePulse);assert(card('ex_01').BHasClass('CollectionGW2RewardHighlight'));api.Close();assert.equal(highlighted().length,0);api.Open('ex');noHighlight();
const switchPulse=begin('ex');finish(switchPulse);api.Select('friend');noHighlight();api.Select('ex');noHighlight();h.advance(700);noHighlight();
const sent=h.sent.length;h.assertCleanDispose(api);assert.equal(h.sent.length,sent,'Disposal cannot repeat a draw');assert.equal(rewardFactories,0);assert.equal(rewardPlays,0);
console.log('COLLECTION_REWARD_FEEDBACK_PASS: precise committed-card clipped glass sweep only; no particles, floating text, success announcement, or fallback; four pools including wife, ACK order, numeric updates, duplicate/failure/closure/reload/filtered authority/ambiguity, 650 ms expiry and rebuild safety');
