const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
let now=0,writes=0;
const shared={},panels=[],terrain={},dynamic={},foot={};
function panel(host){
 const p={host,visible:false,style:{},classes:new Set(),AddClass(c){this.classes.add(c);},
  SetHasClass(c,v){v?this.classes.add(c):this.classes.delete(c);}};
 panels.push(p);return p;
}
vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/survival_grid_state.js','utf8'),{
 GameUI:{CustomUIConfig:()=>shared},$:{CreatePanel:(_,host)=>panel(host)},Date:{now:()=>now}
});
const state=shared.SurvivalGridState.create({terrainHost:terrain,dynamicHost:dynamic,footHost:foot,
 project:p=>[p[0]+300,p[1]*0.5+200],cameraKey:()=> 'fixed',cellSize:()=>64,zOffset:()=>6,
 viewport:()=>[800,600],setStyle:(p,k,v)=>{p.style[k]=v;writes++;}});
const first='3|64|-1|-1|2|2|384|a9',changed='3|64|-1|-1|2|2|384|55';
const update=()=>state.update([0,0,384],{grid_footprint_x:2,grid_footprint_y:2},null);
const tiles=()=>panels.filter(p=>p.host===foot&&p.classes.has('FootprintTile')&&p.visible);
state.ingestDynamic(first);update();
assert.equal(tiles().filter(p=>p.classes.has('Blocked')).length,1);
const initialWrites=writes;
for(let i=0;i<200;i++){now=500+i;state.ingestDynamic(first);update();}
assert.equal(state.stats.dynamic_decodes,1,'identical delivery is not decoded again');
assert.equal(state.stats.dynamic_builds,1,'identical delivery does not rebuild the overlay/index');
assert.equal(state.stats.dynamic_reuses,200);
assert.equal(writes,initialWrites,'duplicate notifications leave actual paint and footprint layouts unchanged');
now=1600;update();
assert.equal(tiles().filter(p=>p.classes.has('Blocked')).length,1,'duplicate delivery extends freshness');
now=1700;update();
assert(tiles().every(p=>p.classes.has('Unknown')),'dynamic colors expire normally');
state.ingestDynamic(first);update();
assert.equal(tiles().filter(p=>p.classes.has('Blocked')).length,1,'same data restores colors after expiry');
assert.equal(state.stats.dynamic_builds,1);
state.ingestDynamic(changed);update();
assert.equal(tiles().filter(p=>p.classes.has('Blocked')).length,4,'new obstruction data is never skipped');
assert.equal(state.stats.dynamic_builds,2);
state.ingestDynamic('invalid');state.ingestDynamic(changed);update();
assert.equal(state.stats.dynamic_builds,2,'invalid payload cannot overwrite the valid cache key');
assert.equal(state.stats.dynamic_decodes,3);
assert(panels.some(p=>p.host===dynamic&&p.visible));
state.configure(changed);update();
assert.equal(state.stats.dynamic_builds,3,'late static atlas rebuilds even when dynamic payload is unchanged');
assert(!panels.some(p=>p.host===dynamic&&p.visible),'static red is not duplicated in the dynamic overlay');
state.configureLayout({bounds:{min_x:-512,min_y:-512,max_x:512,max_y:512},
 build_bounds:{min_x:0,min_y:0,max_x:256,max_y:256},height:384});
assert.equal(state.stats.dynamic_builds,4,'changed build bounds invalidate the cached overlay');
state.ingestDynamic(changed);update();
assert.equal(state.stats.dynamic_builds,4,'delivery after static changes uses the rebuilt overlay');
console.log('GRID_DYNAMIC_CACHE_PASS duplicate delivery, freshness/expiry, changed blockers, late atlas and bounds');
