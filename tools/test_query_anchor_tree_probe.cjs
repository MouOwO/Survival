'use strict';
const assert=require('node:assert/strict');
const {setup}=require('./test_combat_stats_callbacks.cjs');
function fixture(tools,config){
 const commands=new Map();
 const t=setup({portrait:true,config,game:{IsInToolsMode:()=>tools,AddCommand:(name,fn)=>commands.set(name,fn)}});
 return Object.assign(t,{commands});
}
const ordinary=fixture(false);
assert(![...ordinary.commands.keys()].some(name=>name.startsWith('survival_query_anchor_tree_v1_')));
assert.equal(ordinary.cfg.SurvivalQueryAnchorTreeProbe,undefined);
const t=fixture(true),empty=new t.Panel('QueryContainer',t.root);
const active=new t.Panel('QueryContainer',new t.Panel('ActualNativeQuery',t.root));
const host=new t.Panel('PortraitContainer',new t.Panel('QueryVertical',active,'DOTAQueryUnitGuts'),'DOTAQueryUnitPortraitContainer');
const leaf=new t.Panel('QueryUnitHeroPortrait',host,'DOTAScenePanel');leaf.point={x:580,y:820};
const privateNode=new t.Panel('UnrelatedPrivateNode',t.root);
Object.defineProperty(privateNode,'text',{get(){throw Error('Census must not read UI text')}});
t.cfg.SurvivalSelectionResolver.Resolve=()=>{throw Error('Pure DOM census must not read player selection')};
const name=[...t.commands.keys()].find(name=>name.startsWith('survival_query_anchor_tree_v1_'));
assert(name);const nonce='a'.repeat(24),beforeJobs=t.jobs.size;
const callback=t.commands.get(name);callback(nonce);
assert.equal(t.jobs.size,beforeJobs,'no automatic or census timers');
function messages(tag){return t.messages.filter(line=>line.startsWith('['+tag+'] ')).map(line=>JSON.parse(line.slice(tag.length+3)));}
const begin=messages('QUERY_DOM_CENSUS_BEGIN'),end=messages('QUERY_DOM_CENSUS_END');
assert.equal(begin.length,1);assert.equal(end.length,1);assert.equal(begin[0].nonce,nonce);assert.equal(end[0].nonce,nonce);
assert.equal(begin[0].account_reads,0);assert.equal(begin[0].timers,0);assert.equal(end[0].truncated,false);
const leaves=messages('QUERY_DOM_CENSUS_LEAF');
assert.equal(leaves.filter(row=>row.leaf.id==='QueryContainer').length,2,'all same-ID containers retained as distinct rows');
const captured=leaves.find(row=>row.leaf.id==='QueryUnitHeroPortrait');assert(captured);
assert(messages('QUERY_DOM_CENSUS_CHAIN').some(row=>row.index===captured.index&&row.chain.some(node=>node.id==='ActualNativeQuery')));
assert(!t.messages.some(line=>line.includes('UnrelatedPrivateNode')),'unrelated node metadata/text is not exported');
const stale=t.cfg.SurvivalQueryAnchorTreeProbe.Run;t.api.shutdown('test');
const oldCount=t.messages.length;assert.equal(stale(nonce),false);assert.equal(t.messages.length,oldCount);
const shared=t.cfg,next=fixture(true,shared);
const newer=[...next.commands.keys()].find(key=>key.startsWith('survival_query_anchor_tree_v1_'));
assert(newer && newer!==name,'unique command survives same-millisecond HUD reload');
console.log('QUERY_ANCHOR_TREE_PROBE_PASS: Tools-only explicit DOM census, duplicate IDs, full ancestry, no text/account/selection reads, no timer, stale context refusal, unique reload command; no native execution');
