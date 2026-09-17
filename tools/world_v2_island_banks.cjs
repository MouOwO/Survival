// Replace the deeply sloping inner cliff tiles with native Oriental retaining walls.
// Their collision comes from closed stone backing, not decorative prop collision.
const islandBankArt={outward:512,waterWidth:1152,waterLength:4608,taperStart:1152,taperEnd:2048,gateWaterWidth:640,stairWidth:576,towerStairCutout:{start:2432,end:3072,inner:512,previousOuter:896},banks:[],gardens:[]};
// Four bevelled corner platforms replace the remaining native inward-curving tips.
for(let q=0;q<4;q++){
 const p=[[640,704],[704,640],[896,640],[896,896],[640,896]].map(v=>originalIsland.worldPoint(...v,q));
 nativeIslandPrism(p,768,372);
 for(const [r,v,angle]of [[768,608,0],[608,768,90]]){
  const xy=originalIsland.worldPoint(r,v,q);
  entity('prop_static',`island_bank_corner_${q}_${angle}`,[...xy,420],{model:'maps/journey_assets/props/walls_384/wall_jrny_radiant_384_str_1.vmdl',solid:'0',rendercolor:'219 217 204'},`0 ${q*90+angle} 0`,.75);
 }
 const rock=originalIsland.worldPoint(704,704,q);
 entity('prop_static',`island_bank_cornerstone_${q}`,[...rock,660],{model:'models/props_nature/river_rocks001.vmdl',solid:'0',rendercolor:'190 205 200'},`0 ${q*90} 0`,.7);
}
for(let q=0;q<4;q++)for(const side of [-1,1]){
 const pt=(r,v)=>originalIsland.worldPoint(r,side*v,q);
 const edge=r=>r<=2304?originalIsland.channelHalfWidth(r):320-32*Math.min(1,(r-2304)/128);
 const knots=[896,1152,2048,2304,2432,2816,3072];
 for(let k=0;k<knots.length-1;k++){
  // The original 640 -> 768 side stairs start here. Retain the inner gate
  // shoulder, but stop its cap from covering the native outer stair lanes.
  const a=knots[k],b=knots[k+1],outer=a>=2432?512:896,outline=[[a,edge(a)],[b,edge(b)],[b,outer],[a,outer]].map(v=>pt(...v));
  if(side<0)outline.reverse();
  nativeIslandPrism(outline,768,372);
 }
 for(let k=0;k<knots.length-1;k++){
  const a=knots[k],b=knots[k+1],dy=edge(b)-edge(a),distance=Math.hypot(b-a,dy),count=Math.ceil(distance/185);
  for(let i=0;i<count;i++){
   const t=(i+.5)/count,r=a+(b-a)*t,v=edge(a)+dy*t+32;
   const p=pt(r,v),model='maps/journey_assets/props/walls_384/wall_jrny_radiant_384_str_1.vmdl';
   const angle=q*90+Math.atan2(side*dy,b-a)*180/Math.PI+(side<0?180:0);
   entity('prop_static',`island_bank_wall_${q}_${side}_${k}_${i}`,[...p,420],{model,solid:'0',rendercolor:'219 217 204'},` 0 ${angle} 0`,.75);
   islandBankArt.banks.push({q,side,x:p[0],y:p[1],z:420,model});
  }
 }
 // Replace only the obstructed tile strips with closed, walkable treads.
 // The adjacent native ornament and the inner gate shoulders remain in place.
 const slab=(a,b,lo,hi,z)=>{const p=[[a,lo],[b,lo],[b,hi],[a,hi]].map(v=>pt(...v));if(side<0)p.reverse();nativeIslandPrism(p,z,620,'stair');};
 slab(2432,2560,512,896,768);
 for(let i=0;i<8;i++)slab(2560+i*32,2592+i*32,512,896,768-i*16);
 slab(2816,3072,512,896,642);
 slab(3072,3200,384,896,642);
 // Solid shallow coping follows the OUTSIDE of the existing tower stair.
 // Inner edge is exactly v=896; the full 384-unit walking lane stays exposed.
 const cheek=pt(2560,910);
 entity('prop_static',`island_stair_outer_coping_${q}_${side}`,[...cheek,768],{model:'models/xianxia_kit/t08_stair_cheek.vmdl',solid:'0',rendercolor:'195 194 185'},`0 ${q*90} 0`,1);
 // Low plants and isolated flowering trees break up the long bank without hiding towers.
 for(let i=0;i<3;i++){
  const p=pt(1152+i*448,832);
  entity('prop_static',`island_bank_fern_${q}_${side}_${i}`,[...p,768],{model:'models/props_nature/fern002.vmdl',solid:'0',rendercolor:'180 205 185'},`0 ${q*90+i*83} 0`,.8);
 }
}
// Small shrine gardens at the far rim leave the central attack court and side stairs open.
for(let q=0;q<4;q++)for(const side of [-1,1]){
 const p=originalIsland.transform(768,side>0?1024:-768,q);
 if(markers.some(m=>Math.hypot(p[0]-m.x,p[1]-m.y)<500))continue;
 const z=surface(...p);
 entity('ent_dota_tree',`island_blossom_${q}_${side}`,[...p,z],{model:'models/props_tree/tree_oak_01.vmdl',skin:'6',body:'1',solid:'0',rendercolor:'255 255 255',renderamt:'255'},`0 ${q*90+side*30} 0`,1.15);
 for(let i=0;i<3;i++){
  const v=originalIsland.transform(768+(i-1)*128,side>0?1120:-864,q);
  entity('prop_static',`island_garden_rock_${q}_${side}_${i}`,[...v,surface(...v)],{model:'models/props_nature/river_rocks00'+(i+1)+'.vmdl',solid:'0',rendercolor:'195 207 211'},`0 ${q*90+i*71} 0`,.65);
 }
 islandBankArt.gardens.push({q,side,x:p[0],y:p[1],z});
}
fs.writeFileSync(path.join(OUT,'island_expansion_design.json'),JSON.stringify(islandBankArt,null,2));
