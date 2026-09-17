// Added after runtime terrain/navigation review. Existing native assets only.
const scenery=[],occupied=new Set();
const nature='models/props_nature/';
const palettesScenery={
 forest:['fern002','bush_spring_01','flowers001','grass_clump_00b','mushroom_wild001','chipped_rocks002'],
 snow:['river_rocks001','grass_clump_snow_00a','chipped_rocks002','branches001'],
 thaw:['fern002','grass_clump_snow_00a','bush_spring_00','chipped_rocks001'],
 volcanic:['chipped_rocks001','river_rocks003','branches002','campfire_rocks002'],
 corrupt:['branches002','stump001','chipped_rocks003','bush_00']
};
function sceneryPlace(x,y,t,index){
 t=t.replace('martial_','');
 const a=at(x,y);if(!a||a.material===M.water||nativePreserved(x,y)||markers.some(m=>Math.hypot(x-m.x,y-m.y)<340))return false;
 if(Math.hypot(terrainHeight(x+32,y)-terrainHeight(x-32,y),terrainHeight(x,y+32)-terrainHeight(x,y-32))>40)return false;
 const k=Math.round(x/85)+','+Math.round(y/85);if(occupied.has(k))return false;occupied.add(k);
 const names=palettesScenery[t],name=names[index%names.length],model=nature+name+'.vmdl',scale=name.includes('bush')?.42+rnd()*.24:name.includes('mushroom')?.14+rnd()*.11:.48+rnd()*.46;
 entity('prop_static','landscape_detail_'+scenery.length,[x,y,surface(x,y)],{model,solid:'0',body:'0',skin:'0',rendercolor:t==='snow'?'205 216 220':t==='volcanic'?'112 99 91':'173 186 157',renderamt:'255'},`0 ${rnd()*360} 0`,scale);
 scenery.push({x,y,theme:t,model});return true;
}
for(const a of land){if(a.nativeReuse)continue;const p=a.polygon,c=p.reduce((s,v)=>[s[0]+v[0]/p.length,s[1]+v[1]/p.length],[0,0]),perimeter=p.reduce((n,v,i)=>n+Math.hypot(v[0]-p[(i+1)%p.length][0],v[1]-p[(i+1)%p.length][1]),0),groups=Math.min(32,Math.max(8,Math.floor(perimeter/650)));
 for(let g=0;g<groups;g++){const j=Math.floor(rnd()*p.length),u=.15+rnd()*.7,edge=[p[j][0]*(1-u)+p[(j+1)%p.length][0]*u,p[j][1]*(1-u)+p[(j+1)%p.length][1]*u],factor=.72+rnd()*.20,cx=c[0]+(edge[0]-c[0])*factor,cy=c[1]+(edge[1]-c[1])*factor,t=localTheme(cx,cy);
  for(let k=0;k<5;k++)sceneryPlace(cx+(rnd()-.5)*250,cy+(rnd()-.5)*250,t,g+k);
 }
}
// Readable landmarks in small groups; leave the centers free for units and skills.
function artProp(x,y,model,scale=1,t='forest',angle=0){
 if(!at(x,y)||at(x,y).material===M.water||nativePreserved(x,y)||markers.some(m=>Math.hypot(x-m.x,y-m.y)<400))return;
 entity('prop_static','native_art_'+scenery.length,[x,y,surface(x,y)],{model,solid:'0',body:'0',skin:'0',rendercolor:'255 255 255',renderamt:'255'},`0 ${angle} 0`,scale);
 scenery.push({x,y,theme:t,model});
}
for(const a of land){
 if(a.nativeReuse)continue;const p=a.polygon,c=p.reduce((s,v)=>[s[0]+v[0]/p.length,s[1]+v[1]/p.length],[0,0]),t=theme(a);
 const selected=a.name.includes('camp')||a.name.includes('training')||a.name.includes('commandment')||a.material===M.corrupt||a.material===M.lava;
 if(!selected)continue;
 for(let i=0;i<p.length;i+=2){const x=c[0]+(p[i][0]-c[0])*.66,y=c[1]+(p[i][1]-c[1])*.66;
  if(t==='snow')artProp(x,y,'maps/cavern_assets/models/crystals/crystal03.vmdl',.40,t,i*43);
  else if(t==='volcanic')artProp(x,y,'models/props_nature/river_rocks003.vmdl',1.2,t,i*43);
  else if(t==='corrupt'){artProp(x,y,'models/props_structures/grate001.vmdl',1.3,t);if(i%4===0)artProp(x+180,y+120,'models/props_structures/cage001.vmdl',.8,t);}
  else {const model=a.name.includes('gold')?'maps/ti10_assets/trees/ti10_goldenbirch001.vmdl':a.name.includes('n31')?'maps/journey_assets/props/trees/journey_maple/journey_maple02.vmdl':'models/props_tree/newbloom_tree.vmdl';artProp(x,y,model,.80,t,i*53);}
 }
}
fs.writeFileSync(path.join(OUT,'scenery_design.json'),JSON.stringify({count:scenery.length,markerClearance:340,collision:'none',assets:'native Dota environment library',instances:scenery},null,2));
