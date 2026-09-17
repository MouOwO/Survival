// Editable standalone review map and a prop-by-prop room prefab.
const fs=require('fs'),path=require('path');
const root=path.resolve(__dirname,'..'),out=path.join(root,'output/molten_core_room');
const layout=JSON.parse(fs.readFileSync(path.join(out,'room_layout.json')));
const assets=JSON.parse(fs.readFileSync(path.join(out,'asset_manifest.json')));
const source=fs.readFileSync(path.join(__dirname,'build_zombie_abyss_map.cjs'),'utf8');
const prefix=source.slice(0,source.indexOf("water('central_sea'"))
 .replace('../output/zombie_island_v1','../output/molten_core_room').replace('zombie-abyss-v1-','molten-core-room-');
const {children,entity,prism}=new Function('require','__dirname',prefix+'\nreturn {children,entity,prism};')(require,__dirname);
const zbase=128;
// Dota's navigation compiler requires a walkable surface attribute on custom world floors.
const supportMaterial='materials/molten_core_room/floor_support.vmat';
const materialDir=path.join(out,'source/materials/molten_core_room');
fs.writeFileSync(path.join(materialDir,'floor_support.vmat'),fs.readFileSync(path.join(materialDir,'mortar.vmat'),'utf8').replace(/}\s*$/,'"Attributes" { "dota.nav.walkable" "1" "mapbuilder.nodraw" "1" }\n}\n'));
function box(x,y,w,d,top,bottom,mat){prism([[x-w/2,y-d/2],[x+w/2,y-d/2],[x+w/2,y+d/2],[x-w/2,y+d/2]],top,bottom,mat,mat,'255 255 255 255');}
// The chipped slabs dip 0.4 below Z=0; keep the support below their tops.
box(0,0,2048,2304,zbase-.75,zbase-64,supportMaterial);
// Paved rear niche shares the same flat walking surface.
const semicircle=[[-256,1152],[256,1152],...Array.from({length:15},(_,i)=>[256*Math.cos((i+1)*Math.PI/16),1152+256*Math.sin((i+1)*Math.PI/16)])];
prism(semicircle,zbase-.75,zbase-64,supportMaterial,supportMaterial,'255 255 255 255');
for(let i=0;i<layout.placements.length;i++){
 const p=layout.placements[i],a=assets.find(a=>a.name===p.name);
 entity('prop_static','molten_room_'+String(i).padStart(4,'0')+'_'+path.basename(p.name,'.vmdl'),
  [p.origin[0],p.origin[1],zbase+p.origin[2]],
  {model:p.native?p.name:'models/molten_core_room/'+p.name+'.vmdl',solid:a?.collision_hulls?'6':'0',rendercolor:'255 255 255',disableshadows:'0'},
  `${p.pitch||0} ${p.yaw} 0`,p.scale);
}
for(const m of layout.markers)entity('info_target',m.name,[m.origin[0],m.origin[1],zbase+m.origin[2]]);
const prefabChildren=children.slice();
box(0,0,4096,4096,zbase-29,zbase-120,'materials/molten_core_room/earth.vmat');
entity('world_bounds','molten_room_review_bounds',[0,0,0],{min:'-2048 -2048 0',max:'2048 2048 0'});
entity('info_player_start_goodguys','molten_room_review_start',[0,700,152]);
entity('info_player_start','molten_room_editor_start',[0,700,152]);
entity('info_player_start_badguys','molten_room_enemy_start',[0,-140,152]);
entity('ent_dota_game_events','molten_room_events',[0,0,0]);
entity('env_global_light','molten_room_daylight',[0,0,2400],{color:'255 236 215 255',lightscale:'1.7',ambientcolor1:'198 208 215 255',ambientscale1:'1.15',ambientcolor2:'171 184 186 255',ambientscale2:'.8',ambientcolor3:'142 145 129 255',groundscale:'.65',enableshadows:'1',StartDisabled:'0'},'55 315 0');
entity('env_tonemap_controller','molten_room_tonemap',[0,0,0],{UseCustomAutoExposureMin:'1',UseCustomAutoExposureMax:'1',AutoExposureMin:'.9',AutoExposureMax:'1.1'});
let template=fs.readFileSync(path.join(root,'output/zombie_island_v1/source_template.vmap'),'utf8');
template=template.slice(template.indexOf('"CMapRootElement"'));
function close(s,start,op,cl){let d=0,q=false;for(let i=start;i<s.length;i++){if(s[i]==='"'&&s[i-1]!=='\\')q=!q;if(!q){if(s[i]===op)d++;if(s[i]===cl&&--d===0)return i;}}throw Error('Unbalanced VMAP');}
const wa=template.indexOf('"world" "CMapWorld"'),wb=template.indexOf('{',wa),we=close(template,wb,'{','}');
const world=template.slice(wa,we+1),cb=world.indexOf('[',world.indexOf('"children" "element_array"')),ce=close(world,cb,'[',']');
let grid=world.slice(cb+1,ce).trim();
grid=grid.replace('"-8192 -8192 128"','"-2048 -2048 128"').replace('"gridWidth" "int" "64"','"gridWidth" "int" "16"').replace('"gridHeight" "int" "64"','"gridHeight" "int" "16"');
const resized={4096:256,4225:289,8320:544,66049:4225,65536:4096,263169:16641};
let openCells=0;
function walkable(x,y){return (Math.abs(x)<968&&y>-1096&&y<1130)||(y>=1090&&y<1350&&Math.hypot(x,y-1152)<200);}
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
 if(k==='gridnavFlags')for(let y=0;y<64;y++)for(let x=0;x<64;x++){const can=walkable(-2048+x*64+32,-2048+y*64+32);values[y*64+x]=can?'0':'1';if(can)openCells++;}
 return `${indent}"${k}" "${type}_array" [${values.map(v=>'"'+v+'"').join(',')} ]`;
});
function save(name,items){const w=world.slice(0,cb+1)+items.join(',\n')+world.slice(ce);const t=template.slice(0,wa)+w+template.slice(we+1);fs.mkdirSync(path.join(out,'source/maps/prefabs'),{recursive:true});fs.writeFileSync(path.join(out,'source/maps',name+'.vmap'),'<!-- dmx encoding keyvalues2 4 format vmap 40 -->\n'+t);}
save('molten_core_room_review',[grid,...children]);
save('prefabs/molten_core_room',prefabChildren);
fs.writeFileSync(path.join(out,'map_manifest.json'),JSON.stringify({review:'molten_core_room_review',prefab:'prefabs/molten_core_room',instances:layout.placements.length,customAssets:assets.length,nativeAssets:layout.native_models,markers:layout.markers.map(m=>m.name),floorZ:zbase,openGridCells:openCells,emissiveEntities:0,mainMapModified:false},null,2));
console.log('MOLTEN_ROOM_MAP',layout.placements.length,'instances',openCells,'walkable cells');
