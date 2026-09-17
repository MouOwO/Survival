const terrainPaint=[];
function inside(x,y,p){let c=false;for(let i=0,j=p.length-1;i<p.length;j=i++){const a=p[i],b=p[j];if(((a[1]>y)!=(b[1]>y))&&x<(b[0]-a[0])*(y-a[1])/(b[1]-a[1])+a[0])c=!c;}return c;}
function platform(name,p,z=384,material=M.grass,room=false){const a={name,polygon:p,z,material,room};land.push(a);terrainPaint.push(a);if(room)rooms.push(name);}
function water(name,x1,y1,x2,y2){const a={name,polygon:rect(x1,y1,x2,y2,.5),z:0,material:M.water};waters.push(a);terrainPaint.push(a);}
function paving(p,z,material=M.stone){terrainPaint.push({name:'paving',polygon:inset(p,.82),z,material});}
function room(name,x,y,w=13,h=10){
 const type=name.split('_').slice(2).join('_'),top=y<20,z=top?256:640;
 const biome=type==='gold'?'autumn':type==='attributes'?'snow':type==='greater_attributes'?'dire':'forest';
 const material=biome==='snow'?M.snow:biome==='dire'?M.lava:biome==='autumn'?M.dirt:M.grass;
 const p=rect(x,y,x+w,y+h,1);platform(name,p,z,material,true);land[land.length-1].biome=biome;
 mark(name+'_center',x+w/2,y+h/2,z);
 const models={forest:'models/props_tree/tree_oak_spring_01.vmdl',autumn:'maps/ti10_assets/trees/ti10_goldenbirch001.vmdl',snow:'models/props_tree/tree_pine_01_heavysnow.vmdl',dire:'models/props_tree/dire_tree007.vmdl'};
 const old=P.tree;P.tree=models[biome];edge(p,z,'tree',220,.8);P.tree=old;
 for(let j=0;j<4;j++){const xx=x+1.8+j*(w-3.6)/3;prop('rock',xx,y+1,z-.05,1.1,j*77);}
 if(biome==='autumn')entity('prop_static',name+'_shrine',[X(x+w/2),Y(y+2),z],{model:'models/props_structures/temple_statue001.vmdl',solid:'0'},'0 180 0',.65);
}
// INSERT REGIONS
const NAME='survival_world_v2';
// Architectural accents from the same native TI10 palette used by the reference.
for(const a of land.filter(a=>a.name.startsWith('commandment_'))){
 const p=a.polygon,c=p.reduce((s,v)=>[s[0]+v[0]/p.length,s[1]+v[1]/p.length],[0,0]);
 for(const index of [0,2,4,6]){const v=p[index];entity('prop_static','ti10_corner_'+node,[c[0]+(v[0]-c[0])*.88,c[1]+(v[1]-c[1])*.88,a.z],{model:'maps/ti10_assets/column/column_ti10_01.vmdl',solid:'0'},'0 0 0',.65);}
}
// Spatial index keeps million-sample paint evaluation fast and deterministic.
const bins=new Map();for(const a of terrainPaint){const p=a.polygon;a.bb=[Math.min(...p.map(v=>v[0])),Math.min(...p.map(v=>v[1])),Math.max(...p.map(v=>v[0])),Math.max(...p.map(v=>v[1]))];for(let y=Math.floor(a.bb[1]/512);y<=Math.floor(a.bb[3]/512);y++)for(let x=Math.floor(a.bb[0]/512);x<=Math.floor(a.bb[2]/512);x++){const k=x+','+y;if(!bins.has(k))bins.set(k,[]);bins.get(k).push(a);}}
function at(x,y){const a=bins.get(Math.floor(x/512)+','+Math.floor(y/512))||[];for(let i=a.length-1;i>=0;i--)if(inside(x,y,a[i].polygon))return a[i];return null;}
function heightAt(x,y){const a=at(x,y);if(a)return a.material===M.water&&!a.shallow?3:Math.max(1,Math.round(a.z/128));const noise=(Math.sin(x/1100+y/1600)+Math.cos(y/1000-x/1400)+2)/4;return 5+Math.floor(noise*5);}
const heights=Array.from({length:16641},(_,i)=>heightAt(-16384+(i%129)*256,-16384+Math.floor(i/129)*256));
// Native cliff tiles support one height step per edge. Relax steep transitions.
for(let pass=0;pass<12;pass++)for(let y=0;y<129;y++)for(let x=0;x<129;x++){const i=y*129+x;for(let dy=-1;dy<=1;dy++)for(let dx=-1;dx<=1;dx++)if(x+dx>=0&&x+dx<129&&y+dy>=0&&y+dy<129)heights[i]=Math.min(heights[i],heights[(y+dy)*129+x+dx]+1);}
for(let i=0;i<heights.length;i++){const h=originalIsland.height(-16384+i%129*256,-16384+Math.floor(i/129)*256);if(h!==null)heights[i]=h;}
function nativeSurface(x,y){const ix=Math.max(0,Math.min(127,Math.floor((x+16384)/256))),iy=Math.max(0,Math.min(127,Math.floor((y+16384)/256)));return Math.max(heights[iy*129+ix],heights[iy*129+ix+1],heights[(iy+1)*129+ix],heights[(iy+1)*129+ix+1])*128;}
// Continuous native foundation; all room biomes are authored by the masked surface mesh.
// Mixing tile sets underneath those caps exposes square snow/autumn strips at cliffs.
function biomeAt(a){return a?0:1;}
// Existing foliage palettes observed in Treasure and Truth; scatter only around margins.
const details=['models/props_nature/fern002.vmdl','models/props_nature/bush_spring_01.vmdl','models/props_nature/flowers001.vmdl','models/props_nature/campfire_rocks002.vmdl'];
let seed=20260912;function rnd(){seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed/4294967296;}
// Additional small scenery is authored after the terrain and transitions are reviewed.
// INSERT SURFACES
// INSERT SCENERY
for(let i=0;i<300;i++){const x=-15400+rnd()*30800,y=-15000+rnd()*30000;if(springRadius(x,y)<2.2||at(x,y)||at(x+220,y)||at(x-220,y)||at(x,y+220)||at(x,y-220))continue;entity('prop_static','ridge_rock_'+i,[x,y,surface(x,y)],{model:'models/props_nature/river_rocks00'+(1+i%3)+'.vmdl',solid:'0',rendercolor:'106 118 119',renderamt:'255'},`0 ${rnd()*360} 0`,2+rnd()*3);}
const lighting=JSON.parse(fs.readFileSync(path.resolve(__dirname,'../output/reference_asset_study/lighting.json'),'utf8'));
for(const [cls,props]of Object.entries(lighting)){for(const k of Object.keys(props))if(k.endsWith('map_texture')||k==='height_fog_textureopacity')delete props[k];if(cls==='ent_dota_lightinfo'){for(const time of ['day','night'])Object.assign(props,{['color_'+time]:'232 226 211 255',['light_scale_'+time]:'4',['ambient_color_'+time]:'164 189 217 255',['ambient_scale_'+time]:'1.7',['fog_start_'+time]:'20000',['fog_end_'+time]:'40000',['fog_height_'+time]:'0',['fow_darkess_'+time]:'1',['light_direction_'+time]:'66 330 0'});props.farz_override='45000';}else Object.assign(props,{color:'232 226 211 255',lightscale:'4',ambientcolor1:'164 189 217 255',ambientscale1:'1.7',fow_darkness:'1'});entity(cls,NAME+'_'+cls,[0,0,2500],props,'66 330 0');}
entity('env_tonemap_controller','daylight_exposure',[0,0,0],{minexposure:'.7',maxexposure:'1.3',master:'1',rate:'2'});
entity('world_bounds','world_bounds',[0,0,0],{min:'-16384 -16384 0',max:'16384 16384 0'});
entity('info_player_start_goodguys','player_start',[X(158),Y(79)+3200,550]);entity('info_player_start','editor_start',[X(158),Y(79)+3200,550]);entity('info_player_start_badguys','enemy_start',[X(30),Y(48),550]);entity('ent_dota_game_events','game_events',[0,0,0]);
for(let i=0;i<4;i++){const p=originalIsland.transform(512,128,i);entity('info_target','player_'+i+'_builder_spawn',[...p,400]);}
function closing(s,start,open,close){let depth=0,quoted=false;for(let i=start;i<s.length;i++){if(s[i]==='"'&&s[i-1]!=='\\')quoted=!quoted;if(!quoted){if(s[i]===open)depth++;if(s[i]===close&&--depth===0)return i;}}throw Error('Unbalanced');}
let template=fs.readFileSync(path.resolve(__dirname,'../output/zombie_island_v1/source_template.vmap'),'utf8');template=template.slice(template.indexOf('"CMapRootElement"'));
const wa=template.indexOf('"world" "CMapWorld"'),wb=template.indexOf('{',wa),we=closing(template,wb,'{','}');let w=template.slice(wa,we+1),ca=w.indexOf('"children" "element_array"'),cb=w.indexOf('[',ca),ce=closing(w,cb,'[',']');let grid=w.slice(cb+1,ce).trim();
grid=grid.replace('"-8192 -8192 128"','"-16384 -16384 0"').replace('"gridWidth" "int" "64"','"gridWidth" "int" "128"').replace('"gridHeight" "int" "64"','"gridHeight" "int" "128"');
grid=grid.replaceAll('radiant_summer_basic.vmap','radiant_autumn_basic.vmap');
grid=grid.replaceAll('maps/tilesets/','maps/tilesets/world_v2/');
const counts={4096:16384,4225:16641,8320:33024,66049:263169,65536:262144,263169:1050625};
grid=grid.replace(/^(\t{6})"([^"]+)" "(\w+)_array"\s*\[([^\]]*)\]/gm,(all,indent,k,t,body)=>{
 if(t==='element')return all;const values=[...body.matchAll(/"([^"]*)"/g)].map(m=>m[1]);if(/^(cell|object)Configuration/.test(k))return indent+arr(k,t,[]);const count=counts[values.length];if(!count)return all;
 let fill='0';if(/VariationId/.test(k))fill='255';if(k==='blendOpacity')fill='0 255 0 128';if(k==='blendColor')fill='255 255 255 0';if(k==='blendTransitionAndPath')fill='0 255 0 0';if(k==='blendHeight')fill='128';if(k==='grassOpacity')fill='210';if(k==='flowMap'||k==='fogFlowMap')fill='10 20 0 0';const a=Array(count).fill(fill);
 if(k==='cellsTileSet')for(let y=0;y<128;y++)for(let x=0;x<128;x++)a[y*128+x]=biomeAt(at(-16384+x*256+128,-16384+y*256+128));
 if(k==='verticesHeight'||k==='verticesWater')for(let y=0;y<=128;y++)for(let x=0;x<=128;x++){const wx=-16384+x*256,wy=-16384+y*256;a[y*129+x]=k==='verticesHeight'?heights[y*129+x]:(at(wx,wy)?.material===M.water&&!at(wx,wy)?.shallow?1:0);}
 if(k==='gridnavFlags')for(let y=0;y<512;y++)for(let x=0;x<512;x++){const wx=-16384+x*64+32,wy=-16384+y*64+32,b=at(wx,wy);a[y*512+x]=b&&(b.material!==M.water||b.shallow)&&!blockedAreas.some(p=>inside(wx,wy,p))?0:1;}
 if(k==='blendOpacity'||k==='grassOpacity'||k==='blendTransitionAndPath')for(let y=0;y<=1024;y++)for(let x=0;x<=1024;x++){const b=at(-16384+x*32,-16384+y*32),stone=b&&(b.material===M.paving||b.material===M.stone),dirt=b&&b.material===M.dirt;let v=k==='blendOpacity'?(dirt?Math.round(200*smooth(edgeDistance(-16384+x*32,-16384+y*32,b.polygon)/280))+' 255 0 128':'0 255 0 128'):k==='grassOpacity'?0:'0 255 0 0';a[y*1025+x]=v;}
 // Copy all authored paint, paths, variations and object data in one common grid.
 for(let i=0;i<count;i++){
  let x,y,vertical=false;
  if(count===16384){x=-16384+i%128*256+128;y=-16384+Math.floor(i/128)*256+128;}
  else if(count===16641){x=-16384+i%129*256;y=-16384+Math.floor(i/129)*256;}
  else if(count===33024){const r=i%257,row=Math.floor(i/257);vertical=row<128&&r%2===0;x=-16384+(row<128?Math.floor(r/2):r)*256;y=-16384+row*256;}
  else if(count===263169){x=-16384+i%513*64;y=-16384+Math.floor(i/513)*64;}
  else if(count===262144){x=-16384+i%512*64+32;y=-16384+Math.floor(i/512)*64+32;}
  else if(count===1050625){x=-16384+i%1025*32;y=-16384+Math.floor(i/1025)*32;}
  if(x!==undefined)a[i]=originalIsland.sample(k,x,y,a[i],vertical);
  if(k==='cellsHidden')a[i]=nativePreserved(x,y)||at(x,y)?.material===M.water?0:1;
  // Outside the preserved island the native grid only renders sea. Keep all of
  // its vertices flat and wet, so partial shoreline tiles cannot emit old cliffs.
  if(k==='verticesHeight'&&!nativePreserved(x,y))a[i]=3;
  if(k==='verticesWater'&&!nativePreserved(x,y))a[i]=1;
 }
 return indent+arr(k,t,a);
});
// Align scenery and markers to the native grid surface, retaining their authored scale.
for(let i=0;i<children.length;i++)if(children[i].includes('"prop_static"')||children[i].includes('"ent_dota_tree"')||children[i].includes('"info_target"'))children[i]=children[i].replace(/"origin" "vector3" "([^\"]+)"/,(m,p)=>{const v=p.split(' ').map(Number);v[2]=surface(v[0],v[1]);return '"origin" "vector3" "'+v.join(' ')+'"';});
for(const m of markers)m.z=surface(m.x,m.y);
w=w.slice(0,cb+1)+grid+',\n'+children.join(',\n')+w.slice(ce);template=template.slice(0,wa)+w+template.slice(we+1);
fs.writeFileSync(path.join(OUT,NAME+'.vmap'),'<!-- dmx encoding keyvalues2 4 format vmap 40 -->\n'+template);
fs.writeFileSync(path.join(OUT,'layout.json'),JSON.stringify({map:NAME,tileGrid:[128,128],bounds:[-16384,-16384,16384,16384],land,waters,markers,rooms:rooms.length,entities:node-10},null,2));
console.log(JSON.stringify({map:NAME,rooms:rooms.length,entities:node-10}));
