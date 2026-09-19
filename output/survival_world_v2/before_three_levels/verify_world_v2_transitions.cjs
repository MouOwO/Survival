const fs=require('fs'),assert=require('assert/strict'),path=require('path');
const out=path.resolve(__dirname,'../output/survival_world_v2');
assert.equal(fs.readFileSync(path.join(out,'source_materials/transition_forest.vmat'),'utf8'),fs.readFileSync(path.join(out,'source_materials/transition_corrupt.vmat'),'utf8'),'Adjoining grass and paving must share their layer definitions');
const l=JSON.parse(fs.readFileSync(path.join(out,'layout.json'))),surface=JSON.parse(fs.readFileSync(path.join(out,'surface_design.json')));
function bounds(p){return [Math.min(...p.map(v=>v[0])),Math.min(...p.map(v=>v[1])),Math.max(...p.map(v=>v[0])),Math.max(...p.map(v=>v[1]))];}
const islands=l.land.filter(a=>a.nativeReuse),lake=l.waters.find(a=>a.name==='central_cross_shallows');
assert.equal(islands.length,4);assert(lake.shallow);assert.equal(lake.polygon.length,12);const [cx,cy]=surface.crossCenter,ib=[cx-4096,cy-4096,cx+4096,cy+4096],lb=bounds(lake.polygon);
assert.equal(lb[2]-lb[0],3584);assert.equal(surface.crossWidth,640);
assert.equal(l.rooms,20);assert.equal(l.markers.filter(m=>/^commandment_\d+_boss/.test(m.name)).length,10);assert.equal(l.markers.filter(m=>/^rebirth_/.test(m.name)).length,10);
assert.equal(surface.architecture,'continuous closed heightfield');
// Every 128-unit cell outside the preserved 70x70 central rectangle must exist.
assert.equal(surface.meshAudit.reduce((n,c)=>n+c.topTriangles,0),(256*256-70*70)*2);
assert(surface.canopyCount>500);
const sceneryFile=path.join(out,'scenery_design.json');
if(fs.existsSync(sceneryFile)){
 const scenery=JSON.parse(fs.readFileSync(sceneryFile));
 const library=new Set(require('./vpk_inspect.cjs').open('D:/steam/steamapps/common/dota 2 beta/game/dota/pak01_dir.vpk').entries.map(e=>e.path));
 for(const s of scenery.instances){assert(library.has(s.model+'_c'),'Unavailable scenery asset: '+s.model);assert(l.markers.every(m=>Math.hypot(s.x-m.x,s.y-m.y)>=scenery.markerClearance),'Scenery obstructs a gameplay marker');}
 assert(scenery.count>500);
}
const tests=l.markers.map(m=>({name:m.name,x:m.x,y:m.y,walk:true}));
tests.push({name:'mountain_northwest',x:-15500,y:15100,walk:false},{name:'mountain_south',x:0,y:-15100,walk:false});
for(const axis of ['x','y'])for(let t=-1536;t<=1536;t+=128)tests.push({name:'shallow_'+axis+'_'+t,x:cx+(axis==='x'?t:0),y:cy+(axis==='y'?t:0),walk:true,shallow:true});
let lua="if GetMapName()~='survival_world_v2' then return end\nlocal tests={\n";
lua+=tests.map(t=>`{name='${t.name}',x=${t.x},y=${t.y},walk=${t.walk},shallow=${!!t.shallow}}`).join(',\n')+'\n}\n';
lua+=`local failures=0;local low=99999;local high=-99999\nfor _,t in ipairs(tests) do local p=Vector(t.x,t.y,500);local walk=GridNav:IsTraversable(p) and not GridNav:IsBlocked(p);local h=GetGroundHeight(p,nil);local ok=walk==t.walk;if not ok then failures=failures+1 end;if t.shallow then low=math.min(low,h);high=math.max(high,h) end;print('[WORLD_V2_CHECK]',t.name,ok and 'PASS' or 'FAIL',walk,h) end\nprint('[WORLD_V2_CHECK_TOTAL]',#tests,failures)\nprint('[WORLD_V2_SHALLOW_HEIGHT]',low,high,high-low<=4 and 'PASS' or 'FAIL')\nlocal horizontal=GridNav:CanFindPath(Vector(${cx-1536},${cy},384),Vector(${cx+1536},${cy},384));local vertical=GridNav:CanFindPath(Vector(${cx},${cy-1536},384),Vector(${cx},${cy+1536},384));print('[WORLD_V2_SHALLOW_PATH]',horizontal,vertical,horizontal and vertical and 'PASS' or 'FAIL')\nlocal upper=GetGroundHeight(Vector(-8602,13760,256),nil);local lower=GetGroundHeight(Vector(-8602,-6560,640),nil);print('[WORLD_V2_ELEVATION]',upper,lower,lower>upper and 'PASS' or 'FAIL')\n`;
for(const m of l.markers.filter(m=>/^n01_10_player_/.test(m.name)))lua+=`print('[WORLD_V2_CAMP_PATH]', '${m.name}', GridNav:CanFindPath(Vector(${m.x},${m.y},384),Vector(${cx},${cy},384)) and 'PASS' or 'FAIL')\n`;
for(const [name,x,y,expected] of [['dirt_paving',-12880,-7680,396],['grass_paving',-13156,9360,396],['grass_snow',11316,13120,524]])lua+=`do local lo=99999;local hi=-99999;for dx=-128,128,64 do local h=GetGroundHeight(Vector(${x}+dx,${y},700),nil);lo=math.min(lo,h);hi=math.max(hi,h) end; print('[WORLD_V2_TERRAIN_SEAM]','${name}',lo,hi,(hi-lo<=4 and math.abs(lo-${expected})<=4) and 'PASS' or 'FAIL') end\n`;
lua+=`do local h=GetGroundHeight(Vector(0,9000,700),nil);print('[WORLD_V2_SEA_BED]',h,(h>=254 and h<=256) and 'PASS' or 'FAIL') end\n`;
fs.writeFileSync(path.resolve(__dirname,'../scripts/vscripts/maps/survival_world_v2_verify.lua'),lua);
lua+=`do local p=Vector(0,-14000,800);local blocked=not GridNav:IsTraversable(p) or GridNav:IsBlocked(p);local h=GetGroundHeight(p,nil);print('[WORLD_V2_SPA]',h,blocked,(blocked and math.abs(h-640)<4) and 'PASS' or 'FAIL') end\n`;
fs.writeFileSync(path.resolve(__dirname,'../scripts/vscripts/maps/survival_world_v2_verify.lua'),lua);
fs.writeFileSync(path.join(out,'geometry_verification.json'),JSON.stringify({islandExtent:[ib[2]-ib[0],ib[3]-ib[1]],crossExtent:[lb[2]-lb[0],lb[3]-lb[1]],runtimeSamples:tests.length,shallowSamples:tests.filter(t=>t.shallow).length,groundRoots:surface.groundRoots.length,result:'PASS'},null,2));
console.log('Geometry PASS; generated '+tests.length+' engine navigation samples, including 50 shallow crossings.');
