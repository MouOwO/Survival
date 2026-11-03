"use strict";
// Actual UI index with instrumented cell reads. No DOM/native/elapsed-time or
// FPS claim: initialization, stable and dirty work are counted independently.
const assert=require("node:assert/strict"),fs=require("node:fs"),vm=require("node:vm");
const cfg={};let nativeWrites=0;
function panel(){return{style:{},visible:false,AddClass(){},SetHasClass(){}};}
vm.runInNewContext(fs.readFileSync("panorama/src/scripts/custom_game/survival_grid_state.js","utf8"),{
 GameUI:{CustomUIConfig:()=>cfg},$:{CreatePanel:()=>panel()}});
const api=cfg.SurvivalGridState;
function source(w,h,fill=0){
 const raw=Array(w*h).fill(fill),counts={reads:0};
 const states=new Proxy(raw,{get(target,key,receiver){if(typeof key==="string"&&/^\d+$/.test(key))counts.reads++;return Reflect.get(target,key,receiver);}});
 return{atlas:{size:64,x:-2,y:3,w,h,z:384,states,bulk_mode:true,empty_initial:true,revision:1,changes:[]},raw,counts};
}
function changed(fixture,entries){
 fixture.atlas.empty_initial=false;fixture.atlas.changes=entries.map(row=>row[0]);fixture.atlas.revision++;
 entries.forEach(([index,value])=>{fixture.raw[index]=value;});
}
function blocked(index,atlas,n){
 const x=(atlas.x+Math.floor(n/atlas.h)+.5)*atlas.size,y=(atlas.y+n%atlas.h+.5)*atlas.size;
 return Object.values(index.rects).some(r=>r&&x>r[0]&&x<r[2]&&y>r[1]&&y<r[3]);
}
function create(){return api.create({terrainHost:{},dynamicHost:{},footHost:{},project:p=>p,cameraKey:()=>"fixed",
 visibleBounds:()=>[-256,0,512,512],setStyle(p,key,value){nativeWrites++;p.style[key]=value;},cellSize:()=>64,zOffset:()=>0,viewport:()=>[800,600]});}
let checks=0;function test(name,fn){fn();checks++;console.log("ok",name);}
test("1x65536 and256x256 empty initialization/stability read zero cells",()=>{
 for(const [w,h]of[[1,65536],[256,256]]){
  const f=source(w,h);let index=api.patchBlocks(f.atlas,null,[]);
  assert.equal(f.counts.reads,0);assert.equal(Object.keys(index.rects).length,0);
  f.atlas.empty_initial=false;
  for(let n=0;n<1000;n++)index=api.patchBlocks(f.atlas,index,[]);
  assert.equal(f.counts.reads,0);assert.equal(index.block_visits,0);
 }
});
test("a word patch repairs only its aligned8cell blocks regardless of column height",()=>{
 const f=source(1,65536);let index=api.patchBlocks(f.atlas,null,[]);
 changed(f,Array.from({length:16},(_,n)=>[32761+n,n%3]));
 index=api.patchBlocks(f.atlas,index,f.atlas.changes);
 assert.equal(index.block_visits,3);assert.equal(f.counts.reads,24);
 for(let n=32750;n<32790;n++)assert.equal(blocked(index,f.atlas,n),f.raw[n]===1);
 const before=f.counts.reads;changed(f,[[32768,0]]);api.patchBlocks(f.atlas,index,f.atlas.changes);
 assert.equal(f.counts.reads-before,8);assert.equal(blocked(index,f.atlas,32768),false);
});
test("16scattered changed cells visit only16blocks, not the256x256 atlas",()=>{
 const f=source(256,256);const index=api.patchBlocks(f.atlas,null,[]);
 const entries=Array.from({length:16},(_,n)=>[n*256+17,1]);changed(f,entries);
 api.patchBlocks(f.atlas,index,f.atlas.changes);assert.equal(f.counts.reads,128);assert.equal(index.block_visits,16);
 entries.forEach(([n])=>assert.equal(blocked(index,f.atlas,n),true));
});
test("lazy adoption preserves old run pieces outside the dirty block",()=>{
 const f=source(1,64);f.atlas.bulk_mode=false;f.raw.fill(0);for(let n=3;n<14;n++)f.raw[n]=1;
 let index=api.patchColumns(f.atlas,null,[]);const before=f.counts.reads;
 changed(f,[[8,0]]);index=api.patchBlocks(f.atlas,index,[8]);
 assert.equal(f.counts.reads-before,8);
 for(let n=0;n<64;n++)assert.equal(blocked(index,f.atlas,n),f.raw[n]===1,"split run retains exact cell coverage"+n);
});
test("real create.configure avoids a hidden full dynamic-column rebuild during bulk",()=>{
 const state=create(),dynamic=source(1,65536,1);delete dynamic.atlas.bulk_mode;delete dynamic.atlas.empty_initial;
 state.ingestDynamic(dynamic.atlas);const dynamicBefore=dynamic.counts.reads;
 const f=source(1,65536);state.configure(f.atlas);
 assert.equal(f.counts.reads,0);assert.equal(dynamic.counts.reads,dynamicBefore);
 changed(f,[[32768,1]]);state.configure(f.atlas);
 assert.equal(dynamic.counts.reads-dynamicBefore,8);assert.equal(f.counts.reads,16,"8static +8dynamic-filter samples");
 const visits=state.stats.terrain_cell_visits,dynamicVisits=dynamic.counts.reads;
 for(let n=0;n<1000;n++)state.configure(f.atlas);
 assert.equal(state.stats.terrain_cell_visits,visits);assert.equal(dynamic.counts.reads,dynamicVisits);
});
test("four actual UI models own independent sparse indexes and reset independently",()=>{
 const states=Array.from({length:4},create),sources=states.map(()=>source(256,256));
 states.forEach((state,id)=>state.configure(sources[id].atlas));
 changed(sources[0],[[65535,1]]);states[0].configure(sources[0].atlas);
 assert.equal(states[0].stats.terrain_cell_visits,8);
 for(let id=1;id<4;id++){assert.equal(states[id].stats.terrain_cell_visits,0);assert.equal(sources[id].counts.reads,0);}
 states[0].reset();assert.equal(states[0].ready(),false);for(let id=1;id<4;id++)assert.equal(states[id].ready(),true);
});
test("unknown bulk must announce its empty baseline and invalid dirty IDs cannot be guessed",()=>{
 const f=source(1,65536);f.atlas.empty_initial=false;
 assert.throws(()=>api.patchBlocks(f.atlas,null,[]),/grid_bulk_empty_initial_required/);
 f.atlas.empty_initial=true;const index=api.patchBlocks(f.atlas,null,[]);f.atlas.empty_initial=false;
 assert.throws(()=>api.patchBlocks(f.atlas,index,[65536]),/grid_bulk_changed_cell_invalid/);
 assert.equal(f.counts.reads,0);
});
assert.equal(nativeWrites,0,"index updates never emit native styles or create draw work synchronously");
console.log("GRID_BULK_INDEX_PASS "+checks+" groups; O1 empty/idle; <=8 reads per dirty block; long columns and4UI owners; no native/FPS claim");
