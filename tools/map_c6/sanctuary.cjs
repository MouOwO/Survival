// Approved 09 folded entrance. All sectors rotate the east -> northeast court.
const S={poolSide:1200,poolBed:4,poolSurface:16,landHeight:384,laneHeight:24,
 rampLength:96,rampWidth:448,clearingDepth:1400,clearingWidth:1400,radius:3072,
 approachLength:1500,buildStripDepth:384,heightIncrement:128,stairStart:64,stairEnd:704,stairWidth:384};
const court={x0:720,y0:416,x1:2120,y1:1816};
const lane={x0:600,y0:-224,x1:2100,y1:224};
const turn=[[2100,0],[2432,0],[2432,800],[2000,1000]];
const pads=[[1024,624],[1408,624],[1792,624]];
// Low bend, stairs outside the lawn, and a level upper landing. The original
// 1400-square building lawn is intact; only the bend's stair strip slopes.
const corner={x0:1984,y0:-224,x1:2624,y1:1120};
const cornerLow={x0:1984,y0:-224,x1:2624,y1:64};
const cornerStairs={x0:2240,y0:64,x1:2624,y1:704};
const cornerHigh={x0:1984,y0:704,x1:2624,y1:1120};
const cornerPads=[[2432,-80],[2432,912]];
const clamp=(v,a=0,b=1)=>Math.max(a,Math.min(b,v));
const smooth=(a,b,v)=>{const t=clamp((v-a)/(b-a));return t*t*(3-2*t);};
function rotate(x,y,i){return [[x,y],[y,-x],[-x,-y],[-y,x]][((i%4)+4)%4];}
function rectDistance(x,y,b){return Math.hypot(Math.max(b.x0-x,0,x-b.x1),Math.max(b.y0-y,0,y-b.y1));}
function inRect(x,y,b){return x>=b.x0&&x<=b.x1&&y>=b.y0&&y<=b.y1;}
function segmentDistance(x,y,a,b){
 const dx=b[0]-a[0],dy=b[1]-a[1],t=clamp(((x-a[0])*dx+(y-a[1])*dy)/(dx*dx+dy*dy));
 return Math.hypot(x-a[0]-t*dx,y-a[1]-t*dy);
}
function turnDistance(x,y){return Math.min(...turn.slice(1).map((p,i)=>segmentDistance(x,y,turn[i],p)));}
function laneElevation(x){return S.poolBed+(S.laneHeight-S.poolBed)*clamp((x-600)/S.rampLength);}
function stairElevation(y){return S.laneHeight+(S.landHeight-S.laneHeight)*clamp((y-S.stairStart)/(S.stairEnd-S.stairStart));}
function sector(x,y){
 const floors=[[court,S.landHeight,'court'],[lane,laneElevation(x),'lane'],
  [cornerLow,S.laneHeight,'cornerLow'],[cornerStairs,stairElevation(y),'stairs'],[cornerHigh,S.landHeight,'cornerHigh']];
 let nearest={distance:Infinity,z:S.landHeight,kind:'forest'};
 for(const [bounds,z,kind] of floors){const distance=rectDistance(x,y,bounds);
  if(distance===0)return {distance,z,kind};
  if(distance<nearest.distance)nearest={distance,z,kind:'forest'};
 }
 return nearest;
}
function walkDistance(x,y){
 let d=Math.hypot(Math.max(Math.abs(x)-600,0),Math.max(Math.abs(y)-600,0));
 for(let i=0;i<4;i++){const p=rotate(x,y,-i);d=Math.min(d,sector(...p).distance);}
 return d;
}
function height(x,y){
 const major=Math.max(Math.abs(x),Math.abs(y)),minor=Math.min(Math.abs(x),Math.abs(y));
 if(major<600||(major===600&&minor<=224))return S.poolBed;
 let forestHeight=S.landHeight;
 for(let i=0;i<4;i++){
  const p=rotate(x,y,-i),q=sector(...p);
  if(q.distance===0)return q.z;
  // Narrow exposed cliff shoulders replace broad grassy ramps. Woodland tops
  // remain level; only the outer shore and the rock face drop to the low path.
  for(const [bounds,z] of [[lane,laneElevation(clamp(p[0],lane.x0,lane.x1))],
   [cornerLow,S.laneHeight],[cornerStairs,stairElevation(p[1])]]){
   const d=rectDistance(...p,bounds);
   // Recess the lane's bank behind a low stone toe. This fits natural-size
   // boulders inside the blocked strip instead of stretching them into spikes.
   const outerBend=bounds===cornerLow||(bounds===cornerStairs&&p[0]>cornerStairs.x1);
   const bank=bounds===lane?smooth(32,184,d):outerBend?smooth(8,144,d):smooth(0,96,d);
   forestHeight=Math.min(forestHeight,z+(S.landHeight-z)*bank);
  }
 }
 // A low waterside shoulder climbs continuously to the unchanged building
 // lawn. The old 384-high buttresses at x/y=600 made the pool join look cut out.
 const waterDistance=Math.hypot(Math.max(Math.abs(x)-600,0),Math.max(Math.abs(y)-600,0));
 forestHeight=Math.min(forestHeight,128+(S.landHeight-128)*smooth(0,120,waterDistance));
 // A stable rim supports the closing tree belt; the last 32 units form the
 // shoreline face instead of a broad low slope with half-submerged tree roots.
 return forestHeight*(1-smooth(3040,S.radius,Math.hypot(x,y)));
}
function blocked(x,y){return walkDistance(x,y)>0;}
function paint(x,y){
 const n=.5+.23*Math.sin(x*.006+y*.003)+.12*Math.sin(y*.017-x*.011);
 let road=0,courtWear=0;
 for(let i=0;i<4;i++){
  const [u,v]=rotate(x,y,-i);
  const approach=segmentDistance(u,v,[600,0],[2100,0]);
  road=Math.max(road,(1-smooth(85,235,Math.min(approach,turnDistance(u,v))))*.94);
  if(inRect(u,v,court)){
   const center=Math.hypot(u-1420,v-1116);
   const path=segmentDistance(u,v,[1960,760],[1240,1380]);
   const patch=.5+.25*Math.sin(u*.011+v*.004)+.17*Math.sin(u*.006-v*.013);
   courtWear=Math.max(courtWear,.12+.21*(1-smooth(130,850,center))+.19*(1-smooth(35,145,path))+.2*patch);
  }
  if(inRect(u,v,corner))courtWear=Math.max(courtWear,.22+.15*n);
 }
 const wear=clamp(Math.max(road,courtWear)+.055*Math.sin(x*.021)*Math.sin(y*.017));
 const cliff=smooth(2780,S.radius,Math.hypot(x,y))*.35;
 return {blend:[(.1+.15*n)*(1-wear),(1-wear)*(1-cliff),cliff,.48],tint:[1,.99,.91,.12],path:wear};
}
module.exports={...S,court,lane,turn,pads,corner,cornerLow,cornerStairs,cornerHigh,cornerPads,laneElevation,stairElevation,rotate,rectDistance,inRect,turnDistance,walkDistance,height,blocked,paint};
