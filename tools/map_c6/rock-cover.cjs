// Dense mixed vegetation rooted in the visible native rock surfaces. Terrain
// height is deliberately not used: it is far below the stacked rock crowns.
const assets=require('./plant-assets.json'),{sampler}=require('./rock-surfaces.cjs');
function build(S,place,rocks){
 const ray=sampler(rocks),plants=[],regions={},species={},floors=[{x0:-600,x1:600,y0:-600,y1:600}],rimFloors=[floors[0]],rimOverlap=48;
 for(let r=0;r<4;r++)for(const f of [S.court,S.lane,S.cornerLow,S.cornerStairs,S.cornerHigh]){
  const a=S.rotate(f.x0,f.y0,r),b=S.rotate(f.x1,f.y1,r);
  floors.push({x0:Math.min(a[0],b[0]),x1:Math.max(a[0],b[0]),y0:Math.min(a[1],b[1]),y1:Math.max(a[1],b[1])});
  // The user's requested overhang softens the LAWN edge. Roads, steps and
  // landings stay fully clear; only the outer 48 units of a court permit leaves.
  const box=floors[floors.length-1];
  rimFloors.push(f===S.court?{x0:box.x0+rimOverlap,x1:box.x1-rimOverlap,y0:box.y0+rimOverlap,y1:box.y1-rimOverlap}:box);
 }
 const intersects=(b,rim=false)=>(rim?rimFloors:floors).some(f=>Math.min(b.x1,f.x1+2)>Math.max(b.x0,f.x0-2)&&Math.min(b.y1,f.y1+2)>Math.max(b.y0,f.y0-2));
 const noise=(i,k)=>{const n=Math.sin(i*127.1+k*311.7)*43758.5453;return n-Math.floor(n);};
 const tops=['bush_00','bush_01','bush_00','fern002','bush_01','bush_00','bush_spring_00','bush_01','bush_autumn_00'];
 const walls=['bush_00','bush_01','ivy_128a','bush_00','fern002','bush_spring_00','bush_00','bush_autumn_00'];
 let seed=0;
 function patch(origin,dir,zone,crown=false,rim=false){
  let hit=ray(origin,dir),support='native-rock';
  // Moving the back crown row towards the lawn can put its roots onto soil.
  // Choose the visible upper surface there, rather than burying it in a prop
  // or leaving it suspended at the old stone's height.
  if(rim){const ground=S.height(origin[0],origin[1]);
   if(!hit||ground>hit.point[2]){hit={point:[origin[0],origin[1],ground],normal:[0,0,1]};support='terrain';}
  }
  if(!hit)return;
  const i=seed++,name=(crown?tops:walls)[i%(crown?tops.length:walls.length)],a=assets[name];
  // Skin 0 of Valve's oak bushes is the almost-black leaf group 08.
  // Native skin 1 supplies healthy green (or autumn amber); sparse skin 3
  // flowers tie into the island's existing spring trees without tinting.
  const skin=/^bush_(00|01)$/.test(name)?(crown&&i%17===0?'3':'1'):name==='bush_autumn_00'?'1':'0';
  const normal=hit.normal;
  // Crown plants grow upright, wall plants fan out from the rock crevices.
  const pitch=crown?Math.min(20,Math.acos(normal[2])*180/Math.PI):Math.acos(normal[2])*180/Math.PI;
  const yaw=crown?noise(i,1)*360:Math.atan2(normal[1],normal[0])*180/Math.PI;
  const p=pitch*Math.PI/180,h=yaw*Math.PI/180,cp=Math.cos(p),sp=Math.sin(p),c=Math.cos(h),s=Math.sin(h);
  const rotate=([x,y,z])=>[c*(cp*x+sp*z)-s*y,s*(cp*x+sp*z)+c*y,-sp*x+cp*z];
  const anchor=[(a.min[0]+a.max[0])/2,(a.min[1]+a.max[1])/2,a.min[2]+1],offset=rotate(anchor);
  const corners=[a.min[0],a.max[0]].flatMap(x=>[a.min[1],a.max[1]].flatMap(y=>[a.min[2],a.max[2]].map(z=>rotate([x-anchor[0],y-anchor[1],z-anchor[2]]))));
  const root=hit.point.map((v,k)=>v-normal[k]*(crown?4:6));
  let scale=(name==='bush_01'?.66:name==='fern002'?.83:1.05)+noise(i,2)*.12,b;
  for(let tries=0;tries<14;tries++){
   b={x0:root[0]+Math.min(...corners.map(p=>p[0]))*scale,x1:root[0]+Math.max(...corners.map(p=>p[0]))*scale,y0:root[1]+Math.min(...corners.map(p=>p[1]))*scale,y1:root[1]+Math.max(...corners.map(p=>p[1]))*scale};
   if(!intersects(b,rim))break;scale*=.88;
  }
  if(intersects(b,rim)||scale<.24)return;
  for(let r=0;r<4;r++){
   const xy=S.rotate(root[0]-offset[0]*scale,root[1]-offset[1]*scale,r),z=root[2]-offset[2]*scale;
   const angles=[pitch,yaw-r*90,0];place(a.asset,...xy,z,scale,angles,'prop_static',skin);
   const corners2=[S.rotate(b.x0,b.y0,r),S.rotate(b.x1,b.y1,r)];
   const bounds={x0:Math.min(...corners2.map(p=>p[0])),x1:Math.max(...corners2.map(p=>p[0])),y0:Math.min(...corners2.map(p=>p[1])),y1:Math.max(...corners2.map(p=>p[1]))};
   plants.push({zone,quarter:r,name,skin,rim,support,origin:[...xy,z],angles,scale,bounds,surface:[...S.rotate(hit.point[0],hit.point[1],r),hit.point[2]],root:[...S.rotate(root[0],root[1],r),root[2]],normal:[...S.rotate(normal[0],normal[1],r),normal[2]]});
   regions[zone]=(regions[zone]||0)+1;species[name]=(species[name]||0)+1;
  }
 }
 // Keep the front crown row on rock; shift the back row 48 units towards
 // the original cliff lip so leaves overlap the hard grass/stone boundary.
 for(const side of [-1,1]){
  for(let j=0;j<29;j++)for(let k=0;k<2;k++)patch([742+j*48+(k?18:0),side*(300+k*90+(j%3-1)*4),510],[0,0,-1],k?'lane-rim-crown':'lane-crown',true,k===1);
  for(let row=0;row<5;row++)for(let j=0;j<22;j++)patch([750+j*64+(row%2)*22,side*224,64+row*70+(j%3-1)*7],[0,side,0],'lane-face');
 }
 // Continue over the B bend and both staircase cheeks; no planting on treads.
 for(let j=0;j<8;j++){
  patch([2148,140+j*76,540],[0,0,-1],'stairs-inner-crown',true,true);
  patch([2770,-168+j*127,540],[0,0,-1],'stairs-outer-crown',true,true);
  for(let k=0;k<4;k++){
   const y=135+j*75,z=S.stairElevation(y)+40+k*78;
   patch([2240,y,z],[-1,0,0],'stairs-inner-face');
   const oy=-170+j*128,oz=S.stairElevation(oy)+38+k*79;
   patch([2624,oy,oz],[1,0,0],'stairs-outer-face');
  }
 }
 for(let j=0;j<8;j++){
  patch([2094+j*78,-379,540],[0,0,-1],'bend-crown',true,true);
  for(let k=0;k<5;k++)patch([2090+j*78+(k%2)*15,-224,65+k*73],[0,-1,0],'bend-face');
 }
 // Wrap the short pool-side return into the long rim. These uphill bushes
 // bridge the exposed L-shaped soil lip visible in the user's close-up.
 for(const side of [-1,1])for(let j=0;j<7;j++)
  patch([709+(j%3-1)*5,side*(408+j*44),510],[0,0,-1],'pool-rim-crown',true,true);
 for(const side of [-1,1])for(const [x,y] of [[738,399],[706,682],[682,706]])
  patch([x,side*y,510],[0,0,-1],'pool-rim-corner-crown',true,true);
 return {count:plants.length,regions,species,plants,rimOverlap,placement:'native rock or soil support; back crown row moved towards original cliff lip',collision:'none; roads and stairs clear; low leaves may overlap outer 48 units of court'};
}
module.exports={build};
