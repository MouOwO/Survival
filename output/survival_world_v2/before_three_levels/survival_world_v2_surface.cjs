// Continuous closed terrain; original central islands keep their native detail.
const clamp=v=>Math.max(0,Math.min(1,v));
const smooth=v=>{v=clamp(v);return v*v*(3-2*v);};
function edgeDistance(x,y,p){let d=Infinity;for(let i=0;i<p.length;i++){const a=p[i],b=p[(i+1)%p.length],dx=b[0]-a[0],dy=b[1]-a[1],t=clamp(((x-a[0])*dx+(y-a[1])*dy)/(dx*dx+dy*dy||1));d=Math.min(d,Math.hypot(x-a[0]-dx*t,y-a[1]-dy*t));}return d;}
function variation(x,y){return .5+.22*Math.sin(x/340+y/513)+.17*Math.cos(y/257-x/617);}
function theme(a){if(!a)return 'forest';if(a.name.includes('n41_50_camp'))return 'thaw';if(a.material===M.snow||a.name.includes('polar_crystal')||a.name.includes('ice_elegy'))return 'snow';if(a.material===M.lava)return 'volcanic';if(a.material===M.corrupt)return 'corrupt';return 'forest';}
const level=a=>Math.round(a.z/128)*128;
const preserved=[-5632,-1792,3328,7168];
function nativePreserved(x,y){return x>=-5632&&x<=3328&&y>=-1792&&y<=7168;}
function rawSurface(x,y){const a=at(x,y);if(a)return a.material===M.water&&!a.shallow?254:Math.round(a.z/128)*128+12;
 const gx=clamp((x+16384)/32768)*128,gy=clamp((y+16384)/32768)*128,ix=Math.min(127,Math.floor(gx)),iy=Math.min(127,Math.floor(gy)),u=gx-ix,v=gy-iy;
 return ((heights[iy*129+ix]*(1-u)+heights[iy*129+ix+1]*u)*(1-v)+(heights[(iy+1)*129+ix]*(1-u)+heights[(iy+1)*129+ix+1]*u)*v)*128+12;}
const hotSpring={x:0,y:-14000,rx:850,ry:560,bed:640,water:704,rim:740};
function springRadius(x,y){return Math.hypot((x-hotSpring.x)/hotSpring.rx,(y-hotSpring.y)/hotSpring.ry);}
function terrainHeight(x,y){let h=0;for(let j=-1;j<=1;j++)for(let i=-1;i<=1;i++)h+=rawSurface(x+i*128,y+j*128)*(i===0?2:1)*(j===0?2:1);h/=16;
 const r=springRadius(x,y);if(r>=2.3)return h;
 const basin=hotSpring.bed+(hotSpring.rim-hotSpring.bed)*smooth((r-.80)/.45);
 return basin*(1-smooth((r-1.65)/.65))+h*smooth((r-1.65)/.65);}
function surface(x,y){return nativePreserved(x,y)?nativeSurface(x,y):terrainHeight(x,y);}
// Index extends outside each polygon so the blend straddles the old hard boundary.
const paintBins=new Map();
for(const a of terrainPaint){if(a.nativeReuse||a.material===M.water)continue;for(let y=Math.floor((a.bb[1]-400)/512);y<=Math.floor((a.bb[3]+400)/512);y++)for(let x=Math.floor((a.bb[0]-400)/512);x<=Math.floor((a.bb[2]+400)/512);x++){const key=x+','+y;if(!paintBins.has(key))paintBins.set(key,[]);paintBins.get(key).push(a);}}
function nearbyPaint(x,y){return paintBins.get(Math.floor(x/512)+','+Math.floor(y/512))||[];}
function localTheme(x,y){const shapes=nearbyPaint(x,y);for(let i=shapes.length-1;i>=0;i--){const a=shapes[i];if(a.name!=='paving'&&inside(x,y,a.polygon))return theme(a);}return 'forest';}
const paletteNames=['forest','snow','thaw','volcanic','corrupt'],paintCache=new Map();
function continuousPaint(v,m){if(m>=paletteNames.length)return [0,0,0,0];const [x,y]=v,key=x+','+y+','+m;if(paintCache.has(key))return paintCache.get(key);
 const t=paletteNames[m],n=variation(x,y),shapes=nearbyPaint(x,y);let w=[.08+.14*n,0,0],seam=1;
 for(const a of shapes){const own=theme(a),d=edgeDistance(x,y,a.polygon),within=inside(x,y,a.polygon),signed=within?d:-d;
  const compatible=['forest','corrupt'].includes(own)&&['forest','corrupt'].includes(t);
  if(a.name!=='paving'&&own!==t&&!compatible){seam=Math.min(seam,smooth((d-24)/260));continue;}
  const alpha=smooth((signed+160+(n-.5)*210)/440);if(!alpha)continue;let target;
  if(t==='snow')target=[1,0,0];else if(t==='thaw')target=[1,0,0];else if(t==='volcanic')target=[.58+.30*(1-n),1,0];
  else if(a.material===M.dirt)target=[0,1,0];else if(a.material===M.paving||a.material===M.stone||a.material===M.corrupt)target=[0,0,1];else target=[1,0,0];
  w=w.map((v,i)=>v*(1-alpha)+target[i]*alpha);
  if(t==='forest'&&a.material===M.dirt){const fringe=2.4*alpha*(1-alpha);w=w.map((v,i)=>v*(1-fringe)+(i===0?.35:0)*fringe);}
 }
 if(t!=='forest'&&t!=='corrupt'){let edge=0;for(const a of shapes)if(theme(a)===t&&inside(x,y,a.polygon))edge=Math.max(edge,smooth((edgeDistance(x,y,a.polygon)-12)/260));seam*=edge;}
 // TI10's grass reveal has a full 0..1 range; the old long-grass mask was nearly black.
 if((t==='forest'||t==='corrupt')&&at(x,y)&&w[0]>.001&&w[2]>.001)w[2]=1;
 const sr=springRadius(x,y);if(sr<1.65)w=[.20*smooth((sr-1.08)/.5),0,0];
 const result=[...w.map(v=>v*seam),0];paintCache.set(key,result);return result;
}
const gridStep=128,chunkCells=16,meshAudit=[];
for(let cy=0;cy<256;cy+=chunkCells)for(let cx=0;cx<256;cx+=chunkCells){const verts=[],faces=[],ids=new Map(),boundary=new Map();
 function vertex(gx,gy){const key=gx+','+gy;if(ids.has(key))return ids.get(key);const x=-16384+gx*gridStep,y=-16384+gy*gridStep,id=verts.length;verts.push([x,y,terrainHeight(x,y)]);ids.set(key,id);return id;}
 function triangle(v,m){faces.push({v,m});for(let i=0;i<3;i++){const a=v[i],b=v[(i+1)%3],reverse=b+','+a;if(boundary.has(reverse))boundary.delete(reverse);else boundary.set(a+','+b,[a,b]);}}
 for(let gy=cy;gy<cy+chunkCells;gy++)for(let gx=cx;gx<cx+chunkCells;gx++){const x=-16384+(gx+.5)*gridStep,y=-16384+(gy+.5)*gridStep;if(nativePreserved(x,y))continue;const a=vertex(gx,gy),b=vertex(gx+1,gy),c=vertex(gx+1,gy+1),d=vertex(gx,gy+1),m=paletteNames.indexOf(localTheme(x,y));triangle([a,b,c],m);triangle([a,c,d],m);}
 if(!faces.length)continue;const topFaces=faces.length,bottoms=new Map(),edges=[...boundary.values()],center=verts.length;verts.push([-16384+(cx+8)*gridStep,-16384+(cy+8)*gridStep,-512]);
 function bottom(id){if(!bottoms.has(id)){bottoms.set(id,verts.length);verts.push([verts[id][0],verts[id][1],-512]);}return bottoms.get(id);}
 for(const [a,b] of edges){const ba=bottom(a),bb=bottom(b);faces.push({v:[b,a,ba,bb],m:5},{v:[center,bb,ba],m:5});}
 normalVertex=v=>{const dx=(terrainHeight(v[0]+64,v[1])-terrainHeight(v[0]-64,v[1]))/128,dy=(terrainHeight(v[0],v[1]+64)-terrainHeight(v[0],v[1]-64))/128,l=Math.hypot(dx,dy,1);return [-dx/l,-dy/l,1/l];};
 paintVertex=continuousPaint;mesh(verts,faces,[...paletteNames.map(t=>'materials/survival_world_v2/transition_'+t+'.vmat'),'materials/tools/toolsnodraw.vmat'],'255 255 255 255');paintVertex=null;normalVertex=null;meshAudit.push({chunk:[cx,cy],vertices:verts.length,topTriangles:topFaces});
}
// Keep the original native sea across every water region, at one common tile level.
const shallow=terrainPaint.find(a=>a.shallow);
if(shallow){prism(shallow.polygon,396,370,'materials/survival_world_v2/transition_forest.vmat','materials/tools/toolsnodraw.vmat','255 255 255 255');prism(shallow.polygon,416,414,'materials/survival_world_v2/shallow_water.vmat','materials/tools/toolsnodraw.vmat','255 255 255 255');}
const poolOutline=Array.from({length:48},(_,i)=>{const a=i/48*Math.PI*2,r=1.12+.025*Math.sin(a*5);return [hotSpring.x+hotSpring.rx*r*Math.cos(a),hotSpring.y+hotSpring.ry*r*Math.sin(a)];});
prism(poolOutline,hotSpring.water,hotSpring.water-2,'materials/survival_world_v2/spring_water.vmat','materials/tools/toolsnodraw.vmat','255 255 255 255');
for(let i=0;i<30;i++){const a=i/30*Math.PI*2,r=1.17+.045*Math.sin(i*2);const x=hotSpring.x+hotSpring.rx*r*Math.cos(a),y=hotSpring.y+hotSpring.ry*r*Math.sin(a);entity('prop_static','spa_rim_'+i,[x,y,surface(x,y)],{model:'models/props_nature/river_rocks00'+(i%3+1)+'.vmdl',solid:'0',rendercolor:'215 222 217'},`0 ${i*47} 0`,1.2+(i%4)*.2);}
for(let i=0;i<17;i++){const a=i/17*Math.PI*2,r=1.65+.15*Math.sin(i*2.3),x=hotSpring.x+hotSpring.rx*r*Math.cos(a),y=hotSpring.y+hotSpring.ry*r*Math.sin(a);entity('ent_dota_tree','spa_blossom_'+i,[x,y,surface(x,y)],{model:'models/props_tree/tree_oak_01.vmdl',skin:i%5===0?'3':'6',body:'1',solid:'0',rendercolor:'255 255 255',renderamt:'255'},`0 ${i*57} 0`,1.2+(i%3)*.15);}
for(let i=0;i<5;i++)entity('info_particle_system','spa_mist_'+i,[-500+i*250,-14000+(i%2)*180,hotSpring.water+20],{effect_name:'maps/journey_assets/particles/journey_fountain_radiant_mist.vpcf',start_active:'1'});
fs.writeFileSync(path.join(OUT,'hot_spring_design.json'),JSON.stringify({...hotSpring,navigation:'decorative inaccessible mountain',trees:17,rocks:30,mistEmitters:5},null,2));
// Ridge canopy clusters stay away from usable land and entrances.
let canopyCount=0;
for(let y=-15800;y<16000;y+=270)for(let x=-15800;x<16000;x+=270){const px=x+(rnd()-.5)*150,py=y+(rnd()-.5)*150;if(springRadius(px,py)<2.2||nativePreserved(px,py)||at(px,py)||at(px+320,py)||at(px-320,py)||at(px,py+320)||at(px,py-320))continue;if(variation(px*.48,py*.48)<.38||rnd()<.12)continue;
 const colored=px>9000&&py<0||py<-12000&&px>-2200&&px<3200;
 entity('ent_dota_tree','ridge_canopy_'+canopyCount++,[px,py,surface(px,py)],{model:colored?'models/props_tree/tree_oak_01.vmdl':canopyCount%5===0?'models/props_tree/tree_oak_spring_01.vmdl':'models/props_tree/tree_pine_01.vmdl',skin:colored?(canopyCount%5===0?'3':'6'):'0',solid:'0',body:'1',rendercolor:colored?'255 255 255':'183 202 183',renderamt:'255'},`0 ${rnd()*360} 0`,1.35+rnd()*.75);}
const groundRoots=land.filter(a=>!a.nativeReuse);
fs.writeFileSync(path.join(OUT,'surface_design.json'),JSON.stringify({mainIsland:'four rotated original U islands',sourceMap:'template_map.vmap',crossCenter:originalIsland.center,crossLength:3584,crossWidth:640,groundSurfaceZ:396,waterZ:416,transitionWidth:440,architecture:'continuous closed heightfield',preserved,gridStep,meshAudit,canopyCount,groundRoots:groundRoots.map(a=>({name:a.name,theme:theme(a),z:level(a)+12})),lilySource:'Native tileset entities disabled'},null,2));
