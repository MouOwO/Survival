const D=require('./layout.cjs'),S=D.sanctuary,shore=require('./shore.cjs'),banks=require('./cliff-banks.cjs'),undergrowth=require('./slope-cover.cjs'),rockCover=require('./rock-cover.cjs'),vergeCover=require('./verge-cover.cjs'),stairCover=require('./stair-cover.cjs');
module.exports=function buildSanctuary({addMesh,prop,marker,random,flame}){
 const [cx,cy]=D.world(D.center.x,D.center.y),wp=(x,y,z)=>[cx+x,cy+y,z];
 const place=(model,x,y,z,scale=1,angle=0,kind='prop_static',skin='0',color='255 255 255')=>prop(model,...D.localPoint(x,y),z,scale,angle,kind,skin,color);
 const quad=(x0,y0,x1,y1,z)=>[[x1,y0,z],[x1,y1,z],[x0,y1,z],[x0,y0,z]];
 const breaks=new Set([-S.radius,S.radius]);
 for(const v of [0,64,224,320,416,600,640,680,696,704,720,1120,1816,1936,1984,2100,2120,2240,2432,2624,2720,3040,3056])
  for(const sign of [-1,1])breaks.add(sign*v);
 for(let v=-3040;v<=3040;v+=80)breaks.add(v);
 const coords=[...breaks].sort((a,b)=>a-b),land=[],bed=[],cliffs=[];
 const emit=points=>{
  for(const polygon of shore.quads(shore.clip(points))){
   const face=polygon.map(([x,y])=>wp(x,y,S.height(x,y))),heights=face.map(p=>p[2]);
   const x=polygon.reduce((s,p)=>s+p[0],0)/4,y=polygon.reduce((s,p)=>s+p[1],0)/4;
   (S.blocked(x,y)&&Math.max(...heights)-Math.min(...heights)>20?cliffs:land).push(face);
  }
 };
 for(let j=0;j<coords.length-1;j++)for(let i=0;i<coords.length-1;i++){
  const x0=coords[i],x1=coords[i+1],y0=coords[j],y1=coords[j+1],x=(x0+x1)/2,y=(y0+y1)/2;
  if(S.rectDistance(0,0,{x0,y0,x1,y1})>S.radius)continue;
  if(Math.abs(x)<600&&Math.abs(y)<600){bed.push(quad(x0,y0,x1,y1,S.poolBed).map(p=>wp(...p)));continue;}
  const cells=quad(x0,y0,x1,y1,0).map(p=>p.slice(0,2));
  const elevations=cells.map(p=>S.height(...p));
  const outer=cells.some(p=>Math.hypot(...p)>2992);
  const steep=S.blocked(x,y)&&Math.max(...elevations)-Math.min(...elevations)>32;
  if(outer||steep){
   const step=outer?16:24,nx=Math.ceil((x1-x0)/step),ny=Math.ceil((y1-y0)/step);
   for(let sy=0;sy<ny;sy++)for(let sx=0;sx<nx;sx++)
    emit(quad(x0+(x1-x0)*sx/nx,y0+(y1-y0)*sy/ny,x0+(x1-x0)*(sx+1)/nx,y0+(y1-y0)*(sy+1)/ny,0).map(p=>p.slice(0,2)));
  }else emit(cells);
 }
 addMesh(land,'materials/blends/mod_radiant_000.vmat',(x,y)=>S.paint(x-cx,y-cy));
 addMesh(cliffs,'materials/nature/river_rock001.vmat');
 addMesh(bed,'materials/blends/mod_radiant_riverbed_000.vmat',()=>({blend:[0,1,0,.3],tint:[1,1,1,0]}));
 // Original Tile Grid river at Z16, with a visible shallow bed only in the pool.
 const trim=[];
 let cliffProps=0;const bankRocks=[],surfaceRocks=[],surfaceStairs=[];
 for(let id=0;id<4;id++){
  const local=(x,y)=>S.rotate(x,y,id),toWorld=(x,y,z)=>wp(...local(x,y),z);
  const at=(model,x,y,z,scale=1,yaw=0,kind='prop_static',skin='0',color='255 255 255')=>{
   if(id===0&&model.includes('riveredge_rock'))surfaceRocks.push({model:model.match(/riveredge_rock(.+)\.vmdl/)[1],position:[x,y,z],scale,yaw});
   if(id===0&&model.includes('good_stairs001'))surfaceStairs.push({model,position:[x,y,z],scale,yaw});
   place(model,...local(x,y),z,scale,yaw-id*90,kind,skin,color);
  };
  // A is now at water level. Three original stone flights at the outer bend
  // climb north into the high landing without taking any area from the lawn.
  const flightRun=(S.stairEnd-S.stairStart)/3,flightRise=(S.landHeight-S.laneHeight)/3;
  for(let flight=0;flight<3;flight++)
   at('models/props_structures/good_stairs001.vmdl',2432,S.stairStart+flight*flightRun+48.27807*flightRun/242.43662,
    S.laneHeight+flight*flightRise+1.64347*flightRise/146.63241,
    [S.stairWidth/845.00688,flightRun/242.43662,flightRise/146.63241],0);
  for(const [u0,u1] of [[-600,-224],[224,600]]){
   // Match the bank edge exactly instead of leaving a gap above a fixed wall.
   for(let u=u0;u<u1;u+=80){
    const v=Math.min(u+80,u1),z0=S.height(600,u),z1=S.height(600,v);
    trim.push([[600,u,S.poolBed],[600,u,z0],[600,v,z1],[600,v,S.poolBed]].map(p=>toWorld(...p)));
   }
  }
  // Uniform-scale native boulders retain their rock silhouette. The previous
  // thin X / stretched Z props exposed a regular row of smooth pointed teeth.
  // Three interlocked courses fit wholly within the 192-unit blocked shoulder.
  for(const side of [-1,1])for(let row=0;row<3;row++)for(let j=0;j<7;j++){
   const variant=(j+row*2)%3,model=variant===0?'009a':variant===1?'010a':'005a';
   const scale=(variant===0?.55:variant===1?.59:.87)+(j%3)*.015;
   const top=variant===0?288.58884:variant===1?288.01114:160.34778;
   const x=766+j*192+(row===1?47:0)+((j*17)%27),y=side*(320+((j+row)%3-1)*3);
   const crown=[-12,7,-5,15,-8,3,10][j];
   const z=row===2?384-top*scale+crown:(row===1?111+(j%3)*13:4+(j%4)*7);
   at('models/props_rock/riveredge_rock'+model+'.vmdl',x,y,z,
    scale,(side>0?-90:90)+((j*7+row*5)%17-8));
   cliffProps++;
  }
  const sideRocks=banks.build(S,at);cliffProps+=sideRocks.length;
  if(id===0)bankRocks.push(...sideRocks);
  // A low irregular stone toe hides the square pool retaining seam. Rounded
  // native boulders are partly buried; no rigid row of fractured pillars.
  for(const side of [-1,1])for(let j=0;j<4;j++){
   const u=322+j*81,model=['006a','008a','007a','006a'][j];
   at('models/props_rock/riveredge_rock'+model+'.vmdl',626+(j%2)*10,side*u,2+(j%3)*8,.69,(j%2)*10-5);
   at('models/props_rock/riveredge_rock'+model+'.vmdl',650+(j%2)*4,side*(u+16),S.height(677,u+16)-75,.5,(j%2)*12-6);
   cliffProps+=2;
  }
  [...S.pads,...S.cornerPads].forEach(([x,y],index)=>{
   // Invisible editor anchors only. No circular graphic or decorative pad.
   const name=index<S.pads.length?'turret_'+(index+1):'corner_'+(index-S.pads.length+1);
   marker('c6_player_'+id+'_'+name,...D.localPoint(...local(x,y)),S.height(...local(x,y))+16);
  });
 }
 addMesh(trim,'materials/nature/river_rock001.vmat');
 const rocks=['models/props_rock/riveredge_rock009a.vmdl','models/props_rock/riveredge_rock010a.vmdl','models/props_rock/riveredge_rock006a.vmdl'];
 let treeCount=0,rockCount=0,coverCount=0;
 // Native assets kept outside all gameplay footprints, including the firing
 // strips and the full B-to-clearing turns. Colour varies within every quarter.
 for(let gy=-2960;gy<=2960;gy+=196)for(let gx=-2960;gx<=2960;gx+=196){
  const x=gx+(random()-.5)*80,y=gy+(random()-.5)*80,r=Math.hypot(x,y);
  if(r>2990||S.walkDistance(x,y)<190||S.height(x,y)<65)continue;
  const v=random(),flower=v<.22,autumn=v>=.22&&v<.48,gold=v>=.48&&v<.61;
  const model=flower?'tree_oak_spring_01':autumn?'tree_oak_autumn_01':gold?'tree_oak_01':v<.82?'tree_pine_01':'tree_oak_01';
  place('models/props_tree/'+model+'.vmdl',x,y,S.height(x,y)-8,.85+random()*.22,random()*360,'ent_dota_tree_showcase',flower?'11':autumn?'2':gold?'1':'0');
  treeCount++;
 }
 // The opposite (non-firing) bank has a continuous tree belt in all four
 // rotations. A random perimeter alone left one bank looking misleadingly open.
 for(let id=0;id<4;id++)for(let j=0;j<5;j++){
  const [x,y]=S.rotate(960+j*200,-480,id),variant=(id+j)%4;
  const model=variant===0?'tree_oak_spring_01':variant===1?'tree_oak_autumn_01':variant===2?'tree_pine_01':'tree_oak_01';
  place('models/props_tree/'+model+'.vmdl',x,y,S.height(x,y)-8,.85,random()*360,'ent_dota_tree_showcase',variant===0?'11':variant===1?'2':'0');
  treeCount++;
 }
 // An explicit closed ring, rather than chance placement, seals every angle.
 // Broad oak canopies overlap at 109-unit spacing. All trunks stay >190 units
 // outside gameplay floors; a staggered inner row thickens the wooded edge.
 const outerCanopy=[];let innerCanopy=0;
 const palette=[['tree_oak_01','0'],['tree_oak_01','0'],['tree_oak_autumn_01','2'],['tree_oak_spring_01','11'],['tree_oak_01','1'],['tree_oak_spring_01','3']];
 for(let i=0;i<176;i++){
  const a=i*Math.PI*2/176,r=3056,x=r*Math.cos(a),y=r*Math.sin(a),[name,skin]=palette[Math.floor(i/3)%palette.length];
  place('models/props_tree/'+name+'.vmdl',x,y,S.height(x,y)-28,1.16+(i%3)*.035,(i*137.5)%360,'ent_dota_tree_showcase',skin);
  outerCanopy.push([x,y]);treeCount++;
  if(i%2===0){const a2=a+Math.PI/176,ix=2912*Math.cos(a2),iy=2912*Math.sin(a2);
   if(S.walkDistance(ix,iy)>=190){const [iname,iskin]=palette[(Math.floor(i/3)+2)%palette.length];
    place('models/props_tree/'+iname+'.vmdl',ix,iy,S.height(ix,iy)-8,1.08,((i+1)*137.5)%360,'ent_dota_tree_showcase',iskin);treeCount++;innerCanopy++;
   }
  }
 }
 // Broken shoreline rock clusters, low enough not to dwarf the courts.
 for(let i=0;i<78;i++){
  const a=i*Math.PI*2/78,r=3064+(random()-.5)*12,x=r*Math.cos(a),y=r*Math.sin(a);
  if(S.walkDistance(x,y)<110)continue;
  place(rocks[i%rocks.length],x,y,S.height(x,y)-92,.68+random()*.2,a*180/Math.PI+90);
  rockCount++;
 }
 const cover=['fern001','flowers001','flowers002','grass_clump_00a','bush_00','bush_spring_00','leaf_pile','petals_00'];
 for(let i=0;i<650;i++){
  const x=(random()-.5)*6100,y=(random()-.5)*6100,r=Math.hypot(x,y),d=S.walkDistance(x,y);
  if(r>3010||d<110||S.height(x,y)<300)continue;
  // Keep the shelf-facing low bank clear as well as the actual buildable ground.
  let bank=false;for(let id=0;id<4;id++){const [u,v]=S.rotate(x,y,-id);if(u>640&&u<1950&&v>180&&v<460)bank=true;}
  if(bank)continue;
  place('models/props_nature/'+cover[i%cover.length]+'.vmdl',x,y,S.height(x,y)+2,.55+random()*.65,random()*360);
  coverCount++;
 }
 for(const sx of [-1,1])for(const sy of [-1,1]){
  place('models/props_nature/lily_pads001.vmdl',sx*510,sy*500,17,.55,random()*360);
  place('models/props_nature/cattails001.vmdl',sx*575,sy*475,0,.65,random()*360);
 }
 // Building lawns and landing floors deliberately contain no art props.
 const slopeCover=undergrowth.build(S,place);
 const rockGreenery=rockCover.build(S,place,surfaceRocks);
 const vergeGreenery=vergeCover.build(S,place,surfaceRocks);
 const stairGreenery=stairCover.build(S,place,surfaceRocks,surfaceStairs);
 const courtDetails=0;
 for(const p of D.players){
  marker('player_'+p.id+'_builder_spawn',p.x,p.y,p.z);
  marker('monsterborn_player'+(p.id+1),p.ax,p.ay,p.spawnZ);
  marker('c6_player_'+p.id+'_entrance',p.ex,p.ey,p.entranceZ);
 }
 return {layout:'09-folded-four-rotations',reference:'art/maps/c6/folded-reference.png',
  poolSide:S.poolSide,clearingDepth:S.clearingDepth,clearingWidth:S.clearingWidth,
  approachLength:S.approachLength,rampLength:S.rampLength,rampWidth:S.rampWidth,
  landHeight:S.landHeight,laneHeight:S.laneHeight,heightIncrement:S.heightIncrement,forestRidgeHeight:0,forestBlocking:'native GridNav',poolBed:4,poolSurface:S.poolSurface,radius:S.radius,
  canonicalCourt:S.court,canonicalTurn:S.turn,cornerPlatform:S.corner,cornerPads:S.cornerPads,
  lowerLanding:S.cornerLow,upperLanding:S.cornerHigh,stairs:S.cornerStairs,stairFlights:12,cliffProps,bankRocks,
  turretPads:S.pads,buildStripDepth:S.buildStripDepth,
  landQuads:land.length,cliffQuads:cliffs.length,visiblePadRings:0,trees:treeCount,outerCanopy,innerCanopy,treeColor:'native material groups, neutral rendercolor',rocks:rockCount,groundCover:coverCount,slopeCover,rockGreenery,vergeGreenery,stairGreenery,courtDetails};
};
