// Combat rooms: sparse weathered courtyards, native Valve assets only.
// Run after the previous scatter so its random sequence and other areas stay stable.
const combatRooms=land.filter(a=>a.combatArt);
const inCombat=(x,y)=>combatRooms.find(a=>x>=a.bb[0]&&x<=a.bb[2]&&y>=a.bb[1]&&y<=a.bb[3]&&inside(x,y,a.polygon));
const martialArt={theme:'肃杀的日式荒寺庭院',rooms:[],removedProps:0,removedTrees:0,instances:[]};
for(let i=children.length-1;i>=0;i--){
 const s=children[i];if(!s.includes('"prop_static"')&&!s.includes('"ent_dota_tree"'))continue;
 const pos=s.match(/"origin" "vector3" "([^"]+)"/);if(!pos)continue;const [x,y]=pos[1].split(' ').map(Number);if(!inCombat(x,y))continue;
 martialArt.removedProps++;if(/tree|goldenbirch/i.test(s))martialArt.removedTrees++;children.splice(i,1);
}
for(let i=scenery.length-1;i>=0;i--)if(inCombat(scenery[i].x,scenery[i].y))scenery.splice(i,1);
function martialProp(a,x,y,model,scale,yaw,color='154 160 157'){
 if(!inside(x,y,a.polygon)||markers.some(m=>Math.hypot(x-m.x,y-m.y)<400))return;
 entity('prop_static','martial_room_'+martialArt.instances.length,[x,y,surface(x,y)],{model,solid:'0',skin:'0',body:'0',rendercolor:color,renderamt:'255'},`0 ${yaw} 0`,scale);
 const record={room:a.name,x,y,theme:'martial_'+theme(a),model,scale,yaw};scenery.push(record);martialArt.instances.push(record);
}
for(let index=0;index<combatRooms.length;index++){
 const a=combatRooms[index],b=a.bb,c=[(b[0]+b[2])/2,(b[1]+b[3])/2],w=b[2]-b[0],h=b[3]-b[1],start=martialArt.instances.length;
 const point=(u,v)=>[c[0]+u*w/2,c[1]+v*h/2];
 const put=(u,v,model,scale=1,yaw=0,color)=>martialProp(a,...point(u,v),model,scale,yaw,color);
 // Asymmetric corner groups: no dense tree ring and no props in the center.
 const side=index%2?1:-1;
 put(.75*side,.69,'models/props_tree/tree_dead_01.vmdl',.63,index*37,'137 142 140');
 if(w>1400)put(-.78*side,-.62,'models/props_tree/tree_dead_02.vmdl',.55,index*53,'140 144 142');
 put(-.63*side,.76,'models/props_nature/river_rocks002.vmdl',1.3,180,'149 157 150');
 // Short pieces of masonry with wide gaps, rather than a continuous new wall.
 for(const [u,v,yaw]of [[-.25,.83,0],[.28,.83,0],[.83,-.33,90],[-.83,.25,90],[-.32,-.83,0]])
  put(u,v,'maps/journey_assets/props/walls_128/wall_jrny_radiant_128_str_1.vmdl',.72,yaw,'150 158 154');
 for(let i=0;i<9;i++){
  const angle=(i*2.399+index*.31),u=Math.cos(angle)*.80,v=Math.sin(angle)*.80;
  put(u,v,'models/props_nature/'+(i%3===0?'river_rocks003':i%3===1?'chipped_rocks002':'branches001')+'.vmdl',i%3===0?.88:i%3===1?.75:.9,i*79+index*13,'149 157 150');
 }
 put(.65*side,-.61,'models/props_nature/stump001.vmdl',.74,index*31,'147 145 131');
 // More weathered remains on the large original arena; still all at its rim.
 if(w>3000)for(const [u,v,yaw]of [[-.72,-.28,35],[.3,.77,165],[.70,-.35,280]]){
  put(u,v,'maps/journey_assets/props/walls_128/wall_jrny_radiant_128_str_2.vmdl',1.05,yaw);
  put(u+.07,v-.03,'models/props_nature/chipped_rocks003.vmdl',1.15,yaw);
 }
 martialArt.rooms.push({name:a.name,biome:theme(a),props:martialArt.instances.length-start});
}
fs.writeFileSync(path.join(OUT,'martial_rooms_design.json'),JSON.stringify(martialArt,null,2));
fs.writeFileSync(path.join(OUT,'scenery_design.json'),JSON.stringify({count:scenery.length,markerClearance:340,collision:'none',assets:'native Dota environment library',instances:scenery},null,2));
