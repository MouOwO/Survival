// Low native roadside plants at the foot of the cliff. Independent placement
// leaves the accepted crown/rim composition and original scene seed unchanged.
const assets=require('./plant-assets.json'),{sampler}=require('./rock-surfaces.cjs');
function build(S,place,rocks){
 const ray=sampler(rocks),plants=[],species={},regions={},floors=[{x0:-600,x1:600,y0:-600,y1:600}];
 const overlap=24,maxHeight=34;
 for(let r=0;r<4;r++)for(const f of [S.court,S.lane,S.cornerLow,S.cornerStairs,S.cornerHigh]){
  const a=S.rotate(f.x0,f.y0,r),b=S.rotate(f.x1,f.y1,r),inset=f===S.lane||f===S.cornerLow?overlap:0;
  const box={x0:Math.min(a[0],b[0]),x1:Math.max(a[0],b[0]),y0:Math.min(a[1],b[1]),y1:Math.max(a[1],b[1])};
  // Only a thin strip at low-road edges may carry grass tips. Building lawns,
  // water crossings, high landings and all stair treads remain fully clear.
  floors.push({x0:box.x0+inset,x1:box.x1-inset,y0:box.y0+inset,y1:box.y1-inset});
 }
 const occupied=b=>floors.some(f=>Math.min(b.x1,f.x1+1)>Math.max(b.x0,f.x0-1)&&Math.min(b.y1,f.y1+1)>Math.max(b.y0,f.y0-1));
 const noise=(i,k)=>{const n=Math.sin(i*137.3+k*241.9)*43758.5453;return n-Math.floor(n);};
 const palette=['grass_clump_00d','grass_clump_00e','fern003','grass_clump_00f','bush_00','grass_clump_00b','plant002','grass_clump_00e','bush_01','grass_clump_00d','fern003','bush_spring_00'];
 let seed=0;
 function tuft(x,y,nx,ny,name,index,zone){
  const base=S.height(x,y),hits=[7,27].map(h=>ray([x,y,base+h],[nx,ny,0],120)).filter(Boolean);
  // Stay in front of the actual rock toe. Do not place grass using the dirt
  // hidden inside a tall prop, which was the cause of the old coverage gaps.
  const near=hits.length?Math.min(...hits.map(h=>Math.hypot(h.point[0]-x,h.point[1]-y))):40;
  const distance=Math.max(2,Math.min(36,near-9));
  const px=x+nx*distance,py=y+ny*distance;if(!S.blocked(px,py))return;
  const ground=S.height(px,py);if(ground>base+28)return;
  const a=assets[name],lo=a.min,hi=a.max,yaw=noise(index,3)*360,h=yaw*Math.PI/180,c=Math.cos(h),s=Math.sin(h);
  const anchor=[(lo[0]+hi[0])/2,(lo[1]+hi[1])/2,lo[2]+1];
  const rotate=([x,y,z])=>[c*x-s*y,s*x+c*y,z];
  const offset=rotate(anchor),corners=[lo[0],hi[0]].flatMap(u=>[lo[1],hi[1]].flatMap(v=>[lo[2],hi[2]].map(z=>rotate([u-anchor[0],v-anchor[1],z-anchor[2]]))));
  const shortBush=name.startsWith('bush'),flower=name==='flowers003',mushroom=name.startsWith('mushroom');
  const height=shortBush?13+noise(index,4)*7:flower?6:mushroom?13:20+noise(index,4)*10;
  let scale=Math.min(height/(hi[2]-lo[2]),shortBush?.38:flower?.18:1),b;
  for(let i=0;i<14;i++){
   b={x0:px+Math.min(...corners.map(p=>p[0]))*scale,x1:px+Math.max(...corners.map(p=>p[0]))*scale,y0:py+Math.min(...corners.map(p=>p[1]))*scale,y1:py+Math.max(...corners.map(p=>p[1]))*scale};
   if(!occupied(b))break;scale*=.88;
  }
  if(occupied(b)||scale<.07)return;
  const skin=/^bush_(00|01)$/.test(name)?'1':'0',root=[px,py,ground-1.5];
  for(let r=0;r<4;r++){
   const xy=S.rotate(px-offset[0]*scale,py-offset[1]*scale,r),z=root[2]-offset[2]*scale,angles=[0,yaw-r*90,0];
   place(a.asset,...xy,z,scale,angles,'prop_static',skin);
   const v=[S.rotate(b.x0,b.y0,r),S.rotate(b.x1,b.y1,r)];
   const bounds={x0:Math.min(...v.map(p=>p[0])),x1:Math.max(...v.map(p=>p[0])),y0:Math.min(...v.map(p=>p[1])),y1:Math.max(...v.map(p=>p[1])),z0:root[2]+(lo[2]-anchor[2])*scale,z1:root[2]+(hi[2]-anchor[2])*scale};
   plants.push({zone,quarter:r,name,skin,origin:[...xy,z],angles,scale,root:[...S.rotate(px,py,r),root[2]],bounds,ground,rockDistance:near,height:(hi[2]-lo[2])*scale});
   species[name]=(species[name]||0)+1;regions[zone]=(regions[zone]||0)+1;
  }
 }
 function patch(x,y,nx,ny,zone){
  const i=seed++,name=palette[(i+Math.floor(i/5))%palette.length];
  tuft(x,y,nx,ny,name,i,zone);
  // Offset grass blades make small colonies with uneven gaps, not a hedge.
  const along=16+noise(i,2)*14;
  tuft(x-ny*along,y+nx*along,nx,ny,['grass_clump_00d','grass_clump_00e','grass_clump_00f'][i%3],i+400,zone);
  if(i%7===2)tuft(x+ny*17,y-nx*17,nx,ny,'flowers003',i+800,zone+'-flowers');
  if(i%19===5)tuft(x+ny*12,y-nx*12,nx,ny,'mushroom_wild_01',i+1200,zone+'-mushrooms');
 }
 // Both sides of all four low approaches, including the folded outer bend.
 for(const side of [-1,1])for(let j=0;j<22;j++)
  patch(725+j*61+(noise(j,7)-.5)*12,side*224,0,side,'lane-foot');
 for(let j=0;j<8;j++)patch(2120+j*63,-224,0,-1,'bend-foot');
 for(const y of [-172,-106,-40,28])patch(2624,y,1,0,'bend-outer-foot');
 return {count:plants.length,species,regions,plants,roadLeafOverlap:overlap,maxHeight,placement:'low tufts on soil immediately in front of native rock toes',collision:'none; existing terrain and GridNav unchanged'};
}
module.exports={build};
