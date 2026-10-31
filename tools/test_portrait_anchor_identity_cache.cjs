'use strict';
// Real portrait callbacks: positive caches must follow native identity changes.
const assert=require('node:assert/strict');
const {setup}=require('./test_combat_stats_callbacks.cjs');
function mark(p,value){p.__survivalPortraitDimmed=true;p.__survivalPortraitOriginalOpacity=value;p.values.opacity='0';}
const t=setup({portrait:true});t.api.portraitHide('prime');
const old=t.native(),oldGroup=old.GetParent().GetParent();oldGroup.SetParent(new t.Panel('Detached'));
old.values.opacity='0.01';const next=t.mountNative();mark(next,'0.6');
t.api.portraitHide('valid_but_detached_ancestor');assert.equal(next.values.opacity,'0.6');assert.equal(old.values.opacity,'0.01');
const q=setup({portrait:true});q.api.portraitHide('prime_main');q.native().values.opacity='0.01';
q.api.selectionEvent('query_unit_event',{PlayerID:0});q.jobs.clear();
q.api.portraitHide('query_missing_native_fallback');assert.equal(q.overlay.values.visibility,'collapse');assert.equal(q.native().values.opacity,'0.01','Missing query cannot mutate selected-hero leaf');
function query(parent,value){const node=new q.Panel('QueryUnitHeroPortrait',parent,'DOTAScenePanel');node.point={x:120,y:820};mark(node,value);return node;}
const branch=new q.Panel('QueryBranch',q.root),first=query(branch,'0.7');
q.api.portraitHide('late_query_no_new_event');assert.equal(first.values.opacity,'0.7');assert.equal(q.native().values.opacity,'0.01');
branch.SetParent(new q.Panel('DetachedQuery'));first.values.opacity='0.01';
const replacement=query(new q.Panel('QueryReplacementBranch',q.root),'0.8');q.api.portraitHide('query_ancestor_detached_alive');
assert.equal(replacement.values.opacity,'0.8');assert.equal(first.values.opacity,'0.01');assert.equal(q.native().values.opacity,'0.01');
console.log('PORTRAIT_ANCHOR_IDENTITY_PASS: main/query alive-detached ancestors, missing query nativefallback, late query without newevent; selected main remains untouched');
