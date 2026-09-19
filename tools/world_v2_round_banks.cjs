// Retain the gate and eight side flights; remove the former pointed stone arms.
const islandBankArt={outward:512,waterWidth:1152,waterLength:4608,taperStart:1152,taperEnd:2048,gateWaterWidth:640,stairWidth:576,towerStairCutout:{start:2432,end:3072,inner:512,previousOuter:896},banks:[],gardens:[],style:'rounded meadow islands with natural stone shore slopes'};
for(let q=0;q<4;q++)for(const side of [-1,1]){
 const pt=(r,v)=>originalIsland.worldPoint(r,side*v,q);
 const slab=(a,b,lo,hi,z)=>{const p=[[a,lo],[b,lo],[b,hi],[a,hi]].map(v=>pt(...v));if(side<0)p.reverse();nativeIslandPrism(p,z,620,'stair');};
 slab(2432,2560,512,896,768);
 for(let i=0;i<8;i++)slab(2560+i*32,2592+i*32,512,896,768-i*16);
 slab(2816,3072,512,896,642);
}
// Plant groups have exposed soil/grass under their roots. No pavement shrubs.
for(let q=0;q<4;q++){
 const spots=[[3900,-950,'pine'],[2950,1080,'pine'],[4420,100,'peach']];
 for(const [i,[r,v,type]]of spots.entries()){
  const p=originalIsland.worldPoint(r,v,q),z=surface(...p);
  const model=type==='peach'?'models/props_tree/tree_oak_01.vmdl':'maps/journey_assets/props/trees/journey_armandpine/journey_armandpine_01.vmdl';
  entity(type==='peach'?'ent_dota_tree':'prop_static',`island_bank_natural_tree_${q}_${i}`,[...p,z],{model,skin:type==='peach'?'6':'0',body:'1',solid:'0',rendercolor:'225 236 221',renderamt:'255'},`0 ${q*90+i*57} 0`,type==='peach'?.85:1);
  for(let j=0;j<3;j++){
   const a=j*2.1+.7,x=p[0]+Math.cos(a)*100,y=p[1]+Math.sin(a)*100;
   if(originalIsland.round.paint([x,y])[0]<.45||originalIsland.round.stairHole(x,y))continue;
   entity('prop_static',`island_bank_natural_ground_${q}_${i}_${j}`,[x,y,surface(x,y)],{model:j===0?'models/props_nature/river_rocks001.vmdl':'models/props_nature/fern002.vmdl',solid:'0',rendercolor:'184 204 179'},`0 ${j*91} 0`,j===0?.45:.6);
  }
  islandBankArt.gardens.push({q,x:p[0],y:p[1],z,ground:'meadow/soil'});
 }
}
fs.writeFileSync(path.join(OUT,'island_expansion_design.json'),JSON.stringify(islandBankArt,null,2));
