'use strict';
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const {createHarness}=require('./tests/fixtures/menus_v10_harness.cjs');
const h=createHarness(),{cfg,nodes}=h;
cfg.ArchiveHandoff={Icon(){throw Error('Formal concubine rewards must resolve the shared icon registry');},Init(){},Observe(){}};
['common/item_resources.js','reward_presentation.js','ui_snapshot_cache.js','archive_parchment_data.js','archive_v10_semantics.js','common/archive_tooltip.js','collection_gw2_data.js','collection_gw2.js'].forEach(h.load);
const api=cfg.SurvivalCollection;
assert(nodes.CollectionGW2Tab_concubine,'The actual loaded collection view exposes a clickable salary-pool tab');
api.Open('beast');h.click(nodes.CollectionGW2Tab_concubine);
assert.equal(api.Inspect().category,'concubine');
assert(h.sent.some(r=>r.name==='survival_archive_request'&&r.payload.category_id==='concubine'),'The visible tab requests authoritative salary-pool data');
const grades=['N','R','SR','SSR','UR'];
const rows=grades.map((quality,i)=>({id:'concubine_0'+(i+1),name:['灯火守望者','林间药师','雾海旅人','星辰咏者','长夜之誓'][i],quality,count:i===0?1:0,count_known:1,target:60,max_owned:60,description:'攻击力 +'+(i+1)}));
h.emit('survival_archive_snapshot',{ok:1,category_id:'concubine',sequence:1,chunk:1,chunks:1,pending:0,rows,social:{tickets:3,currency_name:'工资',draw_cost:1,remaining:299,total:1}});
assert.equal(api.Inspect().slots,5);assert(api.Inspect().drawEnabled);assert.equal(nodes.CollectionGW2CurrencyName.text,'工资');
rows.forEach((row,i)=>{
 const data=cfg.SurvivalItemResources.Lookup(row);
 assert(data&&data.category_id==='concubine');assert.equal(data.quality,grades[i]);
 assert.equal(data.uri,cfg.SurvivalItemResources.Lookup('wife_0'+(i+1)).uri,'Existing portrait asset is reused');
 const card=nodes['CollectionGW2Item_'+row.id];assert(card&&card.events.onmouseover&&card.events.onmouseout);
 const position=card.GetPositionWithinWindow();h.setCursor(position.x+10,position.y+10);card.events.onmouseover();
 assert(api.Inspect().tooltipVisible,'Every new reward retains an immediately visible attribute tooltip');
 card.events.onmouseout();
});
h.click(nodes.CollectionGW2Draw);
const draws=h.sent.filter(r=>r.name==='survival_archive_social_draw');assert.equal(draws.length,1);assert.equal(draws[0].payload.pool_id,'concubine');
assert(api.Inspect().pending&&api.Inspect().pending.pool_id==='concubine');
h.click(nodes.CollectionGW2Draw);assert.equal(h.sent.filter(r=>r.name==='survival_archive_social_draw').length,1,'Pending draw cannot double-spend salary');
h.emit('survival_archive_social_result',{pool_id:'concubine',request_id:draws[0].payload.request_id,ok:false,terminal:true,error:'fixture_terminal'});
api.Close();h.assertCleanDispose(api);

const source=fs.readFileSync('panorama/src/scripts/custom_game/archive_180de7e38b_titles_compact_v6.js','utf8');
const begin=source.indexOf('    function refreshEndlessStatus()'),end=source.indexOf('    subscribe("survival_endless_state"',begin);assert(begin>=0&&end>begin);
const status={style:{},SetHasClass(name,value){this.hidden=value;}},state={latestEndlessState:null,endlessStatusPanel:null,endlessStatusHidden:null,endlessStatusText:'',valid:p=>!!p,panel:()=>status};
vm.runInNewContext(source.slice(begin,end),state);
for(const variant of ['endless','tower'])for(const running of [true,false]){
 state.latestEndlessState={variant,status:running?'running':'finished',wave:7,remaining:3,seconds:20,score:123,cleared:6};state.refreshEndlessStatus();
 assert(status.text.startsWith((variant==='tower'?'通天塔':'无尽')+(running?'第':'结束')));
}
console.log('ARCHIVE_CONCUBINE_UI_PASS: reachable collection tab, authoritative salary snapshot/draw, five shared portrait icons, immediate tooltip, duplicate-spend guard, disposal, endless/tower status');
