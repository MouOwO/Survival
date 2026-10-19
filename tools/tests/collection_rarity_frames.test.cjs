'use strict';
const fs=require('node:fs'),assert=require('node:assert/strict');
const {createHarness}=require('./fixtures/menus_v10_harness.cjs');
const h=createHarness(),{cfg,nodes}=h;
cfg.ArchiveHandoff={Icon(parent){const image=new h.root.constructor('Image',parent);image.SetImage('fixture://existing-character-portrait');},Init(){},Observe(){}};
for(const script of ['ui_snapshot_cache.js','archive_parchment_data.js','archive_v10_semantics.js','common/archive_tooltip.js','collection_gw2_data.js','collection_gw2.js'])h.load(script);
const colors={N:'#8fc47b',R:'#74c8f2',SR:'#b680ee',SSR:'#f5c65e',UR:'#ef5350'},pools=['ex','friend','wife','beast'];
let api=cfg.SurvivalCollection,sequence=0;
const rows={};
for(const pool of pools)rows[pool]=Object.keys(colors).map((quality,index)=>({id:pool+'_'+index,name:pool+' '+quality,quality,count:index?0:1,count_known:1,target:20,description:'原有收藏效果',...(index===3?{draw_enabled:0,availability_note:'待适配'}:{})}));
function send(pool,extra={}){h.emit('survival_archive_snapshot',{ok:1,category_id:pool,sequence:++sequence,chunk:1,chunks:1,pending:0,rows:rows[pool].map(row=>({...row})),social:{tickets:100,draw_cost:1,remaining:99,total:1},...extra});}
function card(row){return nodes['CollectionGW2Item_'+row.id];}
function part(panel,cls){const matches=panel.Children().filter(child=>child.BHasClass(cls));assert.equal(matches.length,1,cls+' is unique');return matches[0];}
function grade(row,quality=row.quality){
 const panel=card(row),color=colors[quality]||'#88939b';
 const frame=part(panel,'CollectionGW2SlotFrame');
 assert.equal(frame.style.border,'1px solid '+color,'The persistent rim identifies '+quality+' in '+api.Inspect().category);
 assert.equal(frame.__collectionNine.key,'slot');assert.equal(frame.__collectionNine.pieces.length,9,'Native slot artwork retains independent corners');assert.equal(frame.__collectionNine.pieces[4].style.backgroundImage,'none','The rarity rim leaves its portrait uncovered');
 assert.equal(part(panel,'CollectionGW2Hover').style.border,'1px solid '+color,'Hover retains '+quality+' rather than a generic highlight');
 const labels=panel.Children().filter(child=>child.BHasClass('CollectionGW2RarityLabel'));
 assert.equal(labels.length,colors[quality]?1:0,'Only recognized grades receive a rarity label');
 if(colors[quality]){assert.equal(labels[0].text,quality);assert.equal(labels[0].style.color,color);assert(panel.BHasClass('CollectionGW2Quality'+quality));}
 for(const cls of ['CollectionGW2SlotFrame','CollectionGW2Hover']){assert.equal(part(panel,cls).hittest,false);assert.equal(part(panel,cls).hittestchildren,false);}
 const glow=part(panel,'CollectionGW2RewardGlow');assert.equal(glow.style.position,'2px 2px 0px');assert.equal(glow.style.width,'74px');assert.equal(glow.style.height,'74px','Glass reflection cannot paint the two-pixel rim');
 assert.equal(panel.style.saturation,undefined,'Ownership never grays the rarity rim');assert.equal(panel.style.brightness,undefined);
 return panel;
}
for(const pool of pools){
 api.Open(pool);send(pool);
 for(const row of rows[pool]){
  const panel=grade(row),rim=part(panel,'CollectionGW2SlotFrame').style.border;
  panel.events.onmouseover();if(panel.events.onactivate)h.click(panel);assert.equal(part(panel,'CollectionGW2SlotFrame').style.border,rim);assert(!panel.Children().some(child=>child.BHasClass('CollectionGW2SlotSelection')),'Clicking a card cannot leave a selection overlay');
  assert.equal(panel.BHasClass('CollectionGW2Unowned'),row.count===0);
  assert.equal(panel.BHasClass('CollectionGW2Unavailable'),row.draw_enabled===0);
  if(row.draw_enabled===0){assert.equal(nodes['CollectionGW2Unavailable_'+row.id],undefined,'Unavailable cards retain their rarity label without an adaptation notice');assert(!panel.Children().some(child=>child.text==='待适配'));}
 }
 const cells=nodes.CollectionGW2GridBody.Children().slice(),before=h.counts.created;send(pool);assert.equal(h.counts.created,before,'Equal snapshots retain native cards');assert.deepEqual(nodes.CollectionGW2GridBody.Children(),cells);
 h.click(nodes.CollectionGW2Draw);const intent=api.Inspect().pending;assert(intent);
 rows[pool][0].count++;send(pool,{last_draw:{id:'rarity:social_draw:'+intent.request_id,pool_id:pool,name:rows[pool][0].name}});
 assert.equal(api.Inspect().pending,null);assert(grade(rows[pool][0]).BHasClass('CollectionGW2RewardHighlight'),'Winning glass feedback survives the rarity frame');
 h.flushFinite();assert(!grade(rows[pool][0]).BHasClass('CollectionGW2RewardHighlight'));
}
api.Select('wife');const old=card(rows.wife[0]);rows.wife[0].quality='UR';send('wife');assert(!old.IsValid(),'A server rarity change rebuilds the cell');grade(rows.wife[0]);
rows.wife[0].quality=' sr ';send('wife');grade(rows.wife[0],'SR');
for(const unknown of ['',null,'MSSR','legendary']){rows.wife[0].quality=unknown;send('wife');grade(rows.wife[0],unknown);}
rows.wife[0].quality='UR';rows.wife[0].count_known=0;send('wife');assert(grade(rows.wife[0]).BHasClass('CollectionGW2Unknown'),'Unknown ownership retains the authoritative grade');
const oldApi=api;h.load('collection_gw2.js');api=cfg.SurvivalCollection;api.Open('wife');grade(rows.wife[0]);assert.doesNotThrow(()=>oldApi.Open('ex'));assert.equal(api.Inspect().category,'wife','Retired instance cannot change current selection');
const css=fs.readFileSync('panorama/src/styles/custom_game/collection_gw2.css','utf8');
for(const state of ['Unowned','Unknown','Unavailable'])assert(new RegExp('\\.CollectionGW2'+state+' \\.CollectionGW2Portrait\\s*\\{[^}]*saturation:').test(css),state+' gray treatment applies solely to the portrait');
assert(!/\.CollectionGW2(?:Unowned|Unknown|Unavailable)\s*\{/.test(css),'Ownership and availability cannot desaturate the whole card');
assert(!/\.CollectionGW2Slot:hover\s*\{/.test(css),'Hover does not recolor the rarity rim through card-wide brightness');
const layer=cls=>Number(css.match(new RegExp('\\.'+cls+'\\s*\\{[^}]*z-index:\\s*(\\d+)'))?.[1]);
assert(layer('CollectionGW2SlotFrame')>layer('CollectionGW2RewardGlow'),'The permanent rim stays above the glass surface');
assert(!/\.CollectionGW2RewardHighlight[^{}]*\{[^}]*(?:border|saturation|brightness)\s*:/.test(css),'Acquisition feedback cannot replace rarity color');
h.assertCleanDispose(api);
console.log('COLLECTION_RARITY_FRAMES_PASS: five grades and neutral fallback in all four pools; preserved hover/unowned/pending/unknown/glass states without click selection; server grade refresh, equal-snapshot reuse and reload/disposal');
