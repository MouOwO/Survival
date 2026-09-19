const fs=require('fs'),assert=require('assert/strict'),path=require('path');
const out=path.resolve(__dirname,'../output/survival_world_v2');
const l=JSON.parse(fs.readFileSync(path.join(out,'layout.json'))),surface=JSON.parse(fs.readFileSync(path.join(out,'surface_design.json')));
function bounds(p){return [Math.min(...p.map(v=>v[0])),Math.min(...p.map(v=>v[1])),Math.max(...p.map(v=>v[0])),Math.max(...p.map(v=>v[1]))];}
const island=l.land.find(a=>a.name==='n01_10_island'),lake=l.waters.find(a=>a.name==='central_square_lake');
const ib=bounds(island.polygon),lb=bounds(lake.polygon),cx=(ib[0]+ib[2])/2,cy=(ib[1]+ib[3])/2;
assert(Math.abs(ib[2]-ib[0]-(ib[3]-ib[1]))<.001);assert(Math.abs(lb[2]-lb[0]-2048)<.001);assert(Math.abs(lb[3]-lb[1]-2048)<.001);assert(lake.shallow);
for(const p of island.polygon)assert(Math.abs(Math.hypot(p[0]-cx,p[1]-cy)-4608)<.001);
assert.equal(l.rooms,20);assert.equal(l.markers.filter(m=>/^commandment_\d+_boss/.test(m.name)).length,10);assert.equal(l.markers.filter(m=>/^rebirth_/.test(m.name)).length,10);
const tests=l.markers.map(m=>({name:m.name,x:m.x,y:m.y,walk:true}));
tests.push({name:'mountain_northwest',x:-15500,y:15100,walk:false},{name:'mountain_south',x:0,y:-15100,walk:false});
for(const axis of ['x','y'])for(let t=-1536;t<=1536;t+=128)tests.push({name:'shallow_'+axis+'_'+t,x:cx+(axis==='x'?t:0),y:cy+(axis==='y'?t:0),walk:true,shallow:true});
let lua="if GetMapName()~='survival_world_v2' then return end\nlocal tests={\n";
lua+=tests.map(t=>`{name='${t.name}',x=${t.x},y=${t.y},walk=${t.walk},shallow=${!!t.shallow}}`).join(',\n')+'\n}\n';
lua+=`local failures=0;local low=99999;local high=-99999\nfor _,t in ipairs(tests) do local p=Vector(t.x,t.y,500);local walk=GridNav:IsTraversable(p) and not GridNav:IsBlocked(p);local h=GetGroundHeight(p,nil);local ok=walk==t.walk;if not ok then failures=failures+1 end;if t.shallow then low=math.min(low,h);high=math.max(high,h) end;print('[WORLD_V2_CHECK]',t.name,ok and 'PASS' or 'FAIL',walk,h) end\nprint('[WORLD_V2_CHECK_TOTAL]',#tests,failures)\nprint('[WORLD_V2_SHALLOW_HEIGHT]',low,high,high-low<=4 and 'PASS' or 'FAIL')\nlocal horizontal=GridNav:CanFindPath(Vector(${cx-1536},${cy},384),Vector(${cx+1536},${cy},384));local vertical=GridNav:CanFindPath(Vector(${cx},${cy-1536},384),Vector(${cx},${cy+1536},384));print('[WORLD_V2_SHALLOW_PATH]',horizontal,vertical,horizontal and vertical and 'PASS' or 'FAIL')\nlocal upper=GetGroundHeight(Vector(-8602,13760,256),nil);local lower=GetGroundHeight(Vector(-8602,-6560,640),nil);print('[WORLD_V2_ELEVATION]',upper,lower,lower>upper and 'PASS' or 'FAIL')\n`;
fs.writeFileSync(path.resolve(__dirname,'../scripts/vscripts/maps/survival_world_v2_verify.lua'),lua);
fs.writeFileSync(path.join(out,'geometry_verification.json'),JSON.stringify({islandDiameter:[ib[2]-ib[0],ib[3]-ib[1]],lakeSize:[lb[2]-lb[0],lb[3]-lb[1]],runtimeSamples:tests.length,shallowSamples:tests.filter(t=>t.shallow).length,groundRoots:surface.groundRoots.length,result:'PASS'},null,2));
console.log('Geometry PASS; generated '+tests.length+' engine navigation samples, including 50 shallow crossings.');
