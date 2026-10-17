'use strict';
const assert=require('node:assert/strict');
const {createHarness}=require('./fixtures/menus_v10_harness.cjs');
const h=createHarness(),{cfg,nodes}=h;
cfg.ArchiveHandoff={Icon(){},Init(){},Observe(){}};
for(const script of ['ui_snapshot_cache.js','archive_parchment_data.js','archive_v10_semantics.js','common/archive_tooltip.js','collection_gw2_data.js','collection_gw2.js'])h.load(script);
let sequence=0;
const api=cfg.SurvivalCollection;
function hover(pool,item){
 api.Open(pool);h.emit('survival_archive_snapshot',{ok:1,category_id:pool,sequence:++sequence,chunk:1,chunks:1,pending:0,rows:[{id:pool+'_rarity',name:'原角色名字',count:1,count_known:1,target:20,description:'保留原始效果\n全属性+100',quality:'SSR',...item}],social:{tickets:2,draw_cost:1,remaining:19,total:1}});
 nodes['CollectionGW2Item_'+pool+'_rarity'].events.onmouseover();
 return nodes.CollectionGW2TooltipRarity;
}
for(const pool of ['ex','friend','wife','beast']){
 const line=hover(pool,{draw_probability:0.0045,initial_draw_probability:0.001,quality_draw_probability:0.045});
 assert.equal(line.text,'品质 SSR · 当前抽取概率 0.45%','All collection categories show the server single-character probability, not its tier or initial chance');
 assert.equal(line.visible,true);assert.equal(line.style.color,'#f5c65e');assert.equal(line.style.fontSize,'15px');
 assert.equal(nodes.CollectionGW2TooltipTitle.style.color,'#f5c65e','The collection character name matches its SSR frame');
 assert(nodes.CollectionGW2TooltipState.text.includes('已拥有'),'The probability line does not replace ownership state');
 assert.equal(nodes.CollectionGW2TooltipEffect.text,'保留原始效果\n全属性+100','The imported original effect is preserved');
 const body=nodes.CollectionGW2TooltipBody,roles=body.Children().map(node=>node.id);
 assert(roles.indexOf(line.id)>roles.indexOf(nodes.CollectionGW2TooltipState.id));assert(roles.indexOf(line.id)<roles.indexOf(nodes.CollectionGW2TooltipSeparator.id),'Rarity sits adjacent to existing ownership information');
}
const qualityColors={UR:'#ef5350',SSR:'#f5c65e',SR:'#b680ee',R:'#74c8f2',N:'#8fc47b'};
for(const pool of ['ex','friend','wife','beast'])for(const [quality,color]of Object.entries(qualityColors)){
 hover(pool,{quality,draw_probability:0.01});
 assert.equal(nodes.CollectionGW2TooltipTitle.style.color,color,'Character names track consecutive quality changes in '+pool);
}
assert.equal(hover('wife',{draw_probability:0}).text,'品质 SSR · 当前抽取概率 0.00%','A real zero probability is not treated as missing');
assert.equal(hover('wife',{count:20,draw_probability:0}).text,'品质 SSR · 当前抽取概率 0.00%','Full entries retain an honest zero chance');
assert.equal(hover('wife',{draw_probability:1}).text,'品质 SSR · 当前抽取概率 100.00%');
assert.equal(hover('wife',{draw_probability:0.000000001}).text,'品质 SSR · 当前抽取概率 <0.01%','Positive rare chances never round down to an apparent zero');
assert.equal(hover('wife',{quality:' ur ',draw_probability:'0.005'}).text,'品质 UR · 当前抽取概率 0.50%');assert.equal(nodes.CollectionGW2TooltipRarity.style.color,'#ef5350');
for(const missing of [undefined,null,'',false,true,NaN,-0.5,1.01,'not-a-number']){
 const line=hover('wife',{draw_probability:missing,initial_draw_probability:0.125});assert.equal(line.text,'品质 SSR','Missing/invalid current authority never falls back to initial chance: '+String(missing));
}
const pending=hover('wife',{draw_enabled:0,draw_probability:0.005,availability_note:'待适配，暂不参与抽取，不消耗玫瑰'});
assert.equal(nodes.CollectionGW2TooltipTitle.style.color,qualityColors.SSR,'Pending characters still keep their quality name color');
assert.equal(pending.text,'品质 SSR · 暂不参与抽取');assert(nodes.CollectionGW2TooltipState.text.includes('已拥有'));assert(!nodes.CollectionGW2TooltipState.text.includes('待适配'));assert.equal(nodes.CollectionGW2TooltipCondition.text,'待适配，暂不参与抽取，不消耗玫瑰');assert.equal(nodes.CollectionGW2TooltipEffect.text,'保留原始效果\n全属性+100');
const unknown=hover('wife',{quality:'UNCONFIGURED',draw_probability:0.25});assert.equal(unknown.text,'当前抽取概率 25.00%','Unknown grades are not invented');
const defaultTitleColor=nodes.CollectionGW2TooltipTitle.style.color;
assert(!Object.values(qualityColors).includes(defaultTitleColor),'Unknown names reset to the default title color after a graded hover');
assert.equal(hover('wife',{quality:'',draw_probability:undefined}).visible,false,'No row is shown without recognized grade or probability');
api.Close();
const anchor=new h.root.constructor('Panel',h.root,'NormalArchiveAnchor');anchor.style.width='100px';anchor.style.height='78px';
const normal=cfg.SurvivalArchiveTooltip.Create({parent:h.root,root:h.root,idPrefix:'OrdinaryArchiveProbe'});
assert.equal(nodes.OrdinaryArchiveProbeRarity,undefined,'Normal archive tooltips do not gain any extra layout node');
const item={id:'map_1',name:'普通档案',count:2,target:3,description:'原有普通效果',quality:'UR',draw_probability:1};
assert(normal.Show(item,'map_level',anchor,false));assert.equal(normal.elements.Effect.text,'原有普通效果');assert(normal.elements.State.text.includes('map_level'));assert(!normal.elements.State.text.includes('抽取概率'));
assert.equal(normal.elements.Title.style.color,defaultTitleColor,'Ordinary archive names keep their original title color');
normal.Hide();assert(normal.Show(item,'wife',anchor,false),'Non-collection callers keep their old layout even for social rows');assert(!normal.elements.State.text.includes('品质'));assert.equal(nodes.OrdinaryArchiveProbeRarity,undefined);normal.Dispose();
const opted=cfg.SurvivalArchiveTooltip.Create({parent:h.root,root:h.root,idPrefix:'CollectionOnlyProbe',collectionRarity:true});
assert(opted.Show(item,'map_level',anchor,false));assert.equal(opted.elements.Rarity.visible,false,'Opted-in controllers still restrict the line to the four collections');opted.Hide();assert(opted.Show(item,'wife',anchor,true));assert.equal(opted.elements.Rarity.visible,false,'Effect-only tooltips remain effect-only');opted.Dispose();
h.assertCleanDispose(api);
console.log('COLLECTION_RARITY_TOOLTIP_PASS: four pools show authoritative single-character chance; zero/tiny/missing/invalid/pending states; imported effects and ordinary archive layouts preserved');
