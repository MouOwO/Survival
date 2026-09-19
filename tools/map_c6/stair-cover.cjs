// Ground-level planting along every native stair flight and its approach.
// Stone tread heights come from Valve's actual stepped mesh, not a ramp proxy.
const assets=require('./plant-assets.json'),{sampler}=require('./rock-surfaces.cjs');
function build(S,place,rocks,stairs){
 const rockRay=sampler(rocks),stepRay=sampler(stairs),plants=[],regions={},species={};
 const overlap=40,landingOverlap=24,maxHeight=38,protectedFloors=[{x0:-600,x1:600,y0:-600,y1:600}];
 for(let r=0;r<4;r++)for(const f of [S.court,S.lane,S.cornerLow,S.cornerStairs,S.cornerHigh]){
  const inset=f===S.cornerStairs?overlap:f===S.cornerHigh||f===S.cornerLow?landingOverlap:0;
  const b={x0:f.x0+inset,x1:f.x1-inset,y0:f.y0+(f===S.cornerStairs?0:inset),y1:f.y1-(f===S.cornerStairs?0:inset)};
  const a=S.rotate(b.x0,b.y0,r),c=S.rotate(b.x1,b.y1,r);
  protectedFloors.push({x0:Math.min(a[0],c[0]),x1:Math.max(a[0],c[0]),y0:Math.min(a[1],c[1]),y1:Math.max(a[1],c[1])});
 }
 const occupied=b=>protectedFloors.some(f=>Math.min(b.x1,f.x1+1)>Math.max(b.x0,f.x0-1)&&Math.min(b.y1,f.y1+1)>Math.max(b.y0,f.y0-1));
 const noise=(i,k)=>{const a=Math.sin(i*159.7+k*279.1)*43758.5453;return a-Math.floor(a);};
 const palette=['bush_00','grass_clump_00e','fern003','bush_01','grass_clump_00f','plant002','bush_00','grass_clump_00d'];
 let index=0;
 function add(x,y,name,zone,flight,side){
  const seed=index++,base=S.height(x,y);let px=x,ground,stone,cliff,support;
  for(let attempt=0;attempt<4;attempt++){
   ground=S.height(px,y);stone=stepRay([px,y,540],[0,0,-1]);cliff=rockRay([px,y,540],[0,0,-1]);
   // An overhanging boulder can cover the soil beside a tread. Move that
   // tuft a few units toward the outermost stone step rather than bury it.
   if(!cliff||cliff.point[2]<=Math.max(ground,stone?.point[2]??0)+30)break;
   if(flight<0)return;px-=side*5;
  }
  const floor=Math.max(ground,stone?.point[2]??-Infinity);
  if(cliff&&cliff.point[2]>floor+30)return;
  const z=Math.max(floor,cliff?.point[2]??-Infinity);support=z===cliff?.point[2]?'bank-stone':z===stone?.point[2]?'stair-stone':'soil';
  if(z>base+44)return;
  const a=assets[name],lo=a.min,hi=a.max,yaw=noise(seed,2)*360,c=Math.cos(yaw*Math.PI/180),s=Math.sin(yaw*Math.PI/180);
  const anchor=[(lo[0]+hi[0])/2,(lo[1]+hi[1])/2,lo[2]+1],rotate=([x,y,z])=>[x*c-y*s,x*s+y*c,z],offset=rotate(anchor);
  const corners=[lo[0],hi[0]].flatMap(x=>[lo[1],hi[1]].map(y=>rotate([x-anchor[0],y-anchor[1],0])));
  const bush=name.startsWith('bush'),height=bush?22+noise(seed,3)*6:30+noise(seed,3)*8;
  let scale=Math.min(height/(hi[2]-lo[2]),bush?.65:1.05),b;
  for(let i=0;i<14;i++){
   b={x0:px+Math.min(...corners.map(p=>p[0]))*scale,x1:px+Math.max(...corners.map(p=>p[0]))*scale,y0:y+Math.min(...corners.map(p=>p[1]))*scale,y1:y+Math.max(...corners.map(p=>p[1]))*scale};
   if(!occupied(b))break;scale*=.88;
  }
  if(occupied(b)||scale<.1)return;
  const skin=bush?'1':name.startsWith('grass_clump')?'2':'0',root=[px,y,z-1.5];
  for(let r=0;r<4;r++){
   const origin=[...S.rotate(px-offset[0]*scale,y-offset[1]*scale,r),root[2]-offset[2]*scale],angles=[0,yaw-r*90,0];
   place(a.asset,...origin,scale,angles,'prop_static',skin);
   const xy=[S.rotate(b.x0,b.y0,r),S.rotate(b.x1,b.y1,r)],bounds={x0:Math.min(...xy.map(p=>p[0])),x1:Math.max(...xy.map(p=>p[0])),y0:Math.min(...xy.map(p=>p[1])),y1:Math.max(...xy.map(p=>p[1]))};
   plants.push({zone,quarter:r,flight,side,name,skin,origin,angles,scale,bounds,root:[...S.rotate(px,y,r),root[2]],support,surface:z,height:(hi[2]-lo[2])*scale});
   regions[zone]=(regions[zone]||0)+1;species[name]=(species[name]||0)+1;
  }
 }
 // Three consecutive native flights on each of the four rotated staircases.
 const run=(S.stairEnd-S.stairStart)/3;
 for(let flight=0;flight<3;flight++)for(const side of [-1,1])for(let j=0;j<6;j++){
  const y=S.stairStart+flight*run+27+j*31,edge=side<0?S.cornerStairs.x0:S.cornerStairs.x1;
  const k=flight*12+j+(side>0?6:0);
  const name=palette[k%palette.length];
  add(edge+side*(name.startsWith('bush')?8:-6),y,name,'stair-side',flight,side);
  add(edge+side*6,y+13,['grass_clump_00d','grass_clump_00e','grass_clump_00f'][j%3],'stair-side',flight,side);
 }
 // Continue planting around the lower turn and upper path, in small patches.
 for(const y of [-80,-24,32,60])add(2630,y,palette[index%palette.length],'lower-approach',-1,1);
 for(const x of [2152,2186,2220])add(x,92,palette[index%palette.length],'lower-approach',-1,-1);
 for(const y of [742,794,850,906,962,1018,1074]){
  add(2630,y,palette[index%palette.length],'upper-approach',-1,1);
  add(2635,y+17,'grass_clump_00f','upper-approach',-1,1);
 }
 for(const x of [2164,2222,2280,2338,2396,2454,2512,2570])
  add(x,1128,palette[index%palette.length],'upper-approach',-1,1);
 return {count:plants.length,plants,species,regions,stairGroups:4,flights:12,leafOverlap:overlap,landingLeafOverlap:landingOverlap,maxHeight,placement:'native step mesh, bank mesh or adjacent soil; includes both ends of the approach',collision:'none; 304-unit stair center and all building lawns remain clear'};
}
module.exports={build};
