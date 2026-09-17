const fs=require('fs'),assert=require('assert/strict'),path=require('path');
const out=path.resolve(__dirname,'../output/survival_world_v2');
assert.equal(fs.readFileSync(path.join(out,'source_materials/transition_forest.vmat'),'utf8'),fs.readFileSync(path.join(out,'source_materials/transition_corrupt.vmat'),'utf8'),'Adjoining grass and paving must share their layer definitions');
const l=JSON.parse(fs.readFileSync(path.join(out,'layout.json'))),surface=JSON.parse(fs.readFileSync(path.join(out,'surface_design.json')));
function bounds(p){return [Math.min(...p.map(v=>v[0])),Math.min(...p.map(v=>v[1])),Math.max(...p.map(v=>v[0])),Math.max(...p.map(v=>v[1]))];}
const islands=l.land.filter(a=>a.nativeReuse),lake=l.waters.find(a=>a.name==='central_cross_shallows');
assert.equal(islands.length,4);assert(lake.shallow);assert.equal(lake.polygon.length,28);const [cx,cy]=surface.crossCenter,ib=bounds(islands.flatMap(a=>a.polygon)),lb=bounds(lake.polygon);
assert.equal(lb[2]-lb[0],4608);assert.equal(surface.crossWidth,1152);
assert.equal(l.rooms,20);assert.equal(l.markers.filter(m=>/^commandment_\d+_boss/.test(m.name)).length,10);assert.equal(l.markers.filter(m=>/^rebirth_/.test(m.name)).length,10);
assert.equal(surface.architecture,'continuous closed heightfield');
// Every 128-unit cell outside the native central rectangle must exist.
assert.equal(surface.meshAudit.reduce((n,c)=>n+c.topTriangles,0),(256*256-(surface.preserved[2]-surface.preserved[0])*(surface.preserved[3]-surface.preserved[1])/128**2)*2);
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
for(const axis of ['x','y'])for(let t=-2048;t<=2048;t+=128)tests.push({name:'shallow_'+axis+'_'+t,x:cx+(axis==='x'?t:0),y:cy+(axis==='y'?t:0),walk:true,shallow:true});
let lua="if GetMapName()~='survival_world_v2' then return end\nlocal tests={\n";
lua+=tests.map(t=>`{name='${t.name}',x=${t.x},y=${t.y},walk=${t.walk},shallow=${!!t.shallow}}`).join(',\n')+'\n}\n';
lua+=`local failures=0;local low=99999;local high=-99999\nfor _,t in ipairs(tests) do local p=Vector(t.x,t.y,500);local walk=GridNav:IsTraversable(p) and not GridNav:IsBlocked(p);local h=GetGroundHeight(p,nil);local ok=walk==t.walk;if not ok then failures=failures+1 end;if t.shallow then low=math.min(low,h);high=math.max(high,h) end;print('[WORLD_V2_CHECK]',t.name,ok and 'PASS' or 'FAIL',walk,h) end\nprint('[WORLD_V2_CHECK_TOTAL]',#tests,failures)\nprint('[WORLD_V2_SHALLOW_HEIGHT]',low,high,high-low<=4 and 'PASS' or 'FAIL')\nlocal horizontal=GridNav:CanFindPath(Vector(${cx-2176},${cy},384),Vector(${cx+2176},${cy},384));local vertical=GridNav:CanFindPath(Vector(${cx},${cy-2176},384),Vector(${cx},${cy+2176},384));print('[WORLD_V2_SHALLOW_PATH]',horizontal,vertical,horizontal and vertical and 'PASS' or 'FAIL')\nlocal upper=GetGroundHeight(Vector(-8602,13760,256),nil);local lower=GetGroundHeight(Vector(-8602,-6560,640),nil);print('[WORLD_V2_ELEVATION]',upper,lower,lower>upper and 'PASS' or 'FAIL')\n`;
for(const m of l.markers.filter(m=>/^n01_10_player_/.test(m.name)))lua+=`print('[WORLD_V2_CAMP_PATH]', '${m.name}', GridNav:CanFindPath(Vector(${m.x},${m.y},384),Vector(${cx},${cy},384)) and 'PASS' or 'FAIL')\n`;
for(const [name,x,y,expected] of [['dirt_paving',-12880,-7680,396],['grass_paving',-13156,9360,396],['grass_snow',11316,13120,524]])lua+=`do local lo=99999;local hi=-99999;for dx=-128,128,64 do local h=GetGroundHeight(Vector(${x}+dx,${y},700),nil);lo=math.min(lo,h);hi=math.max(hi,h) end; print('[WORLD_V2_TERRAIN_SEAM]','${name}',lo,hi,(hi-lo<=4 and math.abs(lo-${expected})<=4) and 'PASS' or 'FAIL') end\n`;
lua+=`do local h=GetGroundHeight(Vector(0,9000,700),nil);print('[WORLD_V2_SEA_BED]',h,(h>=254 and h<=256) and 'PASS' or 'FAIL') end\n`;
lua+=`do local p=Vector(0,-14000,800);local blocked=not GridNav:IsTraversable(p) or GridNav:IsBlocked(p);local h=GetGroundHeight(p,nil);print('[WORLD_V2_SPA]',h,blocked,(blocked and math.abs(h-640)<4) and 'PASS' or 'FAIL') end\n`;
const islandLevels=JSON.parse(fs.readFileSync(path.join(out,'island_levels_design.json')));
for(const f of islandLevels.flights){
 const vec=p=>`Vector(${p[0]},${p[1]},1000)`;
 lua+=`do local a=GetGroundHeight(${vec(f.attack)},nil);local l=GetGroundHeight(${vec(f.towerLeft)},nil);local r=GetGroundHeight(${vec(f.towerRight)},nil);print('[WORLD_V2_ISLAND_LEVELS]',${f.q},a,l,r,(math.abs(a-640)<4 and math.abs(l-768)<4 and math.abs(r-768)<4) and 'PASS' or 'FAIL') end\n`;
 lua+=`do local a=${vec(f.foot)};local b=${vec(f.landing)};local ok=GridNav:CanFindPath(a,b);local prev=0;local heights={};for i=0,24 do local p=a+(b-a)*(i/24);for _,offset in ipairs({-192,192}) do local side=p+Vector(-(b.y-a.y),b.x-a.x,0):Normalized()*offset;if not GridNav:IsTraversable(side) or GridNav:IsBlocked(side) then ok=false;print('[WORLD_V2_STAIR_EDGE]',${f.q},i,offset) end end;local h=GetGroundHeight(p,nil);table.insert(heights,math.floor(h));if not GridNav:IsTraversable(p) or GridNav:IsBlocked(p) or (i>0 and (h<prev-4 or h-prev>64)) then ok=false;print('[WORLD_V2_STAIR_DETAIL]',${f.q},i,p.x,p.y,h,prev,GridNav:IsTraversable(p),GridNav:IsBlocked(p)) end;prev=h end;print('[WORLD_V2_ISLAND_STAIRS]',${f.q},table.concat(heights,','),ok and 'PASS' or 'FAIL') end\n`;
}
// Probe travel lanes with a 192-unit inset from the sloping bank; edge cells are not fully walkable.
for(let q=0;q<4;q++){const c=Math.cos(q*Math.PI/2),s=Math.sin(q*Math.PI/2);lua+=`do local ok=true;local count=0;for r=128,2176,128 do local margin=384-256*math.max(0,math.min(1,(r-1152)/896));for _,v in ipairs({-margin,0,margin}) do local p=Vector(${cx}+r*${Math.round(c)}-v*${Math.round(s)},${cy}+r*${Math.round(s)}+v*${Math.round(c)},500);local h=GetGroundHeight(p,nil);count=count+1;if not GridNav:IsTraversable(p) or GridNav:IsBlocked(p) or math.abs(h-396)>4 then ok=false;print('[WORLD_V2_CHANNEL_DETAIL]',${q},r,v,h,GridNav:IsTraversable(p),GridNav:IsBlocked(p)) end end end;print('[WORLD_V2_CHANNEL_WIDTH]',${q},count,ok and 'PASS' or 'FAIL') end\n`;}
for(let q=0;q<4;q++){const island=require('./world_v2_original_island.cjs'),points=[-384,0,384].map(v=>island.worldPoint(2560,v,q));lua+=`do local left=GetGroundHeight(Vector(${points[0][0]},${points[0][1]},1000),nil);local middle=GetGroundHeight(Vector(${points[1][0]},${points[1][1]},1000),nil);local right=GetGroundHeight(Vector(${points[2][0]},${points[2][1]},1000),nil);print('[WORLD_V2_GATE_CHOKE]',${q},left,middle,right,(left>=764 and right>=764 and middle>396 and middle<640) and 'PASS' or 'FAIL') end\n`;}
// Probe the original eight lateral flights, separately from the water entrances.
for(let q=0;q<4;q++)for(const side of [-1,1]){
 // The restored lane occupies |v|=512..896. Three probe lanes at 640,736,832
 // leave 128 units from the tall inner shoulder and 64 from the outer edge.
 const island=require('./world_v2_original_island.cjs'),start=island.worldPoint(2368,side*736,q),end=island.worldPoint(3008,side*736,q),dir=island.worldPoint(0,96,q).map((v,i)=>v-island.center[i]);
 lua+=`do local a=Vector(${start[0]},${start[1]},1000);local b=Vector(${end[0]},${end[1]},1000);local hi=GetGroundHeight(a,nil);local lo=GetGroundHeight(b,nil);local ok=math.abs(hi-768)<4 and math.abs(lo-640)<4 and GridNav:CanFindPath(b,a);local prev=hi;local heights={};for i=0,20 do local p=a+(b-a)*(i/20);local h=GetGroundHeight(p,nil);table.insert(heights,math.floor(h));if h>prev+4 or prev-h>48 then ok=false end;prev=h;for _,offset in ipairs({-1,0,1}) do local v=p+Vector(${dir[0]},${dir[1]},0)*offset;if not GridNav:IsTraversable(v) or GridNav:IsBlocked(v) then ok=false;print('[WORLD_V2_TOWER_STAIR_DETAIL]',${q},${side},i,offset,GetGroundHeight(v,nil)) end end end;print('[WORLD_V2_TOWER_STAIRS]',${q},${side},table.concat(heights,','),ok and 'PASS' or 'FAIL') end\n`;
}
fs.writeFileSync(path.resolve(__dirname,'../scripts/vscripts/maps/survival_world_v2_verify.lua'),lua);
fs.writeFileSync(path.join(out,'geometry_verification.json'),JSON.stringify({islandExtent:[ib[2]-ib[0],ib[3]-ib[1]],crossExtent:[lb[2]-lb[0],lb[3]-lb[1]],runtimeSamples:tests.length,shallowSamples:tests.filter(t=>t.shallow).length,groundRoots:surface.groundRoots.length,result:'PASS'},null,2));
console.log('Geometry PASS; generated '+tests.length+' engine navigation samples.');
