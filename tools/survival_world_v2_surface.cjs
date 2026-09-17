// Continuous closed terrain; original central islands keep their native detail.
const clamp=v=>Math.max(0,Math.min(1,v));
const smooth=v=>{v=clamp(v);return v*v*(3-2*v);};
function edgeDistance(x,y,p){let d=Infinity;for(let i=0;i<p.length;i++){const a=p[i],b=p[(i+1)%p.length],dx=b[0]-a[0],dy=b[1]-a[1],t=clamp(((x-a[0])*dx+(y-a[1])*dy)/(dx*dx+dy*dy||1));d=Math.min(d,Math.hypot(x-a[0]-dx*t,y-a[1]-dy*t));}return d;}
function variation(x,y){const wx=x+140*Math.sin(y/479),wy=y+110*Math.cos(x/563);return clamp(.5+.22*Math.sin(wx/340+wy/513)+.15*Math.cos(wy/257-wx/617)+.09*Math.sin(wx/93+wy/137));}
function theme(a){if(!a)return 'forest';if(a.name.includes('n41_50_camp'))return 'thaw';if(a.material===M.snow||a.name.includes('polar_crystal')||a.name.includes('ice_elegy'))return 'snow';if(a.material===M.lava)return 'volcanic';if(a.material===M.corrupt)return 'corrupt';return 'forest';}
const level=a=>Math.round(a.z/128)*128;
const preserved=originalIsland.preserved;
function nativePreserved(x,y){return x>=preserved[0]&&x<=preserved[2]&&y>=preserved[1]&&y<=preserved[3];}
function rawSurface(x,y){const a=at(x,y);if(a)return a.material===M.water&&!a.shallow?254:Math.round(a.z/128)*128+12;
 const gx=clamp((x+16384)/32768)*128,gy=clamp((y+16384)/32768)*128,ix=Math.min(127,Math.floor(gx)),iy=Math.min(127,Math.floor(gy)),u=gx-ix,v=gy-iy;
 return ((heights[iy*129+ix]*(1-u)+heights[iy*129+ix+1]*u)*(1-v)+(heights[(iy+1)*129+ix]*(1-u)+heights[(iy+1)*129+ix+1]*u)*v)*128+12;}
const hotSpring={x:0,y:-14000,rx:850,ry:560,bed:640,water:704,rim:740};
function springRadius(x,y){return Math.hypot((x-hotSpring.x)/hotSpring.rx,(y-hotSpring.y)/hotSpring.ry);}
function terrainHeight(x,y){let h=0;for(let j=-1;j<=1;j++)for(let i=-1;i<=1;i++)h+=rawSurface(x+i*128,y+j*128)*(i===0?2:1)*(j===0?2:1);h/=16;
 const r=springRadius(x,y);if(r>=2.3)return h;
 const basin=hotSpring.bed+(hotSpring.rim-hotSpring.bed)*smooth((r-.80)/.45);
 return basin*(1-smooth((r-1.65)/.65))+h*smooth((r-1.65)/.65);}
function surface(x,y){return nativePreserved(x,y)?originalIsland.round.height(x,y):terrainHeight(x,y);}
// Index extends outside each polygon so the blend straddles the old hard boundary.
const paintBins=new Map();
for(const a of terrainPaint){if(a.nativeReuse||a.material===M.water)continue;for(let y=Math.floor((a.bb[1]-960)/512);y<=Math.floor((a.bb[3]+960)/512);y++)for(let x=Math.floor((a.bb[0]-960)/512);x<=Math.floor((a.bb[2]+960)/512);x++){const key=x+','+y;if(!paintBins.has(key))paintBins.set(key,[]);paintBins.get(key).push(a);}}
function nearbyPaint(x,y){return paintBins.get(Math.floor(x/512)+','+Math.floor(y/512))||[];}
function localTheme(x,y){const shapes=nearbyPaint(x,y);for(let i=shapes.length-1;i>=0;i--){const a=shapes[i];if(a.name!=='paving'&&inside(x,y,a.polygon))return (a.combatArt?'martial_':'')+theme(a);}return 'forest';}
const paletteNames=['forest','snow','thaw','volcanic','corrupt','martial_forest','martial_snow','martial_volcanic','ridge'],paintCache=new Map();
function mountainWeight(x,y){
 if(at(x,y)||springRadius(x,y)<2.3)return 0;
 let d=Infinity;for(const a of nearbyPaint(x,y))d=Math.min(d,edgeDistance(x,y,a.polygon));
 return smooth((d-160)/480);
}
function continuousPaint(v,m){if(m>=paletteNames.length)return [0,0,0,0];const [x,y]=v,key=x+','+y+','+m;if(paintCache.has(key))return paintCache.get(key);
 if(m===8){const slope=Math.hypot(terrainHeight(x+64,y)-terrainHeight(x-64,y),terrainHeight(x,y+64)-terrainHeight(x,y-64))/128,weight=mountainWeight(x,y);return [weight,weight*.14*(1-smooth(slope)),0,0];}
 const martial=paletteNames[m].startsWith('martial_'),t=paletteNames[m].replace('martial_',''),n=variation(x,y),shapes=nearbyPaint(x,y);let w=[.08+.14*n,0,0],seam=1;
 for(const a of shapes){const own=theme(a),d=edgeDistance(x,y,a.polygon),within=inside(x,y,a.polygon),signed=within?d:-d;
  // Both sides meet on the identical rock layer. The unpainted margin exceeds
  // the mesh half diagonal, so switching material cannot expose a straight seam.
  if(a.combatArt&&own!=='forest')seam=Math.min(seam,smooth((d-96)/260));
  const compatible=['forest','corrupt'].includes(own)&&['forest','corrupt'].includes(t);
  if(a.name!=='paving'&&own!==t&&!compatible){seam=Math.min(seam,smooth((d-24)/260));continue;}
  const alpha=smooth((signed+480+(n-.5)*720)/1080);if(!alpha)continue;let target;
  if(t==='snow')target=[1,0,0];else if(t==='thaw')target=[1,0,0];else if(t==='volcanic')target=martial?[1,.35+.25*n,0]:[.58+.30*(1-n),1,0];
  else if(a.material===M.dirt)target=[0,1,0];else if(a.material===M.paving||a.material===M.stone||a.material===M.corrupt)target=[0,0,1];else target=martial?[.65,.25,0]:[1,0,0];
  w=w.map((v,i)=>v*(1-alpha)+target[i]*alpha);
  if(t==='forest'&&a.material===M.dirt){const fringe=2.0*alpha*(1-alpha);w=w.map((v,i)=>v*(1-fringe)+(i===0?.45:0)*fringe);}
 }
 if(t!=='forest'&&t!=='corrupt'){let edge=0;for(const a of shapes)if(theme(a)===t&&inside(x,y,a.polygon))edge=Math.max(edge,smooth((edgeDistance(x,y,a.polygon)-12)/260));seam*=edge;}
 // TI10's grass reveal has a full 0..1 range; the old long-grass mask was nearly black.
 // Keep fractional stone/grass weights instead of forcing stone to 100%.
 const sr=springRadius(x,y);if(sr<1.65)w=[.20*smooth((sr-1.08)/.5),0,0];
 // A flat shared stone/earth shoulder joins biome materials. The identical
 // layer 3 in every palette avoids the previous exposed cliff-texture frame.
 const slope=Math.hypot(terrainHeight(x+64,y)-terrainHeight(x-64,y),terrainHeight(x,y+64)-terrainHeight(x,y-64))/128;
 const shoulder=(1-smooth((slope-.2)/.9))*.18;
 const result=[w[0]*seam,w[1]*seam,w[2]*seam+shoulder*(1-seam),0];paintCache.set(key,result);return result;
}
const gridStep=128,chunkCells=16,meshAudit=[];
for(let cy=0;cy<256;cy+=chunkCells)for(let cx=0;cx<256;cx+=chunkCells){const verts=[],faces=[],ids=new Map(),boundary=new Map();
 function vertex(gx,gy){const key=gx+','+gy;if(ids.has(key))return ids.get(key);const x=-16384+gx*gridStep,y=-16384+gy*gridStep,id=verts.length;verts.push([x,y,terrainHeight(x,y)]);ids.set(key,id);return id;}
 function triangle(v,m){faces.push({v,m});for(let i=0;i<3;i++){const a=v[i],b=v[(i+1)%3],reverse=b+','+a;if(boundary.has(reverse))boundary.delete(reverse);else boundary.set(a+','+b,[a,b]);}}
 for(let gy=cy;gy<cy+chunkCells;gy++)for(let gx=cx;gx<cx+chunkCells;gx++){const x=-16384+(gx+.5)*gridStep,y=-16384+(gy+.5)*gridStep;if(nativePreserved(x,y))continue;const a=vertex(gx,gy),b=vertex(gx+1,gy),c=vertex(gx+1,gy+1),d=vertex(gx,gy+1);const slope=Math.hypot(terrainHeight(x+64,y)-terrainHeight(x-64,y),terrainHeight(x,y+64)-terrainHeight(x,y-64))/128,m=paletteNames.indexOf(mountainWeight(x,y)>0?'ridge':localTheme(x,y));triangle([a,b,c],m);triangle([a,c,d],m);}
 if(!faces.length)continue;const topFaces=faces.length,bottoms=new Map(),edges=[...boundary.values()],center=verts.length;verts.push([-16384+(cx+8)*gridStep,-16384+(cy+8)*gridStep,-512]);
 function bottom(id){if(!bottoms.has(id)){bottoms.set(id,verts.length);verts.push([verts[id][0],verts[id][1],-512]);}return bottoms.get(id);}
 for(const [a,b] of edges){const ba=bottom(a),bb=bottom(b);faces.push({v:[b,a,ba,bb],m:paletteNames.length},{v:[center,bb,ba],m:paletteNames.length});}
 normalVertex=v=>{const dx=(terrainHeight(v[0]+64,v[1])-terrainHeight(v[0]-64,v[1]))/128,dy=(terrainHeight(v[0],v[1]+64)-terrainHeight(v[0],v[1]-64))/128,l=Math.hypot(dx,dy,1);return [-dx/l,-dy/l,1/l];};
 paintVertex=continuousPaint;mesh(verts,faces,[...paletteNames.map(t=>'materials/survival_world_v2/transition_'+t+'.vmat'),'materials/tools/toolsnodraw.vmat'],'255 255 255 255');paintVertex=null;normalVertex=null;meshAudit.push({chunk:[cx,cy],vertices:verts.length,topTriangles:topFaces});
}
// Keep the original native sea across every water region, at one common tile level.
const shallow=terrainPaint.find(a=>a.shallow);
if(shallow){prism(shallow.polygon,396,370,'materials/survival_world_v2/transition_forest.vmat','materials/tools/toolsnodraw.vmat','255 255 255 255');}
// INSERT NATIVE ISLAND MATERIALS
// Four real stair flights: shallow cross -> lower courtyard / wall approach.
// Retain the source's higher U arms and their original lateral stair entrances.
const islandLevels=originalIsland.levels,islandFlights=[];
// INSERT ISLAND FOUNDATION
for(let q=0;q<4;q++){
 const n=16,run=(islandLevels.stairEnd-islandLevels.stairStart)/n,half=islandLevels.stairWidth/2;
 const point=(r,v)=>originalIsland.worldPoint(r+islandLevels.outward,v,q);
 for(let i=0;i<n;i++){
  const r=islandLevels.stairStart+i*run,z=islandLevels.bed+(islandLevels.attack-islandLevels.bed)*(i+1)/n;
  const p=[[r,-half],[r+run,-half],[r+run,half],[r,half]].map(v=>point(...v));
  nativeIslandPrism(p,z,360,'stair');
 }
 const landingPad=[[2304,-half],[2560,-half],[2560,half],[2304,half]].map(v=>point(...v));
 // Cover the original cliff's non-walkable collision surface as well as its
 // visual seam; placing this cap underneath it leaves a blocked nav cell.
 nativeIslandPrism(landingPad,islandLevels.attack+2,360,'stair');
 const attack=originalIsland.transform(512,128,q),towerLeft=originalIsland.worldPoint(3200,1100,q),towerRight=originalIsland.worldPoint(3200,-1100,q);
 const landing=point(2560,0),foot=point(1750,0);
 islandFlights.push({q,foot,landing,attack,towerLeft,towerRight,steps:n});
 entity('info_target','n01_10_wall_approach_'+q,[...landing,islandLevels.attack]);
 entity('info_target','n01_10_tower_left_'+q,[...towerLeft,islandLevels.tower]);
 entity('info_target','n01_10_tower_right_'+q,[...towerRight,islandLevels.tower]);
}
fs.writeFileSync(path.join(OUT,'island_levels_design.json'),JSON.stringify({source:'template_map.vmap',...islandLevels,flights:islandFlights},null,2));
// INSERT ISLAND BANKS
const poolOutline=Array.from({length:48},(_,i)=>{const a=i/48*Math.PI*2,r=1.12+.025*Math.sin(a*5);return [hotSpring.x+hotSpring.rx*r*Math.cos(a),hotSpring.y+hotSpring.ry*r*Math.sin(a)];});
prism(poolOutline,hotSpring.water,hotSpring.water-2,'materials/survival_world_v2/spring_water.vmat','materials/tools/toolsnodraw.vmat','255 255 255 255');
for(let i=0;i<30;i++){const a=i/30*Math.PI*2,r=1.17+.045*Math.sin(i*2);const x=hotSpring.x+hotSpring.rx*r*Math.cos(a),y=hotSpring.y+hotSpring.ry*r*Math.sin(a);entity('prop_static','spa_rim_'+i,[x,y,surface(x,y)],{model:'models/props_nature/river_rocks00'+(i%3+1)+'.vmdl',solid:'0',rendercolor:'215 222 217'},`0 ${i*47} 0`,1.2+(i%4)*.2);}
for(let i=0;i<17;i++){const a=i/17*Math.PI*2,r=1.65+.15*Math.sin(i*2.3),x=hotSpring.x+hotSpring.rx*r*Math.cos(a),y=hotSpring.y+hotSpring.ry*r*Math.sin(a);entity('ent_dota_tree','spa_blossom_'+i,[x,y,surface(x,y)],{model:'models/props_tree/tree_oak_01.vmdl',skin:i%5===0?'3':'6',body:'1',solid:'0',rendercolor:'255 255 255',renderamt:'255'},`0 ${i*57} 0`,1.2+(i%3)*.15);}
for(let i=0;i<5;i++)entity('info_particle_system','spa_mist_'+i,[-500+i*250,-14000+(i%2)*180,hotSpring.water+20],{effect_name:'maps/journey_assets/particles/journey_fountain_radiant_mist.vpcf',start_active:'1'});
fs.writeFileSync(path.join(OUT,'hot_spring_design.json'),JSON.stringify({...hotSpring,navigation:'decorative inaccessible mountain',trees:17,rocks:30,mistEmitters:5},null,2));
// Ridge canopy clusters stay away from usable land and entrances.
let canopyCount=0;
for(let y=-15800;y<16000;y+=270)for(let x=-15800;x<16000;x+=270){const px=x+(rnd()-.5)*150,py=y+(rnd()-.5)*150;if(springRadius(px,py)<2.2||nativePreserved(px,py)||at(px,py)||at(px+320,py)||at(px-320,py)||at(px,py+320)||at(px,py-320))continue;if(variation(px*.48,py*.48)<.38||rnd()<.12)continue;
 const colored=((px>11600&&py<-11900&&py>-14400)||(py<-13100&&py>-15100&&px>-1800&&px<1800))&&canopyCount%3===0;
 entity('ent_dota_tree','ridge_canopy_'+canopyCount++,[px,py,surface(px,py)],{model:colored?'models/props_tree/tree_oak_01.vmdl':canopyCount%5===0?'models/props_tree/tree_oak_spring_01.vmdl':'models/props_tree/tree_pine_01.vmdl',skin:colored?(canopyCount%5===0?'3':'6'):'0',solid:'0',body:'1',rendercolor:colored?'255 255 255':'183 202 183',renderamt:'255'},`0 ${rnd()*360} 0`,1.35+rnd()*.75);}
const groundRoots=land.filter(a=>!a.nativeReuse);
fs.writeFileSync(path.join(OUT,'surface_design.json'),JSON.stringify({mainIsland:'four rounded meadow islands around a small circular shallow lake',sourceMap:'template_map.vmap',crossCenter:originalIsland.center,crossLength:originalIsland.levels.crossHalfLength*2,crossWidth:originalIsland.levels.crossHalfWidth*2,groundSurfaceZ:396,waterZ:400,transitionWidth:1080,architecture:'continuous closed heightfield',preserved,gridStep,meshAudit,canopyCount,groundRoots:groundRoots.map(a=>({name:a.name,theme:theme(a),z:level(a)+12})),lilySource:'Native tileset entities disabled'},null,2));
