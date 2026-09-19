// Replace the deeply sloping inner cliff tiles with native Oriental retaining walls.
// Their collision comes from closed stone backing, not decorative prop collision.
const islandBankArt={outward:512,waterWidth:1152,waterLength:4608,banks:[],gardens:[]};
// Four bevelled corner platforms replace the remaining native inward-curving tips.
for(let q=0;q<4;q++){
 const p=[[640,704],[704,640],[896,640],[896,896],[640,896]].map(v=>originalIsland.worldPoint(...v,q));
 prism(p,768,372,'materials/survival_world_v2/island_stairs.vmat','materials/survival_world_v2/island_stairs.vmat','255 255 255 255');
 for(const [r,v,angle]of [[768,608,0],[608,768,90]]){
  const xy=originalIsland.worldPoint(r,v,q);
  entity('prop_static',`island_bank_corner_${q}_${angle}`,[...xy,420],{model:'maps/journey_assets/props/walls_384/wall_jrny_radiant_384_str_1.vmdl',solid:'0',rendercolor:'219 217 204'},`0 ${q*90+angle} 0`,.75);
 }
 const rock=originalIsland.worldPoint(704,704,q);
 entity('prop_static',`island_bank_cornerstone_${q}`,[...rock,660],{model:'models/props_nature/river_rocks001.vmdl',solid:'0',rendercolor:'190 205 200'},`0 ${q*90} 0`,.7);
}
for(let q=0;q<4;q++)for(const side of [-1,1]){
 const pt=(r,v)=>originalIsland.worldPoint(r,side*v,q);
 const outline=[[896,640],[2432,640],[2432,896],[896,896]].map(v=>pt(...v));
 if(side<0)outline.reverse();
 prism(outline,768,372,'materials/survival_world_v2/island_stairs.vmat','materials/survival_world_v2/island_stairs.vmat','255 255 255 255');
 for(let i=0;i<8;i++){
  const p=pt(992+i*192,608),model='maps/journey_assets/props/walls_384/wall_jrny_radiant_384_str_1.vmdl';
  entity('prop_static',`island_bank_wall_${q}_${side}_${i}`,[...p,420],{model,solid:'0',rendercolor:'219 217 204'},`0 ${q*90+(side<0?180:0)} 0`,.75);
  islandBankArt.banks.push({q,side,x:p[0],y:p[1],z:420,model});
 }
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
