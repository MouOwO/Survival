// Independent ten-rank review map plus ten origin-centered reusable prefabs.
// Geometry comes only from ascension_arenas; no formal gameplay map is edited.
const fs=require('fs'),path=require('path');
const root=path.resolve(__dirname,'..'),out=path.join(root,'output/ascension_arenas');
const sourceDir=path.join(out,'source'),ns='ascension_arenas';
const assets=JSON.parse(fs.readFileSync(path.join(out,'asset_manifest.json'),'utf8').replace(/^\uFEFF/,''));
if(!Array.isArray(assets)||assets.length!==10)throw Error('Expected exactly ten arena assets.');
const source=fs.readFileSync(path.join(__dirname,'build_zombie_abyss_map.cjs'),'utf8');
const prefix=source.slice(0,source.indexOf("water('central_sea'"))
 .replace('../output/zombie_island_v1','../output/ascension_arenas').replace('zombie-abyss-v1-','ascension-arenas-review-');
const {children,entity,prism}=new Function('require','__dirname',prefix+'\nreturn {children,entity,prism};')(require,__dirname);
const zbase=128,supportInset=.75,reviewHalfExtent=2048;
const supportMaterial=`materials/${ns}/floor_support.vmat`;
const materialDir=path.join(sourceDir,'materials',ns);
fs.mkdirSync(materialDir,{recursive:true});
const supportSource=fs.readFileSync(path.join(materialDir,'mortar.vmat'),'utf8');
if(/"Attributes"/.test(supportSource))throw Error('mortar.vmat unexpectedly already contains Attributes.');
fs.writeFileSync(path.join(materialDir,'floor_support.vmat'),supportSource.replace(/}\s*$/,
 '"Attributes" { "dota.nav.walkable" "1" "mapbuilder.nodraw" "1" }\n}\n'));
function box(x,y,w,d,top,bottom,mat){
 prism([[x-w/2,y-d/2],[x+w/2,y-d/2],[x+w/2,y+d/2],[x-w/2,y+d/2]],top,bottom,mat,mat,'255 255 255 255');
}
const stages=assets.map(a=>({...a,...(a.meta||{})})).sort((a,b)=>a.rank-b.rank);
const pair=value=>Array.isArray(value)&&value.length===2&&value.every(Number.isFinite);
for(let i=0;i<stages.length;i++){
 const s=stages[i],rank=i+1;
 if(s.rank!==rank||s.name!==`arena_${String(rank).padStart(2,'0')}`||s.layers!==rank||s.deck_z!==rank*14)
  throw Error('Arena manifest rank/layer/deck contract mismatch: '+JSON.stringify(s));
 if(!pair(s.footprint)||!pair(s.deck_size)||!pair(s.clear_combat_size)||!pair(s.review_xy)||
  s.footprint.some((n,axis)=>n<=0||s.deck_size[axis]<=0||s.deck_size[axis]>n||
   s.clear_combat_size[axis]<=0||s.clear_combat_size[axis]>s.deck_size[axis]))
  throw Error('Missing footprint or combat dimensions: '+s.name);
 if(JSON.stringify(s.footprint)!==JSON.stringify(stages[0].footprint))
  throw Error('All arena ranks must retain the same footprint: '+s.name);
}
// Review spacing belongs to the stage specification. Validate the entire
// footprint, not just the smaller top deck, before generating any placements.
const reviewFootprints=stages.map(s=>({name:s.name,
 min:s.review_xy.map((n,axis)=>n-s.footprint[axis]/2),
 max:s.review_xy.map((n,axis)=>n+s.footprint[axis]/2)}));
let minClearance=Infinity;
for(let i=0;i<reviewFootprints.length;i++){
 const a=reviewFootprints[i];
 if(a.min.some(n=>n < -reviewHalfExtent)||a.max.some(n=>n > reviewHalfExtent))
  throw Error('Arena footprint exceeds review map bounds: '+a.name);
 for(let j=0;j<i;j++){
  const b=reviewFootprints[j],gaps=[0,1].map(axis=>Math.max(a.min[axis]-b.max[axis],b.min[axis]-a.max[axis],0));
  if([0,1].every(axis=>a.min[axis]<b.max[axis]&&b.min[axis]<a.max[axis]))
   throw Error('Review footprints overlap: '+a.name+' / '+b.name);
  minClearance=Math.min(minClearance,Math.hypot(...gaps));
 }
}
const occupiedBounds=[[0,1].map(axis=>Math.min(...reviewFootprints.map(p=>p.min[axis]))),
 [0,1].map(axis=>Math.max(...reviewFootprints.map(p=>p.max[axis])))];
const placements=[],markers=[],prefabs=[];
function addArena(stage,x,y,z,review){
 const rank=stage.rank,name=stage.name,key=String(rank).padStart(2,'0');
 const supportTop=z+stage.deck_z-supportInset;
 // Each support lives immediately beneath that arena's deck. A single shared
 // world floor would either show through low stages or leave high stages void.
 box(x,y,stage.deck_size[0],stage.deck_size[1],supportTop,supportTop-4,supportMaterial);
 const collisionCount=stage.collision_count??stage.collision_hulls;
 if(!(collisionCount>0))throw Error('Arena needs authored collision: '+name);
 entity('prop_static',`ascension_arena_${key}_model`,[x,y,z],
  {model:`models/${ns}/${name}.vmdl`,solid:'6',rendercolor:'255 255 255',disableshadows:'0'},'0 0 0',1);
 const marker={name:`ascension_arena_${key}_center`,origin:[x,y,z+stage.deck_z+24],rank};
 entity('info_target',marker.name,marker.origin);
 const placement={name,rank,label:stage.label,layers:stage.layers,origin:[x,y,z],yaw:0,scale:1,
  model:`models/${ns}/${name}.vmdl`,footprint:stage.footprint,deck_z:stage.deck_z,deck_size:stage.deck_size,
  clear_combat_size:stage.clear_combat_size,world_deck_z:z+stage.deck_z,
  support_top:supportTop,support_bottom:supportTop-4,support_size:stage.deck_size,
  float_preview_offset:review?stage.float_preview_offset:0,collision_count:collisionCount};
 return {placement,marker};
}
for(let i=0;i<stages.length;i++){
 const stage=stages[i],[x,y]=stage.review_xy;
 const expectedOffset=stage.rank<8?0:(stage.rank-7)*10;
 if(stage.float_preview_offset!==expectedOffset)throw Error('Unexpected float preview offset: '+stage.name);
 const result=addArena(stage,x,y,zbase+expectedOffset,true);
 placements.push(result.placement);markers.push(result.marker);
}
const overviewChildren=children.slice();
for(const stage of stages){
 children.length=0;
 const result=addArena(stage,0,0,0,false);
 prefabs.push({rank:stage.rank,name:`ascension_arena_${String(stage.rank).padStart(2,'0')}`,
  path:`prefabs/ascension_arena_${String(stage.rank).padStart(2,'0')}`,
  origin:[0,0,0],preview_offset_baked:false,placement:result.placement,marker:result.marker,
  children:children.slice()});
}
children.length=0;children.push(...overviewChildren);
// Own-material studio ground is review-only and cannot appear above any deck.
box(0,0,4096,4096,zbase-1,zbase-64,`materials/${ns}/earth_edge.vmat`);
entity('world_bounds','ascension_review_bounds',[0,0,0],{min:'-2048 -2048 0',max:'2048 2048 0'});
const first=placements[0],last=placements[9];
entity('info_player_start_goodguys','ascension_review_start',[first.origin[0],first.origin[1],first.world_deck_z+24]);
entity('info_player_start','ascension_editor_start',[first.origin[0],first.origin[1],first.world_deck_z+24]);
entity('info_player_start_badguys','ascension_review_enemy_start',[last.origin[0],last.origin[1],last.world_deck_z+24]);
entity('ent_dota_game_events','ascension_review_events',[0,0,0]);
entity('env_global_light','ascension_review_daylight',[0,0,2400],
 {color:'255 243 218 255',lightscale:'1.8',ambientcolor1:'198 208 215 255',ambientscale1:'1.15',
 ambientcolor2:'171 184 186 255',ambientscale2:'.8',ambientcolor3:'142 145 129 255',groundscale:'.65',
 enableshadows:'1',StartDisabled:'0'},'55 315 0');
entity('env_tonemap_controller','ascension_review_tonemap',[0,0,0],
 {UseCustomAutoExposureMin:'1',UseCustomAutoExposureMax:'1',AutoExposureMin:'.9',AutoExposureMax:'1.1'});
let template=fs.readFileSync(path.join(root,'output/zombie_island_v1/source_template.vmap'),'utf8');
template=template.slice(template.indexOf('"CMapRootElement"'));
function close(s,start,op,cl){let d=0,q=false;for(let i=start;i<s.length;i++){if(s[i]==='"'&&s[i-1]!=='\\')q=!q;if(!q){if(s[i]===op)d++;if(s[i]===cl&&--d===0)return i;}}throw Error('Unbalanced VMAP');}
const wa=template.indexOf('"world" "CMapWorld"'),wb=template.indexOf('{',wa),we=close(template,wb,'{','}');
const world=template.slice(wa,we+1),cb=world.indexOf('[',world.indexOf('"children" "element_array"')),ce=close(world,cb,'[',']');
let grid=world.slice(cb+1,ce).trim();
grid=grid.replace('"-8192 -8192 128"','"-2048 -2048 128"')
 .replace('"gridWidth" "int" "64"','"gridWidth" "int" "16"').replace('"gridHeight" "int" "64"','"gridHeight" "int" "16"');
const resized={4096:256,4225:289,8320:544,66049:4225,65536:4096,263169:16641};
let openCells=0;const cellsByRank=Object.fromEntries(stages.map(s=>[s.rank,0]));
function walkableArena(x,y){return placements.find(p=>Math.abs(x-p.origin[0])<p.clear_combat_size[0]/2&&Math.abs(y-p.origin[1])<p.clear_combat_size[1]/2);}
grid=grid.replace(/^(\t{6})"([^"]+)" "(\w+)_array"\s*\[([^\]]*)\]/gm,(all,indent,k,type,body)=>{
 if(type==='element')return all;
 const old=[...body.matchAll(/"([^"]*)"/g)].map(m=>m[1]);
 if(/^(cell|object)Configuration/.test(k))return `${indent}"${k}" "${type}_array" []`;
 const count=resized[old.length];if(!count)return all;
 let fill=old[0]||'0';
 if(k==='cellsHidden')fill='1';
 else if(k==='verticesHeight'||k==='verticesWater'||k==='edgesPath'||k==='edgesDestruction'||k.startsWith('objects'))fill=k==='objectsVariationId'?'255':'0';
 else if(k==='blendOpacity')fill='0 255 0 128';
 else if(k==='blendColor')fill='255 255 255 0';
 else if(k==='grassOpacity'||k==='fogOpacity')fill='0';
 else if(k==='flowMap'||k==='fogFlowMap')fill='128 128 0 0';
 const values=Array(count).fill(fill);
 if(k==='gridnavFlags')for(let y=0;y<64;y++)for(let x=0;x<64;x++){
  const arena=walkableArena(-2048+x*64+32,-2048+y*64+32);values[y*64+x]=arena?'0':'1';
  if(arena){openCells++;cellsByRank[arena.rank]++;}
 }
 return `${indent}"${k}" "${type}_array" [${values.map(v=>'"'+v+'"').join(',')} ]`;
});
if(!openCells||Object.values(cellsByRank).some(n=>!n))throw Error('Review grid has an arena with no open combat cells.');
function save(name,items){
 const w=world.slice(0,cb+1)+items.join(',\n')+world.slice(ce);
 const t=template.slice(0,wa)+w+template.slice(we+1),file=path.join(sourceDir,'maps',name+'.vmap');
 fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file,'<!-- dmx encoding keyvalues2 4 format vmap 40 -->\n'+t);
}
save('ascension_arenas_review',[grid,...children]);
for(const prefab of prefabs)save(prefab.path,prefab.children);
const layout={namespace:ns,review:'ascension_arenas_review',base_z:zbase,footprint:stages[0].footprint,
 layer_height:14,height_status:'first modeling pass; artistic tuning remains reviewable',
 columns:new Set(stages.map(s=>s.review_xy[0])).size,rows:new Set(stages.map(s=>s.review_xy[1])).size,
 review_bounds:[[-reviewHalfExtent,-reviewHalfExtent],[reviewHalfExtent,reviewHalfExtent]],
 occupied_bounds:occupiedBounds,min_footprint_clearance:minClearance,
 placements,markers,prefabs:prefabs.map(({children,...p})=>p),
 walkable_support: {material:supportMaterial,recess:supportInset,thickness:4,rendered:false},
 review_ground:{top:zbase-1,material:`materials/${ns}/earth_edge.vmat`,exported_to_prefab:false},
 open_grid_cells:openCells,open_cells_by_rank:cellsByRank,main_map_modified:false,runtime_verified:false};
fs.writeFileSync(path.join(out,'layout.json'),JSON.stringify(layout,null,2));
fs.writeFileSync(path.join(out,'map_manifest.json'),JSON.stringify({review:layout.review,prefabs:layout.prefabs.map(p=>p.path),
 instances:placements.length,customAssets:assets.length,markers:markers.map(m=>m.name),baseZ:zbase,
 footprint:layout.footprint,occupiedBounds,reviewBounds:layout.review_bounds,minFootprintClearance:minClearance,
 openGridCells:openCells,emissiveEntities:0,mainMapModified:false,runtimeVerified:false},null,2));
console.log(JSON.stringify({map:layout.review,arenas:placements.length,prefabs:prefabs.length,openGridCells:openCells,cellsByRank},null,2));
