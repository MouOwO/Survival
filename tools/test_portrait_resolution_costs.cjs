'use strict';
// Same production entry points with 0/10,000 unrelated HUD nodes. No native IO.
const assert=require('node:assert/strict');
const {fixture}=require('./test_portrait_resolution_layout.cjs');
const measured=[];
for(const noise of [0,10000]){
 const f=fixture({height:900,noise});assert.equal(f.enter(),f.t.native());
 const initial={...f.m};
 assert.equal(f.t.api.portraitUpdate(f.snapshot),true);
 assert.equal(f.t.api.portraitUpdate(f.snapshot),true);
 const stableOne=f.stable(1,true),stable300=f.stable(300,true),stable10000=f.stable(10000,true);
 for(const stable of [stableOne,stable300,stable10000]){
  assert.equal(stable.rootFind,0,'Stable rendering must not repeat root discovery');
  assert.equal(stable.writes,0,'Unchanged native state must not be written repeatedly');
 }
 // Existing overlay-local lookups remain bounded; scene/HUD population is irrelevant.
 assert(stableOne.recursiveVisits<=12,'Overlay-local traversal budget exceeded');
 assert(stableOne.parent<=34);assert(stableOne.valid<=60);
 assert(stableOne.childCount<=4);assert(stableOne.position<=8);
 assert(stableOne.layoutReads<=30,'Fixed layout-read budget exceeded');
 measured.push({unrelated_nodes:noise,initial_selection:initial,stable_one:stableOne,stable300,stable10000});
}
assert.deepEqual(measured[0].stable_one,measured[1].stable_one);
assert.deepEqual(measured[0].stable300,measured[1].stable300);
assert.deepEqual(measured[0].stable10000,measured[1].stable10000);
// A negative result stays quiet until the remembered leaf's real layout changes.
{
 const f=fixture({height:1000,noise:10000});f.t.native().actualuiscale_x=f.t.native().actualuiscale_y=0;
 assert.equal(f.enter(),null);const negative=f.stable(10000);
 assert.equal(negative.rootFind,0);assert.equal(negative.recursiveVisits,0);assert.equal(negative.writes,0);
 f.t.native().actualuiscale_x=f.t.native().actualuiscale_y=1000/1080;f.clear();
 assert.equal(f.t.api.portraitAnchor(),f.t.native());assert.equal(f.m.rootFind,1);
 const recovery={...f.m},recovered=f.stable(10000);
 assert.equal(recovered.rootFind,0);assert.equal(recovered.recursiveVisits,0);assert.equal(recovered.writes,0);
 measured.push({case:'missing_main_layout_change',negative_10000:negative,recovery,recovered_10000:recovered});
}
console.log(JSON.stringify({status:'PORTRAIT_RESOLUTION_COSTS_PASS',scope:'SYNTHETIC_PRODUCTION_CALL_COUNTS_NOT_NATIVE_FPS',measured}));
