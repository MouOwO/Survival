// Builds an editable native Dota tilegrid from the installed project's template.
// Uses native tile configurations from that template, never rasterized concept art.
const fs=require('fs'),path=require('path'),crypto=require('crypto');
const L=require('./lib.cjs'),D=require('./layout.cjs');
const ROOT=path.resolve(__dirname,'../..');
const OUT=path.join(ROOT,'output/map_build_c6');
fs.mkdirSync(OUT,{recursive:true});
const engine=path.resolve(ROOT,'../../..');
// The fixed seed remains separate from the editable main map and disposable output.
{
  require('child_process').execFileSync(path.join(engine,'game/bin/win64/dmxconvert.exe'),[
    '-i',path.join(engine,'content/dota_addons/survival/maps/templates/c6_terrain_seed.vmap'),
    '-o',path.join(OUT,'template_text.vmap'),'-oe','keyvalues2'],{stdio:'inherit'});
}
if(!fs.existsSync(path.join(OUT,'asset_index.txt'))){
  const pak=new L.Vpk(path.join(engine,'game/dota/pak01_dir.vpk'));
  fs.writeFileSync(path.join(OUT,'asset_index.txt'),[...pak.entries.keys()].join('\n'));
}
const source=fs.readFileSync(path.join(OUT,'template_text.vmap'),'utf8');
const native=L.blocks(source,'CMapDotaTileGrid')[0].text;
const grid=L.blocks(native,'CDmeDotaTileGrid')[0];
const old={};
for(const m of grid.text.matchAll(/"(\w+)" "(int|uint8|bool|color)_array"\s*\[([^\]]*)\]/g))
  old[m[1]]=[...m[3].matchAll(/"([^"\r\n]*)"/g)].map(x=>x[1]);
const configs=L.records(old.cellConfiguration),names=L.records(old.cellConfigurationByName);
const variants=new Map();
for(let y=0;y<64;y++)for(let x=0;x<64;x++){
  const c=y*64+x,vs=[y*65+x,y*65+x+1,(y+1)*65+x,(y+1)*65+x+1];
  const key=old.cellsTileSet[c]+':'+vs.map(v=>old.verticesHeight[v]).join(',')+':'+vs.map(v=>old.verticesWater[v]).join('');
  if(!variants.has(key))variants.set(key,[]);variants.get(key).push(c);
}
const N=D.size, V=N+1,O=N*4+1,B=N*8+1;
const arrays={},zero=(n,v=0)=>Array(n).fill(v);
arrays.verticesHeight=[];arrays.verticesWater=[];
for(let y=0;y<=N;y++)for(let x=0;x<=N;x++){
  const r=D.region(x,y);arrays.verticesHeight.push(r.height);arrays.verticesWater.push(r.centralWater||r.central?1:(r.land?0:1));
}
// Diagonally touching single vertices form an ambiguous shoreline. Fill one
// corner deterministically so all water crossings have a real connected bank.
for(let pass=0;pass<2;pass++)for(let y=0;y<N;y++)for(let x=0;x<N;x++){
  const vs=[y*V+x,y*V+x+1,(y+1)*V+x,(y+1)*V+x+1],m=vs.map(v=>arrays.verticesWater[v]).join('');
  if(m==='1001'||m==='0110')arrays.verticesWater[vs[m==='1001'?0:1]]=0;
}
for(const k of ['cellsTileSet','cellsHidden','cellsOrientation','cellsMaterialSet','cellsCustomPathType','cellsVariationId'])arrays[k]=[];
arrays.cellConfiguration=[];arrays.cellConfigurationByName=[];
let fallbacks=0;
for(let y=0;y<N;y++)for(let x=0;x<N;x++){
  const vs=[y*V+x,y*V+x+1,(y+1)*V+x,(y+1)*V+x+1];
  const water=vs.map(v=>arrays.verticesWater[v]).join(''), heights=vs.map(v=>arrays.verticesHeight[v]).join(',');
  const r=D.region(x+.5,y+.5);let ts=water==='0000'?(r.season===3?2:r.room?3:0):0;
  let entries=variants.get(ts+':'+heights+':'+water);
  if(!entries){ts=0;entries=variants.get('0:'+heights+':'+water);}
  if(!entries){fallbacks++;entries=variants.get('0:0,0,0,0:'+water)||variants.get('0:0,0,0,0:0000');ts=0;}
  const c=entries[(x*7+y*13)%entries.length];
  arrays.cellConfiguration.push(configs[c].length,...configs[c]);
  arrays.cellConfigurationByName.push(names[c].length,...names[c]);
  arrays.cellsTileSet.push(ts);arrays.cellsHidden.push(0);
  arrays.cellsOrientation.push(old.cellsOrientation[c]);arrays.cellsMaterialSet.push(0);
  arrays.cellsCustomPathType.push(0);arrays.cellsVariationId.push(old.cellsVariationId[c]);
}
arrays.edgesPath=zero(N*V*2);arrays.edgesDestruction=zero(N*V*2);
for(const k of ['objectConfiguration','objectConfigurationByName','objectsTileSet','objectsPropType','objectsPlantType','objectsTreeType','objectsTreeSize','objectsRotation','objectsPitch'])arrays[k]=zero(O*O);
arrays.objectsVariationId=zero(O*O,255);
arrays.blendOpacity=zero(B*B,'0 255 0 128');arrays.blendColor=zero(B*B,'255 255 255 0');
arrays.blendTransitionAndPath=zero(B*B,'0 255 0 0');arrays.gridnavFlags=zero(N*N*16);
for(let gy=0;gy<N*4;gy++)for(let gx=0;gx<N*4;gx++){
 const x=(gx/4+.125-D.center.x)*D.tile,y=(gy/4+.125-D.center.y)*D.tile;
 if(Math.hypot(x,y)<D.sanctuary.radius&&D.sanctuary.blocked(x,y))arrays.gridnavFlags[gy*N*4+gx]=1;
}

arrays.grassOpacity=zero(B*B,180);arrays.fogOpacity=zero(B*B,255);
arrays.flowMap=zero(B*B,'10 20 0 0');arrays.fogFlowMap=zero(B*B,'10 20 0 0');arrays.blendHeight=zero(B*B,128);
const paint=require('./paint.cjs');
const paintStats=paint.apply(arrays,B);
let newGrid=grid.text.replace(/"(\w+)" "(int|uint8|bool|color)_array"\s*\[[^\]]*\]/g,(all,k,type)=>
  arrays[k]?`"${k}" "${type}_array" [\n${arrays[k].map(v=>'"'+v+'"').join(',\n')}\n]`:all);
newGrid=L.setValue(L.setValue(newGrid,'gridWidth',N),'gridHeight',N);
let terrain=native.slice(0,grid.start)+newGrid+native.slice(grid.end);
terrain=terrain.replace('"origin" "vector3" "-8192 -8192 128"',`"origin" "vector3" "${-N*128} ${-N*128} 128"`);

const ids=new Set(),entityList=[],placements=[],resourceSet=new Set();let nodeId=1000;
function uuid(){return crypto.randomUUID();}
function quote(v){return String(v).replace(/\\/g,'/').replace(/"/g,'');}
function entity(classname,name,pos,properties={},angle=0,scale=1){
  if(name&&ids.has(name))throw new Error('Duplicate marker '+name);if(name)ids.add(name);
  const id=nodeId++;const ep={classname,targetname:name,...properties};
  const t=`"CMapEntity" { "id" "elementid" "${uuid()}" "nodeID" "int" "${id}"
"children" "element_array" [] "entity_properties" "EditGameClassProps" {
"id" "elementid" "${uuid()}" ${Object.entries(ep).map(([k,v])=>`"${k}" "string" "${quote(v)}"`).join('\n')}
} "origin" "vector3" "${pos.join(' ')}" "angles" "qangle" "${Array.isArray(angle)?angle.join(' '):'0 '+angle+' 0'}"
"scales" "vector3" "${Array.isArray(scale)?scale.join(' '):[scale,scale,scale].join(' ')}" "force_hidden" "bool" "0" "editorOnly" "bool" "0" }`;
  entityList.push(t);placements.push({classname,name,pos,...properties});return t;
}
function marker(name,x,y,z=144){entity('info_target',name,D.world(x,y,z));}
const meshBuilder=require('./mesh.cjs');
function addMesh(quads,material,paint){resourceSet.add(material);entityList.push(meshBuilder.mesh(quads,material,nodeId++,paint));}
function prop(model,x,y,z=128,scale=1,angle=0,kind='prop_static',skin='0',color='255 255 255'){
  const showcase=kind==='ent_dota_tree_showcase';
  resourceSet.add(model);entity(showcase?'ent_dota_tree':kind,'',D.world(x,y,z),{model,solid:model.includes('fence')?'6':'0',rendercolor:color,skin,DefaultAnim:'idle',...(showcase?{always_use_showcase_tree:'1'}:{})},angle,scale);
}
const treeModels=[
 'models/props_tree/tree_oak_spring_01.vmdl',
 'models/props_tree/tree_oak_autumn_01.vmdl',
 'models/props_tree/tree_oak_01.vmdl',
 'models/props_tree/tree_pine_01_heavysnow.vmdl'];
let seed=60128;function random(){seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed/4294967296;}
// Skin is the zero-based material-group index (plum blossom is index 3,
// named "11" inside the model), not the material-group name itself.
function tree(x,y,season,scale=1){prop(treeModels[season%4],x,y,128+D.region(x,y).height*128,scale,random()*360,'ent_dota_tree',season===0?'3':season===1?'2':'0');}
const fence='models/props_generic/fence_str_wood_01a.vmdl',column='models/props_structures/good_column002.vmdl';
function flame(x,y,z=250){const effect='particles/props/roshan_torch_flame_a.vpcf';resourceSet.add(effect);entity('info_particle_system','',D.world(x,y,z),{effect_name:effect,start_active:'1'});}
function line(x1,y1,x2,y2,step,fn){const n=Math.ceil(Math.hypot(x2-x1,y2-y1)/step);for(let i=0;i<=n;i++)fn(x1+(x2-x1)*i/n,y1+(y2-y1)*i/n,i);}
function fenceLine(x1,y1,x2,y2){
  const distance=Math.hypot(x2-x1,y2-y1),n=Math.ceil(distance),scale=distance/n;
  const angle=Math.atan2(y2-y1,x2-x1)*180/Math.PI;
  for(let i=0;i<n;i++)prop(fence,x1+(x2-x1)*i/n,y1+(y2-y1)*i/n,128,scale,angle);
}
for(const r of D.rooms){
  const cx=r.x+r.w/2,cy=r.y+r.h/2;
  marker(`c6_${r.id}_entry`,cx-1,cy);marker(`c6_${r.id}_spawn`,cx+1,cy);
  marker(`c6_${r.id}_min`,r.x+.4,r.y+.4);marker(`c6_${r.id}_max`,r.x+r.w-.4,r.y+r.h-.4);
  for(const [x,y] of [[r.x+.5,r.y+.5],[r.x+r.w-.5,r.y+.5],[r.x+.5,r.y+r.h-.5],[r.x+r.w-.5,r.y+r.h-.5]]){
    prop(column,x,y,128,1);flame(x,y,440);
  }
  fenceLine(r.x+.5,r.y+.5,r.x+r.w-.5,r.y+.5);
  fenceLine(r.x+.5,r.y+r.h-.5,r.x+r.w-.5,r.y+r.h-.5);
  fenceLine(r.x+.5,r.y+.5,r.x+.5,r.y+r.h-.5);
  fenceLine(r.x+r.w-.5,r.y+.5,r.x+r.w-.5,r.y+r.h-.5);
  const treeCount=r.group==='small_southeast'?2:3;
  for(let i=0;i<treeCount;i++)tree(r.x+.65+i*(r.w-1.3)/(treeCount-1),r.y+r.h-.7,r.season,r.group==='small_southeast'?.8:1);
  // Preview-only models communicate scale without spawning unconfigured combat units.
  prop('models/heroes/axe/axe.vmdl',cx-1,cy,128,.85,0,'prop_dynamic');
  prop('models/creeps/neutral_creeps/n_creep_golem_a/neutral_creep_golem_a.vmdl',cx+1,cy,128,.8,180,'prop_dynamic');
}
const slots=D.players;
// A submerged native black surface removes visible gravel from the open water.
// The original Tile Grid water above it retains its animated river surface.
addMesh([[[16384,-16384,2],[16384,16384,2],[-16384,16384,2],[-16384,-16384,2]]],'materials/dev/black.vmat');
const sanctuaryStats=require('./build-sanctuary.cjs')({addMesh,prop,marker,random,flame});
// Rebind every existing gameplay marker to a valid floor, keeping its name.
const roomForChallenge=i=>D.rooms.filter(r=>r.group==='west_main')[i-1];
const lower=D.rooms.filter(r=>r.group==='small_southeast');
const markerPositions=new Map();
for(const b of L.blocks(source,'CMapEntity')){
  if(L.value(b.text,'classname')!=='info_target')continue;
  const name=L.value(b.text,'targetname');if(ids.has(name))continue;
  let r;
  const ch=name.match(/^challenge_(\d+)(?:_stage_(\d+))?/), reb=name.match(/^rebirth_0?(\d+)/);
  if(reb)r=lower[(+reb[1]-1)%10];
  else if(ch){const n=+ch[1];r=n<=10?roomForChallenge(n):D.rooms.filter(q=>['northwest','northeast','west_inner'].includes(q.group))[(+(ch[2]||1)-1)%11];}
  if(!r)continue;
  const x=r.x+r.w/2+(/entry/.test(name)?-1:1),y=r.y+r.h/2;
  marker(name,x,y);markerPositions.set(name,{room:r.id,x,y});
}
// Challenge configs also declare home/multi-spawn anchors absent in the old map.
const locations=fs.readFileSync(path.join(ROOT,'scripts/vscripts/config/generated/challenge_locations.lua'),'utf8');
for(const m of locations.matchAll(/"((?:challenge|rebirth)_[a-z0-9_]+(?:entry|home|spawn(?:_\d+)?))"/g)){
  const name=m[1];if(ids.has(name))continue;
  const prefix=name.match(/^(challenge|rebirth)_(\d+)/);if(!prefix)continue;
  const r=prefix[1]==='rebirth'?lower[(+prefix[2]-1)%10]:(roomForChallenge(+prefix[2])||lower[0]);
  const spawnIndex=+(name.match(/spawn_(\d+)$/)?.[1]||0);
  const offset=spawnIndex?[(spawnIndex%4-1.5)*.7,(Math.floor((spawnIndex-1)/4)-.5)*1.1]:[0,0];
  marker(name,r.x+r.w/2+offset[0],r.y+r.h/2+offset[1]);markerPositions.set(name,{room:r.id});
}
for(const [prefix,id] of [['endless_cycle_sanctum','far_east'],['shadow_realm_forecourt','southern']]){
  const r=D.rooms.find(r=>r.id===id);
  for(const suffix of ['entry','home','target'])marker(prefix+'_'+suffix,r.x+r.w/2+(suffix==='entry'?-1:1),r.y+r.h/2);
}
marker('c6_resource_tree',...D.resourceTree,D.sanctuary.landHeight+16);
// Border scenery, sparse enough that clearings stay open.
for(let i=0;i<2300;i++){
  const x=2+random()*124,y=2+random()*124,r=D.region(x,y);
  if(!r.land||r.room||r.central||r.star||r.boss)continue;
  if(r.plain&&random()>.55)continue;
  tree(x,y,r.season,1.45+random()*.8);
}
for(let i=0;i<48;i++){
  const a=random()*Math.PI*2,d=D.center.r+.5+random()*2;
  prop('models/props_debris/water_creep_camp/water_creep_camp_lily_pads.vmdl',60+d*Math.cos(a),85+d*Math.sin(a),8,.8,random()*360);
}
// Native low ground cover: clusters along tree belts and room margins.
// Keep combat centers and water approaches free of decorative obstructions.
const nature='models/props_nature/';
function groundDetail(x,y,season,index,scale=1){
  const choices=season===0?['petals_00','flowers001','grass_clump_00a']:
    season===1?['leaf_pile','grass_clump_00b','rock_ground001']:
    season===2?['fern001','flowers002','grass_clump_00a']:
    ['grass_clump_snow_00a','river_rocks002','grass_clump_snow_00a'];
  const name=choices[index%choices.length],rock=/rock/.test(name);
  prop(nature+name+'.vmdl',x,y,130,rock?scale*.65:scale,random()*360,'prop_static','0',rock?'130 143 139':'255 255 255');
}
for(const r of D.rooms){
 for(let i=0;i<(r.group==='small_southeast'?4:7);i++){
  const x=r.x+.85+random()*(r.w-1.7);
  const y=i%2?r.y+.8+random()*.35:r.y+r.h-1.15+random()*.35;
  groundDetail(x,y,r.season,i,(1.05+random()*.65)*(r.group==='small_southeast'?.7:1));
 }
}
for(let i=0;i<1800;i++){
 const x=2+random()*124,y=2+random()*124,r=D.region(x,y);
 if(!r.land||r.room||r.scenery||r.central)continue;
 const p=paint.sample(x,y);
 if(p.path>.3)continue;
 if(r.central){
  const [ox,oy]=D.centralOriginal(x,y),dx=ox-60,dy=oy-85,rad=Math.hypot(dx,dy);
  if(rad<17.3&&Math.abs(Math.abs(dx)-Math.abs(dy))>2.8)continue;
 }
 groundDetail(x,y,r.season,i,1.1+random()*.9);
}
prop('models/props_debris/creep_camp001a.vmdl',10,104,128,1.2,0);
prop('models/props_debris/creep_camp001a.vmdl',11,31,128,1.2,0);
marker('c6_red_spawn',62,31);
prop('models/props_gameplay/rune_doubledamage01.vmdl',62,31,128,1,0);
entity('water_lod_control','c6_water_lod',D.world(60,85),{cheapwaterstartdistance:'50000',cheapwaterenddistance:'60000'});

for(const variant of require('./optimize-scene.cjs').variants)resourceSet.add('models/props_nature/'+variant.name+'.vmdl');
const assetIndex=new Set(fs.readFileSync(path.join(OUT,'asset_index.txt'),'utf8').split(/\r?\n/));
const missing=[...resourceSet].filter(r=>!assetIndex.has(r+'_c'));
if(missing.length)throw new Error('Unverified original assets: '+missing.join(', '));
const light=L.blocks(source,'CMapEntity').find(b=>L.value(b.text,'classname')==='env_global_light');
// Preserve the installed template's directional/specular light and neutral
// ambient balance; bright blue ambient and extra intensity flattened the trees.
entityList.push(light.text);
const w=L.blocks(source,'CMapWorld')[0].text;
const childStart=w.indexOf('[',w.indexOf('"children" "element_array"'));
const childEnd=L.endOf(w,childStart,'[',']');
const baseGroup=w.slice(childStart,childEnd).match(/"element" "[a-f0-9-]+"/)[0];
const world=w.slice(0,childStart)+'[\n'+[baseGroup,terrain,...entityList].join(',\n')+'\n]'+w.slice(childEnd);
let root=source.replace(w,world);
// Keep Valve's root metadata and external basic-entities group. Reposition
// starts without changing their original property schema.
for(const b of L.blocks(root,'CMapEntity')){
  const cls=L.value(b.text,'classname');
  if(cls==='info_player_start_goodguys'||cls==='info_player_start_badguys')
    root=root.replace(b.text,L.setValue(b.text,'origin',D.world(...(cls.endsWith('goodguys')?[slots[0].x,slots[0].y,slots[0].z]:[D.center.x,D.center.y,144])).join(' ')));
}
const optimized=require('./optimize-scene.cjs').optimize(root);
root=optimized.text;
fs.writeFileSync(path.join(OUT,'scene-optimization.json'),JSON.stringify(optimized.stats,null,2));
fs.writeFileSync(path.join(OUT,'survival_c6.vmap'),root);
const manifest={map:'survival_c6',reference:'art/maps/c6/layout-reference.png',grid:{tiles:N,unitsPerTile:D.tile,bounds:[-N*128,N*128]},sanctuary:sanctuaryStats,sceneOptimization:optimized.stats,areaScale:D.areaScale,center:D.center,poolCorners:D.poolCorners,rooms:D.rooms,players:slots,counts:Object.fromEntries([...new Set(D.rooms.map(r=>r.group))].map(g=>[g,D.rooms.filter(r=>r.group===g).length])),resources:[...resourceSet].sort(),terrainFallbacks:fallbacks,entities:placements.length,markerPositions:Object.fromEntries(markerPositions)};
fs.writeFileSync(path.join(OUT,'layout.json'),JSON.stringify(manifest,null,2));
fs.writeFileSync(path.join(OUT,'paint.json'),JSON.stringify(paintStats,null,2));
fs.writeFileSync(path.join(OUT,'placements.json'),JSON.stringify(placements));
const [treeX,treeY]=D.world(...D.resourceTree);
const lua=`-- Generated by tools/map_c6/build.cjs from layout.cjs; map geometry only.\nreturn {\n    map_name = "survival_c6",\n    build_bounds = { min_x = ${(D.center.x-D.center.r-64)*256}, max_x = ${(D.center.x+D.center.r-64)*256}, min_y = ${(D.center.y-D.center.r-64)*256}, max_y = ${(D.center.y+D.center.r-64)*256} },\n    resource_tree = { x = ${treeX}, y = ${treeY}, z = ${D.sanctuary.landHeight+16} },\n}\n`;
fs.mkdirSync(path.join(ROOT,'scripts/vscripts/config/map_layouts'),{recursive:true});
fs.writeFileSync(path.join(ROOT,'scripts/vscripts/config/map_layouts/survival_c6.lua'),lua);
console.log(JSON.stringify({rooms:D.rooms.length,counts:manifest.counts,entities:placements.length,assets:resourceSet.size,terrainFallbacks:fallbacks,bytes:root.length}));
