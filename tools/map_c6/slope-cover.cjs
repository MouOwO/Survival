// Mixed Valve undergrowth on exposed banks. Roots follow the authored ground;
// complete rotated model bounds, not only origins, avoid playable footprints.
const assets=require('./plant-assets.json');
const palette=['bush_00','bush_01','fern002','bush_00','bush_spring_00','bush_01','bush_autumn_00','fern001','bush_00','grass_clump_00d'];
function build(S,place){
 const plants=[],regions={},species={},pool={x0:-600,y0:-600,x1:600,y1:600};
 const floors=[pool];
 for(let r=0;r<4;r++)for(const f of [S.court,S.lane,S.cornerLow,S.cornerStairs,S.cornerHigh]){
  const p=[S.rotate(f.x0,f.y0,r),S.rotate(f.x1,f.y1,r)];
  floors.push({x0:Math.min(...p.map(p=>p[0])),x1:Math.max(...p.map(p=>p[0])),y0:Math.min(...p.map(p=>p[1])),y1:Math.max(...p.map(p=>p[1]))});
 }
 const occupied=b=>floors.some(f=>Math.min(b.x1,f.x1+2)>Math.max(b.x0,f.x0-2)&&Math.min(b.y1,f.y1+2)>Math.max(b.y0,f.y0-2));
 const noise=(i,k)=>{const v=Math.sin(i*127.1+k*311.7)*43758.5453;return v-Math.floor(v);};
 function add(name,x,y,size,seed,zone){
  if(!S.blocked(x,y)||Math.hypot(x,y)>3000)return;
  const a=assets[name],lo=a.min,hi=a.max;
  const dx=(S.height(x+4,y)-S.height(x-4,y))/8,dy=(S.height(x,y+4)-S.height(x,y-4))/8;
  const gradient=Math.hypot(dx,dy),upright=/fern|grass/.test(name);
  const pitch=Math.min(upright?24:76,Math.atan(gradient)*180/Math.PI);
  const yaw=gradient>.15?Math.atan2(-dy,-dx)*180/Math.PI:noise(seed,2)*360;
  const p=pitch*Math.PI/180,h=yaw*Math.PI/180,cp=Math.cos(p),sp=Math.sin(p),c=Math.cos(h),s=Math.sin(h);
  const rotate=([x,y,z])=>[c*(cp*x+sp*z)-s*y,s*(cp*x+sp*z)+c*y,-sp*x+cp*z];
  const anchor=[(lo[0]+hi[0])/2,(lo[1]+hi[1])/2,lo[2]+1];
  const offset=rotate(anchor),corners=[lo[0],hi[0]].flatMap(x=>[lo[1],hi[1]].flatMap(y=>[lo[2],hi[2]].map(z=>rotate([x-anchor[0],y-anchor[1],z-anchor[2]]))));
  let scale=size,b;
  for(let tries=0;tries<10;tries++){
   b={x0:x+Math.min(...corners.map(p=>p[0]))*scale,x1:x+Math.max(...corners.map(p=>p[0]))*scale,y0:y+Math.min(...corners.map(p=>p[1]))*scale,y1:y+Math.max(...corners.map(p=>p[1]))*scale};
   if(!occupied(b))break;scale*=.82;
  }
  if(occupied(b)||scale<.16)return;
  // The bottom-center is embedded two units into the actual terrain. Tilted
  // shrubs/ivy follow the slope; ferns remain mostly upright in soil pockets.
  const root=S.height(x,y)-2,origin=[x-offset[0]*scale,y-offset[1]*scale,root-offset[2]*scale],angles=[pitch,yaw,0];
  const skin=/^bush_(00|01)$/.test(name)||name==='bush_autumn_00'?'1':'0';
  place(a.asset,...origin,scale,angles,'prop_static',skin);
  plants.push({zone,name,skin,anchor:[x,y,root],origin,angles,scale,bounds:b});
  regions[zone]=(regions[zone]||0)+1;species[name]=(species[name]||0)+1;
 }
 let index=0;
 function patch(x,y,zone,r,rich=false){
  const seed=index++ +r*59,[u,v]=S.rotate(x,y,r),name=palette[(seed+Math.floor(seed/7))%palette.length];
  add(name,u,v,.8+noise(seed,1)*.28,seed,zone);
  // Trailing ivy is interleaved with shrubs rather than laying a single hedge.
  if(rich||seed%3===0){const [a,b]=S.rotate(x+(noise(seed,3)-.5)*18,y+(noise(seed,4)-.5)*24,r);
   add(seed%4===0?'fern002':'ivy_128a',a,b,.7+noise(seed,5)*.24,seed+700,zone+'-groundcover');
  }
 }
 for(let r=0;r<4;r++){
  // Two stepped belts cover the exact exposed pool shoulders in the feedback.
  for(const sign of [-1,1])for(let j=0;j<5;j++)for(let k=0;k<2;k++){
   const x=638+k*46+(j%2)*4,y=sign*(292+j*68+(k?15:0));
   patch(x,y,'pool-bank',r,true);
  }
  for(const [x,y] of [[622,644],[652,666],[688,686],[644,-642],[682,-680]])patch(x,y,'pool-corner',r,true);
  // Sparse low cap planting softens the long edge without occupying a lawn.
  for(const sign of [-1,1])for(let j=0;j<12;j++){
   patch(786+j*105,sign*(382+(j%3)*6),'lane-edge',r,j%4===0);
  }
  // Soil on the outer side of the bend and in narrow stair-edge pockets.
  for(let j=0;j<7;j++){
   patch(2148+(j%2)*6,146+j*77,'stair-inner',r);
   patch(2814+(j%3)*9,-165+j*138,'stair-outer',r,j%2===0);
  }
  for(let j=0;j<6;j++)patch(2096+j*111,-423-(j%2)*12,'bend-edge',r);
 }
 return {count:plants.length,regions,species,plants,collision:'none; existing native GridNav unchanged'};
}
module.exports={build};
